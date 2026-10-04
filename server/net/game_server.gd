class_name GameServer
extends Node
## Authoritative zone server. Clients only send inputs; the server simulates every
## fighter (players, training dummies and spirit beasts), resolves hits with lag
## compensation, runs technique effects and echoes, owns each player's progression,
## and sends each client a snapshot of the world every tick.
##
## With a backend (online mode), players join with a one-time ticket from the backend,
## their character's progression is loaded from it and saved back, and the server sends
## heartbeats so the backend can route players here. Without one (offline mode, for
## development), anyone can join by name and nothing is saved.

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
## Dummies face +Z, toward where players spawn.
const DUMMY_FACING := PI
const BEAST_TEAM := 1
const HEARTBEAT_SECONDS := 5.0
## Changed progression is saved this often (and always when the player leaves).
const AUTOSAVE_SECONDS := 10.0
## ENet drops a peer that has been silent this long (ms), instead of its ~30 s default.
const PEER_TIMEOUT_MIN_MS := 4000
const PEER_TIMEOUT_MAX_MS := 10000
const STATS_SECONDS := 5.0
## On shutdown, players are warned and saved; quit anyway if saving takes longer than this.
const SHUTDOWN_TIMEOUT_SECONDS := 15.0


class ClientSession:
	var peer_id := 0
	## Backend character id, or -1 in offline mode.
	var character_id := -1
	var progress_dirty := false
	var display_name := ""
	var body: PlayerBody
	var progress := ProgressState.new()
	var inputs: Array[PlayerInput] = []
	var newest_input_tick := 0
	var last_processed_tick := 0
	var input_credit := 0.0
	var interacting := false
	var interest := Interest.new()
	## Set once the player is on their way to another zone.
	var transferring := false
	## Where in this zone the player arrived (spawn name).
	var arrived_at := "default"
	var discipline := "enforcer"
	## The character's Way; until Way selection exists everyone follows Ways.DEFAULT.
	var way_id := Ways.DEFAULT


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
## Multiplies essence from echoes, to test progression quickly.
var essence_mult := 1
## Which zone of the world this server runs (see Zones). Set before start().
var zone_id := Zones.DEFAULT
## Print tick time and bandwidth every few seconds.
var log_stats := false
## Localhost-only admin port ("status", "shutdown"). Godot can't catch SIGTERM, so
## tools/server_entrypoint.sh turns stop signals into a "shutdown" here. 0 = off.
var admin_port := 0
## Online mode: set before start(). Null runs offline.
var backend: BackendClient
## The world (shard) this server belongs to; each world runs one server per zone.
var world_id := "alpha"
## Unique per server process; defaults to "<world>/<zone>".
var shard_id := "alpha/proving_grounds"
var shard_name := "Alpha"
## Address the backend gives players for this shard.
var public_host := "127.0.0.1"

var _sessions := {}  # peer_id -> ClientSession
var _joining := {}  # peer_id -> true while their join ticket is being redeemed
var _admin := TCPServer.new()
var _admin_peers: Array[StreamPeerTCP] = []
var _shutting_down := false
var _dummies: Array[Dummy] = []
var _beasts: Array[Beast] = []
var _info := {}  # entity_id -> {name, kind, species, rank}, for every fighter
var _hit_history := HitHistory.new()
var _effects := TechniqueEffects.new()
var _echoes := EchoField.new()
var _tick := 0
var _next_entity_id := 1
var _port := 0
var _zone: ZoneData
# Stats since the last report.
var _tick_usec_total := 0
var _tick_usec_max := 0
## Time per tick phase (usec), for finding hot spots.
var _phase_usec := {}
var _phase_started := 0
var _ticks_measured := 0
var _bytes_sent_reported := 0
var _bytes_received_reported := 0

@onready var _transport: NetTransport = $NetTransport
@onready var _world: Node3D = $World
@onready var _entities: Node3D = $World/Entities
@onready var _overview_camera: Camera3D = $World/OverviewCamera
@onready var _status: Label = $Debug/Status


