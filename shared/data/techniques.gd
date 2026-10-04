class_name Techniques
extends RefCounted
## Registry of every technique; a technique's id is its index in ALL. For now every
## sacred artist follows the Path of Kindled Flame, and technique slot N casts id N.

enum { FLAME_BODY, EMBER_LANCE, SEARING_RING, CINDER_TRAP }

const PATH_NAME := "Path of Kindled Flame"
const ALL := [
	preload("res://shared/data/techniques/flame_body.tres"),
	preload("res://shared/data/techniques/ember_lance.tres"),
	preload("res://shared/data/techniques/searing_ring.tres"),
	preload("res://shared/data/techniques/cinder_trap.tres"),
]


static func get_technique(id: int) -> TechniqueData:
	return ALL[id] if id >= 0 and id < ALL.size() else null
