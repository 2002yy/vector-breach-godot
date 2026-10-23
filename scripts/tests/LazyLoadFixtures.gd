extends RefCounted


class FailedLevel:
	extends "res://scripts/level/GrayboxLevel.gd"

	func load_level(next_level_id: String, _emit_errors: bool = true) -> bool:
		load_count += 1
		last_load_timings = {"id": next_level_id, "success": false}
		return false


static func run(host: Node) -> void:
	var main: Node = host.call("_instantiate_main", false)
	await host.call("_await_main_ready")
	var level := main.get_node("Level")
	var player := main.get_node("Player")
	var at: Vector3 = player.global_position
	for id in ["training-range", "foundry-reforged", "gatehouse", "training-range", "gatehouse"]:
		main.call("_on_map_selected", main.call("find_level_option_index", id))
		host.call("_assert_equal", level.load_count, 0, "selecting cards must not load geometry")
		host.call(
			"_assert_equal",
			level.get_node("GeometryRoot").get_child_count(),
			0,
			"no preview collision"
		)
		host.call(
			"_assert_equal", level.get_node("VisualRoot").get_child_count(), 0, "no preview GLB"
		)
		host.call(
			"_assert_true", not player.is_physics_processing(), "unloaded-menu player cannot fall"
		)
		host.call("_assert_equal", player.global_position, at, "selection cannot move player")
	main.call("_on_start_pressed")
	main.call("_on_start_pressed")
	main.call("_on_map_selected", main.call("find_level_option_index", "training-range"))
	host.call("_assert_true", main._starting, "start is pending while loading frame is painted")
	host.call("_assert_equal", level.load_count, 0, "loading UI is shown before engine work")
	while main._starting:
		await host.get_tree().process_frame
	host.call("_assert_equal", level.load_count, 1, "double start loads only once")
	host.call(
		"_assert_equal",
		level.get_current_level_data().id,
		"gatehouse",
		"pending start cannot change maps"
	)
	host.call(
		"_assert_true",
		main.game_started and main.last_start_timings.success,
		"match becomes playable"
	)
	host.call("_assert_true", main.last_start_timings.total_ms >= 0, "start duration measured")
	main.call("_open_menu", false)
	main.call("_return_to_map_selection")
	main.call("_on_map_selected", main.call("find_level_option_index", "training-range"))
	host.call("_assert_equal", level.load_count, 1, "return and reselect do not reload")
	await main.call("_on_start_pressed")
	host.call("_assert_equal", level.load_count, 2, "next start loads the final selection once")
	host.call(
		"_assert_equal",
		level.get_current_level_data().id,
		"training-range",
		"new map actually loaded"
	)
	await host.call("_cleanup_main", main)
	await _failure(host)


static func _failure(host: Node) -> void:
	var main: Node = host.call("_instantiate_main", false)
	await host.call("_await_main_ready")
	main.get_node("Level").set_script(FailedLevel)
	var failed: Array = []
	var selected: String = main.level_options[main.selected_level_index].id
	main.level_start_failed.connect(func(id: String): failed.append(id))
	await main.call("_on_start_pressed")
	host.call("_assert_equal", failed, [selected], "failed Start publishes one lifecycle failure")
	host.call(
		"_assert_true",
		not main._starting and not main._level_loading,
		"failure releases loading state"
	)
	host.call(
		"_assert_true",
		not main.game_started and not main.last_start_timings.success,
		"failure cannot enter old world"
	)
	host.call(
		"_assert_true",
		main.menu_open and not GameState.match_active,
		"failure returns to inactive menu"
	)
	host.call(
		"_assert_true", not main.get_node("StartMenu").start_button.disabled, "failure allows retry"
	)
	await host.call("_cleanup_main", main)
