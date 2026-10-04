class_name MeditationMeter
extends Control
## The meditating minigame. A breath circle swells to fill the ring once per beat; pressing
## meditate while it's full (the ring glows) builds flow. Pips show the current flow.

const RING_RADIUS := 70.0
const MIN_FRACTION := 0.3
const RING_COLOR := Color(0.55, 0.85, 1.0, 0.9)
const WINDOW_COLOR := Color(1.0, 0.9, 0.45, 1.0)
const BREATH_COLOR := Color(0.4, 0.75, 1.0, 0.35)
const PIP_EMPTY := Color(1, 1, 1, 0.25)
const PIP_FULL := Color(0.45, 0.9, 1.0)

var _tick := 0.0
var _flow := 0


func show_breath(tick: float, flow: int) -> void:
	_tick = tick
	_flow = flow
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var beat := PlayerBody.BREATH_BEAT_TICKS
	var fullness := absf(cos(PI * _tick / beat))
	var from_peak := absf(_tick - roundf(_tick / beat) * beat)
	var in_window := _tick >= beat - PlayerBody.BREATH_WINDOW and from_peak <= PlayerBody.BREATH_WINDOW

	draw_circle(center, RING_RADIUS * lerpf(MIN_FRACTION, 1.0, fullness), BREATH_COLOR)
	draw_arc(center, RING_RADIUS, 0.0, TAU, 64, WINDOW_COLOR if in_window else RING_COLOR, 6.0 if in_window else 3.0, true)

	var pip_spacing := 22.0
	var first := center + Vector2(-pip_spacing * (PlayerBody.MAX_FLOW - 1) * 0.5, RING_RADIUS + 26.0)
	for i in PlayerBody.MAX_FLOW:
		draw_circle(first + Vector2(pip_spacing * i, 0.0), 7.0, PIP_FULL if i < _flow else PIP_EMPTY)
