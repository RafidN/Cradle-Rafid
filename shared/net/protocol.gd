class_name Protocol
extends RefCounted
## Wire format shared by client and server. Every packet starts with a u8 Msg type and
## is little-endian. Bump VERSION whenever the format changes.

const VERSION := 6
const DEFAULT_PORT := 7777
const MAX_PLAYERS := 100
const TICK_RATE := 30
## How many of the newest inputs each INPUT packet repeats, so one lost packet costs nothing.
const INPUT_REDUNDANCY := 6
const MAX_NAME_LENGTH := 16
const MAX_TICKET_LENGTH := 128

enum Msg {
	HELLO, WELCOME, REJECT, INPUT, SNAPSHOT, ENTITY_INFO, ENTITY_LEFT, HIT, BURST,
	REQUEST, PROGRESS, NOTICE, TRANSFER,
}

## Other fighters' positions are sent as 16-bit fixed point: 1/64 m steps, +-512 m.
const POSITION_SCALE := 64.0
## Bytes per fighter in a snapshot (see encode_remote_entry).
const REMOTE_ENTRY_SIZE := 15
## Bytes per world effect in a snapshot (see encode_effect_entry).
const EFFECT_ENTRY_SIZE := 21

## Kinds of world effects (server-owned objects that aren't fighters) sent in snapshots.
enum Effect { PROJECTILE, TRAP, REMNANT }
## What a fighter is, for drawing it.
enum EntityKind { ARTIST, DUMMY, BEAST }
## Client requests.
enum Request { CRAFT_BINDING, ADVANCE }


static func is_reliable(msg: int) -> bool:
	return not msg in [Msg.INPUT, Msg.SNAPSHOT, Msg.HIT, Msg.BURST]


# --- Client -> server ---------------------------------------------------------------

## ticket is a join ticket from the backend; empty when playing on an offline server,
## which uses display_name instead.
static func encode_hello(display_name: String, ticket := "") -> PackedByteArray:
	var buf := _writer(Msg.HELLO)
	buf.put_u16(VERSION)
	_put_string(buf, display_name.left(MAX_NAME_LENGTH))
	_put_string(buf, ticket.left(MAX_TICKET_LENGTH))
	return buf.data_array


## Returns {version, name, ticket}, or {} if the packet is malformed.
static func decode_hello(buf: StreamPeerBuffer) -> Dictionary:
	if buf.get_available_bytes() < 2:
		return {}
	var version := buf.get_u16()
	var display_name = _get_string(buf, MAX_NAME_LENGTH * 4)
	var ticket = _get_string(buf, MAX_TICKET_LENGTH)
	if display_name == null or ticket == null:
		return {}
	return {"version": version, "name": display_name, "ticket": ticket}


static func encode_inputs(inputs: Array) -> PackedByteArray:
	var buf := _writer(Msg.INPUT)
	buf.put_u8(inputs.size())
	for input: PlayerInput in inputs:
		input.encode(buf)
	return buf.data_array


## Returns the inputs oldest first, or [] if the packet is malformed.
static func decode_inputs(buf: StreamPeerBuffer) -> Array[PlayerInput]:
	var inputs: Array[PlayerInput] = []
	if buf.get_available_bytes() < 1:
		return inputs
	var count := buf.get_u8()
	if count > INPUT_REDUNDANCY or buf.get_available_bytes() < count * PlayerInput.ENCODED_SIZE:
		return inputs
	for i in count:
		inputs.append(PlayerInput.decode(buf))
	return inputs


# --- Server -> client ---------------------------------------------------------------

static func encode_welcome(entity_id: int, position: Vector3, facing: float, zone_id: String) -> PackedByteArray:
	var buf := _writer(Msg.WELCOME)
	buf.put_u32(entity_id)
	_put_vector3(buf, position)
	buf.put_float(facing)
	_put_string(buf, zone_id)
	return buf.data_array


