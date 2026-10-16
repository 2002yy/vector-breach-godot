extends RefCounted

# Optional local Source assets. Gameplay never depends on their presence.
const ROOT := "res://assets/local_reference/cs_agents/"
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
		if FileAccess.file_exists(ROOT + "manifest.json"):
			var parsed: Variant = JSON.parse_string(
				FileAccess.get_file_as_string(ROOT + "manifest.json")
			)
			if parsed is Dictionary and int(parsed.get("version", 0)) == 1:
				_manifest = parsed.get("profiles", {})
	return _manifest.get(id, {}) if NAMES.has(id) else {}


static func available(id: String) -> bool:
	if record(id).is_empty():
		return false
	for suffix in [".glb", "-arm-L.glb", "-arm-R.glb"]:
		if not ResourceLoader.exists(ROOT + id + suffix):
			return false
	return true


static func instantiate(id: String, suffix: String = "") -> Node3D:
	if not available(id):
		return null
	var scene := load(ROOT + id + suffix + ".glb") as PackedScene
	return scene.instantiate() as Node3D if scene != null else null


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
