class_name GameClient
extends Node
## Connects to a zone server, predicts the local fighter and interpolates everyone else.
##
## Local fighter: each tick's input is simulated immediately (prediction), stored, and
## sent to the server. Every snapshot carries the server's full state for this fighter
## and the last input it applied. If that state differs from what was predicted for that
## input (a misprediction, or the server applied a hit), the client restores the server
## state and replays the inputs the server hasn't applied yet (reconciliation).
##
## Remote fighters: snapshots are buffered and drawn INTERP_DELAY_TICKS in the past,
## interpolating between the two snapshots either side of that time. Each input reports
## that time as its view tick so the server can rewind hit checks to match.

signal disconnected(reason: String)

const PLAYER_SCENE := preload("res://shared/sim/player_body.tscn")
const CAMERA_RIG_SCENE := preload("res://client/player/camera_rig.tscn")
const REMOTE_PLAYER_SCENE := preload("res://client/player/remote_player.tscn")

## How far behind the newest snapshot remote fighters are drawn (3 ticks = 100 ms).
const INTERP_DELAY_TICKS := 3.0
## Unacknowledged inputs kept for replay (2 s at 30 Hz).
const MAX_HISTORY := 60
const LOCK_RANGE := 20.0
const LOCK_BREAK_RANGE := 26.0
const STATS_PRINT_INTERVAL := 5.0
const BOT_AGGRO_RANGE := 30.0
const BOT_ATTACK_RANGE := 2.4

const RESULT_TEXT := {
	Combat.Result.HIT: "%d",
	Combat.Result.BLOCKED: "Blocked %d",
	Combat.Result.PARRIED: "PARRY!",
	Combat.Result.GUARD_BROKEN: "GUARD BREAK %d",
}

## Generate inputs automatically instead of reading devices (bots and load tests).
var bot := false

var _entity_id := 0
var _input_tick := 0
var _body: PlayerBody
var _camera_rig: CameraRig
var _history: Array[Dictionary] = []  # {tick, input, state}, oldest first
var _acked := {}  # The newest history entry the server has applied.
var _pending_snapshot := {}
var _newest_snapshot_tick := 0
var _server_time := -1.0  # Estimated tick of the newest snapshot, advanced every frame.
var _remotes := {}  # entity_id -> RemotePlayer
var _names := {}  # entity_id -> display name
var _lock_target_id := -1
var _display_name := ""
var _closed := false

# Stats for the debug overlay.
var _sent_at := {}  # input tick -> msec
var _rtt_ms := -1.0
var _corrections := 0
var _snapshots := 0
var _hits_landed := 0
var _hits_taken := 0
var _stats_timer := 0.0

@onready var _transport: NetTransport = $NetTransport
@onready var _world: Node3D = $World
@onready var _entities: Node3D = $World/Entities
@onready var _debug_label: Label = $HUD/Debug
@onready var _hint_label: Label = $HUD/Hint
@onready var _health_bar: ProgressBar = $HUD/HealthBar
@onready var _target_label: Label = $HUD/TargetLabel
@onready var _death_label: Label = $HUD/DeathLabel


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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("lock_on") and _body and not bot:
		_set_lock_target(-1 if _lock_target_id >= 0 else _find_lock_candidate())


# --- Packets ------------------------------------------------------------------------

func _on_packet(_peer_id: int, bytes: PackedByteArray) -> void:
	var buf := Protocol.reader(bytes)
	var msg := buf.get_u8()
	if msg == Protocol.Msg.SNAPSHOT:
		_on_snapshot(Protocol.decode_snapshot(buf))
	elif msg == Protocol.Msg.HIT:
		_on_hit(Protocol.decode_hit(buf))
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
	_body.respawn(welcome.position, welcome.facing)
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
		remote.push_state(snapshot.tick, other)
	for entity_id in _remotes.keys():
		if not seen.has(entity_id):
			_remove_remote(entity_id)


