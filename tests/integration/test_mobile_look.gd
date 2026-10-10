extends SceneTree
## Actual Main/Player/HUD touch-look integration. Owns a temporary preference
## fixture and restores original settings/servers bytes and process globals.
const SCENE = preload("res://scenes/main.tscn")
const FILES: Array[String] = ["user://settings.cfg", "user://servers.cfg"]
const DESKTOP := {"sensitivity":0.006,"mouse_exponent":1.8,"ads_sensitivity":0.43,"invert_mouse":true}
const TOUCH_KEYS: Array[String] = ["touch_sensitivity","touch_ads_sensitivity","invert_touch"]
const UI_KEYS: Array[String] = ["floating_stick","touch_control_scale","fire_drag_look"]
const TURN := 300.0 * PI / 180.0
const EPS := 0.00003
var checks := 0
var failures := 0
var app: Node3D
var saved: Dictionary = {}
var globals: Dictionary = {}
var finishing := false

func _initialize() -> void:
	call_deferred("run")
	create_timer(45.0).timeout.connect(func():
		if not finishing:
			check(false,"bounded actual-scene fixture completed before cleanup deadline")
			finish())

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("MOBILE LOOK: " + message)

func near(actual: float, expected: float) -> bool:
	return absf(actual - expected) <= EPS

func yaw_near(actual: float, expected: float) -> bool:
	return absf(angle_difference(actual, expected)) <= EPS

func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame
		await create_timer(0.0).timeout

func pose() -> Vector4:
	return Vector4(app.player.rotation.y,app.player.head.rotation.x,app.player._camera_yaw,app.player._camera_pitch)

func reset_pose(mode: int = BlockfieldPlayer.CameraMode.FIRST_PERSON) -> void:
	app.player.camera_mode = mode
	app.player.rotation = Vector3.ZERO
	app.player.head.rotation = Vector3.ZERO
	app.player._camera_yaw = 0.0
	app.player._camera_pitch = 0.0

func defaults() -> void:
	app.player.touch_sensitivity = 1.0
	app.player.touch_ads_sensitivity = 1.0
	app.player.invert_touch = false
	app.player._aim_down_state = 0.0
	app.session.current_tool = LocalSession.Tool.WEAPON
	app.session.current_weapon = 0
	app.session.health = 100
	app.session.team = 0
	app.player.controls_enabled = true
	reset_pose()

func desktop_defaults() -> void:
	for property: String in DESKTOP:
		app.player.set(property,DESKTOP[property])

func save_originals() -> void:
	for path: String in FILES:
		var exists := FileAccess.file_exists(path)
		saved[path] = {"exists":exists,"bytes":FileAccess.get_file_as_bytes(path) if exists else PackedByteArray()}
	globals = {"window_size":root.size,"scale_size":root.content_scale_size,"scale_aspect":root.content_scale_aspect,
		"scale_factor":root.content_scale_factor,"scale_mode":root.content_scale_mode,
		"mouse_mode":Input.mouse_mode,"emulation":Input.emulate_mouse_from_touch,
		"volume":AudioServer.get_bus_volume_db(0),"locale":TranslationServer.get_locale()}

func prepare_preferences() -> bool:
	var config := ConfigFile.new()
	if saved[FILES[0]].exists:
		if config.load(FILES[0]) != OK:
			check(false,"existing settings parse before temporary fixture")
			return false
	for key: String in TOUCH_KEYS:
		if config.has_section_key("input",key):config.erase_section_key("input",key)
	for key: String in UI_KEYS:
		if config.has_section_key("ui",key):config.erase_section_key("ui",key)
	for property: String in DESKTOP:config.set_value("input",property,DESKTOP[property])
	config.set_value("ui","touch_controls",0)
	config.set_value("ui","hidden",false)
	config.set_value("ui","minimap_size",192)
	config.set_value("view","skin","original")
	config.set_value("profile","locale","en")
	config.set_value("graphics","hdr",false)
	config.set_value("test_mobile_look","untouched","retain unrelated settings")
	config.set_value("input","future_input_option",true)
	config.set_value("ui","future_ui_option",Vector2(3,4))
	var ok := config.save(FILES[0]) == OK
	check(ok,"temporary settings omit new touch keys without dropping unrelated sections")
	return ok

