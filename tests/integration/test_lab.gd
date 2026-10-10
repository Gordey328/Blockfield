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


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("LAB INTEGRATION: " + message)


func _run() -> void:
	seed(2468)
	app = MAIN_SCENE.instantiate()
	root.add_child(app)
	session = app.get_node("LocalSession")
	player = app.get_node("Player")
	world = app.get_node("VoxelWorld")
	hud = app.get_node("HUD")
	await frames(3)
	check(session.targets.size() == 6, "startup creates exactly six test soldiers")
	check(hud.is_menu_open() and not player.controls_enabled, "startup menu disables gameplay")
	await test_menu_and_reset()
	await test_movement_and_shooting()
	await test_building_and_spade()
	await test_grenade_pipeline()
	release_actions()
	player.stop_audio()
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


func test_menu_and_reset() -> void:
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


func test_movement_and_shooting() -> void:
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


func test_building_and_spade() -> void:
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
	action("secondary", false)
	await frames(2)
	var placed := 0
	for x in range(47, 51):
		if world.get_block(Vector3i(x, 5, 69)) != 0: placed += 1
	check(placed == 4 and session.blocks == blocks_before - 4,
		"line release creates the entire line with one atomic stock deduction")


func test_grenade_pipeline() -> void:
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
