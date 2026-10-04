class_name NetConditioner
extends RefCounted
## Simulates a bad network for testing: added latency, jitter and packet loss. Loss
## only applies to unreliable packets; reliable ones are delayed but stay in order.

enum { OUTGOING, INCOMING }

## Extra round-trip time in ms. Half is added in each direction.
var latency_ms := 0.0
## Random extra delay per packet, from 0 to this many ms.
var jitter_ms := 0.0
## Chance (0 to 1) that an unreliable packet is dropped, in each direction.
var loss := 0.0

var _pending: Array = []  # [deliver_at_msec, Callable]
var _last_reliable_at := [0.0, 0.0]


func is_active() -> bool:
	return latency_ms > 0.0 or jitter_ms > 0.0 or loss > 0.0


func describe() -> String:
	return "+%d ms RTT, %d ms jitter, %d%% loss" % [latency_ms, jitter_ms, roundi(loss * 100.0)]


func schedule(direction: int, reliable: bool, deliver: Callable) -> void:
	if not reliable and randf() < loss:
		return
	var deliver_at := Time.get_ticks_msec() + latency_ms * 0.5 + randf() * jitter_ms
	if reliable:
		deliver_at = maxf(deliver_at, _last_reliable_at[direction])
		_last_reliable_at[direction] = deliver_at
	_pending.append([deliver_at, deliver])


func flush() -> void:
	if _pending.is_empty():
		return
	var now := Time.get_ticks_msec()
	var due: Array = []
	var waiting: Array = []
	for entry in _pending:
		if entry[0] <= now:
			due.append(entry)
		else:
			waiting.append(entry)
	if due.is_empty():
		return
	_pending = waiting
	due.sort_custom(func(a, b): return a[0] < b[0])
	for entry in due:
		entry[1].call()
