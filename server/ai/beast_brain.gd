class_name BeastBrain
extends RefCounted
## Drives a sacred beast by producing the same PlayerInput a player would send, so beasts
## fight with the shared combat and technique code.
##
## IDLE: wander near home. HUNT: chase the target and attack in bursts separated by
## pauses (the player's openings). RETURN: led too far from home, go back and heal.
## A beast hunts the nearest sacred artist within its aggro range, or whoever hits it.

enum State { IDLE, HUNT, RETURN }

const WANDER_RADIUS := 4.0
const WANDER_STICK := 0.35
const HOME_REACHED := 1.5
## Light presses this far apart chain into the full combo.
const COMBO_SPACING := 7

var data: BeastData
var body: PlayerBody
var home := Vector3.ZERO
var state := State.IDLE
var target_id := -1

var _input_tick := 0
var _cooldown := 0
var _queue: Array = []  # [ticks_until, buttons, move], soonest first
var _wander_to := Vector3.ZERO
var _wander_ticks := 0
var _rng := RandomNumberGenerator.new()


func _init(beast: BeastData, beast_body: PlayerBody, beast_home: Vector3, seed_value: int) -> void:
	data = beast
	body = beast_body
	home = beast_home
	_wander_to = beast_home
	_rng.seed = seed_value


## artists: the bodies of sacred artists (players) a beast may hunt.
func think(artists: Array) -> PlayerInput:
	_input_tick += 1
	var input := PlayerInput.new()
	input.tick = _input_tick
	if body.is_dead():
		_reset()
		return input

	var target := _find_target(artists)
	if state == State.HUNT and (target == null or _from_home() > data.leash_range):
		_start_return()
	elif state == State.IDLE and target != null:
		state = State.HUNT

	match state:
		State.IDLE:
			_wander(input)
		State.RETURN:
			_steer_toward(input, home, 1.0)
			if _from_home() < HOME_REACHED:
				state = State.IDLE
				body.health = body.max_health  # Back in its den, it recovers.
		State.HUNT:
			_hunt(input, target)
	return input


## Being hit makes a beast hunt the attacker, unless it's already returning home.
func on_hit(attacker: PlayerBody) -> void:
	if attacker and state != State.RETURN and not body.is_dead():
		target_id = attacker.entity_id
		state = State.HUNT


func _hunt(input: PlayerInput, target: PlayerBody) -> void:
	var offset := target.global_position - body.global_position
	var yaw := atan2(-offset.x, -offset.z)
	var distance := Vector2(offset.x, offset.z).length()
	input.set_yaw(yaw)
	input.set_aim(yaw)
	input.buttons |= PlayerInput.LOCKED
	if distance > data.attack_range * 0.8:
		input.set_move(Vector2(0.0, -1.0))

	if not _queue.is_empty():
		_run_queue(input)
		return
	if _cooldown > 0:
		_cooldown -= 1
		if distance < data.attack_range * 2.0:
			input.set_move(Vector2(sin(_input_tick * 0.05) * 0.5, 0.0))  # Circle while waiting.
		return

	if distance <= data.attack_range:
		_choose_melee()
		_run_queue(input)
	elif data.ranged_technique >= 0 and distance >= data.ranged_min and distance <= data.ranged_max and _rng.randf() < 0.03:
		_queue.append([0, PlayerInput.technique_button(data.ranged_technique), Vector2.ZERO])
		_cooldown = _rng.randi_range(data.attack_cooldown.x, data.attack_cooldown.y)
		_run_queue(input)


func _choose_melee() -> void:
	var weights := [data.combo_weight, data.heavy_weight, data.dodge_weight,
		data.close_technique_weight if data.close_technique >= 0 else 0.0]
	var pick := _rng.rand_weighted(PackedFloat32Array(weights))
	match pick:
		0:
			for i in 3:
				_queue.append([i * COMBO_SPACING, PlayerInput.LIGHT, Vector2.ZERO])
		1:
			_queue.append([0, PlayerInput.HEAVY, Vector2.ZERO])
		2:
			var side := -1.0 if _rng.randf() < 0.5 else 1.0
			_queue.append([0, PlayerInput.DODGE, Vector2(side, 0.6).normalized()])
		3:
			_queue.append([0, PlayerInput.technique_button(data.close_technique), Vector2.ZERO])
	_cooldown = _rng.randi_range(data.attack_cooldown.x, data.attack_cooldown.y)


func _run_queue(input: PlayerInput) -> void:
	for entry in _queue:
		entry[0] -= 1
	while not _queue.is_empty() and _queue[0][0] < 0:
		var entry: Array = _queue.pop_front()
		input.buttons |= entry[1]
		if entry[2] != Vector2.ZERO:
			input.set_move(entry[2])


func _wander(input: PlayerInput) -> void:
	_wander_ticks -= 1
	if _wander_ticks <= 0:
		var angle := _rng.randf() * TAU
		_wander_to = home + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf() * WANDER_RADIUS
		_wander_ticks = _rng.randi_range(60, 150)
	if body.global_position.distance_to(_wander_to) > 0.8:
		_steer_toward(input, _wander_to, WANDER_STICK)


func _steer_toward(input: PlayerInput, point: Vector3, stick: float) -> void:
	var offset := point - body.global_position
	input.set_yaw(atan2(-offset.x, -offset.z))
	input.set_move(Vector2(0.0, -stick))


func _find_target(artists: Array) -> PlayerBody:
	for artist: PlayerBody in artists:
		if artist.entity_id == target_id and not artist.is_dead():
			return artist
	target_id = -1
	if state == State.RETURN:
		return null
	var nearest: PlayerBody = null
	var nearest_distance := data.aggro_range
	for artist: PlayerBody in artists:
		var distance := artist.global_position.distance_to(body.global_position)
		if not artist.is_dead() and distance < nearest_distance:
			nearest = artist
			nearest_distance = distance
	if nearest:
		target_id = nearest.entity_id
	return nearest


func _start_return() -> void:
	state = State.RETURN
	target_id = -1
	_queue.clear()


func _reset() -> void:
	state = State.IDLE
	target_id = -1
	_queue.clear()
	_cooldown = 0


func _from_home() -> float:
	return body.global_position.distance_to(home)
