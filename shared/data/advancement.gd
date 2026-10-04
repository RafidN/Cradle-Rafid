class_name Advancement
extends RefCounted
## The ranks of spirit practice, the aspects of essence that echoes yield, and the
## sigils crafted from essence. Shared so the client can show what's affordable; the
## server decides.

enum Aspect { FIRE, EARTH, WIND }
enum Rank { IRON, BRONZE, SILVER }
enum Sigil { TEMPERED_BODY, KINDLED_CORE }

const ASPECT_NAMES := ["Fire", "Earth", "Wind"]
const ASPECT_COLORS := [Color(1.0, 0.5, 0.15), Color(0.8, 0.6, 0.3), Color(0.55, 0.95, 0.85)]

## Per rank: stats, how many technique slots are open, and what advancing INTO it costs
## (total essence of any aspect, plus a sigil that is consumed, or -1).
const RANKS := [
	{"name": "Iron", "max_health": 100, "max_spirit": 100, "technique_slots": 2,
		"damage_mult": 1.0, "knockback_taken_mult": 1.0, "essence": 0, "sigil": -1},
	{"name": "Bronze", "max_health": 115, "max_spirit": 140, "technique_slots": 3,
		"damage_mult": 1.05, "knockback_taken_mult": 1.0, "essence": 60, "sigil": -1},
	{"name": "Silver", "max_health": 160, "max_spirit": 160, "technique_slots": 4,
		"damage_mult": 1.15, "knockback_taken_mult": 0.7, "essence": 100, "sigil": Sigil.TEMPERED_BODY},
]

## cost is essence per aspect, indexed by Aspect.
const SIGILS := [
	{"name": "Tempered Body Sigil", "cost": [20, 40, 0], "max": 1,
		"description": "Earth and fire essence forged into a body sigil. Required to advance to Silver."},
	{"name": "Kindled Core Sigil", "cost": [30, 0, 0], "max": 2,
		"description": "Fire essence bound into the core: +15 spirit capacity."},
]
const KINDLED_CORE_SPIRIT := 15

## Essence a fallen spirit practitioner leaves behind (always of their Way's aspect).
const PRACTITIONER_ECHO_ESSENCE := 6
const PRACTITIONER_ECHO_ASPECT := Aspect.FIRE


static func rank_name(rank: int) -> String:
	return RANKS[rank].name if rank >= 0 and rank < RANKS.size() else "?"


## The rank a technique slot opens at.
static func slot_unlock_rank(slot: int) -> int:
	for rank in RANKS.size():
		if RANKS[rank].technique_slots > slot:
			return rank
	return RANKS.size() - 1
