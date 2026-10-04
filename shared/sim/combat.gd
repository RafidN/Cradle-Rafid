class_name Combat
extends RefCounted
## Hit geometry and hit resolution. Resolution runs only on the server; clients see the
## outcome through snapshots and HIT events.

enum Result { HIT, BLOCKED, PARRIED, GUARD_BROKEN }

const BLOCK_DAMAGE_MULT := 0.2
const BLOCK_PUSHBACK_MULT := 0.5
const GUARD_BREAK_DAMAGE_MULT := 0.5
const GUARD_BREAK_TICKS := 24
const PARRY_STAGGER_TICKS := 30


## True if the attack's hitbox, placed on the attacker, touches a hurtbox at target_position.
static func hitbox_overlaps(attacker_position: Vector3, attacker_facing: float,
		attack: AttackData, target_position: Vector3) -> bool:
	var basis := Basis(Vector3.UP, attacker_facing)
	var hitbox_center := attacker_position + basis * attack.hitbox_offset
	var hurtbox_center := target_position + Vector3.UP * (PlayerBody.HURT_HEIGHT * 0.5)
	var local := basis.inverse() * (hurtbox_center - hitbox_center)
	var reach := attack.hitbox_size * 0.5 + Vector3(
		PlayerBody.HURT_RADIUS, PlayerBody.HURT_HEIGHT * 0.5, PlayerBody.HURT_RADIUS)
	return absf(local.x) <= reach.x and absf(local.y) <= reach.y and absf(local.z) <= reach.z


## Applies a landed attack to the target (and to the attacker, on a parry). Blocking only
## works against attacks from the front half. Returns the Result and the damage dealt.
static func resolve(attacker: PlayerBody, target: PlayerBody, attack: AttackData) -> Array:
	var away := target.global_position - attacker.global_position
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.0001 else PlayerBody._forward(attacker.facing)
	var target_forward := PlayerBody._forward(target.facing)
	var frontal := target_forward.dot(-away) > 0.0

	if target.action == PlayerBody.Action.BLOCK and frontal:
		if target.is_parrying():
			attacker.apply_stagger(PARRY_STAGGER_TICKS, -away * attack.knockback * 0.5)
			return [Result.PARRIED, 0]
		if attack.guard_break:
			var damage := ceili(attack.damage * GUARD_BREAK_DAMAGE_MULT)
			target.apply_damage(damage)
			target.apply_stagger(GUARD_BREAK_TICKS, away * attack.knockback)
			return [Result.GUARD_BROKEN, damage]
		var chip := ceili(attack.damage * BLOCK_DAMAGE_MULT)
		target.apply_damage(chip)
		if not target.is_dead():
			var push := away * attack.knockback * BLOCK_PUSHBACK_MULT
			target.velocity.x = push.x
			target.velocity.z = push.z
		return [Result.BLOCKED, chip]

	target.apply_damage(attack.damage)
	target.apply_hitstun(attack.hitstun, away * attack.knockback)
	return [Result.HIT, attack.damage]
