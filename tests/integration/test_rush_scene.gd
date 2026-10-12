extends SceneTree
## Real Home -> Rush scene -> authoritative offer -> result -> one-click replay.
## Serial engine lease: godot --headless --path game --script ../tests/integration/test_rush_scene.gd
const SCENE = preload("res://scenes/offline_survival.tscn")
const SHELL = preload("res://scenes/game_shell.tscn")
const CATALOG = preload("res://ui/map_catalog.gd")
const SETTINGS = preload("res://gameplay/survival_settings.gd")
const ARENA = preload("res://ai/survival_arena.gd")
const PROFILES = preload("res://simulation/weapon_profiles.gd")
const RECORDS = preload("res://gameplay/rush_records.gd")
const OWNER_ID: int = 1
const WEAPON: int = 1
var checks: int = 0
var failures: int = 0
var app: Node3D
var shell: GameShell
var returned_home: Node
var backups: Dictionary[String, Dictionary] = {}
var launches: Array[Dictionary] = []
var classic_selection: Dictionary = {}


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("RUSH SCENE: " + label)


func frames(count: int) -> void:
	for index: int in count:
		await physics_frame
		await process_frame
		await create_timer(0.0).timeout


func action(id: String, pressed: bool) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = id
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func backup(path: String) -> void:
	var exists: bool = FileAccess.file_exists(path)
	backups[path] = {"exists": exists,
		"bytes": FileAccess.get_file_as_bytes(path) if exists else PackedByteArray()}


func restore() -> void:
	for path: String in backups:
		var snapshot: Dictionary = backups[path]
		if bool(snapshot.exists):
			var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
			check(file != null, "private preference/record backup can be restored: " + path)
			if file != null:
				file.store_buffer(snapshot.bytes)
				file.close()
		elif FileAccess.file_exists(path):
			check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK,
				"fixture-only preference/record file removed: " + path)


func run() -> void:
	backup(CATALOG.SETTINGS_PATH)
	backup(RECORDS.PATH)
	# A private test profile makes old saves/records unable to mask this wiring.
	var preferences: ConfigFile = ConfigFile.new()
	preferences.set_value("profile", "locale", "ru")
	preferences.set_value("profile", "name", "Rush scene fixture")
	preferences.set_value("ui", "touch_controls", 2)
	check(preferences.save(CATALOG.SETTINGS_PATH) == OK, "private scene profile seeded")
	if FileAccess.file_exists(RECORDS.PATH):
		check(DirAccess.remove_absolute(ProjectSettings.globalize_path(RECORDS.PATH)) == OK,
			"record starts independently of existing personal best")
	var classic: Dictionary = SETTINGS.defaults()
	classic.duration_seconds = 300
	classic.wave_interval_seconds = 45
	classic.zombies_per_wave = 4
	classic.growth_per_minute = 0.0
	classic.growth_mode = "constant"
	classic.zombie_damage = 27
	classic.zombie_block_damage = 62
	classic_selection = {"mode": "survival", "map_id": "mira_hq",
		"weapon": WEAPON, "survival": classic}
	check(CATALOG.save_selection(classic_selection) == OK, "different classic map and custom waves saved")
	await exercise()
	# Every guarded early return from exercise still reaches cleanup/restore.
	if is_instance_valid(shell): shell.queue_free()
	if is_instance_valid(app): app.queue_free()
	if is_instance_valid(returned_home): returned_home.queue_free()
	await frames(3)
	if has_meta("blockfield_launch"): remove_meta("blockfield_launch")
	LabInputBindings.release_actions()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	restore()
	print("RUSH SCENE: %d checks, %d failures" % [checks, failures])
	# Native audio owns real-time references even during accelerated headless frames.
	OS.delay_msec(80)
	quit(1 if failures else 0)