func start(port: int) -> Error:
	_zone = Zones.get_zone(zone_id)
	if _zone == null:
		push_error("Unknown zone '%s'" % zone_id)
		return ERR_INVALID_PARAMETER
	_world.add_child(load(_zone.scene_path).instantiate())
	var extent := _zone.overview
	_overview_camera.position = Vector3(0.0, extent, extent)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, Protocol.MAX_PLAYERS)
	if err != OK:
		return err
	(multiplayer as SceneMultiplayer).server_relay = false
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(func(peer_id: int):
		peer.get_peer(peer_id).set_timeout(0, PEER_TIMEOUT_MIN_MS, PEER_TIMEOUT_MAX_MS))
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_transport.packet_received.connect(_on_packet)
	_port = port
	_effects.hit_history = _hit_history
	_effects.max_rewind_ticks = MAX_REWIND_TICKS
	_effects.land_hit = _land_hit
	_effects.burst = func(caster_id: int, technique_id: int, at: Vector3) -> void:
		_broadcast_near(at, Protocol.encode_burst(caster_id, technique_id, at))
	_spawn_dummies()
	_spawn_beasts()
	print("[server] %s listening on UDP port %d (protocol v%d, %d Hz)" % [
		_zone.display_name, port, Protocol.VERSION, Protocol.TICK_RATE])
	if log_stats:
		_every(STATS_SECONDS, _report_stats)
	if admin_port > 0:
		var admin_err := _admin.listen(admin_port, "127.0.0.1")
		if admin_err == OK:
			print("[server] Admin port %d (localhost only)" % admin_port)
		else:
			push_warning("[server] Admin port %d unavailable: %s" % [admin_port, error_string(admin_err)])
	if backend:
		add_child(backend)
		_every(HEARTBEAT_SECONDS, _send_heartbeat)
		_every(AUTOSAVE_SECONDS, _autosave)
		_send_heartbeat()
		print("[server] Online mode: shard '%s' registered with %s" % [shard_id, backend.base_url])
	else:
		print("[server] Offline mode: players join by name and nothing is saved")
	return OK


func _physics_process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_phase_started = started
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
	_phase("players")
	var practitioners := _practitioner_bodies()
	for beast in _beasts:
		beast.body.simulate(beast.brain.think(practitioners), delta)
		_after_simulate(beast.body, _tick - 1, bodies)
	for dummy in _dummies:
		dummy.body.simulate(dummy.input, delta)
	_phase("beasts")
	_effects.update(_tick, bodies, _entities.get_world_3d().direct_space_state)
	_phase("effects")
	_update_echoes()
	_check_portals()
	_phase("echoes")

	for body: PlayerBody in bodies:
		if body.global_position.y < KILL_Y or (body.is_dead() and body.action_tick >= _respawn_ticks(body)):
			_respawn(body)

	_hit_history.record(_tick, bodies)
	_phase("history")
	_send_snapshots()
	_phase("snapshots")
	if _tick % Protocol.TICK_RATE == 0:
		_status.text = "SERVER  |  %s  |  port %d  |  tick %d  |  %d / %d players  |  %d echoes" % [
			_zone.display_name, _port, _tick, _sessions.size(), Protocol.MAX_PLAYERS, _echoes.count()]
	var elapsed := Time.get_ticks_usec() - started
	_tick_usec_total += elapsed
	_tick_usec_max = maxi(_tick_usec_max, elapsed)
	_ticks_measured += 1


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
	_broadcast_near(at, Protocol.encode_hit(attacker_id, target.entity_id, outcome[0], outcome[1], at))
	var beast := _beast_of(target)
	if beast:
		beast.brain.on_hit(attacker)
	if log_hits:
		var source := "melee" if technique_id < 0 else Techniques.get_technique(technique_id).display_name
		print("[server] %s -> %s: %s %d (%s)" % [_name_of(attacker_id), _name_of(target.entity_id),
			Combat.Result.keys()[outcome[0]], outcome[1], source])
	if target.is_dead():
		_on_killed(target, attacker)


## The fallen leave echoes: beasts of their aspect, spirit practitioners of their Way's.
## Whoever landed the killing blow gets first claim, if they're a spirit practitioner.
func _on_killed(target: PlayerBody, killer: PlayerBody) -> void:
	var killer_id := killer.entity_id if killer else 0
	print("[server] %s defeated %s" % [_name_of(killer_id), _name_of(target.entity_id)])
	var owner := killer_id if _session_of(killer) else 0
	var beast := _beast_of(target)
	if beast:
		var data := Beasts.get_beast(beast.species)
		_echoes.spawn(target.global_position, data.aspect, data.essence * essence_mult, owner, data.display_name)
	elif _session_of(target):
		_echoes.spawn(target.global_position, Advancement.PRACTITIONER_ECHO_ASPECT,
			Advancement.PRACTITIONER_ECHO_ESSENCE * essence_mult, owner, _name_of(target.entity_id))


