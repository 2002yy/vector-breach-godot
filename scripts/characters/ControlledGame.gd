extends Control
## Explicit development entry. Texture presentation never resizes native buffers directly.

const MainScene = preload("res://scenes/Main.tscn")
const SSAOOwner = preload("res://scripts/characters/SourceCharacterSSAOOwner.gd")
const RuntimeInputs = preload("res://scripts/characters/SourceCharacterRuntimeInputs.gd")
const Hands = preload("res://scripts/player/FirstPersonHands.gd")

@export var bundle_paths: PackedStringArray = []
var game: Node3D
var viewport: SubViewport
var ssao: Node
var runtime: Node
var candidate_state := "未提供候选输入"
var _catalog := {}
var _bound := {}
var _display: TextureRect
var _session := 0
var _retired: Array[Material] = []
var _retiring := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var args := OS.get_cmdline_user_args()
	for index in range(args.size() - 1):
		if args[index] == "--character-bundle":
			bundle_paths.append(args[index + 1])
	_catalog = bundle_catalog(bundle_paths)
	viewport = SubViewport.new()
	viewport.name = "GameViewport"
	viewport.size = Vector2i(size).max(Vector2i(2, 2))
	viewport.own_world_3d = true
	viewport.audio_listener_enable_3d = true
	viewport.handle_input_locally = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	_display = TextureRect.new()
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_display.texture = viewport.get_texture()
	add_child(_display)
	ssao = SSAOOwner.new()
	viewport.add_child(ssao)
	runtime = RuntimeInputs.new()
	viewport.add_child(runtime)
	get_tree().node_added.connect(_node_added)
	game = MainScene.instantiate()
	game.get_node("Level").level_load_started.connect(_map_started)
	game.level_prepared.connect(_map_prepared)
	game.level_start_failed.connect(_map_failed)
	game.get_node("CombatSandbox").combatants_spawned.connect(_roster_changed)
	game.get_node("CombatSandbox").combatants_clearing.connect(_characters_clearing)
	viewport.add_child(game)
	ssao.attach(game.get_node("WorldEnvironment"))
	resized.connect(_resize)
	get_window().focus_exited.connect(_focus_lost)
	get_window().focus_entered.connect(_focus_returned)
	# Lobby selection is metadata only; input configuration starts at level_prepared.
	_resize()


static func bundle_catalog(paths: PackedStringArray) -> Dictionary:
	var catalog := {}
	for path in paths:
		if not FileAccess.file_exists(path):
			return {}
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > 65536:
			return {}
		var parser := JSON.new()
		if parser.parse(file.get_as_text()) != OK:
			return {}
		var data: Variant = parser.data
		if (
			not data is Dictionary
			or data.get("contract") != "source-character-runtime-bundle-v1"
			or not data.get("level") is String
			or data.level.is_empty()
			or catalog.has(data.level)
		):
			return {}
		catalog[data.level] = path
	return catalog


func _input(event: InputEvent) -> void:
	if not is_instance_valid(viewport) or not is_visible_in_tree():
		return
	var forwarded := event.duplicate() as InputEvent
	if forwarded is InputEventMouse:
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		forwarded.position = local * Vector2(viewport.size) / size
		forwarded.global_position = forwarded.position
		if forwarded is InputEventMouseMotion and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			forwarded.relative *= Vector2(viewport.size) / size
	viewport.push_input(forwarded, true)
	get_viewport().set_input_as_handled()


func _resize() -> void:
	if is_instance_valid(ssao):
		ssao.request_size(Vector2i(size).max(Vector2i(2, 2)))


func _focus_lost() -> void:
	if is_instance_valid(game) and game.game_started and not game.menu_open:
		game.call("_open_menu", false)


func _focus_returned() -> void:
	# Main owns recapture on resume; regaining focus alone must not resume a match.
	if is_instance_valid(viewport):
		viewport.notify_mouse_entered()


