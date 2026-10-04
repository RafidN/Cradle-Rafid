extends Node
## Entry point. Starts a dedicated server, a client, or shows the connect menu,
## depending on the build and these command-line arguments (with or without a "--"
## separator before them, so they also work in the editor's Customize Run Instances):
##   --server [--port=7777] [--log-hits] [--essence-mult=N]
##   --connect=host[:port] [--name=X] [--latency=ms] [--jitter=ms] [--loss=percent] [--bot]
##   --screenshot=path.png [--screenshot-after=seconds]  (save one frame, then quit)
## Headless runs and dedicated_server exports start a server unless --connect is given.

const SERVER_SCENE := preload("res://server/server.tscn")
const CLIENT_SCENE := preload("res://client/client.tscn")
const HEADLESS_MAX_FPS := 120

var _headless := DisplayServer.get_name() == "headless"
var _session: Node

@onready var _menu: CanvasLayer = $Menu
@onready var _name_edit: LineEdit = %NameEdit
@onready var _address_edit: LineEdit = %AddressEdit
@onready var _latency_spin: SpinBox = %LatencySpin
@onready var _jitter_spin: SpinBox = %JitterSpin
@onready var _loss_spin: SpinBox = %LossSpin
@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	%ConnectButton.pressed.connect(_on_connect_pressed)
	%ServerButton.pressed.connect(_start_server.bind(Protocol.DEFAULT_PORT, false, 1))
	if _headless:
		Engine.max_fps = HEADLESS_MAX_FPS

	var args := _parse_args(OS.get_cmdline_args() + OS.get_cmdline_user_args())
	if args.has("screenshot"):
		_screenshot_and_quit(String(args.screenshot), String(args.get("screenshot-after", "5")).to_float())
	if args.has("connect"):
		_start_client(
			String(args.connect),
			String(args.get("name", "")),
			String(args.get("latency", "0")).to_float(),
			String(args.get("jitter", "0")).to_float(),
			String(args.get("loss", "0")).to_float(),
			args.has("bot"))
	elif args.has("server") or _headless or OS.has_feature("dedicated_server"):
		_start_server(String(args.get("port", str(Protocol.DEFAULT_PORT))).to_int(), args.has("log-hits"),
			String(args.get("essence-mult", "1")).to_int())


func _on_connect_pressed() -> void:
	_start_client(_address_edit.text.strip_edges(), _name_edit.text.strip_edges(),
		_latency_spin.value, _jitter_spin.value, _loss_spin.value, false)


func _start_server(port: int, log_hits: bool, essence_mult: int) -> void:
	var server: GameServer = SERVER_SCENE.instantiate()
	server.log_hits = log_hits
	server.essence_mult = maxi(essence_mult, 1)
	add_child(server)
	var err := server.start(port)
	if err != OK:
		server.queue_free()
		_fail("Could not start server on port %d: %s" % [port, error_string(err)])
		return
	_session = server
	_menu.hide()


func _start_client(address: String, display_name: String, latency_ms: float,
		jitter_ms: float, loss_percent: float, bot: bool) -> void:
	var host := address.get_slice(":", 0)
	var port := Protocol.DEFAULT_PORT
	if address.contains(":"):
		port = address.get_slice(":", 1).to_int()
	if display_name.is_empty():
		display_name = "Artist%d" % randi_range(100, 999)

	var conditioner := NetConditioner.new()
	conditioner.latency_ms = latency_ms
	conditioner.jitter_ms = jitter_ms
	conditioner.loss = clampf(loss_percent / 100.0, 0.0, 1.0)

	var client: GameClient = CLIENT_SCENE.instantiate()
	client.bot = bot
	add_child(client)
	client.disconnected.connect(_on_client_disconnected)
	var err := client.connect_to_server(host, port, display_name,
		conditioner if conditioner.is_active() else null)
	if err != OK:
		client.queue_free()
		_fail("Could not connect: %s" % error_string(err))
		return
	_session = client
	_menu.hide()


func _on_client_disconnected(reason: String) -> void:
	_session.queue_free()
	_session = null
	_fail(reason)


func _fail(message: String) -> void:
	if _headless:
		printerr(message)
		get_tree().quit(1)
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_status_label.text = message
	_menu.show()


func _screenshot_and_quit(path: String, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("Screenshot %s: %s" % [path, error_string(err)])
	get_tree().quit()


## Turns ["--a=1", "--b"] into {"a": "1", "b": true}.
static func _parse_args(raw: PackedStringArray) -> Dictionary:
	var args := {}
	for arg in raw:
		if not arg.begins_with("--"):
			continue
		var pair := arg.trim_prefix("--").split("=", true, 1)
		args[pair[0]] = pair[1] if pair.size() > 1 else true
	return args