func _on_hit(hit: Dictionary) -> void:
	var tint := Color(1, 1, 1)
	if hit.target == _entity_id:
		tint = Color(1.0, 0.35, 0.3)
		_hits_taken += 1
	elif hit.attacker == _entity_id:
		tint = Color(1.0, 0.85, 0.3)
		_hits_landed += 1
	if hit.result == Combat.Result.PARRIED:
		tint = Color(0.4, 0.9, 1.0)
	var text: String = RESULT_TEXT.get(hit.result, "%d")
	FloatingText.spawn(_world, hit.position, text % hit.damage if text.contains("%d") else text, tint)


# --- Simulation ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _body == null:
		return
	if not _pending_snapshot.is_empty():
		_reconcile(_pending_snapshot, delta)
		_pending_snapshot = {}

	_input_tick += 1
	var input := _bot_input() if bot else _player_input()
	input.tick = _input_tick
	input.view_tick = _server_time - INTERP_DELAY_TICKS
	_body.simulate(input, delta)
	_history.append({"tick": _input_tick, "input": input, "state": _body.capture_state()})
	if _history.size() > MAX_HISTORY:
		_history.pop_front()

	_sent_at[_input_tick] = Time.get_ticks_msec()
	var recent := _history.slice(-Protocol.INPUT_REDUNDANCY).map(func(entry): return entry.input)
	_transport.send(1, Protocol.encode_inputs(recent), false)


func _reconcile(snapshot: Dictionary, delta: float) -> void:
	var ack: int = snapshot.ack
	var server_state: Dictionary = snapshot.state
	_body.health = server_state.health  # Always the server's; never predicted.
	if ack == 0:
		return  # The server hasn't applied any of our inputs yet.

	if _sent_at.has(ack):
		var rtt: float = Time.get_ticks_msec() - _sent_at[ack]
		_rtt_ms = rtt if _rtt_ms < 0.0 else lerpf(_rtt_ms, rtt, 0.2)
	for tick in _sent_at.keys():
		if tick <= ack:
			_sent_at.erase(tick)

	while not _history.is_empty() and _history[0].tick <= ack:
		_acked = _history.pop_front()
	# Compared even when ack hasn't moved: the server can change our state between our
	# inputs (a hit, a parry, a respawn).
	if _acked.get("tick") == ack and PlayerBody.states_match(_acked.state, server_state):
		return

	_corrections += 1
	var jump := _body.global_position.distance_to(server_state.position)
	_body.restore_state(server_state)
	_acked = {"tick": ack, "state": server_state}
	for entry in _history:
		_body.simulate(entry.input, delta)
		entry.state = _body.capture_state()
	if jump > 3.0:
		_body.reset_physics_interpolation()  # Teleport (respawn); don't slide across the map.


func _player_input() -> PlayerInput:
	var input := _camera_rig.sample_input()
	var target: RemotePlayer = _remotes.get(_lock_target_id)
	if target:
		input.buttons |= PlayerInput.LOCKED
		input.set_aim(_yaw_to(target.global_position))
	return input


# --- Lock-on ------------------------------------------------------------------------

## Nearest living fighter within range, preferring ones near the center of the view.
func _find_lock_candidate() -> int:
	var best_id := -1
	var best_score := INF
	var view_forward := -_camera_rig.global_basis.z
	for entity_id in _remotes:
		var remote: RemotePlayer = _remotes[entity_id]
		var offset := remote.global_position - _body.global_position
		var distance := offset.length()
		if remote.is_dead() or distance > LOCK_RANGE:
			continue
		var alignment := view_forward.dot(offset.normalized())
		if alignment < 0.2:
			continue
		var score := distance * (2.0 - alignment)
		if score < best_score:
			best_score = score
			best_id = entity_id
	return best_id


func _set_lock_target(entity_id: int) -> void:
	var previous: RemotePlayer = _remotes.get(_lock_target_id)
	if previous:
		previous.set_locked(false)
	_lock_target_id = entity_id
	var target: RemotePlayer = _remotes.get(entity_id)
	if target:
		target.set_locked(true)
	if _camera_rig:
		_camera_rig.locked = target != null


