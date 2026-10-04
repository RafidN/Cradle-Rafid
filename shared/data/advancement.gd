class_name Advancement
extends RefCounted
## The ranks of the sacred arts, the aspects of essence that remnants yield, and the
## bindings crafted from essence. Shared so the client can show what's affordable; the
## server decides. (Rank names are working names from the Cradle books.)

enum Aspect { FIRE, EARTH, WIND }
enum Rank { FOUNDATION, COPPER, IRON }
enum Binding { IRON_BODY, KINDLED_CORE }

const ASPECT_NAMES := ["Fire", "Earth", "Wind"]
const ASPECT_COLORS := [Color(1.0, 0.5, 0.15), Color(0.8, 0.6, 0.3), Color(0.55, 0.95, 0.85)]

## Per rank: stats, how many technique slots are open, and what advancing INTO it costs
## (total essence of any aspect, plus a binding that is consumed, or -1).
const RANKS := [
	{"name": "Foundation", "max_health": 100, "max_madra": 100, "technique_slots": 2,
		"damage_mult": 1.0, "knockback_taken_mult": 1.0, "essence": 0, "binding": -1},
	{"name": "Copper", "max_health": 115, "max_madra": 140, "technique_slots": 3,
		"damage_mult": 1.05, "knockback_taken_mult": 1.0, "essence": 60, "binding": -1},
	{"name": "Iron", "max_health": 160, "max_madra": 160, "technique_slots": 4,
		"damage_mult": 1.15, "knockback_taken_mult": 0.7, "essence": 100, "binding": Binding.IRON_BODY},
]

## cost is essence per aspect, indexed by Aspect.
const BINDINGS := [
	{"name": "Iron Body Binding", "cost": [20, 40, 0], "max": 1,
		"description": "Earth and fire essence forged into a body binding. Required to advance to Iron."},
	{"name": "Kindled Core Binding", "cost": [30, 0, 0], "max": 2,
		"description": "Fire essence bound into the core: +15 madra capacity."},
]
const KINDLED_CORE_MADRA := 15

## Essence a fallen sacred artist leaves behind (always of their Path's aspect).
const ARTIST_REMNANT_ESSENCE := 6
const ARTIST_REMNANT_ASPECT := Aspect.FIRE


static func rank_name(rank: int) -> String:
	return RANKS[rank].name if rank >= 0 and rank < RANKS.size() else "?"


## The rank a technique slot opens at.
static func slot_unlock_rank(slot: int) -> int:
	for rank in RANKS.size():
		if RANKS[rank].technique_slots > slot:
			return rank
	return RANKS.size() - 1