func create_app() -> bool:
	app = SCENE.instantiate()
	root.add_child(app)
	app.session.select_team(0)
	app.session.select_weapon(0)
	app.hud.set_menu_visible(false)
	var ready := false
	for frame in 150:
		if app.player.can_use_tool():ready = true;break
		await frames(1)
		if finishing:return false
	check(ready,"actual Main/Player/HUD and original weapon reach source ready state")
	# Retain actual node/input/signal connections while isolating look arithmetic
	# from frame-driven ADS easing, respawn, spectator mode and camera shake.
	app.set_process(false)
	app.set_physics_process(false)
	app.player.set_physics_process(false)
	app.hud.set_process(false)
	return ready

func initial_defaults() -> void:
	check(near(app.player.touch_sensitivity,1.0) and near(app.player.touch_ads_sensitivity,1.0) and not app.player.invert_touch,"missing input preferences load independent touch defaults")
	check(app.hud.floating_stick and near(app.hud.touch_control_scale,1.0) and app.hud.fire_drag_look,"missing UI preferences load floating stick, default scale and fire-drag defaults")
	var mobile: Control = app.hud.mobile_controls
	check(mobile.floating_stick and near(mobile.control_scale,1.0) and mobile.fire_drag_look,"actual first overlay creation receives HUD default preferences")
	for property: String in DESKTOP:
		check(app.player.get(property) == DESKTOP[property],"new defaults preserve independently loaded desktop " + property)

func normalization() -> void:
	defaults()
	for extent: Vector2 in [Vector2(960,540),Vector2(1920,1080),Vector2(844,390),Vector2(390,844)]:
		reset_pose()
		app.player.apply_touch_motion(Vector2(extent.x * 0.18,extent.x * 0.035),extent)
		check(yaw_near(app.player.rotation.y,-TURN * 0.18),"fractional swipe has resolution-independent yaw at " + str(extent))
		check(near(app.player.head.rotation.x,-TURN * 0.035),"pitch uses the same logical width gain in landscape/portrait " + str(extent))
	for sensitivity: float in [0.25,1.0,3.0]:
		app.player.touch_sensitivity = sensitivity
		reset_pose()
		app.player.apply_touch_motion(Vector2(80,10),Vector2(1000,600))
		check(yaw_near(app.player.rotation.y,-TURN * 0.08 * sensitivity) and near(app.player.head.rotation.x,-TURN * 0.01 * sensitivity),"documented touch sensitivity scales yaw and pitch linearly")
	app.player.touch_sensitivity = -3.0
	check(near(app.player.touch_sensitivity,0.25),"touch sensitivity lower bound")
	app.player.touch_sensitivity = 30.0
	check(near(app.player.touch_sensitivity,3.0),"touch sensitivity upper bound")
	app.player.touch_sensitivity = NAN
	check(near(app.player.touch_sensitivity,1.0),"nonfinite touch sensitivity resets to finite default")
	app.player.touch_ads_sensitivity = -1.0
	check(near(app.player.touch_ads_sensitivity,0.25),"touch ADS lower bound")
	app.player.touch_ads_sensitivity = 9.0
	check(near(app.player.touch_ads_sensitivity,2.0),"touch ADS upper bound")
	app.player.touch_ads_sensitivity = INF
	check(near(app.player.touch_ads_sensitivity,1.0),"nonfinite touch ADS resets to finite default")

