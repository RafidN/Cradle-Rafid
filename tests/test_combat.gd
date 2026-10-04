extends SceneTree
## Headless tests for combat, spirit, meditating and techniques, and simulation determinism.
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

	_test_all_scripts_compile()
	_test_no_borrowed_terms()
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
	_test_technique_costs_spirit()
	_test_overdraw_exhausts()
	_test_exhaustion_limits()
	_test_enforcer()
	_test_meditation_rhythm()
	_test_meditation_regen()
	_test_technique_hits()
	_test_faces_camera()
	_test_move_cancels_recovery()
	_test_progression_rules()
	_test_rank_stats()
	_test_stat_multipliers()
	_test_echo_claiming()
	_test_beast_brain()
	_test_interest()
	_test_remote_entry_encoding()
	_test_content_data()
	_test_save_migration()
	_test_notice_messages()

	print("\n%s" % ("ALL TESTS PASSED" if _failures == 0 else "%d FAILURE(S)" % _failures))
	quit(1 if _failures > 0 else 0)


## Loads every script in the project, so client/server code these tests never run still
## has to compile.
func _test_all_scripts_compile() -> void:
	var broken := []
	for path in _scripts_under("res://"):
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			broken.append(path)
	_check(broken.is_empty(), "every script compiles%s" % ("" if broken.is_empty() else " (broken: %s)" % [broken]))


## The game uses only its own vocabulary (docs/ROADMAP.md, Lexicon). Fails if a term or
## name borrowed from the books it started from comes back into code, data or docs.
## Only distinctive terms are listed, so ordinary words like "foundation" or "iron" are fine.
func _test_no_borrowed_terms() -> void:
	var borrowed := RegEx.create_from_string("(?i)\\b(madra|remnants?|cycling|sacred (art|artist|artists|beast|beasts)|"
		+ "(?<!key)(?<!re)bindings?|lowgold|highgold|true gold|underlord|overlord|archlord|"
		+ "path of (black|the)|will wight|cradle (series|books?)|blackflame|lindon|yerin|eithan|orthos|sophara)\\b"
		+ "|\\b(Striker|Ruler|Forger)s?\\b")
	var found := []
	for path in _files_under("res://", ["gd", "tscn", "tres", "godot", "md", "ts", "sh"]):
		if path == "res://tests/test_combat.gd":
			continue  # This list.
		var text := FileAccess.get_file_as_string(path)
		for match in borrowed.search_all(text):
			found.append("%s: %s" % [path.trim_prefix("res://"), match.get_string()])
	_check(found.is_empty(), "no borrowed terms in code, data or docs%s" % ("" if found.is_empty() else " %s" % [found]))


func _files_under(dir_path: String, extensions: Array) -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	for sub in dir.get_directories():
		if not sub.begins_with(".") and sub not in ["node_modules", "data", "dist"]:
			found.append_array(_files_under(dir_path.path_join(sub), extensions))
	for file in dir.get_files():
		if file.get_extension() in extensions:
			found.append(dir_path.path_join(file))
	return found


func _scripts_under(dir_path: String) -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	for sub in dir.get_directories():
		if not sub.begins_with("."):
			found.append_array(_scripts_under(dir_path.path_join(sub)))
	for file in dir.get_files():
		if file.get_extension() == "gd":
			found.append(dir_path.path_join(file))
	return found


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
			PlayerInput.technique_button(3), PlayerInput.MEDITATE]
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


