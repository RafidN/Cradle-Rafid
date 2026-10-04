class_name CharacterModel
extends Node3D
## Placeholder fighter visuals: a capsule with a weapon, posed procedurally. Every frame
## it works out the pose for the current action and eases toward it, so actions blend
## into each other instead of snapping. Swings use easing curves, the fighter leans and
## bobs while running, and the weapon flashes while its hitbox is live.

## Weapon rotation at rest and at the start/end of each attack's swing.
const REST := Vector3(-0.7, 0.0, 0.0)
const SWINGS := {
	Attacks.LIGHT_1: [Vector3(0.1, -1.6, 0.0), Vector3(-0.1, 1.4, 0.0)],
	Attacks.LIGHT_2: [Vector3(0.1, 1.6, 0.0), Vector3(-0.1, -1.4, 0.0)],
	Attacks.LIGHT_3: [Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0)],
	Attacks.HEAVY: [Vector3(2.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0)],
}
const THRUST_DISTANCE := 0.6
const BLOCK_POSE := Vector3(0.0, 1.35, 0.0)
## How quickly the rig eases toward each frame's target pose (per second).
const BLEND_RATE := 28.0
const ENFORCER_GLOW := Color(1.0, 0.45, 0.1)
const EXHAUSTED_TINT := Color(0.45, 0.45, 0.5)
const HIT_FLASH := Color(1.0, 0.25, 0.2)
const WEAPON_COLOR := Color(0.85, 0.85, 0.9)
const WEAPON_GLOW := Color(1.0, 0.9, 0.6)

@export var color := Color(0.56, 0.82, 0.54)

var _body_material := StandardMaterial3D.new()
var _weapon_material := StandardMaterial3D.new()
var _stride := 0.0
var _time := 0.0

@onready var _rig: Node3D = $Rig
@onready var _weapon: Node3D = $Rig/WeaponPivot
@onready var _weapon_rest_position := _weapon.position
@onready var _shield: Node3D = $Rig/Shield


class Pose:
	var rig_rotation := Vector3.ZERO
	var rig_scale := Vector3.ONE
	var rig_offset := Vector3.ZERO
	var weapon_rotation := REST
	var weapon_offset := Vector3.ZERO
	var weapon_glow := 0.0
	var tint := Color.WHITE
	var shield := false


func _ready() -> void:
	_body_material.albedo_color = color
	_body_material.emission = ENFORCER_GLOW
	$Rig/Body.material_override = _body_material
	_weapon_material.albedo_color = WEAPON_COLOR
	_weapon_material.emission_enabled = true
	_weapon_material.emission = WEAPON_GLOW
	_weapon_material.emission_energy_multiplier = 0.0
	$Rig/WeaponPivot/Weapon.material_override = _weapon_material


func set_color(new_color: Color) -> void:
	color = new_color
	_body_material.albedo_color = color


## tick may be fractional (between physics ticks). speed is horizontal m/s.
func update_pose(action: int, action_id: int, tick: float, flags: int, speed: float, delta: float) -> void:
	_time += delta
	_stride += delta * speed * 2.4
	var pose := _target_pose(action, action_id, tick, flags, speed)
	var w := 1.0 - exp(-BLEND_RATE * delta)
	_rig.rotation = _rig.rotation.lerp(pose.rig_rotation, w)
	_rig.scale = _rig.scale.lerp(pose.rig_scale, w)
	_rig.position = _rig.position.lerp(pose.rig_offset, w)
	_weapon.rotation = _weapon.rotation.lerp(pose.weapon_rotation, w)
	_weapon.position = _weapon.position.lerp(_weapon_rest_position + pose.weapon_offset, w)
	_weapon_material.emission_energy_multiplier = lerpf(_weapon_material.emission_energy_multiplier, pose.weapon_glow * 4.0, w)
	_shield.visible = pose.shield
	_body_material.albedo_color = _body_material.albedo_color.lerp(pose.tint, w)
	var enforcer := flags & PlayerBody.FLAG_ENFORCER != 0
	_body_material.emission_enabled = enforcer
	_body_material.emission_energy_multiplier = 0.8 + 0.3 * sin(_time * 10.0)


