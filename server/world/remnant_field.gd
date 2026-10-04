class_name RemnantField
extends RefCounted
## Remnants left by the fallen. Claim one by standing next to it and holding interact,
## without acting or moving away, for CLAIM_TICKS. Whoever made the kill has it to
## themselves for EXCLUSIVE_TICKS; after that anyone can claim it. Unclaimed remnants
## fade after LIFETIME_TICKS.

const CLAIM_TICKS := 60
const CLAIM_RADIUS := 2.2
const EXCLUSIVE_TICKS := 300
const LIFETIME_TICKS := 2700
## Remnant ids share the snapshot's effect id space with technique effects.
const FIRST_ID := 1 << 24


class Remnant:
	var id := 0
	var aspect := 0
	var essence := 0
	var owner_id := 0
	var source_name := ""
	var position := Vector3.ZERO
	var age := 0

	func is_claimable_by(entity_id: int) -> bool:
		return owner_id == 0 or owner_id == entity_id or age >= EXCLUSIVE_TICKS


var _remnants: Array[Remnant] = []
var _claims := {}  # entity_id -> {"remnant": id, "ticks": int}
var _next_id := FIRST_ID


## owner_id 0 means anyone may claim it from the start.
func spawn(at: Vector3, aspect: int, essence: int, owner_id: int, source_name: String) -> void:
	var remnant := Remnant.new()
	remnant.id = _next_id
	_next_id += 1
	remnant.aspect = aspect
	remnant.essence = essence
	remnant.owner_id = owner_id
	remnant.source_name = source_name
	remnant.position = at + Vector3.UP * 0.9
	_remnants.append(remnant)


## claimants: [{body: PlayerBody, interacting: bool}] for every sacred artist.
## Returns [[entity_id, Remnant]] for each claim completed this tick.
func update(claimants: Array) -> Array:
	for remnant in _remnants:
		remnant.age += 1
	_remnants = _remnants.filter(func(r: Remnant): return r.age < LIFETIME_TICKS)

	var completed := []
	for claimant: Dictionary in claimants:
		var body: PlayerBody = claimant.body
		var remnant := _claimable_near(body) if claimant.interacting and _can_claim(body) else null
		if remnant == null:
			_claims.erase(body.entity_id)
			continue
		var claim: Dictionary = _claims.get(body.entity_id, {})
		if claim.get("remnant") != remnant.id:
			claim = {"remnant": remnant.id, "ticks": 0}
		claim.ticks += 1
		_claims[body.entity_id] = claim
		if claim.ticks >= CLAIM_TICKS:
			completed.append([body.entity_id, remnant])
			_remnants.erase(remnant)
			_claims.erase(body.entity_id)
	return completed


## How far along the artist's current claim is, 0-1.
func progress_of(entity_id: int) -> float:
	return _claims.get(entity_id, {}).get("ticks", 0) / float(CLAIM_TICKS)


func remove_owner(entity_id: int) -> void:
	_claims.erase(entity_id)
	for remnant in _remnants:
		if remnant.owner_id == entity_id:
			remnant.owner_id = 0


## Snapshot entries, in Protocol's effect format. owner is 0 once anyone may claim it.
func snapshot_entries() -> Array:
	var entries := []
	for remnant in _remnants:
		var owner := 0 if remnant.age >= EXCLUSIVE_TICKS else remnant.owner_id
		entries.append({"id": remnant.id, "kind": Protocol.Effect.REMNANT, "owner": owner,
			"position": remnant.position, "velocity": Vector3.ZERO, "armed": true, "data": remnant.aspect})
	return entries


func count() -> int:
	return _remnants.size()


func _can_claim(body: PlayerBody) -> bool:
	return body.action == PlayerBody.Action.NONE and Vector2(body.velocity.x, body.velocity.z).length() < 0.5


func _claimable_near(body: PlayerBody) -> Remnant:
	var nearest: Remnant = null
	var nearest_distance := CLAIM_RADIUS
	for remnant in _remnants:
		var offset := remnant.position - body.global_position
		var distance := Vector2(offset.x, offset.z).length()
		if distance <= nearest_distance and remnant.is_claimable_by(body.entity_id):
			nearest = remnant
			nearest_distance = distance
	return nearest
