extends Node

const Official = preload("res://scripts/player/OfficialEquipment.gd")
const Guide = preload("res://scripts/ui/PlayerGuide.gd")
var kills: VBoxContainer
var team_messages: VBoxContainer
var _seen: Dictionary = {}
var _radio_times: Dictionary = {}


func build(root: Control, kill_box: VBoxContainer) -> void:
	kills = kill_box
	kills.offset_left = -560
	team_messages = VBoxContainer.new()
	team_messages.name = "TeamMessages"
	team_messages.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	team_messages.offset_left = 24
	team_messages.offset_right = 460
	team_messages.offset_top = -250
	team_messages.offset_bottom = -110
	team_messages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(team_messages)
	CombatEvents.death_reported.connect(show_death)
	CombatEvents.round_cleared.connect(clear)


func clear() -> void:
	for box in [kills, team_messages]:
		if box == null:
			continue
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	_seen.clear()
	_radio_times.clear()


func show_death(event: Dictionary) -> void:
	var id := int(event.get("id", 0))
	if id != 0 and _seen.has(id):
		return
	_seen[id] = true
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.05, 0.88)
	style.border_color = (
		Color("c7ad68") if bool(event.get("local_involved", false)) else Color("465058")
	)
	style.set_border_width_all(1)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 7)
	panel.add_child(row)
	var killer := String(event.get("killer", "环境"))
	var assists: Array = event.get("assists", [])
	if not assists.is_empty():
		killer += " + " + ", ".join(assists)
	row.add_child(_label(killer, _team_color(String(event.get("killer_team", "")))))
	var weapon := String(event.get("weapon_id", "environment"))
	var texture := Official.preview(weapon, String(event.get("killer_team", "CT")))
	if texture != null:
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(46, 22)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = texture
		row.add_child(icon)
	var text := "环境" if weapon == "environment" else Guide.weapon_name(weapon)
	if bool(event.get("self_kill", false)):
		text += " · 自伤"
	elif bool(event.get("team_kill", false)):
		text += " · 友杀"
	if bool(event.get("headshot", false)):
		text += " · 爆头"
	if bool(event.get("penetrated", false)):
		text += " · 穿透"
	row.add_child(_label(text, Color("d3d5cd")))
	row.add_child(
		_label(String(event.get("victim", "单位")), _team_color(String(event.get("victim_team", ""))))
	)
	kills.add_child(panel)
	_trim(kills, 5)
	_expire(panel, 6.0)


func show_radio(caller: String, message: String) -> void:
	var key := caller + ":" + message
	var now := Time.get_ticks_msec()
	if now - int(_radio_times.get(key, -10000)) < 2000:
		return
	_radio_times[key] = now
	# Bound dedup state as well as the visible queue during long matches.
	for old_key in _radio_times.keys():
		if now - int(_radio_times[old_key]) > 10000:
			_radio_times.erase(old_key)
	var entry := _label("[队伍] %s：%s" % [caller, message], Color("9dcee5"))
	entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entry.add_theme_constant_override("outline_size", 4)
	entry.add_theme_color_override("font_outline_color", Color.BLACK)
	team_messages.add_child(entry)
	_trim(team_messages, 4)
	_expire(entry, 5.0)


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 16)
	return label


func _team_color(team: String) -> Color:
	return Color("80b5dc") if team == "CT" else Color("d6b565") if team == "T" else Color("bfc3bc")


func _trim(box: VBoxContainer, limit: int) -> void:
	while box.get_child_count() > limit:
		var child := box.get_child(0)
		box.remove_child(child)
		child.queue_free()


func _expire(node: Node, seconds: float) -> void:
	var reference: WeakRef = weakref(node)
	get_tree().create_timer(seconds).timeout.connect(
		func() -> void:
			var live: Node = reference.get_ref()
			if is_instance_valid(live):
				live.queue_free()
	)
