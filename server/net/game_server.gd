class_name GameServer
extends Node
## Authoritative zone server. Clients only send inputs; the server simulates every
## fighter (players, training dummies and sacred beasts), resolves hits with lag
## compensation, runs technique effects and remnants, owns each player's progression,
## and sends each client a snapshot of the world every tick.

const PLAYER_SCENE := preload("res://shared/sim/player_body.tscn")
## Queued inputs beyond this are dropped so a client can't bank movement.
const MAX_QUEUED_INPUTS := 8
## Ticks of input a stalled client may catch up on at once. Over time a client can never
## act more than one input per tick, which stops speed hacks.
const MAX_INPUT_CREDIT := 4.0
## Furthest back a hit check may rewind targets (12 ticks = 400 ms).
const MAX_REWIND_TICKS := 12
const KILL_Y := -30.0
const REJECT_GRACE_SECONDS := 0.5
const DUMMIES := [
	{"name": "Training Dummy", "position": Vector3(-3.0, 0.5, -3.0), "block": false},
	{"name": "Guarding Dummy", "position": Vector3(3.0, 0.5, -3.0), "block": true},
]
## Dummies face +Z, toward where players spawn.
const DUMMY_FACING := PI
const BEAST_TEAM := 1
## Where sacred beasts make their dens.
const BEAST_DENS := [
	{"species": Beasts.EMBER_HOUND, "position": Vector3(-18.0, 0.5, 14.0)},
	{"species": Beasts.EMBER_HOUND, "position": Vector3(-22.0, 0.5, 20.0)},
	{"species": Beasts.GALE_FOX, "position": Vector3(-20.0, 0.5, -18.0)},
	{"species": Beasts.GALE_FOX, "position": Vector3(-14.0, 0.5, -23.0)},
	{"species": Beasts.STONEBACK_BOAR, "position": Vector3(20.0, 0.5, 18.0)},
	{"species": Beasts.STONEBACK_BOAR, "position": Vector3(22.0, 0.5, -16.0)},
]


class ClientSession:
	var peer_id := 0
	var display_name := ""
	var body: PlayerBody
	var progress := ProgressState.new()
	var inputs: Array[PlayerInput] = []
	var newest_input_tick := 0
	var last_processed_tick := 0
	var input_credit := 0.0
	var interacting := false


class Dummy:
	var body: PlayerBody
	var home := Vector3.ZERO
	var input := PlayerInput.new()


class Beast:
	var body: PlayerBody
	var brain: BeastBrain
	var species := 0


## Print every hit (noisy; for debugging).
var log_hits := false
## Multiplies essence from remnants, to test progression quickly.
var essence_mult := 1

var _sessions := {}  # peer_id -> ClientSession
var _dummies: Array[Dummy] = []
var _beasts: Array[Beast] = []
var _info := {}  # entity_id -> {name, kind, species, rank}, for every fighter
var _hit_history := HitHistory.new()
var _effects := TechniqueEffects.new()
var _remnants := RemnantField.new()
var _tick := 0
var _next_entity_id := 1
var _port := 0

@onready var _transport: NetTransport = $NetTransport
@onready var _entities: Node3D = $World/Entities
@onready var _status: Label = $Debug/Status


func start(port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, Protocol.MAX_PLAYERS)
	if err != OK:
		return err
	(multiplayer as SceneMultiplayer).server_relay = false
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_transport.packet_received.connect(_on_packet)
	_port = port
	_effects.hit_history = _hit_history
	_effects.max_rewind_ticks = MAX_REWIND_TICKS
	_effects.land_hit = _land_hit
	_effects.burst = func(caster_id: int, technique_id: int, at: Vector3) -> void:
		_broadcast(Protocol.encode_burst(caster_id, technique_id, at), false)
	_spawn_dummies()
	_spawn_beasts()
	print("[server] Listening on UDP port %d (protocol v%d, %d Hz)" % [port, Protocol.VERSION, Protocol.TICK_RATE])
	return OK


