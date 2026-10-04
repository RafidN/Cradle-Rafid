class_name EchoField
extends RefCounted
## Echoes left by the fallen. Claim one by standing next to it and holding interact,
## without acting or moving away, for CLAIM_TICKS. Whoever made the kill has it to
## themselves for EXCLUSIVE_TICKS; after that anyone can claim it. Unclaimed echoes
## fade after LIFETIME_TICKS.

const CLAIM_TICKS := 60
const CLAIM_RADIUS := 2.2
const EXCLUSIVE_TICKS := 300
const LIFETIME_TICKS := 2700
## Most echoes a zone holds; the oldest fade first.
const MAX_ECHOS := 120
## Echo ids share the snapshot's effect id space with technique effects.
const FIRST_ID := 1 << 24


class Echo:
	var id := 0
	var aspect := 0
	var essence := 0
	var owner_id := 0
	var source_name := ""
	var position := Vector3.ZERO
	var age := 0

	func is_claimable_by(entity_id: int) -> bool:
		return owner_id == 0 or owner_id == entity_id or age >= EXCLUSIVE_TICKS


var _echoes: Array[Echo] = []
var _claims := {}  # entity_id -> {"echo": id, "ticks": int}
var _next_id := FIRST_ID


## owner_id 0 means anyone may claim it from the start.
func spawn(at: Vector3, aspect: int, essence: int, owner_id: int, source_name: String) -> void:
	var echo := Echo.new()
	echo.id = _next_id
	_next_id += 1
	echo.aspect = aspect
	echo.essence = essence
	echo.owner_id = owner_id
	echo.source_name = source_name
	echo.position = at + Vector3.UP * 0.9
	_echoes.append(echo)
	if _echoes.size() > MAX_ECHOS:
		_echoes.pop_front()


## claimants: [{body: PlayerBody, interacting: bool}] for every spirit practitioner.
## Returns [[entity_id, Echo]] for each claim completed this tick.
func update(claimants: Array) -> Array:
	for echo in _echoes:
		echo.age += 1
	_echoes = _echoes.filter(func(r: Echo): return r.age < LIFETIME_TICKS)

	var completed := []
	for claimant: Dictionary in claimants:
		var body: PlayerBody = claimant.body
		var echo := _claimable_near(body) if claimant.interacting and _can_claim(body) else null
		if echo == null:
			_claims.erase(body.entity_id)
			continue
		var claim: Dictionary = _claims.get(body.entity_id, {})
		if claim.get("echo") != echo.id:
			claim = {"echo": echo.id, "ticks": 0}
		claim.ticks += 1
		_claims[body.entity_id] = claim
		if claim.ticks >= CLAIM_TICKS:
			completed.append([body.entity_id, echo])
			_echoes.erase(echo)
			_claims.erase(body.entity_id)
	return completed


## How far along the practitioner's current claim is, 0-1.
func progress_of(entity_id: int) -> float:
	return _claims.get(entity_id, {}).get("ticks", 0) / float(CLAIM_TICKS)


func remove_owner(entity_id: int) -> void:
	_claims.erase(entity_id)
	for echo in _echoes:
		if echo.owner_id == entity_id:
			echo.owner_id = 0


## Snapshot entries, in Protocol's effect format. owner is 0 once anyone may claim it.
func snapshot_entries() -> Array:
	var entries := []
	for echo in _echoes:
		var owner := 0 if echo.age >= EXCLUSIVE_TICKS else echo.owner_id
		entries.append({"id": echo.id, "kind": Protocol.Effect.ECHO, "owner": owner,
			"position": echo.position, "velocity": Vector3.ZERO, "armed": true, "data": echo.aspect})
	return entries


func count() -> int:
	return _echoes.size()


func _can_claim(body: PlayerBody) -> bool:
	return body.action == PlayerBody.Action.NONE and Vector2(body.velocity.x, body.velocity.z).length() < 0.5


func _claimable_near(body: PlayerBody) -> Echo:
	var nearest: Echo = null
	var nearest_distance := CLAIM_RADIUS
	for echo in _echoes:
		var offset := echo.position - body.global_position
		var distance := Vector2(offset.x, offset.z).length()
		if distance <= nearest_distance and echo.is_claimable_by(body.entity_id):
			nearest = echo
			nearest_distance = distance
	return nearest
