class_name ProgressionPanel
extends PanelContainer
## Rank, essence and sigils, with buttons to craft sigils and break through to the
## next rank. Everything here is a request; the server checks it and answers with a
## PROGRESS update and a notice.

signal craft_requested(sigil: int)
signal advance_requested

var _rank_label := Label.new()
var _next_label := Label.new()
var _essence_label := Label.new()
var _sigil_rows: Array[Dictionary] = []  # {label, button}
var _advance_button := Button.new()
var _advance_hint := Label.new()


func _ready() -> void:
	custom_minimum_size = Vector2(440, 0)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := Label.new()
	title.text = tr("Advancement")
	title.add_theme_font_size_override("font_size", 26)
	column.add_child(title)
	_rank_label.add_theme_font_size_override("font_size", 20)
	column.add_child(_rank_label)
	_next_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_next_label)
	column.add_child(HSeparator.new())
	column.add_child(_essence_label)
	column.add_child(HSeparator.new())

	var sigils_title := Label.new()
	sigils_title.text = tr("Sigils")
	sigils_title.add_theme_font_size_override("font_size", 18)
	column.add_child(sigils_title)
	for sigil in Advancement.sigil_count():
		var row := HBoxContainer.new()
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var button := Button.new()
		button.text = tr("Craft")
		button.pressed.connect(func(): craft_requested.emit(sigil))
		row.add_child(button)
		column.add_child(row)
		_sigil_rows.append({"label": label, "button": button})

	column.add_child(HSeparator.new())
	_advance_button.pressed.connect(func(): advance_requested.emit())
	column.add_child(_advance_button)
	_advance_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_advance_hint.modulate = Color(1, 1, 1, 0.7)
	column.add_child(_advance_hint)

	var close_hint := Label.new()
	close_hint.text = tr("P to close")
	close_hint.modulate = Color(1, 1, 1, 0.5)
	column.add_child(close_hint)


func show_progress(progress: ProgressState, meditating: bool) -> void:
	var rank := Advancement.rank(progress.rank)
	_rank_label.text = tr("%s  —  %d HP, %d spirit, %d techniques") % [
		tr(rank.display_name), progress.max_health(), progress.spirit_capacity() / PlayerBody.SPIRIT_SCALE, rank.technique_slots]

	var has_next := progress.rank + 1 < Advancement.rank_count()
	if has_next:
		var next := Advancement.rank(progress.rank + 1)
		var needs := tr("%d essence (you have %d)") % [next.essence_cost, progress.total_essence()]
		var required := Advancement.sigils.net_id_of(next.required_sigil)
		if required >= 0:
			needs += tr(" and a %s") % tr(Advancement.sigil(required).display_name)
		_next_label.text = tr("Next: %s needs %s.") % [tr(next.display_name), needs]
	else:
		_next_label.text = tr("You stand at the peak of what this world allows. For now.")

	var lines := PackedStringArray()
	for aspect in progress.essence.size():
		lines.append(tr("%s essence: %d") % [tr(Advancement.ASPECT_NAMES[aspect]), progress.essence[aspect]])
	_essence_label.text = "\n".join(lines)

	for sigil in _sigil_rows.size():
		var info := Advancement.sigil(sigil)
		var cost := PackedStringArray()
		for aspect in info.cost.size():
			if info.cost[aspect] > 0:
				cost.append("%d %s" % [info.cost[aspect], tr(Advancement.ASPECT_NAMES[aspect]).to_lower()])
		var row: Dictionary = _sigil_rows[sigil]
		row.label.text = tr("%s (%d/%d)\n%s\nCost: %s") % [tr(info.display_name), progress.sigils[sigil], info.max_count,
			tr(info.description), ", ".join(cost)]
		var error := progress.craft_error(sigil)
		row.button.disabled = not error.is_empty()
		row.button.tooltip_text = Text.render(error)

	var advance_error := progress.advance_error(meditating)
	_advance_button.visible = has_next
	_advance_button.text = tr("Break through to %s") % tr(Advancement.rank_name(progress.rank + 1)) if has_next else ""
	_advance_button.disabled = not advance_error.is_empty()
	_advance_hint.text = Text.render(advance_error) if has_next else ""