func _physics_process(delta: float) -> void:
	_tick += 1
	var bodies := _entities.get_children()
	for session: ClientSession in _sessions.values():
		session.input_credit = minf(session.input_credit + 1.0, MAX_INPUT_CREDIT)
		while session.input_credit >= 1.0 and not session.inputs.is_empty():
			var input: PlayerInput = session.inputs.pop_front()
			session.body.simulate(input, delta)
			session.last_processed_tick = input.tick
			session.input_credit -= 1.0
			session.interacting = input.is_pressed(PlayerInput.INTERACT)
			_after_simulate(session.body, input.view_tick, bodies)
	var artists := _artist_bodies()
	for beast in _beasts:
		beast.body.simulate(beast.brain.think(artists), delta)
		_after_simulate(beast.body, _tick - 1, bodies)
	for dummy in _dummies:
		dummy.body.simulate(dummy.input, delta)
	_effects.update(_tick, bodies, _entities.get_world_3d().direct_space_state)
	_update_remnants()

	for body: PlayerBody in bodies:
		if body.global_position.y < KILL_Y or (body.is_dead() and body.action_tick >= _respawn_ticks(body)):
			_respawn(body)

	_hit_history.record(_tick, bodies)
	_send_snapshots()
	if _tick % Protocol.TICK_RATE == 0:
		_status.text = "SERVER  |  port %d  |  tick %d  |  %d / %d players  |  %d remnants" % [
			_port, _tick, _sessions.size(), Protocol.MAX_PLAYERS, _remnants.count()]


## Melee hits and technique releases for a fighter that just simulated a tick.
func _after_simulate(body: PlayerBody, view_tick: float, bodies: Array) -> void:
	_resolve_attack(body, view_tick)
	if body.released_technique >= 0:
		_effects.release(body, body.released_technique, _tick, view_tick, bodies)


## Checks the attacker's live hitbox against every other fighter, rewound to where the
## attacker saw them. Each attack hits a given target at most once.
func _resolve_attack(attacker: PlayerBody, view_tick: float) -> void:
	var attack := attacker.active_attack()
	if attack == null:
		return
	var rewind_to := clampf(view_tick, _tick - MAX_REWIND_TICKS, _tick - 1)
	for target: PlayerBody in _entities.get_children():
		if target == attacker or target.is_dead() or attacker.hit_targets.has(target.entity_id) \
				or not Combat.can_harm(attacker, target):
			continue
		var past := _hit_history.sample(target.entity_id, rewind_to)
		var seen_at: Vector3 = past.position if not past.is_empty() else target.global_position
		if not Combat.hitbox_overlaps(attacker.global_position, attacker.facing, attack, seen_at):
			continue
		# A dodge counts if it was active where the attacker saw it or on the server now.
		if target.is_invulnerable() or past.get("invulnerable", false):
			continue
		attacker.hit_targets[target.entity_id] = true
		_land_hit(attacker, target, Combat.melee_spec(attacker, attack), attacker.global_position, -1)


## Resolves a landed hit, tells every client, and handles a kill. technique_id is -1
## for melee.
func _land_hit(attacker: PlayerBody, target: PlayerBody, spec: HitSpec, origin: Vector3, technique_id: int) -> void:
	var outcome := Combat.resolve(attacker, target, spec, origin)
	var attacker_id := attacker.entity_id if attacker else 0
	var at := target.global_position + Vector3.UP * 1.6
	_broadcast(Protocol.encode_hit(attacker_id, target.entity_id, outcome[0], outcome[1], at), false)
	var beast := _beast_of(target)
	if beast:
		beast.brain.on_hit(attacker)
	if log_hits:
		var source := "melee" if technique_id < 0 else Techniques.get_technique(technique_id).display_name
		print("[server] %s -> %s: %s %d (%s)" % [_name_of(attacker_id), _name_of(target.entity_id),
			Combat.Result.keys()[outcome[0]], outcome[1], source])
	if target.is_dead():
		_on_killed(target, attacker)


## The fallen leave remnants: beasts of their aspect, sacred artists of their Path's.
## Whoever landed the killing blow gets first claim, if they're a sacred artist.
func _on_killed(target: PlayerBody, killer: PlayerBody) -> void:
	var killer_id := killer.entity_id if killer else 0
	print("[server] %s defeated %s" % [_name_of(killer_id), _name_of(target.entity_id)])
	var owner := killer_id if _session_of(killer) else 0
	var beast := _beast_of(target)
	if beast:
		var data := Beasts.get_beast(beast.species)
		_remnants.spawn(target.global_position, data.aspect, data.essence * essence_mult, owner, data.display_name)
	elif _session_of(target):
		_remnants.spawn(target.global_position, Advancement.ARTIST_REMNANT_ASPECT,
			Advancement.ARTIST_REMNANT_ESSENCE * essence_mult, owner, _name_of(target.entity_id))


func _update_remnants() -> void:
	var claimants := []
	for session: ClientSession in _sessions.values():
		claimants.append({"body": session.body, "interacting": session.interacting})
	for claim in _remnants.update(claimants):
		var session := _session_by_entity(claim[0])
		var remnant: RemnantField.Remnant = claim[1]
		session.progress.add_essence(remnant.aspect, remnant.essence)
		_send_progress(session)
		_notify(session, "Claimed the remnant of %s: +%d %s essence" % [
			remnant.source_name, remnant.essence, Advancement.ASPECT_NAMES[remnant.aspect].to_lower()])


