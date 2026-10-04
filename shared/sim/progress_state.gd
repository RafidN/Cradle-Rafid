class_name ProgressState
extends RefCounted
## One spirit practitioner's progression: rank, essence and sigils. The server owns the real
## one and sends copies to the client, which uses them to show the progression panel.

## Version of the saved form (to_dict). Bump it and add a step to _migrate() when it changes.
const SAVE_VERSION := 2

var rank := Advancement.Rank.IRON
var essence := PackedInt32Array([0, 0, 0])
## Count held of each sigil, indexed by sigil net id.
var sigils := PackedInt32Array()


func _init() -> void:
	sigils.resize(Advancement.sigil_count())


func total_essence() -> int:
	var total := 0
	for amount in essence:
		total += amount
	return total


func add_essence(aspect: int, amount: int) -> void:
	essence[aspect] = mini(essence[aspect] + amount, 0xFFFF)


## Why the sigil can't be crafted, or "" if it can.
func craft_error(sigil: int) -> String:
	var info := Advancement.sigil(sigil)
	if info == null:
		return "Unknown sigil"
	if sigils[sigil] >= info.max_count:
		return "You can't hold more %ss" % info.display_name
	if info.obsolete_at_rank >= 0 and rank >= info.obsolete_at_rank:
		return "You've already advanced past needing a %s" % info.display_name
	for aspect in essence.size():
		if essence[aspect] < info.cost[aspect]:
			return "Not enough %s essence" % Advancement.ASPECT_NAMES[aspect].to_lower()
	return ""


func craft(sigil: int) -> void:
	var info := Advancement.sigil(sigil)
	for aspect in essence.size():
		essence[aspect] -= info.cost[aspect]
	sigils[sigil] += 1


## Why the practitioner can't advance, or "" if they can. Breakthroughs happen while meditating.
func advance_error(meditating: bool) -> String:
	if rank + 1 >= Advancement.rank_count():
		return "No higher rank yet"
	var next := Advancement.rank(rank + 1)
	if total_essence() < next.essence_cost:
		return "Need %d essence to reach %s" % [next.essence_cost, next.display_name]
	var required := Advancement.sigils.net_id_of(next.required_sigil)
	if required >= 0 and sigils[required] < 1:
		return "Need a %s to reach %s" % [Advancement.sigil(required).display_name, next.display_name]
	if not meditating:
		return "Sit and meditate (C) to break through"
	return ""


## Spends the essence (largest pools first) and sigil, and raises the rank.
func advance() -> void:
	var next := Advancement.rank(rank + 1)
	var owed := next.essence_cost
	while owed > 0:
		var largest := 0
		for aspect in essence.size():
			if essence[aspect] > essence[largest]:
				largest = aspect
		var taken := mini(owed, essence[largest])
		essence[largest] -= taken
		owed -= taken
	var required := Advancement.sigils.net_id_of(next.required_sigil)
	if required >= 0:
		sigils[required] -= 1
	rank += 1


func max_health() -> int:
	return Advancement.rank(rank).max_health


func spirit_capacity() -> int:
	var whole := Advancement.rank(rank).max_spirit
	for sigil in sigils.size():
		whole += sigils[sigil] * Advancement.sigil(sigil).spirit_capacity_bonus
	return whole * PlayerBody.SPIRIT_SCALE


func technique_slots() -> int:
	return Advancement.rank(rank).technique_slots


func damage_mult() -> float:
	return Advancement.rank(rank).damage_mult


func knockback_taken_mult() -> float:
	return Advancement.rank(rank).knockback_taken_mult


func apply_to(body: PlayerBody) -> void:
	body.apply_stats(max_health(), spirit_capacity(), technique_slots(), damage_mult(), knockback_taken_mult(), 1.0)


## The saved form (stored as JSON by the backend). Ranks and sigils are saved by their
## stable string ids, so reordering or adding content never scrambles saves.
func to_dict() -> Dictionary:
	var held := {}
	for sigil in sigils.size():
		if sigils[sigil] > 0:
			held[String(Advancement.sigil(sigil).id)] = sigils[sigil]
	return {
		"version": SAVE_VERSION,
		"rank": String(Advancement.rank(rank).id),
		"essence": Array(essence),
		"sigils": held,
	}


## Tolerates missing or malformed fields (e.g. a brand-new character's empty save) and
## upgrades saves written by older versions.
static func from_dict(saved: Dictionary) -> ProgressState:
	var data := _migrate(saved.duplicate(true))
	var state := ProgressState.new()
	var rank_id := Advancement.ranks.net_id_of(StringName(str(data.get("rank", ""))))
	state.rank = maxi(rank_id, 0)
	var saved_essence: Array = data.get("essence", []) if data.get("essence") is Array else []
	for aspect in mini(saved_essence.size(), state.essence.size()):
		state.essence[aspect] = clampi(int(saved_essence[aspect]), 0, 0xFFFF)
	var saved_sigils: Dictionary = data.get("sigils", {}) if data.get("sigils") is Dictionary else {}
	for sigil_id in saved_sigils:
		var sigil := Advancement.sigils.net_id_of(StringName(str(sigil_id)))
		if sigil >= 0:
			state.sigils[sigil] = clampi(int(saved_sigils[sigil_id]), 0, Advancement.sigil(sigil).max_count)
	return state


## Upgrades a save to SAVE_VERSION one step at a time.
static func _migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 1))
	if version < 2:
		# v1 saved the rank and sigils by position; v2 saves them by id.
		var rank_position := int(data.get("rank", 0)) if not (data.get("rank") is String) else 0
		var old_rank := Advancement.rank(clampi(rank_position, 0, Advancement.rank_count() - 1))
		data.rank = String(old_rank.id)
		var by_id := {}
		var old_sigils: Array = data.get("sigils", []) if data.get("sigils") is Array else []
		for position in old_sigils.size():
			var sigil := Advancement.sigil(position)
			if sigil and int(old_sigils[position]) > 0:
				by_id[String(sigil.id)] = int(old_sigils[position])
		data.sigils = by_id
	data.version = SAVE_VERSION
	return data


func encode(buf: StreamPeerBuffer) -> void:
	buf.put_u8(rank)
	for amount in essence:
		buf.put_u16(amount)
	buf.put_u8(sigils.size())
	for count in sigils:
		buf.put_u8(count)


static func decode(buf: StreamPeerBuffer) -> ProgressState:
	var state := ProgressState.new()
	state.rank = clampi(buf.get_u8(), 0, Advancement.rank_count() - 1)
	for aspect in state.essence.size():
		state.essence[aspect] = buf.get_u16()
	var count := buf.get_u8()
	for sigil in count:
		var held := buf.get_u8()
		if sigil < state.sigils.size():
			state.sigils[sigil] = held
	return state