static func decode_welcome(buf: StreamPeerBuffer) -> Dictionary:
	var welcome := {
		"entity_id": buf.get_u32(),
		"position": _get_vector3(buf),
		"facing": buf.get_float(),
	}
	var zone_id = _get_string(buf, 64)
	welcome.zone = zone_id if zone_id != null else Zones.DEFAULT
	return welcome


## Go to another zone's server: connect to host:port and join with ticket.
static func encode_transfer(host: String, port: int, ticket: String, zone_id: String) -> PackedByteArray:
	var buf := _writer(Msg.TRANSFER)
	_put_string(buf, host)
	buf.put_u16(port)
	_put_string(buf, ticket)
	_put_string(buf, zone_id)
	return buf.data_array


static func decode_transfer(buf: StreamPeerBuffer) -> Dictionary:
	var host = _get_string(buf, 256)
	var port := buf.get_u16()
	var ticket = _get_string(buf, MAX_TICKET_LENGTH)
	var zone_id = _get_string(buf, 64)
	if host == null or ticket == null or zone_id == null:
		return {}
	return {"host": host, "port": port, "ticket": ticket, "zone": zone_id}


static func encode_reject(reason: String) -> PackedByteArray:
	var buf := _writer(Msg.REJECT)
	_put_string(buf, reason)
	return buf.data_array


static func decode_reject(buf: StreamPeerBuffer) -> String:
	var reason = _get_string(buf, 256)
	return reason if reason != null else "Rejected by server"


## One snapshot per client per tick. The receiving client's own fighter is sent in full
## (everything PlayerBody.capture_state() holds) for reconciliation, with the tick of the
## last input the server applied for it. Then the other fighters it can see, as entries
## from encode_remote_entry(), then the world effects it can see, as entries from
## encode_effect_entry(). Entries are encoded once per tick and shared by every client.
## claim is the client's remnant-claiming progress, 0-1.
static func encode_snapshot(tick: int, ack_input_tick: int, own: PlayerBody, remote_entries: Array,
		effect_entries: Array, claim: float) -> PackedByteArray:
	var buf := _writer(Msg.SNAPSHOT)
	buf.put_u32(tick)
	buf.put_u32(ack_input_tick)
	buf.put_u8(roundi(clampf(claim, 0.0, 1.0) * 255.0))
	_put_body_state(buf, own.capture_state())
	buf.put_u16(remote_entries.size())
	var bytes := buf.data_array
	for entry: PackedByteArray in remote_entries:
		bytes.append_array(entry)
	bytes.append(effect_entries.size() & 0xFF)
	bytes.append(effect_entries.size() >> 8)
	for entry: PackedByteArray in effect_entries:
		bytes.append_array(entry)
	return bytes


## A world effect ({id, kind, owner, position, velocity, armed, data}). 21 bytes.
static func encode_effect_entry(effect: Dictionary) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u32(effect.id)
	buf.put_u8(effect.kind)
	buf.put_u16(effect.owner)
	_put_fixed(buf, effect.position)
	_put_fixed(buf, effect.velocity)
	buf.put_u8(1 if effect.armed else 0)
	buf.put_u8(effect.get("data", 0))
	return buf.data_array


## A fighter as other clients see it: just enough to draw it. 15 bytes.
static func encode_remote_entry(body: PlayerBody) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u16(body.entity_id)
	_put_fixed(buf, body.global_position)
	buf.put_u8(quantize_angle(body.facing) >> 8)
	buf.put_u8(body.action)
	buf.put_u8(body.action_id)
	buf.put_u8(mini(body.action_tick, 255))
	buf.put_u16(body.health)
	buf.put_u8(body.visual_flags())
	return buf.data_array


