class_name PlayerInput
extends RefCounted
## One tick of player intent. Inputs are the only thing a client may send; the server
## turns them into movement. Values are stored at wire precision so the predicting
## client simulates exactly what the server will receive.

const JUMP := 1 << 0

## Bytes per input on the wire: u32 tick, s8 move x, s8 move y, u16 yaw, u8 buttons.
const ENCODED_SIZE := 9

var tick := 0
var buttons := 0

var _move_x := 0
var _move_y := 0
var _yaw := 0


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


func is_pressed(button: int) -> bool:
	return buttons & button != 0


func encode(buf: StreamPeerBuffer) -> void:
	buf.put_u32(tick)
	buf.put_8(_move_x)
	buf.put_8(_move_y)
	buf.put_u16(_yaw)
	buf.put_u8(buttons)


static func decode(buf: StreamPeerBuffer) -> PlayerInput:
	var input := PlayerInput.new()
	input.tick = buf.get_u32()
	input._move_x = clampi(buf.get_8(), -127, 127)
	input._move_y = clampi(buf.get_8(), -127, 127)
	input._yaw = buf.get_u16()
	input.buttons = buf.get_u8()
	return input