func segmentation() -> void:
	defaults()
	app.player.mouse_exponent = 2.7
	app.player.sensitivity = 0.07
	app.player.ads_sensitivity = 1.9
	var extent := Vector2(960,540)
	var total := Vector2(180,-30)
	for segments: int in [1,2,7,64]:
		reset_pose()
		for index in segments:
			app.player.apply_touch_motion(total / float(segments),extent)
			if segments >= 7:await process_frame
		check(yaw_near(app.player.rotation.y,-TURN * total.x / extent.x),"one swipe split into%d events preserves yaw despite mouse acceleration" % segments)
		check(near(app.player.head.rotation.x,-TURN * total.y / extent.x),"event/frame-rate segmentation preserves linear touch pitch")
	check(near(app.player.mouse_exponent,2.7) and near(app.player.sensitivity,0.07) and near(app.player.ads_sensitivity,1.9),"touch events do not rewrite desktop tuning")

func ads_and_mouse_independence() -> void:
	defaults()
	app.player.touch_sensitivity = 1.25
	app.player.touch_ads_sensitivity = 0.6
	app.player.invert_mouse = true
	app.player.mouse_exponent = 2.8
	app.player.sensitivity = 0.07
	app.player.ads_sensitivity = 1.95
	for weapon: int in range(3):
		app.session.current_weapon = weapon
		for state: float in [0.0,0.5,1.0]:
			app.player._aim_down_state = state
			var zoom: float = 1.0 + (3.0 - 2.0 * pow(state,1.5)) * pow(state,3.0) * [1.4,0.8,0.4][weapon]
			check(near(app.player.get_aim_zoom(),zoom),"actual source weapon zoom remains available for touch ADS")
			var gain: float = TURN * 1.25 * pow(0.6,state) / zoom
			for mode: int in [BlockfieldPlayer.CameraMode.FIRST_PERSON,BlockfieldPlayer.CameraMode.THIRD_PERSON]:
				reset_pose(mode)
				app.player.apply_touch_motion(Vector2(60,20),Vector2(1000,600))
				check(yaw_near(app.player.rotation.y,-gain * 0.06) and near(app.player.head.rotation.x,-gain * 0.02),"own view uses native zoom and touch-only ADS exponent for weapon%d state%.1f mode%d" % [weapon,state,mode])
	defaults()
	desktop_defaults()
	app.player._aim_down_state = 0.5
	var zoom: float = app.player.get_aim_zoom()
	var relative := Vector2(20,-5)
	var delta := relative / zoom
	var width := maxf(1.0,app.player.get_viewport().get_visible_rect().size.x)
	delta *= pow(delta.length_squared() / pow(width * 0.1,2.0),1.8 * 0.5 - 0.5)
	delta *= pow(0.43,0.5) * 0.006
	app.player.apply_mouse_motion(relative)
	var before := pose()
	check(yaw_near(before.x,-delta.x) and near(before.y,delta.y),"actual desktop source exponent/ADS/inversion formula remains unchanged")
	app.player.touch_sensitivity = 3.0
	app.player.touch_ads_sensitivity = 0.25
	app.player.invert_touch = true
	reset_pose()
	app.player.apply_mouse_motion(relative)
	check(pose().is_equal_approx(before),"touch sensitivity, ADS and inversion never change mouse look")

