extends SceneTree
## Headless tests for combat, madra, cycling and techniques, and simulation determinism.
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
	_test_technique_costs_madra()
	_test_overdraw_exhausts()
	_test_exhaustion_limits()
	_test_enforcer()
	_test_cycling_rhythm()
	_test_cycling_regen()
	_test_technique_hits()

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
	var outcome := _melee(pair[0], pair[1], attack)
	_check(outcome[0] == Combat.Result.HIT, "unguarded attack hits")
	_check(pair[1].health == PlayerBody.MAX_HEALTH - attack.damage, "hit deals full damage")
	_check(pair[1].action == PlayerBody.Action.HITSTUN, "hit causes hitstun")
	_check(pair[1].velocity.z < 0.0, "hit knocks target away")
	_free(pair)


func _test_block_and_backstab() -> void:
	var pair := _pair()
	var attack := Attacks.get_attack(Attacks.LIGHT_1)
	_hold_block(pair[1], PlayerBody.PARRY_WINDOW + 3)
	var outcome := _melee(pair[0], pair[1], attack)
	_check(outcome[0] == Combat.Result.BLOCKED, "frontal attack is blocked")
	_check(pair[1].health > PlayerBody.MAX_HEALTH - attack.damage, "block reduces damage")
	_check(pair[1].action == PlayerBody.Action.BLOCK, "blocker keeps blocking")

	pair[1].facing = 0.0  # Now facing away from the attacker.
	outcome = _melee(pair[0], pair[1], attack)
	_check(outcome[0] == Combat.Result.HIT, "block doesn't stop attacks from behind")
	_free(pair)


func _test_parry() -> void:
	var pair := _pair()
	_hold_block(pair[1], 2)
	var outcome := _melee(pair[0], pair[1], Attacks.get_attack(Attacks.LIGHT_1))
	_check(outcome[0] == Combat.Result.PARRIED, "early block parries")
	_check(pair[1].health == PlayerBody.MAX_HEALTH, "parry takes no damage")
	_check(pair[0].action == PlayerBody.Action.STAGGER, "parry staggers the attacker")
	_free(pair)


func _test_guard_break() -> void:
	var pair := _pair()
	_hold_block(pair[1], PlayerBody.PARRY_WINDOW + 3)
	var outcome := _melee(pair[0], pair[1], Attacks.get_attack(Attacks.HEAVY))
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
		var presses := [0, PlayerInput.LIGHT, PlayerInput.DODGE, PlayerInput.JUMP, PlayerInput.HEAVY,
			PlayerInput.technique_button(0), PlayerInput.technique_button(1), PlayerInput.technique_button(2),
			PlayerInput.technique_button(3), PlayerInput.CYCLE]
		var input := _input(presses[i * 7 % presses.size()] if i % 6 == 0 else 0)
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
	var input := _input(PlayerInput.LIGHT | PlayerInput.BLOCK | PlayerInput.LOCKED | PlayerInput.technique_button(3))
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


func _test_technique_costs_madra() -> void:
	var body := _body(Vector3.ZERO, 0.0)
	var lance := Techniques.get_technique(Techniques.EMBER_LANCE)
	_step(body, _input(PlayerInput.technique_button(Techniques.EMBER_LANCE)))
	_check(body.action == PlayerBody.Action.TECHNIQUE, "technique key starts a cast")
	_check(body.madra == PlayerBody.MAX_MADRA - lance.cost * PlayerBody.MADRA_SCALE + PlayerBody.PASSIVE_REGEN,
		"casting spends the technique's cost up front (then that tick's regen)")
	var released := -1
	for i in lance.total_ticks():
		_step(body, _input())
		if body.released_technique >= 0:
			released = body.released_technique
	_check(released == Techniques.EMBER_LANCE, "technique releases after its startup")
	_check(body.action == PlayerBody.Action.NONE, "cast ends after recovery")
	body.free()


func _test_overdraw_exhausts() -> void:
	var body := _body(Vector3.ZERO, 0.0)
	body.madra = 5 * PlayerBody.MADRA_SCALE
	_step(body, _input(PlayerInput.technique_button(Techniques.SEARING_RING)))
	_check(body.action == PlayerBody.Action.TECHNIQUE, "overdrawing still casts")
	_check(body.madra == 0 and body.is_exhausted(), "overdrawing empties madra and exhausts")
	body.free()


func _test_exhaustion_limits() -> void:
	var body := _body(Vector3.ZERO, 0.0)
	body.madra = 0
	body.exhaust_ticks = PlayerBody.EXHAUST_TICKS
	_step(body, _input(PlayerInput.DODGE))
	_check(body.action != PlayerBody.Action.DODGE, "exhausted artists can't dodge")
	_step(body, _input(PlayerInput.BLOCK))
	_check(body.action != PlayerBody.Action.BLOCK, "exhausted artists can't block")
	_step(body, _input(PlayerInput.technique_button(Techniques.EMBER_LANCE)))
	_check(body.action != PlayerBody.Action.TECHNIQUE, "exhausted artists can't cast")
	_check(body.madra == 0, "no regen while exhausted")
	for i in PlayerBody.EXHAUST_TICKS:
		_step(body, _input())
	_check(not body.is_exhausted() and body.madra > 0, "exhaustion wears off and regen resumes")
	body.free()


