extends RefCounted

const Progress = preload("res://scripts/ai/BotRouteProgress.gd")
const Navigation = preload("res://scripts/ai/BotNavigationModel.gd")


static func oscillation_and_blocked_nodes(host: Node) -> void:
	var progress := Progress.new()
	var reports := 0
	for index in range(960):
		var position := Vector3(sin(index * 0.1) * 0.4, 1, 0)
		if progress.observe(position, Vector3((index % 2) * 10, 1, -20), 1.0 / 60.0):
			reports += 1
	host.call("_assert_equal", reports, 3, "oscillation cannot masquerade as route progress")
	host.call(
		"_assert_equal", progress.attempts, 3, "three bounded replans have an explicit outcome"
	)
	progress.observe(Vector3(3, 1, 0), Vector3(0, 1, -20), 0.016)
	host.call("_assert_equal", progress.attempts, 0, "actual travel clears stalled episode")
	for weighted in [false, true]:
		var navigation := Navigation.new()
		var link: Variant = {"from": 0, "to": 1, "danger": 0.1} if weighted else [0, 1]
		navigation.configure(
			{
				"points": [[0, 0, 0], [1, 0, 0], [2, 0, 0], [1, 0, 2]],
				"links": [link, [1, 2], [0, 3], [3, 2]]
			}
		)
		navigation.set_point_blocked(1, true)
		var danger: Array[Dictionary] = []
		host.call(
			"_assert_equal",
			navigation.find_path(0, 2, danger),
			[0, 3, 2],
			"native and weighted search both reject blocked waypoint"
		)
		host.call(
			"_assert_true",
			navigation.nearest_index(Vector3(1, 0, 0)) != 1,
			"nearest start cannot immediately reselect rejected node"
		)
		navigation.set_point_blocked(1, false)
		host.call(
			"_assert_equal", navigation.find_path(0, 2, danger), [0, 1, 2], "expiry restores route"
		)
