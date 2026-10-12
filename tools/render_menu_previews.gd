extends SceneTree
## Bake lightweight menu art from actual VoxelWorld geometry and imported models.
## Run with the Compatibility GPU renderer after project import; never --headless.

const CATALOG = preload("res://ui/map_catalog.gd")
const WORLD = preload("res://world/voxel_world.gd")
const DATA = preload("res://world/voxel_data.gd")
const ARENA = preload("res://ai/tdm_arena.gd")
const MAP_PACKAGE = preload("res://world/blockfield_map.gd")
const MODELS = preload("res://presentation/openspades_models.gd")
const MAP_SIZE: Vector2i = Vector2i(640, 360)
const WEAPON_SIZE: Vector2i = Vector2i(512, 192)
const UPSTREAM_COMMIT: String = "dcf449c845d509bbde9d79239b32d201c1389961"

var output: String = "res://assets/ui/menu"
var only: PackedStringArray = []
var failures: int = 0
var records: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("MENU PREVIEWS requires a real Compatibility graphics context.")
		quit(1)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
		elif argument.begins_with("--only="):
			only = argument.trim_prefix("--only=").split(",", false)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(output)
	if directory_error != OK:
		push_error("Cannot create preview directory: " + output)
		quit(1)
		return
	var provenance_path: String = output.path_join("provenance.json")
	if FileAccess.file_exists(provenance_path):
		var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(provenance_path))
		if typeof(old) == TYPE_DICTIONARY and typeof(old.get("previews")) == TYPE_DICTIONARY:
			records = old.previews
	for entry: Dictionary in CATALOG.entries():
		if only.is_empty() or only.has(str(entry.id)):
			await _render_map(entry)
	var weapon_names: Array[String] = ["Rifle", "SMG", "Shotgun"]
	for weapon: String in weapon_names:
		if only.is_empty() or only.has(weapon.to_lower()):
			await _render_weapon(weapon)
	_write_provenance()
	print("MENU PREVIEWS: %d files recorded; %d failures; %s" % [records.size(), failures, output])
	quit(0 if failures == 0 else 1)

func _render_map(entry: Dictionary) -> void:
	var began: int = Time.get_ticks_msec()
	var map_id: String = str(entry.id)
	print("MENU PREVIEWS: loading " + map_id)
	root.size = MAP_SIZE
	root.transparent_bg = false
	var stage: Node3D = _stage(true)
	var world: VoxelWorld = WORLD.new()
	# The imported maps reuse chunk meshes. There is never a node per voxel.
	world.render_radius = 10
	var map_data: VoxelData = DATA.new()
	var metadata: Dictionary = {}
	var source: String = str(entry.resource)
	var error: Error = OK
	match map_id:
		"crossroads":
			map_data = ARENA.build()
			source = "res://ai/tdm_arena.gd"
		"lab":
			error = map_data.generate_lab()
			source = "res://world/voxel_data.gd"
		"title":
			error = map_data.load_vxl_bytes(FileAccess.get_file_as_bytes(source))
		"mirage", "dust2":
			var loaded: Dictionary = MAP_PACKAGE.load_bytes(FileAccess.get_file_as_bytes(source))
			error = loaded.error
			if error == OK:
				map_data = loaded.data
				metadata = loaded.metadata
		_:
			error = ERR_INVALID_PARAMETER
	if error != OK:
		_fail("Map load failed: %s (%d)" % [map_id, error])
		stage.queue_free()
		await process_frame
		return
	world.data = map_data
	if metadata.has("water_enabled"):
		world.water_enabled = bool(metadata.water_enabled)
	stage.add_child(world)
	var spawn: Vector3 = Vector3.INF
	if metadata.has("spawn"):
		var point: Array = metadata.spawn
		spawn = Vector3(float(point[0]), float(point[1]), float(point[2]))
	error = world.set_map_data(map_data, str(entry.name_en), true, spawn)
	if error != OK:
		_fail("Map adoption failed: " + map_id)
		stage.queue_free()
		await process_frame
		return
	var camera: Camera3D = Camera3D.new()
	camera.current = true
	camera.fov = 57.0
	camera.near = 0.05
	camera.far = 900.0
	stage.add_child(camera)
	var target: Vector3 = world.get_spawn_position()
	match map_id:
		"crossroads":
			target = Vector3(40, 4, 28)
			camera.position = Vector3(79, 31, 63)
		"lab":
			target = Vector3(45, 6, 42)
			camera.position = Vector3(80, 30, 86)
		"mirage":
			target = Vector3(86, 12, 84)
			camera.position = Vector3(179, 104, 188)
			camera.fov = 55.0
		"title":
			target += Vector3(-12, -2, -14)
			camera.position = world.get_spawn_position() + Vector3(56, 50, 66)
		_:
			camera.position = target + Vector3(40, 35, 40)
	camera.look_at(target)
	world.set_view_position(target)
	world.rebuild_now()
	# Inspection cameras can sit outside gameplay chunk-distance culling.
	# Disable culling on this offline bake only, after real chunk construction.
	for node: Node in world.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		mesh.visibility_range_begin = 0.0
		mesh.visibility_range_end = 0.0
	world.set_process(false)
	var image: Image = await _capture()
	var filename: String = "map_" + map_id + ".png"
	if image.save_png(output.path_join(filename)) != OK:
		_fail("Could not save " + filename)
	else:
		records[filename] = {"kind": "actual_game_world", "source": source,
			"source_sha256": _hash_file(source), "dimensions": [640, 360],
			"camera_position": _vector(camera.position), "camera_target": _vector(target),
			"camera_fov": camera.fov, "image_sha256": _hash_file(output.path_join(filename))}
	print("MENU PREVIEWS: %s in %.2fs" % [filename, float(Time.get_ticks_msec() - began) / 1000.0])
	stage.queue_free()
	await process_frame
	await process_frame