func _update_echoes() -> void:
	var claimants := []
	for session: ClientSession in _sessions.values():
		claimants.append({"body": session.body, "interacting": session.interacting})
	for claim in _echoes.update(claimants):
		var session := _session_by_entity(claim[0])
		var echo: EchoField.Echo = claim[1]
		session.progress.add_essence(echo.aspect, echo.essence)
		session.progress_dirty = true
		_send_progress(session)
		_notify(session, "Claimed the echo of %s: +%d %s essence" % [
			echo.source_name, echo.essence, Advancement.ASPECT_NAMES[echo.aspect].to_lower()])


## Every fighter is encoded once per tick; each player then gets the entries (and
## effects) that their interest set selects.
func _send_snapshots() -> void:
	var bodies := _entities.get_children()
	var ids := PackedInt32Array()
	var positions := PackedVector3Array()
	var entries := []
	for body: PlayerBody in bodies:
		ids.append(body.entity_id)
		positions.append(body.global_position)
		entries.append(Protocol.encode_remote_entry(body))
	var effect_ids := PackedInt32Array()
	var effect_positions := PackedVector3Array()
	var effect_stationary := PackedByteArray()
	var effect_entries := []
	for effect: Dictionary in _effects.snapshot_entries() + _echoes.snapshot_entries():
		effect_ids.append(effect.id)
		effect_positions.append(effect.position)
		effect_stationary.append(1 if effect.kind != Protocol.Effect.PROJECTILE else 0)
		effect_entries.append(Protocol.encode_effect_entry(effect))
	for session: ClientSession in _sessions.values():
		var viewer := session.body.global_position
		var visible := []
		for i in session.interest.select(viewer, ids, positions, _tick):
			if ids[i] != session.body.entity_id:
				visible.append(entries[i])
		var nearby := []
		for i in Interest.select_effects(viewer, effect_ids, effect_positions, effect_stationary, _tick):
			nearby.append(effect_entries[i])
		var claim := _echoes.progress_of(session.body.entity_id)
		var bytes := Protocol.encode_snapshot(_tick, session.last_processed_tick, session.body, visible, nearby, claim)
		_transport.send(session.peer_id, bytes, false)


## Unreliable events (hits, bursts) only go to players close enough to see them.
func _broadcast_near(at: Vector3, bytes: PackedByteArray) -> void:
	for session: ClientSession in _sessions.values():
		if Interest.can_see(session.body.global_position, at):
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
	if backend == null:
		var display_name := String(hello.name).strip_edges().left(Protocol.MAX_NAME_LENGTH)
		_admit(peer_id, display_name if not display_name.is_empty() else "Practitioner", -1, ProgressState.new(), "default", {})
		return
	if _joining.has(peer_id):
		return
	if String(hello.ticket).is_empty():
		_reject(peer_id, "This server requires logging in")
		return

	_joining[peer_id] = true
	var redeemed := await backend.request_json(HTTPClient.METHOD_POST, "/internal/tickets/redeem",
		{"ticket": hello.ticket, "shard_id": shard_id})
	var still_here := _joining.erase(peer_id)
	if not redeemed.ok:
		if still_here:
			_reject(peer_id, "Couldn't join: %s" % redeemed.error)
		return
	var character: Dictionary = redeemed.data.get("character", {})
	var character_id := int(character.get("id", -1))
	var progress_data = character.get("progress", {})
	var progress := ProgressState.from_dict(progress_data if progress_data is Dictionary else {})
	if not still_here:
		# They disconnected while we were asking; release the character again.
		backend.request_json(HTTPClient.METHOD_POST, "/internal/characters/%d/left" % character_id, {})
		return
	# Logging in again takes over: the old connection (often a dead one that hasn't timed
	# out yet) is dropped, and its in-memory progress, which is newer than the save, carries over.
	for old: ClientSession in _sessions.values():
		if old.character_id == character_id:
			progress = old.progress
			_remove_session(old, false)
			multiplayer.multiplayer_peer.disconnect_peer(old.peer_id)
			print("[server] %s reconnected; dropped the old connection" % old.display_name)
	_admit(peer_id, String(character.get("name", "Practitioner")), character_id, progress,
		String(redeemed.data.get("spawn", "default")), character)