static func decode_snapshot(buf: StreamPeerBuffer) -> Dictionary:
	var snapshot := {
		"tick": buf.get_u32(),
		"ack": buf.get_u32(),
		"claim": buf.get_u8() / 255.0,
		"state": _get_body_state(buf),
		"others": [],
		"effects": [],
	}
	var count := buf.get_u16()
	for i in count:
		snapshot.others.append({
			"id": buf.get_u16(),
			"position": _get_fixed(buf),
			"facing": dequantize_angle(buf.get_u8() << 8),
			"action": buf.get_u8(),
			"action_id": buf.get_u8(),
			"action_tick": buf.get_u8(),
			"health": buf.get_u16(),
			"flags": buf.get_u8(),
		})
	var effect_count := buf.get_u16()
	for i in effect_count:
		snapshot.effects.append({
			"id": buf.get_u32(),
			"kind": buf.get_u8(),
			"owner": buf.get_u16(),
			"position": _get_fixed(buf),
			"velocity": _get_fixed(buf),
			"armed": buf.get_u8() != 0,
			"data": buf.get_u8(),
		})
	return snapshot


static func encode_hit(attacker_id: int, target_id: int, result: Combat.Result, damage: int, at: Vector3) -> PackedByteArray:
	var buf := _writer(Msg.HIT)
	buf.put_u32(attacker_id)
	buf.put_u32(target_id)
	buf.put_u8(result)
	buf.put_u16(damage)
	_put_vector3(buf, at)
	return buf.data_array


static func decode_hit(buf: StreamPeerBuffer) -> Dictionary:
	return {
		"attacker": buf.get_u32(),
		"target": buf.get_u32(),
		"result": buf.get_u8(),
		"damage": buf.get_u16(),
		"position": _get_vector3(buf),
	}


## A technique effect went off at a point: a Ruler burst, or a trap detonating.
static func encode_burst(caster_id: int, technique_id: int, at: Vector3) -> PackedByteArray:
	var buf := _writer(Msg.BURST)
	buf.put_u32(caster_id)
	buf.put_u8(technique_id)
	_put_vector3(buf, at)
	return buf.data_array


static func decode_burst(buf: StreamPeerBuffer) -> Dictionary:
	return {"caster": buf.get_u32(), "technique": buf.get_u8(), "position": _get_vector3(buf)}


## Who a fighter is: name, what kind of fighter, species (beasts), rank (artists) and
## max health. Sent when the client first needs it and again whenever it changes.
static func encode_entity_info(entity_id: int, display_name: String, kind: EntityKind, species: int, rank: int,
		max_health: int) -> PackedByteArray:
	var buf := _writer(Msg.ENTITY_INFO)
	buf.put_u32(entity_id)
	_put_string(buf, display_name)
	buf.put_u8(kind)
	buf.put_u8(maxi(species, 0))
	buf.put_u8(rank)
	buf.put_u16(max_health)
	return buf.data_array


static func decode_entity_info(buf: StreamPeerBuffer) -> Dictionary:
	var entity_id := buf.get_u32()
	var display_name = _get_string(buf, MAX_NAME_LENGTH * 4)
	return {
		"id": entity_id,
		"name": display_name if display_name != null else "?",
		"kind": buf.get_u8(),
		"species": buf.get_u8(),
		"rank": buf.get_u8(),
		"max_health": buf.get_u16(),
	}


static func encode_entity_left(entity_id: int) -> PackedByteArray:
	var buf := _writer(Msg.ENTITY_LEFT)
	buf.put_u32(entity_id)
	return buf.data_array


static func encode_request(request: Request, argument := 0) -> PackedByteArray:
	var buf := _writer(Msg.REQUEST)
	buf.put_u8(request)
	buf.put_u8(argument)
	return buf.data_array


## Returns {request, argument}, or {} if malformed.
static func decode_request(buf: StreamPeerBuffer) -> Dictionary:
	if buf.get_available_bytes() < 2:
		return {}
	return {"request": buf.get_u8(), "argument": buf.get_u8()}


static func encode_progress(progress: ProgressState) -> PackedByteArray:
	var buf := _writer(Msg.PROGRESS)
	progress.encode(buf)
	return buf.data_array


