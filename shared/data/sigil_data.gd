class_name SigilData
extends ContentData
## Crafted from essence. Some are spent to advance; others are kept for a lasting bonus.

@export var display_name := ""
@export_multiline var description := ""
## Essence per aspect (indexed by Advancement.Aspect).
@export var cost := PackedInt32Array([0, 0, 0])
## Most a practitioner can hold.
@export var max_count := 1
## Whole spirit capacity added per sigil held.
@export var spirit_capacity_bonus := 0
## Can't be crafted at or above this rank (net id), e.g. a sigil for reaching it; -1 = no limit.
@export var obsolete_at_rank := -1
