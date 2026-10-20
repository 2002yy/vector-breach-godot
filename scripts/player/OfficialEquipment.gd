extends RefCounted

const ROOT := "res://assets/local_reference/cs_official/equipment/"
const NativePanel = preload("res://scripts/objective/OfficialC4Panel.gd")
const KEYS := ["rifle-ct", "rifle-t", "pistol", "knife-ct", "knife-t", "c4", "c4-world",
	"sniper", "smg", "shotgun", "fire_grenade"]
static var _items: Dictionary = {}
static var _loaded := false


static func item_key(kind: String, team: String) -> String:
	return kind + ("-ct" if team == "CT" else "-t") if kind in ["rifle", "knife"] else kind


static func available(key: String) -> bool:
	if key not in KEYS:
		return false
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(ROOT + "manifest.json"):
			var parsed: Variant = JSON.parse_string(
				FileAccess.get_file_as_string(ROOT + "manifest.json")
			)
			if parsed is Dictionary and int(parsed.get("version", 0)) == 1:
				if parsed.get("items", {}) is Dictionary:
					_items = parsed.get("items", {})
	if not _items.get(key, {}) is Dictionary or _items.get(key, {}).is_empty():
		return false
	if key != "c4-world":
		var mount: Variant = _items[key].get("mount_transform", [])
		if not mount is Array or mount.size() != 4:
			return false
		for column in mount:
			if not column is Array or column.size() != 3:
				return false
			for value in column:
				if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
					return false
		if (
			absf(Basis(_vector(mount[0]), _vector(mount[1]), _vector(mount[2])).determinant())
			< 0.0001
		):
			return false
	return ResourceLoader.exists(ROOT + key + ".glb")


static func build(kind: String, team: String = "T") -> Node3D:
	var key := item_key(kind, team)
	if not available(key):
		return null
	var packed := load(ROOT + key + ".glb") as PackedScene
	if packed == null:
		return null
	var model := packed.instantiate() as Node3D
	preload("res://scripts/level/SourceAssetMaterials.gd").apply(model, ROOT + key + ".glb")
	model.set_meta("official_cs", key)
	var mount: Array = _items[key].get("mount_transform", [])
	if mount.size() == 4:
		model.transform = Transform3D(
			Basis(_vector(mount[0]), _vector(mount[1]), _vector(mount[2])), _vector(mount[3])
		)
	if key in ["c4", "c4-world"]:
		var panel := NativePanel.new()
		panel.name = "NativeDisplay"
		model.add_child(panel)
	return model


static func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


static func preview(kind: String, team: String) -> Texture2D:
	var key := item_key(kind, team)
	var path := ROOT.trim_suffix("equipment/") + "ui/" + key + ".png"
	return load(path) as Texture2D if available(key) and ResourceLoader.exists(path) else null


static func play(model: Node3D, clip: String, duration: float = 0.0) -> bool:
	if not is_instance_valid(model) or not model.has_meta("official_cs"):
		return false
	for player in model.find_children("*", "AnimationPlayer", true, false):
		for name in player.get_animation_list():
			if String(name) == clip or String(name).ends_with("/" + clip):
				var animation: Animation = player.get_animation(name)
				player.speed_scale = 1.0
				player.play(name, 0.04, animation.length / duration if duration > 0.0 else 1.0)
				return true
	return false


static func reset(model: Node3D) -> void:
	if not is_instance_valid(model) or not model.has_meta("official_cs"):
		return
	for player in model.find_children("*", "AnimationPlayer", true, false):
		player.speed_scale = 1.0
		if player.has_animation("RESET"):
			player.play("RESET")
			player.advance(0.0)
		player.stop()
