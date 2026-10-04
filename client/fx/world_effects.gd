class_name WorldEffects
extends Node3D
## Draws technique effects. Server-owned effects (projectiles, traps) come from snapshots
## and are drawn at the same delayed render time as remote fighters. The local player's
## own projectiles and bursts are predicted: spawned the moment the technique releases.

const FLAME := Color(1.0, 0.5, 0.15)
const PREDICTED_HIT_RADIUS := 0.7
const WORLD_MASK := 1
## Stationary effects are only resent every few ticks; one missing this long is gone.
const STATIONARY_EXPIRY_TICKS := 20

## Called with no arguments; returns positions predicted projectiles can stop on.
var target_positions: Callable

var _server_effects := {}  # id -> {node, kind, tick, position, velocity, last_seen}
var _predicted: Array[Dictionary] = []  # {node, velocity, remaining}
var _newest_tick := 0


func sync(snapshot_tick: int, effects: Array, local_entity_id: int) -> void:
	_newest_tick = snapshot_tick
	for effect: Dictionary in effects:
		if effect.kind == Protocol.Effect.PROJECTILE and effect.owner == local_entity_id:
			continue  # Already shown as a predicted projectile.
		var entry: Dictionary = _server_effects.get(effect.id, {})
		if entry.is_empty():
			var node: Node3D
			match effect.kind:
				Protocol.Effect.PROJECTILE:
					node = _make_projectile()
				Protocol.Effect.TRAP:
					node = _make_trap()
				_:
					node = _make_remnant(Advancement.ASPECT_COLORS[clampi(effect.data, 0, 2)])
			add_child(node)
			entry = {"node": node, "kind": effect.kind}
			_server_effects[effect.id] = entry
		entry.tick = snapshot_tick
		entry.position = effect.position
		entry.velocity = effect.velocity
		entry.armed = effect.armed
		entry.owner = effect.owner
		entry.last_seen = snapshot_tick


func render(render_tick: float) -> void:
	for id in _server_effects.keys():
		var entry: Dictionary = _server_effects[id]
		# Gone from snapshots. Projectiles (sent every tick) are drawn until render time
		# catches up with their last update; stationary effects expire after a while.
		var gone: bool = render_tick > entry.last_seen + 1 if entry.kind == Protocol.Effect.PROJECTILE \
			else _newest_tick - entry.last_seen > STATIONARY_EXPIRY_TICKS
		if gone:
			entry.node.queue_free()
			_server_effects.erase(id)
			continue
		var elapsed: float = (render_tick - entry.tick) / Protocol.TICK_RATE
		entry.node.global_position = entry.position + entry.velocity * elapsed
		if entry.kind == Protocol.Effect.TRAP:
			var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.008) if entry.armed else 0.25
			entry.node.get_child(0).transparency = 1.0 - pulse
		elif entry.kind == Protocol.Effect.REMNANT:
			var t: float = Time.get_ticks_msec() * 0.001 + id * 0.37
			entry.node.position.y += sin(t * 2.0) * 0.15
			entry.node.rotation.y = t * 0.8


## The nearest remnant within max_distance of a point that entity_id may claim, as
## {"id", "position"}, or {}.
func nearest_remnant(point: Vector3, max_distance: float, entity_id: int) -> Dictionary:
	var best := {}
	var best_distance := max_distance
	for id in _server_effects:
		var entry: Dictionary = _server_effects[id]
		if entry.kind != Protocol.Effect.REMNANT or (entry.owner != 0 and entry.owner != entity_id):
			continue
		var offset: Vector3 = entry.position - point
		var distance := Vector2(offset.x, offset.z).length()
		if distance < best_distance:
			best_distance = distance
			best = {"id": id, "position": entry.position}
	return best


func spawn_predicted_projectile(origin: Vector3, velocity: Vector3, max_range: float) -> void:
	var node := _make_projectile()
	add_child(node)
	node.global_position = origin
	_predicted.append({"node": node, "velocity": velocity, "remaining": max_range})


func spawn_burst(at: Vector3, radius: float) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.85
	mesh.outer_radius = 1.0
	mesh.material = _glow_material(FLAME)
	var ring := MeshInstance3D.new()
	ring.mesh = mesh
	ring.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(ring)
	ring.global_position = at + Vector3.UP * 0.3
	ring.scale = Vector3.ONE * 0.3
	var tween := ring.create_tween().set_parallel()
	tween.tween_property(ring, "scale", Vector3(radius, 1.0, radius), 0.25).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "transparency", 1.0, 0.45)
	tween.chain().tween_callback(ring.queue_free)


func _process(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var targets: Array = target_positions.call() if target_positions.is_valid() else []
	for projectile in _predicted.duplicate():
		var node: Node3D = projectile.node
		var step: Vector3 = projectile.velocity * delta
		var hit_wall := not space.intersect_ray(PhysicsRayQueryParameters3D.create(
			node.global_position, node.global_position + step, WORLD_MASK)).is_empty()
		node.global_position += step
		projectile.remaining -= step.length()
		var hit_target := false
		for target_position: Vector3 in targets:
			hit_target = hit_target or Combat.sphere_overlaps(node.global_position, PREDICTED_HIT_RADIUS, target_position)
		if hit_wall or hit_target or projectile.remaining <= 0.0:
			node.queue_free()
			_predicted.erase(projectile)


func _make_projectile() -> Node3D:
	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var mesh := SphereMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.44
	mesh.material = _glow_material(FLAME)
	var ball := MeshInstance3D.new()
	ball.mesh = mesh
	root.add_child(ball)
	var light := OmniLight3D.new()
	light.light_color = FLAME
	light.omni_range = 3.0
	light.light_energy = 1.5
	root.add_child(light)
	return root


func _make_trap() -> Node3D:
	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var technique := Techniques.get_technique(Techniques.CINDER_TRAP)
	var mesh := CylinderMesh.new()
	mesh.top_radius = technique.radius
	mesh.bottom_radius = technique.radius
	mesh.height = 0.05
	mesh.material = _glow_material(FLAME)
	var disc := MeshInstance3D.new()
	disc.mesh = mesh
	disc.position.y = 0.03
	root.add_child(disc)
	return root


## A remnant: a slowly turning, glowing wisp in its aspect's color.
func _make_remnant(tint: Color) -> Node3D:
	var root := Node3D.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var core := SphereMesh.new()
	core.radius = 0.28
	core.height = 0.56
	core.material = _glow_material(tint)
	var core_mesh := MeshInstance3D.new()
	core_mesh.mesh = core
	root.add_child(core_mesh)
	var shell := SphereMesh.new()
	shell.radius = 0.6
	shell.height = 1.4
	var shell_material := _glow_material(tint)
	shell_material.albedo_color.a = 0.25
	shell_material.emission_energy_multiplier = 0.6
	shell.material = shell_material
	var shell_mesh := MeshInstance3D.new()
	shell_mesh.mesh = shell
	root.add_child(shell_mesh)
	var light := OmniLight3D.new()
	light.light_color = tint
	light.omni_range = 4.0
	light.light_energy = 1.2
	root.add_child(light)
	return root


static func _glow_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	return material
