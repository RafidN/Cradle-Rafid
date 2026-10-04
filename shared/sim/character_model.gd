class_name CharacterModel
extends Node3D
## Placeholder fighter visuals: a capsule with a weapon, posed procedurally for each
## combat action so fights read clearly before real animation exists.

## Weapon rotation at rest and at the start/end of each attack's swing.
const REST := Vector3(-0.7, 0.0, 0.0)
const SWINGS := {
	Attacks.LIGHT_1: [Vector3(0.0, -1.5, 0.0), Vector3(0.0, 1.3, 0.0)],
	Attacks.LIGHT_2: [Vector3(0.0, 1.5, 0.0), Vector3(0.0, -1.3, 0.0)],
	Attacks.LIGHT_3: [Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.0)],
	Attacks.HEAVY: [Vector3(1.8, 0.0, 0.0), Vector3(-0.9, 0.0, 0.0)],
}
const THRUST_DISTANCE := 0.6
const BLOCK_POSE := Vector3(0.0, 1.35, 0.0)

@export var color := Color(0.56, 0.82, 0.54)

var _material := StandardMaterial3D.new()

@onready var _rig: Node3D = $Rig
@onready var _weapon: Node3D = $Rig/WeaponPivot
@onready var _weapon_rest_position := _weapon.position
@onready var _shield: Node3D = $Rig/Shield


func _ready() -> void:
	_material.albedo_color = color
	$Rig/Body.material_override = _material


func apply_pose(action: int, action_id: int, tick: float) -> void:
	_rig.rotation = Vector3.ZERO
	_rig.scale = Vector3.ONE
	_weapon.rotation = REST
	_weapon.position = _weapon_rest_position
	_shield.visible = false
	var tint := color

	match action:
		PlayerBody.Action.ATTACK:
			_pose_attack(action_id, tick)
		PlayerBody.Action.BLOCK:
			_weapon.rotation = BLOCK_POSE
			_shield.visible = true
		PlayerBody.Action.DODGE:
			var t := clampf(tick / PlayerBody.DODGE_TICKS, 0.0, 1.0)
			_rig.scale = Vector3(1.0, lerpf(0.55, 1.0, t * t), 1.0)
			_rig.rotation.x = -0.5 * sin(t * PI)
		PlayerBody.Action.HITSTUN:
			_rig.rotation.x = 0.35
			tint = color.lerp(Color(1.0, 0.2, 0.2), 0.6)
		PlayerBody.Action.STAGGER:
			_rig.rotation.x = 0.45
			_rig.rotation.z = sin(tick * 0.8) * 0.2
			tint = color.lerp(Color(1.0, 0.85, 0.2), 0.6)
		PlayerBody.Action.DEAD:
			_rig.rotation.x = PI * 0.5
			tint = color.darkened(0.6)
	_material.albedo_color = tint


func _pose_attack(action_id: int, tick: float) -> void:
	var attack := Attacks.get_attack(action_id)
	if attack == null:
		return
	var swing: Array = SWINGS.get(action_id, [REST, REST])
	var wind := clampf(tick / attack.startup, 0.0, 1.0)
	var strike := clampf((tick - attack.startup) / attack.active, 0.0, 1.0)
	var recover := clampf((tick - attack.startup - attack.active) / attack.recovery, 0.0, 1.0)

	_weapon.rotation = REST.lerp(swing[0], wind).lerp(swing[1], strike).lerp(REST, recover)
	_rig.rotation.x = -0.2 * strike * (1.0 - recover)
	if action_id == Attacks.LIGHT_3:
		var reach := THRUST_DISTANCE * strike * (1.0 - recover)
		_weapon.position = _weapon_rest_position + Vector3(0.0, 0.0, -reach)
