class_name RankData
extends ContentData
## A power tier. net_id is its place in the ladder (0 = the starting tier).

@export var display_name := ""
@export var max_health := 100
## Whole spirit (not hundredths).
@export var max_spirit := 100
## Technique slots open at this rank (slots 0..technique_slots-1).
@export var technique_slots := 2
@export var damage_mult := 1.0
@export var knockback_taken_mult := 1.0
@export_group("Advancing into this rank")
## Total essence of any aspect spent to advance into this rank.
@export var essence_cost := 0
## Sigil (id) consumed to advance into this rank, or empty.
@export var required_sigil: StringName
