class_name PlayerBody
extends CharacterBody3D
## A fighter's movement and combat state machine, shared by server and client. The server
## runs it authoritatively; the owning client runs the same code on the same inputs to
## predict. capture_state() holds everything simulate() reads, so the client can rewind
## to a server state and replay.
##
## Damage, hitstun, stagger and death come only from the server (see Combat). The client
## learns about them from snapshots and corrects.

enum Action { NONE, ATTACK, DODGE, BLOCK, HITSTUN, STAGGER, DEAD }

const RUN_SPEED := 6.0
const BLOCK_SPEED := 2.4
const GROUND_ACCEL := 45.0
const GROUND_FRICTION := 60.0
const AIR_ACCEL := 15.0
const STUN_FRICTION := 15.0
const GRAVITY := 22.0
const JUMP_VELOCITY := 8.5
const TURN_SPEED := 14.0
const LOCK_TURN_SPEED := 20.0
const GROUND_PROBE := 0.08

const DODGE_TICKS := 10
const DODGE_SPEED := 11.0
## Dodge ticks (inclusive) during which the fighter can't be hit.
const DODGE_IFRAME_START := 1
const DODGE_IFRAME_END := 6
const DODGE_COOLDOWN := 6
## How long a pressed action waits for the fighter to be free.
const BUFFER_TICKS := 8
## Block ticks at the start of a block that count as a parry.
const PARRY_WINDOW := 5
const RESPAWN_TICKS := 90
const MAX_HEALTH := 100
const MAX_ACTION_TICK := 0xFFFF

## Hurtbox: an upright capsule, treated as a box of this radius and height for hit tests.
const HURT_RADIUS := 0.4
const HURT_HEIGHT := 1.8

## Prediction error tolerated before the client corrects, in m, m/s and radians.
const POSITION_EPSILON := 0.01
const VELOCITY_EPSILON := 0.05
const ANGLE_EPSILON := 0.01

var entity_id := 0
## Yaw the fighter faces. Separate from the camera; attacks go this way.
var facing := 0.0
var health := MAX_HEALTH
var action := Action.NONE
var action_id := 0
var action_tick := 0
## Duration of server-imposed actions (hitstun, stagger, dead).
var action_length := 0
## PlayerInput button waiting for the fighter to be free, or 0.
var buffered := 0
var buffer_ticks := 0
var dodge_cooldown := 0
var dodge_yaw := 0.0
## Server only: entity ids already hit by the current attack.
var hit_targets := {}

@onready var _model: CharacterModel = $Model


func simulate(input: PlayerInput, delta: float) -> void:
	var grounded := is_grounded()
	var move := input.get_move()
	var direction := Vector3(move.x, 0.0, move.y).rotated(Vector3.UP, input.get_yaw())

	_update_buffer(input)
	dodge_cooldown = maxi(dodge_cooldown - 1, 0)
	action_tick = mini(action_tick + 1, MAX_ACTION_TICK)

	match action:
		Action.ATTACK:
			var attack := Attacks.get_attack(action_id)
			if action_tick >= attack.total_ticks():
				_set_action(Action.NONE)
			elif action_tick >= attack.startup + attack.active and grounded:
				_try_start_buffered(input, direction, true)
		Action.DODGE:
			if action_tick >= DODGE_TICKS:
				_set_action(Action.NONE)
				dodge_cooldown = DODGE_COOLDOWN
		Action.HITSTUN, Action.STAGGER:
			if action_tick >= action_length:
				_set_action(Action.NONE)
		Action.BLOCK:
			if not input.is_pressed(PlayerInput.BLOCK):
				_set_action(Action.NONE)

	if (action == Action.NONE or action == Action.BLOCK) and grounded:
		_try_start_buffered(input, direction, false)
		if action == Action.NONE and input.is_pressed(PlayerInput.BLOCK):
			_set_action(Action.BLOCK)

	_apply_movement(input, direction, grounded, delta)
	move_and_slide()
	_model.apply_pose(action, action_id, action_tick)


