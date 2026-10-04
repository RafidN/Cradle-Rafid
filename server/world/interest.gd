class_name Interest
extends RefCounted
## Which fighters a player is told about (interest management). A fighter comes into
## view within ENTER_RADIUS and stays in view until it's beyond LEAVE_RADIUS, so things
## at the edge don't flicker in and out. Fighters beyond NEAR_RADIUS are only sent every
## FAR_INTERVAL ticks: far away, 10 updates a second interpolate just as smoothly.

const ENTER_RADIUS := 55.0
const LEAVE_RADIUS := 65.0
const NEAR_RADIUS := 25.0
const FAR_INTERVAL := 3
## Stationary world effects (traps, echoes) are resent this often; projectiles every tick.
const STATIC_EFFECT_INTERVAL := 6

## Entity ids currently in view, for hysteresis.
var _in_view := {}


## Indices into positions/ids of the fighters to include in this tick's snapshot.
## The viewer's own fighter must not be in the list.
func select(viewer: Vector3, ids: PackedInt32Array, positions: PackedVector3Array, tick: int) -> PackedInt32Array:
	var chosen := PackedInt32Array()
	var enter_sq := ENTER_RADIUS * ENTER_RADIUS
	var leave_sq := LEAVE_RADIUS * LEAVE_RADIUS
	var near_sq := NEAR_RADIUS * NEAR_RADIUS
	for i in ids.size():
		var id := ids[i]
		var distance_sq := viewer.distance_squared_to(positions[i])
		if distance_sq > (leave_sq if _in_view.has(id) else enter_sq):
			_in_view.erase(id)
			continue
		_in_view[id] = true
		if distance_sq > near_sq and (tick + id) % FAR_INTERVAL != 0:
			continue
		chosen.append(i)
	return chosen


## Indices of the effects to include this tick: those within view, with stationary
## ones only every STATIC_EFFECT_INTERVAL ticks.
static func select_effects(viewer: Vector3, ids: PackedInt32Array, positions: PackedVector3Array,
		stationary: PackedByteArray, tick: int) -> PackedInt32Array:
	var chosen := PackedInt32Array()
	var leave_sq := LEAVE_RADIUS * LEAVE_RADIUS
	for i in ids.size():
		if stationary[i] and (tick + ids[i]) % STATIC_EFFECT_INTERVAL != 0:
			continue
		if viewer.distance_squared_to(positions[i]) <= leave_sq:
			chosen.append(i)
	return chosen


## Whether a point (an effect, a hit) is close enough for this viewer to care about.
static func can_see(viewer: Vector3, point: Vector3) -> bool:
	return viewer.distance_squared_to(point) <= LEAVE_RADIUS * LEAVE_RADIUS


func forget(entity_id: int) -> void:
	_in_view.erase(entity_id)
