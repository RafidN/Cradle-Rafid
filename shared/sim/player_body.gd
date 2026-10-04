class_name PlayerBody
extends CharacterBody3D
## A spirit practitioner's movement, combat and spirit state machine, shared by server and
## client. The server runs it authoritatively; the owning client runs the same code on
## the same inputs to predict. capture_state() holds everything simulate() reads, so the
## client can rewind to a server state and replay.
##
## Damage, hitstun, stagger and death come only from the server (see Combat). So do the
## effects of released techniques (projectiles, bursts, traps); the simulation only
## reports the release through released_technique.

## New actions go at the end: the values go over the network.
enum Action { NONE, ATTACK, DODGE, BLOCK, HITSTUN, STAGGER, DEAD, MEDITATE, TECHNIQUE }

## Visual flags sent with other fighters.
const FLAG_ENFORCER := 1 << 0
const FLAG_EXHAUSTED := 1 << 1

const RUN_SPEED := 6.0
const BLOCK_SPEED := 2.4
const GROUND_ACCEL := 45.0
const GROUND_FRICTION := 60.0
const AIR_ACCEL := 15.0
const STUN_FRICTION := 15.0
const GRAVITY := 22.0
const JUMP_VELOCITY := 8.5
## The fighter turns to face where the camera looks (or its lock-on target).
const FACE_TURN_SPEED := 20.0
## Attacks and casts can still be steered toward the camera during their startup.
const STARTUP_STEER_SPEED := 10.0
## Movement input cancels an attack or cast once this much of its recovery has passed.
const MOVE_CANCEL_FRACTION := 0.5
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

## Spirit is kept in hundredths so it stays an integer and predicts exactly.
const SPIRIT_SCALE := 100
const MAX_SPIRIT := 100 * SPIRIT_SCALE
## Regen per tick, in hundredths: passive 0.3/s; meditating 1.2/s per (1 + flow), so up to
## 7.2/s at full flow. No regen while blocking, exhausted or with an Enforcer active.
const PASSIVE_REGEN := 1
const MEDITATION_REGEN := 4
const ENFORCER_DRAIN := 5
const ENFORCER_SPEED_MULT := 1.2
## Running dry leaves the practitioner exhausted: slow, unable to dodge, block or cast.
const EXHAUST_TICKS := 60
const EXHAUSTED_SPEED_MULT := 0.5
## Meditating: a breath peaks every BREATH_BEAT_TICKS. A breath within BREATH_WINDOW ticks of
## the peak raises flow; an off-beat breath breaks it; a skipped peak lowers it.
const BREATH_BEAT_TICKS := 45
const BREATH_WINDOW := 4
const MAX_FLOW := 5

## Hurtbox: an upright capsule, treated as a box of this radius and height for hit tests.
const HURT_RADIUS := 0.4
const HURT_HEIGHT := 1.8

## Prediction error tolerated before the client corrects, in m, m/s and radians.
const POSITION_EPSILON := 0.01
const VELOCITY_EPSILON := 0.05
const ANGLE_EPSILON := 0.01

## Action priority when several are pressed on the same tick.
const BUFFER_PRIORITY := [
	PlayerInput.DODGE,
	PlayerInput.TECHNIQUE_1, PlayerInput.TECHNIQUE_1 << 1, PlayerInput.TECHNIQUE_1 << 2, PlayerInput.TECHNIQUE_1 << 3,
	PlayerInput.HEAVY, PlayerInput.LIGHT, PlayerInput.MEDITATE,
]

var entity_id := 0

# Stats. Set from rank (players) or species (beasts) with apply_stats(); the defaults
# are a fully unlocked Iron practitioner. Not part of the per-tick state.
var max_health := MAX_HEALTH
var spirit_capacity := MAX_SPIRIT
## Technique slots 0..technique_slots-1 can be cast.
var technique_slots := PlayerInput.TECHNIQUE_COUNT
var damage_mult := 1.0
var knockback_taken_mult := 1.0
var speed_mult := 1.0
## Fighters on the same nonzero team can't hurt each other (beasts are team 1).
## Team 0 is free-for-all: spirit practitioners may fight anyone.
var team := 0

## Yaw the fighter faces. Separate from the camera; attacks go this way.
var facing := 0.0
var health := MAX_HEALTH
var action := Action.NONE
## Attack id for ATTACK, technique id for TECHNIQUE.
var action_id := 0
var action_tick := 0
## Duration of server-imposed actions (hitstun, stagger, dead).
var action_length := 0
## PlayerInput button waiting for the fighter to be free, or 0.
var buffered := 0
var buffer_ticks := 0
var dodge_cooldown := 0
var dodge_yaw := 0.0
var spirit := MAX_SPIRIT
var flow := 0
## Last meditating beat that was breathed on or missed.
var breath_beat := 0
var exhaust_ticks := 0
var enforcer_active := false