func _update_lock() -> void:
	if _lock_target_id < 0:
		return
	var target: RemotePlayer = _remotes.get(_lock_target_id)
	if target == null or target.is_dead() or _body.is_dead() \
			or target.global_position.distance_to(_body.global_position) > LOCK_BREAK_RANGE:
		_set_lock_target(-1)
		return
	_camera_rig.lock_point = target.global_position + Vector3.UP * 1.2


# --- Per frame ----------------------------------------------------------------------

func _process(delta: float) -> void:
	if _server_time >= 0.0:
		_server_time += delta * Protocol.TICK_RATE
		var render_tick := _server_time - INTERP_DELAY_TICKS
		for remote: RemotePlayer in _remotes.values():
			remote.render(render_tick)

	if _body:
		_update_lock()
		_update_hud()
	_stats_timer += delta
	if bot and _stats_timer >= STATS_PRINT_INTERVAL:
		_stats_timer = 0.0
		print("[client %s] %s" % [_display_name, _stats_text().replace("\n", "  |  ")])


func _update_hud() -> void:
	_debug_label.text = _stats_text()
	_health_bar.value = _body.health
	var target: RemotePlayer = _remotes.get(_lock_target_id)
	_target_label.visible = target != null
	if target:
		_target_label.text = "%s  —  %d / %d" % [target.display_name, target.latest_state().get("health", 0), PlayerBody.MAX_HEALTH]
	_death_label.visible = _body.is_dead()


func _stats_text() -> String:
	var lines := PackedStringArray([
		"%s (entity %d)  |  %d fighters visible" % [_display_name, _entity_id, _remotes.size() + 1],
		"Input RTT: %s" % ("%d ms" % _rtt_ms if _rtt_ms >= 0.0 else "-"),
		"Unacked inputs: %d  |  Corrections: %d" % [_history.size(), _corrections],
		"HP: %d  |  Hits landed: %d  |  Hits taken: %d" % [_body.health if _body else 0, _hits_landed, _hits_taken],
		"Snapshots: %d" % _snapshots,
	])
	if _transport.conditioner:
		lines.append("Simulated network: %s" % _transport.conditioner.describe())
	return "\n".join(lines)


# --- Bot ----------------------------------------------------------------------------

## Chases the nearest living fighter and cycles through light combos, heavies, blocks
## and dodges, so headless runs exercise every part of combat.
func _bot_input() -> PlayerInput:
	var input := PlayerInput.new()
	var target := _nearest_remote(BOT_AGGRO_RANGE)
	if target == null:
		var t := _input_tick / float(Protocol.TICK_RATE) + _entity_id * 1.7
		input.set_move(Vector2(sin(t * 0.7), cos(t * 0.7)))
		return input

	var yaw := _yaw_to(target.global_position)
	input.set_yaw(yaw)
	input.set_aim(yaw)
	input.buttons |= PlayerInput.LOCKED
	var distance := target.global_position.distance_to(_body.global_position)
	if distance > BOT_ATTACK_RANGE - 0.6:
		input.set_move(Vector2(0.0, -1.0))
	if distance <= BOT_ATTACK_RANGE:
		var phase := (_input_tick + _entity_id * 23) % 120
		if phase < 45 and phase % 6 == 0:
			input.buttons |= PlayerInput.LIGHT
		elif phase == 60:
			input.buttons |= PlayerInput.HEAVY
		elif phase >= 85 and phase < 105:
			input.buttons |= PlayerInput.BLOCK
		elif phase == 110:
			input.buttons |= PlayerInput.DODGE
	return input


func _nearest_remote(max_range: float) -> RemotePlayer:
	var nearest: RemotePlayer = null
	var nearest_distance := max_range
	for remote: RemotePlayer in _remotes.values():
		var distance := remote.global_position.distance_to(_body.global_position)
		if not remote.is_dead() and distance < nearest_distance:
			nearest = remote
			nearest_distance = distance
	return nearest


func _yaw_to(point: Vector3) -> float:
	var offset := point - _body.global_position
	return atan2(-offset.x, -offset.z)


func _remove_remote(entity_id: int) -> void:
	var remote: RemotePlayer = _remotes.get(entity_id)
	if remote:
		remote.queue_free()
		_remotes.erase(entity_id)
	if entity_id == _lock_target_id:
		_set_lock_target(-1)
