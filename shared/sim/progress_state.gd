class_name ProgressState
extends RefCounted
## One spirit practitioner's progression: rank, essence and sigils. The server owns the real
## one and sends copies to the client, which uses them to show the progression panel.

var rank := Advancement.Rank.IRON
var essence := PackedInt32Array([0, 0, 0])
var sigils := PackedInt32Array([0, 0])


func total_essence() -> int:
	var total := 0
	for amount in essence:
		total += amount
	return total


func add_essence(aspect: int, amount: int) -> void:
	essence[aspect] = mini(essence[aspect] + amount, 0xFFFF)


## Why the sigil can't be crafted, or "" if it can.
func craft_error(sigil: int) -> String:
	if sigil < 0 or sigil >= Advancement.SIGILS.size():
		return "Unknown sigil"
	var info: Dictionary = Advancement.SIGILS[sigil]
	if sigils[sigil] >= info.max:
		return "You can't hold more %ss" % info.name
	if sigil == Advancement.Sigil.TEMPERED_BODY and rank >= Advancement.Rank.SILVER:
		return "Your body is already Silver"
	for aspect in essence.size():
		if essence[aspect] < info.cost[aspect]:
			return "Not enough %s essence" % Advancement.ASPECT_NAMES[aspect].to_lower()
	return ""


func craft(sigil: int) -> void:
	var info: Dictionary = Advancement.SIGILS[sigil]
	for aspect in essence.size():
		essence[aspect] -= info.cost[aspect]
	sigils[sigil] += 1


## Why the practitioner can't advance, or "" if they can. Breakthroughs happen while meditating.
func advance_error(meditating: bool) -> String:
	if rank + 1 >= Advancement.RANKS.size():
		return "No higher rank yet"
	var next: Dictionary = Advancement.RANKS[rank + 1]
	if total_essence() < next.essence:
		return "Need %d essence to reach %s" % [next.essence, next.name]
	if next.sigil >= 0 and sigils[next.sigil] < 1:
		return "Need a %s to reach %s" % [Advancement.SIGILS[next.sigil].name, next.name]
	if not meditating:
		return "Sit and meditate (C) to break through"
	return ""


## Spends the essence (largest pools first) and sigil, and raises the rank.
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
	if next.sigil >= 0:
		sigils[next.sigil] -= 1
	rank += 1


func max_health() -> int:
	return Advancement.RANKS[rank].max_health


func spirit_capacity() -> int:
	var whole: int = Advancement.RANKS[rank].max_spirit + sigils[Advancement.Sigil.KINDLED_CORE] * Advancement.KINDLED_CORE_SPIRIT
	return whole * PlayerBody.SPIRIT_SCALE


func technique_slots() -> int:
	return Advancement.RANKS[rank].technique_slots


func damage_mult() -> float:
	return Advancement.RANKS[rank].damage_mult


func knockback_taken_mult() -> float:
	return Advancement.RANKS[rank].knockback_taken_mult


func apply_to(body: PlayerBody) -> void:
	body.apply_stats(max_health(), spirit_capacity(), technique_slots(), damage_mult(), knockback_taken_mult(), 1.0)


## The saved form (stored as JSON by the backend).
func to_dict() -> Dictionary:
	return {"rank": rank, "essence": Array(essence), "sigils": Array(sigils)}


## Tolerates missing or malformed fields (e.g. a brand-new character's empty save).
static func from_dict(data: Dictionary) -> ProgressState:
	var state := ProgressState.new()
	state.rank = clampi(int(data.get("rank", 0)), 0, Advancement.RANKS.size() - 1)
	var saved_essence: Array = data.get("essence", []) if data.get("essence") is Array else []
	for aspect in mini(saved_essence.size(), state.essence.size()):
		state.essence[aspect] = clampi(int(saved_essence[aspect]), 0, 0xFFFF)
	var saved_sigils: Array = data.get("sigils", []) if data.get("sigils") is Array else []
	for sigil in mini(saved_sigils.size(), state.sigils.size()):
		state.sigils[sigil] = clampi(int(saved_sigils[sigil]), 0, Advancement.SIGILS[sigil].max)
	return state


func encode(buf: StreamPeerBuffer) -> void:
	buf.put_u8(rank)
	for amount in essence:
		buf.put_u16(amount)
	for count in sigils:
		buf.put_u8(count)


static func decode(buf: StreamPeerBuffer) -> ProgressState:
	var state := ProgressState.new()
	state.rank = clampi(buf.get_u8(), 0, Advancement.RANKS.size() - 1)
	for aspect in state.essence.size():
		state.essence[aspect] = buf.get_u16()
	for sigil in state.sigils.size():
		state.sigils[sigil] = buf.get_u8()
	return state