## A message for the player's screen ("Claimed a remnant", "Advanced to Copper").
static func encode_notice(text: String) -> PackedByteArray:
	var buf := _writer(Msg.NOTICE)
	_put_string(buf, text)
	return buf.data_array


static func decode_notice(buf: StreamPeerBuffer) -> String:
	var text = _get_string(buf, 512)
	return text if text != null else ""


# --- Helpers ------------------------------------------------------------------------

static func reader(bytes: PackedByteArray) -> StreamPeerBuffer:
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	return buf


static func quantize_angle(radians: float) -> int:
	return roundi(fposmod(radians, TAU) / TAU * 65536.0) % 65536


static func dequantize_angle(quantized: int) -> float:
	return quantized / 65536.0 * TAU


static func _writer(msg: Msg) -> StreamPeerBuffer:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(msg)
	return buf


static func _put_body_state(buf: StreamPeerBuffer, state: Dictionary) -> void:
	_put_vector3(buf, state.position)
	_put_vector3(buf, state.velocity)
	buf.put_float(state.facing)
	buf.put_float(state.dodge_yaw)
	buf.put_u16(state.health)
	buf.put_u8(state.action)
	buf.put_u8(state.action_id)
	buf.put_u16(state.action_tick)
	buf.put_u16(state.action_length)
	buf.put_u16(state.buffered)
	buf.put_u8(state.buffer_ticks)
	buf.put_u8(state.dodge_cooldown)
	buf.put_u16(state.madra)
	buf.put_u8(state.flow)
	buf.put_u16(state.cycle_beat)
	buf.put_u8(state.exhaust_ticks)
	buf.put_u8(1 if state.enforcer_active else 0)


static func _get_body_state(buf: StreamPeerBuffer) -> Dictionary:
	return {
		"position": _get_vector3(buf),
		"velocity": _get_vector3(buf),
		"facing": buf.get_float(),
		"dodge_yaw": buf.get_float(),
		"health": buf.get_u16(),
		"action": buf.get_u8(),
		"action_id": buf.get_u8(),
		"action_tick": buf.get_u16(),
		"action_length": buf.get_u16(),
		"buffered": buf.get_u16(),
		"buffer_ticks": buf.get_u8(),
		"dodge_cooldown": buf.get_u8(),
		"madra": buf.get_u16(),
		"flow": buf.get_u8(),
		"cycle_beat": buf.get_u16(),
		"exhaust_ticks": buf.get_u8(),
		"enforcer_active": buf.get_u8() != 0,
	}


## 16-bit fixed point per axis (1/POSITION_SCALE steps), for positions and velocities.
static func _put_fixed(buf: StreamPeerBuffer, v: Vector3) -> void:
	for axis in 3:
		buf.put_16(clampi(roundi(v[axis] * POSITION_SCALE), -32768, 32767))


static func _get_fixed(buf: StreamPeerBuffer) -> Vector3:
	return Vector3(buf.get_16(), buf.get_16(), buf.get_16()) / POSITION_SCALE


static func _put_vector3(buf: StreamPeerBuffer, v: Vector3) -> void:
	buf.put_float(v.x)
	buf.put_float(v.y)
	buf.put_float(v.z)


static func _get_vector3(buf: StreamPeerBuffer) -> Vector3:
	return Vector3(buf.get_float(), buf.get_float(), buf.get_float())


static func _put_string(buf: StreamPeerBuffer, text: String) -> void:
	var bytes := text.to_utf8_buffer()
	buf.put_u32(bytes.size())
	buf.put_data(bytes)


## Returns null if the length prefix is missing, too long, or past the end of the packet.
static func _get_string(buf: StreamPeerBuffer, max_bytes: int) -> Variant:
	if buf.get_available_bytes() < 4:
		return null
	var size := buf.get_u32()
	if size > max_bytes or size > buf.get_available_bytes():
		return null
	return buf.get_utf8_string(size)