## character: the backend's character record (discipline, appearance, Way); {} offline.
func _admit(peer_id: int, display_name: String, character_id: int, progress: ProgressState,
		spawn_name: String, character: Dictionary) -> void:
	var session := ClientSession.new()
	session.peer_id = peer_id
	session.display_name = display_name
	session.character_id = character_id
	session.progress = progress
	var discipline := str(character.get("discipline", "enforcer"))
	session.discipline = discipline if Disciplines.is_valid(discipline) else "enforcer"
	var way = character.get("way")
	session.way_id = StringName(way) if way is String and Ways.get_way(StringName(way)) else Ways.DEFAULT
	session.body = _spawn_body(display_name, Protocol.EntityKind.PRACTITIONER, -1)
	session.progress.apply_to(session.body)
	session.body.loadout = Ways.loadout(session.way_id)
	session.arrived_at = spawn_name
	session.body.respawn(Zones.spawn_point(zone_id, spawn_name), 0.0)
	_sessions[peer_id] = session
	_set_rank_info(session)

	var body := session.body
	_transport.send(peer_id, Protocol.encode_welcome(body.entity_id, body.global_position, body.facing, zone_id,
		session.way_id), true)
	_send_progress(session)
	for entity_id in _info:
		if entity_id != body.entity_id:
			_transport.send(peer_id, _encode_info(entity_id), true)
	for other: ClientSession in _sessions.values():
		if other != session:
			_transport.send(other.peer_id, _encode_info(body.entity_id), true)
	print("[server] %s joined (peer %d, entity %d, %s). %d online." % [display_name, peer_id, body.entity_id,
		"character %d, %s" % [character_id, Advancement.rank_name(progress.rank)] if character_id >= 0 else "offline",
		_sessions.size()])


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
		Protocol.Request.CRAFT_SIGIL:
			var error := progress.craft_error(request.argument)
			if not error.is_empty():
				_notify(session, error)
				return
			progress.craft(request.argument)
			session.progress_dirty = true
			progress.apply_to(session.body)
			_send_progress(session)
			_notify(session, "Crafted: %s" % Advancement.sigil(request.argument).display_name)
		Protocol.Request.ADVANCE:
			var error := progress.advance_error(session.body.action == PlayerBody.Action.MEDITATE)
			if not error.is_empty():
				_notify(session, error)
				return
			progress.advance()
			session.progress_dirty = true
			_save(session)  # Don't risk losing a breakthrough.
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
	_joining.erase(peer_id)
	var session: ClientSession = _sessions.get(peer_id)
	if session:
		_remove_session(session, true)


## Takes a player out of the world. left_world: the character is going offline (final
## save); false when a new connection is taking the character over.
func _remove_session(session: ClientSession, left_world: bool) -> void:
	var peer_id := session.peer_id
	_sessions.erase(peer_id)
	if backend and session.character_id >= 0 and left_world:
		backend.request_json(HTTPClient.METHOD_POST, "/internal/characters/%d/left" % session.character_id,
			{"progress": session.progress.to_dict()})
	var entity_id := session.body.entity_id
	_info.erase(entity_id)
	_effects.remove_owned_by(entity_id)
	_echoes.remove_owner(entity_id)
	_entities.remove_child(session.body)
	session.body.queue_free()
	_broadcast(Protocol.encode_entity_left(entity_id), true)
	if left_world:
		print("[server] %s left. %d online." % [session.display_name, _sessions.size()])


func _reject(peer_id: int, reason: String) -> void:
	_transport.send(peer_id, Protocol.encode_reject(reason), true)
	await get_tree().create_timer(REJECT_GRACE_SECONDS).timeout
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


# --- Admin and shutdown -------------------------------------------------------------

func _process(_delta: float) -> void:
	if not _admin.is_listening():
		return
	while _admin.is_connection_available():
		_admin_peers.append(_admin.take_connection())
	for peer in _admin_peers.duplicate():
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_admin_peers.erase(peer)
		elif peer.get_available_bytes() > 0:
			_admin_command(peer.get_utf8_string(peer.get_available_bytes()).strip_edges(), peer)


func _admin_command(line: String, peer: StreamPeerTCP) -> void:
	var command := line.get_slice(" ", 0)
	match command:
		"status":
			var status := {"zone": String(zone_id), "world": world_id, "tick": _tick, "players": _sessions.size(),
				"fighters": _entities.get_child_count(), "echoes": _echoes.count(), "shutting_down": _shutting_down}
			peer.put_data((JSON.stringify(status) + "\n").to_utf8_buffer())
		"shutdown":
			peer.put_data("shutting down\n".to_utf8_buffer())
			shutdown(line.trim_prefix("shutdown").strip_edges())
		_:
			peer.put_data(("unknown command '%s' (try: status, shutdown [reason])\n" % command).to_utf8_buffer())


