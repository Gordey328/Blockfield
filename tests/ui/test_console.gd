extends SceneTree
## Bounded parser and setting adapter contract, plus real chat input behavior.
const CONSOLE = preload("res://ui/lab_console.gd")
const CHAT = preload("res://ui/lab_chat.gd")

class PlayerPreferences extends Node:
	var base_fov: float = 90
	var sensitivity: float = .0025
	var ads_sensitivity: float = 1
	var mouse_exponent: float = 1
	var invert_mouse: bool = false
	var hold_aim_down_sight: bool = false
	var wheel_tool_direction: int = 1
	var third_person: bool = false
	var animations_enabled: bool = true
	var eject_brass: bool = true
	var view_weapon_offset: Vector3 = Vector3.ZERO

class FocusPreferences extends RefCounted:
	var speed: float = .4

class HUDPreferences extends Node:
	var values: Dictionary = {"hide_hud":false,"statistics":false,"hit_indicator":true,"alerts":true,"minimap_player_colors":true,"minimap_weapon_icons":true,"minimap_size":180,"player_names":2}
	func get_console_setting(key: String) -> Variant: return values.get(key)
	func set_console_setting(key: String, value: Variant) -> bool:
		if not values.has(key): return false
		values[key] = value
		return true

class Application extends Node:
	var player: PlayerPreferences = PlayerPreferences.new()
	var focus_control: FocusPreferences = FocusPreferences.new()
	var hud: HUDPreferences = HUDPreferences.new()
	var session: LocalSession = LocalSession.new()
	var environmental_audio: bool = true
	var positional_audio: bool = true
	var chat_beep: bool = true
	var hit_feedback_gain: float = .2
	var source_audio_gain: float = 1.0
	var source_audio_efx: bool = true
	var saves: int = 0
	var resets: int = 0
	var graphics: Dictionary = {"hdr":false,"hdr_min_ev":-1.5,"hdr_max_ev":.5,"hdr_speed":1.0,"manual_focus":false,"dof_strength":1.0,"particles":2,"shake":2,"blood":true,"ragdolls":true,"bloom":false,"camera_blur":false,"color_correction":true,"dof":false,"fxaa":false,"lens":false,"lens_flare":false,"shadows":true,"lighting":true,"gi":false,"ssao":false,"saturation":1.0,"exposure":0.0,"msaa":0,"water":true,"water_reflections":true,"water_refraction":true}
	func _init() -> void:
		add_child(player)
		add_child(hud)
		add_child(session)
	func get_graphics_options() -> Dictionary: return graphics.duplicate()
	func set_graphics_option(key: String, value: Variant) -> void:
		if graphics.has(key): graphics[key] = value; save_settings()
	func save_settings() -> void: saves += 1
	func reset_lab() -> void: resets += 1; session.reset_lab()

var assertions: int = 0
var failures: int = 0
var app: Application
var console: CONSOLE

