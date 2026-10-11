extends SceneTree
## Actual scene readout, source session behavior, localization and responsive HUD.
## The coordinator owns the serial engine lease; this script preserves preferences.
const LAB_SCENE = preload("res://scenes/main.tscn")
const TDM_SCENE = preload("res://scenes/offline_tdm.tscn")
const COMBAT_THEME = preload("res://ui/combat_theme.gd")
const FILES: Array[String] = ["user://settings.cfg", "user://servers.cfg"]
var assertions: int = 0
var failures: int = 0
var app: Node3D
var hud: LabHUD
var session: LocalSession
var readout: Control
var saved: Dictionary = {}
var globals: Dictionary = {}


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("COMBAT HUD: " + message)


func frames(count: int) -> void:
	for frame in count:
		await process_frame
		await create_timer(0.0).timeout


func state() -> Dictionary:
	return readout.call("get_display_state")


func refresh() -> void:
	hud._process(0.0)
	readout.queue_redraw()


func remember() -> void:
	for path: String in FILES:
		var exists := FileAccess.file_exists(path)
		saved[path] = {"exists": exists, "bytes": FileAccess.get_file_as_bytes(path) if exists else PackedByteArray()}
	globals = {"size": root.size, "scale_size": root.content_scale_size,
		"scale_aspect": root.content_scale_aspect, "scale_mode": root.content_scale_mode,
		"scale_factor": root.content_scale_factor, "mouse_mode": Input.mouse_mode,
		"emulation": Input.emulate_mouse_from_touch, "locale": TranslationServer.get_locale()}


