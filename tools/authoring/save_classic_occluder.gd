extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]):
		quit(1)
		return
	var file := FileAccess.open(args[0], FileAccess.READ)
	var count := file.get_32()
	if count == 0 or count % 3 != 0 or file.get_length() != 4 + count * 12:
		quit(1)
		return
	var floats := file.get_buffer(count * 12).to_float32_array()
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	vertices.resize(count)
	indices.resize(count)
	for index in range(count):
		vertices[index] = Vector3(floats[index * 3], floats[index * 3 + 1], floats[index * 3 + 2])
		indices[index] = index
	var occluder := ArrayOccluder3D.new()
	occluder.set_arrays(vertices, indices)
	var result := ResourceSaver.save(occluder, args[1])
	print("CLASSIC_OCCLUDER_SAVE=" + str(result))
	quit(0 if result == OK else 1)