## Derived from position and velocity only (not move_and_slide's cached floor state),
## so it gives the same answer after the client rewinds and replays.
func is_grounded() -> bool:
	return velocity.y <= 0.0 and test_move(global_transform, Vector3.DOWN * GROUND_PROBE)


## The attack whose hitbox is live this tick, or null.
func active_attack() -> AttackData:
	if action != Action.ATTACK:
		return null
	var attack := Attacks.get_attack(action_id)
	if action_tick >= attack.startup and action_tick < attack.startup + attack.active:
		return attack
	return null


func is_dead() -> bool:
	return action == Action.DEAD


func is_invulnerable() -> bool:
	return action == Action.DEAD or (action == Action.DODGE
		and action_tick >= DODGE_IFRAME_START and action_tick <= DODGE_IFRAME_END)


func is_parrying() -> bool:
	return action == Action.BLOCK and action_tick <= PARRY_WINDOW


# --- Server-applied effects -------------------------------------------------------

func apply_damage(amount: int) -> void:
	health = maxi(health - amount, 0)
	if health == 0:
		_set_action(Action.DEAD, 0, RESPAWN_TICKS)
		_consume_buffer()
		velocity = Vector3(0.0, minf(velocity.y, 0.0), 0.0)


func apply_hitstun(ticks: int, knockback: Vector3) -> void:
	_apply_stun(Action.HITSTUN, ticks, knockback)


func apply_stagger(ticks: int, knockback: Vector3) -> void:
	_apply_stun(Action.STAGGER, ticks, knockback)


func respawn(at: Vector3, new_facing: float) -> void:
	restore_state({
		"position": at, "velocity": Vector3.ZERO, "facing": new_facing, "dodge_yaw": 0.0,
		"health": MAX_HEALTH, "action": Action.NONE, "action_id": 0, "action_tick": 0,
		"action_length": 0, "buffered": 0, "buffer_ticks": 0, "dodge_cooldown": 0,
	})


# --- State capture for prediction ---------------------------------------------------

func capture_state() -> Dictionary:
	return {
		"position": global_position,
		"velocity": velocity,
		"facing": facing,
		"dodge_yaw": dodge_yaw,
		"health": health,
		"action": action,
		"action_id": action_id,
		"action_tick": action_tick,
		"action_length": action_length,
		"buffered": buffered,
		"buffer_ticks": buffer_ticks,
		"dodge_cooldown": dodge_cooldown,
	}


func restore_state(state: Dictionary) -> void:
	global_position = state.position
	velocity = state.velocity
	facing = state.facing
	dodge_yaw = state.dodge_yaw
	health = state.health
	action = state.action
	action_id = state.action_id
	action_tick = state.action_tick
	action_length = state.action_length
	buffered = state.buffered
	buffer_ticks = state.buffer_ticks
	dodge_cooldown = state.dodge_cooldown
	_model.apply_pose(action, action_id, action_tick)


## True if a predicted state agrees with the server's. Health is ignored: it never feeds
## back into the simulation, and the client always takes the server's value.
static func states_match(a: Dictionary, b: Dictionary) -> bool:
	return (a.position.distance_to(b.position) <= POSITION_EPSILON
		and a.velocity.distance_to(b.velocity) <= VELOCITY_EPSILON
		and absf(angle_difference(a.facing, b.facing)) <= ANGLE_EPSILON
		and absf(angle_difference(a.dodge_yaw, b.dodge_yaw)) <= ANGLE_EPSILON
		and a.action == b.action
		and a.action_id == b.action_id
		and a.action_tick == b.action_tick
		and a.action_length == b.action_length
		and a.buffered == b.buffered
		and a.buffer_ticks == b.buffer_ticks
		and a.dodge_cooldown == b.dodge_cooldown)


# --- Internals ----------------------------------------------------------------------

