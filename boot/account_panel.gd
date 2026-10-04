class_name AccountPanel
extends PanelContainer
## Online play: log in or register with the backend, pick or create a character, and
## join. Joining returns a one-time ticket and a shard address; the bootstrap connects
## there with the ticket.

## Emitted when the backend has handed out a ticket for a shard.
signal play(host: String, port: int, ticket: String, character_name: String)
## Emitted when auto_play() can't get into the world.
signal failed(message: String)

## Set game/backend_url in Project Settings before exporting a build for players.
const BACKEND_URL_SETTING := "game/backend_url"

var _backend := BackendClient.new()
var _username := ""
var _selected := {}  # the chosen character

var _url_edit := LineEdit.new()
var _user_edit := LineEdit.new()
var _password_edit := LineEdit.new()
var _login_box := VBoxContainer.new()
var _characters_box := VBoxContainer.new()
var _character_list := VBoxContainer.new()
var _new_name_edit := LineEdit.new()
var _discipline_picker := OptionButton.new()
var _discipline_summary := Label.new()
var _play_button := Button.new()
var _status := Label.new()
var _buttons: Array[Button] = []


func _ready() -> void:
	add_child(_backend)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := Label.new()
	title.text = tr("Play Online")
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	_url_edit.text = ProjectSettings.get_setting(BACKEND_URL_SETTING, "http://127.0.0.1:8080")
	_url_edit.placeholder_text = tr("Backend URL")
	column.add_child(_url_edit)

	_login_box.add_theme_constant_override("separation", 8)
	column.add_child(_login_box)
	_user_edit.placeholder_text = tr("Username")
	_login_box.add_child(_user_edit)
	_password_edit.placeholder_text = tr("Password (8+ characters)")
	_password_edit.secret = true
	_password_edit.text_submitted.connect(func(_text): _on_login(false))
	_login_box.add_child(_password_edit)
	var auth_row := HBoxContainer.new()
	_login_box.add_child(auth_row)
	_add_button(auth_row, tr("Log in"), _on_login.bind(false))
	_add_button(auth_row, tr("Register"), _on_login.bind(true))

	_characters_box.visible = false
	_characters_box.add_theme_constant_override("separation", 8)
	column.add_child(_characters_box)
	_characters_box.add_child(_character_list)
	var create_row := HBoxContainer.new()
	_characters_box.add_child(create_row)
	_new_name_edit.placeholder_text = tr("New character name")
	_new_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_row.add_child(_new_name_edit)
	_add_button(create_row, tr("Create"), _on_create)
	for discipline: Dictionary in Disciplines.ALL:
		_discipline_picker.add_item(tr(discipline.name))
	_discipline_picker.item_selected.connect(_show_discipline)
	_characters_box.add_child(_discipline_picker)
	_discipline_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_discipline_summary.modulate = Color(1, 1, 1, 0.7)
	_characters_box.add_child(_discipline_summary)
	_show_discipline(0)
	_play_button.text = tr("Enter the world")
	_play_button.disabled = true
	_play_button.pressed.connect(_on_play)
	_characters_box.add_child(_play_button)
	_buttons.append(_play_button)

	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status)


func set_backend_url(url: String) -> void:
	_url_edit.text = url


## Logs in (registering the account if it doesn't exist), creates the character if
## needed, and joins with it. Used by --account/--character for bots and scripts.
func auto_play(username: String, password: String, character_name: String, discipline := "enforcer") -> void:
	_user_edit.text = username
	_password_edit.text = password
	if not await _authenticate(false, true) and not await _authenticate(true):
		failed.emit(_status.text)
		return
	var characters := await _load_characters()
	var match_found := characters.filter(func(c: Dictionary): return String(c.name).to_lower() == character_name.to_lower())
	if match_found.is_empty():
		var created := await _backend.request_json(HTTPClient.METHOD_POST, "/characters",
			{"name": character_name, "discipline": discipline})
		if not created.ok:
			_show_status(created.error, true)
			failed.emit(created.error)
			return
		_selected = created.data.character
	else:
		_selected = match_found[0]
	if not await _on_play():
		failed.emit(_status.text)