func exercise() -> void:
	shell = SHELL.instantiate()
	root.add_child(shell)
	shell.launch_requested.connect(func(configuration: Dictionary): launches.append(configuration.duplicate(true)))
	await frames(2)
	check(shell.get_display_state().page == "home", "real GameShell begins on Home")
	check(shell.get_selection() == classic_selection, "Home loads selected SMG and classic custom waves")
	check(CATALOG.load_selection() == classic_selection, "classic save exists before Rush")
	var rush_button: Button = shell.find_child("Rush", true, false) as Button
	check(rush_button != null and not rush_button.disabled, "Home has an enabled actual Rush button")
	if rush_button == null: return
	rush_button.pressed.emit()
	check(launches.size() == 1, "one Home button action emits one launch")
	if launches.size() != 1: return
	var configuration: Dictionary = launches[0]
	check(configuration == {"mode": "survival", "map_id": "crossroads", "weapon": WEAPON,
		"survival": SETTINGS.rush_defaults()}, "Home emits fixed Rush on Crossroads with current equipment")
	check(shell.get_selection() == classic_selection and CATALOG.load_selection() == classic_selection,
		"one-shot Rush leaves live and persisted classic selection unchanged")
	check(CATALOG.load_survival_settings() == classic_selection.survival,
		"one-shot Rush preserves custom classic survival settings")
	shell.queue_free()
	await frames(2)
	set_meta("blockfield_launch", configuration.duplicate(true))
	app = SCENE.instantiate()
	root.add_child(app)
	current_scene = app
	await wait_ready("initial Rush")
	if app.get_launch_state().status != "ready": return
	var session: OfflineSurvivalSession = app.session as OfflineSurvivalSession
	var inventory: Dictionary = PROFILES.get_info("0.75", WEAPON)
	check(not has_meta("blockfield_launch"), "launch metadata is consumed once by Main")
	check(app.offline_survival_mode and session.get_rush_state().enabled,
		"ordinary survival scene enters authoritative Rush")
	check(app.world.data == session.simulation.data,
		"Rush rendering and simulation use the same authoritative map")
	check(session.get_survival_state().settings == SETTINGS.rush_defaults(),
		"Main installs canonical Rush instead of persisted classic configuration")
	check(session.get_survival_state().phase == "preparation"
		and float(session.get_survival_state().preparation_remaining) > 4.5,
		"normal ready state begins five-second preparation")
	check(session.current_weapon == WEAPON and session.magazine == int(inventory.clip_size)
		and session.reserve == int(inventory.max_stock), "selected SMG receives finite ordinary inventory once")
	check(CATALOG.load_selection() == classic_selection
		and CATALOG.load_survival_settings() == classic_selection.survival,
		"real Main launch also preserves classic selection and custom wave settings")
	check(not app.hud.is_menu_open() and not session.paused and app.player.controls_enabled,
		"ready opens battle controls without another menu click")
	for index: int in 60:
		if session.get_owner_state().tool_raise >= 0.999: break
		await frames(1)
	check(session.get_owner_state().tool_raise >= 0.999, "actual selected weapon raises before firing")
	var initial_clip: int = session.magazine
	action("primary", true)
	await frames(4)
	action("primary", false)
	check(session.magazine < initial_clip, "real primary input consumes finite selected ammunition")
	# Use the production clock and director, without replacing the scene adapter.
	var phase_deadline: int = Time.get_ticks_msec() + 10000
	while session.phase == "preparation" and Time.get_ticks_msec() < phase_deadline:
		await frames(1)
	check(session.phase == "active", "five-second preparation admits the real active schedule")
	if session.phase != "active": return
	app.hud.set_mobile_controls_mode(1)
	await frames(2)
	check(app.hud.mobile_controls._enabled and app.player.controls_enabled,
		"actual touch controls are enabled before the offer")
	var projectile_id: int = make_projectile(session)
	check(projectile_id >= 0, "real grenadier creates a live shared projectile before threshold")
	if projectile_id < 0: return
	# Keep a primary action held into the threshold; the modal must release it.
	action("primary", true)
	for life: int in 3:
		var spawned: Dictionary = spawn_fixture_zombie(session, 12)
		check(bool(spawned.get("ok", false)), "real reusable zombie life admitted: %d" % life)
		if not bool(spawned.get("ok", false)): return
		session.simulation.damage_actor(12, 100.0, OWNER_ID, "fixture")
		await frames(2)
	var rush: Dictionary = session.get_rush_state()
	check(int(rush.kills) == 3 and bool(rush.pending), "three real life deaths create authoritative first offer")
	if not bool(rush.pending): return
	var panel: RushUpgradePanel = app.hud._rush_panel as RushUpgradePanel
	check(panel != null and panel.is_visible_in_tree(), "HUD renders the real choice overlay")
	check(not app.player.controls_enabled and not app.hud.mobile_controls._enabled
		and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "offer releases battle/touch control and cursor")
	check(not session.paused, "choice freeze belongs to authority, independently of pause menu")
	check(not Input.is_action_pressed("primary"), "held primary is released on modal entry")
	var frozen_tick: int = session.simulation.tick
	var frozen_state: Dictionary = session.get_survival_state()
	var frozen_positions: Dictionary[int, Vector3] = actor_positions(session)
	var projectile: SharedGrenadeState = session.simulation.grenades.get(projectile_id)
	check(projectile != null, "shared projectile is still alive at pending boundary")
	if projectile == null: return
	var projectile_position: Vector3 = projectile.position
	var projectile_tick: int = projectile.last_tick
	await frames(12)
	check(session.simulation.tick == frozen_tick and actor_positions(session) == frozen_positions,
		"choice freezes all actual actor ticks and positions for twelve scene frames")
	check(session.get_survival_state().elapsed_seconds == frozen_state.elapsed_seconds
		and session.get_survival_state().time_remaining == frozen_state.time_remaining,
		"active duration does not advance while choosing")
	check(projectile.position == projectile_position and projectile.last_tick == projectile_tick,
		"shared grenade flight and fuse clock share the offer boundary")
	app.hud.set_menu_visible(true)
	await frames(2)
	check(session.paused and not panel.is_visible_in_tree(), "pause menu hides pending choice and retains pause ownership")
	app.hud._survival_panel._resume.pressed.emit()
	await frames(2)
	check(not session.paused and panel.is_visible_in_tree() and not app.player.controls_enabled,
		"actual Resume button restores pending choice before battle input")
	app.hud._focused = false
	app.hud._sync_controls()
	await frames(2)
	check(session.paused and not panel.is_visible_in_tree() and not app.player.controls_enabled,
		"focus loss hides choice and disables battle")
	app.hud._focused = true
	app.hud._sync_controls()
	await frames(2)
	check(not session.paused and panel.is_visible_in_tree(), "focus restoration returns the same pending offer")
	var chosen: Button = panel.find_child("RushChoice0", true, false) as Button
	check(chosen != null and not chosen.disabled, "real first upgrade card is available")
	if chosen == null: return
	var clip_at_choice: int = session.magazine
	chosen.pressed.emit()
	await frames(12)
	rush = session.get_rush_state()
	check(not bool(rush.pending) and int(rush.levels.power) == 1,
		"actual card signal applies one authoritative firepower rank")
	check(not panel.is_visible_in_tree() and app.player.controls_enabled
		and app.hud.mobile_controls._enabled and not session.paused,
		"accepted choice restores battle/touch input")
	check(session.simulation.tick > frozen_tick and session.magazine == clip_at_choice
		and not Input.is_action_pressed("primary"), "resume advances rules without leaking the pre-choice primary action")
	action("primary", false)
	session.simulation.damage_actor(OWNER_ID, 100.0, 0, "fixture")
	await frames(3)
	check(session.finished and session.outcome == "defeat", "real owner death ends Rush")
	var result: Dictionary = app.hud._survival_panel.get_display_state()
	check(app.hud.is_menu_open() and bool(result.resume_disabled)
		and str(result.detail).contains("Личный рекорд"), "real result panel shows the recorded personal best")
	check(RECORDS.best(WEAPON) == int(session.get_rush_state().score)
		and RECORDS.best(0) == 0 and RECORDS.best(2) == 0,
		"result persists only the selected weapon's score")
	var epoch: int = session.simulation.epoch
	app.hud._survival_panel._restart.pressed.emit()
	# Closing the HUD menu/focus callbacks must not admit battle behind loading.
	# Global Escape separately cancels LaunchOverlay and is covered below.
	check(str(app.get_launch_state().status) in ["idle", "loading"]
		and not app.world.get_visual_preparation_stats().ready,
		"actual Repeat exposes pending restored terrain before ready")
	var replay_blocked: Dictionary = session.get_survival_state()
	replay_blocked.tick = session.simulation.tick
	app.hud.set_menu_visible(false)
	check(not app.player.controls_enabled and not app.hud.mobile_controls._enabled
		and session.paused, "closing the actual HUD menu cannot unpause a loading Rush replay")
	app.hud._focused = false
	app.hud._sync_controls()
	app.hud._focused = true
	app.hud._sync_controls()
	check(not app.player.controls_enabled and not app.hud.mobile_controls._enabled
		and session.paused, "focus cycle cannot bypass the restored-map launch gate")
	await wait_ready("Rush repeat", replay_blocked)
	check(session.simulation.epoch > epoch and session.current_weapon == WEAPON,
		"one actual Repeat button resets the match while retaining equipment")
	check(session.get_survival_state().settings == SETTINGS.rush_defaults()
		and str(app.get_launch_state().configuration.map_id) == "crossroads",
		"repeat retains the fixed preset and Crossroads")
	check(session.phase == "preparation" and not session.finished
		and float(session.get_survival_state().preparation_remaining) > 4.5
		and session.get_rush_state().levels == {"power": 0, "armor": 0, "field_kit": 0},
		"repeat resets perks, life and five-second preparation")
	check(not app.hud.is_menu_open() and not session.paused and app.player.controls_enabled,
		"ready repeat resumes automatically after restored terrain preparation")
	check(app.world.get_visual_preparation_stats().ready
		and CATALOG.load_selection() == classic_selection
		and CATALOG.load_survival_settings() == classic_selection.survival,
		"repeat prepares terrain and still preserves the saved classic setup")
	# A separate final replay exercises intentional Escape -> Home cancellation,
	# including deferred launch/layout callbacks after Main leaves the tree.
	app.hud.set_menu_visible(true)
	app.hud._survival_panel._restart.pressed.emit()
	check(str(app.get_launch_state().status) in ["idle", "loading"],
		"last actual replay is pending before global Escape cancellation")
	action("pause", true)
	action("pause", false)
	var home_deadline: int = Time.get_ticks_msec() + 5000
	while (is_instance_valid(app) or current_scene == null) and Time.get_ticks_msec() < home_deadline:
		await frames(1)
	await frames(3)
	check(not is_instance_valid(app), "real loading Escape frees the canceled Rush scene")
	returned_home = current_scene
	check(is_instance_valid(returned_home)
		and returned_home.scene_file_path == "res://scenes/entry.tscn",
		"real loading Escape returns to Entry without waiting for resource warming")
	var home_shell: GameShell = returned_home.get("_screen") as GameShell if is_instance_valid(returned_home) else null
	check(is_instance_valid(home_shell) and home_shell.get_display_state().page == "home",
		"canceled loading shows the real GameShell Home")
	check(CATALOG.load_selection() == classic_selection
		and CATALOG.load_survival_settings() == classic_selection.survival,
		"canceling replay preserves saved classic selection and custom waves")