func _update_buffer(input: PlayerInput) -> void:
	if buffer_ticks > 0:
		buffer_ticks -= 1
		if buffer_ticks == 0:
			buffered = 0
	for button in [PlayerInput.DODGE, PlayerInput.HEAVY, PlayerInput.LIGHT]:
		if input.is_pressed(button):
			buffered = button
			buffer_ticks = BUFFER_TICKS
			return


func _consume_buffer() -> void:
	buffered = 0
	buffer_ticks = 0


## Starts the buffered action if allowed. from_attack means cancelling an attack's
## recovery: light chains into the attack's combo, heavy ends the chain.
func _try_start_buffered(input: PlayerInput, direction: Vector3, from_attack: bool) -> void:
	if buffered == PlayerInput.DODGE:
		if dodge_cooldown == 0:
			_consume_buffer()
			_set_action(Action.DODGE)
			dodge_yaw = _yaw_of(direction) if direction != Vector3.ZERO else wrapf(facing + PI, -PI, PI)
	elif buffered == PlayerInput.LIGHT:
		var next := Attacks.LIGHT_1
		if from_attack:
			next = Attacks.get_attack(action_id).combo_next
		if next >= 0:
			_start_attack(next, input, direction)
	elif buffered == PlayerInput.HEAVY:
		if not (from_attack and action_id == Attacks.HEAVY):
			_start_attack(Attacks.HEAVY, input, direction)


func _start_attack(id: int, input: PlayerInput, direction: Vector3) -> void:
	_consume_buffer()
	_set_action(Action.ATTACK, id)
	hit_targets.clear()
	if input.is_pressed(PlayerInput.LOCKED):
		facing = input.get_aim()
	elif direction != Vector3.ZERO:
		facing = _yaw_of(direction)


func _apply_movement(input: PlayerInput, direction: Vector3, grounded: bool, delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	match action:
		Action.NONE, Action.BLOCK:
			var speed := RUN_SPEED if action == Action.NONE else BLOCK_SPEED
			var rate := GROUND_ACCEL if grounded else AIR_ACCEL
			if grounded and direction == Vector3.ZERO:
				rate = GROUND_FRICTION
			horizontal = horizontal.move_toward(direction * speed, rate * delta)
			if input.is_pressed(PlayerInput.LOCKED):
				facing = _turn(facing, input.get_aim(), LOCK_TURN_SPEED * delta)
			elif action == Action.NONE and direction != Vector3.ZERO:
				facing = _turn(facing, _yaw_of(direction), TURN_SPEED * delta)
		Action.ATTACK:
			var attack := Attacks.get_attack(action_id)
			var lunge := Vector3.ZERO
			if action_tick < attack.startup + attack.active:
				lunge = _forward(facing) * attack.lunge_speed
			horizontal = horizontal.move_toward(lunge, GROUND_FRICTION * delta)
		Action.DODGE:
			horizontal = _forward(dodge_yaw) * DODGE_SPEED
		_:
			horizontal = horizontal.move_toward(Vector3.ZERO, STUN_FRICTION * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if grounded:
		var jumping := action == Action.NONE and input.is_pressed(PlayerInput.JUMP)
		velocity.y = JUMP_VELOCITY if jumping else 0.0
	else:
		velocity.y -= GRAVITY * delta


func _apply_stun(stun: Action, ticks: int, knockback: Vector3) -> void:
	if action == Action.DEAD:
		return
	_set_action(stun, 0, ticks)
	_consume_buffer()
	velocity.x = knockback.x
	velocity.z = knockback.z


func _set_action(new_action: Action, id := 0, length := 0) -> void:
	action = new_action
	action_id = id
	action_tick = 0
	action_length = length


static func _forward(yaw: float) -> Vector3:
	return Vector3.FORWARD.rotated(Vector3.UP, yaw)


static func _yaw_of(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


static func _turn(from: float, to: float, max_step: float) -> float:
	return wrapf(rotate_toward(from, to, max_step), -PI, PI)
