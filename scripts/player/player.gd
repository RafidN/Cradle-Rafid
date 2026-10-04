class_name Player
extends CharacterBody3D
## Third-person platformer controller: camera-relative movement, coyote time,
## jump buffering, variable jump height, and Seed-gated double jump / dash.

@export_group("Movement")
@export var run_speed := 7.0
@export var acceleration := 40.0
@export var air_acceleration := 18.0
@export var friction := 50.0
@export var turn_speed := 12.0

@export_group("Jump")
@export var jump_velocity := 9.0
@export var gravity := 24.0
@export var fall_gravity_mult := 1.6
@export var jump_cut_mult := 0.5
@export var coyote_time := 0.1
@export var jump_buffer_time := 0.1

@export_group("Dash")
@export var dash_speed := 18.0
@export var dash_time := 0.18

@export_group("Camera")
@export var mouse_sensitivity := 0.003
@export var stick_sensitivity := 3.0
@export var min_pitch := -1.2
@export var max_pitch := 0.4

var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _air_jumps_used := 0
var _dash_timer := 0.0
var _dash_available := true
var _dash_direction := Vector3.ZERO

@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _model: Node3D = $Model


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rotate_camera(-event.relative.x * mouse_sensitivity, -event.relative.y * mouse_sensitivity)
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	var look := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	_rotate_camera(-look.x * stick_sensitivity * delta, -look.y * stick_sensitivity * delta)

	if is_on_floor():
		_coyote_timer = coyote_time
		_air_jumps_used = 0
		_dash_available = true
	else:
		_coyote_timer -= delta

	_jump_buffer_timer -= delta
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time

	if _dash_timer > 0.0:
		_dash_timer -= delta
		velocity = _dash_direction * dash_speed
		move_and_slide()
		return

	var direction := _get_move_direction()
	if Input.is_action_just_pressed("dash") and _dash_available and GameState.has_ability(&"dash"):
		_start_dash(direction)
		return

	_apply_gravity(delta)
	_handle_jump()
	_apply_horizontal(direction, delta)
	move_and_slide()


func _rotate_camera(yaw: float, pitch: float) -> void:
	_camera_pivot.rotation.y += yaw
	_camera_pivot.rotation.x = clampf(_camera_pivot.rotation.x + pitch, min_pitch, max_pitch)


func _get_move_direction() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis_yaw := Basis(Vector3.UP, _camera_pivot.global_rotation.y)
	return (basis_yaw * Vector3(input.x, 0.0, input.y)).normalized() * input.length()


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var g := gravity * (fall_gravity_mult if velocity.y < 0.0 else 1.0)
	velocity.y -= g * delta
	if velocity.y > 0.0 and not Input.is_action_pressed("jump"):
		velocity.y -= gravity * (1.0 / jump_cut_mult - 1.0) * delta


func _handle_jump() -> void:
	if _jump_buffer_timer <= 0.0:
		return
	if _coyote_timer > 0.0:
		_jump()
	elif _air_jumps_used == 0 and GameState.has_ability(&"double_jump"):
		_air_jumps_used += 1
		_jump()


func _jump() -> void:
	velocity.y = jump_velocity
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0


func _apply_horizontal(direction: Vector3, delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target := direction * run_speed
	var rate := acceleration if is_on_floor() else air_acceleration
	if direction == Vector3.ZERO and is_on_floor():
		rate = friction
	horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if direction != Vector3.ZERO:
		var target_yaw := atan2(-direction.x, -direction.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, turn_speed * delta)


func _start_dash(direction: Vector3) -> void:
	if direction == Vector3.ZERO:
		direction = -_model.global_basis.z
	_dash_direction = Vector3(direction.x, 0.0, direction.z).normalized()
	_dash_available = false
	_dash_timer = dash_time
