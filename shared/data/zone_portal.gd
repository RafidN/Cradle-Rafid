class_name ZonePortal
extends Resource
## Walking within radius of position sends a player to to_zone, arriving at to_spawn.

@export var position := Vector3.ZERO
@export var radius := 1.6
@export var to_zone: StringName
@export var to_spawn := "default"
