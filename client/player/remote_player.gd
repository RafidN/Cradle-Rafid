class_name RemotePlayer
extends Node3D
## Another fighter as this client sees them: visuals only, positioned and posed by
## interpolating buffered server snapshots. No collision and no simulation.

const MAX_BUFFERED := 32
const BAR_SIZE := Vector2(0.9, 0.09)
const BAR_HEIGHT := 2.15
const NAME_COLOR := Color(1, 1, 1)
const LOCKED_COLOR := Color(1.0, 0.82, 0.3)
const ARTIST_COLOR := Color(0.85, 0.45, 0.38)
const DUMMY_COLOR := Color(0.75, 0.68, 0.55)

var display_name := "..."
var kind := Protocol.EntityKind.ARTIST
var max_health := PlayerBody.MAX_HEALTH
## Tick of the newest snapshot that included this fighter.
var last_seen_tick := 0
var _label_text := "..."
var _locked := false

var _states: Array[Dictionary] = []  # snapshot states with "tick", oldest first
var _fill_mesh := QuadMesh.new()
var _bar_quads: Array[MeshInstance3D] = []
var _shown_health := -1
var _previous_position := Vector3.ZERO
var _speed := 0.0

@onready var _model: CharacterModel = $Model
@onready var _name_label: Label3D = $NameLabel


func _ready() -> void:
	# Moved every frame by render(), not in physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var background := QuadMesh.new()
	background.size = BAR_SIZE
	_add_bar_quad(background, Color(0.08, 0.08, 0.08, 0.8), 0)
	_fill_mesh.size = BAR_SIZE
	_add_bar_quad(_fill_mesh, Color(0.85, 0.2, 0.2), 1)


## Applies an ENTITY_INFO: name, and what the fighter looks like.
func configure(info: Dictionary) -> void:
	display_name = info.name
	kind = info.kind
	max_health = info.get("max_health", PlayerBody.MAX_HEALTH)
	_shown_health = -1
	var tint := ARTIST_COLOR
	var size := 1.0
	_label_text = "%s  ·  %s" % [display_name, Advancement.rank_name(info.rank)]
	if kind == Protocol.EntityKind.BEAST:
		var beast := Beasts.get_beast(info.species)
		tint = beast.color
		size = beast.scale
		_label_text = "%s  (%s)" % [display_name, beast.rank_label]
	elif kind == Protocol.EntityKind.DUMMY:
		tint = DUMMY_COLOR
		_label_text = display_name
	_model.set_color(tint)
	_model.scale = Vector3.ONE * size
	_name_label.position.y = 2.4 * size
	for quad in _bar_quads:
		quad.position.y = BAR_HEIGHT * size
	_refresh_label()


func set_locked(locked: bool) -> void:
	_locked = locked
	_refresh_label()


func _refresh_label() -> void:
	_name_label.modulate = LOCKED_COLOR if _locked else NAME_COLOR
	_name_label.text = "> %s <" % _label_text if _locked else _label_text


func push_state(tick: int, state: Dictionary) -> void:
	state.tick = tick
	last_seen_tick = tick
	_states.append(state)
	if _states.size() > MAX_BUFFERED:
		_states.pop_front()


func latest_state() -> Dictionary:
	return _states[-1] if not _states.is_empty() else {}


func is_dead() -> bool:
	return not _states.is_empty() and _states[-1].action == PlayerBody.Action.DEAD


func render(render_tick: float, delta: float) -> void:
	if _states.is_empty():
		return
	var from: Dictionary = _states[0]
	var to: Dictionary = _states[0]
	var weight := 0.0
	if render_tick >= _states[-1].tick:
		from = _states[-1]  # Out of data: hold the newest state rather than extrapolate.
		to = from
	elif render_tick > _states[0].tick:
		for i in _states.size() - 1:
			if render_tick < _states[i + 1].tick:
				from = _states[i]
				to = _states[i + 1]
				weight = (render_tick - from.tick) / float(to.tick - from.tick)
				break

	global_position = from.position.lerp(to.position, weight)
	_model.rotation.y = lerp_angle(from.facing, to.facing, weight)
	var action_tick: float = from.action_tick
	if to.action == from.action and to.action_id == from.action_id:
		action_tick = lerpf(from.action_tick, to.action_tick, weight)
	if delta > 0.0:
		var moved := global_position - _previous_position
		_speed = lerpf(_speed, Vector2(moved.x, moved.z).length() / delta, 1.0 - exp(-12.0 * delta))
	_previous_position = global_position
	_model.update_pose(from.action, from.action_id, action_tick, from.flags, _speed, delta)
	_update_health_bar(from.health, max_health)


func _update_health_bar(health: int, max_health: int) -> void:
	if health == _shown_health:
		return
	_shown_health = health
	var fraction := clampf(float(health) / maxi(max_health, 1), 0.0, 1.0)
	_fill_mesh.size = Vector2(BAR_SIZE.x * fraction, BAR_SIZE.y)
	# Left-align the fill inside the bar, in billboard space.
	_fill_mesh.center_offset = Vector3(-BAR_SIZE.x * (1.0 - fraction) * 0.5, 0.0, 0.002)


func _add_bar_quad(mesh: QuadMesh, tint: Color, priority: int) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.albedo_color = tint
	material.render_priority = priority
	mesh.material = material
	var quad := MeshInstance3D.new()
	quad.mesh = mesh
	quad.position.y = BAR_HEIGHT
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)
	_bar_quads.append(quad)
