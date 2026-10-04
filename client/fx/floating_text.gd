class_name FloatingText
extends Label3D
## A short-lived label that rises and fades, for damage numbers and combat callouts.

const LIFETIME := 0.9
const RISE := 1.2


static func spawn(parent: Node, at: Vector3, message: String, tint: Color) -> void:
	var label := FloatingText.new()
	label.text = message
	label.modulate = tint
	parent.add_child(label)
	label.global_position = at


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true
	fixed_size = true
	pixel_size = 0.0012
	font_size = 32
	outline_size = 8
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "position:y", position.y + RISE, LIFETIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "modulate:a", 0.0, LIFETIME).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)
