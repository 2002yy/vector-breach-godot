extends RefCounted

# Optional local Source assets. Gameplay never depends on their presence.
const ROOT := "res://assets/local_reference/cs_agents/"
const OFFICIAL_ROOT := "res://assets/local_reference/cs_official/"
const PROFILES := {
	"CT": ["ct-st6", "ct-sas-officer", "ct-fbi"],
	"T": ["t-phoenix", "t-elite", "t-blackwolf"],
}
const NAMES := {
	"ct-st6": "海豹突击队",
	"ct-sas-officer": "英国特勤队",
	"ct-fbi": "联邦特警",
	"t-phoenix": "凤凰战士",
	"t-elite": "精英叛军",
	"t-blackwolf": "黑狼",
}
static var _manifest: Dictionary = {}
static var _loaded := false


static func profile_for(team: String, index: int = 0) -> String:
	var choices: Array = PROFILES.get(team, PROFILES["T"])
	return choices[posmod(index, choices.size())]


static func sanitize(id: String, team: String) -> String:
	return id if id in PROFILES.get(team, []) else profile_for(team)


static func record(id: String) -> Dictionary:
	if not _loaded:
		_loaded = true
		for asset_root in [ROOT, OFFICIAL_ROOT]:
			if not FileAccess.file_exists(asset_root + "manifest.json"):
				continue
			var parsed: Variant = JSON.parse_string(
				FileAccess.get_file_as_string(asset_root + "manifest.json")
			)
			if not parsed is Dictionary or int(parsed.get("version", 0)) != 1:
				continue
			var profiles: Variant = parsed.get("profiles", {})
			if not profiles is Dictionary:
				continue
			for profile in NAMES:
				var entry: Variant = profiles.get(profile, {})
				if not entry is Dictionary or entry.is_empty():
					continue
				var complete := true
				for suffix in [".glb", "-arm-L.glb", "-arm-R.glb"]:
					complete = complete and ResourceLoader.exists(asset_root + profile + suffix)
				if complete:
					_manifest[profile] = entry.duplicate(true)
					_manifest[profile]["asset_root"] = asset_root
	return _manifest.get(id, {}) if NAMES.has(id) else {}


static func available(id: String) -> bool:
	if record(id).is_empty():
		return false
	for suffix in [".glb", "-arm-L.glb", "-arm-R.glb"]:
		if not ResourceLoader.exists(String(record(id).get("asset_root", ROOT)) + id + suffix):
			return false
	return true


static func instantiate(id: String, suffix: String = "") -> Node3D:
	if not available(id):
		return null
	var scene_path := String(record(id).get("asset_root", ROOT)) + id + suffix + ".glb"
	var model := preload("res://scripts/SceneInstance.gd").instantiate(scene_path)
	if model == null:
		return null
	preload("res://scripts/level/SourceAssetMaterials.gd").apply(model, scene_path)
	preload("res://scripts/characters/SourceCharacterMaterials.gd").apply(model, scene_path)
	return model


static func find_skeleton(root: Node) -> Skeleton3D:
	for child in root.find_children("*", "Skeleton3D", true, false):
		return child as Skeleton3D
	return null


static func grip_frame(id: String, side: String) -> Transform3D:
	var frame: Array = record(id).get("arms", {}).get(side, {}).get("grip_frame", [])
	if frame.size() != 4:
		return Transform3D.IDENTITY
	return Transform3D(
		Basis(_vector(frame[0]), _vector(frame[1]), _vector(frame[2])), _vector(frame[3])
	)


static func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