## Set by simulate() on the tick a technique releases, else -1. Not part of the state.
var released_technique := -1
## Server only: entity ids already hit by the current attack.
var hit_targets := {}

@onready var _model: CharacterModel = $Model


func _ready() -> void:
	set_process(DisplayServer.get_name() != "headless")


## Poses the model every rendered frame, between physics ticks, so motion stays smooth.
func _process(delta: float) -> void:
	var tick := action_tick + Engine.get_physics_interpolation_fraction()
	_model.update_pose(action, action_id, tick, visual_flags(), Vector2(velocity.x, velocity.z).length(), delta)


func simulate(input: PlayerInput, delta: float) -> void:
	var grounded := is_grounded()
	var move := input.get_move()
	var direction := Vector3(move.x, 0.0, move.y).rotated(Vector3.UP, input.get_yaw())
	released_technique = -1

	_update_buffer(input)
	dodge_cooldown = maxi(dodge_cooldown - 1, 0)
	exhaust_ticks = maxi(exhaust_ticks - 1, 0)
	action_tick = mini(action_tick + 1, MAX_ACTION_TICK)

	match action:
		Action.ATTACK:
			var attack := Attacks.get_attack(action_id)
			var recovery_start := attack.startup + attack.active
			if action_tick >= attack.total_ticks() or _move_cancels(direction, recovery_start, attack.recovery):
				_set_action(Action.NONE)
			elif action_tick >= recovery_start and grounded:
				_try_start_buffered(input, direction, true)
		Action.TECHNIQUE:
			var technique := Techniques.get_technique(action_id)
			if action_tick == technique.startup:
				_release(technique)
			if action_tick >= technique.total_ticks() or _move_cancels(direction, technique.startup + 1, technique.recovery):
				_set_action(Action.NONE)
		Action.DODGE:
			if action_tick >= DODGE_TICKS:
				_set_action(Action.NONE)
				dodge_cooldown = DODGE_COOLDOWN
		Action.HITSTUN, Action.STAGGER:
			if action_tick >= action_length:
				_set_action(Action.NONE)
		Action.BLOCK:
			if not input.is_pressed(PlayerInput.BLOCK) or is_exhausted():
				_set_action(Action.NONE)
		Action.MEDITATE:
			_update_meditation(input, direction)

	if (action == Action.NONE or action == Action.BLOCK) and grounded:
		_try_start_buffered(input, direction, false)
		if action == Action.NONE and input.is_pressed(PlayerInput.BLOCK) and not is_exhausted():
			_set_action(Action.BLOCK)

	_update_spirit()
	_apply_movement(input, direction, grounded, delta)
	move_and_slide()
	_model.rotation.y = facing


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


func is_exhausted() -> bool:
	return exhaust_ticks > 0


func is_invulnerable() -> bool:
	return action == Action.DEAD or (action == Action.DODGE
		and action_tick >= DODGE_IFRAME_START and action_tick <= DODGE_IFRAME_END)


func is_parrying() -> bool:
	return action == Action.BLOCK and action_tick <= PARRY_WINDOW


func visual_flags() -> int:
	return (FLAG_ENFORCER if enforcer_active else 0) | (FLAG_EXHAUSTED if is_exhausted() else 0)


## Whether a technique slot could be cast right now, ignoring cost (overdrawing is allowed).
func can_cast() -> bool:
	return not is_exhausted() and spirit > 0


func forward() -> Vector3:
	return _forward(facing)


# --- Server-applied effects -------------------------------------------------------

func apply_damage(amount: int) -> void:
	health = maxi(health - amount, 0)
	if health == 0:
		_set_action(Action.DEAD, 0, RESPAWN_TICKS)
		_consume_buffer()
		enforcer_active = false
		flow = 0
		velocity = Vector3(0.0, minf(velocity.y, 0.0), 0.0)


func apply_hitstun(ticks: int, knockback: Vector3) -> void:
	_apply_stun(Action.HITSTUN, ticks, knockback)


func apply_stagger(ticks: int, knockback: Vector3) -> void:
	_apply_stun(Action.STAGGER, ticks, knockback)


