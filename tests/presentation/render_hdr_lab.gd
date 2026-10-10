extends SceneTree
## Actual-main Compatibility proof; temporary fixtures/prefs are restored.
const MAIN = preload("res://scenes/main.tscn")
const BACKUP := "user://hdr-lab-settings-before.bin"
var app: Node3D
var player: BlockfieldPlayer
var hud: LabHUD
var hdr: HdrSceneViewport
var checks := 0
var failures := 0
var output: String
var metrics: Dictionary = {}
var settings_before := PackedByteArray()
var settings_existed := false
var master_was_muted := false
var fixture: MeshInstance3D

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("HDR_LAB_GPU: " + message)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("HDR lab proof requires a real graphics context")
		quit(1)
		return
	output = ProjectSettings.globalize_path("res://../.cache/previews/hdr-lab")
	DirAccess.make_dir_recursive_absolute(output)
	if FileAccess.file_exists(BACKUP):
		var previous := FileAccess.get_file_as_bytes(BACKUP)
		settings_existed = not previous.is_empty() and previous[0] == 1
		settings_before = previous.slice(1)
		restore_settings()
	settings_existed = FileAccess.file_exists("user://settings.cfg")
	if settings_existed:
		settings_before = FileAccess.get_file_as_bytes("user://settings.cfg")
	var backup := FileAccess.open(BACKUP, FileAccess.WRITE)
	backup.store_8(1 if settings_existed else 0)
	backup.store_buffer(settings_before)
	backup.close()
	ConfigFile.new().save("user://settings.cfg")
	master_was_muted = AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(960, 540)
	app = MAIN.instantiate()
	root.add_child(app)
	check(app.has_method("set_graphics_option"), "actual main script loads")
	if not app.has_method("set_graphics_option"):
		await finish()
		return
	player = app.get_node("Player")
	hud = app.get_node("HUD")
	hdr = app.hdr_scene
	check(hdr != null and hdr.available, "actual main creates available HDR adapter")
	if hdr == null:
		await finish()
		return
	app.set_process(false)
	player.set_physics_process(false)
	app.effects.set_process(false)
	app.post_effects.set_process(false)
	hud.set_process(false)
	app.stop_audio()
	app.set_locale("en")
	hud.set_menu_visible(false)
	player.respawn_at(Vector3(48.5, 4.01, 70.5))
	player.controls_enabled = true
	player.third_person = false
	player._has_entered = true
	player._connect_simulation()
	player._update_view(.5)
	player._weapon_view.initialize_selection(2, 0)
	player._update_view(.5)
	app._player_view.hide()
	for key: String in ["hdr", "bloom", "lens", "lens_flare", "fxaa", "dof", "ssao", "camera_blur", "water_reflections", "gi"]:
		app.set_graphics_option(key, false)
	app.set_graphics_option("msaa", 0)
	app.set_graphics_option("hdr_speed", 0.0)
	hdr.exposure.automatic_update = false
	hud._update_reticle(0)
	app._update_graphics(0)
	var off: Image = await capture("01-main-ldr")
	app.set_graphics_option("hdr", true)
	await settle()
	check(hdr.enabled and root.disable_3d and hdr.scene_camera.current and not player.camera.current, "HDR owns the render camera while reference rendering is disabled")
	check(hdr.scene_viewport.world_3d == root.world_3d, "actual terrain and equipment share the HDR World3D")
	check(root.get_audio_listener_3d() != null and root.get_audio_listener_3d().get_parent() == player.camera, "spatial listener stays attached to reference camera")
	check_camera("initial")
	var on: Image = await capture("02-main-hdr")
	metrics.hdr_scene_difference = difference(off, on)
	check(float(metrics.hdr_scene_difference) > .001, "actual world visibly changes through HDR presentation")
	player.weapon_root.hide()
	var no_weapon: Image = await capture("03-hdr-without-equipment")
	player.weapon_root.show()
	var with_weapon: Image = await capture("04-hdr-equipment")
	metrics.weapon_difference = difference(no_weapon, with_weapon, .45)
	check(float(metrics.weapon_difference) > .0001, "original first-person weapon/arms remain visible under HDR")
	hud._root.hide()
	var no_hud: Image = await capture("05-hdr-without-hud")
	hud._root.show()
	var with_hud: Image = await capture("06-hdr-root-hud")
	metrics.hud_difference = difference(no_hud, with_hud)
	check(float(metrics.hud_difference) > .0001, "root HUD is rendered above the HDR scene")
	metrics.hud_readable_pixels = readable_overlay_pixels(no_hud, with_hud)
	check(int(metrics.hud_readable_pixels) > 80, "actual HUD retains readable bright glyphs/icons")
	# This is spatial geometry in the actual shared world, above/left of the gun.
	# Its expected radiance is encoded by a GPU pass before any CPU readback.
	fixture = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(.8, .8)
	fixture.mesh = quad
	var shader := Shader.new()
	shader.code = "shader_type spatial;render_mode unshaded,fog_disabled;void fragment(){ALBEDO=vec3(4.0,2.0,0.5);}"
	var material := ShaderMaterial.new()
	material.shader = shader
	fixture.material_override = material
	fixture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	app.add_child(fixture)
	fixture.global_transform = player.camera.global_transform * Transform3D(Basis.IDENTITY, Vector3(-1.3, .6, -4))
	await settle()
	var radiance: Color = await read_radiance()
	metrics.actual_world_radiance = [radiance.r, radiance.g, radiance.b]
	metrics.fixture_albedo = [4.0, 2.0, .5]
	# Godot4.7.2 Compatibility scene.glsl:2204/2570 performs the transfer
	# pair from tonemap_inc.glsl:12-21, including its polynomial approximation.
	# Independent source-formula goldens, not fitted to readback or CPU format:
	# https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/gles3/shaders/tonemap_inc.glsl
	metrics.compatibility_fixture_expected = [4.3276512478, 2.0413034295, .5009995435]
	check(absf(radiance.r - 4.3276512478) < .05 and absf(radiance.g - 2.0413034295) < .05 and absf(radiance.b - .5009995435) < .05, "GPU-encoded actual-world float color follows Compatibility transfer goldens above LDR range")
	var without_bloom: Image = await capture("07-hdr-highlight-no-bloom")
	app.set_graphics_option("bloom", true)
	var with_bloom: Image = await capture("08-hdr-highlight-native-bloom")
	metrics.bloom_difference = difference(without_bloom, with_bloom)
	check(float(metrics.bloom_difference) > .0001, "native HDR bloom visibly affects the actual scene")
	check(hdr.exposure.get_present_material().get_shader_parameter("bloom_enabled") == true, "float HDR composite owns bloom")
	check(app.post_effects._color_material.get_shader_parameter("bloom_enabled") == false and app.post_effects._color_material.get_shader_parameter("correction_enabled") == false, "later LDR pass suppresses duplicate bloom/color correction")
	check(hdr.exposure.get_present_material().get_shader_parameter("aces_enabled") == true, "actual main requests pre-LDR ACES correction")
	app.set_graphics_option("ssao", true)
	app.set_graphics_option("dof", true)
	app.set_graphics_option("manual_focus", true)
	app.post_effects.update_state(0, 100, 10, false, 0.0, 1.5)
	check(app.post_effects._depth_quad.visible, "real depth post quad is active")
	player.weapon_root.hide()
	var depth_without: Image = await capture("09-hdr-depth-no-equipment")
	player.weapon_root.show()
	var depth_with: Image = await capture("10-hdr-depth-equipment")
	metrics.depth_weapon_difference = difference(depth_without, depth_with, .45)
	check(float(metrics.depth_weapon_difference) > .0001, "HDR plus depth post does not erase original weapon/arms")
	check(difference(with_bloom, depth_with) > .000001, "depth effects make an actual GPU difference in HDR scene")
	app.set_graphics_option("dof", false)
	app.set_graphics_option("ssao", false)
	app.set_graphics_option("bloom", false)
	var msaa_off: Image = await capture("11-hdr-msaa-off")
	app.set_graphics_option("msaa", 4)
	var msaa_on: Image = await capture("12-hdr-msaa-4x")
	check(root.msaa_3d == Viewport.MSAA_4X and hdr.scene_viewport.msaa_3d == root.msaa_3d, "actual HDR target inherits root MSAA4x")
	metrics.msaa_difference = difference(msaa_off, msaa_on)
	check(float(metrics.msaa_difference) > .000001, "MSAA changes real scene-edge pixels")
	root.size = Vector2i(800, 600)
	player.camera.fov = 77.0
	player.camera.near = .035
	player.camera.far = 180.0
	player.camera.h_offset = .02
	player.camera.v_offset = -.03
	player.head.rotation.x = -.05
	await settle()
	check_camera("resized/offset")
	var resized: Image = await capture("13-hdr-resized-800x600")
	check(resized.get_size() == Vector2i(800, 600) and hdr.scene_viewport.size == resized.get_size(), "HDR float scene and presentation follow actual viewport resize")
	player.weapon_root.hide()
	var resized_without: Image = await capture("14-hdr-resized-no-equipment")
	player.weapon_root.show()
	var resized_weapon: Image = await capture("15-hdr-resized-equipment")
	check(difference(resized_without, resized_weapon, .45) > .0001, "first-person equipment survives resize and changed projection")
	app.set_graphics_option("hdr", false)
	var restored: Image = await capture("16-main-hdr-disabled")
	check(not hdr.enabled and player.camera.current and not root.disable_3d and not hdr.presentation.visible, "disabling HDR restores original reference camera/framebuffer")
	check(difference(resized_weapon, restored) > .001, "HDR off restores visibly different LDR presentation")
	app.set_graphics_option("hdr", true)
	await capture("17-main-hdr-reenabled")
	check_camera("re-enabled")
	check(hdr.enabled and hdr.presentation.visible, "re-enabling HDR after resize remains functional")
	metrics.hdr_budget = hdr.get_stats()
	metrics.renderer = RenderingServer.get_video_adapter_name()
	metrics.engine = Engine.get_version_info().string
	metrics.readback_mode = "GPU range-encoded RGBA8; not CPU-format inference"
	await finish()

