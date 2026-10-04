class_name ZoneData
extends ContentData
## A zone of the world. Each zone runs on its own game server; portals carry players
## between zones.

@export var display_name := ""
@export_file("*.tscn") var scene_path := ""
## Height (and distance) of the server window's overview camera.
@export var overview := 30.0
## Named arrival points (String -> Vector3). "default" is also where the fallen respawn.
@export var spawns := {}
@export var portals: Array[ZonePortal] = []
@export var dummies: Array[ZoneDummy] = []
@export var dens: Array[ZoneDen] = []