func spectator_and_permissions() -> void:
	defaults()
	app.player.touch_sensitivity = 1.4
	app.player.touch_ads_sensitivity = 0.25
	app.player._aim_down_state = 1.0
	app.player.invert_mouse = true
	var gain := TURN * 1.4 / 1000.0
	for mode: int in [BlockfieldPlayer.CameraMode.FREE,BlockfieldPlayer.CameraMode.DEATH,BlockfieldPlayer.CameraMode.FOLLOW_THIRD_PERSON]:
		reset_pose(mode)
		app.player.apply_touch_motion(Vector2(40,15),Vector2(1000,600))
		check(near(app.player._camera_yaw,-40 * gain) and near(app.player._camera_pitch,-15 * gain),"spectator mode%d uses touch gain without own weapon ADS/mouse inversion" % mode)
		check(app.player.rotation == Vector3.ZERO and app.player.head.rotation == Vector3.ZERO,"spectator touch orbits presentation rather than moving the player body")
		app.player.invert_touch = true
		reset_pose(mode)
		app.player.apply_touch_motion(Vector2(40,15),Vector2(1000,600))
		check(near(app.player._camera_pitch,15 * gain),"spectator inversion comes from touch preference")
		app.player.invert_touch = false
		app.player.apply_touch_motion(Vector2(0,1e8),Vector2(1000,600))
		check(near(app.player._camera_pitch,-PI * 0.45),"spectator downward pitch clamps at source orbit bound")
		app.player.apply_touch_motion(Vector2(0,-1e8),Vector2(1000,600))
		check(near(app.player._camera_pitch,PI * 0.45),"spectator upward pitch clamps at source orbit bound")
	defaults()
	app.player.invert_touch = true
	app.player.apply_touch_motion(Vector2(30,12),Vector2(1000,600))
	check(yaw_near(app.player.rotation.y,-TURN * 0.03) and near(app.player.head.rotation.x,TURN * 0.012),"live touch inversion changes vertical sign independently of horizontal")
	app.player.invert_touch = false
	app.player.apply_touch_motion(Vector2(0,1e8),Vector2(1000,600))
	check(near(app.player.head.rotation.x,-1.55),"live downward pitch clamps")
	app.player.apply_touch_motion(Vector2(0,-1e8),Vector2(1000,600))
	check(near(app.player.head.rotation.x,1.55),"live upward pitch clamps")
	reset_pose(BlockfieldPlayer.CameraMode.FOLLOW_FIRST_PERSON)
	app.player.apply_touch_motion(Vector2(100,100),Vector2(1000,600))
	check(pose() == Vector4.ZERO,"follow first-person ignores local touch look")
	for mode: int in [BlockfieldPlayer.CameraMode.FIRST_PERSON,BlockfieldPlayer.CameraMode.FREE]:
		reset_pose(mode)
		app.player.controls_enabled = false
		app.player.apply_touch_motion(Vector2(100,100),Vector2(1000,600))
		check(pose() == Vector4.ZERO,"disabled gameplay permission blocks touch in own and spectator modes")
	app.player.controls_enabled = true
	reset_pose()
	var session: LocalSession = app.player.session
	app.player.session = null
	app.player.apply_touch_motion(Vector2(100,100),Vector2(1000,600))
	app.player.session = session
	check(pose() == Vector4.ZERO,"detached session cannot consume touch look")
	for extent: Vector2 in [Vector2.ZERO,Vector2(1000,0),Vector2(NAN,600)]:
		app.player.apply_touch_motion(Vector2(100,100),extent)
		check(pose() == Vector4.ZERO,"invalid logical screen extent cannot rotate camera")
	app.player.apply_touch_motion(Vector2(INF,0),Vector2(1000,600))
	check(pose() == Vector4.ZERO,"nonfinite drag cannot poison player rotation")

func configure_overlay(extent: Vector2, scale: Vector2 = Vector2.ONE) -> Control:
	var mobile: Control = app.hud.mobile_controls
	mobile.release_all()
	mobile.set_anchors_preset(Control.PRESET_TOP_LEFT)
	mobile.position = Vector2(12,9)
	mobile.size = extent
	mobile.scale = scale
	mobile.set_enabled(true)
	return mobile

