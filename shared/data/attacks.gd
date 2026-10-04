class_name Attacks
extends RefCounted
## Registry of every attack. An attack's id is its index in ALL; ids go over the network.

enum { LIGHT_1, LIGHT_2, LIGHT_3, HEAVY }

const ALL := [
	preload("res://shared/data/attacks/light_1.tres"),
	preload("res://shared/data/attacks/light_2.tres"),
	preload("res://shared/data/attacks/light_3.tres"),
	preload("res://shared/data/attacks/heavy.tres"),
]


static func get_attack(id: int) -> AttackData:
	return ALL[id] if id >= 0 and id < ALL.size() else null