func wait_ready(label: String, blocked_clock: Dictionary = {}) -> void:
	var deadline: int = Time.get_ticks_msec() + 35000
	var loading_clock_safe: bool = true
	while str(app.get_launch_state().status) in ["idle", "loading"] and Time.get_ticks_msec() < deadline:
		if not blocked_clock.is_empty():
			var session: OfflineSurvivalSession = app.session as OfflineSurvivalSession
			var clock: Dictionary = session.get_survival_state()
			loading_clock_safe = loading_clock_safe and session.paused and not app.player.controls_enabled \
				and session.simulation.tick == int(blocked_clock.tick) \
				and clock.phase == blocked_clock.phase \
				and clock.preparation_remaining == blocked_clock.preparation_remaining \
				and clock.elapsed_seconds == blocked_clock.elapsed_seconds
		await frames(1)
	if not blocked_clock.is_empty():
		check(loading_clock_safe, "HUD menu/focus replay keeps actual ticks and phase clocks frozen until ready")
	check(app.get_launch_state().status == "ready", label + " reaches ready within launch budget")
	if app.get_launch_state().status == "ready":
		check(app.world.get_visual_preparation_stats().ready
			and app.world.get_rebuild_stats().pending_chunks == 0
			and not app.world.get_rebuild_stats().active_build,
			label + " finishes restored initial terrain before battle admission")