func check_camera(label: String) -> void:
	var source := player.camera
	var clone := hdr.scene_camera
	check(source.global_transform.is_equal_approx(clone.global_transform), label + " camera transforms match")
	check(source.projection == clone.projection and source.keep_aspect == clone.keep_aspect, label + " projection modes match")
	check(is_equal_approx(source.fov, clone.fov) and is_equal_approx(source.near, clone.near) and is_equal_approx(source.far, clone.far), label + " FOV/clips match")
	check(is_equal_approx(source.h_offset, clone.h_offset) and is_equal_approx(source.v_offset, clone.v_offset) and source.frustum_offset.is_equal_approx(clone.frustum_offset), label + " projection offsets match")
	check(source.cull_mask == clone.cull_mask and clone.cull_mask & (1 << 18) != 0, label + " first-person render layer19 is retained")
	check(source.environment == clone.environment and source.attributes == clone.attributes, label + " camera environment/attributes match")
	var reference_projection := source.get_camera_projection()
	var clone_projection := clone.get_camera_projection()
	var equal := true
	for column in range(4):
		equal = equal and reference_projection[column].is_equal_approx(clone_projection[column])
	check(equal, label + " actual projection matrices match")

func read_radiance() -> Color:
	var sample_uv := player.camera.unproject_position(fixture.global_position) / Vector2(hdr.scene_viewport.size)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(2, 2)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;render_mode unshaded;uniform sampler2D scene_texture:filter_nearest;uniform vec2 sample_uv;void fragment(){COLOR=vec4(texture(scene_texture,sample_uv).rgb/8.0,1.0);}"
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("scene_texture", hdr.scene_viewport.get_texture())
	material.set_shader_parameter("sample_uv", sample_uv)
	var rect := ColorRect.new()
	rect.size = Vector2(2, 2)
	rect.material = material
	viewport.add_child(rect)
	await settle()
	var pixel := viewport.get_texture().get_image().get_pixel(1, 1)
	viewport.queue_free()
	return Color(pixel.r * 8, pixel.g * 8, pixel.b * 8)

