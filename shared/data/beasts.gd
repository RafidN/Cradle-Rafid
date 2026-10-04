class_name Beasts
extends RefCounted
## Registry of sacred beast species; a species id is its index in ALL.

enum { EMBER_HOUND, STONEBACK_BOAR, GALE_FOX }

const ALL := [
	preload("res://shared/data/beasts/ember_hound.tres"),
	preload("res://shared/data/beasts/stoneback_boar.tres"),
	preload("res://shared/data/beasts/gale_fox.tres"),
]


static func get_beast(id: int) -> BeastData:
	return ALL[id] if id >= 0 and id < ALL.size() else null