func _test_technique_costs_spirit() -> void:
	var body := _body(Vector3.ZERO, 0.0)
	var lance := Techniques.get_technique(Techniques.EMBER_LANCE)
	_step(body, _input(PlayerInput.technique_button(Techniques.EMBER_LANCE)))
	_check(body.action == PlayerBody.Action.TECHNIQUE, "technique key starts a cast")
	_check(body.spirit == PlayerBody.MAX_SPIRIT - lance.cost * PlayerBody.SPIRIT_SCALE + PlayerBody.PASSIVE_REGEN,
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
	body.spirit = 5 * PlayerBody.SPIRIT_SCALE
	_step(body, _input(PlayerInput.technique_button(Techniques.SEARING_RING)))
	_check(body.action == PlayerBody.Action.TECHNIQUE, "overdrawing still casts")
	_check(body.spirit == 0 and body.is_exhausted(), "overdrawing empties spirit and exhausts")
	body.free()


func _test_exhaustion_limits() -> void:
	var body := _body(Vector3.ZERO, 0.0)
	body.spirit = 0
	body.exhaust_ticks = PlayerBody.EXHAUST_TICKS
	_step(body, _input(PlayerInput.DODGE))
	_check(body.action != PlayerBody.Action.DODGE, "exhausted practitioners can't dodge")
	_step(body, _input(PlayerInput.BLOCK))
	_check(body.action != PlayerBody.Action.BLOCK, "exhausted practitioners can't block")
	_step(body, _input(PlayerInput.technique_button(Techniques.EMBER_LANCE)))
	_check(body.action != PlayerBody.Action.TECHNIQUE, "exhausted practitioners can't cast")
	_check(body.spirit == 0, "no regen while exhausted")
	for i in PlayerBody.EXHAUST_TICKS:
		_step(body, _input())
	_check(not body.is_exhausted() and body.spirit > 0, "exhaustion wears off and regen resumes")
	body.free()


func _test_enforcer() -> void:
	var body := _body(Vector3.ZERO, 0.0)
	var flame_body := Techniques.get_technique(Techniques.FLAME_BODY)
	_step(body, _input(PlayerInput.technique_button(Techniques.FLAME_BODY)))
	for i in flame_body.total_ticks():
		_step(body, _input())
	_check(body.enforcer_active, "Flame Body turns on")
	var before := body.spirit
	for i in 30:
		_step(body, _input())
	_check(body.spirit == before - 30 * PlayerBody.ENFORCER_DRAIN, "an active Enforcer drains spirit every tick")
	var spec := Combat.melee_spec(body, Attacks.get_attack(Attacks.LIGHT_1))
	_check(spec.damage == roundi(Attacks.get_attack(Attacks.LIGHT_1).damage * Combat.ENFORCER_DAMAGE_MULT), "Flame Body strengthens melee")
	before = body.spirit
	_step(body, _input(PlayerInput.technique_button(Techniques.FLAME_BODY)))
	for i in flame_body.total_ticks():
		_step(body, _input())
	_check(not body.enforcer_active, "casting Flame Body again turns it off")
	_check(body.spirit >= before - flame_body.total_ticks() * PlayerBody.ENFORCER_DRAIN, "turning it off costs nothing")
	body.spirit = PlayerBody.ENFORCER_DRAIN
	body.enforcer_active = true
	_step(body, _input())
	_check(not body.enforcer_active and body.is_exhausted(), "draining dry ends the Enforcer and exhausts")
	body.exhaust_ticks = 0
	body.spirit = body.spirit_capacity
	body.enforcer_active = true
	_step(body, _input(PlayerInput.MEDITATE))
	_check(body.action == PlayerBody.Action.MEDITATE and not body.enforcer_active, "meditating releases the Enforcer")
	body.free()


func _test_meditation_rhythm() -> void:
	var body := _body(Vector3.ZERO, 0.0)
	var beat := PlayerBody.BREATH_BEAT_TICKS
	_step(body, _input(PlayerInput.MEDITATE))
	_check(body.action == PlayerBody.Action.MEDITATE, "meditate key starts meditating")
	for n in 3:  # Breathe right on three beats.
		while body.action_tick < (n + 1) * beat - 1:
			_step(body, _input())
		_step(body, _input(PlayerInput.MEDITATE))
	_check(body.flow == 3, "breathing on the beat builds flow (got %d)" % body.flow)

	while body.action_tick < 4 * beat + PlayerBody.BREATH_WINDOW + 2:
		_step(body, _input())
	_check(body.flow == 2, "skipping a beat loses one flow (got %d)" % body.flow)

	while body.action_tick < 4 * beat + beat / 2:
		_step(body, _input())
	_step(body, _input(PlayerInput.MEDITATE))
	_check(body.flow == 0, "an off-beat breath breaks flow")

	var held := _input()
	held.set_move(Vector2(0, -1))
	_step(body, held)
	_check(body.action == PlayerBody.Action.NONE, "moving stops meditating")
	body.free()


func _test_meditation_regen() -> void:
	var resting := _body(Vector3.ZERO, 0.0)
	var meditating := _body(Vector3(5, 0, 0), 0.0)
	resting.spirit = 0
	meditating.spirit = 0
	_step(meditating, _input(PlayerInput.MEDITATE))
	_step(resting, _input())
	for i in 90:
		_step(resting, _input())
		_step(meditating, _input())
	_check(meditating.spirit > resting.spirit * 3, "meditating regenerates far faster than resting")
	_free([resting, meditating])


func _test_technique_hits() -> void:
	var pair := _pair()
	_hold_block(pair[1], PlayerBody.PARRY_WINDOW + 3)
	var ring := HitSpec.from_technique(Techniques.get_technique(Techniques.SEARING_RING))
	var outcome := Combat.resolve(pair[0], pair[1], ring, pair[0].global_position)
	_check(outcome[0] == Combat.Result.HIT, "Controller bursts can't be blocked")

	var fresh := _pair()
	_hold_block(fresh[1], 2)
	var lance := HitSpec.from_technique(Techniques.get_technique(Techniques.EMBER_LANCE))
	outcome = Combat.resolve(fresh[0], fresh[1], lance, fresh[0].global_position)
	_check(outcome[0] == Combat.Result.BLOCKED, "techniques can be blocked but never parried")

	var tired := _pair()
	tired[1].exhaust_ticks = PlayerBody.EXHAUST_TICKS
	var attack := Attacks.get_attack(Attacks.LIGHT_1)
	outcome = _melee(tired[0], tired[1], attack)
	_check(outcome[1] == roundi(attack.damage * Combat.EXHAUSTED_DAMAGE_TAKEN_MULT), "exhausted practitioners take extra damage")
	_free(pair + fresh + tired)


func _test_faces_camera() -> void:
	var body := _body(Vector3.ZERO, 0.0)
	var look_left := _input()
	look_left.set_yaw(PI * 0.5)
	for i in 10:
		_step(body, look_left)
	_check(absf(angle_difference(body.facing, look_left.get_yaw())) < 0.01, "the fighter turns to face the camera")

	var backpedal := _input()
	backpedal.set_yaw(PI * 0.5)
	backpedal.set_move(Vector2(0, 1))
	for i in 10:
		_step(body, backpedal)
	_check(absf(angle_difference(body.facing, backpedal.get_yaw())) < 0.01, "moving backward keeps facing the camera")

	var swing := _input(PlayerInput.LIGHT)
	swing.set_yaw(-PI * 0.5)
	swing.set_move(Vector2(0, 1))  # Holding back while attacking used to turn around.
	_step(body, swing)
	_check(absf(angle_difference(body.facing, swing.get_yaw())) < 0.01, "attacks go where the camera looks")
	body.free()


func _test_move_cancels_recovery() -> void:
	var body := _body(Vector3.ZERO, 0.0)
	var attack := Attacks.get_attack(Attacks.HEAVY)
	_step(body, _input(PlayerInput.HEAVY))
	var move := _input()
	move.set_move(Vector2(0, -1))
	while body.action_tick < attack.startup + attack.active:
		_step(body, move)
	_check(body.action == PlayerBody.Action.ATTACK, "moving doesn't cancel startup or active ticks")
	for i in attack.recovery:
		_step(body, move)
		if body.action != PlayerBody.Action.ATTACK:
			break
	_check(body.action == PlayerBody.Action.NONE and body.action_tick < attack.total_ticks(),
		"moving cancels the back half of recovery")
	body.free()


func _test_progression_rules() -> void:
	var progress := ProgressState.new()
	_check(not progress.advance_error(true).is_empty(), "can't advance without essence")
	progress.add_essence(Advancement.Aspect.FIRE, 40)
	progress.add_essence(Advancement.Aspect.WIND, 25)
	_check(not progress.advance_error(false).is_empty(), "can't break through unless meditating")
	_check(progress.advance_error(true).is_empty(), "enough essence of any aspect reaches Bronze")
	progress.advance()
	_check(progress.rank == Advancement.Rank.BRONZE, "advancing raises the rank")
	_check(progress.total_essence() == 5 and progress.essence[Advancement.Aspect.FIRE] == 0,
		"advancing spends essence from the largest pools first (left %s)" % progress.essence)

	progress.add_essence(Advancement.Aspect.EARTH, 200)
	_check(Text.render(progress.advance_error(true)).contains("Tempered Body"), "Silver needs a Tempered Body Sigil")
	_check(not progress.craft_error(Advancement.Sigil.TEMPERED_BODY).is_empty(), "sigils need every aspect in their cost")
	progress.add_essence(Advancement.Aspect.FIRE, 50)
	progress.craft(Advancement.Sigil.TEMPERED_BODY)
	_check(progress.sigils[Advancement.Sigil.TEMPERED_BODY] == 1 and progress.essence[Advancement.Aspect.FIRE] == 30,
		"crafting spends its cost and adds the sigil")
	_check(not progress.craft_error(Advancement.Sigil.TEMPERED_BODY).is_empty(), "sigils have a cap")
	progress.advance()
	_check(progress.rank == Advancement.Rank.SILVER and progress.sigils[Advancement.Sigil.TEMPERED_BODY] == 0,
		"advancing to Silver consumes the sigil")
	_check(not progress.advance_error(true).is_empty(), "nothing above Silver yet")

	var buf := StreamPeerBuffer.new()
	progress.encode(buf)
	buf.seek(0)
	var decoded := ProgressState.decode(buf)
	_check(decoded.rank == progress.rank and decoded.essence == progress.essence and decoded.sigils == progress.sigils,
		"progress survives the wire")


func _test_rank_stats() -> void:
	var body := _body(Vector3.ZERO, 0.0)
	var progress := ProgressState.new()
	progress.apply_to(body)
	body.respawn(Vector3.ZERO, 0.0)
	_step(body, _input(PlayerInput.technique_button(Techniques.SEARING_RING)))
	_check(body.action != PlayerBody.Action.TECHNIQUE, "Iron can't cast a Bronze technique")
	_step(body, _input(PlayerInput.technique_button(Techniques.EMBER_LANCE)))
	_check(body.action == PlayerBody.Action.TECHNIQUE, "Iron can cast its own techniques")

	progress.rank = Advancement.Rank.SILVER
	progress.sigils[Advancement.Sigil.KINDLED_CORE] = 2
	progress.apply_to(body)
	body.respawn(Vector3.ZERO, 0.0)
	_check(body.max_health == 160 and body.health == 160, "Silver raises max health")
	var core_bonus := Advancement.sigil(Advancement.Sigil.KINDLED_CORE).spirit_capacity_bonus
	_check(core_bonus > 0 and body.spirit_capacity == (160 + 2 * core_bonus) * PlayerBody.SPIRIT_SCALE,
		"Kindled Cores add spirit capacity")
	for i in 30:
		_step(body, _input())
	_check(body.spirit <= body.spirit_capacity, "spirit never exceeds capacity")
	body.free()


func _test_stat_multipliers() -> void:
	var pair := _pair()
	var attack := Attacks.get_attack(Attacks.LIGHT_1)
	pair[0].damage_mult = 2.0
	pair[1].knockback_taken_mult = 0.0
	var outcome := _melee(pair[0], pair[1], attack)
	_check(outcome[1] == attack.damage * 2, "attacker damage multiplier applies")
	_check(is_zero_approx(pair[1].velocity.x) and is_zero_approx(pair[1].velocity.z), "knockback resistance applies")
	pair[0].team = 1
	_check(Combat.can_harm(pair[0], pair[1]), "beasts can hurt practitioners")
	pair[1].team = 1
	_check(not Combat.can_harm(pair[0], pair[1]), "beasts can't hurt each other")
	pair[0].team = 0
	pair[1].team = 0
	_check(Combat.can_harm(pair[0], pair[1]) and Combat.can_harm(pair[1], pair[0]), "practitioners can fight each other")
	_free(pair)


func _test_echo_claiming() -> void:
	var killer := _body(Vector3.ZERO, 0.0)
	var rival := _body(Vector3(0.5, 0, 0), 0.0)
	killer.entity_id = 1
	rival.entity_id = 2
	var field := EchoField.new()
	field.spawn(Vector3(1, 0, 0), Advancement.Aspect.EARTH, 30, 1, "Stoneback Boar")

	var done := []
	for i in 30:
		done += field.update([{"body": rival, "interacting": true}])
	_check(done.is_empty() and field.progress_of(2) == 0.0, "only the killer may claim at first")

	for i in EchoField.CLAIM_TICKS - 10:
		done += field.update([{"body": killer, "interacting": true}])
	field.update([{"body": killer, "interacting": false}])
	_check(field.progress_of(1) == 0.0, "letting go of interact resets the claim")

	for i in EchoField.CLAIM_TICKS:
		done += field.update([{"body": killer, "interacting": true}])
	_check(done.size() == 1 and done[0][0] == 1 and done[0][1].essence == 30, "holding interact long enough claims it")
	_check(field.count() == 0, "a claimed echo is gone")

	field.spawn(Vector3(1, 0, 0), Advancement.Aspect.FIRE, 6, 1, "Somebody")
	for i in EchoField.EXCLUSIVE_TICKS:
		field.update([])
	done = []
	for i in EchoField.CLAIM_TICKS:
		done += field.update([{"body": rival, "interacting": true}])
	_check(done.size() == 1 and done[0][0] == 2, "anyone may claim once exclusivity ends")

	field.spawn(Vector3(1, 0, 0), Advancement.Aspect.FIRE, 6, 0, "Nobody")
	for i in EchoField.LIFETIME_TICKS:
		field.update([])
	_check(field.count() == 0, "unclaimed echoes fade")
	_free([killer, rival])


func _test_beast_brain() -> void:
	var data := Beasts.get_beast(Beasts.EMBER_HOUND)
	var beast := _body(Vector3.ZERO, 0.0)
	beast.apply_stats(data.max_health, PlayerBody.MAX_SPIRIT, 4, data.damage_mult, data.knockback_taken_mult, data.speed_mult)
	beast.respawn(Vector3.ZERO, 0.0)
	var brain := BeastBrain.new(data, beast, Vector3.ZERO, 7)
	var far := _body(Vector3(0, 0, -(data.aggro_range + 5.0)), 0.0)
	far.entity_id = 50
	brain.think([far])
	_check(brain.state == BeastBrain.State.IDLE, "beasts ignore practitioners beyond aggro range")

	var near := _body(Vector3(0, 0, -1.5), PI)
	near.entity_id = 51
	var attacked := false
	for i in 120:
		var input := brain.think([near])
		_step(beast, input)
		attacked = attacked or input.is_pressed(PlayerInput.LIGHT) or input.is_pressed(PlayerInput.HEAVY) \
			or input.is_pressed(PlayerInput.DODGE)
	_check(brain.state == BeastBrain.State.HUNT and brain.target_id == 51, "beasts hunt practitioners that come close")
	_check(attacked, "hunting beasts attack in melee range")

	brain.on_hit(far)
	_check(brain.target_id == 50, "being hit makes a beast hunt the attacker")
	beast.global_position = Vector3(0, 0, data.leash_range + 2.0)
	beast.health = 10
	brain.think([near, far])
	_check(brain.state == BeastBrain.State.RETURN, "beasts led past their leash return home")
	beast.global_position = Vector3(0.5, 0, 0)
	brain.think([near, far])
	_check(brain.state == BeastBrain.State.IDLE and beast.health == beast.max_health, "beasts heal once home")
	_free([beast, far, near])


func _test_interest() -> void:
	var interest := Interest.new()
	var ids := PackedInt32Array([1, 2, 3])
	var positions := PackedVector3Array([Vector3(5, 0, 0), Vector3(40, 0, 0), Vector3(60, 0, 0)])
	var seen := {}
	for tick in Interest.FAR_INTERVAL:
		for i in interest.select(Vector3.ZERO, ids, positions, tick):
			seen[ids[i]] = seen.get(ids[i], 0) + 1
	_check(seen.get(1, 0) == Interest.FAR_INTERVAL, "near fighters are sent every tick")
	_check(seen.get(2, 0) == 1, "far fighters are sent every %d ticks" % Interest.FAR_INTERVAL)
	_check(not seen.has(3), "fighters beyond the enter radius aren't sent")

	positions[1] = Vector3(60, 0, 0)  # Already in view: stays until LEAVE_RADIUS.
	var still_seen := false
	for tick in Interest.FAR_INTERVAL:
		still_seen = still_seen or Array(interest.select(Vector3.ZERO, ids, positions, tick)).has(1)
	_check(still_seen, "a fighter in view stays in view past the enter radius (hysteresis)")
	positions[1] = Vector3(70, 0, 0)
	interest.select(Vector3.ZERO, ids, positions, 0)
	positions[1] = Vector3(60, 0, 0)
	var back := false
	for tick in Interest.FAR_INTERVAL:
		back = back or Array(interest.select(Vector3.ZERO, ids, positions, tick)).has(1)
	_check(not back, "once out of view, it has to come back inside the enter radius")


func _test_remote_entry_encoding() -> void:
	var body := _body(Vector3(-37.123, 2.5, 71.987), 1.234)
	body.entity_id = 4321
	body.health = 77
	body.enforcer_active = true
	var snapshot_body := _body(Vector3.ZERO, 0.0)
	var entry := Protocol.encode_remote_entry(body)
	_check(entry.size() == Protocol.REMOTE_ENTRY_SIZE, "remote entries are %d bytes" % Protocol.REMOTE_ENTRY_SIZE)
	var effect := {"id": 1 << 24, "kind": Protocol.Effect.ECHO, "owner": 4321, "position": Vector3(1.5, 0.9, -3.25),
		"velocity": Vector3(0, 0, -24), "armed": true, "data": 2}
	var effect_entry := Protocol.encode_effect_entry(effect)
	_check(effect_entry.size() == Protocol.EFFECT_ENTRY_SIZE, "effect entries are %d bytes" % Protocol.EFFECT_ENTRY_SIZE)
	var bytes := Protocol.encode_snapshot(9, 8, snapshot_body, [entry], [effect_entry], 0.0)
	var buf := Protocol.reader(bytes)
	buf.get_u8()
	var snapshot := Protocol.decode_snapshot(buf)
	var decoded: Dictionary = snapshot.others[0]
	var decoded_effect: Dictionary = snapshot.effects[0]
	_check(decoded_effect.id == effect.id and decoded_effect.owner == 4321 and decoded_effect.data == 2
		and decoded_effect.position.distance_to(effect.position) < 1.0 / Protocol.POSITION_SCALE
		and decoded_effect.velocity.distance_to(effect.velocity) < 1.0 / Protocol.POSITION_SCALE,
		"effect entry fields survive the wire")
	_check(decoded.id == 4321 and decoded.health == 77 and decoded.flags & PlayerBody.FLAG_ENFORCER,
		"remote entry fields survive the wire")
	_check(decoded.position.distance_to(body.global_position) < 1.0 / Protocol.POSITION_SCALE,
		"positions are accurate to 1/%d m" % Protocol.POSITION_SCALE)
	_check(absf(angle_difference(decoded.facing, body.facing)) < TAU / 256.0, "facing is accurate to 1/256 turn")
	_free([body, snapshot_body])


## Every piece of content loads, has unique ids, and every reference between content
## (combo chains, beast techniques, rank sigils, Way techniques, zone dens and portals)
## points at something that exists.
func _test_content_data() -> void:
	var problems := PackedStringArray()
	var registries := {"attacks": Attacks.registry, "techniques": Techniques.registry, "beasts": Beasts.registry,
		"ranks": Advancement.ranks, "sigils": Advancement.sigils, "ways": Ways.registry, "zones": Zones.registry}
	for kind: String in registries:
		var registry: ContentRegistry = registries[kind]
		problems.append_array(registry.errors)
		if registry.size() == 0:
			problems.append("no %s found" % kind)
	# Ranks and sigils are indexed by net id, so their net ids must run 0, 1, 2...
	for kind in ["ranks", "sigils"]:
		var registry: ContentRegistry = registries[kind]
		for i in registry.size():
			if registry.all[i].net_id != i:
				problems.append("%s net ids must run 0..%d without gaps" % [kind, registry.size() - 1])
				break

	# Constants the code uses must name the right content.
	var named := {
		Attacks.registry: {Attacks.LIGHT_1: &"light_1", Attacks.LIGHT_2: &"light_2", Attacks.LIGHT_3: &"light_3", Attacks.HEAVY: &"heavy"},
		Techniques.registry: {Techniques.FLAME_BODY: &"flame_body", Techniques.EMBER_LANCE: &"ember_lance",
			Techniques.SEARING_RING: &"searing_ring", Techniques.CINDER_TRAP: &"cinder_trap"},
		Beasts.registry: {Beasts.EMBER_HOUND: &"ember_hound", Beasts.STONEBACK_BOAR: &"stoneback_boar", Beasts.GALE_FOX: &"gale_fox"},
		Advancement.ranks: {Advancement.Rank.IRON: &"iron", Advancement.Rank.BRONZE: &"bronze", Advancement.Rank.SILVER: &"silver"},
		Advancement.sigils: {Advancement.Sigil.TEMPERED_BODY: &"tempered_body", Advancement.Sigil.KINDLED_CORE: &"kindled_core"},
	}
	for registry: ContentRegistry in named:
		for net_id: int in named[registry]:
			var item := registry.by_net_id(net_id)
			if item == null or item.id != named[registry][net_id]:
				problems.append("%s: net id %d should be '%s'" % [registry.folder, net_id, named[registry][net_id]])

	for attack: AttackData in Attacks.registry.all:
		if attack.combo_next != &"" and Attacks.registry.by_id(attack.combo_next) == null:
			problems.append("attack %s chains into unknown '%s'" % [attack.id, attack.combo_next])
	for beast: BeastData in Beasts.registry.all:
		for technique_id in [beast.close_technique, beast.ranged_technique]:
			if technique_id != &"" and Techniques.registry.by_id(technique_id) == null:
				problems.append("beast %s uses unknown technique '%s'" % [beast.id, technique_id])
			elif technique_id != &"" and not Ways.loadout(Ways.DEFAULT).has(Techniques.registry.net_id_of(technique_id)):
				problems.append("beast %s uses '%s', which isn't in the beasts' loadout" % [beast.id, technique_id])
	for rank: RankData in Advancement.ranks.all:
		if rank.required_sigil != &"" and Advancement.sigils.by_id(rank.required_sigil) == null:
			problems.append("rank %s requires unknown sigil '%s'" % [rank.id, rank.required_sigil])
	for sigil: SigilData in Advancement.sigils.all:
		if sigil.cost.size() != Advancement.ASPECT_NAMES.size():
			problems.append("sigil %s needs a cost for each aspect" % sigil.id)
	for way: WayData in Ways.registry.all:
		if way.techniques.size() != PlayerInput.TECHNIQUE_COUNT:
			problems.append("way %s needs %d techniques" % [way.id, PlayerInput.TECHNIQUE_COUNT])
		for technique_id in way.techniques:
			if Techniques.registry.by_id(technique_id) == null:
				problems.append("way %s teaches unknown technique '%s'" % [way.id, technique_id])
	if Ways.get_way(Ways.DEFAULT) == null:
		problems.append("the default Way '%s' doesn't exist" % Ways.DEFAULT)

	if Zones.get_zone(Zones.DEFAULT) == null:
		problems.append("the default zone '%s' doesn't exist" % Zones.DEFAULT)
	for zone: ZoneData in Zones.registry.all:
		if not ResourceLoader.exists(zone.scene_path):
			problems.append("zone %s: missing scene" % zone.id)
		if not zone.spawns.has("default"):
			problems.append("zone %s: no default spawn" % zone.id)
		for den in zone.dens:
			if Beasts.by_id(den.species) == null:
				problems.append("zone %s: den for unknown species '%s'" % [zone.id, den.species])
		for portal in zone.portals:
			var target := Zones.get_zone(portal.to_zone)
			if target == null or not target.spawns.has(portal.to_spawn):
				problems.append("zone %s: portal to unknown %s/%s" % [zone.id, portal.to_zone, portal.to_spawn])
			for spawn: Vector3 in zone.spawns.values():
				if Vector2(spawn.x - portal.position.x, spawn.z - portal.position.z).length() < portal.radius + 3.0:
					problems.append("zone %s: a spawn point is inside a portal" % zone.id)
	_check(problems.is_empty(), "content is consistent%s" % ("" if problems.is_empty() else " %s" % [problems]))


func _test_notice_messages() -> void:
	var msg := Text.message("Claimed the echo of %s: +%d %s essence", ["Ember Hound", 12, "Fire"])
	var buf := Protocol.reader(Protocol.encode_notice(msg))
	buf.get_u8()
	var decoded := Protocol.decode_notice(buf)
	_check(decoded == msg, "notices carry their message key and typed args over the wire")
	_check(Text.render(decoded) == "Claimed the echo of Ember Hound: +12 Fire essence", "messages render to text")
	_check(Text.render([]) == "", "an empty message renders as nothing")


func _test_save_migration() -> void:
	var old := {"rank": 1, "essence": [5, 6, 7], "sigils": [1, 2]}  # A version 1 save.
	var migrated := ProgressState.from_dict(old)
	_check(migrated.rank == Advancement.Rank.BRONZE and migrated.essence == PackedInt32Array([5, 6, 7])
		and migrated.sigils[Advancement.Sigil.TEMPERED_BODY] == 1 and migrated.sigils[Advancement.Sigil.KINDLED_CORE] == 2,
		"version 1 saves load (rank and sigils by position)")
	var saved := migrated.to_dict()
	_check(saved.version == ProgressState.SAVE_VERSION and saved.rank == "bronze" and saved.sigils.get("kindled_core") == 2,
		"saves store ranks and sigils by id")
	var reloaded := ProgressState.from_dict(JSON.parse_string(JSON.stringify(saved)))
	_check(reloaded.rank == migrated.rank and reloaded.sigils == migrated.sigils and reloaded.essence == migrated.essence,
		"a save survives a round trip through JSON")
	_check(ProgressState.from_dict({}).rank == Advancement.Rank.IRON, "an empty save is a new Iron practitioner")


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


## Blocks while looking the way the body already faces (fighters turn toward their yaw).
func _hold_block(body: PlayerBody, ticks: int) -> void:
	var input := _input(PlayerInput.BLOCK)
	input.set_yaw(body.facing)
	for i in ticks:
		_step(body, input)


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