func _test_enforcer() -> void:
	var body := _body(Vector3.ZERO, 0.0)
	var flame_body := Techniques.get_technique(Techniques.FLAME_BODY)
	_step(body, _input(PlayerInput.technique_button(Techniques.FLAME_BODY)))
	for i in flame_body.total_ticks():
		_step(body, _input())
	_check(body.enforcer_active, "Flame Body turns on")
	var before := body.madra
	for i in 30:
		_step(body, _input())
	_check(body.madra == before - 30 * PlayerBody.ENFORCER_DRAIN, "an active Enforcer drains madra every tick")
	var spec := Combat.melee_spec(body, Attacks.get_attack(Attacks.LIGHT_1))
	_check(spec.damage == roundi(Attacks.get_attack(Attacks.LIGHT_1).damage * Combat.ENFORCER_DAMAGE_MULT), "Flame Body strengthens melee")
	before = body.madra
	_step(body, _input(PlayerInput.technique_button(Techniques.FLAME_BODY)))
	for i in flame_body.total_ticks():
		_step(body, _input())
	_check(not body.enforcer_active, "casting Flame Body again turns it off")
	_check(body.madra >= before - flame_body.total_ticks() * PlayerBody.ENFORCER_DRAIN, "turning it off costs nothing")
	body.madra = PlayerBody.ENFORCER_DRAIN
	body.enforcer_active = true
	_step(body, _input())
	_check(not body.enforcer_active and body.is_exhausted(), "draining dry ends the Enforcer and exhausts")
	body.free()


func _test_cycling_rhythm() -> void:
	var body := _body(Vector3.ZERO, 0.0)
	var beat := PlayerBody.CYCLE_BEAT_TICKS
	_step(body, _input(PlayerInput.CYCLE))
	_check(body.action == PlayerBody.Action.CYCLE, "cycle key starts cycling")
	for n in 3:  # Breathe right on three beats.
		while body.action_tick < (n + 1) * beat - 1:
			_step(body, _input())
		_step(body, _input(PlayerInput.CYCLE))
	_check(body.flow == 3, "breathing on the beat builds flow (got %d)" % body.flow)

	while body.action_tick < 4 * beat + PlayerBody.CYCLE_WINDOW + 2:
		_step(body, _input())
	_check(body.flow == 2, "skipping a beat loses one flow (got %d)" % body.flow)

	while body.action_tick < 4 * beat + beat / 2:
		_step(body, _input())
	_step(body, _input(PlayerInput.CYCLE))
	_check(body.flow == 0, "an off-beat breath breaks flow")

	var held := _input()
	held.set_move(Vector2(0, -1))
	_step(body, held)
	_check(body.action == PlayerBody.Action.NONE, "moving stops cycling")
	body.free()


func _test_cycling_regen() -> void:
	var resting := _body(Vector3.ZERO, 0.0)
	var cycling := _body(Vector3(5, 0, 0), 0.0)
	resting.madra = 0
	cycling.madra = 0
	_step(cycling, _input(PlayerInput.CYCLE))
	_step(resting, _input())
	for i in 90:
		_step(resting, _input())
		_step(cycling, _input())
	_check(cycling.madra > resting.madra * 3, "cycling regenerates far faster than resting")
	_free([resting, cycling])


func _test_technique_hits() -> void:
	var pair := _pair()
	_hold_block(pair[1], PlayerBody.PARRY_WINDOW + 3)
	var ring := HitSpec.from_technique(Techniques.get_technique(Techniques.SEARING_RING))
	var outcome := Combat.resolve(pair[0], pair[1], ring, pair[0].global_position)
	_check(outcome[0] == Combat.Result.HIT, "Ruler bursts can't be blocked")

	var fresh := _pair()
	_hold_block(fresh[1], 2)
	var lance := HitSpec.from_technique(Techniques.get_technique(Techniques.EMBER_LANCE))
	outcome = Combat.resolve(fresh[0], fresh[1], lance, fresh[0].global_position)
	_check(outcome[0] == Combat.Result.BLOCKED, "techniques can be blocked but never parried")

	var tired := _pair()
	tired[1].exhaust_ticks = PlayerBody.EXHAUST_TICKS
	var attack := Attacks.get_attack(Attacks.LIGHT_1)
	outcome = _melee(tired[0], tired[1], attack)
	_check(outcome[1] == roundi(attack.damage * Combat.EXHAUSTED_DAMAGE_TAKEN_MULT), "exhausted artists take extra damage")
	_free(pair + fresh + tired)


# --- Helpers ------------------------------------------------------------------------

## Attacker at the origin facing -Z, target 1.5 m in front facing the attacker.
func _pair() -> Array:
	return [_body(Vector3.ZERO, 0.0), _body(Vector3(0, 0, -1.5), PI)]


func _melee(attacker: PlayerBody, target: PlayerBody, attack: AttackData) -> Array:
	return Combat.resolve(attacker, target, Combat.melee_spec(attacker, attack), attacker.global_position)


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