func hud_bridge() -> void:
	defaults()
	app.hud.set_mobile_controls_mode(1)
	app.hud.set_menu_visible(false)
	app.hud.floating_stick = true
	app.hud.touch_control_scale = 1.0
	app.hud.fire_drag_look = true
	app.hud._apply_touch_preferences()
	app.player.mouse_exponent = 2.8
	app.player.sensitivity = 0.07
	for extent: Vector2 in [Vector2(960,540),Vector2(844,390)]:
		var mobile := configure_overlay(extent)
		var start: Vector2 = (mobile.get_hit_regions().look as Rect2).get_center()
		var delta := Vector2(extent.x * 0.06,-extent.x * 0.02)
		reset_pose()
		check(mobile.handle_touch(11,start,true) and mobile.handle_drag(11,start+delta,delta),"actual HUD accepts local look pointer/drag")
		check(yaw_near(app.player.rotation.y,-TURN * 0.06) and near(app.player.head.rotation.x,TURN * 0.02),"actual HUD signal uses overlay logical extent and touch path at " + str(extent))
		mobile.release_all()
	var mobile := configure_overlay(Vector2(960,540))
	var regions: Dictionary = mobile.get_hit_regions()
	var look: Vector2 = (regions.look as Rect2).get_center()
	var move: Vector2 = (regions.move as Rect2).get_center()
	reset_pose()
	check(mobile.handle_touch(12,move,true) and mobile.handle_touch(13,look,true),"actual Main accepts independent simultaneous stick/look ownership")
	mobile.handle_drag(12,move+Vector2(0,-25),Vector2(300,400))
	check(pose() == Vector4.ZERO and app.player.touch_movement.y < 0.0,"stick updates real player movement without rotating its look")
	mobile.handle_drag(13,look+Vector2(60,0),Vector2(60,0))
	check(yaw_near(app.player.rotation.y,-TURN * 60.0 / 960.0) and app.player.touch_movement.y < 0.0,"look updates yaw while actual stick intent remains independent")
	mobile.release_all()
	check(app.player.touch_movement == Vector2.ZERO,"actual HUD releases simultaneous movement/look ownership")
	# Real ScreenTouch/ScreenDrag run through production canvas conversion, then
	# the actual HUD signal. Neither physical scale nor nonuniform scale is a
	# second sensitivity factor when delta and extent share local coordinates.
	mobile = configure_overlay(Vector2(960,540),Vector2(0.63,0.81))
	look = (mobile.get_hit_regions().look as Rect2).get_center()
	var delta := Vector2(64,-16)
	reset_pose()
	var transform: Transform2D = mobile.get_global_transform_with_canvas()
	var touch := InputEventScreenTouch.new()
	touch.window_id = root.get_window_id()
	touch.index = 23;touch.position = transform * look;touch.pressed = true
	root.push_input(touch,true)
	await process_frame
	var drag := InputEventScreenDrag.new()
	drag.window_id = root.get_window_id()
	drag.index = 23;drag.position = transform * (look+delta);drag.relative = transform.basis_xform(delta)
	root.push_input(drag,true)
	await process_frame
	check(yaw_near(app.player.rotation.y,-TURN * 64.0 / 960.0) and near(app.player.head.rotation.x,TURN * 16.0 / 960.0),"real scaled screen events preserve local fractional look gain through Main/HUD")
	touch = InputEventScreenTouch.new()
	touch.window_id = root.get_window_id();touch.index = 23;touch.position = transform * (look+delta);touch.pressed = false
	root.push_input(touch,true)
	await process_frame
	mobile.release_all()
	mobile.scale = Vector2.ONE
	reset_pose()
	app.hud.set_menu_visible(true)
	mobile.look_moved.emit(Vector2(50,50))
	check(not app.player.controls_enabled and pose() == Vector4.ZERO,"actual menu permission blocks even a late look signal")
	app.hud.set_menu_visible(false)
	app.hud.open_chat(false)
	mobile.look_moved.emit(Vector2(50,50))
	check(not app.player.controls_enabled and pose() == Vector4.ZERO,"actual chat permission blocks late look signals")
	app.hud._chat.cancel_input()
	app.hud._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	mobile.look_moved.emit(Vector2(50,50))
	check(not app.player.controls_enabled and pose() == Vector4.ZERO,"focus loss blocks touch and clears actual control ownership")
	app.hud._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	check(app.player.controls_enabled,"focus return restores permission without a latent drag")

