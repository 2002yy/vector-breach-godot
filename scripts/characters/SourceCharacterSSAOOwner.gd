extends Node
## Diagnostic viewport owner. Does not enable character environment shading in gameplay.

signal reconfigured(applied: bool)

const Delivery = preload("res://scripts/characters/SourceCharacterSSAO.gd")
var effect: CompositorEffect
var _world: WorldEnvironment
var _viewport: Viewport
var _original: Compositor
var _owned: Compositor
var _configuration: Array = []
var _window: Window
var _transition := false
var _pending_size := Vector2i.ZERO
var _pending_scale := -1.0
var _pending_msaa := -1
var _session := 0


func attach(world: WorldEnvironment, follow_window := false) -> bool:
	detach()
	if (
		not is_inside_tree()
		or not is_instance_valid(world)
		or not world.is_inside_tree()
		or world.get_viewport() != get_viewport()
		or not world.get_viewport() is SubViewport
		or RenderingServer.get_rendering_device() == null
	):
		return false
	_world = world
	_viewport = world.get_viewport()
	_original = world.compositor
	_owned = Compositor.new()
	var effects: Array[CompositorEffect] = []
	if _original != null:
		effects.assign(_original.compositor_effects)
	effect = Delivery.new()
	effects.append(effect)
	_owned.compositor_effects = effects
	_world.compositor = _owned
	_world.tree_exiting.connect(detach)
	if follow_window:
		_window = get_window()
		_window.size_changed.connect(_window_resized)
	process_priority = 100000
	set_process(true)
	_sync()
	return true


func bind(material: ShaderMaterial) -> bool:
	if effect == null:
		return false
	effect.bind(material)
	return true


func detach() -> void:
	set_process(false)
	var canceled := _transition
	_session += 1
	if effect != null:
		effect.clear_bindings()
	if is_instance_valid(_world):
		if _world.compositor == _owned:
			_world.compositor = _original
		if _world.tree_exiting.is_connected(detach):
			_world.tree_exiting.disconnect(detach)
	if is_instance_valid(_window) and _window.size_changed.is_connected(_window_resized):
		_window.size_changed.disconnect(_window_resized)
	effect = null
	_world = null
	_viewport = null
	_owned = null
	_original = null
	_configuration = []
	_window = null
	_transition = false
	_pending_size = Vector2i.ZERO
	_pending_scale = -1.0
	_pending_msaa = -1
	if canceled:
		reconfigured.emit(false)


func request_size(size: Vector2i) -> void:
	if effect == null or size.x < 2 or size.y < 2:
		return
	_pending_size = size
	_begin_transition()


func request_render_settings(scale: float, msaa: int) -> void:
	if effect == null or not is_finite(scale) or scale < 0.25 or scale > 2.0:
		return
	if msaa < Viewport.MSAA_DISABLED or msaa > Viewport.MSAA_8X:
		return
	_pending_scale = scale
	_pending_msaa = msaa
	_begin_transition()


func _window_resized() -> void:
	request_size(_window.size)


func _begin_transition() -> void:
	if _transition:
		return
	_transition = true
	var session := _session
	effect.invalidate()
	# The viewport's native setter releases buffers before size_changed. Own the
	# mutation instead: retire the borrowed view before any native reallocation.
	await RenderingServer.frame_post_draw
	if session != _session or effect == null:
		return
	if not is_instance_valid(_world) or _world.compositor != _owned:
		detach()
		return
	if _pending_size != Vector2i.ZERO:
		_viewport.size = _pending_size
	if _pending_scale > 0.0:
		_viewport.scaling_3d_scale = _pending_scale
		_viewport.msaa_3d = _pending_msaa
	_pending_size = Vector2i.ZERO
	_pending_scale = -1.0
	_pending_msaa = -1
	_transition = false
	_configuration = []
	_sync()
	reconfigured.emit(true)


func _process(_delta: float) -> void:
	_sync()


func _sync() -> void:
	if not is_instance_valid(_world) or _world.compositor != _owned:
		detach()
		return
	if _transition:
		return
	var configuration := [
		_world.environment,
		_viewport.get_visible_rect().size,
		_viewport.scaling_3d_scale,
		_viewport.scaling_3d_mode,
		_viewport.msaa_3d,
	]
	if configuration != _configuration:
		effect.invalidate()
		_configuration = configuration
	effect.set_requested(_world.environment != null and _world.environment.ssao_enabled)


func _exit_tree() -> void:
	detach()
