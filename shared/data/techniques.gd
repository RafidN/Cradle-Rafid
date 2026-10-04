class_name Techniques
extends RefCounted
## Every technique: shared/data/techniques/*.tres. Which techniques a practitioner can
## cast comes from their Way (see Ways). The constants are net ids of techniques the code
## refers to directly; a test checks they match the data.

enum { FLAME_BODY, EMBER_LANCE, SEARING_RING, CINDER_TRAP }

static var registry := ContentRegistry.new("res://shared/data/techniques")


static func get_technique(net_id: int) -> TechniqueData:
	return registry.by_net_id(net_id) as TechniqueData
