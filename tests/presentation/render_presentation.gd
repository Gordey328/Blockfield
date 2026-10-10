extends SceneTree
## Render original character/weapon assemblies for visual QA with a real renderer.
## Run with -- --output=<absolute output directory>; never included in game flow.

const CharacterScript = preload("res://presentation/character_view.gd")
const WeaponScript = preload("res://presentation/weapon_view.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var output := "user://presentation-checks"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1024, 640)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.16, 0.21, 0.26)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 1.0
	stage.add_child(sun)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.current = true
	camera.position = Vector3(0, 2.5, -7)
	camera.look_at(Vector3(0, 1.4, 0))
	var characters: Array[Node3D] = []
	for index in range(4):
		var character := CharacterScript.new()
		stage.add_child(character)
		character.position.x = float(index) * 1.8 - 2.7
		character.set_team(index % 2)
		character.set_weapon(index % 3, 2)
		character.set_pose(index == 2, index == 3, false)
		characters.append(character)
	await _capture(output.path_join("characters.png"))
	for character in characters:
		character.free()
	camera.position = Vector3(0, 1.8, 0)
	camera.rotation = Vector3.ZERO
	camera.near = 0.025
	camera.fov = 75
	var weapon := WeaponScript.new()
	camera.add_child(weapon)
	for gun in range(3):
		weapon.set_selection(2, gun)
		weapon.set_ammo(6, 6)
		for frame in range(20):
			weapon.update_pose(0.025, false, false, false, 0)
		await _capture(output.path_join("weapon" + str(gun) + ".png"))
		weapon.update_pose(0.2, true, false, false, 0)
		await _capture(output.path_join("weapon" + str(gun) + "-ads.png"))
	weapon.free()
	stage.free()
	print("PRESENTATION_RENDER_CHECKS_OK: ", output)
	quit(0)

func _capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var texture := root.get_texture()
	var image := texture.get_image()
	assert(not image.is_empty(), "A real rendering backend is required")
	assert(image.save_png(path) == OK)
