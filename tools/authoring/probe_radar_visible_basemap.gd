extends "res://tools/authoring/probe_optional_export_vulkan.gd"
## Same frozen pose, with only the radar basemap texture replaced by transparent data.


func _capture(label: String) -> void:
	var radar: Control = game.get_node("CombatHud/HudRoot/Radar")
	var snapshot: Dictionary = {}
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		snapshot = radar.call("get_debug_snapshot")
		if snapshot.atlas_status == "ready" and int(snapshot.atlas_layer) >= 0:
			break
	assert(snapshot.atlas_status == "ready")
	assert(int(snapshot.atlas_layer) >= 0)
	var atlas: RefCounted = radar.get("_atlas")
	var manifest: Dictionary = atlas.get("manifest")
	assert(int(snapshot.atlas_layer_count) == manifest.layers.size())
	assert(int(snapshot.atlas_layer) < manifest.layers.size())
	var height := float(snapshot.atlas_floor_height)
	var nearest_distance := INF
	for layer in manifest.layers:
		nearest_distance = minf(nearest_distance, absf(float(layer.height) - height))
	var selected_height := float(manifest.layers[int(snapshot.atlas_layer)].height)
	var selected_distance := absf(selected_height - height)
	assert(selected_distance <= 2.5 and selected_distance <= nearest_distance + 0.25)
	var mode := game.process_mode
	game.process_mode = Node.PROCESS_MODE_DISABLED
	await super._capture(label)
	var saved: Dictionary = radar.get("_atlas_slice")
	var hidden := saved.duplicate()
	var blank := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	blank.fill(Color.TRANSPARENT)
	hidden.texture = ImageTexture.create_from_image(blank)
	radar.set("_atlas_slice", hidden)
	radar.queue_redraw()
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	assert(
		(
			host.viewport.get_texture().get_image().save_png(
				output.path_join(label + "-hidden.png")
			)
			== OK
		)
	)
	radar.set("_atlas_slice", saved)
	radar.queue_redraw()
	game.process_mode = mode
	var proof := {
		"snapshot": snapshot,
		"identity_source": atlas.get("identity_source"),
		"identity_digest": atlas.get("identity_digest"),
		"layer_count": manifest.layers.size(),
		"selected_height": selected_height,
		"selected_distance": selected_distance,
		"nearest_distance": nearest_distance,
		"radar_rect": str(radar.get_global_rect()),
		"comparison": "Only basemap texture hidden; grid and markers retained"
	}
	FileAccess.open(output.path_join(label + "-radar.json"), FileAccess.WRITE).store_string(
		JSON.stringify(proof, "\t")
	)