func spawn_fixture_zombie(session: OfflineSurvivalSession, id: int) -> Dictionary:
	for point: Vector3 in ARENA.metadata().spawn_sectors:
		var floor_cell: Vector3i = Vector3i(floori(point.x), floori(point.y) - 1, floori(point.z))
		if session.simulation.data.get_block(floor_cell) == 0: continue
		if not session.simulation._spawn_clear(point): continue
		return session.simulation.spawn_zombie_slot(id, point)
	return {"ok": false, "error": "No supported fixture sector"}


func make_projectile(session: OfflineSurvivalSession) -> int:
	var spawned: Dictionary = spawn_fixture_zombie(session, 13)
	if not bool(spawned.get("ok", false)): return -1
	if not session.simulation.assign_zombie_type(13, "grenadier"): return -1
	var actor: SharedPlayerState = session.simulation.get_actor(13)
	for direction: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var target: Vector3 = actor.feet() + Vector3.UP * 1.1 + direction * 10.0
		var events: Array[Dictionary] = session.simulation.throw_zombie_grenade(13, target, 15, 40)
		if not events.is_empty():
			var ids: Array = session.simulation.grenades.keys()
			return int(ids[-1])
	return -1


func actor_positions(session: OfflineSurvivalSession) -> Dictionary[int, Vector3]:
	var positions: Dictionary[int, Vector3] = {}
	for id: int in session.simulation.actors:
		positions[id] = session.simulation.get_actor(id).feet()
	return positions