func _initialize() -> void: call_deferred("_run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures += 1; push_error("CONSOLE: " + message)

func _run() -> void:
	app = Application.new()
	root.add_child(app)
	console = CONSOLE.new()
	console.setup(app)
	var volume_before: float = AudioServer.get_bus_volume_db(0)
	_test_queries_and_mapping()
	_test_validation()
	_test_reset_and_legacy()
	_test_chat_completion()
	AudioServer.set_bus_volume_db(0, volume_before)
	app.free()
	console = null
	print("CONSOLE: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)

func _test_queries_and_mapping() -> void:
	var before: int = app.saves
	var result: Dictionary = console.execute("/CG_FOV")
	check(result.handled and not result.changed and str(result.message).contains("90"), "native cvar query reads actual value case-insensitively")
	check(app.saves == before, "queries do not write preferences")
	check(not console.execute("ordinary chat").handled, "ordinary chat remains outside console dispatch")
	check(console.execute("/cg_fov 75").changed and app.player.base_fov == 75, "native FOV setter updates player")
	check(app.saves == before + 1, "player setting persists once")
	check(console.execute("/set cg_mouseSensitivity 2").changed and is_equal_approx(app.player.sensitivity,.006), "native mouse sensitivity uses .003 radians per unit")
	check(str(console.execute("/get cg_mouseSensitivity").message).contains("2"), "sensitivity query reverses native-unit conversion")
	check(console.execute("/cg_zoomedMouseSensScale 0.05").changed and is_equal_approx(app.player.ads_sensitivity,.05), "ADS scale accepts native Preferences lower bound")
	check(console.execute("/cg_mouseExpPower 1.7").changed and is_equal_approx(app.player.mouse_exponent,1.7), "exponent setter updates input transform")
	check(console.execute("/cg_invertMouseY on").changed and app.player.invert_mouse, "boolean alias maps mouse inversion")
	check(console.execute("/cg_switchToolByWheel 0").changed and app.player.wheel_tool_direction == 0, "wheel cvar can disable tool scrolling")
	check(console.execute("/cg_animations 0").changed and not app.player.animations_enabled, "animation toggle updates actual controller preference")
	check(console.execute("/cg_ejectBrass false").changed and not app.player.eject_brass, "casing toggle updates controller preference")
	check(console.execute("/cg_chatBeep off").changed and not app.chat_beep, "chat beep uses application preference")
	check(console.execute("/cg_hitFeedbackSoundGain .7").changed and is_equal_approx(app.hit_feedback_gain,.7), "hit sound gain remains independent of master gain")
	console.execute("/cg_viewWeaponX .25")
	console.execute("/cg_viewWeaponY -.5")
	console.execute("/cg_viewWeaponZ .125")
	check(app.player.view_weapon_offset.is_equal_approx(Vector3(.25,-.5,.125)), "native XYZ offset updates independent components without axis reinterpretation")
	check(console.execute("/cg_autoFocusSpeed .8").changed and is_equal_approx(app.focus_control.speed,.8), "autofocus cvar controls actual reciprocal-distance speed")
	check(console.execute("/r_multisamples 4").changed and app.graphics.msaa == 4, "graphics cvar uses supported setter path")
	check(console.execute("/r_hdr on").changed and app.graphics.hdr,"HDR cvar selects the true float scene path")
	check(console.execute("/r_hdrAutoExposureMin -2").changed and app.graphics.hdr_min_ev == -2,"Native HDR minEV maps to the exposure pass")
	check(console.execute("/r_hdrAutoExposureMax .7").changed and is_equal_approx(app.graphics.hdr_max_ev,.7),"Native HDR maxEV maps to the exposure pass")
	check(console.execute("/r_hdrAutoExposureSpeed 0").changed and app.graphics.hdr_speed==0,"Native zero adaptation speed is supported")
	console.execute("/r_water 1")
	check(app.graphics.water and not app.graphics.water_reflections and not app.graphics.water_refraction, "water level one enables surface without reflection/refraction")
	console.execute("/r_water 3")
	check(app.graphics.water and app.graphics.water_reflections and app.graphics.water_refraction, "water level three selects reflection and refraction together")
	console.execute("/r_water 0")
	check(not app.graphics.water and not app.graphics.water_reflections and not app.graphics.water_refraction, "water level zero disables all mapped water layers")
	console.execute("/s_gain .5")
	check(is_equal_approx(app.source_audio_gain,.5), "native source gain is applied before each source's effective gain clamp")
	check(console.execute("/s_eax 0").changed and not app.source_audio_efx,"native EAX switch controls the separate reverb/obstruction setting")
	check(console.execute("/cg_hideHud true").changed and bool(app.hud.values.hide_hud), "HUD cvar uses public HUD adapter")
	check(console.execute("/cg_minimapSize 256").changed and app.hud.values.minimap_size == 256, "minimap bounds match persisted UI limits")
	check(console.execute("/bf_positionalAudio 0").changed and not app.positional_audio, "explicit port audio variable maps application panning")
	var records: Array[Dictionary] = console.list_variables()
	check(records.size() >= 45, "registry exposes all supported mappings and metadata")
	var incomplete_records: Array[String] = []
	for record: Dictionary in records:
		if not record.has("default") or not record.has("minimum") or not record.has("maximum") or not record.has("mapping"):
			incomplete_records.append(str(record.get("name", "unknown")))
	check(incomplete_records.is_empty(), "registry consumers receive reviewable reset values and bounds for every entry")

func _test_validation() -> void:
	var before: float = app.player.base_fov
	var saves_before: int = app.saves
	for command: String in ["/cg_fov 44.999", "/cg_fov 90.001", "/cg_fov nan", "/cg_fov inf", "/cg_fov 1e999", "/cg_fov 1e-999", "/cg_fov 75 extra", "/set cg_fov", "/cg_fov 60;reset", "/cg_fov 60\n/reset", "/cg_fov " + "7".repeat(161)]:
		var result: Dictionary = console.execute(command)
		check(result.handled and not result.changed and app.player.base_fov == before, "invalid input cannot mutate settings: " + command.left(40))
	check(app.saves == saves_before, "invalid input cannot persist preferences")
	for command: String in ["/r_multisamples 1", "/r_multisamples 3", "/cg_particles 1.5", "/cg_invertMouseY yes", "/cg_minimapSize 127", "/cg_viewWeaponZ 1.01"]:
		check(not console.execute(command).changed, "setting-specific bounds/types reject: " + command)
	for name: String in ["s_alDriver", "r_blitFramebuffer", "cg_keyAttack", "cg_debugHitTest"]:
		var result: Dictionary = console.execute("/" + name + " 1")
		check(result.handled and not result.changed and str(result.message).begins_with("Unsupported"), "unsupported native variable reports explicit limitation: " + name)
	check(str(console.execute("/arbitrary_property 1").message).begins_with("Unknown"), "unknown names never become arbitrary object properties")
	check(str(console.execute("/cg_fov 75").message).begins_with("cg_fov") and not console.execute("/cg_fov 75").changed, "reapplying identical value reports no change")

func _test_reset_and_legacy() -> void:
	check(console.execute("/reset cg_fov").changed and app.player.base_fov == 68, "named reset restores documented native default")
	console.execute("/reset cg_viewWeaponY")
	check(app.player.view_weapon_offset.is_equal_approx(Vector3(.25,0,.125)), "named offset reset preserves other axes")
	app.session.blocks = 1
	check(console.execute("/restock").handled and app.session.blocks == 50, "existing restock command retained")
	console.execute("/mode tc")
	check(app.session.mode == "tc", "existing local mode command retained")
	console.execute("/team spectator")
	check(app.session.team == 2, "existing team command retained")
	console.execute("/reset")
	check(app.resets == 1, "bare reset still resets the test lab")
	check(str(console.execute("/help").message).contains("/restock") and str(console.execute("/help").message).contains("/cvars"), "help preserves local commands and advertises cvars")
	var result: Dictionary = console.execute("/reset all")
	check(result.changed and app.resets == 1, "reset all resets settings without resetting lab")
	check(app.player.base_fov == 68 and is_equal_approx(app.player.sensitivity,.003) and app.player.view_weapon_offset == Vector3.ZERO, "all reset restores native input and offset defaults")
	check(app.player.animations_enabled and app.player.eject_brass and app.chat_beep, "all reset restores disabled presentation/audio switches")
	check(app.graphics.water and app.graphics.water_reflections and not app.graphics.water_refraction, "native water default is level two")

func _test_chat_completion() -> void:
	check(console.completion("/cg_viewWeapon") == ["/cg_viewWeaponX", "/cg_viewWeaponY", "/cg_viewWeaponZ"], "completion returns sorted bounded native names")
	check(console.completion("/set cg_mouseS") == ["/set cg_mouseSensitivity"], "explicit set command completes variable argument")
	check(console.completion("ordinary").is_empty() and console.completion("/cg_fov 7").is_empty(), "completion does not parse chat or numeric argument as cvar")
	var chat: CHAT = CHAT.new()
	chat.completion_callable = console.completion
	root.add_child(chat)
	chat.open(false)
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	chat.set_input_text("hello")
	check(chat.handle_input(tab) and chat.team_channel, "Tab in ordinary chat retains channel toggle behavior")
	chat.set_input_text("/cg_mouseS")
	check(chat.handle_input(tab) and chat.get_input_text() == "/cg_mouseSensitivity" and chat.team_channel, "Tab completes command without changing team/global channel")
	chat.set_input_text("/cg_viewWeapon")
	chat.handle_input(tab)
	check(chat.get_input_text() == "/cg_viewWeapon" and chat.completion_suggestions.size() == 3, "ambiguous completion preserves shared prefix and exposes suggestions")
	chat.set_input_text("/cg_mouseS", 4)
	chat.handle_input(tab)
	check(chat.get_input_text() == "/cg_mouseS" and chat.team_channel, "completion inside an edited command neither overwrites suffix nor toggles channel")
	chat.set_input_text("/no_such_variable")
	chat.handle_input(tab)
	check(chat.get_input_text() == "/no_such_variable" and chat.team_channel, "unknown command completion leaves draft and channel intact")
	chat.cancel_input()
	check(chat.completion_suggestions.is_empty(), "closing chat clears completion display")
	chat.free()
