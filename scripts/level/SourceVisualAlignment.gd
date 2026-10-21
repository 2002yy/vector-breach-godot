extends RefCounted

const Adapter = preload("res://scripts/level/SourceProbeDiagnostic.gd")


static func invalid() -> Transform3D:
	return Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)


# Legacy VRF exports have Source-world vertices beneath per-mesh transforms,
# rather than the explicit alignment parent used by newer map imports.
# gdlint: disable=max-returns
static func resolve(root: Node, level: Dictionary, receipt_path: String = "") -> Transform3D:
	if receipt_path.is_empty():
		return Adapter.alignment_from_visual(root)
	if not root is Node3D or not FileAccess.file_exists(receipt_path):
		return invalid()
	if not root.find_children("OfficialSourceAlignment", "Node3D", true, false).is_empty():
		return invalid()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(receipt_path))
	if (
		not data is Dictionary
		or data.get("schema") != 1
		or data.get("contract") != "source-world-visual-alignment-v1"
		or data.get("level") != level.get("id")
		or not data.get("source_vpk_sha256") is String
		or data.source_vpk_sha256.length() != 64
		or not data.source_vpk_sha256.is_valid_hex_number(false)
		or data.get("source_vpk_sha256") != level.get("sourceTrace", {}).get("vpkSha256")
		or data.get("visual_scene") != root.scene_file_path
		or not FileAccess.file_exists(root.scene_file_path)
		or FileAccess.get_sha256(root.scene_file_path) != data.get("visual_sha256")
	):
		return invalid()
	var anchors: Variant = data.get("anchors")
	if not anchors is Array or anchors.size() != 3:
		return invalid()
	var paths: Array[String] = []
	var result := invalid()
	for entry in anchors:
		if not entry is Dictionary or not entry.get("path") is String:
			return invalid()
		var path: String = entry.path
		if (
			path.is_empty()
			or path.begins_with("/")
			or ":" in path
			or "\\" in path
			or ".." in path.split("/")
			or "." in path.split("/")
			or path in paths
		):
			return invalid()
		paths.append(path)
		var mesh := root.get_node_or_null(NodePath(path)) as MeshInstance3D
		if mesh == null or mesh.mesh == null or not Adapter.valid_alignment(mesh.global_transform):
			return invalid()
		var bounds: Variant = entry.get("source_bounds")
		if not bounds is Array or bounds.size() != 6:
			return invalid()
		for value in bounds:
			if not (value is int or value is float) or not is_finite(float(value)):
				return invalid()
		var box := mesh.mesh.get_aabb()
		if (
			box.position.distance_to(Vector3(bounds[0], bounds[1], bounds[2])) > 0.01
			or box.end.distance_to(Vector3(bounds[3], bounds[4], bounds[5])) > 0.01
		):
			return invalid()
		if paths.size() == 1:
			result = mesh.global_transform
		elif not result.is_equal_approx(mesh.global_transform):
			return invalid()
	return result
