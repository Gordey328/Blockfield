extends SceneTree
## Independent acceptance cases from pinned Player.cpp/Weapon.cpp/World.cpp.
## Run: godot --headless --path game --script ../tests/gameplay/test_source_parity.gd --verbose

const MAIN_SCENE := preload("res://scenes/main.tscn")
var assertions := 0
var failures := 0
var app: Node3D
var player: BlockfieldPlayer
var session: LocalSession
var world: VoxelWorld
var _settings_existed := false
var _settings_before := PackedByteArray()

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("SOURCE PARITY: " + message)

func _run() -> void:
	for scenario in ["test_hit_volumes","test_recoil","test_sustained_cadence","test_selection_interrupts"]:
		check(call(scenario) == true, "pure source scenario reaches completion: " + scenario)
	_settings_existed = FileAccess.file_exists("user://settings.cfg")
	if _settings_existed: _settings_before = FileAccess.get_file_as_bytes("user://settings.cfg")
	app = MAIN_SCENE.instantiate()
	root.add_child(app)
	app.set_locale("ru")
	player = app.get_node("Player")
	session = app.get_node("LocalSession")
	session.unlimited_ammo = false
	session.invulnerable = false
	world = app.get_node("VoxelWorld")
	await frames(3)
	app.set_process(false)
	player.set_physics_process(false)
	app.hud.set_menu_visible(false)
	for scenario in ["test_jump_order", "test_movement_friction", "test_build_contracts", "test_persistent_block_damage", "test_offline_grenade_input", "test_tool_depletion", "test_ray_occlusion", "test_melee_contract", "test_match_reset"]:
		var completed: Variant = await call(scenario)
		check(completed == true, "scenario reaches completion: " + scenario)
	release_actions()
	app.stop_audio()
	await frames(3)
	var scene_ref: WeakRef = weakref(app)
	app.queue_free()
	for cleanup_frame in 12:
		await frames(1)
		if cleanup_frame >= 2 and scene_ref.get_ref() == null: break
	check(scene_ref.get_ref() == null, "scene freed before exit")
	var audio_deadline:=Time.get_ticks_msec()+200
	while Time.get_ticks_msec()<audio_deadline:
		OS.delay_msec(1)
		await process_frame
	if _settings_existed:
		var file := FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		file.store_buffer(_settings_before)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	print("SOURCE PARITY: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)

func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func release_actions() -> void:
	for action in InputMap.get_actions(): Input.action_release(action)
	Input.flush_buffered_events()

func volume_bounds(volume: Dictionary) -> AABB:
	var box: AABB = volume.box
	var transform: Transform3D = volume.transform
	var result := AABB(transform * box.position, Vector3.ZERO)
	for corner in 8: result = result.expand(transform * box.get_endpoint(corner))
	return result

func test_hit_volumes() -> bool:
	# Player.cpp:1316–1385, converted source Z-down to Godot Y-up.
	var standing_centers: Array[Vector3] = [Vector3(0,2.35,0), Vector3(0,1.6,0), Vector3(-.25,.55,0), Vector3(.25,.55,0), Vector3(0,1.6,0)]
	var standing_sizes: Array[Vector3] = [Vector3(.6,.6,.6), Vector3(.8,.9,.3), Vector3(.3,1,.3), Vector3(.3,1,.3), Vector3(1.2,.9,.3)]
	var crouch_centers: Array[Vector3] = [Vector3(0,1.45,0), Vector3(0,.9,.25), Vector3(-.25,.25,0), Vector3(.25,.25,0), Vector3(0,.9,0)]
	var crouch_sizes: Array[Vector3] = [Vector3(.6,.6,.6), Vector3(.8,.6,.8), Vector3(.3,.5,.3), Vector3(.3,.5,.3), Vector3(1.2,.6,.3)]
	for crouch in [false,true]:
		var volumes := LabHitVolumes.volumes(crouch)
		check(volumes.size() == 5, "native volumes include two distinct legs and one broad arms volume")
		for index in 5:
			var bounds := volume_bounds(volumes[index])
			check(bounds.get_center().is_equal_approx(crouch_centers[index] if crouch else standing_centers[index]), "source hit-volume center, crouch=%s index=%d" % [crouch,index])
			check(bounds.size.is_equal_approx(crouch_sizes[index] if crouch else standing_sizes[index]), "source hit-volume dimensions, crouch=%s index=%d" % [crouch,index])
		var pitched := volume_bounds(LabHitVolumes.volumes(crouch, PI/2.0)[0])
		check(pitched.get_center().is_equal_approx(Vector3(0,1.15 if crouch else 2.05,.3)), "head pitches around original offset pivot")
	var cases := [
		[Vector3(0,2.35,-5),false,"head"], [Vector3(0,1.6,-5),false,"torso"],
		[Vector3(.5,1.6,-5),false,"arms"], [Vector3(-.25,.5,-5),false,"legs"],
		[Vector3(.25,.5,-5),false,"legs"], [Vector3(0,.5,-5),false,""],
		[Vector3(-.25,.25,-5),true,"legs"], [Vector3(0,.25,-5),true,""],
		[Vector3(-.25,.55,-5),true,""], [Vector3(0,.9,-5),true,"torso"],
		[Vector3(.5,.9,-5),true,"arms"], [Vector3(0,1.45,-5),true,"head"]
	]
	for item in cases:
		var hit := LabHitVolumes.cast_ray(item[0],Vector3.BACK,Vector3.ZERO,0.0,item[1])
		check(str(hit.part) == item[2] and bool(hit.hit) == (item[2] != ""), "actual ray respects native gap/pose/part: " + str(item))
	var yaw_hit := LabHitVolumes.cast_ray(Vector3(5,.9,0),Vector3.LEFT,Vector3.ZERO,PI/2.0,true)
	check(yaw_hit.hit and yaw_hit.part == "torso", "yaw rotates exact source volumes")
	var tie := LabHitVolumes.cast_ray(Vector3(0,0,0),Vector3.UP,Vector3.ZERO,0.0,false)
	check(tie.hit and tie.part == "head", "firearm horizontal-distance ties retain source head-first order")
	return true

func test_recoil() -> bool:
	# Player.cpp:759–784: normalized vector addition, deterministic triangular wave.
	var recoil := Vector3(.025,.05,0)
	for phase in [0.0,.25,.5,.75,1.0]:
		var wave: float = [-1.0,0.0,1.0,0.0,-1.0][int(round(phase*4.0))]
		for crouch in [false,true]:
			var scale := .5 if crouch else 1.0
			var expected := Vector3(recoil.x*wave*scale,recoil.y*scale,-1).normalized()
			var actual := BlockfieldPlayer.source_recoil(Vector3.FORWARD,Vector3.RIGHT,Vector3.UP,recoil,phase/.9788,crouch)
			check(actual.is_equal_approx(expected), "source recoil at triangular phase %.2f crouch=%s" % [phase,crouch])
	var near_vertical := Vector3(.01,sqrt(1.0-.0001),0)
	var result := BlockfieldPlayer.source_recoil(near_vertical,Vector3.FORWARD,Vector3(-near_vertical.y,near_vertical.x,0),Vector3(0,.5,0),0,false)
	check(result.is_equal_approx(near_vertical), "upward recoil clamps when horizontal projection falls below .03")
	seed(337)
	var expected_random := randf()
	seed(337)
	BlockfieldPlayer.source_recoil(Vector3.FORWARD,Vector3.RIGHT,Vector3.UP,recoil,.7,false)
	check(is_equal_approx(randf(),expected_random), "deterministic recoil consumes no shot-spread random draw")
	return true

func test_sustained_cadence() -> bool:
	# Weapon.cpp:86–111. Independent absolute-deadline oracle, no cooldown reset.
	for profile in ["0.75","0.76"]:
		for weapon in 3:
			for jitter in [false,true]:
				var state := LocalSession.new()
				state.set_profile_version(profile)
				state.select_weapon(weapon)
				state.unlimited_ammo = true
				state.set_trigger_held(true)
				state.fire()
				var delay: float = state.get_weapon_info().delay
				var elapsed := 0.0
				var deadline := delay
				var expected := 1
				var maximum_lateness := 0.0
				for tick in 601:
					var delta: float = [.011,.023,.016][tick%3] if jitter else 1.0/60.0
					elapsed += delta
					if elapsed >= deadline:
						expected += 1
						deadline += delay
					state.update(delta)
					if state.fire(): maximum_lateness = maxf(maximum_lateness,elapsed-float(state.shots_fired-1)*delay)
				check(absi(state.shots_fired-expected) <= 1, "sustained source cadence profile=%s weapon=%d jitter=%s expected=%d actual=%d" % [profile,weapon,jitter,expected,state.shots_fired])
				check(maximum_lateness <= (.023 if jitter else 1.0/60.0)+.000001, "automatic deadline drift remains bounded by one simulation tick")
				state.set_trigger_held(false)
				state.update(1.8)
				state.set_trigger_held(true)
				check(state.fire() and is_equal_approx(state.fire_cooldown,delay), "new trigger after idle does not inherit past deadline debt")
				state.free()
	return true

func test_selection_interrupts() -> bool:
	var state := LocalSession.new()
	state.magazine = 4
	state.reload_weapon()
	state.update(1.0)
	state.select_tool(LocalSession.Tool.SPADE)
	state.update(2.0)
	check(not state.is_reloading and state.magazine == 4, "SetTool aborts magazine reload without consuming reserve")
	state.select_weapon(LocalSession.Weapon.SHOTGUN)
	state.magazine = 1
	state.reload_weapon()
	state.select_tool(LocalSession.Tool.BLOCK)
	state.update(1.0)
	check(not state.is_reloading and state.magazine == 1, "SetTool aborts per-shell reload")
	state.select_tool(LocalSession.Tool.GRENADE)
	state.begin_grenade_cook()
	state.update(.6)
	state.select_tool(LocalSession.Tool.SPADE)
	check(not state.is_cooking_grenade and state.live_grenades.is_empty() and state.grenades == 3, "SetTool cancels held grenade without throw or stock loss")
	state.grenade_cooldown = 0
	state.select_tool(LocalSession.Tool.GRENADE)
	state.begin_grenade_cook()
	state.update(.05)
	state.release_grenade()
	state.select_tool(LocalSession.Tool.SPADE)
	state.update(.2)
	check(state.live_grenades.is_empty() and state.grenades == 3, "SetTool also cancels quick-release waiting for .15s pin pull")
	state.select_tool(LocalSession.Tool.GRENADE)
	state.begin_grenade_cook()
	state.update(.6)
	state.select_weapon(LocalSession.Weapon.SMG)
	state.update(3.1)
	check(not state.is_cooking_grenade and state.live_grenades.is_empty() and state.grenades == 3,
		"lab weapon selection obeys SetTool cancellation instead of invisibly force-throwing a grenade")
	state.select_tool(LocalSession.Tool.GRENADE)
	state.begin_grenade_cook()
	state.update(.05)
	state.release_grenade()
	state.set_profile_version("0.76")
	state.update(.2)
	check(not state.is_cooking_grenade and state.live_grenades.is_empty() and state.grenades == 3,
		"profile selection cancels a quick-release pending pin pull")
	state.set_trigger_held(true)
	state.fire()
	state.update(1.0)
	state.select_weapon(state.current_weapon)
	state.update(2.0)
	check(is_zero_approx(state.fire_cooldown), "same-weapon lab selection releases the previous held trigger deadline")
	state.set_profile_version("0.75")
	state.select_weapon(LocalSession.Weapon.SHOTGUN)
	state.magazine = 0
	state.reload_weapon()
	state.set_trigger_held(true)
	state.fire()
	state.update(.6)
	check(not state.is_reloading and state.magazine == 0 and state.reserve == 48, "empty held shotgun trigger aborts shell reload before consuming reserve")
	state.free()
	return true

func test_jump_order() -> bool:
	release_actions()
	app.reset_lab()
	player.set_physics_process(true)
	for tick in 60:
		await frames(1)
		if player.is_grounded(): break
	check(player.is_grounded(), "jump fixture starts grounded")
	player.set_physics_process(false)
	Input.action_press("jump")
	player._physics_process(1.0/60.0)
	var expected := (.36-1.0/60.0)/(1.0+1.0/60.0)*32.0
	check(is_equal_approx(player.velocity.y,expected), "native jump is assigned before this frame's gravity/friction")
	release_actions()
	return true

func test_movement_friction() -> bool:
	# Player.cpp:1120–1168, source velocity recurrence before 32× displacement.
	for variant in ["walk","sprint","crouch","sneak"]:
		release_actions()
		app.reset_lab()
		# Native destination probes retain the old position at contact. Spawn
		# above the surface and wait for stable contact instead of assuming a
		# Godot floor cache after three frames at an integer voxel face.
		player.respawn_at(Vector3(48.5,4.1,70.5))
		player.rotation = Vector3.ZERO
		player.head.rotation = Vector3.ZERO
		player.set_physics_process(true)
		var ground_ticks: int = 0
		for settle_tick in 60:
			await frames(1)
			ground_ticks = ground_ticks+1 if player.is_grounded() else 0
			if ground_ticks >= 2: break
		player.set_physics_process(false)
		check(player.is_grounded(), "ground-friction fixture is grounded: " + variant)
		Input.action_press("forward")
		if variant != "walk": Input.action_press(variant)
		var acceleration: float = {"walk":1.0,"sprint":1.3,"crouch":.3,"sneak":.5}[variant]
		var expected := 0.0
		for tick in 10:
			# Client_Update.cpp:395–399 suppresses sprint until the previous
			# horizontal native speed reaches .1; Shift starts at walking speed.
			var tick_acceleration := 1.0 if variant == "sprint" and expected < .1 else acceleration
			expected = (expected+tick_acceleration/60.0)/(1.0+4.0/60.0)
			player._physics_process(1.0/60.0)
			if variant == "sprint" and tick == 0:
				check(not player.sprinting, "held Shift cannot sprint from rest before the native .1 speed threshold")
		check(is_equal_approx(-player.velocity.z,expected*32.0), "actual grounded velocity follows source acceleration/friction: " + variant)
		if variant == "sprint": check(player.sprinting, "held Shift starts sprinting after walking reaches the native speed threshold")
	release_actions()
	player.respawn_at(Vector3(48.5,40,70.5))
	player.head.rotation = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player._physics_process(1.0/60.0) # Clear cached ground contact before air input.
	Input.action_press("forward")
	var air_expected := 0.0
	for tick in 10:
		air_expected = (air_expected+.1/60.0)/(1.0+1.0/60.0)
		player._physics_process(1.0/60.0)
	check(is_equal_approx(-player.velocity.z,air_expected*32.0), "actual airborne velocity follows source .1 acceleration and air friction")
	release_actions()
	return true

func test_build_contracts() -> bool:
	release_actions()
	app.reset_lab()
	player.set_physics_process(false)
	player.controls_enabled = true
	player.respawn_at(Vector3(48.5,12.1,70.5))
	check(not player._overlaps_player(Vector3i(48,11,70)) and not player._overlaps_player(Vector3i(48,15,70)), "placement overlap excludes space beneath feet and above eye")
	check(player._overlaps_player(Vector3i(48,12,70)) and player._overlaps_player(Vector3i(48,14,70)), "standing build overlap uses native eye-down box")
	player.crouching = true
	player.head.position.y = 1.35
	check(not player._overlaps_player(Vector3i(48,14,70)) and player._overlaps_player(Vector3i(48,13,70)), "crouching build overlap shortens to .85 blocks below eye")
	player.crouching = false
	player.head.position.y = 2.25
	session.select_tool(LocalSession.Tool.BLOCK)
	world.set_block(Vector3i(48,13,69),VoxelWorld.pack_color(Color.GRAY))
	player.head.look_at(Vector3(48.5,13.5,69.5),Vector3.UP)
	player._build_single()
	var pending := Vector3i(48,13,70)
	check(world.get_block(pending) == 0 and bool(player.get_build_preview().pending), "airborne self-overlap queues rather than immediately creates a block")
	player.global_position.x += 10
	player._physics_process(1.0/60.0)
	check(world.get_block(pending) == 0 and session.blocks == 50, "pending placement cannot build after player leaves three-block reach")
	player.global_position.x -= 10
	session.blocks = 0
	player._physics_process(1.0/60.0)
	session.restock()
	player.global_position.x += 1.5
	player._physics_process(1.0/60.0)
	check(world.get_block(pending) == 0, "stock depletion cancels pending placement permanently before later restock")
	# World::CubeLine fixture in source coordinates (20,20,43)->(8,9,54).
	var line := player._cube_line(Vector3i(20,20,20),Vector3i(8,9,9),4)
	var expected: Array[Vector3i] = [Vector3i(20,20,20),Vector3i(19,20,20),Vector3i(19,20,19),Vector3i(19,19,19)]
	check(line == expected, "cube-line odd crossing preserves original Z-down sign before Godot conversion")
	var reverse_expected: Array[Vector3i] = [Vector3i(8,9,9),Vector3i(9,9,9),Vector3i(9,10,9),Vector3i(9,10,10)]
	check(player._cube_line(Vector3i(8,9,9),Vector3i(20,20,20),4) == reverse_expected, "reversed cube-line preserves native odd crossing asymmetry")
	return true

func test_persistent_block_damage() -> bool:
	# User-approved gameplay policy: surviving damage has no automatic recovery.
	# Actual map edits/reset clear it; an unchanged RGB write is not replacement.
	release_actions()
	app.reset_lab()
	player.set_physics_process(false)
	player.controls_enabled = true
	var cell := Vector3i(40,4,40)
	var color := VoxelWorld.pack_color(Color8(255,128,65))
	world.set_block(cell,color)
	player._damage_block(cell,35)
	check(world.is_block_damaged(cell) and world.get_block(cell) == color,
		"first surviving hit marks visual damage without modifying canonical RGB")
	check(world.get_render_color(cell,color).is_equal_approx(Color8(127,64,32)),
		"damaged color uses the source byte mask and integer half on every RGB channel")
	session.update(10.01)
	player._physics_process(1.0/60.0)
	check(world.is_block_damaged(cell) and world.get_render_color(cell,color).is_equal_approx(Color8(127,64,32)),
		"actual controller retains the damaged appearance beyond the former ten-second deadline")
	world.set_block(cell,color)
	check(world.is_block_damaged(cell), "identical RGB write is a no-op and cannot heal a damaged voxel")
	session.update(3600.0)
	player._physics_process(1.0/60.0)
	check(world.is_block_damaged(cell) and world.get_block(cell) == color,
		"long idle retains damaged appearance and canonical RGB")
	player._damage_block(cell,70)
	check(world.get_block(cell) == 0, "later hit uses the previous65HP even after long idle and an unchanged-color write")
	check(not world.is_block_damaged(cell), "destruction clears the damaged-block appearance")
	session.update(3600.0)
	player._physics_process(1.0/60.0)
	check(world.get_block(cell) == 0 and not world.is_block_damaged(cell), "destroyed cells remain air after long idle")
	world.set_block(cell,color)
	check(not world.is_block_damaged(cell) and world.get_render_color(cell,color).is_equal_approx(Color8(255,128,65)),
		"actual recreation with the same RGB starts with healthy appearance")
	player._damage_block(cell,70)
	check(world.get_block(cell) != 0 and world.is_block_damaged(cell), "same-color recreated voxel starts with fresh100HP")
	player._damage_block(cell,35)
	check(world.get_block(cell) == 0, "damage accumulates independently on the recreated voxel")
	world.set_block(cell,color)
	player._damage_block(cell,35)
	world.set_block(cell,VoxelWorld.pack_color(Color.RED))
	check(not world.is_block_damaged(cell), "replacement clears the old voxel's damaged appearance")
	player._damage_block(cell,70)
	check(world.get_block(cell) != 0, "external cell replacement clears stale health from previous voxel")
	check(world.is_block_damaged(cell), "new replacement voxel gets its own damaged state")
	app.reset_lab()
	player.set_physics_process(false)
	var reset_cell := Vector3i(40,3,40)
	var reset_color: int = world.get_block(reset_cell)
	check(reset_color != 0, "explicit reset fixture selects a real baseline terrain voxel")
	player._damage_block(reset_cell,70)
	check(world.is_block_damaged(reset_cell), "baseline terrain is damaged before explicit map/session reset")
	app.reset_lab()
	player.set_physics_process(false)
	check(not world.is_block_damaged(reset_cell) and world.get_block(reset_cell) == reset_color,
		"explicit map/session reset restores the baseline healthy appearance")
	player._damage_block(reset_cell,70)
	check(world.get_block(reset_cell) != 0, "explicit map/session reset clears logical damage and starts with100HP")
	return true

func grenade_action(pressed: bool) -> void:
	# Exercise the actual controller event path and the corresponding held Input
	# state. The same InputEventAction is emitted by the mobile action bridge.
	if pressed:
		Input.action_press("primary")
	else:
		Input.action_release("primary")
	var event := InputEventAction.new()
	event.action = "primary"
	event.pressed = pressed
	player._unhandled_input(event)

func ready_offline_grenade() -> void:
	release_actions()
	session.respawn()
	session.select_tool(LocalSession.Tool.GRENADE)
	player.respawn_at(world.get_spawn_position())
	app.hud.set_menu_visible(false)
	for tick in 90:
		player._physics_process(1.0/60.0)
		if player.can_use_tool():
			break
	check(player.can_use_tool(), "offline grenade fixture raises the actual tool before input")

func test_offline_grenade_input() -> bool:
	# Source SetWeaponInput starts a cook on the effective press edge; Update's
	# automatic throw retains that held edge and omits manual-release cooldown.
	app.reset_lab()
	player.set_physics_process(false)
	session.unlimited_ammo = false
	var was_invulnerable: bool = session.invulnerable
	session.invulnerable = true
	var throws: Array[Dictionary] = []
	var observe_throw: Callable = func(data: Dictionary) -> void: throws.append(data)
	session.grenade_thrown.connect(observe_throw)
	ready_offline_grenade()
	grenade_action(true)
	check(session.is_cooking_grenade and session.grenades == 3, "actual primary press pulls one pin without consuming stock")
	session.update(2.9)
	player._physics_process(1.0/60.0)
	check(session.is_cooking_grenade and throws.is_empty(), "actual controller retains a held grenade at exactly2.9 seconds")
	session.update(0.001)
	player._physics_process(1.0/60.0)
	check(throws.size() == 1 and bool(throws[0].get("automatic",false)) and session.grenades == 2,
		"held primary creates exactly one automatic throw after the strict boundary")
	for tick in 240:
		session.update(1.0/60.0)
		player._physics_process(1.0/60.0)
	check(throws.size() == 1 and not session.is_cooking_grenade and session.grenades == 2,
		"continuing the same held press cannot cook or throw another grenade")
	ready_offline_grenade()
	grenade_action(true)
	session.update(2.901)
	player._physics_process(1.0/60.0)
	check(throws.size() == 2 and bool(throws[1].get("automatic",false)), "immediate-new-press fixture reaches an automatic throw")
	grenade_action(false)
	grenade_action(true)
	check(session.is_cooking_grenade and is_zero_approx(session.grenade_cooldown),
		"release plus immediate new press after automatic throw can pull the next pin")
	session.update(0.2)
	grenade_action(false)
	check(throws.size() == 3 and not bool(throws[2].get("automatic",true)) and is_equal_approx(session.grenade_cooldown,0.5),
		"actual manual release starts the original half-second cooldown")
	grenade_action(true)
	session.update(0.499)
	player._physics_process(1.0/60.0)
	check(not session.is_cooking_grenade and throws.size() == 3, "held new press is denied before the manual deadline")
	session.update(0.0011)
	player._physics_process(1.0/60.0)
	check(session.is_cooking_grenade, "press held during manual cooldown begins when its effective edge becomes available")
	grenade_action(false)
	session.update(0.149)
	player._physics_process(1.0/60.0)
	check(throws.size() == 3 and session.is_cooking_grenade, "quick controller release retains the grenade until pin minimum")
	session.update(0.0011)
	player._physics_process(1.0/60.0)
	check(throws.size() == 4 and not session.is_cooking_grenade and session.grenades == 0,
		"pin minimum completes one manual release and consumes only one grenade")

	ready_offline_grenade()
	grenade_action(true)
	session.update(0.05)
	session.select_tool(LocalSession.Tool.WEAPON)
	session.update(3.1)
	player._physics_process(1.0/60.0)
	check(throws.size() == 4 and not session.is_cooking_grenade and session.grenades == 3,
		"tool change cancels the held edge and grenade without delayed throw")

	ready_offline_grenade()
	grenade_action(true)
	session.update(0.05)
	app.hud.set_menu_visible(true)
	player._physics_process(1.0/60.0)
	check(session.is_cooking_grenade and throws.size() == 4,
		"brief denied input retains the source primary state before pin minimum")
	session.update(0.03)
	app.hud.set_menu_visible(false)
	grenade_action(true)
	session.update(0.081)
	player._physics_process(1.0/60.0)
	check(session.is_cooking_grenade and session.grenade_cook_time >= 0.15 and throws.size() == 4,
		"fresh press before pin minimum keeps the same cook after brief input denial")
	session.select_tool(LocalSession.Tool.WEAPON)

	ready_offline_grenade()
	grenade_action(true)
	session.update(0.05)
	session.invulnerable = false
	session.damage_player(100.0)
	player._physics_process(1.0/60.0)
	check(throws.size() == 5 and bool(throws[4].drop) and session.grenades == 2,
		"death during pin pull drops exactly one grenade before the minimum")
	session.damage_player(100.0)
	player._physics_process(1.0/60.0)
	check(throws.size() == 5, "dead-controller input cannot drop a second grenade")
	session.invulnerable = true

	ready_offline_grenade()
	grenade_action(true)
	session.update(0.05)
	app.hud.set_menu_visible(true)
	player._physics_process(1.0/60.0)
	session.update(0.101)
	player._physics_process(1.0/60.0)
	check(throws.size() == 6 and not session.is_cooking_grenade and not player.controls_enabled,
		"opening the menu releases a held grenade once while respecting pin minimum")
	session.update(1.0)
	player._physics_process(1.0/60.0)
	check(throws.size() == 6, "disabled menu input cannot begin the next cook")
	app.hud.set_menu_visible(false)
	grenade_action(true)
	check(session.is_cooking_grenade, "fresh press works after closing the menu without a stale held edge")
	session.select_tool(LocalSession.Tool.WEAPON)

	ready_offline_grenade()
	grenade_action(true)
	session.update(0.05)
	app.hud._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	player._physics_process(1.0/60.0)
	session.update(0.101)
	player._physics_process(1.0/60.0)
	check(throws.size() == 7 and not session.is_cooking_grenade and not Input.is_action_pressed("primary"),
		"focus loss releases the cook and physical action without repeating it")
	session.update(0.5)
	player._physics_process(1.0/60.0)
	app.hud._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	grenade_action(true)
	check(session.is_cooking_grenade, "focus return accepts a new primary press")
	session.select_tool(LocalSession.Tool.WEAPON)
	session.grenade_thrown.disconnect(observe_throw)
	session.invulnerable = was_invulnerable
	release_actions()
	return true

func test_tool_depletion() -> bool:
	release_actions()
	app.reset_lab()
	player.set_physics_process(false)
	session.select_tool(LocalSession.Tool.BLOCK)
	session.blocks = 0
	player._physics_process(1.0/60.0)
	check(session.current_tool == LocalSession.Tool.SPADE, "depleted block tool automatically selects previous available tool")
	session.select_weapon(LocalSession.Weapon.RIFLE)
	session.magazine = 0
	session.reserve = 0
	player._physics_process(1.0/60.0)
	check(session.current_tool == LocalSession.Tool.SPADE, "empty firearm automatically skips depleted blocks")
	session.restock()
	session.select_weapon(LocalSession.Weapon.RIFLE)
	session.select_tool(LocalSession.Tool.GRENADE)
	session.grenades = 0
	player._physics_process(1.0/60.0)
	check(session.current_tool == LocalSession.Tool.WEAPON, "depleted grenade tool automatically returns to available firearm")
	session.select_tool(LocalSession.Tool.BLOCK)
	session.select_tool(LocalSession.Tool.SPADE)
	session.blocks = 0
	player.select_last_tool()
	check(session.current_tool == LocalSession.Tool.SPADE, "last-tool selection refuses depleted item")
	return true

func test_melee_contract() -> bool:
	app.reset_lab()
	player.set_physics_process(false)
	for target in session.targets: session.set_target_state(int(target.id),"dead")
	player.respawn_at(Vector3(48.5,20,45.5))
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	var id := session.add_target(Vector3(51,20,43),1,false)
	check(player.find_melee_target(player.get_aim_origin(),Vector3.FORWARD) == id, "melee uses eye Chebyshev reach and broad cone, including off-axis target beyond3m Euclidean")
	session.get_target(id).position.x = 51.5
	check(player.find_melee_target(player.get_aim_origin(),Vector3.FORWARD) == -1, "melee excludes exact three-block Chebyshev boundary")
	session.get_target(id).position.x = 51
	world.set_block(Vector3i(48,22,44),VoxelWorld.pack_color(Color.GRAY))
	session.select_tool(LocalSession.Tool.SPADE)
	player._spade(false)
	check(session.get_target(id).health == 0 and session.last_hit_part == "melee", "native primary melee player selection precedes map hit action")
	return true

func test_ray_occlusion() -> bool:
	# Source compares horizontal distances even for vertical shots: a nearer
	# map hit tying a player's horizontal0 retains the head-first player hit.
	check(BlockfieldPlayer.source_weapon_hit(Vector3.ZERO,{"hit":true,"position":Vector3.UP},{"position":Vector3.UP*3})=="player","native vertical horizontal-distance tie retains player")
	check(BlockfieldPlayer.source_weapon_hit(Vector3.ZERO,{"hit":true,"position":Vector3(128,0,0)}, {})=="none","map at exact horizontal128 is outside firearm range")
	check(BlockfieldPlayer.source_weapon_hit(Vector3.ZERO,{"hit":false},{"position":Vector3(128,0,0)})=="none","player at exact horizontal128 is outside firearm range")
	check(BlockfieldPlayer.source_weapon_hit(Vector3.ZERO,{"hit":true,"position":Vector3(129,0,0)},{"position":Vector3(127,900,0)})=="player","horizontal range allows a far vertical player while ignoring farther map")
	release_actions()
	app.reset_lab()
	player.set_physics_process(false)
	for target in session.targets: session.set_target_state(int(target.id),"dead")
	var id := session.add_target(Vector3(48.5,20,40.5),1,false)
	player.respawn_at(Vector3(48.5,20,45.5))
	player.head.rotation = Vector3.ZERO
	player.rotation = Vector3.ZERO
	var ray := player.raycast_targets(player.get_aim_origin(),Vector3.FORWARD)
	check(ray.has("target_id") and int(ray.target_id) == id and ray.part == "head", "controller uses source volumes for actual target ray")
	world.set_block(Vector3i(48,22,43),VoxelWorld.pack_color(Color.GRAY))
	session.select_weapon(LocalSession.Weapon.RIFLE)
	player._shoot()
	check(session.get_target(id).health == 100, "nearer voxel occludes firearm target damage")
	world.set_block(Vector3i(48,22,43),0)
	session.fire_cooldown = 0
	player.head.rotation = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player._shoot()
	check(session.get_target(id).health == 0 and session.last_hit_part == "head", "same authoritative shot reaches exact head zone after occluder removed")
	return true

func test_match_reset() -> bool:
	release_actions()
	app.reset_lab()
	player.set_physics_process(false)
	# User-supplied VXL baseline, not the procedural reset path. Encode only once.
	var restored_cell := Vector3i(12,3,12)
	var original := world.get_block(restored_cell)
	app._map_baseline = world.encode_vxl()
	app._map_baseline_name = "Acceptance.vxl"
	world.set_block(restored_cell,0)
	session.set_mode("ctf")
	session.configure_ctf(Vector3(20,4,70),Vector3(76,4,22))
	session.team_scores = [2,1]
	session.ctf_flags[1].carrier = 0
	session.ctf_flags[1].at_base = false
	session.score = 22
	session.player_deaths = 4
	session.blocks = 2
	session.grenades = 1
	session.health = 7
	session.select_tool(LocalSession.Tool.GRENADE)
	session.begin_grenade_cook()
	session.update(.5)
	session.release_grenade()
	await app.reset_match()
	await frames(3)
	check(world.get_block(restored_cell) == original and world.map_name == "Acceptance.vxl", "reset_match restores uploaded VXL baseline rather than returning to lab map")
	check(session.team_scores == [0,0] and session.winning_team == -1 and session.ctf_flags.all(func(flag: Dictionary): return bool(flag.at_base) and int(flag.carrier) == -1), "reset_match clears CTF score/carrier/winner state")
	check(session.health == 100 and session.blocks == 50 and session.grenades == 3 and session.score == 0 and session.player_deaths == 0, "reset_match restores resources and all score counters")
	check(session.live_grenades.is_empty() and not session.is_cooking_grenade and session.targets.size() == 6, "reset_match removes live projectiles and recreates exactly six lab actor states")
	session.set_mode("tc")
	session.territories[0].owner = 1
	session.territories[1].progress = .75
	session.territories[1].capturing_team = 0
	session.territories[1].contested = true
	session.winning_team = 1
	await app.reset_match()
	check(session.mode == "tc" and session.territories.all(func(territory: Dictionary): return int(territory.owner) == 2 and float(territory.progress) == 0 and int(territory.capturing_team) == -1 and not bool(territory.contested)), "reset_match preserves chosen mode and clears neutral/contested TC state")
	return true
