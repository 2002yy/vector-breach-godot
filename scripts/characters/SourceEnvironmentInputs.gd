extends RefCounted

const Reflection = preload("res://scripts/level/SourceReflectionTexture.gd")
const BRDF_SHA := "2b234525df00b01659f9bbbefc4a8a2fb47f315f0508a5852fe3f8e426f707ee"
var texture: Texture2DArray
var harmonics := PackedVector4Array()


# gdlint: disable=max-returns
static func validate(data: Dictionary, reflection: Dictionary, raw: PackedByteArray) -> bool:
	if (
		data.get("schema") != 1
		or data.get("contract") != "source-reflection-normalization-v1"
		or not data.get("level") is String
		or data.level != reflection.get("level")
		or data.get("source_trace") != reflection.get("source_trace")
		or data.get("reflection_sha256") != reflection.get("sha256")
		or data.get("compiled_reflection_sha256") != reflection.get("compiled_sha256")
		or reflection.get("mip_count") != 7
		or not data.get("brdf") is Dictionary
		or data.brdf.get("file") != "brdf-rgba-f32.bin"
		or data.brdf.get("compiled_sha256") != BRDF_SHA
		or data.brdf.get("sha256") != Reflection._sha(raw)
		or raw.size() != 64 * 64 * 3 * 16
	):
		return false
	var native: Variant = data.get("native_sh")
	var rows: Variant = data.get("normalization_sh")
	var count: Variant = reflection.get("cubes")
	if (
		not (count is int or count is float)
		or not is_finite(count)
		or count != int(count)
		or count < 1
		or count > 128
	):
		return false
	if (
		not native is Dictionary
		or native.get("compiled_sha256") != reflection.get("compiled_sha256")
	):
		return false
	if not rows is Array or rows.size() != int(count) or native.get("cubes") != count:
		return false
	var coefficients: Variant = native.get("native_coefficients")
	if not coefficients is Array or coefficients.size() != int(count) * 27:
		return false
	for value in coefficients:
		if not (value is int or value is float) or not is_finite(value):
			return false
	for i in range(int(count)):
		if not rows[i] is Array or rows[i].size() != 4:
			return false
		var luma := PackedFloat64Array([0, 0, 0, 0])
		for band in range(4):
			for channel in range(3):
				luma[band] += (
					coefficients[i * 27 + channel * 9 + band] * [0.2125, 0.7154, 0.0721][channel]
				)
		var expected := [
			luma[3] * 0.325735, luma[1] * 0.325735, luma[2] * 0.325735, luma[0] * 0.282095
		]
		for band in range(4):
			var value: Variant = rows[i][band]
			if (
				not (value is int or value is float)
				or not is_finite(value)
				or absf(value - expected[band]) > 0.000001
			):
				return false
	for i in range(0, raw.size(), 4):
		if not is_finite(raw.decode_float(i)):
			return false
	return true


func configure(path: String, reflection: Dictionary) -> bool:
	texture = null
	harmonics.clear()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return false
	var raw := FileAccess.get_file_as_bytes(path.get_base_dir().path_join("brdf-rgba-f32.bin"))
	if not validate(data, reflection, raw) or DisplayServer.get_name() == "headless":
		return false
	var images: Array[Image] = []
	for layer in range(3):
		images.append(
			Image.create_from_data(
				64, 64, false, Image.FORMAT_RGBAF, raw.slice(layer * 65536, (layer + 1) * 65536)
			)
		)
	var result := Texture2DArray.new()
	if result.create_from_images(images) != OK:
		return false
	texture = result
	harmonics.resize(128)
	for i in range(data.normalization_sh.size()):
		var row: Array = data.normalization_sh[i]
		harmonics[i] = Vector4(row[0], row[1], row[2], row[3])
	return true


func bind(material: ShaderMaterial) -> bool:
	if texture == null:
		return false
	material.set_shader_parameter("source_brdf_lut", texture)
	material.set_shader_parameter("reflection_sh", harmonics)
	return true
