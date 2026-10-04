class_name WayData
extends ContentData
## A Way: a school of techniques taught by one House.

@export var display_name := ""
## The House that teaches this Way; its name becomes the practitioner's surname.
@export var house_name := ""
@export var aspect := Advancement.Aspect.FIRE
## Technique ids by slot. Slot N unlocks with rank (RankData.technique_slots).
@export var techniques: Array[StringName] = []
