class_name PlayerInput
extends RefCounted
## One tick of player intent. Inputs are the only thing a client may send; the server
## turns them into movement and actions. Values are stored at wire precision so the
## predicting client simulates exactly what the server will receive.

const JUMP := 1 << 0
const LIGHT := 1 << 1
const HEAVY := 1 << 2
const DODGE := 1 << 3
## Held rather than pressed: set on every tick block is down.
const BLOCK := 1 << 4
## Locked on to a target; the aim yaw is valid.
const LOCKED := 1 << 5

## Bytes per input on the wire: u32 tick, s8 move x, s8 move y, u16 yaw, u8 buttons,
## u16 aim, u32 view tick, u8 view tick fraction.
const ENCODED_SIZE := 16

var tick := 0
var buttons := 0
## Server tick (with fraction) of the world this client was showing when it produced the
## input. The server uses it for lag compensation; the simulation ignores it.
var view_tick := 0.0

var _move_x := 0
var _move_y := 0
var _yaw := 0
var _aim := 0


## Movement stick, x = right and y = back (Input.get_vector order).
func set_move(move: Vector2) -> void:
	move = move.limit_length(1.0)
	_move_x = roundi(move.x * 127.0)
	_move_y = roundi(move.y * 127.0)


func get_move() -> Vector2:
	return (Vector2(_move_x, _move_y) / 127.0).limit_length(1.0)


## Camera yaw in radians. Movement is relative to it.
func set_yaw(radians: float) -> void:
	_yaw = Protocol.quantize_angle(radians)


func get_yaw() -> float:
	return Protocol.dequantize_angle(_yaw)


## Yaw from the player toward the lock-on target. Only meaningful with LOCKED.
func set_aim(radians: float) -> void:
	_aim = Protocol.quantize_angle(radians)


func get_aim() -> float:
	return Protocol.dequantize_angle(_aim)


func is_pressed(button: int) -> bool:
	return buttons & button != 0


func encode(buf: StreamPeerBuffer) -> void:
	var view := maxf(view_tick, 0.0)
	buf.put_u32(tick)
	buf.put_8(_move_x)
	buf.put_8(_move_y)
	buf.put_u16(_yaw)
	buf.put_u8(buttons)
	buf.put_u16(_aim)
	buf.put_u32(floori(view))
	buf.put_u8(floori(fmod(view, 1.0) * 256.0))


static func decode(buf: StreamPeerBuffer) -> PlayerInput:
	var input := PlayerInput.new()
	input.tick = buf.get_u32()
	input._move_x = clampi(buf.get_8(), -127, 127)
	input._move_y = clampi(buf.get_8(), -127, 127)
	input._yaw = buf.get_u16()
	input.buttons = buf.get_u8()
	input._aim = buf.get_u16()
	input.view_tick = buf.get_u32() + buf.get_u8() / 256.0
	return input
