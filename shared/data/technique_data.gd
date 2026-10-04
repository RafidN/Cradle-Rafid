class_name TechniqueData
extends Resource
## A Path technique. Casting spends madra at the start, then runs startup -> release ->
## recovery like an attack. What happens on release depends on the kind:
##   ENFORCER  toggles a self-buff that drains madra while active
##   STRIKER   fires a projectile
##   RULER     hits everything within radius around the caster (can't be blocked)
##   FORGER    places a construct (a trap) that persists in the world

enum Kind { ENFORCER, STRIKER, RULER, FORGER }

@export var display_name := ""
@export var kind := Kind.STRIKER
## Madra spent when the cast starts (whole madra, not hundredths).
@export var cost := 10
@export var startup := 8
@export var recovery := 10
@export var damage := 0
@export var hitstun := 0
@export var knockback := 0.0
@export var blockable := true
## Ruler: burst radius. Forger: trigger radius.
@export var radius := 0.0
## Striker: projectile speed (m/s) and range (m).
@export var speed := 0.0
@export var max_range := 0.0
## Forger: ticks before the construct is armed, and its lifetime.
@export var arm_ticks := 0
@export var lifetime_ticks := 0


func total_ticks() -> int:
	return startup + recovery