func range_value(key: String, value: float) -> void:
	var controls: Dictionary = app.hud._ui_settings_controls
	check(controls.has(key) and controls[key] is Range,"actual touch settings slider exists: " + key)
	if controls.has(key) and controls[key] is Range:controls[key].value = value

func button_value(key: String, value: bool) -> void:
	var controls: Dictionary = app.hud._ui_settings_controls
	check(controls.has(key) and controls[key] is BaseButton,"actual touch settings toggle exists: " + key)
	if controls.has(key) and controls[key] is BaseButton:controls[key].button_pressed = value

func ui_preferences() -> void:
	desktop_defaults()
	range_value("touch_sensitivity",1.75)
	range_value("touch_ads_sensitivity",0.6)
	button_value("invert_touch",true)
	button_value("floating_stick",false)
	range_value("touch_control_scale",1.2)
	button_value("fire_drag_look",false)
	check(near(app.player.touch_sensitivity,1.75) and near(app.player.touch_ads_sensitivity,0.6) and app.player.invert_touch,"real settings callbacks change only player touch preferences")
	check(not app.hud.floating_stick and near(app.hud.touch_control_scale,1.2) and not app.hud.fire_drag_look,"real settings callbacks change HUD touch preferences")
	var mobile: Control = app.hud.mobile_controls
	check(not mobile.floating_stick and near(mobile.control_scale,1.2) and not mobile.fire_drag_look,"live overlay receives persisted UI preference changes")
	var config := ConfigFile.new()
	check(config.load(FILES[0]) == OK,"real callbacks saved a readable ConfigFile")
	check(near(float(config.get_value("input","touch_sensitivity",0.0)),1.75) and near(float(config.get_value("input","touch_ads_sensitivity",0.0)),0.6) and bool(config.get_value("input","invert_touch",false)),"player preferences persist in input section")
	check(not bool(config.get_value("ui","floating_stick",true)) and near(float(config.get_value("ui","touch_control_scale",0.0)),1.2) and not bool(config.get_value("ui","fire_drag_look",true)),"HUD preferences persist in ui section")
	for property: String in DESKTOP:
		check(config.get_value("input",property) == DESKTOP[property],"touch callbacks preserve desktop setting " + property)
	check(config.get_value("test_mobile_look","untouched") == "retain unrelated settings" and config.get_value("input","future_input_option") == true and config.get_value("ui","future_ui_option") == Vector2(3,4),"touch save preserves unrelated/unknown settings across sections")
	check(config.get_value("ui","minimap_size") == 192,"touch save preserves unrelated minimap preference")

