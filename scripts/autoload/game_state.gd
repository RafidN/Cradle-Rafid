extends Node
## Run data for the current playthrough.

var abilities := {
	&"double_jump": false,
	&"dash": false,
	&"wall_jump": false,
}
var current_checkpoint: StringName = &""
var motes := 0
var play_time := 0.0


func _process(delta: float) -> void:
	play_time += delta


func has_ability(ability: StringName) -> bool:
	return abilities.get(ability, false)


func unlock(ability: StringName) -> void:
	if abilities.get(ability, false):
		return
	abilities[ability] = true
	Events.ability_unlocked.emit(ability)


func to_dict() -> Dictionary:
	return {
		"abilities": abilities,
		"current_checkpoint": String(current_checkpoint),
		"motes": motes,
		"play_time": play_time,
	}


func from_dict(data: Dictionary) -> void:
	for key in data.get("abilities", {}):
		abilities[StringName(key)] = data["abilities"][key]
	current_checkpoint = StringName(data.get("current_checkpoint", ""))
	motes = data.get("motes", 0)
	play_time = data.get("play_time", 0.0)
