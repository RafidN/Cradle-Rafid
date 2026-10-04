class_name CombatHud
extends CanvasLayer
## Health, spirit, techniques, lock-on target, meditating meter and the debug overlay.

const TECHNIQUE_KEYS := ["1", "2", "3", "4"]
const SLOT_READY := Color(1, 1, 1)
const SLOT_OVERDRAW := Color(1.0, 0.55, 0.45)
const SLOT_UNAVAILABLE := Color(1, 1, 1, 0.35)
const SLOT_ACTIVE := Color(1.0, 0.6, 0.2)
const SPIRIT_COLOR := Color(0.3, 0.6, 1.0)
const EXHAUSTED_COLOR := Color(0.45, 0.45, 0.5)
const FEEDBACK_SECONDS := 0.8
const NOTICE_SECONDS := 5.0
const MAX_NOTICES := 4

var _slots: Array[Label] = []
var _shown_loadout := PackedInt32Array()
var _spirit_fill := StyleBoxFlat.new()
var _last_flow := 0
var _last_breath_beat := 0
var _feedback_timer := 0.0
var _notices: Array[Dictionary] = []  # {text, time_left}

@onready var debug_label: Label = $Debug
@onready var hint_label: Label = $Hint
@onready var _health_bar: ProgressBar = $HealthBar
@onready var _spirit_bar: ProgressBar = $SpiritBar
@onready var _spirit_label: Label = $SpiritBar/Value
@onready var _status_label: Label = $StatusLabel
@onready var _technique_bar: HBoxContainer = $TechniqueBar
@onready var _target_label: Label = $TargetLabel
@onready var _death_label: Label = $DeathLabel
@onready var _meditation_meter: MeditationMeter = $MeditationMeter
@onready var _feedback_label: Label = $MeditationMeter/Feedback
@onready var _claim_bar: ProgressBar = $ClaimBar
@onready var _interact_label: Label = $InteractLabel
@onready var _notice_label: Label = $NoticeLabel
@onready var progression_panel: ProgressionPanel = $ProgressionPanel


func _ready() -> void:
	_spirit_fill.bg_color = SPIRIT_COLOR
	_spirit_bar.add_theme_stylebox_override("fill", _spirit_fill)


## One label per technique slot, rebuilt whenever the fighter's loadout changes.
func _build_technique_bar(loadout: PackedInt32Array) -> void:
	_shown_loadout = loadout.duplicate()
	for label in _slots:
		label.queue_free()
	_slots.clear()
	for slot in loadout.size():
		var technique := Techniques.get_technique(loadout[slot])
		if technique == null:
			continue
		var label := Label.new()
		label.set_meta("text", "[%s] %s  %d" % [TECHNIQUE_KEYS[slot], tr(technique.display_name), technique.cost])
		label.set_meta("technique", loadout[slot])
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 4)
		_technique_bar.add_child(label)
		_slots.append(label)


func show_fighter(body: PlayerBody) -> void:
	_health_bar.max_value = body.max_health
	_health_bar.value = body.health
	_spirit_bar.max_value = body.spirit_capacity
	_spirit_bar.value = body.spirit
	_spirit_label.text = "%d / %d" % [body.spirit / PlayerBody.SPIRIT_SCALE, body.spirit_capacity / PlayerBody.SPIRIT_SCALE]
	_spirit_fill.bg_color = EXHAUSTED_COLOR if body.is_exhausted() else SPIRIT_COLOR
	_death_label.visible = body.is_dead()

	var status := PackedStringArray()
	if body.is_exhausted():
		status.append(tr("EXHAUSTED"))
	if body.enforcer_active:
		status.append(tr("Flame Body"))
	if body.action == PlayerBody.Action.MEDITATE:
		var per_second := PlayerBody.MEDITATION_REGEN * (1 + body.flow) * Protocol.TICK_RATE / float(PlayerBody.SPIRIT_SCALE)
		status.append(tr("Meditating  —  flow %d  (+%.1f spirit/s)") % [body.flow, per_second])
	_status_label.text = "   ".join(status)

	if body.loadout != _shown_loadout:
		_build_technique_bar(body.loadout)
	for slot in _slots.size():
		var technique := Techniques.get_technique(_slots[slot].get_meta("technique"))
		var color := SLOT_READY
		var locked := slot >= body.technique_slots
		_slots[slot].text = _slots[slot].get_meta("text") + (
			tr("  (%s)") % tr(Advancement.rank_name(Advancement.slot_unlock_rank(slot))) if locked else "")
		if locked:
			color = SLOT_UNAVAILABLE
		elif technique.kind == TechniqueData.Kind.ENFORCER and body.enforcer_active:
			color = SLOT_ACTIVE
		elif not body.can_cast():
			color = SLOT_UNAVAILABLE
		elif body.spirit < technique.cost * PlayerBody.SPIRIT_SCALE:
			color = SLOT_OVERDRAW
		_slots[slot].modulate = color

	_show_meditation(body)


## progress: 0-1 claim progress. can_claim: a claimable echo is within reach.
func show_claim(progress: float, can_claim: bool) -> void:
	_claim_bar.visible = progress > 0.0
	_claim_bar.value = progress
	_interact_label.visible = can_claim and progress <= 0.0


func notify(text: String) -> void:
	_notices.append({"text": text, "time_left": NOTICE_SECONDS})
	if _notices.size() > MAX_NOTICES:
		_notices.pop_front()
	_refresh_notices()


func _refresh_notices() -> void:
	_notice_label.text = "\n".join(_notices.map(func(n: Dictionary): return n.text))


func show_target(text: String) -> void:
	_target_label.visible = not text.is_empty()
	_target_label.text = text


func _show_meditation(body: PlayerBody) -> void:
	var meditating := body.action == PlayerBody.Action.MEDITATE
	_meditation_meter.visible = meditating
	if not meditating:
		_last_flow = 0
		_last_breath_beat = 0
		return
	# Smooth between physics ticks so the breath doesn't step.
	_meditation_meter.show_breath(body.action_tick + Engine.get_physics_interpolation_fraction(), body.flow)
	if body.breath_beat != _last_breath_beat:
		if body.flow > _last_flow:
			_feedback(tr("Good breath"), Color(0.5, 1.0, 0.7))
		elif body.flow == 0 and _last_flow > 0:
			_feedback(tr("Breath broken"), Color(1.0, 0.5, 0.4))
		elif body.flow < _last_flow:
			_feedback(tr("Missed"), Color(1.0, 0.8, 0.4))
	_last_flow = body.flow
	_last_breath_beat = body.breath_beat


func _feedback(text: String, color: Color) -> void:
	_feedback_label.text = text
	_feedback_label.modulate = color
	_feedback_timer = FEEDBACK_SECONDS


func _process(delta: float) -> void:
	if not _notices.is_empty():
		for notice in _notices:
			notice.time_left -= delta
		var before := _notices.size()
		_notices = _notices.filter(func(n: Dictionary): return n.time_left > 0.0)
		if _notices.size() != before:
			_refresh_notices()
	_feedback_timer = maxf(_feedback_timer - delta, 0.0)
	_feedback_label.modulate.a = clampf(_feedback_timer / FEEDBACK_SECONDS * 2.0, 0.0, 1.0)
