class_name Zones
extends RefCounted
## Every zone of the world. Each zone runs on its own game server; portals carry players
## between zones (through the backend, so only in online mode). Shared so client and
## server agree on the map, spawn points and portals.

const DEFAULT := "proving_grounds"

## spawns: named arrival points ("default" is also where the fallen respawn).
## portals: walking within radius of position sends you to to_zone, arriving at to_spawn.
## dummies / dens: what the zone's server spawns.
const ALL := {
	"proving_grounds": {
		"name": "Proving Grounds",
		"scene": "res://shared/world/test_arena.tscn",
		## Height (and distance) of the server window's overview camera.
		"overview": 28.0,
		"spawns": {
			"default": Vector3(0.0, 0.5, 4.0),
			"from_wilds": Vector3(0.0, 0.5, -21.0),
		},
		"portals": [
			{"position": Vector3(0.0, 0.0, -27.5), "radius": 1.6, "to_zone": "ember_wilds", "to_spawn": "from_grounds"},
		],
		"dummies": [
			{"name": "Training Dummy", "position": Vector3(-3.0, 0.5, -3.0), "block": false},
			{"name": "Guarding Dummy", "position": Vector3(3.0, 0.5, -3.0), "block": true},
		],
		"dens": [
			{"species": Beasts.EMBER_HOUND, "position": Vector3(-18.0, 0.5, 14.0)},
			{"species": Beasts.EMBER_HOUND, "position": Vector3(-22.0, 0.5, 20.0)},
			{"species": Beasts.GALE_FOX, "position": Vector3(-20.0, 0.5, -18.0)},
			{"species": Beasts.GALE_FOX, "position": Vector3(18.0, 0.5, 18.0)},
		],
	},
	"ember_wilds": {
		"name": "Ember Wilds",
		"scene": "res://shared/world/ember_wilds.tscn",
		"overview": 95.0,
		"spawns": {
			"default": Vector3(0.0, 0.5, 66.0),
			"from_grounds": Vector3(0.0, 0.5, 66.0),
		},
		"portals": [
			{"position": Vector3(0.0, 0.0, 73.0), "radius": 1.6, "to_zone": "proving_grounds", "to_spawn": "from_wilds"},
		],
		"dummies": [],
		"dens": [
			{"species": Beasts.EMBER_HOUND, "position": Vector3(-30.0, 0.5, 40.0)},
			{"species": Beasts.EMBER_HOUND, "position": Vector3(-38.0, 0.5, 30.0)},
			{"species": Beasts.EMBER_HOUND, "position": Vector3(35.0, 0.5, 35.0)},
			{"species": Beasts.EMBER_HOUND, "position": Vector3(-55.0, 0.5, -10.0)},
			{"species": Beasts.EMBER_HOUND, "position": Vector3(-48.0, 0.5, -20.0)},
			{"species": Beasts.EMBER_HOUND, "position": Vector3(10.0, 0.5, 10.0)},
			{"species": Beasts.GALE_FOX, "position": Vector3(50.0, 0.5, -5.0)},
			{"species": Beasts.GALE_FOX, "position": Vector3(58.0, 0.5, 8.0)},
			{"species": Beasts.GALE_FOX, "position": Vector3(-20.0, 0.5, -45.0)},
			{"species": Beasts.GALE_FOX, "position": Vector3(-10.0, 0.5, -55.0)},
			{"species": Beasts.STONEBACK_BOAR, "position": Vector3(40.0, 0.5, -45.0)},
			{"species": Beasts.STONEBACK_BOAR, "position": Vector3(25.0, 0.5, -60.0)},
			{"species": Beasts.STONEBACK_BOAR, "position": Vector3(-60.0, 0.5, 55.0)},
			{"species": Beasts.STONEBACK_BOAR, "position": Vector3(0.0, 0.5, -20.0)},
		],
	},
}


static func get_zone(zone_id: String) -> Dictionary:
	return ALL.get(zone_id, {})


static func display_name(zone_id: String) -> String:
	return get_zone(zone_id).get("name", zone_id)


## A spawn point with a little random spread so arrivals don't stack.
static func spawn_point(zone_id: String, spawn_name: String) -> Vector3:
	var spawns: Dictionary = get_zone(zone_id).get("spawns", {})
	var base: Vector3 = spawns.get(spawn_name, spawns.get("default", Vector3(0.0, 0.5, 0.0)))
	return base + Vector3(randf_range(-2.5, 2.5), 0.0, randf_range(-2.5, 2.5))
