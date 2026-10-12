extends SceneTree
## Actual launch, controller, authority map and zombie presentation lifecycle.
const SCENE = preload("res://scenes/offline_survival.tscn")
const ARENA = preload("res://ai/survival_arena.gd")
const SETTINGS = preload("res://gameplay/survival_settings.gd")
var checks: int = 0
var failures: int = 0
var app: Node3D
var saved: PackedByteArray
var had_settings: bool = false

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SURVIVAL SCENE: " + label)

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

func run() -> void:
	had_settings = FileAccess.file_exists("user://settings.cfg")
	if had_settings: saved = FileAccess.get_file_as_bytes("user://settings.cfg")
	var preferences: ConfigFile = ConfigFile.new()
	preferences.set_value("profile", "locale", "ru")
	preferences.set_value("ui", "touch_controls", 2)
	preferences.save("user://settings.cfg")
	var settings: Dictionary = SETTINGS.defaults()
	settings.duration_seconds = 60
	settings.zombies_per_wave = 2
	set_meta("blockfield_launch", {"mode": "survival", "map_id": "crossroads", "weapon": 2, "survival": settings})
	app = SCENE.instantiate()
	root.add_child(app)
	current_scene = app
	var launch_deadline: int = Time.get_ticks_msec() + 35000
	while app.get_launch_state().status == "loading" and Time.get_ticks_msec() < launch_deadline:
		await frames(1)
	var session: OfflineSurvivalSession = app.session
	check(app.get_launch_state().status == "ready", "ordinary selected survival reaches ready")
	check(app.world.get_visual_preparation_stats().ready and app.world.get_rebuild_stats().pending_chunks == 0 and not app.world.get_rebuild_stats().active_build,
		"ordinary survival finishes initial terrain before enabling combat")
	check(not has_meta("blockfield_launch"), "launch metadata consumed once")
	check(app.offline_survival_mode and session.mode == "survival", "new adapter, not TDM score policy")
	check(app.world.data == session.simulation.data, "one authoritative map is adopted by renderer")
	check(session.current_weapon == 2 and session.magazine == 6, "actual starting shotgun granted once")
	check(session.get_survival_state().phase == "preparation", "production launch starts twenty-second preparation")
	check(not app.hud.is_menu_open() and not session.paused, "normal launch opens controls")
	var start: Vector3 = session.get_owner_state().feet()
	action("forward", true)
	await frames(12)
	action("forward", false)
	check(session.get_owner_state().feet().distance_to(start) > 0.1, "normal movement controls reach shared authority")
	for index: int in range(20):
		if session.get_owner_state().tool_raise >= .999: break
		await frames(1)
	check(session.get_owner_state().tool_raise >= .999, "selected weapon finishes its ordinary raise before fire")
	action("primary", true)
	await frames(3)
	action("primary", false)
	check(session.magazine < 6, "normal fire uses finite selected magazine")
	app.hud.set_menu_visible(true)
	var paused_tick: int = session.simulation.tick
	await frames(12)
	check(session.simulation.tick == paused_tick, "pause freezes preparation and world rules")
	check(app.hud._survival_panel.get_display_state().title == "Выживание", "survival panel replaces team menu")
	# Explicit short test contract exercises the same real scene without waiting a
	# ten-minute authority clock; launch validation never admits this override.
	var fast: Dictionary = SETTINGS.defaults()
	fast.duration_seconds = 5
	fast.wave_interval_seconds = 2
	fast.preparation_seconds = 0
	fast.zombies_per_wave = 3
	fast.live_limit = 4
	var configured: Dictionary = session.configure_survival(ARENA.build(), ARENA.metadata(), fast, "Player", true)
	check(configured.ok, "short fixture reconfigures real authority explicitly")
	app._clear_match_views()
	app.world.set_map_data(configured.data, "Crossroads · Выживание", true)
	app._create_survival_supply_views()
	app.hud.set_menu_visible(false)
	await frames(75)
	check(session.get_survival_state().wave >= 1 and session.get_survival_state().live > 0, "real fixed updates admit a timed wave")
	check(app._zombie_views.size() > 0 and app._target_nodes.is_empty(), "foes use unarmed zombie views without soldier hit Areas")
	check(app._corpses.is_empty(), "no soldier corpse is manufactured for zombie views")
	check(app.hud._combat_readout.survival_text.contains("ВОЛНА"), "combat display supplies wave state")
	var before_epoch: int = session.simulation.epoch
	var count: int = app._zombie_views.size()
	app.hud.set_menu_visible(true)
	await frames(5)
	for view: ZombieView in app._zombie_views.values():
		check(view.get_display_state().paused, "zombie presentation pauses with authority")
	app.restart_offline_tdm()
	await frames(4)
	check(session.simulation.epoch > before_epoch and app._zombie_views.size() <= count, "retry restores map/lives and clears old views")
	check(session.get_survival_state().wave == 0 and session.paused, "restart resets schedule and waits for Resume")
	check(app._survival_supply_views.size() == 2, "one supply marker and caption remain bounded")
	app.hud.set_menu_visible(false)
	var owner: SharedPlayerState = session.simulation.get_actor(1)
	session.simulation.damage_actor(1, 100, 0, "fixture")
	await frames(3)
	check(session.finished and session.get_survival_state().outcome == "defeat", "owner death ends attempt instead of respawning")
	check(app.hud.is_menu_open() and app.hud._survival_panel.get_display_state().resume_disabled, "result opens and cannot resume a defeated life")
	check(not owner.is_alive(), "defeated owner remains dead")
	app.queue_free()
	await frames(3)
	LabInputBindings.release_actions()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if had_settings:
		var file: FileAccess = FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		file.store_buffer(saved)
		file.close()
	else: DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	print("SURVIVAL SCENE: %d checks, %d failures" % [checks, failures])
	# Fixed-FPS headless frames can run faster than the native audio mixer.
	# Let stopped playback references leave its real-time callback before exit.
	OS.delay_msec(80)
	quit(1 if failures else 0)
