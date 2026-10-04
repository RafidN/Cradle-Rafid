class_name AttackData
extends ContentData
## Frame data for one attack. Ticks are server ticks (30 per second). An attack runs
## startup -> active (hitbox live) -> recovery, then the fighter is free again.

@export var display_name := ""
@export var startup := 6
@export var active := 3
@export var recovery := 10
@export var damage := 10
## Ticks the target can't act after being hit.
@export var hitstun := 12
## Horizontal speed (m/s) the target is pushed away with.
@export var knockback := 3.0
## Forward speed (m/s) of the attacker during startup and active ticks.
@export var lunge_speed := 3.0
## Hitbox in the attacker's local space; -Z is forward, the origin is at the feet.
@export var hitbox_size := Vector3(1.8, 1.2, 1.6)
@export var hitbox_offset := Vector3(0.0, 0.9, -1.0)
## Breaks through a block (the defender is staggered and takes part of the damage).
@export var guard_break := false
## Attack a buffered light attack chains into during recovery (an attack id), or empty.
@export var combo_next: StringName


func total_ticks() -> int:
	return startup + active + recovery