func respawn(at: Vector3, new_facing: float) -> void:
	restore_state({
		"position": at, "velocity": Vector3.ZERO, "facing": new_facing, "dodge_yaw": 0.0,
		"health": max_health, "action": Action.NONE, "action_id": 0, "action_tick": 0,
		"action_length": 0, "buffered": 0, "buffer_ticks": 0, "dodge_cooldown": 0,
		"spirit": spirit_capacity, "flow": 0, "breath_beat": 0, "exhaust_ticks": 0,
		"enforcer_active": false,
	})


## Applies rank or species stats. Health and spirit are clamped to the new maximums.
func apply_stats(new_max_health: int, new_spirit_capacity: int, new_technique_slots: int,
		new_damage_mult: float, new_knockback_taken_mult: float, new_speed_mult: float) -> void:
	max_health = new_max_health
	spirit_capacity = new_spirit_capacity
	technique_slots = new_technique_slots
	damage_mult = new_damage_mult
	knockback_taken_mult = new_knockback_taken_mult
	speed_mult = new_speed_mult
	health = mini(health, max_health)
	spirit = mini(spirit, spirit_capacity)


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
		"spirit": spirit,
		"flow": flow,
		"breath_beat": breath_beat,
		"exhaust_ticks": exhaust_ticks,
		"enforcer_active": enforcer_active,
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
	spirit = state.spirit
	flow = state.flow
	breath_beat = state.breath_beat
	exhaust_ticks = state.exhaust_ticks
	enforcer_active = state.enforcer_active
	_model.rotation.y = facing


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
		and a.dodge_cooldown == b.dodge_cooldown
		and a.spirit == b.spirit
		and a.flow == b.flow
		and a.breath_beat == b.breath_beat
		and a.exhaust_ticks == b.exhaust_ticks
		and a.enforcer_active == b.enforcer_active)


# --- Internals ----------------------------------------------------------------------

func _update_buffer(input: PlayerInput) -> void:
	if buffer_ticks > 0:
		buffer_ticks -= 1
		if buffer_ticks == 0:
			buffered = 0
	for button: int in BUFFER_PRIORITY:
		# While meditating, the meditate button is a breath, not an action to buffer.
		if button == PlayerInput.MEDITATE and action == Action.MEDITATE:
			continue
		if input.is_pressed(button):
			buffered = button
			buffer_ticks = BUFFER_TICKS
			return


func _consume_buffer() -> void:
	buffered = 0
	buffer_ticks = 0


## Starts the buffered action if allowed. from_attack means cancelling an attack's
## recovery: light chains into the attack's combo, heavy ends the chain, and dodges and
## techniques cancel freely.
func _try_start_buffered(input: PlayerInput, direction: Vector3, from_attack: bool) -> void:
	if buffered == PlayerInput.DODGE:
		if is_exhausted():
			_consume_buffer()
		elif dodge_cooldown == 0:
			_consume_buffer()
			_set_action(Action.DODGE)
			dodge_yaw = _yaw_of(direction) if direction != Vector3.ZERO else wrapf(facing + PI, -PI, PI)
	elif buffered & PlayerInput.TECHNIQUE_MASK:
		_try_cast(PlayerInput.technique_slot(buffered), input, direction)
	elif buffered == PlayerInput.LIGHT:
		var next := Attacks.LIGHT_1
		if from_attack:
			next = Attacks.get_attack(action_id).combo_next
		if next >= 0:
			_start_attack(next, input, direction)
	elif buffered == PlayerInput.HEAVY:
		if not (from_attack and action_id == Attacks.HEAVY):
			_start_attack(Attacks.HEAVY, input, direction)
	elif buffered == PlayerInput.MEDITATE and action == Action.NONE:
		_consume_buffer()
		_set_action(Action.MEDITATE)
		flow = 0
		breath_beat = 0
		enforcer_active = false  # Sitting to meditate releases an Enforcer technique.


func _start_attack(id: int, input: PlayerInput, _direction: Vector3) -> void:
	_consume_buffer()
	_set_action(Action.ATTACK, id)
	hit_targets.clear()
	facing = _intent_yaw(input)


## Casting spends spirit up front. Overdrawing is allowed: the technique still goes off,
## but the pool empties and the practitioner is exhausted. Turning an Enforcer off is free.
func _try_cast(technique_id: int, input: PlayerInput, _direction: Vector3) -> void:
	_consume_buffer()
	var technique := Techniques.get_technique(technique_id)
	if technique == null or technique_id >= technique_slots:
		return  # Not unlocked at this rank.
	var toggling_off := technique.kind == TechniqueData.Kind.ENFORCER and enforcer_active
	if not toggling_off:
		if not can_cast():
			return
		spirit -= technique.cost * SPIRIT_SCALE
		if spirit <= 0:
			_exhaust()
	_set_action(Action.TECHNIQUE, technique_id)
	facing = _intent_yaw(input)