func _render_weapon(weapon: String) -> void:
	print("MENU PREVIEWS: rendering original " + weapon)
	# The project uses a 1280x720 canvas. Its inherited KEEP aspect clipped
	# the512x192 window's framebuffer to341x192, while camera fitting assumed
	#512x192. A bake needs an exact image-sized viewport, independent of UI scale.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = WEAPON_SIZE
	root.transparent_bg = true
	var stage: Node3D = _stage(false)
	var relative_path: String = "Weapons/" + weapon + "/Weapon"
	var model: Node3D = MODELS.create(relative_path)
	stage.add_child(model)
	var bounds: Array[AABB] = []
	_mesh_bounds(model, bounds)
	if bounds.is_empty():
		_fail("Original model has no geometry: " + weapon)
		stage.queue_free()
		await process_frame
		return
	var combined: AABB = bounds[0]
	for box: AABB in bounds:
		combined = combined.merge(box)
	var center: Vector3 = combined.get_center()
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	camera.near = 0.05
	camera.far = 1000.0
	stage.add_child(camera)
	var direction: Vector3 = Vector3(1.0, 0.22, 0.30).normalized()
	camera.position = center + direction * maxf(10.0, combined.size.length() * 2.0)
	camera.look_at(center)
	# A cool studio key lifts the source's dark metal above a dark menu card.
	# It changes only this isolated capture stage, preserving imported colors.
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation = camera.rotation
	key.light_color = Color(0.86, 0.94, 1.0)
	key.light_energy = 3.0
	stage.add_child(key)
	var camera_space: Transform3D = camera.global_transform.affine_inverse()
	var low: Vector2 = Vector2(INF, INF)
	var high: Vector2 = Vector2(-INF, -INF)
	for corner: int in 8:
		var local: Vector3 = camera_space * combined.get_endpoint(corner)
		low = low.min(Vector2(local.x, local.y))
		high = high.max(Vector2(local.x, local.y))
	var dimensions: Vector2 = high - low
	var aspect: float = float(WEAPON_SIZE.x) / float(WEAPON_SIZE.y)
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = maxf(dimensions.y, dimensions.x / aspect) * 1.22
	var image: Image = await _capture()
	if image.get_size() != WEAPON_SIZE:
		_fail("Weapon framebuffer must be512x192, got " + str(image.get_size()))
	var filename: String = "weapon_" + weapon.to_lower() + ".png"
	if image.save_png(output.path_join(filename)) != OK:
		_fail("Could not save " + filename)
	else:
		var source: String = MODELS.ASSET_ROOT + relative_path + ".glb"
		records[filename] = {"kind": "original_imported_weapon", "source": source,
			"source_sha256": _hash_file(source), "dimensions": [512, 192],
			"camera_direction": _vector(direction), "camera_projection": "orthogonal",
			"camera_size": camera.size, "transparent": true,
			"studio_ambient_energy": 3.0, "studio_key_energy": 3.0,
			"image_sha256": _hash_file(output.path_join(filename))}
	stage.queue_free()
	await process_frame
	await process_frame
	MODELS.clear_cache()
	root.transparent_bg = false

func _stage(use_sky: bool) -> Node3D:
	var stage: Node3D = Node3D.new()
	root.add_child(stage)
	var holder: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b7c9d2") if use_sky else Color.WHITE
	environment.ambient_light_energy = 0.75 if use_sky else 3.0
	if use_sky:
		environment.background_mode = Environment.BG_SKY
		var material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
		material.sky_top_color = Color("557f9c")
		material.sky_horizon_color = Color("c7d4d0")
		material.ground_horizon_color = Color("c7d4d0")
		material.ground_bottom_color = Color("343e3d")
		var sky: Sky = Sky.new()
		sky.sky_material = material
		environment.sky = sky
	else:
		environment.background_mode = Environment.BG_CLEAR_COLOR
	holder.environment = environment
	stage.add_child(holder)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_color = Color(1.0, 0.91, 0.78)
	sun.light_energy = 1.1
	stage.add_child(sun)
	return stage

func _mesh_bounds(node: Node, bounds: Array[AABB]) -> void:
	if node is MeshInstance3D:
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh != null:
			bounds.append(mesh.global_transform * mesh.get_aabb())
	for child: Node in node.get_children():
		_mesh_bounds(child, bounds)

func _capture() -> Image:
	for frame: int in 8:
		await process_frame
		await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _write_provenance() -> void:
	var document: Dictionary = {"generator": "tools/render_menu_previews.gd",
		"engine": Engine.get_version_info().string, "renderer": "Compatibility",
		"upstream": "OpenSpades v0.1.3", "upstream_commit": UPSTREAM_COMMIT,
		"description": "Offline GPU captures of existing game worlds and original imported models; no AI imagery.",
		"previews": records}
	var file: FileAccess = FileAccess.open(output.path_join("provenance.json"), FileAccess.WRITE)
	if file == null:
		_fail("Cannot save preview provenance")
		return
	file.store_string(JSON.stringify(document, "\t") + "\n")

func _hash_file(path: String) -> String:
	return FileAccess.get_sha256(path)

func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

func _fail(message: String) -> void:
	failures += 1
	push_error("MENU PREVIEWS: " + message)
