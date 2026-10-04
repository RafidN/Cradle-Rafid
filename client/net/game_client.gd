class_name GameClient
extends Node
## Connects to a zone server, predicts the local player and interpolates everyone else.
##
## Local player: each tick's input is simulated immediately (prediction), stored, and sent
## to the server. Every snapshot says which input the server applied last. If the
## server's result for that input differs from the prediction, the client snaps to the
## server state and replays the inputs the server hasn't applied yet (reconciliation).
##
## Remote players: snapshots are buffered and rendered INTERP_DELAY_TICKS in the past,
## interpolating between the two snapshots either side of that time.

signal disconnected(reason: String)

const PLAYER_SCENE := preload("res://shared/sim/player_body.tscn")
const CAMERA_RIG_SCENE := preload("res://client/player/camera_rig.tscn")
const REMOTE_PLAYER_SCENE := preload("res://client/player/remote_player.tscn")

## How far behind the newest snapshot remote players are drawn (3 ticks = 100 ms).
const INTERP_DELAY_TICKS := 3.0
## Prediction error tolerated before correcting, in m and m/s.
const POSITION_EPSILON := 0.01
const VELOCITY_EPSILON := 0.05
## Unacknowledged inputs kept for replay (2 s at 30 Hz).
const MAX_HISTORY := 60
const STATS_PRINT_INTERVAL := 5.0

## Generate inputs automatically instead of reading devices (bots and load tests).
var bot := false

var _entity_id := 0
var _input_tick := 0
var _body: PlayerBody
var _camera_rig: CameraRig
var _history: Array[Dictionary] = []  # {input, position, velocity, facing}, oldest first
var _pending_snapshot := {}
var _newest_snapshot_tick := 0
var _last_ack := 0
var _server_time := -1.0  # Estimated tick of the newest snapshot, advanced every frame.
var _remotes := {}  # entity_id -> RemotePlayer
var _names := {}  # entity_id -> display name
var _display_name := ""
var _closed := false

# Stats for the debug overlay.
var _sent_at := {}  # input tick -> msec
var _rtt_ms := -1.0
var _corrections := 0
var _snapshots := 0
var _stats_timer := 0.0

@onready var _transport: NetTransport = $NetTransport
@onready var _world: Node3D = $World
@onready var _entities: Node3D = $World/Entities
@onready var _debug_label: Label = $HUD/Debug
@onready var _hint_label: Label = $HUD/Hint


func connect_to_server(host: String, port: int, display_name: String, conditioner: NetConditioner) -> Error:
	_display_name = display_name
	_transport.conditioner = conditioner
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_close.bind("Could not reach %s:%d" % [host, port]))
	multiplayer.server_disconnected.connect(_close.bind("Disconnected from server"))
	_transport.packet_received.connect(_on_packet)
	_debug_label.text = "Connecting to %s:%d..." % [host, port]
	_hint_label.visible = not bot
	return OK


func _exit_tree() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _close(reason: String) -> void:
	if _closed:
		return
	_closed = true
	disconnected.emit(reason)


func _on_connected() -> void:
	_transport.send(1, Protocol.encode_hello(_display_name), true)


func _on_packet(_peer_id: int, bytes: PackedByteArray) -> void:
	var buf := Protocol.reader(bytes)
	var msg := buf.get_u8()
	if msg == Protocol.Msg.SNAPSHOT:
		_on_snapshot(Protocol.decode_snapshot(buf))
	elif msg == Protocol.Msg.WELCOME:
		_on_welcome(Protocol.decode_welcome(buf))
	elif msg == Protocol.Msg.PLAYER_JOINED:
		var joined := Protocol.decode_player_joined(buf)
		_names[joined.id] = joined.name
		if _remotes.has(joined.id):
			_remotes[joined.id].set_display_name(joined.name)
	elif msg == Protocol.Msg.PLAYER_LEFT:
		var entity_id := buf.get_u32()
		_names.erase(entity_id)
		_remove_remote(entity_id)
	elif msg == Protocol.Msg.REJECT:
		_close(Protocol.decode_reject(buf))


func _on_welcome(welcome: Dictionary) -> void:
	if _body:
		return
	_entity_id = welcome.entity_id
	_body = PLAYER_SCENE.instantiate()
	_body.entity_id = _entity_id
	_body.name = "LocalPlayer"
	_world.add_child(_body)
	_body.set_state(welcome.position, Vector3.ZERO, welcome.facing)
	_body.reset_physics_interpolation()

	_camera_rig = CAMERA_RIG_SCENE.instantiate()
	_camera_rig.target = _body
	_camera_rig.capture_mouse = not bot
	_world.add_child(_camera_rig)
	_camera_rig.rotation.y = welcome.facing


