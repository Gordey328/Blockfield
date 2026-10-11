extends SceneTree
## Actual Main touch look, exact actor/terrain visibility, and persisted control.
## godot --headless --path game --fixed-fps 60 --script ../tests/integration/test_mobile_aim_assist.gd
const SCENE = preload("res://scenes/main.tscn")
const ASSIST = preload("res://gameplay/touch_aim_assist.gd")
const FILES: Array[String] = ["user://settings.cfg", "user://servers.cfg"]
const FEET := Vector3(48.5, 20.0, 70.5)
const TARGET_FEET := Vector3(48.5, 20.0, 50.5)
const TURN: float = 400.0 * PI / 180.0
const EPS: float = 0.00001
var assertions: int = 0
var failures: int = 0
var app: Node3D
var player: BlockfieldPlayer
var session: LocalSession
var world: VoxelWorld
var saved: Dictionary = {}
var globals: Dictionary = {}


class RecordingReplica extends BlockfieldClientReplica:
	var owner := SharedPlayerState.new()
	var submitted: Array[Dictionary] = []
	var objectives: Dictionary = {}
	var actors: Array[Dictionary] = []
	func get_owner_state() -> SharedPlayerState:
		return owner.copy()
	func get_public_state() -> Dictionary:
		return {"epoch": owner.match_epoch, "tick": owner.last_tick,
			"actors": actors.duplicate(true), "grenades": [], "objectives": objectives}
	func submit_input(buttons: int, move: Vector2, yaw: float, pitch: float, tool: int = 255, weapon: int = 255) -> Dictionary:
		submitted.append({"buttons": buttons, "move": move, "yaw": yaw, "pitch": pitch, "tool": tool, "weapon": weapon})
		owner.yaw = yaw
		owner.pitch = pitch
		return {"ok": true}


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("MOBILE AIM ASSIST: " + message)


func near(actual: float, expected: float) -> bool:
	return absf(actual - expected) <= EPS


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame
		await create_timer(0.0).timeout


func enemy(patch: Dictionary = {}) -> Dictionary:
	var actor := {"id": 7, "position": TARGET_FEET, "yaw": 0.0, "pitch": 0.0,
		"crouching": false, "state": "standing", "team": 1, "alive": true,
		"health": 100, "health_known": true, "name": "Visible enemy"}
	actor.merge(patch, true)
	return actor


func defaults() -> void:
	player.clear_touch_motion()
	player.global_position = FEET
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player._camera_yaw = 0.0
	player._camera_pitch = 0.0
	player.camera_mode = BlockfieldPlayer.CameraMode.FIRST_PERSON
	player.controls_enabled = true
	player.touch_sensitivity = 1.0
	player.touch_ads_sensitivity = 1.0
	player.invert_touch = false
	player.touch_aim_assist = true
	player._aim_down_state = 0.0
	player.followed_target_id = -1
	session.health = 100
	session.team = 0
	session.current_tool = LocalSession.Tool.WEAPON
	session.current_weapon = LocalSession.Weapon.RIFLE
	session.targets.assign([enemy()])


func pose() -> Vector4:
	return Vector4(player.rotation.y, player.head.rotation.x, player._camera_yaw, player._camera_pitch)


func gain_for(actors: Array[Dictionary], motion: Vector2 = Vector2(0.5 * PI / 180.0, 0.0), origin: Vector3 = FEET + Vector3.UP * 2.25, direction: Vector3 = Vector3.FORWARD, own_team: int = 0, exclude: int = 0) -> float:
	return ASSIST.gain(origin, direction, actors, own_team, exclude, world, motion)


