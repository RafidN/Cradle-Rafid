class_name HitHistory
extends RefCounted
## Where every fighter was, and whether it was invulnerable, on each recent server tick.
## Hit checks rewind targets to the tick the attacker was looking at (lag compensation).

const MAX_TICKS := 32

var _frames := {}  # tick -> {entity_id: [position, invulnerable]}


func record(tick: int, bodies: Array) -> void:
	var frame := {}
	for body: PlayerBody in bodies:
		frame[body.entity_id] = [body.global_position, body.is_invulnerable()]
	_frames[tick] = frame
	_frames.erase(tick - MAX_TICKS)


## Returns {position, invulnerable} interpolated at a fractional tick, or {} if the
## entity has no recorded state there.
func sample(entity_id: int, tick: float) -> Dictionary:
	var base := floori(tick)
	var a = _frames.get(base, {}).get(entity_id)
	var b = _frames.get(base + 1, {}).get(entity_id)
	if a == null and b == null:
		return {}
	if a == null or b == null:
		var only: Array = a if a != null else b
		return {"position": only[0], "invulnerable": only[1]}
	return {
		"position": a[0].lerp(b[0], tick - base),
		"invulnerable": a[1] or b[1],
	}
