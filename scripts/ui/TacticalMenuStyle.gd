extends RefCounted

const INK := Color("101518")
const PANEL := Color("192024")
const BRASS := Color("b9a36c")
const TEXT := Color("e9e6dc")
const MUTED := Color("969e9f")
const CT := Color("779dad")


static func box(color: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.border_color = border
	result.set_border_width_all(1)
	result.set_corner_radius_all(2)
	result.content_margin_left = 14
	result.content_margin_right = 14
	result.content_margin_top = 10
	result.content_margin_bottom = 10
	return result


static func button(control: Button, primary: bool = false) -> void:
	control.add_theme_stylebox_override("normal", box(BRASS if primary else PANEL))
	control.add_theme_stylebox_override(
		"hover", box(Color("d6c18a") if primary else Color("283237"))
	)
	control.add_theme_stylebox_override(
		"pressed", box(Color("948052") if primary else Color("334148"))
	)
	control.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, TEXT))
	control.add_theme_stylebox_override("disabled", box(Color("171c1f")))
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		control.add_theme_color_override(state, INK if primary else TEXT)
	control.add_theme_font_size_override("font_size", 18)
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


static func label(copy: String, size: int = 18, color: Color = TEXT) -> Label:
	var result := Label.new()
	result.text = copy
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result
