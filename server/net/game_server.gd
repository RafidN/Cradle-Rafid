class_name GameServer
extends Node
## Authoritative zone server. Clients only send inputs; the server simulates every
## player and sends each client a snapshot of the world every tick.

const PLAYER_SCENE := preload("res://shared/sim/player_body.tscn")
## Queued inputs beyond this are dropped so a client can't bank movement.
const MAX_QUEUED_INPUTS := 8
## Ticks of input a stalled client may catch up on at once. Over time a client can never
## move more than one input per tick, which stops speed hacks.
const MAX_INPUT_CREDIT := 4.0
const KILL_Y := -30.0
const REJECT_GRACE_SECONDS := 0.5


class ClientSession:
	var peer_id := 0
	var display_name := ""
	var body: PlayerBody
	var inputs: Array[PlayerInput] = []
	var newest_input_tick := 0
	var last_processed_tick := 0
	var input_credit := 0.0


var _sessions := {}  # peer_id -> ClientSession
var _tick := 0
var _next_entity_id := 1
var _port := 0

@onready var _transport: NetTransport = $NetTransport
@onready var _players: Node3D = $World/Players
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
		if session.body.global_position.y < KILL_Y:
			session.body.set_state(_spawn_point(), Vector3.ZERO, session.body.facing)
	_send_snapshots()
	if _tick % Protocol.TICK_RATE == 0:
		_status.text = "SERVER  |  port %d  |  tick %d  |  %d / %d players" % [
			_port, _tick, _sessions.size(), Protocol.MAX_PLAYERS]


func _send_snapshots() -> void:
	var bodies := _players.get_children()
	for session: ClientSession in _sessions.values():
		var bytes := Protocol.encode_snapshot(_tick, session.last_processed_tick, session.body, bodies)
		_transport.send(session.peer_id, bytes, false)


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

	var session := ClientSession.new()
	session.peer_id = peer_id
	session.display_name = String(hello.name).strip_edges().left(Protocol.MAX_NAME_LENGTH)
	if session.display_name.is_empty():
		session.display_name = "Artist"
	session.body = PLAYER_SCENE.instantiate()
	session.body.entity_id = _next_entity_id
	session.body.name = "Player%d" % _next_entity_id
	_next_entity_id += 1
	_players.add_child(session.body)
	session.body.set_state(_spawn_point(), Vector3.ZERO, 0.0)
	_sessions[peer_id] = session

	var body := session.body
	_transport.send(peer_id, Protocol.encode_welcome(body.entity_id, body.global_position, body.facing), true)
	for other: ClientSession in _sessions.values():
		if other == session:
			continue
		_transport.send(peer_id, Protocol.encode_player_joined(other.body.entity_id, other.display_name), true)
		_transport.send(other.peer_id, Protocol.encode_player_joined(body.entity_id, session.display_name), true)
	print("[server] %s joined (peer %d, entity %d). %d online." % [
		session.display_name, peer_id, body.entity_id, _sessions.size()])


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
	session.body.queue_free()
	for other: ClientSession in _sessions.values():
		_transport.send(other.peer_id, Protocol.encode_player_left(entity_id), true)
	print("[server] %s left. %d online." % [session.display_name, _sessions.size()])


func _reject(peer_id: int, reason: String) -> void:
	_transport.send(peer_id, Protocol.encode_reject(reason), true)
	await get_tree().create_timer(REJECT_GRACE_SECONDS).timeout
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


func _spawn_point() -> Vector3:
	return Vector3(randf_range(-4.0, 4.0), 0.5, randf_range(2.0, 6.0))
