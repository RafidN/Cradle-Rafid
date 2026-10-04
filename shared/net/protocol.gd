class_name Protocol
extends RefCounted
## Wire format shared by client and server. Every packet starts with a u8 Msg type and
## is little-endian. Bump VERSION whenever the format changes.

const VERSION := 1
const DEFAULT_PORT := 7777
const MAX_PLAYERS := 100
const TICK_RATE := 30
## How many of the newest inputs each INPUT packet repeats, so one lost packet costs nothing.
const INPUT_REDUNDANCY := 6
const MAX_NAME_LENGTH := 16

enum Msg { HELLO, WELCOME, REJECT, INPUT, SNAPSHOT, PLAYER_JOINED, PLAYER_LEFT }


static func is_reliable(msg: int) -> bool:
	return msg != Msg.INPUT and msg != Msg.SNAPSHOT


# --- Client -> server ---------------------------------------------------------------

static func encode_hello(display_name: String) -> PackedByteArray:
	var buf := _writer(Msg.HELLO)
	buf.put_u16(VERSION)
	_put_string(buf, display_name.left(MAX_NAME_LENGTH))
	return buf.data_array


## Returns {version, name}, or {} if the packet is malformed.
static func decode_hello(buf: StreamPeerBuffer) -> Dictionary:
	if buf.get_available_bytes() < 2:
		return {}
	var version := buf.get_u16()
	var display_name = _get_string(buf, MAX_NAME_LENGTH * 4)
	if display_name == null:
		return {}
	return {"version": version, "name": display_name}


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

static func encode_welcome(entity_id: int, position: Vector3, facing: float) -> PackedByteArray:
	var buf := _writer(Msg.WELCOME)
	buf.put_u32(entity_id)
	_put_vector3(buf, position)
	buf.put_float(facing)
	return buf.data_array


static func decode_welcome(buf: StreamPeerBuffer) -> Dictionary:
	return {
		"entity_id": buf.get_u32(),
		"position": _get_vector3(buf),
		"facing": buf.get_float(),
	}


static func encode_reject(reason: String) -> PackedByteArray:
	var buf := _writer(Msg.REJECT)
	_put_string(buf, reason)
	return buf.data_array


static func decode_reject(buf: StreamPeerBuffer) -> String:
	var reason = _get_string(buf, 256)
	return reason if reason != null else "Rejected by server"


## One snapshot per client per tick. The receiving client's own body is sent in full
## (position, velocity, facing) for reconciliation, together with the tick of the last
## input the server applied for it. Everyone else is sent as position + facing.
static func encode_snapshot(tick: int, ack_input_tick: int, own: PlayerBody, bodies: Array) -> PackedByteArray:
	var buf := _writer(Msg.SNAPSHOT)
	buf.put_u32(tick)
	buf.put_u32(ack_input_tick)
	_put_vector3(buf, own.global_position)
	_put_vector3(buf, own.velocity)
	buf.put_float(own.facing)
	buf.put_u16(bodies.size() - 1)
	for body: PlayerBody in bodies:
		if body == own:
			continue
		buf.put_u32(body.entity_id)
		_put_vector3(buf, body.global_position)
		buf.put_u16(quantize_angle(body.facing))
	return buf.data_array


static func decode_snapshot(buf: StreamPeerBuffer) -> Dictionary:
	var snapshot := {
		"tick": buf.get_u32(),
		"ack": buf.get_u32(),
		"position": _get_vector3(buf),
		"velocity": _get_vector3(buf),
		"facing": buf.get_float(),
		"others": [],
	}
	var count := buf.get_u16()
	for i in count:
		snapshot.others.append({
			"id": buf.get_u32(),
			"position": _get_vector3(buf),
			"facing": dequantize_angle(buf.get_u16()),
		})
	return snapshot


static func encode_player_joined(entity_id: int, display_name: String) -> PackedByteArray:
	var buf := _writer(Msg.PLAYER_JOINED)
	buf.put_u32(entity_id)
	_put_string(buf, display_name)
	return buf.data_array


static func decode_player_joined(buf: StreamPeerBuffer) -> Dictionary:
	var entity_id := buf.get_u32()
	var display_name = _get_string(buf, MAX_NAME_LENGTH * 4)
	return {"id": entity_id, "name": display_name if display_name != null else "?"}


static func encode_player_left(entity_id: int) -> PackedByteArray:
	var buf := _writer(Msg.PLAYER_LEFT)
	buf.put_u32(entity_id)
	return buf.data_array


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
