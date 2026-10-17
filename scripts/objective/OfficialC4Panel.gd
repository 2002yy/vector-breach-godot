extends Node

var display: Label
var viewport: SubViewport
var _previous := ""


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(256, 128)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	var background := ColorRect.new()
	background.color = Color("071b1c")
	background.size = Vector2(256, 128)
	viewport.add_child(background)
	display = Label.new()
	display.size = Vector2(256, 128)
	display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	display.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	display.add_theme_font_size_override("font_size", 38)
	display.add_theme_color_override("font_color", Color("a4f4d8"))
	viewport.add_child(display)
	for mesh in get_parent().find_children("*", "MeshInstance3D", true, false):
		for index in range(mesh.mesh.get_surface_count()):
			var material: Material = mesh.get_active_material(index)
			if material == null or "panorama_control_panel" not in material.resource_name:
				continue
			var screen := StandardMaterial3D.new()
			screen.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			screen.albedo_texture = viewport.get_texture()
			screen.uv1_scale = Vector3(-1, -1, 1)
			screen.uv1_offset = Vector3(1, 1, 0)
			screen.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh.set_surface_override_material(index, screen)
	_update_display()


func _process(_delta: float) -> void:
	_update_display()


func _update_display() -> void:
	var armed := RoundManager.state == RoundManager.RoundState.BOMB_PLANTED
	var seconds := maxi(0, ceili(RoundManager.time_remaining))
	var next := "C4\n%02d:%02d" % [seconds / 60, seconds % 60] if armed else "C4\n•••••••"
	if next == _previous:
		return
	_previous = next
	display.text = next
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