func _map_started(_level_id: String) -> void:
	_session += 1
	if is_instance_valid(game.spectator):
		game.spectator.stop()
	_characters_clearing()
	runtime.clear()
	if ssao.effect != null:
		ssao.effect.clear_bindings()
	candidate_state = "等待地图就绪"


func _map_prepared(data: Dictionary) -> void:
	var session := _session
	var path: String = _catalog.get(data.get("id", ""), "")
	if path.is_empty():
		candidate_state = "此地图无候选输入，保留原材质"
		return
	var visual := game.get_node_or_null("Level/VisualRoot/LevelVisual")
	candidate_state = "校验并加载候选输入"
	var applied: bool = await runtime.configure(path, data, visual, true)
	if session != _session or not is_inside_tree():
		return
	candidate_state = "候选已启用" if applied else "候选输入失效，保留原材质"
	if applied:
		_refresh_characters()


func _map_failed(level_id: String) -> void:
	_map_started(level_id)
	candidate_state = "地图加载失败，保留原材质"


func _roster_changed(_friendly: int, _enemy: int) -> void:
	_refresh_characters.call_deferred()


func _refresh_characters() -> void:
	if not is_inside_tree() or not runtime.configured or ssao.effect == null:
		return
	var alive := {}
	var hand_ids := {}
	for actor in game.get_node("CombatSandbox").get_children():
		if not actor.has_method("get_native_character") or actor.is_queued_for_deletion():
			continue
		if not actor.appearance_changed.is_connected(_refresh_characters):
			actor.appearance_changed.connect(_refresh_characters)
			actor.appearance_changing.connect(_appearance_changing)
		var visual: Node3D = actor.get_native_character()
		if not is_instance_valid(visual):
			continue
		var id := visual.get_instance_id()
		alive[id] = visual
	for hands in get_tree().get_nodes_in_group("first_person_hands"):
		if hands.get_viewport() != viewport or hands.is_queued_for_deletion():
			continue
		if not hands.native_changed.is_connected(_refresh_characters):
			hands.native_changed.connect(_refresh_characters)
			hands.native_changing.connect(_appearance_changing)
		var visual: Node3D = hands.get_native_hands()
		if is_instance_valid(visual):
			alive[visual.get_instance_id()] = visual
			hand_ids[visual.get_instance_id()] = true
	# Retire old materials before RuntimeInputs.track can prune dead meshes.
	for id in _bound.keys():
		if not alive.has(id):
			_retire(id)
	for id in alive:
		if _bound.has(id):
			continue
		var composite: RefCounted = runtime.attach_character(alive[id], true, hand_ids.has(id))
		if composite != null:
			for material in composite.materials:
				ssao.bind(material)
			_bound[id] = composite


func _node_added(node: Node) -> void:
	# Spectator view models are created after map preparation. Wait for ready so
	# the hands group and initial appearance are available; filter viewport there.
	if node.get_script() == Hands:
		_refresh_characters.call_deferred()


func _appearance_changing(visual: Node3D) -> void:
	_retire(visual.get_instance_id())


func _characters_clearing() -> void:
	for id in _bound.keys():
		_retire(id)


func _retire(id: int) -> void:
	if not _bound.has(id):
		return
	var composite: RefCounted = _bound[id]
	for binding in composite._bindings:
		_retired.append(binding.original)
		if binding.previous != null:
			_retired.append(binding.previous)
	for material in composite.materials:
		_retired.append(material)
		if ssao.effect != null:
			ssao.effect.unbind(material)
	composite.detach()
	_bound.erase(id)
	if not _retiring:
		_retiring = true
		_release_retired.call_deferred()


func _release_retired() -> void:
	# Keep queued renderer dependencies alive through the final old draw.
	await RenderingServer.frame_post_draw
	_retired.clear()
	_retiring = false


func _exit_tree() -> void:
	_session += 1
	_characters_clearing()
	if is_instance_valid(runtime):
		runtime.clear()
	if is_instance_valid(ssao):
		ssao.detach()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
