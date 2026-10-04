class_name HitSpec
extends RefCounted
## What a landed hit does, independent of its source (melee attack, projectile, burst,
## trap). Combat.resolve() applies it.

var damage := 0
var hitstun := 0
var knockback := 0.0
var guard_break := false
var blockable := true
var parryable := true


static func from_attack(attack: AttackData, damage_mult: float) -> HitSpec:
	var spec := HitSpec.new()
	spec.damage = roundi(attack.damage * damage_mult)
	spec.hitstun = attack.hitstun
	spec.knockback = attack.knockback
	spec.guard_break = attack.guard_break
	return spec


## Techniques can be blocked or not, but never parried.
static func from_technique(technique: TechniqueData) -> HitSpec:
	var spec := HitSpec.new()
	spec.damage = technique.damage
	spec.hitstun = technique.hitstun
	spec.knockback = technique.knockback
	spec.blockable = technique.blockable
	spec.parryable = false
	return spec