func _target_pose(action: int, action_id: int, tick: float, flags: int, speed: float) -> Pose:
	var pose := Pose.new()
	pose.tint = color
	match action:
		PlayerBody.Action.NONE:
			_pose_locomotion(pose, speed / PlayerBody.RUN_SPEED)
		PlayerBody.Action.ATTACK:
			_pose_attack(pose, action_id, tick)
		PlayerBody.Action.BLOCK:
			_pose_locomotion(pose, speed / PlayerBody.RUN_SPEED * 0.5)
			pose.weapon_rotation = BLOCK_POSE
			pose.shield = true
		PlayerBody.Action.DODGE:
			var t := clampf(tick / PlayerBody.DODGE_TICKS, 0.0, 1.0)
			pose.rig_scale = Vector3(1.05, lerpf(0.55, 1.0, ease(t, 2.0)), 1.05)
			pose.rig_rotation.x = -0.55 * sin(t * PI)
		PlayerBody.Action.HITSTUN:
			pose.rig_rotation.x = 0.4
			pose.rig_rotation.z = sin(tick * 1.7) * 0.08
			pose.tint = color.lerp(HIT_FLASH, clampf(1.0 - tick / 8.0, 0.25, 1.0))
		PlayerBody.Action.STAGGER:
			pose.rig_rotation.x = 0.5
			pose.rig_rotation.z = sin(tick * 0.8) * 0.22
			pose.weapon_rotation = Vector3(-1.3, 0.4, 0.0)
			pose.tint = color.lerp(Color(1.0, 0.85, 0.2), 0.6)
		PlayerBody.Action.DEAD:
			pose.rig_rotation.x = PI * 0.5
			pose.weapon_rotation = Vector3(-1.5, 0.0, 0.0)
			pose.tint = color.darkened(0.6)
		PlayerBody.Action.MEDITATE:
			# Seated, breathing in time with the meditating beat.
			var breath := absf(cos(PI * tick / PlayerBody.BREATH_BEAT_TICKS))
			pose.rig_scale = Vector3(1.0 + 0.06 * breath, 0.62 + 0.04 * breath, 1.0 + 0.06 * breath)
			pose.weapon_rotation = Vector3(-1.4, 0.0, 0.0)
		PlayerBody.Action.TECHNIQUE:
			_pose_technique(pose, action_id, tick)

	if flags & PlayerBody.FLAG_EXHAUSTED:
		pose.tint = pose.tint.lerp(EXHAUSTED_TINT, 0.7)
		pose.rig_rotation.x += 0.25
	return pose


## Idle breathing at rest; forward lean and a running bob that grow with speed.
func _pose_locomotion(pose: Pose, run: float) -> void:
	run = clampf(run, 0.0, 1.2)
	pose.rig_rotation.x = -0.14 * run
	pose.rig_rotation.z = sin(_stride) * 0.05 * run
	pose.rig_offset.y = absf(sin(_stride)) * 0.07 * run
	pose.rig_scale = Vector3.ONE * (1.0 + 0.012 * sin(_time * 2.2) * (1.0 - run))
	pose.weapon_rotation = REST + Vector3(0.0, 0.0, sin(_stride) * 0.15 * run)


## Wind up during startup (easing in), whip through the swing during active ticks
## (easing out), then settle back during recovery.
func _pose_attack(pose: Pose, action_id: int, tick: float) -> void:
	var attack := Attacks.get_attack(action_id)
	if attack == null:
		return
	var swing: Array = SWINGS.get(action_id, [REST, REST])
	var wind := ease(clampf(tick / attack.startup, 0.0, 1.0), 2.2)
	var strike := ease(clampf((tick - attack.startup) / attack.active, 0.0, 1.0), 0.35)
	var recover := smoothstep(0.0, 1.0, clampf((tick - attack.startup - attack.active) / attack.recovery, 0.0, 1.0))
	var live := tick >= attack.startup and tick < attack.startup + attack.active

	pose.weapon_rotation = REST.lerp(swing[0], wind).lerp(swing[1], strike).lerp(REST, recover)
	var commit := (0.1 * wind + 0.15 * strike) * (1.0 - recover)
	pose.rig_rotation = Vector3(-commit, swing[0].y * 0.12 * wind * (1.0 - strike), 0.0)
	pose.weapon_glow = 1.0 if live else 0.0
	if action_id == Attacks.LIGHT_3:
		pose.weapon_offset = Vector3(0.0, 0.0, -THRUST_DISTANCE * strike * (1.0 - recover))
	if action_id == Attacks.HEAVY:
		pose.rig_scale = Vector3.ONE * (1.0 + 0.06 * wind * (1.0 - strike))


## Wind up during startup, snap into a kind-specific release pose, then settle.
func _pose_technique(pose: Pose, technique_id: int, tick: float) -> void:
	var technique := Techniques.get_technique(technique_id)
	if technique == null:
		return
	var wind := ease(clampf(tick / technique.startup, 0.0, 1.0), 2.0)
	var settle := smoothstep(0.0, 1.0, clampf((tick - technique.startup) / technique.recovery, 0.0, 1.0))
	var released := 1.0 if tick >= technique.startup else 0.0
	match technique.kind:
		TechniqueData.Kind.ENFORCER:
			pose.weapon_rotation = REST.lerp(Vector3(1.6, 0.0, 0.0), wind).lerp(REST, settle)
			pose.rig_scale = Vector3.ONE * (1.0 + 0.12 * wind * (1.0 - settle))
		TechniqueData.Kind.LANCER:
			pose.weapon_rotation = REST.lerp(Vector3(0.3, 0.0, 0.0), wind).lerp(REST, settle)
			pose.weapon_offset = Vector3(0.0, 0.0, -THRUST_DISTANCE * released * (1.0 - settle))
			pose.rig_rotation.x = 0.12 * released * (1.0 - settle)  # Recoil.
		TechniqueData.Kind.CONTROLLER:
			pose.rig_scale = Vector3(1.0, 1.0 - 0.3 * wind * (1.0 - released), 1.0) * (1.0 + 0.1 * released * (1.0 - settle))
			pose.weapon_rotation = REST.lerp(Vector3(1.8, 0.0, 0.0), wind).lerp(Vector3(-1.3, 0.0, 0.0), released).lerp(REST, settle)
		TechniqueData.Kind.BUILDER:
			pose.rig_rotation.x = -0.6 * wind * (1.0 - settle)
			pose.weapon_rotation = REST.lerp(Vector3(-1.4, 0.0, 0.0), wind).lerp(REST, settle)
	pose.weapon_glow = released * (1.0 - settle)
