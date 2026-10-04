class_name Attacks
extends RefCounted
## Every attack: shared/data/attacks/*.tres. The constants are net ids of attacks the code
## refers to directly; a test checks they match the data.

enum { LIGHT_1, LIGHT_2, LIGHT_3, HEAVY }

static var registry := ContentRegistry.new("res://shared/data/attacks")


static func get_attack(net_id: int) -> AttackData:
	return registry.by_net_id(net_id) as AttackData
