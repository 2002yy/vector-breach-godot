extends CanvasLayer

@onready var perf_label: Label = $StatusPanel/Margin/VBox/Perf
@onready var quality_label: Label = $StatusPanel/Margin/VBox/Quality
@onready var level_label: Label = $StatusPanel/Margin/VBox/Level
@onready var state_label: Label = $StatusPanel/Margin/VBox/State
@onready var movement_label: Label = $StatusPanel/Margin/VBox/Movement
@onready var weapon_debug_label: Label = $StatusPanel/Margin/VBox/WeaponDebug
@onready var position_label: Label = $StatusPanel/Margin/VBox/Position
@onready var control_label: Label = $StatusPanel/Margin/VBox/Controls

func update_display(snapshot: Dictionary) -> void:
	var fps: int = roundi(Engine.get_frames_per_second())
	perf_label.text = "\u5e27\u6570\uff1a%d" % fps
	quality_label.text = _build_quality_text()
	level_label.text = "\u5730\u56fe\uff1a%s" % GameState.current_level_name
	state_label.text = "\u72b6\u6001\uff1a%s | \u7a97\u53e3\uff1a%s | \u9f20\u6807\uff1a%s" % [
		RoundManager.get_state_label(),
		String(snapshot.get("window", "\u7a97\u53e3")),
		String(snapshot.get("mouse", "\u81ea\u7531"))
	]
	movement_label.text = "\u901f\u5ea6\uff1a%.2f | \u843d\u5730\uff1a%s" % [
		float(snapshot.get("speed", 0.0)),
		"\u662f" if bool(snapshot.get("grounded", false)) else "\u5426"
	]
	weapon_debug_label.text = "\u6269\u6563\uff1a%.2f\u00b0 | \u540e\u5750\uff1a%.3f" % [
		float(GameState.current_spread_degrees),
		float(GameState.recoil_display_value)
	]
	var pos: Vector3 = snapshot.get("position", Vector3.ZERO)
	position_label.text = "\u5750\u6807\uff1aX %.2f | Y %.2f | Z %.2f" % [pos.x, pos.y, pos.z]
	control_label.text = "\u5feb\u6377\u952e\uff1aEsc/P \u83dc\u5355 | F \u5168\u5c4f | F3 \u9690\u85cf\u8c03\u8bd5"

func _build_quality_text() -> String:
	var renderer: String = String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus"))
	var msaa_value: int = int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0))
	var physics_engine: String = String(ProjectSettings.get_setting("physics/3d/physics_engine", "Default"))
	var interpolation_enabled: bool = bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false))

	var preset_label: String = _quality_preset_label(renderer, msaa_value, physics_engine, interpolation_enabled)
	return "\u753b\u8d28\uff1a%s | \u6e32\u67d3\uff1a%s | MSAA\uff1a%s | \u7269\u7406\uff1a%s | \u63d2\u503c\uff1a%s | \u51e0\u4f55\uff1a%s" % [
		preset_label,
		_renderer_name(renderer),
		_msaa_name(msaa_value),
		physics_engine,
		"\u5f00" if interpolation_enabled else "\u5173",
		GameState.get_graphics_preset_label()
	]

func _quality_preset_label(renderer: String, msaa_value: int, physics_engine: String, interpolation_enabled: bool) -> String:
	var is_forward_plus: bool = renderer == "forward_plus"
	var is_jolt: bool = physics_engine == "Jolt Physics"
	if is_forward_plus and msaa_value >= 1 and is_jolt and interpolation_enabled:
		return "\u539f\u578b+"
	if is_forward_plus and is_jolt and interpolation_enabled:
		return "\u539f\u578b"
	if renderer == "mobile" and msaa_value == 0:
		return "\u4f4e"
	if is_forward_plus and msaa_value == 0:
		return "\u4e2d"
	return "\u81ea\u5b9a\u4e49"

func _renderer_name(value: String) -> String:
	match value:
		"forward_plus":
			return "Forward+"
		"mobile":
			return "\u79fb\u52a8"
		"gl_compatibility":
			return "GL \u517c\u5bb9"
		_:
			return value

func _msaa_name(value: int) -> String:
	match value:
		0:
			return "\u5173"
		1:
			return "2x"
		2:
			return "4x"
		3:
			return "8x"
		_:
			return str(value)
