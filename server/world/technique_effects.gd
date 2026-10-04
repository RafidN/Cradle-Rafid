class_name TechniqueEffects
extends RefCounted
## Server-side results of released techniques: Lancer projectiles, Controller bursts and
## Builder traps. Enforcers need nothing here; they live in the fighter simulation.
##
## Lag compensation: a projectile remembers how far behind the server its caster's view
## was when it was cast, and tests targets rewound by that much for its whole flight,
## so it hits what the caster was aiming at. Bursts rewind like melee. Traps test
## current positions: the victim is the one moving into them.

const PROJECTILE_RADIUS := 0.25
## Projectiles move up to 0.8 m per tick; sub-steps keep them from skipping past targets.
const PROJECTILE_SUBSTEPS := 4
const PROJECTILE_HEIGHT := 1.3
const TRAP_PLACE_DISTANCE := 1.6
const MAX_TRAPS_PER_OWNER := 2
const WORLD_MASK := 1


class Projectile:
	var id := 0
	var owner_id := 0
	var technique: TechniqueData
	var position := Vector3.ZERO
	var velocity := Vector3.ZERO
	var travelled := 0.0
	var lag_ticks := 0.0


class Trap:
	var id := 0
	var owner_id := 0
	var technique: TechniqueData
	var position := Vector3.ZERO
	var age := 0


## Called as land_hit(attacker_or_null, target, spec, origin, technique_id).
var land_hit: Callable
## Called as burst(caster_id, technique_id, position).
var burst: Callable
var hit_history: HitHistory
var max_rewind_ticks := 12

var _projectiles: Array[Projectile] = []
var _traps: Array[Trap] = []
var _next_id := 1


## Spawns whatever a just-released technique creates. view_tick is the caster's.
func release(caster: PlayerBody, technique_id: int, tick: int, view_tick: float, bodies: Array) -> void:
	var technique := Techniques.get_technique(technique_id)
	match technique.kind:
		TechniqueData.Kind.LANCER:
			var projectile := Projectile.new()
			projectile.id = _take_id()
			projectile.owner_id = caster.entity_id
			projectile.technique = technique
			projectile.position = caster.global_position + Vector3.UP * PROJECTILE_HEIGHT + caster.forward() * 0.6
			projectile.velocity = caster.forward() * technique.speed
			projectile.lag_ticks = clampf(tick - view_tick, 0.0, max_rewind_ticks)
			_projectiles.append(projectile)
		TechniqueData.Kind.CONTROLLER:
			var rewind_to := clampf(view_tick, tick - max_rewind_ticks, tick - 1)
			burst.call(caster.entity_id, technique_id, caster.global_position)
			for target: PlayerBody in bodies:
				if target == caster or target.is_dead() or not Combat.can_harm(caster, target):
					continue
				var seen_at := _rewound(target, rewind_to)
				var offset := seen_at - caster.global_position
				if Vector2(offset.x, offset.z).length() > technique.radius + PlayerBody.HURT_RADIUS or absf(offset.y) > 2.0:
					continue
				if not _dodged(target, rewind_to):
					land_hit.call(caster, target, Combat.technique_spec(caster, technique), caster.global_position, technique_id)
		TechniqueData.Kind.BUILDER:
			var trap := Trap.new()
			trap.id = _take_id()
			trap.owner_id = caster.entity_id
			trap.technique = technique
			trap.position = caster.global_position + caster.forward() * TRAP_PLACE_DISTANCE
			_traps.append(trap)
			var owned := _traps.filter(func(t: Trap): return t.owner_id == caster.entity_id)
			if owned.size() > MAX_TRAPS_PER_OWNER:
				_traps.erase(owned[0])


func update(tick: int, bodies: Array, space: PhysicsDirectSpaceState3D) -> void:
	for projectile in _projectiles.duplicate():
		if _advance_projectile(projectile, tick, bodies, space):
			_projectiles.erase(projectile)
	for trap in _traps.duplicate():
		trap.age += 1
		if trap.age >= trap.technique.lifetime_ticks or _check_trap(trap, bodies):
			_traps.erase(trap)