func _on_snapshot(snapshot: Dictionary) -> void:
	if snapshot.tick <= _newest_snapshot_tick:
		return  # Late or duplicate; a newer one already arrived.
	_newest_snapshot_tick = snapshot.tick
	_snapshots += 1
	_pending_snapshot = snapshot  # Reconciled at the start of the next physics tick.

	if _server_time < 0.0 or absf(snapshot.tick - _server_time) > 10.0:
		_server_time = snapshot.tick
	else:
		_server_time = lerpf(_server_time, snapshot.tick, 0.1)

	var seen := {}
	for other: Dictionary in snapshot.others:
		seen[other.id] = true
		var remote: RemotePlayer = _remotes.get(other.id)
		if remote == null:
			remote = REMOTE_PLAYER_SCENE.instantiate()
			_entities.add_child(remote)
			remote.set_display_name(_names.get(other.id, "..."))
			_remotes[other.id] = remote
		remote.push_state(snapshot.tick, other.position, other.facing)
	for entity_id in _remotes.keys():
		if not seen.has(entity_id):
			_remove_remote(entity_id)


func _physics_process(delta: float) -> void:
	if _body == null:
		return
	if not _pending_snapshot.is_empty():
		_reconcile(_pending_snapshot, delta)
		_pending_snapshot = {}

	_input_tick += 1
	var input := _bot_input() if bot else _camera_rig.sample_input()
	input.tick = _input_tick
	_body.simulate(input, delta)
	_history.append({
		"input": input,
		"position": _body.global_position,
		"velocity": _body.velocity,
		"facing": _body.facing,
	})
	if _history.size() > MAX_HISTORY:
		_history.pop_front()

	_sent_at[_input_tick] = Time.get_ticks_msec()
	var recent := _history.slice(-Protocol.INPUT_REDUNDANCY).map(func(entry): return entry.input)
	_transport.send(1, Protocol.encode_inputs(recent), false)


func _reconcile(snapshot: Dictionary, delta: float) -> void:
	var ack: int = snapshot.ack
	if ack <= _last_ack:
		return  # The server hasn't applied any new input since the last check.
	_last_ack = ack

	if _sent_at.has(ack):
		var rtt: float = Time.get_ticks_msec() - _sent_at[ack]
		_rtt_ms = rtt if _rtt_ms < 0.0 else lerpf(_rtt_ms, rtt, 0.2)
	for tick in _sent_at.keys():
		if tick <= ack:
			_sent_at.erase(tick)

	var predicted := {}
	while not _history.is_empty() and _history[0].input.tick <= ack:
		predicted = _history.pop_front()
	if (not predicted.is_empty() and predicted.input.tick == ack
			and predicted.position.distance_to(snapshot.position) <= POSITION_EPSILON
			and predicted.velocity.distance_to(snapshot.velocity) <= VELOCITY_EPSILON):
		return

	_corrections += 1
	_body.set_state(snapshot.position, snapshot.velocity, snapshot.facing)
	for entry in _history:
		_body.simulate(entry.input, delta)
		entry.position = _body.global_position
		entry.velocity = _body.velocity
		entry.facing = _body.facing


func _process(delta: float) -> void:
	if _server_time >= 0.0:
		_server_time += delta * Protocol.TICK_RATE
		var render_tick := _server_time - INTERP_DELAY_TICKS
		for remote: RemotePlayer in _remotes.values():
			remote.render(render_tick)

	if _body:
		_debug_label.text = _stats_text()
	_stats_timer += delta
	if bot and _stats_timer >= STATS_PRINT_INTERVAL:
		_stats_timer = 0.0
		print("[client %s] %s" % [_display_name, _stats_text().replace("\n", "  |  ")])


func _stats_text() -> String:
	var lines := PackedStringArray([
		"%s (entity %d)  |  %d players visible" % [_display_name, _entity_id, _remotes.size() + 1],
		"Input RTT: %s" % ("%d ms" % _rtt_ms if _rtt_ms >= 0.0 else "-"),
		"Unacked inputs: %d" % _history.size(),
		"Corrections: %d" % _corrections,
		"Snapshots: %d" % _snapshots,
	])
	if _transport.conditioner:
		lines.append("Simulated network: %s" % _transport.conditioner.describe())
	return "\n".join(lines)


func _bot_input() -> PlayerInput:
	var input := PlayerInput.new()
	var t := _input_tick / float(Protocol.TICK_RATE) + _entity_id * 1.7
	input.set_move(Vector2(sin(t * 0.7), cos(t * 0.7)))
	if _input_tick % 45 == 0:
		input.buttons |= PlayerInput.JUMP
	return input


func _remove_remote(entity_id: int) -> void:
	var remote: RemotePlayer = _remotes.get(entity_id)
	if remote:
		remote.queue_free()
		_remotes.erase(entity_id)