func _send_snapshots() -> void:
	var bodies := _entities.get_children()
	var effects := _effects.snapshot_entries() + _remnants.snapshot_entries()
	for session: ClientSession in _sessions.values():
		var claim := _remnants.progress_of(session.body.entity_id)
		var bytes := Protocol.encode_snapshot(_tick, session.last_processed_tick, session.body, bodies, effects, claim)
		_transport.send(session.peer_id, bytes, false)


func _broadcast(bytes: PackedByteArray, reliable: bool) -> void:
	for session: ClientSession in _sessions.values():
		_transport.send(session.peer_id, bytes, reliable)


# --- Packets ------------------------------------------------------------------------

func _on_packet(peer_id: int, bytes: PackedByteArray) -> void:
	var buf := Protocol.reader(bytes)
	var msg := buf.get_u8()
	if msg == Protocol.Msg.HELLO:
		_on_hello(peer_id, Protocol.decode_hello(buf))
	elif msg == Protocol.Msg.INPUT:
		_on_inputs(peer_id, Protocol.decode_inputs(buf))
	elif msg == Protocol.Msg.REQUEST:
		_on_request(peer_id, Protocol.decode_request(buf))


func _on_hello(peer_id: int, hello: Dictionary) -> void:
	if _sessions.has(peer_id):
		return
	if hello.is_empty() or hello.version != Protocol.VERSION:
		_reject(peer_id, "Version mismatch: server runs protocol v%d" % Protocol.VERSION)
		return

	var display_name := String(hello.name).strip_edges().left(Protocol.MAX_NAME_LENGTH)
	if display_name.is_empty():
		display_name = "Artist"
	var session := ClientSession.new()
	session.peer_id = peer_id
	session.display_name = display_name
	session.body = _spawn_body(display_name, Protocol.EntityKind.ARTIST, -1)
	session.progress.apply_to(session.body)
	session.body.respawn(_spawn_point(), 0.0)
	_sessions[peer_id] = session
	_set_rank_info(session)

	var body := session.body
	_transport.send(peer_id, Protocol.encode_welcome(body.entity_id, body.global_position, body.facing), true)
	_send_progress(session)
	for entity_id in _info:
		if entity_id != body.entity_id:
			_transport.send(peer_id, _encode_info(entity_id), true)
	for other: ClientSession in _sessions.values():
		if other != session:
			_transport.send(other.peer_id, _encode_info(body.entity_id), true)
	print("[server] %s joined (peer %d, entity %d). %d online." % [
		display_name, peer_id, body.entity_id, _sessions.size()])


func _on_inputs(peer_id: int, inputs: Array[PlayerInput]) -> void:
	var session: ClientSession = _sessions.get(peer_id)
	if session == null:
		return
	for input in inputs:
		if input.tick <= session.newest_input_tick:
			continue  # Already received in an earlier packet's redundant copy.
		session.newest_input_tick = input.tick
		session.inputs.append(input)
	while session.inputs.size() > MAX_QUEUED_INPUTS:
		session.inputs.pop_front()


func _on_request(peer_id: int, request: Dictionary) -> void:
	var session: ClientSession = _sessions.get(peer_id)
	if session == null or request.is_empty():
		return
	var progress := session.progress
	match request.request:
		Protocol.Request.CRAFT_BINDING:
			var error := progress.craft_error(request.argument)
			if not error.is_empty():
				_notify(session, error)
				return
			progress.craft(request.argument)
			progress.apply_to(session.body)
			_send_progress(session)
			_notify(session, "Crafted: %s" % Advancement.BINDINGS[request.argument].name)
		Protocol.Request.ADVANCE:
			var error := progress.advance_error(session.body.action == PlayerBody.Action.CYCLE)
			if not error.is_empty():
				_notify(session, error)
				return
			progress.advance()
			progress.apply_to(session.body)
			session.body.health = session.body.max_health  # A breakthrough restores the body.
			_send_progress(session)
			_set_rank_info(session)
			_broadcast(_encode_info(session.body.entity_id), true)
			var rank_name := Advancement.rank_name(progress.rank)
			_notify(session, "Breakthrough! You have advanced to %s" % rank_name)
			for other: ClientSession in _sessions.values():
				if other != session:
					_notify(other, "%s has advanced to %s" % [session.display_name, rank_name])
			print("[server] %s advanced to %s" % [session.display_name, rank_name])


