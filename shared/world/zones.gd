class_name Zones
extends RefCounted
## Every zone of the world: shared/data/zones/*.tres. Each zone runs on its own game
## server; portals carry players between zones (through the backend, so only online).

const DEFAULT := &"proving_grounds"

static var registry := ContentRegistry.new("res://shared/data/zones")


static func get_zone(zone_id: StringName) -> ZoneData:
	return registry.by_id(zone_id) as ZoneData


static func display_name(zone_id: StringName) -> String:
	var zone := get_zone(zone_id)
	return zone.display_name if zone else String(zone_id)


## A spawn point with a little random spread so arrivals don't stack.
static func spawn_point(zone_id: StringName, spawn_name: String) -> Vector3:
	var zone := get_zone(zone_id)
	var spawns: Dictionary = zone.spawns if zone else {}
	var base: Vector3 = spawns.get(spawn_name, spawns.get("default", Vector3(0.0, 0.5, 0.0)))
	return base + Vector3(randf_range(-2.5, 2.5), 0.0, randf_range(-2.5, 2.5))
