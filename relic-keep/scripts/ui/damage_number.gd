extends Label
## Floating number for damage / healing.


func setup(pos: Vector2, value: String, color: Color) -> void:
	text = value
	position = pos - size / 2.0 + Vector2(randf_range(-4, 4), 0)
	modulate = color
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "position:y", position.y - 18.0, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "modulate:a", 0.0, 0.3).set_delay(0.35)
	tw.chain().tween_callback(queue_free)