## Warns every player, saves them all (online: final save and mark offline), then quits.
func shutdown(reason := "") -> void:
	if _shutting_down:
		return
	_shutting_down = true
	print("[server] Shutting down%s; saving %d players" % [": " + reason if reason else "", _sessions.size()])
	_broadcast(Protocol.encode_notice("The server is shutting down%s. Your progress is saved." % (
		" (%s)" % reason if reason else "")), true)
	get_tree().create_timer(SHUTDOWN_TIMEOUT_SECONDS).timeout.connect(func():
		push_warning("[server] Saving took too long; quitting anyway")
		get_tree().quit())
	if backend:
		for session: ClientSession in _sessions.values():
			if session.character_id >= 0:
				var result := await backend.request_json(HTTPClient.METHOD_POST,
					"/internal/characters/%d/left" % session.character_id, {"progress": session.progress.to_dict()})
				if not result.ok:
					push_warning("[server] Final save for %s failed: %s" % [session.display_name, result.error])
	print("[server] All players saved")
	get_tree().quit()


# --- Zones -------------------------------------------------------------------------

## Walking into a portal sends the player to another zone's server. That goes through
## the backend (which saves the character and issues a ticket for the target zone), so
## portals only work online.
func _check_portals() -> void:
	if _shutting_down:
		return
	for session: ClientSession in _sessions.values():
		if session.transferring or session.body.is_dead():
			continue
		for portal in _zone.portals:
			var offset: Vector3 = session.body.global_position - portal.position
			if Vector2(offset.x, offset.z).length() > portal.radius:
				continue
			if backend == null or session.character_id < 0:
				if _tick % (Protocol.TICK_RATE * 2) == 0:
					_notify(session, "Portals only work on an online server")
				continue
			_transfer(session, portal)


func _transfer(session: ClientSession, portal: ZonePortal) -> void:
	session.transferring = true
	var destination := Zones.display_name(portal.to_zone)
	_notify(session, "Traveling to %s..." % destination)
	var result := await backend.request_json(HTTPClient.METHOD_POST,
		"/internal/characters/%d/transfer" % session.character_id,
		{"zone": portal.to_zone, "spawn": portal.to_spawn, "progress": session.progress.to_dict()})
	if not _sessions.has(session.peer_id):
		return  # They left while we were asking.
	if not result.ok:
		session.transferring = false
		_notify(session, "The way to %s is closed: %s" % [destination, result.error])
		# Step them back out of the portal so it doesn't fire again immediately.
		session.body.global_position = Zones.spawn_point(zone_id, session.arrived_at)
		return
	session.progress_dirty = false
	_transport.send(session.peer_id, Protocol.encode_transfer(String(result.data.host), int(result.data.port),
		String(result.data.ticket), String(portal.to_zone)), true)
	print("[server] %s is traveling to %s" % [session.display_name, destination])
	_remove_session(session, false)


## Charges the time since the previous phase mark to this phase.
func _phase(phase: String) -> void:
	if not log_stats:
		return
	var now := Time.get_ticks_usec()
	_phase_usec[phase] = _phase_usec.get(phase, 0) + now - _phase_started
	_phase_started = now


func _report_stats() -> void:
	var seconds := STATS_SECONDS
	var sent := _transport.bytes_sent - _bytes_sent_reported
	var received := _transport.bytes_received - _bytes_received_reported
	_bytes_sent_reported = _transport.bytes_sent
	_bytes_received_reported = _transport.bytes_received
	var players := _sessions.size()
	print("[stats] %s | %d players, %d fighters | tick avg %.2f ms, max %.2f ms (budget %.1f) | out %.1f KB/s (%.1f per player) | in %.1f KB/s" % [
		_zone.display_name, players, _entities.get_child_count(),
		_tick_usec_total / 1000.0 / maxi(_ticks_measured, 1), _tick_usec_max / 1000.0, 1000.0 / Protocol.TICK_RATE,
		sent / 1024.0 / seconds, sent / 1024.0 / seconds / maxi(players, 1), received / 1024.0 / seconds])
	var phases := PackedStringArray()
	for phase: String in _phase_usec:
		phases.append("%s %.2f" % [phase, _phase_usec[phase] / 1000.0 / maxi(_ticks_measured, 1)])
	print("[stats]   per tick (ms): %s" % ", ".join(phases))
	_phase_usec.clear()
	_tick_usec_total = 0
	_tick_usec_max = 0
	_ticks_measured = 0