func _on_peer_disconnected(peer_id: int) -> void:
	var session: ClientSession = _sessions.get(peer_id)
	if session == null:
		return
	_sessions.erase(peer_id)
	var entity_id := session.body.entity_id
	_info.erase(entity_id)
	_effects.remove_owned_by(entity_id)
	_remnants.remove_owner(entity_id)
	_entities.remove_child(session.body)
	session.body.queue_free()
	_broadcast(Protocol.encode_entity_left(entity_id), true)
	print("[server] %s left. %d online." % [session.display_name, _sessions.size()])


func _reject(peer_id: int, reason: String) -> void:
	_transport.send(peer_id, Protocol.encode_reject(reason), true)
	await get_tree().create_timer(REJECT_GRACE_SECONDS).timeout
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


func _send_progress(session: ClientSession) -> void:
	_transport.send(session.peer_id, Protocol.encode_progress(session.progress), true)


func _notify(session: ClientSession, text: String) -> void:
	_transport.send(session.peer_id, Protocol.encode_notice(text), true)


# --- Fighters -----------------------------------------------------------------------

func _spawn_dummies() -> void:
	for config: Dictionary in DUMMIES:
		var dummy := Dummy.new()
		dummy.home = config.position
		dummy.body = _spawn_body(config.name, Protocol.EntityKind.DUMMY, -1)
		dummy.body.respawn(dummy.home, DUMMY_FACING)
		dummy.input.set_yaw(DUMMY_FACING)  # Fighters turn to face their input yaw.
		if config.block:
			dummy.input.buttons = PlayerInput.BLOCK
		_dummies.append(dummy)


func _spawn_beasts() -> void:
	for den: Dictionary in BEAST_DENS:
		var data := Beasts.get_beast(den.species)
		var beast := Beast.new()
		beast.species = den.species
		beast.body = _spawn_body(data.display_name, Protocol.EntityKind.BEAST, den.species)
		beast.body.apply_stats(data.max_health, PlayerBody.MAX_MADRA, PlayerInput.TECHNIQUE_COUNT,
			data.damage_mult, data.knockback_taken_mult, data.speed_mult)
		beast.body.team = BEAST_TEAM
		beast.body.respawn(den.position, randf() * TAU)
		beast.brain = BeastBrain.new(data, beast.body, den.position, beast.body.entity_id)
		_beasts.append(beast)


func _spawn_body(display_name: String, kind: Protocol.EntityKind, species: int) -> PlayerBody:
	var body: PlayerBody = PLAYER_SCENE.instantiate()
	body.entity_id = _next_entity_id
	body.name = "Fighter%d" % _next_entity_id
	_next_entity_id += 1
	_entities.add_child(body)
	_info[body.entity_id] = {"name": display_name, "kind": kind, "species": species, "rank": 0}
	return body


func _respawn(body: PlayerBody) -> void:
	for dummy in _dummies:
		if dummy.body == body:
			body.respawn(dummy.home, DUMMY_FACING)
			return
	var beast := _beast_of(body)
	if beast:
		body.respawn(beast.brain.home, randf() * TAU)
		return
	body.respawn(_spawn_point(), body.facing)


func _respawn_ticks(body: PlayerBody) -> int:
	var beast := _beast_of(body)
	return Beasts.get_beast(beast.species).respawn_ticks if beast else PlayerBody.RESPAWN_TICKS


func _spawn_point() -> Vector3:
	return Vector3(randf_range(-4.0, 4.0), 0.5, randf_range(2.0, 6.0))


func _set_rank_info(session: ClientSession) -> void:
	_info[session.body.entity_id].rank = session.progress.rank


func _encode_info(entity_id: int) -> PackedByteArray:
	var info: Dictionary = _info[entity_id]
	return Protocol.encode_entity_info(entity_id, info.name, info.kind, info.species, info.rank)


func _artist_bodies() -> Array:
	return _sessions.values().map(func(s: ClientSession): return s.body)


func _beast_of(body: PlayerBody) -> Beast:
	for beast in _beasts:
		if beast.body == body:
			return beast
	return null


func _session_of(body: PlayerBody) -> ClientSession:
	if body == null:
		return null
	return _session_by_entity(body.entity_id)


func _session_by_entity(entity_id: int) -> ClientSession:
	for session: ClientSession in _sessions.values():
		if session.body.entity_id == entity_id:
			return session
	return null


func _name_of(entity_id: int) -> String:
	return _info.get(entity_id, {}).get("name", "?")
