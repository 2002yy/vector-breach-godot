extends SceneTree

var requested_rate := 60


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rate="):
			requested_rate = int(arg.trim_prefix("--rate="))
			if requested_rate not in [60, 120]:
				quit(1)
				return
	Engine.physics_ticks_per_second = requested_rate
	_open.call_deferred()


func _open() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: weapon-manifest.json new-receipt.json [--smoke|--render-smoke]")
		quit(1)
		return
	var session = load("res://tools/authoring/WeaponMovementObservationSession.gd").new()
	session.requested_rate = requested_rate
	session.manifest_path = args[0]
	session.output_path = args[1]
	session.render_smoke = "--render-smoke" in args
	session.smoke = "--smoke" in args or session.render_smoke
	root.add_child(session)
