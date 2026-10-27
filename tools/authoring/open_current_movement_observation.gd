extends SceneTree


func _initialize() -> void:
	_open.call_deferred()


func _open() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: selected-manifest.json new-receipt.json [--smoke|--render-smoke]")
		quit(1)
		return
	for arg in args:
		if arg.begins_with("--rate="):
			var rate := int(arg.trim_prefix("--rate="))
			if rate not in [60, 120]:
				quit(1)
				return
			Engine.physics_ticks_per_second = rate
	var session = load("res://tools/authoring/CurrentMovementObservationSession.gd").new()
	session.manifest_path = args[0]
	session.output_path = args[1]
	session.render_smoke = "--render-smoke" in args
	session.smoke = "--smoke" in args or session.render_smoke
	root.add_child(session)
