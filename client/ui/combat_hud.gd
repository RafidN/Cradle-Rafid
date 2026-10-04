class_name CombatHud
extends CanvasLayer
## Health, madra, techniques, lock-on target, cycling meter and the debug overlay.

const TECHNIQUE_KEYS := ["1", "2", "3", "4"]
const SLOT_READY := Color(1, 1, 1)
const SLOT_OVERDRAW := Color(1.0, 0.55, 0.45)
const SLOT_UNAVAILABLE := Color(1, 1, 1, 0.35)
const SLOT_ACTIVE := Color(1.0, 0.6, 0.2)
const MADRA_COLOR := Color(0.3, 0.6, 1.0)
const EXHAUSTED_COLOR := Color(0.45, 0.45, 0.5)
const FEEDBACK_SECONDS := 0.8

var _slots: Array[Label] = []
var _madra_fill := StyleBoxFlat.new()
var _last_flow := 0
var _last_cycle_beat := 0
var _feedback_timer := 0.0

@onready var debug_label: Label = $Debug
@onready var hint_label: Label = $Hint
@onready var _health_bar: ProgressBar = $HealthBar
@onready var _madra_bar: ProgressBar = $MadraBar
@onready var _madra_label: Label = $MadraBar/Value
@onready var _status_label: Label = $StatusLabel
@onready var _technique_bar: HBoxContainer = $TechniqueBar
@onready var _target_label: Label = $TargetLabel
@onready var _death_label: Label = $DeathLabel
@onready var _cycling_meter: CyclingMeter = $CyclingMeter
@onready var _feedback_label: Label = $CyclingMeter/Feedback


func _ready() -> void:
	_madra_fill.bg_color = MADRA_COLOR
	_madra_bar.add_theme_stylebox_override("fill", _madra_fill)
	_madra_bar.max_value = PlayerBody.MAX_MADRA
	for slot in Techniques.ALL.size():
		var technique := Techniques.get_technique(slot)
		var label := Label.new()
		label.text = "[%s] %s  %d" % [TECHNIQUE_KEYS[slot], technique.display_name, technique.cost]
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 4)
		_technique_bar.add_child(label)
		_slots.append(label)


func show_fighter(body: PlayerBody) -> void:
	_health_bar.value = body.health
	_madra_bar.value = body.madra
	_madra_label.text = "%d / %d" % [body.madra / PlayerBody.MADRA_SCALE, PlayerBody.MAX_MADRA / PlayerBody.MADRA_SCALE]
	_madra_fill.bg_color = EXHAUSTED_COLOR if body.is_exhausted() else MADRA_COLOR
	_death_label.visible = body.is_dead()

	var status := PackedStringArray()
	if body.is_exhausted():
		status.append("EXHAUSTED")
	if body.enforcer_active:
		status.append("Flame Body")
	if body.action == PlayerBody.Action.CYCLE:
		var per_second := PlayerBody.CYCLE_REGEN * (1 + body.flow) * Protocol.TICK_RATE / float(PlayerBody.MADRA_SCALE)
		status.append("Cycling  —  flow %d  (+%.1f madra/s)" % [body.flow, per_second])
	_status_label.text = "   ".join(status)

	for slot in _slots.size():
		var technique := Techniques.get_technique(slot)
		var color := SLOT_READY
		if technique.kind == TechniqueData.Kind.ENFORCER and body.enforcer_active:
			color = SLOT_ACTIVE
		elif not body.can_cast():
			color = SLOT_UNAVAILABLE
		elif body.madra < technique.cost * PlayerBody.MADRA_SCALE:
			color = SLOT_OVERDRAW
		_slots[slot].modulate = color

	_show_cycling(body)


func show_target(text: String) -> void:
	_target_label.visible = not text.is_empty()
	_target_label.text = text


func _show_cycling(body: PlayerBody) -> void:
	var cycling := body.action == PlayerBody.Action.CYCLE
	_cycling_meter.visible = cycling
	if not cycling:
		_last_flow = 0
		_last_cycle_beat = 0
		return
	# Smooth between physics ticks so the breath doesn't step.
	_cycling_meter.show_breath(body.action_tick + Engine.get_physics_interpolation_fraction(), body.flow)
	if body.cycle_beat != _last_cycle_beat:
		if body.flow > _last_flow:
			_feedback("Good breath", Color(0.5, 1.0, 0.7))
		elif body.flow == 0 and _last_flow > 0:
			_feedback("Breath broken", Color(1.0, 0.5, 0.4))
		elif body.flow < _last_flow:
			_feedback("Missed", Color(1.0, 0.8, 0.4))
	_last_flow = body.flow
	_last_cycle_beat = body.cycle_beat


func _feedback(text: String, color: Color) -> void:
	_feedback_label.text = text
	_feedback_label.modulate = color
	_feedback_timer = FEEDBACK_SECONDS


func _process(delta: float) -> void:
	_feedback_timer = maxf(_feedback_timer - delta, 0.0)
	_feedback_label.modulate.a = clampf(_feedback_timer / FEEDBACK_SECONDS * 2.0, 0.0, 1.0)
