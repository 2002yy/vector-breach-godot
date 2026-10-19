extends Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func _draw() -> void:
	var center := size * 0.5
	var radius := size.y * 0.43
	var width := size.length()
	draw_arc(center, radius + width * 0.5, 0, TAU, 128, Color.BLACK, width, true)
	draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), Color.BLACK, 1)
	draw_line(center - Vector2(0, radius), center + Vector2(0, radius), Color.BLACK, 1)
