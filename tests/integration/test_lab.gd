extends SceneTree
## Exercise the actual scene, menu callbacks, input, ray hits and world/session flow.
## godot --headless --path game --script ../tests/integration/test_lab.gd

const MAIN_SCENE = preload("res://scenes/main.tscn")
var assertions: int = 0
var failures: int = 0
var app: Node3D
var session: LocalSession
var player: BlockfieldPlayer
var world: VoxelWorld
var hud: LabHUD
var _settings_existed: bool = false
var _settings_before: PackedByteArray = PackedByteArray()


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("LAB INTEGRATION: " + message)


func _run() -> void:
	seed(2468)
	_settings_existed = FileAccess.file_exists("user://settings.cfg")
	if _settings_existed: _settings_before = FileAccess.get_file_as_bytes("user://settings.cfg")
	app = MAIN_SCENE.instantiate()
	root.add_child(app)
	app.set_locale("ru")
	session = app.get_node("LocalSession")
	player = app.get_node("Player")
	world = app.get_node("VoxelWorld")
	hud = app.get_node("HUD")
	await frames(3)
	check(session.targets.size() == 6, "startup creates exactly six test soldiers")
	check(hud.is_menu_open() and not player.controls_enabled, "startup menu disables gameplay")
	check(player.camera_mode == BlockfieldPlayer.CameraMode.INTRO, "before joining the local lab camera is in intro state")
	var startup_tool := session.current_tool
	action("tool_spade",true)
	action("tool_spade",false)
	check(session.current_tool == startup_tool, "menu blocks gameplay tool shortcuts")
	for scenario in ["test_menu_and_reset","test_movement_and_shooting","test_movement_input_and_camera","test_building_and_spade","test_grenade_pipeline"]:
		var completed: Variant = await call(scenario)
		check(completed == true, "scenario reaches completion: " + scenario)
	release_actions()
	player.stop_audio()
	if app.has_method("stop_audio"): app.stop_audio()
	# Drain the real audio server and deferred deletions before exiting the
	# process; an immediate quit can retain in-flight Vorbis playback refs.
	await frames(3)
	var scene_reference: WeakRef = weakref(app)
	app.queue_free()
	for cleanup_frame in range(12):
		await frames(1)
		if cleanup_frame >= 2 and scene_reference.get_ref() == null:
			break
	check(scene_reference.get_ref() == null, "the lab scene is fully freed before test exit")
	if _settings_existed:
		var settings_file := FileAccess.open("user://settings.cfg",FileAccess.WRITE)
		settings_file.store_buffer(_settings_before)
		settings_file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	print("LAB INTEGRATION: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func frames(count: int) -> void:
	for frame in range(count):
		await physics_frame
		await process_frame


func nodes_below(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child)
		result.append_array(nodes_below(child))
	return result


func menu_button(text: String) -> Button:
	for node in nodes_below(hud):
		if node is Button and node.text == text:
			return node
	return null


func menu_option(first_text: String) -> OptionButton:
	for node in nodes_below(hud):
		if node is OptionButton and node.item_count > 0 and node.get_item_text(0) == first_text:
			return node
	return null


func press_menu(text: String) -> void:
	var button := menu_button(text)
	check(button != null, "menu exposes control: " + text)
	if button != null:
		button.pressed.emit()


func action(name: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func release_actions() -> void:
	for name in ["forward", "back", "left", "right", "jump", "crouch", "sprint", "primary", "secondary"]:
		action(name, false)


func grenades_in_scene() -> Array[LabGrenade]:
	var result: Array[LabGrenade] = []
	for node in app.get_children():
		if node is LabGrenade and not node.is_queued_for_deletion():
			result.append(node)
	return result


func aim_at(point: Vector3) -> void:
	player.look_at(Vector3(point.x, player.global_position.y, point.z), Vector3.UP)
	player.head.rotation.x = atan2(point.y - player.camera.global_position.y,
		Vector2(point.x - player.global_position.x, point.z - player.global_position.z).length())
	player.camera.rotation = Vector3.ZERO


func test_menu_and_reset() -> bool:
	for entry in [["Винтовка", 0], ["Пистолет-пулемёт", 1], ["Дробовик", 2]]:
		press_menu(entry[0])
		check(session.current_weapon == int(entry[1]) and session.current_tool == 2,
			"weapon button selects firearm and gun tool")
	for entry in [["Лопата · 1", 0], ["Блоки · 2", 1], ["Оружие · 3", 2], ["Граната · 4", 3]]:
		press_menu(entry[0])
		check(session.current_tool == int(entry[1]), "tool button selects original tool index")
	var profile := menu_option("Ace of Spades 0.75")
	check(profile != null, "profile selector is present")
	if profile != null:
		profile.item_selected.emit(1)
		check(session.profile_version == "0.76" and session.magazine == 8,
			"0.76 menu selection updates shotgun profile")
		profile.item_selected.emit(0)
	for entry in [["Синяя команда", 0], ["Зелёная команда", 1], ["Наблюдатель", 2]]:
		press_menu(entry[0])
		check(session.team == int(entry[1]), "team button selects original appearance/spectator")
	press_menu("Синяя команда")
	var poses := menu_option("Стоя")
	check(poses != null, "test lab exposes soldier pose selector")
	if poses != null:
		poses.item_selected.emit(1)
		check(str(session.targets[0].state) == "crouching", "pose menu updates authoritative target state")
		poses.item_selected.emit(0)
		check(bool(session.targets[2].alive), "standing pose revives a corpse display target")
	press_menu("Сбросить испытательный полигон")
	await frames(2)
	press_menu("Сбросить испытательный полигон")
	await frames(2)
	check(session.targets.size() == 6, "reset does not retain invisible target authorities")
	var soldier_count := 0
	for node in app.get_children():
		if node is LabSoldier: soldier_count += 1
	check(soldier_count == 6, "reset does not duplicate rendered soldiers")
	press_menu("ВОЙТИ НА ПОЛИГОН  →")
	check(not hud.is_menu_open() and player.controls_enabled, "enter button enables gameplay without a server")
	await frames(3)
	return true


func test_movement_and_shooting() -> bool:
	session.unlimited_ammo = false
	session.select_weapon(0)
	session.select_team(0)
	await frames(50)
	check(player.is_on_floor(), "player lands on generated voxel collision")
	var before := player.global_position
	action("forward", true)
	await frames(30)
	action("forward", false)
	check(player.global_position.distance_to(before) > 1.0, "W input moves player through the real controller")
	await frames(30)
	var target: Dictionary = session.targets[0]
	var id := int(target.id)
	session.set_target_state(id, "standing", 0, 2)
	var target_point: Vector3 = target.position
	aim_at(target_point + Vector3.UP * 1.6)
	action("secondary", true)
	await frames(3)
	var old_magazine := session.magazine
	action("primary", true)
	await frames(2)
	action("primary", false)
	action("secondary", false)
	check(session.magazine == old_magazine - 1, "real trigger consumes one rifle round")
	check(int(session.get_target(id).health) < 100 and session.hits_landed > 0,
		"real camera ray and soldier hitzone route damage to local authority")
	var view_count := 0
	for node in nodes_below(player.camera):
		if node is WeaponView: view_count += 1
	check(view_count == 1, "all selections share one integrated original WeaponView")
	return true


func wheel(button_index: int) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func test_movement_input_and_camera() -> bool:
	release_actions()
	player.respawn_at(Vector3(48.5,4.01,70.5))
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	session.select_weapon(0)
	player.hold_aim_down_sight = false
	await frames(8)
	action("secondary",true)
	await frames(2)
	action("secondary",false)
	await frames(10)
	check(player.aiming and is_equal_approx(player.get_aim_zoom(),2.4), "toggle ADS stays active after release and uses original rifle zoom")
	var before_yaw := player.rotation.y
	player.ads_sensitivity = 1.0
	player.apply_mouse_motion(Vector2(10,0))
	var full_ads_turn := absf(player.rotation.y - before_yaw)
	player.rotation.y = before_yaw
	player.ads_sensitivity = 0.5
	player.apply_mouse_motion(Vector2(10,0))
	check(is_equal_approx(absf(player.rotation.y - before_yaw),full_ads_turn * 0.5), "ADS sensitivity setting scales the captured-pointer adapter")
	player.ads_sensitivity = 1.0
	player.rotation.y = before_yaw
	action("secondary",true)
	await frames(2)
	action("secondary",false)
	await frames(22)
	check(not player.aiming and is_equal_approx(player.get_aim_zoom(),1.0), "second ADS click returns camera to normal zoom")
	player.hold_aim_down_sight = true
	action("secondary",true)
	await frames(10)
	check(player.aiming, "hold ADS activates while alternate trigger is down")
	action("secondary",false)
	await frames(22)
	check(not player.aiming, "hold ADS ends when alternate trigger is released")
	player.hold_aim_down_sight = false
	# Headless Godot cannot capture a pointer. Exercise the public mouse-input
	# adapter shared by the captured-pointer event path instead.
	player.invert_mouse = false
	player.mouse_exponent = 1.0
	player.head.rotation.x = 0.0
	player.apply_mouse_motion(Vector2(0,10))
	var normal_pitch := player.head.rotation.x
	player.head.rotation.x = 0.0
	player.invert_mouse = true
	player.apply_mouse_motion(Vector2(0,10))
	check(normal_pitch < 0.0 and player.head.rotation.x > 0.0, "mouse inversion reverses pitch without changing yaw")
	player.invert_mouse = false
	player.head.rotation.x = 0.0
	player.mouse_exponent = 2.0
	player.apply_mouse_motion(Vector2(0,10))
	check(absf(player.head.rotation.x) < absf(normal_pitch), "mouse exponent gives fine motion lower sensitivity")
	player.mouse_exponent = NAN
	player.apply_mouse_motion(Vector2.ZERO)
	check(player.mouse_exponent == 1.0 and is_finite(player.head.rotation.x), "invalid mouse exponent recovers safely")
	player.head.rotation.x = 0.0
	session.select_tool(0)
	session.blocks = 0
	session.grenades = 0
	wheel(MOUSE_BUTTON_WHEEL_UP)
	check(session.current_tool == 2, "wheel skips depleted blocks and selects next available tool")
	player.select_last_tool()
	check(session.current_tool == 0, "last tool restores the previous selected tool")
	player.wheel_tool_direction = 0
	wheel(MOUSE_BUTTON_WHEEL_UP)
	check(session.current_tool == 0, "disabled wheel switching leaves selection unchanged")
	player.wheel_tool_direction = 1
	session.select_weapon(0)
	session.magazine = 0
	session.reserve = 0
	var dry_events: Array[int] = [0]
	var dry_callback := func(): dry_events[0] += 1
	player.dry_fired.connect(dry_callback)
	action("primary",true)
	await frames(20)
	check(dry_events[0] == 1, "empty held trigger plays one dryfire rather than repeating every frame")
	action("primary",false)
	await frames(2)
	action("primary",true)
	await frames(2)
	action("primary",false)
	check(dry_events[0] == 2 and session.magazine == 0, "new empty trigger press clicks again without consuming ammo")
	player.dry_fired.disconnect(dry_callback)
	session.select_weapon(0)
	session.restock()
	action("crouch",true)
	await frames(5)
	world.set_block(Vector3i(48,6,70),VoxelWorld.pack_color(Color.GRAY))
	world.rebuild_now()
	await frames(2)
	action("crouch",false)
	await frames(5)
	check(player.crouching and not player.can_stand(), "ceiling prevents uncrouch and keeps the short collision body")
	player.respawn_at(Vector3(51.5,4.01,70.5))
	await frames(5)
	check(not player.crouching and player.can_stand(), "leaving low ceiling permits standing")
	player.respawn_at(Vector3(51.5,10.0,70.5))
	await frames(2)
	var airborne_feet := player.global_position.y
	var airborne_eye := player.get_aim_origin().y
	action("crouch",true)
	await frames(1)
	# Frames can contain several physics catch-up ticks when rebuilding the
	# voxel world. Compare the geometric change independently of gravity.
	var feet_change := player.global_position.y - airborne_feet
	var eye_change := player.get_aim_origin().y - airborne_eye
	check(player.crouching and feet_change > 0.0 \
		and is_equal_approx(feet_change - eye_change,0.9), "airborne crouch raises feet rather than lowering the eye")
	var crouched_feet := player.global_position.y
	action("crouch",false)
	await frames(1)
	check(not player.crouching and player.global_position.y < crouched_feet - 0.8, "airborne uncrouch lowers feet into clear space")
	world.set_block(Vector3i(48,6,70),0)
	world.rebuild_now()
	player.respawn_at(Vector3(0.5,20.01,70.5))
	player.rotation = Vector3.ZERO
	action("left",true)
	await frames(30)
	action("left",false)
	check(player.global_position.x >= 0.4499 and player.global_position.x <= 0.6, "active player cannot cross horizontal map boundary")
	player.respawn_at(Vector3(62.5,4.01,78.5))
	await frames(6)
	action("forward",true)
	await frames(30)
	var dry_speed := Vector2(player.velocity.x,player.velocity.z).length()
	action("forward",false)
	for x in range(59,66):
		for z in range(73,81):
			for y in range(1,4): world.set_block(Vector3i(x,y,z),0)
	world.rebuild_now()
	player.respawn_at(Vector3(62.5,1.01,78.5))
	await frames(6)
	action("forward",true)
	await frames(30)
	var wet_speed := Vector2(player.velocity.x,player.velocity.z).length()
	action("forward",false)
	check(player.wading and wet_speed < dry_speed * 0.85 and wet_speed > 0.0, "water friction slows actual grounded movement relative to dry terrain")
	# Restore the test scene before verifying camera/world collision.
	app.reset_lab()
	await frames(4)
	player.respawn_at(Vector3(48.5,4.01,70.5))
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	for y in range(4,8): world.set_block(Vector3i(48,y,72),VoxelWorld.pack_color(Color.GRAY))
	world.rebuild_now()
	player.third_person = true
	await frames(5)
	check(player.camera_mode == BlockfieldPlayer.CameraMode.THIRD_PERSON and player.camera.global_position.z < 72.0, "third-person camera shortens before a voxel wall")
	check(player.get_aim_origin().distance_to(player.head.global_position) < 0.001 \
		and player.get_aim_origin().distance_to(player.camera.global_position) > 0.5, "third-person tools keep authoritative eye origin independent of orbit position")
	player.third_person = false
	session.invulnerable = false
	session.damage_player(1000.0)
	session.invulnerable = true
	await frames(2)
	check(player.camera_mode == BlockfieldPlayer.CameraMode.DEATH and not player.weapon_root.visible, "death enters corpse orbit and hides first-person tool")
	check(not player.follow_target(int(session.targets[0].id)), "death camera enforces original initial 1.3-second follow delay")
	await frames(85)
	var same_team: Dictionary = session.targets[0]
	check(player.follow_target(int(same_team.id)), "dead player can follow a living same-team target after delay")
	session.select_team(2)
	player.stop_following()
	await frames(2)
	check(player.camera_mode == BlockfieldPlayer.CameraMode.FREE, "spectator without follow enters free camera")
	var stock_before := session.magazine
	action("primary",true)
	action("primary",false)
	await frames(2)
	check(player.followed_target_id >= 0 and session.magazine == stock_before, "spectator attack follows a target without shooting")
	action("jump",true)
	action("jump",false)
	await frames(2)
	check(player.camera_mode == BlockfieldPlayer.CameraMode.FOLLOW_FIRST_PERSON, "spectator jump switches living follow target to first person")
	action("reload",true)
	action("reload",false)
	await frames(2)
	var free_before := player.camera.global_position
	action("forward",true)
	await frames(30)
	action("forward",false)
	check(player.camera_mode == BlockfieldPlayer.CameraMode.FREE and player.camera.global_position.distance_to(free_before) > 0.25, "spectator reload unfollows and W accelerates the real free camera")
	# Build a wall directly across the free camera's future path. The camera
	# should collide even though the spectator body is not a physics actor.
	player.apply_mouse_motion(Vector2(player.camera.global_rotation.y / 0.003,player.camera.global_rotation.x / 0.003))
	await frames(2)
	var wall_z := floori(player.camera.global_position.z) - 2
	var camera_x := floori(player.camera.global_position.x)
	var camera_y := floori(player.camera.global_position.y)
	for x in range(camera_x - 3,camera_x + 4):
		for y in range(maxi(1,camera_y - 3),camera_y + 4):
			world.set_block(Vector3i(x,y,wall_z),VoxelWorld.pack_color(Color.GRAY))
	world.rebuild_now()
	action("forward",true)
	await frames(60)
	action("forward",false)
	check(player.camera.global_position.z >= float(wall_z + 1) - 0.001, "free camera cannot pass through a voxel wall")
	session.select_team(0)
	await frames(3)
	check(player.camera_mode == BlockfieldPlayer.CameraMode.FIRST_PERSON and player.followed_target_id == -1, "active-team respawn restores local first-person camera")
	app.reset_lab()
	await frames(3)
	return true


func test_building_and_spade() -> bool:
	release_actions()
	player.respawn_at(Vector3(48.5, 4.01, 70.5))
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	await frames(5)
	for height in [4, 5, 6]:
		world.set_block(Vector3i(48, height, 68), VoxelWorld.pack_color(Color.GRAY))
	world.set_block(Vector3i(48, 5, 69), 0)
	world.rebuild_now()
	session.restock()
	session.select_tool(1)
	var blocks_before := session.blocks
	aim_at(Vector3(48.5, 5.5, 68.5))
	var preview := player.get_build_preview()
	check(bool(preview.valid) and preview.cells == [Vector3i(48,5,69)], "single-block preview reports the same valid adjacent placement")
	action("primary", true)
	await frames(2)
	action("primary", false)
	check(world.get_block(Vector3i(48, 5, 69)) != 0 and session.blocks == blocks_before - 1,
		"block tool places adjacent cube and consumes one resource")
	await frames(35)
	session.select_tool(0)
	aim_at(Vector3(48.5, 5.5, 69.5))
	action("primary", true)
	await frames(2)
	check(world.get_block(Vector3i(48, 5, 69)) != 0, "first 55-damage spade hit leaves block standing")
	await frames(15)
	action("primary", false)
	check(world.get_block(Vector3i(48, 5, 69)) == 0 and session.blocks == blocks_before,
		"second spade hit destroys cube and restores a block to stock")
	await frames(15)
	aim_at(Vector3(48.5, 5.5, 68.5))
	action("secondary", true)
	await frames(2)
	check(world.get_block(Vector3i(48, 5, 68)) != 0, "secondary spade waits before first dig")
	await frames(65)
	action("secondary", false)
	check(world.get_block(Vector3i(48, 4, 68)) == 0 and world.get_block(Vector3i(48, 5, 68)) == 0 \
		and world.get_block(Vector3i(48, 6, 68)) == 0, "secondary dig removes three vertical cubes")
	# Drive a drag-line through the normal secondary press/release route.
	for x in [47, 50]:
		for height in [4, 5]:
			world.set_block(Vector3i(x, height, 68), VoxelWorld.pack_color(Color.GRAY))
	for x in range(47, 51):
		world.set_block(Vector3i(x, 5, 69), 0)
	world.rebuild_now()
	player.respawn_at(Vector3(48.5, 4.01, 71.0))
	await frames(5)
	session.select_tool(1)
	blocks_before = session.blocks
	aim_at(Vector3(47.5, 5.5, 68.5))
	action("secondary", true)
	await frames(2)
	aim_at(Vector3(50.5, 5.5, 68.5))
	preview = player.get_build_preview()
	check(bool(preview.valid) and preview.cells.size() == 4, "drag-line preview exposes all four cells before committing resources")
	action("secondary", false)
	await frames(2)
	var placed := 0
	for x in range(47, 51):
		if world.get_block(Vector3i(x, 5, 69)) != 0: placed += 1
	check(placed == 4 and session.blocks == blocks_before - 4,
		"line release creates the entire line with one atomic stock deduction")
	return true


func test_grenade_pipeline() -> bool:
	release_actions()
	session.select_tool(3)
	session.grenade_cooldown = 0.0
	session.restock()
	var starting_stock := session.grenades
	action("primary", true)
	await frames(15)
	action("primary", false)
	check(grenades_in_scene().size() == 1 and session.grenades == starting_stock - 1,
		"cooked release spawns exactly one projectile through session event")
	# Detonate beside an exposed target to verify blast damage, not merely visuals.
	if not grenades_in_scene().is_empty():
		var grenade := grenades_in_scene()[0]
		var target: Dictionary = session.targets[0]
		session.set_target_state(int(target.id), "standing")
		grenade.global_position = Vector3(target.position) + Vector3.UP * 1.2
		grenade.velocity = Vector3.ZERO
		session.set_grenade_position(grenade.grenade_id, grenade.global_position)
		session.update(3.1)
		check(int(target.health) < 100, "authoritative explosion applies nonzero damage to uncovered target")
	await frames(2)
	check(grenades_in_scene().is_empty(), "detonated projectile is removed")
	session.grenade_cooldown = 0.0
	starting_stock = session.grenades
	action("primary", true)
	action("primary", false)
	check(grenades_in_scene().is_empty(), "quick release waits until pin is pulled")
	session.update(0.16)
	check(grenades_in_scene().size() == 1 and session.grenades == starting_stock - 1,
		"quick release eventually spawns one projectile rather than losing grenade")
	session.update(3.1)
	await frames(2)
	session.restock()
	session.grenade_cooldown = 0.0
	starting_stock = session.grenades
	action("primary", true)
	await frames(2)
	session.update(2.91)
	check(grenades_in_scene().size() == 1 and session.grenades == starting_stock - 1,
		"overcooked grenade force-spawns once without a release event")
	action("primary", false)
	check(grenades_in_scene().size() == 1, "late physical release does not spawn a second grenade")
	session.update(0.2)
	await frames(2)
	session.restock()
	session.grenade_cooldown = 0.0
	action("primary", true)
	await frames(12)
	session.invulnerable = false
	session.damage_player(1000)
	session.invulnerable = true
	check(grenades_in_scene().size() == 1, "death while cooking creates one dropped projectile")
	action("primary", false)
	check(grenades_in_scene().size() == 1, "release after death does not duplicate dropped projectile")
	session.update(3.1)
	await frames(2)
	return true
