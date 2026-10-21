extends RefCounted

signal upload_finished

var texture: TextureCubemapArrayRD
var _rid := RID()
var _busy := false
var _cancelled := false


# gdlint: disable=max-returns
static func validate(data: Dictionary, payload: PackedByteArray) -> bool:
	if not _integer_equal(data.get("schema"), 1):
		return false
	for key in ["contract", "format", "layout"]:
		if not data.get(key) is String:
			return false
	if not data.get("face_order") is Array:
		return false
	if (
		data.get("schema") != 1
		or data.get("contract") != "source-reflection-blocks-v1"
		or data.get("format") != "BC6H-UFLOAT"
		or data.get("layout") != "mip-ascending/cube/face/BC6H-blocks"
		or data.get("face_order") != ["+X", "-X", "+Y", "-Y", "+Z", "-Z"]
	):
		return false
	for key in ["width", "cubes", "mip_count"]:
		var value: Variant = data.get(key)
		if not (value is float or value is int) or not is_finite(value) or value != int(value):
			return false
	var width := int(data.width)
	var cubes := int(data.cubes)
	var count := int(data.mip_count)
	if width < 1 or width > 4096 or (width & (width - 1)) != 0 or cubes < 1 or cubes > 128:
		return false
	if count < 1 or count > int(log(width) / log(2.0)) + 1:
		return false
	if not data.get("mips") is Array or data.mips.size() != count:
		return false
	var offset := 0
	for level in range(count):
		var mip: Variant = data.mips[level]
		if not mip is Dictionary:
			return false
		var size := maxi(1, width >> level)
		var blocks := maxi(1, ceili(size / 4.0))
		var face_bytes := blocks * blocks * 16
		var length := face_bytes * cubes * 6
		var expected := {
			"level": level,
			"size": size,
			"offset": offset,
			"face_bytes": face_bytes,
			"bytes": length
		}
		for key in expected:
			if not _integer_equal(mip.get(key), expected[key]):
				return false
		if not mip.get("sha256") is String:
			return false
		if (
			offset + length > payload.size()
			or _sha(payload.slice(offset, offset + length)) != mip.get("sha256")
		):
			return false
		offset += length
	return offset == payload.size()


# gdlint: enable=max-returns
static func _integer_equal(value: Variant, expected: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value == expected


static func _sha(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func create(data: Dictionary, payload: PackedByteArray) -> bool:
	if (
		_busy
		or texture != null
		or DisplayServer.get_name() == "headless"
		or not validate(data, payload)
	):
		return false
	var layers: Array[PackedByteArray] = []
	for layer in range(int(data.cubes) * 6):
		var bytes := PackedByteArray()
		for mip in data.mips:
			var start := int(mip.offset) + layer * int(mip.face_bytes)
			bytes.append_array(payload.slice(start, start + int(mip.face_bytes)))
		layers.append(bytes)
	_busy = true
	_cancelled = false
	RenderingServer.call_on_render_thread(
		_upload.bind(int(data.width), int(data.mip_count), layers)
	)
	await upload_finished
	return texture != null


func _upload(width: int, mips: int, layers: Array[PackedByteArray]) -> void:
	var device := RenderingServer.get_rendering_device()
	var format := RDTextureFormat.new()
	format.width = width
	format.height = width
	format.array_layers = layers.size()
	format.mipmaps = mips
	format.texture_type = RenderingDevice.TEXTURE_TYPE_CUBE_ARRAY
	format.format = RenderingDevice.DATA_FORMAT_BC6H_UFLOAT_BLOCK
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var result := RID()
	if (
		device != null
		and device.texture_is_format_supported_for_usage(format.format, format.usage_bits)
	):
		result = device.texture_create(format, RDTextureView.new(), layers)
	_finish.call_deferred(result)


func _finish(result: RID) -> void:
	if _cancelled and result.is_valid():
		RenderingServer.call_on_render_thread(_free.bind(result))
		result = RID()
	_rid = result
	if result.is_valid():
		texture = TextureCubemapArrayRD.new()
		texture.texture_rd_rid = result
	_busy = false
	upload_finished.emit()


func release() -> void:
	_cancelled = true
	if texture != null:
		texture.texture_rd_rid = RID()
		texture = null
	if _rid.is_valid():
		RenderingServer.call_on_render_thread(_free.bind(_rid))
		_rid = RID()


static func _free(rid: RID) -> void:
	var device := RenderingServer.get_rendering_device()
	if device != null:
		device.free_rid(rid)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# The owner cannot call its own methods during PREDELETE. Bind the
		# native device directly so queued cleanup has no dead script receiver.
		if texture != null:
			texture.texture_rd_rid = RID()
		var device := RenderingServer.get_rendering_device()
		if _rid.is_valid() and device != null:
			RenderingServer.call_on_render_thread(device.free_rid.bind(_rid))
