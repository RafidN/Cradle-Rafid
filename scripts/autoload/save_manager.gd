extends Node
## Saves and loads GameState to user://save.json.

const SAVE_PATH := "user://save.json"


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not open save file: %s" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(GameState.to_dict()))


func load_game() -> bool:
	if not has_save():
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if data is Dictionary:
		GameState.from_dict(data)
		return true
	return false
