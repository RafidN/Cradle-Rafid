class_name Ways
extends RefCounted
## Every Way: shared/data/ways/*.tres. Until Way selection exists (roadmap Phase 4),
## every practitioner follows DEFAULT.

const DEFAULT := &"kindled_flame"

static var registry := ContentRegistry.new("res://shared/data/ways")


static func get_way(id: StringName) -> WayData:
	return registry.by_id(id) as WayData


## Technique net ids by slot for a Way.
static func loadout(way_id: StringName) -> PackedInt32Array:
	var slots := PackedInt32Array()
	var way := get_way(way_id)
	if way:
		for technique_id in way.techniques:
			slots.append(Techniques.registry.net_id_of(technique_id))
	return slots
