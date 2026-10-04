class_name ProgressState
extends RefCounted
## One sacred artist's progression: rank, essence and bindings. The server owns the real
## one and sends copies to the client, which uses them to show the progression panel.

var rank := Advancement.Rank.FOUNDATION
var essence := PackedInt32Array([0, 0, 0])
var bindings := PackedInt32Array([0, 0])


func total_essence() -> int:
	var total := 0
	for amount in essence:
		total += amount
	return total


func add_essence(aspect: int, amount: int) -> void:
	essence[aspect] = mini(essence[aspect] + amount, 0xFFFF)


## Why the binding can't be crafted, or "" if it can.
func craft_error(binding: int) -> String:
	if binding < 0 or binding >= Advancement.BINDINGS.size():
		return "Unknown binding"
	var info: Dictionary = Advancement.BINDINGS[binding]
	if bindings[binding] >= info.max:
		return "You can't hold more %ss" % info.name
	if binding == Advancement.Binding.IRON_BODY and rank >= Advancement.Rank.IRON:
		return "Your body is already Iron"
	for aspect in essence.size():
		if essence[aspect] < info.cost[aspect]:
			return "Not enough %s essence" % Advancement.ASPECT_NAMES[aspect].to_lower()
	return ""


func craft(binding: int) -> void:
	var info: Dictionary = Advancement.BINDINGS[binding]
	for aspect in essence.size():
		essence[aspect] -= info.cost[aspect]
	bindings[binding] += 1


## Why the artist can't advance, or "" if they can. Breakthroughs happen while cycling.
func advance_error(cycling: bool) -> String:
	if rank + 1 >= Advancement.RANKS.size():
		return "No higher rank yet"
	var next: Dictionary = Advancement.RANKS[rank + 1]
	if total_essence() < next.essence:
		return "Need %d essence to reach %s" % [next.essence, next.name]
	if next.binding >= 0 and bindings[next.binding] < 1:
		return "Need a %s to reach %s" % [Advancement.BINDINGS[next.binding].name, next.name]
	if not cycling:
		return "Sit and cycle (C) to break through"
	return ""


## Spends the essence (largest pools first) and binding, and raises the rank.
func advance() -> void:
	var next: Dictionary = Advancement.RANKS[rank + 1]
	var owed: int = next.essence
	while owed > 0:
		var largest := 0
		for aspect in essence.size():
			if essence[aspect] > essence[largest]:
				largest = aspect
		var taken := mini(owed, essence[largest])
		essence[largest] -= taken
		owed -= taken
	if next.binding >= 0:
		bindings[next.binding] -= 1
	rank += 1


func max_health() -> int:
	return Advancement.RANKS[rank].max_health


func madra_capacity() -> int:
	var whole: int = Advancement.RANKS[rank].max_madra + bindings[Advancement.Binding.KINDLED_CORE] * Advancement.KINDLED_CORE_MADRA
	return whole * PlayerBody.MADRA_SCALE


func technique_slots() -> int:
	return Advancement.RANKS[rank].technique_slots


func damage_mult() -> float:
	return Advancement.RANKS[rank].damage_mult


func knockback_taken_mult() -> float:
	return Advancement.RANKS[rank].knockback_taken_mult


func apply_to(body: PlayerBody) -> void:
	body.apply_stats(max_health(), madra_capacity(), technique_slots(), damage_mult(), knockback_taken_mult(), 1.0)


## The saved form (stored as JSON by the backend).
func to_dict() -> Dictionary:
	return {"rank": rank, "essence": Array(essence), "bindings": Array(bindings)}


## Tolerates missing or malformed fields (e.g. a brand-new character's empty save).
static func from_dict(data: Dictionary) -> ProgressState:
	var state := ProgressState.new()
	state.rank = clampi(int(data.get("rank", 0)), 0, Advancement.RANKS.size() - 1)
	var saved_essence: Array = data.get("essence", []) if data.get("essence") is Array else []
	for aspect in mini(saved_essence.size(), state.essence.size()):
		state.essence[aspect] = clampi(int(saved_essence[aspect]), 0, 0xFFFF)
	var saved_bindings: Array = data.get("bindings", []) if data.get("bindings") is Array else []
	for binding in mini(saved_bindings.size(), state.bindings.size()):
		state.bindings[binding] = clampi(int(saved_bindings[binding]), 0, Advancement.BINDINGS[binding].max)
	return state


func encode(buf: StreamPeerBuffer) -> void:
	buf.put_u8(rank)
	for amount in essence:
		buf.put_u16(amount)
	for count in bindings:
		buf.put_u8(count)


static func decode(buf: StreamPeerBuffer) -> ProgressState:
	var state := ProgressState.new()
	state.rank = clampi(buf.get_u8(), 0, Advancement.RANKS.size() - 1)
	for aspect in state.essence.size():
		state.essence[aspect] = buf.get_u16()
	for binding in state.bindings.size():
		state.bindings[binding] = buf.get_u8()
	return state