## Drops everything a fighter owns (e.g. when its player leaves).
func remove_owned_by(entity_id: int) -> void:
	_traps = _traps.filter(func(t: Trap): return t.owner_id != entity_id)


## Snapshot entries, in Protocol's effect format.
func snapshot_entries() -> Array:
	var entries := []
	for projectile in _projectiles:
		entries.append({"id": projectile.id, "kind": Protocol.Effect.PROJECTILE, "owner": projectile.owner_id,
			"position": projectile.position, "velocity": projectile.velocity, "armed": true})
	for trap in _traps:
		entries.append({"id": trap.id, "kind": Protocol.Effect.TRAP, "owner": trap.owner_id,
			"position": trap.position, "velocity": Vector3.ZERO, "armed": trap.age >= trap.technique.arm_ticks})
	return entries


## Returns true when the projectile is spent (hit something or reached its range).
func _advance_projectile(projectile: Projectile, tick: int, bodies: Array, space: PhysicsDirectSpaceState3D) -> bool:
	var rewind_to := clampf(tick - projectile.lag_ticks, tick - max_rewind_ticks, tick - 1)
	var step := projectile.velocity / Protocol.TICK_RATE / PROJECTILE_SUBSTEPS
	for i in PROJECTILE_SUBSTEPS:
		var next := projectile.position + step
		var query := PhysicsRayQueryParameters3D.create(projectile.position, next, WORLD_MASK)
		if not space.intersect_ray(query).is_empty():
			return true
		projectile.position = next
		projectile.travelled += step.length()
		var caster := _find(bodies, projectile.owner_id)
		for target: PlayerBody in bodies:
			if target.entity_id == projectile.owner_id or target.is_dead() or not Combat.can_harm(caster, target):
				continue
			if not Combat.sphere_overlaps(projectile.position, PROJECTILE_RADIUS, _rewound(target, rewind_to)):
				continue
			if _dodged(target, rewind_to):
				continue
			var origin := projectile.position - projectile.velocity.normalized()
			land_hit.call(caster, target, Combat.technique_spec(caster, projectile.technique), origin,
				Techniques.ALL.find(projectile.technique))
			return true
		if projectile.travelled >= projectile.technique.max_range:
			return true
	return false


## Returns true if the trap detonated.
func _check_trap(trap: Trap, bodies: Array) -> bool:
	if trap.age < trap.technique.arm_ticks:
		return false
	var victims := []
	var caster := _find(bodies, trap.owner_id)
	for target: PlayerBody in bodies:
		if target.entity_id == trap.owner_id or target.is_dead() or target.is_invulnerable() \
				or not Combat.can_harm(caster, target):
			continue
		var offset := target.global_position - trap.position
		if Vector2(offset.x, offset.z).length() <= trap.technique.radius + PlayerBody.HURT_RADIUS and absf(offset.y) < 1.5:
			victims.append(target)
	if victims.is_empty():
		return false
	var technique_id := Techniques.ALL.find(trap.technique)
	burst.call(trap.owner_id, technique_id, trap.position)
	for target: PlayerBody in victims:
		land_hit.call(caster, target, Combat.technique_spec(caster, trap.technique), trap.position, technique_id)
	return true


func _rewound(target: PlayerBody, tick: float) -> Vector3:
	var past := hit_history.sample(target.entity_id, tick)
	return past.position if not past.is_empty() else target.global_position


## A dodge counts if it was active where the attacker saw it or on the server now.
func _dodged(target: PlayerBody, tick: float) -> bool:
	return target.is_invulnerable() or hit_history.sample(target.entity_id, tick).get("invulnerable", false)


func _find(bodies: Array, entity_id: int) -> PlayerBody:
	for body: PlayerBody in bodies:
		if body.entity_id == entity_id:
			return body
	return null


func _take_id() -> int:
	_next_id += 1
	return _next_id