func roundtrip() -> void:
	check(near(app.player.touch_sensitivity,1.75) and near(app.player.touch_ads_sensitivity,0.6) and app.player.invert_touch,"fresh actual Main reloads persisted touch sensitivity/ADS/inversion")
	check(not app.hud.floating_stick and near(app.hud.touch_control_scale,1.2) and not app.hud.fire_drag_look,"fresh HUD reloads persisted floating/scale/fire-drag settings")
	var mobile: Control = app.hud.mobile_controls
	check(not mobile.floating_stick and near(mobile.control_scale,1.2) and not mobile.fire_drag_look,"new overlay creation receives reloaded settings rather than component defaults")
	for property: String in DESKTOP:
		check(app.player.get(property) == DESKTOP[property],"fresh scene preserves desktop setting " + property)
	app.player._aim_down_state = 0.0
	app.session.current_tool = LocalSession.Tool.WEAPON
	app.hud.set_mobile_controls_mode(1)
	app.hud.set_menu_visible(false)
	reset_pose()
	mobile = configure_overlay(Vector2(960,540))
	var look: Vector2 = (mobile.get_hit_regions().look as Rect2).get_center()
	check(mobile.handle_touch(24,look,true) and mobile.handle_drag(24,look+Vector2(48,10),Vector2(48,10)),"new overlay retains its actual HUD look connection")
	check(yaw_near(app.player.rotation.y,-TURN * 0.05 * 1.75) and near(app.player.head.rotation.x,TURN * 10.0 / 960.0 * 1.75),"reloaded sensitivity and inversion apply to actual new-scene touch look")
	mobile.release_all()
	var controls: Dictionary = app.hud._ui_settings_controls
	check(controls.has("touch_reset") and controls.touch_reset is Button,"actual mobile reset settings button exists")
	if controls.has("touch_reset") and controls.touch_reset is Button:controls.touch_reset.pressed.emit()
	check(near(app.player.touch_sensitivity,1.0) and near(app.player.touch_ads_sensitivity,1.0) and not app.player.invert_touch,"real reset callback restores touch input defaults")
	check(app.hud.floating_stick and near(app.hud.touch_control_scale,1.0) and app.hud.fire_drag_look and mobile.floating_stick and near(mobile.control_scale,1.0) and mobile.fire_drag_look,"real reset callback restores and propagates HUD defaults")
	for property: String in DESKTOP:
		check(app.player.get(property) == DESKTOP[property],"mobile reset leaves desktop setting unchanged: " + property)
	var config := ConfigFile.new();config.load(FILES[0])
	check(near(float(config.get_value("input","touch_sensitivity",0.0)),1.0) and near(float(config.get_value("input","touch_ads_sensitivity",0.0)),1.0) and not bool(config.get_value("input","invert_touch",true)),"reset saves default input preferences")
	check(bool(config.get_value("ui","floating_stick",false)) and near(float(config.get_value("ui","touch_control_scale",0.0)),1.0) and bool(config.get_value("ui","fire_drag_look",false)),"reset saves default UI preferences")
	check(config.get_value("test_mobile_look","untouched") == "retain unrelated settings" and config.get_value("input","future_input_option") == true and config.get_value("ui","future_ui_option") == Vector2(3,4),"mobile reset preserves unrelated settings")

func destroy_app() -> void:
	if is_instance_valid(app):
		app.hud._release_mobile_input()
		app.player.controls_enabled = false
		LabInputBindings.release_actions()
		app.stop_audio()
		app.queue_free()
		app = null
		await frames(8)
		await create_timer(0.2).timeout

func run() -> void:
	save_originals()
	if not prepare_preferences():await finish();return
	if not await create_app():await finish();return
	initial_defaults()
	normalization()
	await segmentation()
	if finishing:return
	ads_and_mouse_independence()
	spectator_and_permissions()
	await hud_bridge()
	if finishing:return
	ui_preferences()
	await destroy_app()
	if finishing:return
	if not await create_app():await finish();return
	roundtrip()
	await finish()

func finish() -> void:
	if finishing:return
	finishing = true
	await destroy_app()
	for path: String in saved:
		if saved[path].exists:
			var file := FileAccess.open(path,FileAccess.WRITE)
			check(file != null,"original settings file can be restored: " + path)
			if file != null:file.store_buffer(saved[path].bytes);file.close()
		else:
			if FileAccess.file_exists(path):DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		check(FileAccess.file_exists(path) == saved[path].exists and (not saved[path].exists or FileAccess.get_file_as_bytes(path) == saved[path].bytes),"original preference/servers existence and bytes restored exactly: " + path)
	if not globals.is_empty():
		root.size = globals.window_size
		root.content_scale_size = globals.scale_size
		root.content_scale_aspect = globals.scale_aspect
		root.content_scale_factor = globals.scale_factor
		root.content_scale_mode = globals.scale_mode
		Input.emulate_mouse_from_touch = globals.emulation
		Input.mouse_mode = globals.mouse_mode
		AudioServer.set_bus_volume_db(0,globals.volume)
		TranslationServer.set_locale(globals.locale)
	LabInputBindings.release_actions()
	print("MOBILE LOOK: %d assertions, %d failures" % [checks,failures])
	quit(1 if failures else 0)