# --- Backend ------------------------------------------------------------------------

func _send_heartbeat() -> void:
	var result := await backend.request_json(HTTPClient.METHOD_POST, "/internal/shards/heartbeat", {
		"id": shard_id, "name": shard_name, "world": world_id, "zone": zone_id, "host": public_host, "port": _port,
		"players": _sessions.size() + _joining.size(), "capacity": Protocol.MAX_PLAYERS,
	})
	if not result.ok:
		push_warning("[server] Heartbeat failed: %s" % result.error)


func _autosave() -> void:
	for session: ClientSession in _sessions.values():
		if session.progress_dirty:
			_save(session)


func _save(session: ClientSession) -> void:
	if backend == null or session.character_id < 0:
		return
	session.progress_dirty = false
	var result := await backend.request_json(HTTPClient.METHOD_PUT,
		"/internal/characters/%d/progress" % session.character_id, {"progress": session.progress.to_dict()})
	if not result.ok:
		session.progress_dirty = true  # Try again at the next autosave.
		push_warning("[server] Saving %s failed: %s" % [session.display_name, result.error])


func _every(seconds: float, callback: Callable) -> void:
	var timer := Timer.new()
	timer.wait_time = seconds
	timer.timeout.connect(callback)
	add_child(timer)
	timer.start()


func _send_progress(session: ClientSession) -> void:
	_transport.send(session.peer_id, Protocol.encode_progress(session.progress), true)


func _notify(session: ClientSession, text: String) -> void:
	_transport.send(session.peer_id, Protocol.encode_notice(text), true)


# --- Fighters -----------------------------------------------------------------------

func _spawn_dummies() -> void:
	for config in _zone.dummies:
		var dummy := Dummy.new()
		dummy.home = config.position
		dummy.body = _spawn_body(config.display_name, Protocol.EntityKind.DUMMY, -1)
		dummy.body.respawn(dummy.home, DUMMY_FACING)
		dummy.input.set_yaw(DUMMY_FACING)  # Fighters turn to face their input yaw.
		if config.block:
			dummy.input.buttons = PlayerInput.BLOCK
		_dummies.append(dummy)


func _spawn_beasts() -> void:
	for den in _zone.dens:
		var data := Beasts.by_id(den.species)
		if data == null:
			push_error("Zone '%s' has a den for unknown species '%s'" % [zone_id, den.species])
			continue
		var beast := Beast.new()
		beast.species = data.net_id
		beast.body = _spawn_body(data.display_name, Protocol.EntityKind.BEAST, data.net_id)
		beast.body.apply_stats(data.max_health, PlayerBody.MAX_SPIRIT, PlayerInput.TECHNIQUE_COUNT,
			data.damage_mult, data.knockback_taken_mult, data.speed_mult)
		beast.body.team = BEAST_TEAM
		_info[beast.body.entity_id].max_health = data.max_health
		beast.body.respawn(den.position, randf() * TAU)
		beast.brain = BeastBrain.new(data, beast.body, den.position, beast.body.entity_id)
		_beasts.append(beast)


func _spawn_body(display_name: String, kind: Protocol.EntityKind, species: int) -> PlayerBody:
	var body: PlayerBody = PLAYER_SCENE.instantiate()
	body.entity_id = _next_entity_id
	body.name = "Fighter%d" % _next_entity_id
	_next_entity_id += 1
	_entities.add_child(body)
	_info[body.entity_id] = {"name": display_name, "kind": kind, "species": species, "rank": 0,
		"max_health": PlayerBody.MAX_HEALTH}
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
	body.respawn(Zones.spawn_point(zone_id, "default"), body.facing)


func _respawn_ticks(body: PlayerBody) -> int:
	var beast := _beast_of(body)
	return Beasts.get_beast(beast.species).respawn_ticks if beast else PlayerBody.RESPAWN_TICKS


func _set_rank_info(session: ClientSession) -> void:
	_info[session.body.entity_id].rank = session.progress.rank
	_info[session.body.entity_id].max_health = session.body.max_health


func _encode_info(entity_id: int) -> PackedByteArray:
	var info: Dictionary = _info[entity_id]
	return Protocol.encode_entity_info(entity_id, info.name, info.kind, info.species, info.rank, info.max_health)


func _practitioner_bodies() -> Array:
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