func run() -> void:
	for path: String in FILES:
		var exists := FileAccess.file_exists(path)
		saved[path] = {"exists": exists, "bytes": FileAccess.get_file_as_bytes(path) if exists else PackedByteArray()}
	globals = {"size": root.size, "scale_size": root.content_scale_size, "scale_aspect": root.content_scale_aspect,
		"scale_mode": root.content_scale_mode, "scale_factor": root.content_scale_factor,
		"mouse_mode": Input.mouse_mode, "emulation": Input.emulate_mouse_from_touch,
		"locale": TranslationServer.get_locale()}
	var config := ConfigFile.new()
	config.set_value("profile", "locale", "ru")
	config.set_value("ui", "touch_controls", 1)
	config.set_value("input", "future_setting", "preserve")
	config.set_value("input", "sensitivity", 0.006)
	check(config.save(FILES[0]) == OK, "temporary settings omit assist to exercise its migration default")
	await create_app()
	check(player.touch_aim_assist, "missing setting defaults to mild touch assistance")
	defaults()
	pure_visibility()
	touch_behavior()
	exclusions()
	await hud_and_preferences()
	network_command_boundary()
	await destroy_app()
	await create_app()
	check(not player.touch_aim_assist, "fresh Main loads the saved disabled assist setting")
	var controls: Dictionary = app.hud._ui_settings_controls
	check(controls.has("touch_reset") and controls.touch_reset is Button, "actual touch reset button exists")
	if controls.has("touch_reset") and controls.touch_reset is Button:
		controls.touch_reset.pressed.emit()
	check(player.touch_aim_assist, "actual reset restores the default assist preference")
	config.load(FILES[0])
	check(bool(config.get_value("input", "touch_aim_assist", false)), "reset persists the enabled assist default")
	check(config.get_value("input", "future_setting", "") == "preserve", "reset preserves unrelated future input settings")
	await destroy_app()
	await restore()
	print("MOBILE AIM ASSIST: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func create_app() -> void:
	app = SCENE.instantiate()
	root.add_child(app)
	await frames(5)
	player = app.get_node("Player")
	session = app.get_node("LocalSession")
	world = app.get_node("VoxelWorld")
	app.hud.set_menu_visible(false)
	app.set_process(false)
	app.set_physics_process(false)
	player.set_process(false)
	player.set_physics_process(false)
	app.hud.set_process(false)
	player.global_position = FEET
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	await frames(1)
	var hit := LabHitVolumes.cast_ray(player.get_aim_origin(), player.get_aim_direction(), TARGET_FEET, 0.0, false)
	check(bool(hit.hit) and float(hit.distance) > 10.0, "fixture ray intersects an actual original soldier OBB")
	var terrain := world.cast_source_ray(player.get_aim_origin(), player.get_aim_direction(), 30)
	check(not bool(terrain.hit) or float(terrain.position.distance_to(player.get_aim_origin())) > float(hit.distance),
		"fixture's elevated enemy is visible through the actual voxel world")


func pure_visibility() -> void:
	check(near(gain_for([enemy()]), 0.82), "small motion over a visible enemy has the accepted 18 percent friction")
	check(near(gain_for([]), 1.0), "empty aim lane has no friction")
	check(near(gain_for([enemy({"team": 0})]), 1.0), "ally does not attract friction")
	check(near(gain_for([enemy({"alive": false, "health": 0})]), 1.0), "dead soldier does not attract friction")
	check(near(gain_for([enemy({"health": 0})]), 1.0), "known zero health cannot retain friction during a stale alive snapshot")
	check(near(gain_for([enemy({"health": -1, "health_known": false})]), 0.82), "public network actor uses alive status without private HP")
	check(near(gain_for([enemy({"id": 0})]), 1.0), "owner identity is excluded")
	check(near(gain_for([enemy({"team": 2})]), 1.0), "spectator actor is excluded")
	check(near(gain_for([enemy({"position": FEET + Vector3.BACK * 20.0})]), 1.0), "actor behind the view is excluded")
	check(near(gain_for([enemy({"position": FEET + Vector3.FORWARD * 70.0})]), 1.0), "actor beyond the finite assistance range is excluded")
	check(near(gain_for([enemy()], Vector2(0.01, 0.0), FEET + Vector3(1.0, 2.25, 0.0)), 1.0),
		"a ray missing the exact body volumes is not caught by a broad aim cone")
	var ally := enemy({"id": 8, "team": 0, "position": FEET + Vector3.FORWARD * 10.0})
	check(near(gain_for([enemy(), ally]), 1.0) and near(gain_for([ally, enemy()]), 1.0),
		"nearest ally shields the enemy independently of actor iteration order")
	ally.position = FEET + Vector3.FORWARD * 30.0
	check(near(gain_for([ally, enemy()]), 0.82), "an ally behind the enemy does not shield its visible body")
	var wall := Vector3i(48, 22, 60)
	var original := world.get_block(wall)
	world.set_block(wall, VoxelWorld.pack_color(Color.WHITE))
	check(near(gain_for([enemy()]), 1.0), "actual foreground voxel suppresses assistance")
	defaults()
	player.apply_touch_motion(Vector2(1.0, 0.0), Vector2(1000.0, 600.0))
	check(near(player.rotation.y, -TURN * 0.001), "controller also respects foreground voxel occlusion")
	world.set_block(wall, original)
	wall = Vector3i(48, 22, 40)
	original = world.get_block(wall)
	world.set_block(wall, VoxelWorld.pack_color(Color.WHITE))
	check(near(gain_for([enemy()]), 0.82), "terrain behind the enemy leaves its visible body eligible")
	world.set_block(wall, original)
	check(near(gain_for([enemy()], Vector2.ZERO), 1.0), "zero user motion has no assistance work")
	check(near(gain_for([enemy()], Vector2(INF, 0.0)), 1.0), "invalid angular motion is rejected")
	check(near(gain_for([enemy()], Vector2(0.01, 0.0), Vector3(INF, 0.0, 0.0)), 1.0), "invalid origin is rejected before voxel queries")
	check(near(gain_for([enemy()], Vector2(0.01, 0.0), FEET, Vector3.ZERO), 1.0), "zero direction is rejected")
	check(near(gain_for([enemy()], Vector2(0.01, 0.0), FEET, Vector3.FORWARD, 2), 1.0), "spectator owner has no assistance")
	check(near(ASSIST.gain(FEET, Vector3.FORWARD, [enemy()], 0, 0, null, Vector2(0.01, 0.0)), 1.0), "detached voxel world has no assistance")


func touch_behavior() -> void:
	for extent: Vector2 in [Vector2(390, 844), Vector2(844, 390), Vector2(1280, 720), Vector2(2560, 1080)]:
		defaults()
		var relative := Vector2(extent.x * 0.001, extent.x * 0.0005)
		player.apply_touch_motion(relative, extent)
		check(near(player.rotation.y, -TURN * 0.001 * 0.82) and near(player.head.rotation.x, -TURN * 0.0005 * 0.82),
			"the same fractional drag has the same mild friction at " + str(extent))
	defaults()
	var before := pose()
	player.apply_touch_motion(Vector2.ZERO, Vector2(1000, 600))
	check(pose() == before, "visible target never rotates the view without user displacement")
	player.queue_touch_motion(Vector2.ZERO, Vector2(1000, 600))
	check(not player.flush_touch_motion() and pose() == before, "zero queued motion cannot trigger a snap")
	defaults()
	player.apply_touch_motion(Vector2(20.0, 0.0), Vector2(1000, 600))
	check(near(player.rotation.y, -TURN * 0.02), "deliberate eight degree swipe escapes friction completely")
	defaults()
	player.apply_touch_motion(Vector2(6.25, 0.0), Vector2(1000, 600))
	var transition := -player.rotation.y / (TURN * 0.00625)
	check(transition > 0.82 and transition < 1.0, "moderate swipe smoothly reduces friction toward full user gain")
	defaults()
	player.queue_touch_motion(Vector2(0.4, 0.2), Vector2(1000, 600))
	player.queue_touch_motion(Vector2(0.6, 0.3), Vector2(1000, 600))
	check(pose() == Vector4.ZERO, "HUD displacement remains queued before its production boundary")
	check(player.flush_touch_motion(), "queued touch is consumed once")
	check(near(player.rotation.y, -TURN * 0.001 * 0.82) and near(player.head.rotation.x, -TURN * 0.0005 * 0.82),
		"all queued events receive one coherent assisted angular displacement")
	before = pose()
	check(not player.flush_touch_motion() and pose() == before, "following boundary cannot replay assisted touch motion")
	for weapon: int in [0, 1, 2]:
		defaults()
		session.current_weapon = weapon
		player._aim_down_state = 1.0
		var zoom := player.get_aim_zoom()
		player.apply_touch_motion(Vector2(1.0, 0.0), Vector2(1000, 600))
		check(near(player.rotation.y, -TURN * 0.001 / zoom * 0.82), "all original weapons retain their ADS zoom with mild friction: " + str(weapon))


func exclusions() -> void:
	for patch: Dictionary in [{"team": 0}, {"alive": false}, {"health": 0}, {"position": FEET + Vector3.BACK * 20.0}]:
		defaults()
		session.targets.assign([enemy(patch)])
		player.apply_touch_motion(Vector2(1.0, 0.0), Vector2(1000, 600))
		check(near(player.rotation.y, -TURN * 0.001), "controller excludes ineligible target " + str(patch))
	for tool: int in [LocalSession.Tool.SPADE, LocalSession.Tool.BLOCK, LocalSession.Tool.GRENADE]:
		defaults()
		session.current_tool = tool
		player.apply_touch_motion(Vector2(1.0, 0.0), Vector2(1000, 600))
		check(near(player.rotation.y, -TURN * 0.001), "non-firearm touch tool never receives friction: " + str(tool))
	defaults()
	player.touch_aim_assist = false
	player.apply_touch_motion(Vector2(1.0, 0.0), Vector2(1000, 600))
	check(near(player.rotation.y, -TURN * 0.001), "disabled preference restores full raw touch gain")
	defaults()
	player.camera_mode = BlockfieldPlayer.CameraMode.THIRD_PERSON
	player.apply_touch_motion(Vector2(1.0, 0.0), Vector2(1000, 600))
	check(near(player.rotation.y, -TURN * 0.001), "third-person touch has no combat assistance")
	for mode: int in [BlockfieldPlayer.CameraMode.DEATH, BlockfieldPlayer.CameraMode.FREE, BlockfieldPlayer.CameraMode.FOLLOW_THIRD_PERSON]:
		defaults()
		player.camera_mode = mode
		player.apply_touch_motion(Vector2(1.0, 0.0), Vector2(1000, 600))
		check(near(player._camera_yaw, -TURN * 0.001), "spectator orbit remains unassisted: " + str(mode))
	defaults()
	player.camera_mode = BlockfieldPlayer.CameraMode.FOLLOW_FIRST_PERSON
	player.apply_touch_motion(Vector2(1.0, 0.0), Vector2(1000, 600))
	check(pose() == Vector4.ZERO, "first-person following cannot turn the observed player's view")
	for owner: Dictionary in [{"health": 0}, {"team": 2}]:
		defaults()
		for key: String in owner:
			session.set(key, owner[key])
		player.apply_touch_motion(Vector2(1.0, 0.0), Vector2(1000, 600))
		check(near(player.rotation.y, -TURN * 0.001), "dead or spectator owner cannot gain assisted combat look")
	defaults()
	player.sensitivity = 0.006
	player.mouse_exponent = 1.0
	player.apply_mouse_motion(Vector2(1.0, 0.5))
	var mouse_pose := pose()
	defaults()
	player.touch_aim_assist = false
	player.apply_mouse_motion(Vector2(1.0, 0.5))
	check(pose() == mouse_pose and near(mouse_pose.x, -0.006), "assist preference never changes the desktop mouse path")


func hud_and_preferences() -> void:
	defaults()
	app.hud.set_mobile_controls_mode(1)
	app.hud.set_menu_visible(false)
	var mobile: Control = app.hud.mobile_controls
	mobile.release_all()
	mobile.set_anchors_preset(Control.PRESET_TOP_LEFT)
	mobile.position = Vector2.ZERO
	mobile.size = Vector2(1000, 600)
	mobile.set_enabled(true)
	var origin: Vector2 = (mobile.get_hit_regions().look as Rect2).get_center()
	check(mobile.handle_touch(31, origin, true) and mobile.handle_drag(31, origin + Vector2(1.0, 0.5), Vector2(1.0, 0.5)),
		"actual mobile HUD accepts a fine look gesture")
	check(pose() == Vector4.ZERO, "actual HUD signal queues motion rather than rotating per event")
	player.flush_touch_motion()
	check(near(player.rotation.y, -TURN * 0.001 * 0.82), "actual HUD reaches the assisted controller path")
	mobile.release_all()
	defaults()
	app.hud.set_menu_visible(true)
	mobile.look_moved.emit(Vector2(1.0, 0.5))
	check(not player.flush_touch_motion() and pose() == Vector4.ZERO, "open menu blocks late touch assistance signals")
	app.hud.set_menu_visible(false)
	app.hud.open_chat(false)
	mobile.look_moved.emit(Vector2(1.0, 0.5))
	check(not player.flush_touch_motion() and pose() == Vector4.ZERO, "chat input blocks late touch assistance signals")
	app.hud._chat.cancel_input()
	app.hud._sync_controls()
	var controls: Dictionary = app.hud._ui_settings_controls
	check(controls.has("touch_aim_assist") and controls.touch_aim_assist is BaseButton, "actual settings expose the touch assist preference")
	if controls.has("touch_aim_assist") and controls.touch_aim_assist is BaseButton:
		controls.touch_aim_assist.button_pressed = false
	check(not player.touch_aim_assist, "actual settings callback disables assistance")
	var config := ConfigFile.new()
	check(config.load(FILES[0]) == OK and not bool(config.get_value("input", "touch_aim_assist", true)),
		"disabled assistance persists in the input section")
	check(config.get_value("input", "future_setting", "") == "preserve", "saving assistance preserves unrelated future input preferences")
	await frames(1)


func network_command_boundary() -> void:
	defaults()
	var offline := player.session
	var previous_connected := player._connected_session
	var previous_replica: BlockfieldClientReplica = app.network_client
	var replica := RecordingReplica.new()
	replica.status = "live"
	replica.actor_id = 1
	replica.epoch = 1
	replica.owner.player_id = 1
	replica.owner.team = 0
	replica.owner.health = 100
	replica.owner.spawn_generation = 1
	replica.owner.tool_raise = 1.0
	replica.owner.motion = SourcePlayerMotion.create_state(FEET)
	var remote := SharedPlayerState.new(7, "Visible network enemy", 1)
	remote.team = 1
	remote.health = 100
	remote.spawn_generation = 1
	remote.motion = SourcePlayerMotion.create_state(TARGET_FEET)
	replica.actors.assign([SimulationCodec._public_actor(remote)])
	replica.objectives = {"mode": offline.mode, "capture_limit": offline.capture_limit,
		"winning_team": offline.winning_team, "scores": offline.team_scores.duplicate(),
		"bases": offline.ctf_bases.duplicate(true), "flags": offline.ctf_flags.duplicate(true),
		"territories": offline.territories.duplicate(true)}
	var network := NetworkSession.new()
	network.bind_replica(replica)
	app.network_client = replica
	player.session = network
	player._connected_session = network
	player._network_epoch = 0
	player._network_generation = -1
	player._physics_process(0.0)
	check(network.targets.size() == 1 and not bool(network.targets[0].health_known), "network adapter mirrors a live public actor without private HP")
	replica.submitted.clear()
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.camera_mode = BlockfieldPlayer.CameraMode.FIRST_PERSON
	player.queue_touch_motion(Vector2(1.0, 0.5), Vector2(1000, 600))
	player._physics_process(1.0 / 60.0)
	check(replica.submitted.size() == 1, "network production boundary samples exactly one assisted command")
	if not replica.submitted.is_empty():
		var command: Dictionary = replica.submitted.back()
		check(near(float(command.yaw), -TURN * 0.001 * 0.82) and near(float(command.pitch), -TURN * 0.0005 * 0.82),
			"assisted user angles enter the normal authenticated network intent")
	var before := pose()
	player._process(0.001)
	player._physics_process(1.0 / 60.0)
	check(pose().is_equal_approx(before), "render and subsequent network sampling cannot replay assisted movement")
	player.session = offline
	player._connected_session = previous_connected
	app.network_client = previous_replica
	player._network_owner = null
	player._network_epoch = 0
	player._network_generation = -1
	network.free()
	player.touch_aim_assist = false
	# Keep the previously saved disabled setting for the fresh scene round trip.
	app.save_settings()


func destroy_app() -> void:
	if app == null:
		return
	app.hud._release_mobile_input()
	player.controls_enabled = false
	LabInputBindings.release_actions()
	app.stop_audio()
	var reference: WeakRef = weakref(app)
	app.queue_free()
	await frames(8)
	check(reference.get_ref() == null, "actual scene is freed before fresh settings or process exit")
	app = null
	player = null
	session = null
	world = null
	var deadline := Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
		await process_frame


func restore() -> void:
	for path: String in FILES:
		if saved[path].exists:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(saved[path].bytes)
			file.close()
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	root.size = globals.size
	root.content_scale_size = globals.scale_size
	root.content_scale_aspect = globals.scale_aspect
	root.content_scale_mode = globals.scale_mode
	root.content_scale_factor = globals.scale_factor
	Input.mouse_mode = globals.mouse_mode
	Input.emulate_mouse_from_touch = globals.emulation
	TranslationServer.set_locale(globals.locale)
