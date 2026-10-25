extends RefCounted

const Navigation = preload("res://scripts/ai/BotNavigationModel.gd")


static func run(host: Node) -> void:
	var graph := {"points": [], "links": []}
	for index in range(300):
		graph.points.append([index, 0, 0])
		if index > 0:
			graph.links.append([index - 1, index])
	var prepared := Navigation.prepare(graph)
	var first := Navigation.new()
	var second := Navigation.new()
	var legacy := Navigation.new()
	first.configure(prepared)
	second.configure(prepared)
	legacy.configure(graph)
	var danger: Array[Dictionary] = []
	host.call("_assert_true", first.points.is_read_only(), "prepared points cannot be edited")
	host.call("_assert_true", first.links.is_read_only(), "prepared adjacency cannot be edited")
	host.call("_assert_true", first.links[0].is_read_only(), "prepared neighbors cannot be edited")
	host.call(
		"_assert_true",
		first.links[0][0].is_read_only(),
		"prepared edge attributes cannot be edited"
	)
	host.call(
		"_assert_equal", first.links, legacy.links, "normalized topology matches legacy parse"
	)
	host.call("_assert_equal", first.link_count, legacy.link_count, "edge counts match")
	host.call(
		"_assert_true",
		first.get("_uniform_search") != second.get("_uniform_search"),
		"native searches remain per actor"
	)
	var direct := legacy.find_path(0, 20, danger)
	host.call(
		"_assert_equal",
		first.find_path(0, 20, danger),
		direct,
		"prepared path matches direct configuration"
	)
	first.set_point_blocked(10, true)
	host.call(
		"_assert_true", first.find_path(0, 20, danger).is_empty(), "local blocked node is respected"
	)
	host.call(
		"_assert_equal", second.find_path(0, 20, danger), direct, "another actor keeps its route"
	)
	host.call(
		"_assert_equal",
		second.nearest_index(Vector3(10, 0, 0)),
		10,
		"another actor keeps closest node"
	)
	first.configure(prepared)
	host.call(
		"_assert_equal",
		first.find_path(0, 20, danger),
		direct,
		"reconfigure clears local block state"
	)
	prepared.configure({})
	host.call(
		"_assert_equal",
		second.find_path(0, 20, danger),
		direct,
		"template retirement cannot clear actor topology"
	)
	first.configure({})
	host.call(
		"_assert_true", first.points.is_empty(), "ordinary reconfigure discards prepared topology"
	)
	host.call(
		"_assert_equal",
		second.find_path(0, 20, danger),
		direct,
		"reconfigure cannot clear another actor"
	)
	graph.links[0] = {"from": 0, "to": 1, "cover": 0.7, "crouch": true, "costMultiplier": 1.4}
	var weighted := Navigation.prepare(graph)
	first.configure(weighted)
	legacy.configure(graph)
	host.call(
		"_assert_true",
		first.get("_uniform_search") == null,
		"weighted topology retains tactical search"
	)
	danger.append({"position": Vector3(4, 0, 0), "radius": 2, "intensity": 0.7})
	host.call(
		"_assert_equal",
		first.find_path(0, 8, danger),
		legacy.find_path(0, 8, danger),
		"weighted dynamic-danger route is unchanged"
	)
	host.call(
		"_assert_equal",
		first.find_link(0, 1, danger),
		legacy.find_link(0, 1, danger),
		"cover and traversal rules are unchanged"
	)
	graph.points[0][0] = 99
	graph.links[0].cover = 0.0
	host.call(
		"_assert_equal", first.points[0], Vector3.ZERO, "source edits cannot mutate prepared points"
	)
	host.call(
		"_assert_equal", first.links[0][0].cover, 0.7, "source edits cannot mutate prepared edges"
	)

	var fork := (
		Navigation
		. prepare(
			{
				"points": [[0, 0, 0], [2, 0, 0], [1, 0, 2]],
				"links": [[0, 1], [0, 2], [2, 1]],
			}
		)
	)
	first.configure(fork)
	second.configure(fork)
	var threat: Array[Dictionary] = [
		{"position": Vector3(1, 0, 0), "radius": 1.0, "intensity": 100.0}
	]
	var safe: Array[Dictionary] = []
	host.call(
		"_assert_equal",
		first.find_path(0, 1, threat),
		[0, 2, 1],
		"dynamic danger chooses alternate route"
	)
	host.call(
		"_assert_equal",
		second.find_path(0, 1, safe),
		[0, 1],
		"another actor without danger keeps direct route"
	)
	host.call(
		"_assert_equal", first.find_path(0, 1, safe), [0, 1], "expired danger restores direct route"
	)
