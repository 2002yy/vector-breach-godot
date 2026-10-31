extends SceneTree

var button: Button
var rows: Array[Dictionary] = []
var live := false
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = Vector2(40, 40)
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _snapshot(label: String) -> void:
	rows.append(
		{
			"label": label,
			"live": live,
			"pressed": Input.is_action_just_pressed("probe_fire"),
			"held": Input.is_action_pressed("probe_fire")
		}
	)


func _check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error("READY_INPUT_ASSERT: " + label)


func _run() -> void:
	InputMap.add_action("probe_fire")
	var binding := InputEventMouseButton.new()
	binding.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("probe_fire", binding)
	button = Button.new()
	button.position = Vector2(10, 10)
	button.size = Vector2(120, 80)
	button.text = "Ready"
	button.pressed.connect(
		func() -> void:
			live = true
			_snapshot("button_pressed")
	)
	root.add_child(button)
	await process_frame
	await process_frame
	_mouse(true)
	_snapshot("down")
	_mouse(false)
	_snapshot("up_same_frame")
	await process_frame
	_snapshot("following_process")
	print("READY_INPUT_TIMELINE ", JSON.stringify(rows))
	_check(rows.size() == 4, "real Button must emit exactly one pressed signal")
	if rows.size() == 4:
		_check(rows[0].label == "down" and not rows[0].live, "down remains in UI")
		_check(rows[0].pressed and rows[0].held, "down registers both input states")
		_check(rows[1].label == "button_pressed", "release activates real Button")
		for index in [1, 2]:
			_check(rows[index].live, "release synchronously enables combat")
			_check(not rows[index].held, "release clears held input")
			_check(rows[index].pressed, "same-frame just_pressed survives release")
		_check(rows[3].live and not rows[3].held, "following frame retains live/release")
		_check(not rows[3].pressed, "following frame clears just_pressed")
	print("READY_INPUT_ASSERTIONS failures=", failures)
	quit(1 if failures > 0 else 0)
