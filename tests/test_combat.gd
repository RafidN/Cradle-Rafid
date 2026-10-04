extends SceneTree
## Headless tests for combat rules and simulation determinism.
## Run: godot --headless --path . --script res://tests/test_combat.gd

const PLAYER_SCENE := preload("res://shared/sim/player_body.tscn")
const DT := 1.0 / Protocol.TICK_RATE

var _failures := 0
var _floor: StaticBody3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_floor = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	shape.shape = box
	shape.position.y = -0.5
	_floor.add_child(shape)
	root.add_child(_floor)
	await physics_frame
	await physics_frame

	_test_hitbox_geometry()
	_test_clean_hit()
	_test_block_and_backstab()
	_test_parry()
	_test_guard_break()
	_test_dodge_iframes()
	_test_light_combo_chains()
	_test_death()
	_test_replay_matches()
	_test_input_roundtrip()

	print("\n%s" % ("ALL TESTS PASSED" if _failures == 0 else "%d FAILURE(S)" % _failures))
	quit(1 if _failures > 0 else 0)


func _test_hitbox_geometry() -> void:
	var attack := Attacks.get_attack(Attacks.LIGHT_1)
	_check(Combat.hitbox_overlaps(Vector3.ZERO, 0.0, attack, Vector3(0, 0, -1.5)), "hitbox reaches target in front")
	_check(not Combat.hitbox_overlaps(Vector3.ZERO, 0.0, attack, Vector3(0, 0, 1.5)), "hitbox misses target behind")
	_check(not Combat.hitbox_overlaps(Vector3.ZERO, 0.0, attack, Vector3(0, 0, -4.0)), "hitbox misses distant target")
	_check(Combat.hitbox_overlaps(Vector3.ZERO, PI * 0.5, attack, Vector3(-1.5, 0, 0)), "hitbox follows facing")


func _test_clean_hit() -> void:
	var pair := _pair()
	var attack := Attacks.get_attack(Attacks.LIGHT_1)
	var outcome := Combat.resolve(pair[0], pair[1], attack)
	_check(outcome[0] == Combat.Result.HIT, "unguarded attack hits")
	_check(pair[1].health == PlayerBody.MAX_HEALTH - attack.damage, "hit deals full damage")
	_check(pair[1].action == PlayerBody.Action.HITSTUN, "hit causes hitstun")
	_check(pair[1].velocity.z < 0.0, "hit knocks target away")
	_free(pair)


func _test_block_and_backstab() -> void:
	var pair := _pair()
	var attack := Attacks.get_attack(Attacks.LIGHT_1)
	_hold_block(pair[1], PlayerBody.PARRY_WINDOW + 3)
	var outcome := Combat.resolve(pair[0], pair[1], attack)
	_check(outcome[0] == Combat.Result.BLOCKED, "frontal attack is blocked")
	_check(pair[1].health > PlayerBody.MAX_HEALTH - attack.damage, "block reduces damage")
	_check(pair[1].action == PlayerBody.Action.BLOCK, "blocker keeps blocking")

	pair[1].facing = 0.0  # Now facing away from the attacker.
	outcome = Combat.resolve(pair[0], pair[1], attack)
	_check(outcome[0] == Combat.Result.HIT, "block doesn't stop attacks from behind")
	_free(pair)


func _test_parry() -> void:
	var pair := _pair()
	_hold_block(pair[1], 2)
	var outcome := Combat.resolve(pair[0], pair[1], Attacks.get_attack(Attacks.LIGHT_1))
	_check(outcome[0] == Combat.Result.PARRIED, "early block parries")
	_check(pair[1].health == PlayerBody.MAX_HEALTH, "parry takes no damage")
	_check(pair[0].action == PlayerBody.Action.STAGGER, "parry staggers the attacker")
	_free(pair)


func _test_guard_break() -> void:
	var pair := _pair()
	_hold_block(pair[1], PlayerBody.PARRY_WINDOW + 3)
	var outcome := Combat.resolve(pair[0], pair[1], Attacks.get_attack(Attacks.HEAVY))
	_check(outcome[0] == Combat.Result.GUARD_BROKEN, "heavy breaks a block")
	_check(pair[1].action == PlayerBody.Action.STAGGER, "guard break staggers the blocker")
	_free(pair)


func _test_dodge_iframes() -> void:
	var body := _body(Vector3.ZERO, 0.0)
	_step(body, _input(PlayerInput.DODGE))
	var invulnerable_ticks := 0
	for i in PlayerBody.DODGE_TICKS + 2:
		if body.is_invulnerable():
			invulnerable_ticks += 1
		_step(body, _input())
	var expected := PlayerBody.DODGE_IFRAME_END - PlayerBody.DODGE_IFRAME_START + 1
	_check(invulnerable_ticks == expected, "dodge is invulnerable for %d ticks (got %d)" % [expected, invulnerable_ticks])
	_check(body.action == PlayerBody.Action.NONE, "dodge ends")
	body.free()


