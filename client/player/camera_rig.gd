class_name CameraRig
extends Node3D
## Third-person orbit camera. Its yaw also defines "forward" for movement input, so
## reading the player's input lives here too. While locked on, it turns to keep the
## target in view and mouse yaw is ignored.

const LOCK_TURN_SPEED := 8.0

@export var mouse_sensitivity := 0.003
@export var stick_sensitivity := 3.0
@export var min_pitch := -1.2
@export var max_pitch := 0.5
@export var height := 1.5

var target: Node3D
var capture_mouse := true
## World point to keep in view while locked on.
var lock_point := Vector3.ZERO
var locked := false

@onready var _pitch: Node3D = $Pitch


func _ready() -> void:
	# Follows the target's interpolated transform by hand every frame instead.
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(0.0 if locked else -event.relative.x * mouse_sensitivity, -event.relative.y * mouse_sensitivity)
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and capture_mouse \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var stick := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	_look(0.0 if locked else -stick.x * stick_sensitivity * delta, -stick.y * stick_sensitivity * delta)
	if is_instance_valid(target):
		global_position = target.get_global_transform_interpolated().origin + Vector3.UP * height
	if locked:
		var to_target := lock_point - global_position
		var target_yaw := atan2(-to_target.x, -to_target.z)
		rotation.y = wrapf(rotate_toward(rotation.y, target_yaw, LOCK_TURN_SPEED * delta), -PI, PI)


## Called once per physics tick.
func sample_input() -> PlayerInput:
	var input := PlayerInput.new()
	input.set_move(Input.get_vector("move_left", "move_right", "move_forward", "move_back"))
	input.set_yaw(rotation.y)
	if capture_mouse and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return input  # The menu has the mouse; don't swing at it.
	if Input.is_action_just_pressed("jump"):
		input.buttons |= PlayerInput.JUMP
	if Input.is_action_just_pressed("dodge"):
		input.buttons |= PlayerInput.DODGE
	if Input.is_action_just_pressed("heavy_attack"):
		input.buttons |= PlayerInput.HEAVY
	if Input.is_action_just_pressed("light_attack"):
		input.buttons |= PlayerInput.LIGHT
	if Input.is_action_pressed("block"):
		input.buttons |= PlayerInput.BLOCK
	if Input.is_action_just_pressed("cycle"):
		input.buttons |= PlayerInput.CYCLE
	for slot in PlayerInput.TECHNIQUE_COUNT:
		if Input.is_action_just_pressed("technique_%d" % (slot + 1)):
			input.buttons |= PlayerInput.technique_button(slot)
	return input


func _look(yaw: float, pitch: float) -> void:
	rotation.y = wrapf(rotation.y + yaw, -PI, PI)
	_pitch.rotation.x = clampf(_pitch.rotation.x + pitch, min_pitch, max_pitch)
