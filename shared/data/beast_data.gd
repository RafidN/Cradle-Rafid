class_name BeastData
extends ContentData
## A species of spirit beast: stats, how its brain fights, and the echo it leaves.

@export var display_name := ""
@export var aspect := Advancement.Aspect.FIRE
@export var rank_label := "Bronze"
@export var max_health := 60
@export var damage_mult := 1.0
@export var speed_mult := 1.0
@export var knockback_taken_mult := 1.0
## Visual only; hit tests use the standard hurtbox.
@export var scale := 1.0
@export var color := Color(0.8, 0.4, 0.3)
## Essence of its aspect left in its echo.
@export var essence := 10

@export_group("Brain")
@export var aggro_range := 9.0
## Gives up and returns home past this distance from home.
@export var leash_range := 22.0
@export var attack_range := 2.2
## Ticks between attack bursts, as (min, max). These pauses are the player's openings.
@export var attack_cooldown := Vector2i(30, 50)
## Relative odds of each choice when in melee range.
@export var combo_weight := 1.0
@export var heavy_weight := 1.0
@export var dodge_weight := 0.0
@export var close_technique_weight := 0.0
## Technique (id) cast in melee range, e.g. a stomp, or empty.
@export var close_technique: StringName
## Technique (id) cast between ranged_min and ranged_max, or empty.
@export var ranged_technique: StringName
@export var ranged_min := 5.0
@export var ranged_max := 14.0
@export var respawn_ticks := 600