func run() -> void:
	remember()
	var preferences := ConfigFile.new()
	preferences.set_value("profile", "locale", "ru")
	preferences.set_value("ui", "touch_controls", 2)
	preferences.set_value("ui", "hidden", false)
	check(preferences.save(FILES[0]) == OK, "temporary preferences are written")
	await create_scene(LAB_SCENE)
	if readout != null:
		await test_session_readout()
		await test_lifecycle()
		await test_layouts()
		test_font()
	await free_scene()
	await create_scene(TDM_SCENE)
	if readout != null:
		check(session.mode == "tdm", "team battle uses the same readout through its real adapter")
		check(readout.is_visible_in_tree() and state().live, "team battle alive owner has visible vitals and ammo")
		check(int(state().health) == session.health and int(state().ammo) == session.magazine,
			"team battle readout mirrors its authoritative owner values")
		await resize_and_check(Vector2i(390, 844), true, "team battle portrait")
		await resize_and_check(Vector2i(844, 390), true, "team battle landscape")
		await resize_and_check(Vector2i(390, 844), true, "team battle portrait large controls", false, 1.4)
		await resize_and_check(Vector2i(844, 390), true, "team battle landscape large controls", false, 1.4)
		await resize_and_check(Vector2i(390, 844), true, "team battle mirrored portrait large controls", true, 1.4)
		await resize_and_check(Vector2i(844, 390), true, "team battle mirrored landscape large controls", true, 1.4)
	await free_scene()
	await restore()
	print("COMBAT HUD: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func create_scene(scene: PackedScene) -> void:
	app = scene.instantiate()
	root.add_child(app)
	await frames(5)
	hud = app.get_node("HUD")
	session = app.get_node("LocalSession")
	readout = hud.get("_combat_readout")
	check(readout != null and readout.has_method("get_display_state") and readout.has_method("get_panel_rects"),
		"actual HUD owns the modern readout and its drawing state")
	if readout == null:
		return
	app.set_locale("ru")
	hud.set_mobile_controls_mode(2)
	hud.set_menu_visible(false)
	# Keep real session/controller/HUD connections; stop frame-driven authority
	# so deliberately staged health/reload states stay stable during inspection.
	app.set_process(false)
	app.set_physics_process(false)
	app.get_node("Player").set_process(false)
	app.get_node("Player").set_physics_process(false)
	hud.set_process(false)
	refresh()
	await frames(2)
	check(readout.mouse_filter == Control.MOUSE_FILTER_IGNORE, "combat readout leaves gameplay input available")
	check(is_zero_approx(hud._stats.self_modulate.a) and is_zero_approx(hud._ammo.self_modulate.a)
		and is_zero_approx(hud._weapon_icon.self_modulate.a), "legacy values remain semantic only and do not duplicate the modern HUD")


func test_session_readout() -> void:
	session.invulnerable = false
	session.unlimited_ammo = false
	session.select_team(0)
	session.damage_player(63.0)
	session.blocks = 17
	session.grenades = 2
	refresh()
	var shown := state()
	check(shown.health == 37 and shown.blocks == 17 and shown.grenades == 2,
		"health damage and both resource stocks reach the actual readout")
	for weapon: int in [LocalSession.Weapon.RIFLE, LocalSession.Weapon.SMG, LocalSession.Weapon.SHOTGUN]:
		session.select_weapon(weapon)
		var info := session.get_weapon_info()
		refresh()
		shown = state()
		check(shown.weapon_label == OpenSpadesLocalization.text(str(info.name), "Client").to_upper(),
			"selected firearm keeps its translated name: " + str(info.name))
		check(shown.tool == LocalSession.Tool.WEAPON and shown.ammo == session.magazine and shown.reserve == session.reserve,
			"selected firearm shows real loaded and reserve rounds: " + str(info.name))
		var magazine_before := session.magazine
		check(session.fire(), "session accepts a shot for readout verification: " + str(info.name))
		refresh()
		check(state().ammo == magazine_before - 1, "accepted shot immediately updates loaded rounds: " + str(info.name))
		session.reload_weapon()
		session.update(float(info.reload_time) * 0.25)
		refresh()
		check(session.is_reloading and absf(float(state().reload_progress) - 0.25) < 0.0001,
			"reload progress follows the real session clock: " + str(info.name))
		check(not str(readout.get("status_text")).is_empty() and str(readout.get("status_text")) == hud._weapon_status.text,
			"reload explanation reaches the drawn readout alongside ammunition")
		session.select_tool(LocalSession.Tool.SPADE)
		refresh()
		check(float(state().reload_progress) < 0.0, "changing tools clears completed or cancelled reload progress")
	for tool: int in [LocalSession.Tool.SPADE, LocalSession.Tool.BLOCK, LocalSession.Tool.GRENADE]:
		session.select_tool(tool)
		refresh()
		shown = state()
		check(shown.tool == tool and not str(shown.weapon_label).is_empty(), "each original tool has its own readable selection: " + str(tool))
		check(shown.blocks == session.blocks and shown.grenades == session.grenades,
			"tool selection retains both actual inventory stocks")
	session.select_tool(LocalSession.Tool.BLOCK)
	var blocks_before := session.blocks
	check(session.use_block(2), "session accepts a block resource action")
	refresh()
	check(state().blocks == blocks_before - 2, "building consumption reaches the modern resource counter")
	session.select_tool(LocalSession.Tool.GRENADE)
	var grenades_before := session.grenades
	check(session.begin_grenade_cook(), "session accepts a grenade cook action")
	session.update(0.5)
	refresh()
	check(not str(readout.get("status_text")).is_empty(), "held grenade fuse reaches the drawn tool status")
	var released: Dictionary = session.release_grenade()
	check(not released.is_empty(), "session releases a held grenade")
	refresh()
	check(state().grenades == grenades_before - 1, "throwing consumption reaches the modern grenade counter")
	session.select_weapon(LocalSession.Weapon.RIFLE)
	session.magazine = 0
	session.reserve = 0
	refresh()
	check(state().ammo == 0 and state().reserve == 0 and state().ammo_warning,
		"an empty firearm shows both zero stocks and an ammo warning")
	check(not str(readout.get("status_text")).is_empty(), "empty firearm has a readable explanation in the new readout")
	session.respawn()
	refresh()
	check(not state().ammo_warning, "restored ammunition clears the empty warning")
	app.set_locale("en_US")
	refresh()
	check(state().weapon_label == "RIFLE", "locale changes update the drawn weapon name")
	app.set_locale("ru")
	refresh()
	check(state().weapon_label == "ВИНТОВКА", "Russian weapon name survives the modern font path")
	await frames(1)


func test_lifecycle() -> void:
	session.select_team(0)
	refresh()
	check(readout.is_visible_in_tree() and state().live, "alive owner sees the combat readout")
	session.damage_player(1000.0)
	refresh()
	check(readout.is_visible_in_tree() and not state().live, "dead state gates live islands while retaining the match score layer")
	check(not hud._state_hint.text.is_empty(), "dead state retains the respawn explanation")
	session.respawn()
	refresh()
	check(readout.is_visible_in_tree() and state().health == 100, "respawn restores the readout with replenished health")
	session.select_team(2)
	refresh()
	check(readout.is_visible_in_tree() and not state().live, "spectator gates private vitals and stock while retaining the match score layer")
	check(not hud._state_hint.text.is_empty(), "spectator retains camera instructions")
	session.select_team(0)
	refresh()
	hud.set_menu_visible(true)
	check(not readout.is_visible_in_tree(), "opening the menu hides combat presentation")
	hud.set_menu_visible(false)
	refresh()
	hud.set_hud_hidden(true)
	check(not readout.is_visible_in_tree(), "hide-HUD preference applies to the new readout")
	hud.set_hud_hidden(false)
	refresh()
	check(readout.is_visible_in_tree(), "show-HUD restores the new readout")
	hud.open_chat()
	check(readout.is_visible_in_tree() and not app.get_node("Player").controls_enabled,
		"chat owns input while leaving combat information readable")
	hud._chat.cancel_input()
	hud._sync_controls()
	await frames(1)


func test_layouts() -> void:
	await resize_and_check(Vector2i(1280, 720), false, "desktop")
	await resize_and_check(Vector2i(2560, 1080), false, "ultrawide")
	await resize_and_check(Vector2i(390, 844), true, "portrait")
	await resize_and_check(Vector2i(844, 390), true, "landscape")
	await resize_and_check(Vector2i(390, 844), true, "portrait large controls", false, 1.4)
	await resize_and_check(Vector2i(844, 390), true, "landscape large controls", false, 1.4)
	await resize_and_check(Vector2i(390, 844), true, "mirrored portrait", true)
	await resize_and_check(Vector2i(390, 844), true, "mirrored portrait large controls", true, 1.4)
	await resize_and_check(Vector2i(844, 390), true, "mirrored landscape large controls", true, 1.4)
	hud.left_handed_touch = false
	hud.touch_control_scale = 1.0
	hud.set_mobile_controls_mode(2)


func resize_and_check(extent: Vector2i, mobile: bool, description: String, mirrored: bool = false, control_scale: float = 1.0) -> void:
	root.size = extent
	if not mobile:
		hud._desktop_scale = extent
	hud.floating_stick = false
	hud.left_handed_touch = mirrored
	hud.touch_control_scale = control_scale
	hud.set_mobile_controls_mode(1 if mobile else 2)
	hud._update_mobile_layout()
	hud._apply_touch_preferences()
	await frames(3)
	refresh()
	check(bool(readout.get("compact")) == mobile, description + " selects the correct readout density")
	var viewport_rect := root.get_visible_rect()
	var panels: Array = readout.call("get_panel_rects")
	check(panels.size() == 2, description + " has separate vitals and ammunition islands")
	var global_panels: Array[Rect2] = []
	for panel: Rect2 in panels:
		var rectangle := Rect2(readout.global_position + panel.position, panel.size)
		global_panels.append(rectangle)
		check(viewport_rect.grow(0.1).encloses(rectangle), description + " panel stays inside the logical viewport")
		check(not rectangle.intersects(hud._map.get_global_rect()), description + " panel does not cover the minimap")
	if global_panels.size() == 2:
		check(not global_panels[0].intersects(global_panels[1]), description + " vitals and ammunition remain separate")
	if mobile:
		var regions: Dictionary = hud.mobile_controls.get_hit_regions()
		check(hud.mobile_controls.visible and regions.has("primary") and regions.has("reload"), description + " actual touch overlay is active")
		check(is_equal_approx(float(hud.mobile_controls.get("control_scale")), control_scale),
			description + " actual touch overlay receives the chosen control size")
		var actions: Dictionary = hud.mobile_controls.call("get_action_rects")
		var map_frame := hud._map_frame.get_global_rect()
		check(viewport_rect.grow(0.1).encloses(map_frame), description + " complete minimap frame stays inside the logical viewport")
		check(actions.size() == 13, description + " minimap placement checks all13 actual action buttons")
		for name: String in actions:
			var action: Rect2 = actions[name]
			var global_action := Rect2(hud.mobile_controls.global_position + action.position, action.size)
			check(not map_frame.intersects(global_action), description + " minimap frame stays clear of touch " + name)
		for rectangle: Rect2 in global_panels:
			for name: String in ["primary", "reload", "jump", "crouch", "sprint", "move"]:
				if regions.has(name):
					check(not rectangle.intersects(regions[name]), description + " readout stays clear of touch " + name)
		if session.mode == "tdm":
			check_match_score_layout(description, viewport_rect, global_panels)


func check_match_score_layout(description: String, viewport_rect: Rect2, islands: Array[Rect2]) -> void:
	var score: String = str(readout.get("score_text"))
	check(not score.is_empty() and score == hud._tdm_score.text, description + " drawn score receives the real match score and clock")
	# CombatReadout's compact score drawing uses a204×32 island. The wide
	# invisible semantic Label is not its rendering or collision footprint.
	var score_y: float = float(readout.get("score_y"))
	var rectangle := Rect2(readout.global_position + Vector2((readout.size.x - 204.0) * 0.5, score_y), Vector2(204, 32))
	check(viewport_rect.grow(0.1).encloses(rectangle), description + " score stays inside the logical viewport")
	check(is_equal_approx(rectangle.get_center().x, viewport_rect.get_center().x), description + " match score remains centered")
	var toolbar_bottom: float = float(hud.mobile_controls.call("get_layout_height"))
	check(rectangle.position.y >= hud.mobile_controls.global_position.y + toolbar_bottom + 7.9,
		description + " score clears the actual scaled tool and utility band")
	check(not rectangle.intersects(hud._map_frame.get_global_rect()), description + " score does not cover the complete minimap frame")
	for island: Rect2 in islands:
		check(not rectangle.intersects(island), description + " score remains separate from resources and ammunition")
	var actions: Dictionary = hud.mobile_controls.call("get_action_rects")
	check(actions.size() == 13, description + " placement checks all13 actual tool utility and combat buttons")
	for name: String in actions:
		var action: Rect2 = actions[name]
		var global_action := Rect2(hud.mobile_controls.global_position + action.position, action.size)
		check(not rectangle.intersects(global_action), description + " score stays clear of touch " + name)


func test_font() -> void:
	var font: Font = COMBAT_THEME.font()
	check(font != null, "combat font is loaded")
	if font == null:
		return
	for code: int in [0x0030, 0x0039, 0x0041, 0x0412, 0x0438, 0x4e2d, 0x65e5, 0xd55c]:
		check(font.has_char(code), "combat font preserves Latin/Cyrillic and original multilingual fallback: %x" % code)
	check(font.get_string_size("ВИНТОВКА", HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x > 50.0,
		"modern font shapes the selected Russian weapon name")
	check(font.get_string_size("中文 日本語 한국어", HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x > 50.0,
		"multilingual fallback still shapes original supported locale text")


func free_scene() -> void:
	if app == null:
		return
	LabInputBindings.release_actions()
	app.stop_audio()
	await frames(2)
	var reference: WeakRef = weakref(app)
	app.queue_free()
	await frames(4)
	check(reference.get_ref() == null, "actual scene is released before the next scene or exit")
	app = null
	hud = null
	session = null
	readout = null


func restore() -> void:
	var deadline := Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
		await process_frame
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
