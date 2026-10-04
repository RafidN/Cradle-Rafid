class_name PlayerBody
extends CharacterBody3D
## Player movement shared by server and client. The server runs it authoritatively; the
## owning client runs the same code on the same inputs to predict, so the results agree.
## Everything simulate() depends on is position, velocity, facing and the input.

const RUN_SPEED := 6.0
const GROUND_ACCEL := 45.0
const GROUND_FRICTION := 60.0
const AIR_ACCEL := 15.0
const GRAVITY := 22.0
const JUMP_VELOCITY := 8.5
const TURN_SPEED := 14.0
const GROUND_PROBE := 0.08

var entity_id := 0
## Yaw the character faces. Separate from the camera; combat will use it.
var facing := 0.0

@onready var _model: Node3D = $Model


func simulate(input: PlayerInput, delta: float) -> void:
	var grounded := is_grounded()
	var move := input.get_move()
	var direction := Vector3(move.x, 0.0, move.y).rotated(Vector3.UP, input.get_yaw())

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := GROUND_ACCEL if grounded else AIR_ACCEL
	if grounded and direction == Vector3.ZERO:
		rate = GROUND_FRICTION
	horizontal = horizontal.move_toward(direction * RUN_SPEED, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if grounded:
		velocity.y = JUMP_VELOCITY if input.is_pressed(PlayerInput.JUMP) else 0.0
	else:
		velocity.y -= GRAVITY * delta

	if direction != Vector3.ZERO:
		var target := atan2(-direction.x, -direction.z)
		facing = wrapf(rotate_toward(facing, target, TURN_SPEED * delta), -PI, PI)
	_model.rotation.y = facing

	move_and_slide()


## Derived from position and velocity only (not move_and_slide's cached floor state),
## so it gives the same answer after the client rewinds and replays.
func is_grounded() -> bool:
	return velocity.y <= 0.0 and test_move(global_transform, Vector3.DOWN * GROUND_PROBE)


func set_state(new_position: Vector3, new_velocity: Vector3, new_facing: float) -> void:
	global_position = new_position
	velocity = new_velocity
	facing = new_facing
	_model.rotation.y = facing
