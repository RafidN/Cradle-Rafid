class_name GameServer
extends Node
## Authoritative zone server. Clients only send inputs; the server simulates every
## fighter, resolves hits with lag compensation, and sends each client a snapshot of the
## world every tick.

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


class ClientSession:
	var peer_id := 0
	var display_name := ""
	var body: PlayerBody
	var inputs: Array[PlayerInput] = []
	var newest_input_tick := 0
	var last_processed_tick := 0
	var input_credit := 0.0


class Dummy:
	var body: PlayerBody
	var home := Vector3.ZERO
	var input := PlayerInput.new()


## Print every hit (noisy; for debugging).
var log_hits := false

var _sessions := {}  # peer_id -> ClientSession
var _dummies: Array[Dummy] = []
var _names := {}  # entity_id -> display name, for every fighter
var _hit_history := HitHistory.new()
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
	_spawn_dummies()
	print("[server] Listening on UDP port %d (protocol v%d, %d Hz)" % [port, Protocol.VERSION, Protocol.TICK_RATE])
	return OK


func _physics_process(delta: float) -> void:
	_tick += 1
	for session: ClientSession in _sessions.values():
		session.input_credit = minf(session.input_credit + 1.0, MAX_INPUT_CREDIT)
		while session.input_credit >= 1.0 and not session.inputs.is_empty():
			var input: PlayerInput = session.inputs.pop_front()
			session.body.simulate(input, delta)
			session.last_processed_tick = input.tick
			session.input_credit -= 1.0
			_resolve_attack(session.body, input.view_tick)
	for dummy in _dummies:
		dummy.body.simulate(dummy.input, delta)

	for body: PlayerBody in _entities.get_children():
		var dead_long_enough := body.is_dead() and body.action_tick >= PlayerBody.RESPAWN_TICKS
		if dead_long_enough or body.global_position.y < KILL_Y:
			_respawn(body)

	_hit_history.record(_tick, _entities.get_children())
	_send_snapshots()
	if _tick % Protocol.TICK_RATE == 0:
		_status.text = "SERVER  |  port %d  |  tick %d  |  %d / %d players" % [
			_port, _tick, _sessions.size(), Protocol.MAX_PLAYERS]


## Checks the attacker's live hitbox against every other fighter, rewound to where the
## attacker saw them. Each attack hits a given target at most once.
func _resolve_attack(attacker: PlayerBody, view_tick: float) -> void:
	var attack := attacker.active_attack()
	if attack == null:
		return
	var rewind_to := clampf(view_tick, _tick - MAX_REWIND_TICKS, _tick - 1)
	for target: PlayerBody in _entities.get_children():
		if target == attacker or target.is_dead() or attacker.hit_targets.has(target.entity_id):
			continue
		var past := _hit_history.sample(target.entity_id, rewind_to)
		var seen_at: Vector3 = past.position if not past.is_empty() else target.global_position
		if not Combat.hitbox_overlaps(attacker.global_position, attacker.facing, attack, seen_at):
			continue
		# A dodge counts if it was active where the attacker saw it or on the server now.
		if target.is_invulnerable() or past.get("invulnerable", false):
			continue
		attacker.hit_targets[target.entity_id] = true
		var outcome := Combat.resolve(attacker, target, attack)
		var at := target.global_position + Vector3.UP * 1.6
		_broadcast(Protocol.encode_hit(attacker.entity_id, target.entity_id, outcome[0], outcome[1], at), false)
		if log_hits:
			print("[server] %s -> %s: %s %d (rewound %.1f ticks)" % [_names[attacker.entity_id],
				_names[target.entity_id], Combat.Result.keys()[outcome[0]], outcome[1], _tick - rewind_to])
		if target.is_dead():
			print("[server] %s defeated %s" % [_names[attacker.entity_id], _names[target.entity_id]])


func _send_snapshots() -> void:
	var bodies := _entities.get_children()
	for session: ClientSession in _sessions.values():
		var bytes := Protocol.encode_snapshot(_tick, session.last_processed_tick, session.body, bodies)
		_transport.send(session.peer_id, bytes, false)


func _broadcast(bytes: PackedByteArray, reliable: bool) -> void:
	for session: ClientSession in _sessions.values():
		_transport.send(session.peer_id, bytes, reliable)


func _on_packet(peer_id: int, bytes: PackedByteArray) -> void:
	var buf := Protocol.reader(bytes)
	var msg := buf.get_u8()
	if msg == Protocol.Msg.HELLO:
		_on_hello(peer_id, Protocol.decode_hello(buf))
	elif msg == Protocol.Msg.INPUT:
		_on_inputs(peer_id, Protocol.decode_inputs(buf))


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
	session.body = _spawn_body(display_name, _spawn_point(), 0.0)
	_sessions[peer_id] = session

	var body := session.body
	_transport.send(peer_id, Protocol.encode_welcome(body.entity_id, body.global_position, body.facing), true)
	for entity_id in _names:
		if entity_id != body.entity_id:
			_transport.send(peer_id, Protocol.encode_player_joined(entity_id, _names[entity_id]), true)
	for other: ClientSession in _sessions.values():
		if other != session:
			_transport.send(other.peer_id, Protocol.encode_player_joined(body.entity_id, display_name), true)
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


func _on_peer_disconnected(peer_id: int) -> void:
	var session: ClientSession = _sessions.get(peer_id)
	if session == null:
		return
	_sessions.erase(peer_id)
	var entity_id := session.body.entity_id
	_names.erase(entity_id)
	_entities.remove_child(session.body)
	session.body.queue_free()
	_broadcast(Protocol.encode_player_left(entity_id), true)
	print("[server] %s left. %d online." % [session.display_name, _sessions.size()])


func _reject(peer_id: int, reason: String) -> void:
	_transport.send(peer_id, Protocol.encode_reject(reason), true)
	await get_tree().create_timer(REJECT_GRACE_SECONDS).timeout
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


func _spawn_dummies() -> void:
	for config: Dictionary in DUMMIES:
		var dummy := Dummy.new()
		dummy.home = config.position
		dummy.body = _spawn_body(config.name, dummy.home, DUMMY_FACING)
		if config.block:
			dummy.input.buttons = PlayerInput.BLOCK
		_dummies.append(dummy)


func _spawn_body(display_name: String, at: Vector3, facing: float) -> PlayerBody:
	var body: PlayerBody = PLAYER_SCENE.instantiate()
	body.entity_id = _next_entity_id
	body.name = "Fighter%d" % _next_entity_id
	_next_entity_id += 1
	_entities.add_child(body)
	body.respawn(at, facing)
	_names[body.entity_id] = display_name
	return body


func _respawn(body: PlayerBody) -> void:
	for dummy in _dummies:
		if dummy.body == body:
			body.respawn(dummy.home, DUMMY_FACING)
			return
	body.respawn(_spawn_point(), body.facing)


func _spawn_point() -> Vector3:
	return Vector3(randf_range(-4.0, 4.0), 0.5, randf_range(2.0, 6.0))
