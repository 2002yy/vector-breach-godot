extends RefCounted

const MAPS := {
	"inferno-classic-local":
	{"folder": "inferno", "name": "炼狱小镇 Inferno", "routes": "香蕉道、中路、A 区公寓；近距离推进与配合"},
	"mirage-classic-local":
	{"folder": "mirage", "name": "荒漠迷城 Mirage", "routes": "中路、A 区宫殿、B 区公寓；中路控制与转点"},
}


static func is_classic(id: String) -> bool:
	return id.begins_with("dustline-depths") or MAPS.has(id)


static func installed_options() -> Array:
	var options: Array = []
	# Match the existing local Dust II policy: public headless suites enumerate
	# shipped maps; optional local maps are exercised by explicit Vulkan probes.
	if DisplayServer.get_name() == "headless":
		return options
	for id in MAPS:
		if not FileAccess.file_exists("res://data/levels/%s.json" % id):
			continue
		var data := preload("res://scripts/level/LevelDataLoader.gd").load_level(id, false)
		if data.is_empty():
			continue
		if not FileAccess.file_exists(String(data.get("match_manifest", ""))):
			continue
		var visual := String(data.get("visual_scene", ""))
		if not ResourceLoader.exists(visual, "PackedScene"):
			continue
		var collision := String(data.get("runtime_collision_scene", ""))
		if not ResourceLoader.exists(collision, "PackedScene"):
			continue
		options.append(describe_option(id, data))
	return options


static func describe_option(id: String, data: Dictionary) -> Dictionary:
	if not MAPS.has(id):
		return {}
	var record: Dictionary = MAPS[id]
	var source: Dictionary = data.get("sourceTrace", {})
	var original := (
		bool(source.get("originalTextures", false))
		and not bool(data.get("reconstructed_materials", false))
	)
	return {
		"id": id,
		"name": record.name + ("（经典原始材质）" if original else "（经典复刻·重建材质）"),
		"preview": "",
		"description":
		"官方地图几何与原始贴图的本机适配版；5 对 5 爆破与购买/就绪。" if original else "原始几何、重建材质的本机研究版；5 对 5 爆破与购买/就绪。",
		"recommended_use": record.routes,
		"route_profile": record.routes,
		"test_focus": "原始材质逐区检查、独立物理与 AI 通路" if original else "实际碰撞、双爆点与 AI 通路；并非原始贴图版本",
	}
