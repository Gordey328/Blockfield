extends SceneTree
## GPU visual aid. Exported screenshots stay outside tracked source.
## godot --path game --rendering-method gl_compatibility --script ../tests/presentation/render_effects.gd -- --output=<absolute dir>
const Effects = preload("res://presentation/openspades_effects.gd")

class FloorWorld extends Node3D:
	var water_level := -100.0
	func get_block(cell: Vector3i) -> int:
		return 0x01777777 if cell.y == 0 else 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var output := OS.get_cache_dir().path_join("blockfield-effects-preview")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	var world := FloorWorld.new()
	root.add_child(world)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.4, 0.45)
	floor_mesh.material_override = material
	floor_mesh.position.y = 1
	world.add_child(floor_mesh)
	var sky := WorldEnvironment.new()
	sky.environment = Environment.new()
	sky.environment.background_mode = Environment.BG_COLOR
	sky.environment.background_color = Color(0.12, 0.18, 0.24)
	sky.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.environment.ambient_light_color = Color.WHITE
	sky.environment.ambient_light_energy = 0.6
	world.add_child(sky)
	var sunlight := DirectionalLight3D.new()
	sunlight.rotation_degrees = Vector3(-50, -35, 0)
	world.add_child(sunlight)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 7, 18)
	camera.look_at(Vector3(0, 2, 0))
	camera.fov = 60
	camera.current = true
	var effects := Effects.new()
	root.add_child(effects)
	effects.setup(world, camera)
	effects.set_process(false)
	effects.audio_enabled = false
	effects.rng.seed = 7341
	for data in [["BLOOD", -6.0], ["BLOCK IMPACT", -3.0], ["GRENADE", 0.0], ["MUZZLE", 3.0], ["WATER", 6.0]]:
		var label := Label3D.new()
		label.text = data[0]
		label.font_size = 32
		label.pixel_size = 0.01
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		world.add_child(label)
		label.position = Vector3(data[1], 1.2, 2)
	effects.blood(Vector3(-6, 2, 0))
	effects.block_hit(Vector3(-3, 2, 0), Vector3.UP, Color(0.2, 0.5, 0.9))
	effects.grenade_explosion(Vector3(0, 2, 0))
	effects.muzzle_fire(Vector3(3, 2, 0), Vector3.FORWARD, 0)
	effects.water_hit(Vector3(6, 2, 0))
	effects.eject_shell(Vector3(3, 2, 0), Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, 0)
	for shot in [0.02, 0.2, 0.8]:
		var steps := ceili(shot / 0.02)
		for step in range(steps):
			effects.update_effects(0.02)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("effects-%03d.png" % roundi(shot * 1000)))
	effects.clear()
	world.queue_free()
	effects.queue_free()
	camera.queue_free()
	await process_frame
	await process_frame
	print("EFFECTS_GPU_PREVIEW: " + output)
	quit()