func _release(technique: TechniqueData) -> void:
	released_technique = action_id
	if technique.kind == TechniqueData.Kind.ENFORCER:
		enforcer_active = not enforcer_active and not is_exhausted()


func _update_meditation(input: PlayerInput, direction: Vector3) -> void:
	if direction.length() > 0.3 or input.is_pressed(PlayerInput.BLOCK) or buffered != 0:
		_set_action(Action.NONE)
		flow = 0
		return
	var tick := action_tick
	if input.is_pressed(PlayerInput.MEDITATE):
		var beat := (tick + BREATH_BEAT_TICKS / 2) / BREATH_BEAT_TICKS
		if beat >= 1 and absi(tick - beat * BREATH_BEAT_TICKS) <= BREATH_WINDOW and breath_beat < beat:
			flow = mini(flow + 1, MAX_FLOW)
		else:
			flow = 0  # Off-beat or a second breath on the same beat.
		breath_beat = maxi(breath_beat, beat)
	elif tick > BREATH_WINDOW and (tick - BREATH_WINDOW - 1) % BREATH_BEAT_TICKS == 0:
		var missed := (tick - BREATH_WINDOW - 1) / BREATH_BEAT_TICKS
		if missed >= 1 and breath_beat < missed:
			flow = maxi(flow - 1, 0)
			breath_beat = missed
	# Keep counters small during very long sessions; beat timing is unchanged.
	if action_tick >= BREATH_BEAT_TICKS * 1000:
		action_tick -= BREATH_BEAT_TICKS * 900
		breath_beat -= 900


func _update_spirit() -> void:
	if enforcer_active:
		spirit -= ENFORCER_DRAIN
		if spirit <= 0:
			_exhaust()
		return
	if is_exhausted() or action == Action.DEAD:
		return
	var regen := PASSIVE_REGEN
	if action == Action.MEDITATE:
		regen = MEDITATION_REGEN * (1 + flow)
	elif action == Action.BLOCK:
		regen = 0
	spirit = mini(spirit + regen, spirit_capacity)


func _exhaust() -> void:
	spirit = 0
	exhaust_ticks = EXHAUST_TICKS
	enforcer_active = false


## Where the player wants to face: the lock-on target, or else where the camera looks.
static func _intent_yaw(input: PlayerInput) -> float:
	return input.get_aim() if input.is_pressed(PlayerInput.LOCKED) else input.get_yaw()


func _move_cancels(direction: Vector3, recovery_start: int, recovery: int) -> bool:
	return direction.length() > 0.3 and action_tick >= recovery_start + ceili(recovery * MOVE_CANCEL_FRACTION)


func _apply_movement(input: PlayerInput, direction: Vector3, grounded: bool, delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	match action:
		Action.NONE, Action.BLOCK:
			var speed := (RUN_SPEED if action == Action.NONE else BLOCK_SPEED) * speed_mult
			if enforcer_active:
				speed *= ENFORCER_SPEED_MULT
			if is_exhausted():
				speed *= EXHAUSTED_SPEED_MULT
			var rate := GROUND_ACCEL if grounded else AIR_ACCEL
			if grounded and direction == Vector3.ZERO:
				rate = GROUND_FRICTION
			horizontal = horizontal.move_toward(direction * speed, rate * delta)
			facing = _turn(facing, _intent_yaw(input), FACE_TURN_SPEED * delta)
		Action.ATTACK:
			var attack := Attacks.get_attack(action_id)
			var lunge := Vector3.ZERO
			if action_tick < attack.startup:
				facing = _turn(facing, _intent_yaw(input), STARTUP_STEER_SPEED * delta)
			if action_tick < attack.startup + attack.active:
				lunge = _forward(facing) * attack.lunge_speed
			horizontal = horizontal.move_toward(lunge, GROUND_FRICTION * delta)
		Action.DODGE:
			horizontal = _forward(dodge_yaw) * DODGE_SPEED
		Action.TECHNIQUE:
			if action_tick < Techniques.get_technique(action_id).startup:
				facing = _turn(facing, _intent_yaw(input), STARTUP_STEER_SPEED * delta)
			horizontal = horizontal.move_toward(Vector3.ZERO, GROUND_FRICTION * delta)
		Action.MEDITATE:
			horizontal = horizontal.move_toward(Vector3.ZERO, GROUND_FRICTION * delta)
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
	flow = 0
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
