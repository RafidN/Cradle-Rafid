class_name CameraRig
extends Node3D
## Third-person orbit camera. Its yaw also defines "forward" for movement input, so
## reading the player's input lives here too.

@export var mouse_sensitivity := 0.003
@export var stick_sensitivity := 3.0
@export var min_pitch := -1.2
@export var max_pitch := 0.5
@export var height := 1.5

var target: Node3D
var capture_mouse := true

@onready var _pitch: Node3D = $Pitch


func _ready() -> void:
	# Follows the target's interpolated transform by hand every frame instead.
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(-event.relative.x * mouse_sensitivity, -event.relative.y * mouse_sensitivity)
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	var stick := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	_look(-stick.x * stick_sensitivity * delta, -stick.y * stick_sensitivity * delta)
	if is_instance_valid(target):
		global_position = target.get_global_transform_interpolated().origin + Vector3.UP * height


## Called once per physics tick.
func sample_input() -> PlayerInput:
	var input := PlayerInput.new()
	input.set_move(Input.get_vector("move_left", "move_right", "move_forward", "move_back"))
	input.set_yaw(rotation.y)
	if Input.is_action_just_pressed("jump"):
		input.buttons |= PlayerInput.JUMP
	return input


func _look(yaw: float, pitch: float) -> void:
	rotation.y = wrapf(rotation.y + yaw, -PI, PI)
	_pitch.rotation.x = clampf(_pitch.rotation.x + pitch, min_pitch, max_pitch)
