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
var _generation := 0


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_PRE_OPAQUE
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_white = ImageTexture.create_from_image(image)
	texture.texture_rd_rid = RenderingServer.texture_get_rd_texture(_white.get_rid())


func set_requested(value: bool) -> void:
	if value == _requested:
		return
	if not value:
		invalidate()
		return
	_mutex.lock()
	_requested = true
	_mutex.unlock()
	for reference in _materials:
		var material := reference.get_ref() as ShaderMaterial
		if material != null and _owns(material):
			material.set_shader_parameter("source_ssao_texture", texture)
			material.set_shader_parameter("source_ssao_enabled", true)


func invalidate() -> void:
	# Main-thread barrier before a viewport can release its borrowed RD slice.
	# Reject deferred publications queued by any earlier allocation/generation.
	_mutex.lock()
	_generation += 1
	_requested = false
	_published = RID()
	_mutex.unlock()
	for reference in _materials:
		var material := reference.get_ref() as ShaderMaterial
		if material != null and _owns(material):
			material.set_shader_parameter("source_ssao_enabled", false)
			material.set_shader_parameter("source_ssao_texture", _white)
	texture.texture_rd_rid = RenderingServer.texture_get_rd_texture(_white.get_rid())


func bind(material: ShaderMaterial) -> void:
	material.set_shader_parameter("source_ssao_texture", texture if _requested else _white)
	material.set_shader_parameter("source_ssao_enabled", _requested)
	for index in range(_materials.size() - 1, -1, -1):
		if _materials[index].get_ref() == null:
			_materials.remove_at(index)
		elif _materials[index].get_ref() == material:
			return
	_materials.append(weakref(material))


func unbind(material: ShaderMaterial) -> void:
	if _owns(material):
		material.set_shader_parameter("source_ssao_enabled", false)
		material.set_shader_parameter("source_ssao_texture", _white)
	for index in range(_materials.size() - 1, -1, -1):
		if _materials[index].get_ref() == null or _materials[index].get_ref() == material:
			_materials.remove_at(index)


func _owns(material: ShaderMaterial) -> bool:
	var current: Variant = material.get_shader_parameter("source_ssao_texture")
	return current == texture or current == _white


func clear_bindings() -> void:
	invalidate()
	for reference in _materials.duplicate():
		var material := reference.get_ref() as ShaderMaterial
		if material != null:
			unbind(material)
	_materials.clear()


func _publish(target: RID, generation: int) -> void:
	_mutex.lock()
	var current := generation == _generation and _requested
	_mutex.unlock()
	if current:
		texture.texture_rd_rid = target


func _render_callback(callback: int, render_data: RenderData) -> void:
	if callback != EFFECT_CALLBACK_TYPE_PRE_OPAQUE:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	_mutex.lock()
	var requested := _requested
	var generation := _generation
	_mutex.unlock()
	if not requested:
		return
	var target := RenderingServer.texture_get_rd_texture(_white.get_rid())
	if buffers.get_view_count() == 1 and buffers.has_texture("rb_ssao", "final"):
		target = buffers.get_texture_slice("rb_ssao", "final", 0, 0, 1, 1)
	_mutex.lock()
	var publish := generation == _generation and _requested and _published != target
	if publish:
		_published = target
	_mutex.unlock()
	if publish:
		_publish.call_deferred(target, generation)