func settle() -> void:
	for frame in range(3):
		await process_frame
		await RenderingServer.frame_post_draw

func capture(name: String) -> Image:
	await settle()
	var image := root.get_texture().get_image()
	check(not image.is_empty() and image.save_png(output.path_join(name + ".png")) == OK, "save actual-main GPU preview " + name)
	return image

func difference(first: Image, second: Image, top: float = 0.0) -> float:
	var total := 0.0
	var count := 0
	for y in range(int(first.get_height() * top), first.get_height(), 3):
		for x in range(0, first.get_width(), 3):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			total += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			count += 3
	return total / maxf(1, count)

func readable_overlay_pixels(without_hud: Image, with_hud: Image) -> int:
	var count := 0
	for y in range(0, with_hud.get_height(), 2):
		for x in range(0, with_hud.get_width(), 2):
			var a := without_hud.get_pixel(x, y)
			var b := with_hud.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > .1 and minf(b.r, minf(b.g, b.b)) > .65:
				count += 1
	return count

func restore_settings() -> void:
	if settings_existed:
		var file := FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		file.store_buffer(settings_before)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP))

func finish() -> void:
	if is_instance_valid(app):
		if app.has_method("stop_audio"):
			app.stop_audio()
		app.queue_free()
		for frame in range(6):
			await process_frame
	await create_timer(.2).timeout
	restore_settings()
	check(FileAccess.get_file_as_bytes("user://settings.cfg") == settings_before if settings_existed else not FileAccess.file_exists("user://settings.cfg"), "original preferences restored exactly")
	AudioServer.set_bus_mute(0, master_was_muted)
	metrics.checks = checks
	metrics.failures = failures
	FileAccess.open(output.path_join("metrics.json"), FileAccess.WRITE).store_string(JSON.stringify(metrics, "\t"))
	print("HDR_LAB_GPU: %d checks, %d failures; %s" % [checks, failures, output])
	print(JSON.stringify(metrics))
	quit(1 if failures else 0)
