class_name Beasts
extends RefCounted
## Every spirit beast species: shared/data/beasts/*.tres. The constants are net ids of
## species the code refers to directly; a test checks they match the data.

enum { EMBER_HOUND, STONEBACK_BOAR, GALE_FOX }

static var registry := ContentRegistry.new("res://shared/data/beasts")


static func get_beast(net_id: int) -> BeastData:
	return registry.by_net_id(net_id) as BeastData


static func by_id(id: StringName) -> BeastData:
	return registry.by_id(id) as BeastData
