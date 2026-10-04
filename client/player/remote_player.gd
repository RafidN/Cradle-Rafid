class_name RemotePlayer
extends Node3D
## Another player as this client sees them: visuals only, positioned by interpolating
## buffered server snapshots. No collision and no simulation.

const MAX_BUFFERED := 32

var _states: Array[Dictionary] = []  # {tick, position, facing}, oldest first

@onready var _model: Node3D = $Model
@onready var _name_label: Label3D = $NameLabel


func _ready() -> void:
	# Moved every frame by render(), not in physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func set_display_name(display_name: String) -> void:
	_name_label.text = display_name


func push_state(tick: int, state_position: Vector3, facing: float) -> void:
	_states.append({"tick": tick, "position": state_position, "facing": facing})
	if _states.size() > MAX_BUFFERED:
		_states.pop_front()


func render(render_tick: float) -> void:
	if _states.is_empty():
		return
	var from: Dictionary = _states[0]
	var to: Dictionary = _states[0]
	var weight := 0.0
	if render_tick >= _states[-1].tick:
		from = _states[-1]  # Out of data: hold the newest state rather than extrapolate.
		to = from
	else:
		for i in _states.size() - 1:
			if _states[i].tick <= render_tick and render_tick < _states[i + 1].tick:
				from = _states[i]
				to = _states[i + 1]
				weight = (render_tick - from.tick) / float(to.tick - from.tick)
				break
	global_position = from.position.lerp(to.position, weight)
	_model.rotation.y = lerp_angle(from.facing, to.facing, weight)
