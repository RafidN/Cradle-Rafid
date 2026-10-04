extends Node
## Global signal bus. Emit and connect here to keep systems decoupled.

signal player_died
signal checkpoint_activated(id: StringName)
signal ability_unlocked(ability: StringName)
signal mote_collected
signal level_change_requested(path: String, spawn_id: StringName)
signal game_completed
