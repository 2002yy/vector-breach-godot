extends "res://tools/authoring/JumpPlaytestSession.gd"
## Latest-source adapter. Frozen per-profile references, no automatic playback.


func _reset_attempt(reason: String) -> void:
	scheme_index = SCHEMES.find(String(manifest.observation_scheme))
	super._reset_attempt(reason)
	var point: Dictionary = points[case_index]
	var references := PackedStringArray()
	for event in point.native_timeline:
		var keys := PackedStringArray()
		for key in event["keys"]:
			keys.append(String(key))
		var mouse := float(event.get("mouse_dx", 0.0))
		var mouse_help := " 鼠标Δx=%.1f" % mouse if mouse != 0.0 else ""
		references.append("%.3fs %s%s" % [float(event.at), "+".join(keys), mouse_help])
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 900
	label.text = "\n".join(
		[
			"Movement-4 原图人工观察 · %s" % manifest.level,
			"%s / %s / %s" % [point.parent_case, point.kind, manifest.observation_scheme],
			"点类型：%s；物理频率：%sHz" % [point.observation_status, Engine.physics_ticks_per_second],
			"参考目标：橙色首落范围；仅原起点到目标，完整路线待验",
			"输入参考（人工操作，无自动回放）：",
			" | ".join(references),
			"WASD 移动 / 鼠标视角 / 空格跳 / Ctrl 蹲 / Shift 静步",
			"F5 原点重试  F6 下一点  Esc 释放  F4 继续  F8 保存退出",
			"方案已冻结；换方案请重新启动入口。人工评分与射击观察仍待填写。",
			"来源：%s / %s" % [point.reference_source, point.reference_case]
		]
	)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_F7:
		return
	super._input(event)
