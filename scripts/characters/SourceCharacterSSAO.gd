extends CompositorEffect
## One effect per mono viewport. Diagnostic only; pair set_requested() with its Environment.
## PRE_OPAQUE precedes SSAO generation. Godot writes this persistent slice before
## opaque shading in the same frame. Publication is deferred between frames to
## avoid invalidating material uniform sets inside a draw. Cold start is white.

var texture := Texture2DRD.new()
var _white: ImageTexture
var _mutex := Mutex.new()
var _requested := false
var _published := RID()
var _materials: Array[WeakRef] = []


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_PRE_OPAQUE
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_white = ImageTexture.create_from_image(image)
	texture.texture_rd_rid = RenderingServer.texture_get_rd_texture(_white.get_rid())


func set_requested(value: bool) -> void:
	# Main-thread API: make disable immediate, independent of deferred RID publication.
	for reference in _materials:
		var material := reference.get_ref() as ShaderMaterial
		if material != null:
			material.set_shader_parameter("source_ssao_enabled", value)
	_mutex.lock()
	_requested = value
	_mutex.unlock()


func bind(material: ShaderMaterial) -> void:
	material.set_shader_parameter("source_ssao_texture", texture)
	material.set_shader_parameter("source_ssao_enabled", _requested)
	for reference in _materials:
		if reference.get_ref() == material:
			return
	_materials.append(weakref(material))


func unbind(material: ShaderMaterial) -> void:
	material.set_shader_parameter("source_ssao_enabled", false)
	material.set_shader_parameter("source_ssao_texture", _white)
	for index in range(_materials.size() - 1, -1, -1):
		if _materials[index].get_ref() == null or _materials[index].get_ref() == material:
			_materials.remove_at(index)


func _render_callback(callback: int, render_data: RenderData) -> void:
	if callback != EFFECT_CALLBACK_TYPE_PRE_OPAQUE:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	_mutex.lock()
	var requested := _requested
	_mutex.unlock()
	var target := RenderingServer.texture_get_rd_texture(_white.get_rid())
	if requested and buffers.get_view_count() == 1 and buffers.has_texture("rb_ssao", "final"):
		target = buffers.get_texture_slice("rb_ssao", "final", 0, 0, 1, 1)
	if texture.texture_rd_rid != target:
		if _published != target:
			_published = target
			texture.set_deferred("texture_rd_rid", target)
