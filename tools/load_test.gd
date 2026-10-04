extends SceneTree
## Load test: connects many lightweight bots from a single process to an offline game
## server. Each bot has its own SceneMultiplayer + ENet connection, roams the zone and
## fights (attacks, dodges, casts), and reads only its own position from snapshots, so
## this process stays cheap and the server is what gets measured. Start the server with
## --stats to see its tick time and bandwidth.
##
## Usage: godot --headless --path . --script res://tools/load_test.gd -- --bots=100
##        [--host=127.0.0.1] [--port=7777] [--seconds=60] [--spread=70]

const REPORT_SECONDS := 5.0
## New connections per second, so the server isn't hit by 100 handshakes at once.
const CONNECTS_PER_SECOND := 20.0


class LoadBot extends Node:
	var index := 0
	var host := "127.0.0.1"
	var port := Protocol.DEFAULT_PORT
	var spread := 70.0
	var entity_id := 0
	var bytes_in := 0
	var snapshots := 0
	var closed := false

	var _api := SceneMultiplayer.new()
	var _tick := 0
	var _position := Vector3.ZERO
	var _target := Vector3.ZERO
	var _rng := RandomNumberGenerator.new()

	func start() -> void:
		_rng.seed = index * 7919
		_pick_target()
		get_tree().set_multiplayer(_api, get_path())
		var peer := ENetMultiplayerPeer.new()
		if peer.create_client(host, port) != OK:
			closed = true
			return
		_api.multiplayer_peer = peer
		_api.connected_to_server.connect(func():
			_api.send_bytes(Protocol.encode_hello("Load%03d" % index), 1, MultiplayerPeer.TRANSFER_MODE_RELIABLE))
		_api.server_disconnected.connect(func(): closed = true)
		_api.connection_failed.connect(func(): closed = true)
		_api.peer_packet.connect(_on_packet)

	func _on_packet(_from: int, bytes: PackedByteArray) -> void:
		bytes_in += bytes.size()
		var buf := Protocol.reader(bytes)
		var msg := buf.get_u8()
		if msg == Protocol.Msg.WELCOME:
			entity_id = buf.get_u32()
		elif msg == Protocol.Msg.SNAPSHOT:
			snapshots += 1
			buf.seek(10)  # type, tick, ack, claim; the fighter's own state starts with its position.
			_position = Vector3(buf.get_float(), buf.get_float(), buf.get_float())

	func _physics_process(_delta: float) -> void:
		if entity_id == 0 or closed:
			return
		_tick += 1
		var offset := _target - _position
		if Vector2(offset.x, offset.z).length() < 2.0 or _tick % 240 == 0:
			_pick_target()
		var input := PlayerInput.new()
		input.tick = _tick
		input.set_yaw(atan2(-offset.x, -offset.z))
		input.set_move(Vector2(0.0, -1.0))
		var roll := _rng.randf()
		if roll < 0.04:
			input.buttons |= PlayerInput.LIGHT
		elif roll < 0.05:
			input.buttons |= PlayerInput.HEAVY
		elif roll < 0.055:
			input.buttons |= PlayerInput.DODGE
		elif roll < 0.058:
			input.buttons |= PlayerInput.technique_button(_rng.randi_range(0, 1))
		_api.send_bytes(Protocol.encode_inputs([input]), 1, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)

	func _pick_target() -> void:
		_target = Vector3(_rng.randf_range(-spread, spread), 0.0, _rng.randf_range(-spread, spread))


var _bots: Array[LoadBot] = []
var _wanted := 100
var _seconds := 60.0
var _elapsed := 0.0
var _next_report := REPORT_SECONDS
var _bytes_reported := 0
var _settings := {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		_settings[pair[0]] = pair[1] if pair.size() > 1 else "true"
	_wanted = int(_settings.get("bots", "100"))
	_seconds = float(_settings.get("seconds", "60"))
	print("[load] Connecting %d bots to %s:%s for %d s" % [_wanted, _settings.get("host", "127.0.0.1"),
		_settings.get("port", str(Protocol.DEFAULT_PORT)), _seconds])


func _process(delta: float) -> bool:
	_elapsed += delta
	var due := mini(_wanted, int(_elapsed * CONNECTS_PER_SECOND) + 1)
	while _bots.size() < due:
		var bot := LoadBot.new()
		bot.index = _bots.size()
		bot.host = _settings.get("host", "127.0.0.1")
		bot.port = int(_settings.get("port", str(Protocol.DEFAULT_PORT)))
		bot.spread = float(_settings.get("spread", "70"))
		bot.name = "Bot%d" % bot.index
		root.add_child(bot)
		bot.start()
		_bots.append(bot)

	if _elapsed >= _next_report:
		_next_report += REPORT_SECONDS
		var joined := _bots.filter(func(b: LoadBot): return b.entity_id != 0 and not b.closed).size()
		var total := 0
		var snapshots := 0
		for bot in _bots:
			total += bot.bytes_in
			snapshots += bot.snapshots
		var rate := (total - _bytes_reported) / 1024.0 / REPORT_SECONDS
		_bytes_reported = total
		print("[load] t=%ds  in world: %d/%d  |  received %.1f KB/s total, %.2f KB/s per bot  |  snapshots %d" % [
			_elapsed, joined, _wanted, rate, rate / maxi(joined, 1), snapshots])
	return _elapsed >= _seconds