func _test_light_combo_chains() -> void:
	var body := _body(Vector3.ZERO, 0.0)
	var seen := []
	for i in 80:
		_step(body, _input(PlayerInput.LIGHT if i % 4 == 0 else 0))
		if body.action == PlayerBody.Action.ATTACK and (seen.is_empty() or seen[-1] != body.action_id):
			seen.append(body.action_id)
	_check(seen.slice(0, 3) == [Attacks.LIGHT_1, Attacks.LIGHT_2, Attacks.LIGHT_3],
		"mashing light chains 1 -> 2 -> 3 (got %s)" % [seen])
	body.free()


func _test_death() -> void:
	var pair := _pair()
	pair[1].apply_damage(PlayerBody.MAX_HEALTH)
	_check(pair[1].is_dead() and pair[1].is_invulnerable(), "zero health kills and the dead can't be hit")
	pair[1].apply_hitstun(10, Vector3.ONE)
	_check(pair[1].is_dead(), "hitstun doesn't revive the dead")
	pair[1].respawn(Vector3(0, 0, 5), 0.0)
	_check(pair[1].health == PlayerBody.MAX_HEALTH and not pair[1].is_dead(), "respawn restores the fighter")
	_free(pair)


## The client's rewind-and-replay must land exactly where straight simulation does.
func _test_replay_matches() -> void:
	var inputs: Array[PlayerInput] = []
	for i in 90:
		var input := _input([0, PlayerInput.LIGHT, PlayerInput.DODGE, PlayerInput.JUMP, PlayerInput.HEAVY][i % 23 % 5] if i % 7 == 0 else 0)
		input.set_move(Vector2(sin(i * 0.2), -cos(i * 0.13)))
		input.set_yaw(i * 0.05)
		if i > 60:
			input.buttons |= PlayerInput.BLOCK
		inputs.append(input)

	var straight := _body(Vector3.ZERO, 0.0)
	for input in inputs:
		_step(straight, input)

	var replayed := _body(Vector3(20, 0, 0), 0.0)
	replayed.respawn(Vector3.ZERO, 0.0)
	var checkpoint := {}
	for i in inputs.size():
		_step(replayed, inputs[i])
		if i == 40:
			checkpoint = replayed.capture_state()
	replayed.restore_state(checkpoint)
	for i in range(41, inputs.size()):
		_step(replayed, inputs[i])

	_check(PlayerBody.states_match(straight.capture_state(), replayed.capture_state()), "rewind + replay matches straight simulation")
	straight.free()
	replayed.free()


func _test_input_roundtrip() -> void:
	var input := _input(PlayerInput.LIGHT | PlayerInput.BLOCK | PlayerInput.LOCKED)
	input.tick = 1234
	input.set_move(Vector2(0.7, -0.7))
	input.set_yaw(-2.0)
	input.set_aim(1.0)
	input.view_tick = 987.5
	var buf := StreamPeerBuffer.new()
	input.encode(buf)
	_check(buf.data_array.size() == PlayerInput.ENCODED_SIZE, "input encodes to ENCODED_SIZE bytes")
	buf.seek(0)
	var decoded := PlayerInput.decode(buf)
	_check(decoded.tick == 1234 and decoded.buttons == input.buttons, "input tick and buttons survive the wire")
	_check(decoded.get_move() == input.get_move() and decoded.get_yaw() == input.get_yaw() and decoded.get_aim() == input.get_aim(),
		"input move/yaw/aim survive the wire exactly")
	_check(is_equal_approx(decoded.view_tick, 987.5), "view tick survives the wire")


# --- Helpers ------------------------------------------------------------------------

## Attacker at the origin facing -Z, target 1.5 m in front facing the attacker.
func _pair() -> Array:
	return [_body(Vector3.ZERO, 0.0), _body(Vector3(0, 0, -1.5), PI)]


func _body(at: Vector3, facing: float) -> PlayerBody:
	var body: PlayerBody = PLAYER_SCENE.instantiate()
	root.add_child(body)
	body.respawn(at, facing)
	return body


func _hold_block(body: PlayerBody, ticks: int) -> void:
	for i in ticks:
		_step(body, _input(PlayerInput.BLOCK))


func _input(buttons := 0) -> PlayerInput:
	var input := PlayerInput.new()
	input.buttons = buttons
	return input


func _step(body: PlayerBody, input: PlayerInput) -> void:
	body.simulate(input, DT)


func _free(bodies: Array) -> void:
	for body: PlayerBody in bodies:
		body.free()


func _check(condition: bool, description: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + description)
	if not condition:
		_failures += 1
