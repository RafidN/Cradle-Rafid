class_name WorldEffects
extends Node3D
## Draws technique effects. Server-owned effects (projectiles, traps) come from snapshots
## and are drawn at the same delayed render time as remote fighters. The local player's
## own projectiles and bursts are predicted: spawned the moment the technique releases.

const FLAME := Color(1.0, 0.5, 0.15)
const PREDICTED_HIT_RADIUS := 0.7
const WORLD_MASK := 1

## Called with no arguments; returns positions predicted projectiles can stop on.
var target_positions: Callable

var _server_effects := {}  # id -> {node, kind, tick, position, velocity, last_seen}
var _predicted: Array[Dictionary] = []  # {node, velocity, remaining}


func sync(snapshot_tick: int, effects: Array, local_entity_id: int) -> void:
	for effect: Dictionary in effects:
		if effect.kind == Protocol.Effect.PROJECTILE and effect.owner == local_entity_id:
			continue  # Already shown as a predicted projectile.
		var entry: Dictionary = _server_effects.get(effect.id, {})
		if entry.is_empty():
			var node := _make_projectile() if effect.kind == Protocol.Effect.PROJECTILE else _make_trap()
			add_child(node)
			entry = {"node": node, "kind": effect.kind}
			_server_effects[effect.id] = entry
		entry.tick = snapshot_tick
		entry.position = effect.position
		entry.velocity = effect.velocity
		entry.armed = effect.armed
		entry.last_seen = snapshot_tick


func render(render_tick: float) -> void:
	for id in _server_effects.keys():
		var entry: Dictionary = _server_effects[id]
		# Gone from snapshots: keep drawing until render time catches up, then remove.
		if render_tick > entry.last_seen + 1:
			entry.node.queue_free()
			_server_effects.erase(id)
			continue
		var elapsed: float = (render_tick - entry.tick) / Protocol.TICK_RATE
		entry.node.global_position = entry.position + entry.velocity * elapsed
		if entry.kind == Protocol.Effect.TRAP:
			var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.008) if entry.armed else 0.25
			entry.node.get_child(0).transparency = 1.0 - pulse


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


static func _glow_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	return material