func _on_login(register: bool) -> void:
	if await _authenticate(register):
		await _load_characters()


## quiet: don't report failure (auto_play tries logging in before registering).
func _authenticate(register: bool, quiet := false) -> bool:
	_busy(true, tr("Registering...") if register else tr("Logging in..."))
	_backend.base_url = _url_edit.text.strip_edges()
	_backend.token = ""
	var result := await _backend.request_json(HTTPClient.METHOD_POST, "/auth/register" if register else "/auth/login",
		{"username": _user_edit.text.strip_edges(), "password": _password_edit.text})
	_busy(false)
	if not result.ok:
		if not quiet:
			_show_status(result.error, true)
		return false
	_backend.token = result.data.token
	_username = result.data.username
	_login_box.visible = false
	_characters_box.visible = true
	_show_status(tr("Logged in as %s") % _username)
	return true


func _load_characters() -> Array:
	var result := await _backend.request_json(HTTPClient.METHOD_GET, "/characters")
	if not result.ok:
		_show_status(result.error, true)
		return []
	for child in _character_list.get_children():
		child.queue_free()
	var characters: Array = result.data.get("characters", [])
	for character: Dictionary in characters:
		var progress := ProgressState.from_dict(character.progress if character.progress is Dictionary else {})
		var button := Button.new()
		button.toggle_mode = true
		button.text = "%s  ·  %s %s" % [character.name, Advancement.rank_name(progress.rank),
			Disciplines.display_name(str(character.get("discipline", "")))]
		button.pressed.connect(_select.bind(character, button))
		_character_list.add_child(button)
	if characters.is_empty():
		_show_status(tr("Create your first character"))
	return characters


func _show_discipline(index: int) -> void:
	var discipline: Dictionary = Disciplines.ALL[index]
	_discipline_summary.text = tr("%s: %s (+%d talent points in its branch, permanently)") % [
		tr(discipline.name), tr(discipline.summary), Disciplines.DISCIPLINE_BONUS_POINTS]


func _select(character: Dictionary, chosen: Button) -> void:
	_selected = character
	for button in _character_list.get_children():
		button.button_pressed = button == chosen
	_play_button.disabled = false


func _on_create() -> void:
	_busy(true, tr("Creating..."))
	var discipline: Dictionary = Disciplines.ALL[_discipline_picker.selected]
	var result := await _backend.request_json(HTTPClient.METHOD_POST, "/characters",
		{"name": _new_name_edit.text.strip_edges(), "discipline": discipline.id})
	_busy(false)
	if not result.ok:
		_show_status(result.error, true)
		return
	_new_name_edit.text = ""
	await _load_characters()
	_show_status(tr("Created %s") % result.data.character.name)


## Returns whether a ticket was obtained (and play emitted).
func _on_play() -> bool:
	if _selected.is_empty():
		return false
	_busy(true, tr("Joining..."))
	var result := await _backend.request_json(HTTPClient.METHOD_POST, "/characters/%d/join" % int(_selected.id))
	_busy(false)
	if not result.ok:
		_show_status(result.error, true)
		return false
	var shard: Dictionary = result.data.shard
	_show_status(tr("Joining %s...") % shard.name)
	play.emit(String(shard.host), int(shard.port), String(result.data.ticket), String(_selected.name))
	return true


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	_buttons.append(button)


func _busy(busy: bool, text := "") -> void:
	for button in _buttons:
		button.disabled = busy or (button == _play_button and _selected.is_empty())
	if busy:
		_show_status(text)


func _show_status(text: String, error := false) -> void:
	_status.text = text
	_status.modulate = Color(1.0, 0.55, 0.5) if error else Color(1, 1, 1, 0.8)
