extends SceneTree


func _initialize() -> void:
	_open.call_deferred()


func _open() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("Usage: manifest.json new-receipt.json [--smoke]")
		quit(1)
		return
	var session = load("res://tools/authoring/JumpPlaytestSession.gd").new()
	session.manifest_path = args[0]
	session.output_path = args[1]
	session.render_smoke = "--render-smoke" in args
	session.smoke = "--smoke" in args or session.render_smoke
	root.add_child(session)
