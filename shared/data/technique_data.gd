class_name TechniqueData
extends ContentData
## A Way technique. Casting spends spirit at the start, then runs startup -> release ->
## recovery like an attack. What happens on release depends on the kind:
##   ENFORCER    toggles a self-buff that drains spirit while active
##   LANCER      fires a projectile
##   CONTROLLER  hits everything within radius around the caster (can't be blocked)
##   BUILDER     places a construct (a trap) that persists in the world

enum Kind { ENFORCER, LANCER, CONTROLLER, BUILDER }

@export var display_name := ""
@export var kind := Kind.LANCER
## Spirit spent when the cast starts (whole spirit, not hundredths).
@export var cost := 10
@export var startup := 8
@export var recovery := 10
@export var damage := 0
@export var hitstun := 0
@export var knockback := 0.0
@export var blockable := true
## Controller: burst radius. Builder: trigger radius.
@export var radius := 0.0
## Lancer: projectile speed (m/s) and range (m).
@export var speed := 0.0
@export var max_range := 0.0
## Builder: ticks before the construct is armed, and its lifetime.
@export var arm_ticks := 0
@export var lifetime_ticks := 0


func total_ticks() -> int:
	return startup + recovery
