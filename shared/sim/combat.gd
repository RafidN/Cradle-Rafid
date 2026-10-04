class_name Combat
extends RefCounted
## Hit geometry and hit resolution. Resolution runs only on the server; clients see the
## outcome through snapshots and HIT events.

enum Result { HIT, BLOCKED, PARRIED, GUARD_BROKEN }

const BLOCK_DAMAGE_MULT := 0.2
const BLOCK_PUSHBACK_MULT := 0.5
const GUARD_BREAK_DAMAGE_MULT := 0.5
const GUARD_BREAK_TICKS := 24
const PARRY_STAGGER_TICKS := 30
## An active Enforcer technique strengthens melee attacks.
const ENFORCER_DAMAGE_MULT := 1.3
## Exhausted practitioners take extra damage from everything.
const EXHAUSTED_DAMAGE_TAKEN_MULT := 1.25


## True if the attack's hitbox, placed on the attacker, touches a hurtbox at target_position.
static func hitbox_overlaps(attacker_position: Vector3, attacker_facing: float,
		attack: AttackData, target_position: Vector3) -> bool:
	var basis := Basis(Vector3.UP, attacker_facing)
	var hitbox_center := attacker_position + basis * attack.hitbox_offset
	var hurtbox_center := target_position + Vector3.UP * (PlayerBody.HURT_HEIGHT * 0.5)
	var local := basis.inverse() * (hurtbox_center - hitbox_center)
	var reach := attack.hitbox_size * 0.5 + Vector3(
		PlayerBody.HURT_RADIUS, PlayerBody.HURT_HEIGHT * 0.5, PlayerBody.HURT_RADIUS)
	return absf(local.x) <= reach.x and absf(local.y) <= reach.y and absf(local.z) <= reach.z


## True if a sphere at point overlaps the hurtbox of a fighter standing at target_position.
static func sphere_overlaps(point: Vector3, radius: float, target_position: Vector3) -> bool:
	var horizontal := Vector2(point.x - target_position.x, point.z - target_position.z)
	return (horizontal.length() <= radius + PlayerBody.HURT_RADIUS
		and point.y >= target_position.y - radius
		and point.y <= target_position.y + PlayerBody.HURT_HEIGHT + radius)


## Whether attacker may hurt target. A null attacker (its owner left) can hurt anyone.
static func can_harm(attacker: PlayerBody, target: PlayerBody) -> bool:
	return attacker == null or attacker.team == 0 or attacker.team != target.team


static func melee_spec(attacker: PlayerBody, attack: AttackData) -> HitSpec:
	var mult := attacker.damage_mult * (ENFORCER_DAMAGE_MULT if attacker.enforcer_active else 1.0)
	return HitSpec.from_attack(attack, mult)


static func technique_spec(caster: PlayerBody, technique: TechniqueData) -> HitSpec:
	return HitSpec.from_technique(technique, caster.damage_mult if caster else 1.0)


## Applies a landed hit to the target. origin is where the hit came from (it decides
## knockback direction and whether a block faces it). attacker may be null (e.g. its
## owner disconnected); it's only needed to stagger it on a parry.
## Returns [Result, damage dealt].
static func resolve(attacker: PlayerBody, target: PlayerBody, spec: HitSpec, origin: Vector3) -> Array:
	var away := target.global_position - origin
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = attacker.forward() if attacker else Vector3.FORWARD
	away = away.normalized()
	var frontal := target.forward().dot(-away) > 0.0
	var knockback := spec.knockback * target.knockback_taken_mult
	var damage_mult := EXHAUSTED_DAMAGE_TAKEN_MULT if target.is_exhausted() else 1.0

	if spec.blockable and target.action == PlayerBody.Action.BLOCK and frontal:
		if spec.parryable and target.is_parrying() and attacker:
			attacker.apply_stagger(PARRY_STAGGER_TICKS, -away * spec.knockback * 0.5)
			return [Result.PARRIED, 0]
		if spec.guard_break:
			var damage := ceili(spec.damage * GUARD_BREAK_DAMAGE_MULT * damage_mult)
			target.apply_damage(damage)
			target.apply_stagger(GUARD_BREAK_TICKS, away * knockback)
			return [Result.GUARD_BROKEN, damage]
		var chip := ceili(spec.damage * BLOCK_DAMAGE_MULT * damage_mult)
		target.apply_damage(chip)
		if not target.is_dead():
			var push := away * knockback * BLOCK_PUSHBACK_MULT
			target.velocity.x = push.x
			target.velocity.z = push.z
		return [Result.BLOCKED, chip]

	var dealt := roundi(spec.damage * damage_mult)
	target.apply_damage(dealt)
	target.apply_hitstun(spec.hitstun, away * knockback)
	return [Result.HIT, dealt]
