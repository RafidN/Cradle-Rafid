extends Node3D
## Placeholder character visual: a capsule with a nose showing which way it faces.

@export var color := Color(0.56, 0.82, 0.54)


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	$Body.material_override = material
