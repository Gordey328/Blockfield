extends SceneTree
## Actual Main/HUD/controller, fixed authority and five AI actors; no socket server.
## godot --headless --path game --fixed-fps 60 --script ../tests/integration/test_offline_tdm_scene.gd
const TDM_SCENE = preload("res://scenes/offline_tdm.tscn")
const LAB_SCENE = preload("res://scenes/main.tscn")
var assertions: int = 0
var failures: int = 0
var app: Node3D
var before: Dictionary = {}
var events: Array[Dictionary] = []
var hurt_events: int = 0
var death_events: int = 0
var respawn_events: int = 0
var baseline_blocks: PackedInt32Array = PackedInt32Array()


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("OFFLINE TDM SCENE: " + message)


func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame
		# Sample after node physics and presentation callbacks, not their signal.
		await create_timer(0.0).timeout


func action(name: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func release_actions() -> void:
	for name: String in ["forward", "back", "left", "right", "primary", "secondary", "jump", "crouch", "sprint", "reload", "pause"]:
		action(name, false)


func nodes_below(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in node.get_children():
		result.append(child)
		result.append_array(nodes_below(child))
	return result


func press_menu(caption: String) -> void:
	var button: Button
	for node: Node in nodes_below(app.hud):
		if node is Button and node.text == caption:
			button = node
			break
	check(button != null, "actual menu exposes: " + caption)
	if button != null:
		button.pressed.emit()


func owner() -> SharedPlayerState:
	return app.session.simulation.get_actor(app.session.local_player_id())


func _run() -> void:
	seed(9347)
	for path: String in ["user://settings.cfg", "user://servers.cfg"]:
		var exists := FileAccess.file_exists(path)
		before[path] = {"exists": exists, "bytes": FileAccess.get_file_as_bytes(path) if exists else PackedByteArray()}
	app = TDM_SCENE.instantiate()
	root.add_child(app)
	app.set_locale("ru")
	app.hud.set_mobile_controls_mode(2)
	app.session.match_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
	app.session.player_hurt.connect(func(_amount: float, _origin: Vector3, _kind: String): hurt_events += 1)
	app.session.player_died.connect(func(): death_events += 1)
	app.session.player_respawned.connect(func(): respawn_events += 1)
	await frames(4)
	baseline_blocks = app.world.data.blocks.duplicate()
	await startup_and_input()
	await bot_combat()
	await damage_and_respawn()
	await end_and_restart()
	await cleanup_scene()
	await normal_lab_regression()
	release_actions()
	var drain_deadline := Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < drain_deadline:
		OS.delay_msec(1)
		await process_frame
	for path: String in before:
		if before[path].exists:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(before[path].bytes)
			file.close()
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("OFFLINE TDM SCENE: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func startup_and_input() -> void:
	var diagnostics: Dictionary = app.session.get_diagnostics()
	check(app.offline_tdm_mode and not app.network_mode and app.network_client == null, "TDM scene starts serverless without a network client")
	check(app.session.mode == "tdm" and app.session.simulation.actors.size() == 6, "actual scene admits one human and five bots to the shared authority")
	check(diagnostics.bot_count == 5 and diagnostics.team_counts == [3, 3], "roster is exactly three versus three")
	check(app.session.targets.size() == 5 and app._target_nodes.size() == 5, "presentation has five bot soldiers and no lab display actors")
	check(app.world.data == app.session.simulation.data, "world presentation and authority share one writable voxel map")
	check(app.hud.is_menu_open() and not app.player.controls_enabled and app.session.paused, "entry menu pauses the entire match and gates gameplay")
	var tick: int = app.session.simulation.tick
	var magazine: int = owner().magazine
	action("primary", true)
	action("forward", true)
	await frames(12)
	release_actions()
	app.session.update(.5)
	check(app.session.simulation.tick == tick and owner().magazine == magazine, "paused input and presentation update cannot advance authority or consume ammunition")
	var copied: SharedPlayerState = app.session.get_owner_state()
	copied.magazine = 0
	check(owner().magazine == magazine, "controller owner snapshot cannot mutate authoritative ammunition")
	press_menu("Начать матч 3×3")
	await frames(3)
	check(not app.hud.is_menu_open() and app.player.controls_enabled and not app.session.paused, "start button enters a live offline match")
	var start: Vector3 = owner().feet()
	action("forward", true)
	await frames(15)
	action("forward", false)
	check(owner().feet().distance_to(start) > .2, "ordinary forward input moves the shared local actor")
	check(app.player.global_position.distance_to(owner().feet()) < .001, "actual rendered player adopts the shared authoritative feet")
	for unused in 120:
		if app.player.can_use_tool() and owner().is_alive():
			break
		await frames(1)
	magazine = owner().magazine
	var shots: int = app.session.shots_fired
	action("primary", true)
	await frames(2)
	action("primary", false)
	check(owner().magazine == magazine - 1 and app.session.magazine == owner().magazine, "normal rifle trigger consumes one round once in shared authority")
	check(app.session.shots_fired == shots + 1, "normal trigger produces one confirmed local shot")
	action("pause", true)
	action("pause", false)
	await frames(2)
	tick = app.session.simulation.tick
	check(app.hud.is_menu_open() and app.session.paused, "Escape opens the real pause menu")
	await frames(24)
	check(app.session.simulation.tick == tick, "pause stops human and all five bot authority steps")
	press_menu("Продолжить")
	await frames(2)
	check(app.session.simulation.tick > tick and app.player.controls_enabled, "resume button advances the same live match")


func bot_combat() -> void:
	# An unmodified arena and normal controller frames exercise real commands.
	# Attempt counters alone cannot establish accepted firearm execution.
	await frames(1200)
	var diagnostics: Dictionary = app.session.get_diagnostics()
	var bot_diagnostics: Dictionary = diagnostics.bots
	var moved: int = 0
	for bot: Dictionary in bot_diagnostics.bots:
		if float(bot.distance_moved) > 2.0:
			moved += 1
	var local_id: int = app.session.local_player_id()
	var accepted_shots: int = events.filter(func(event: Dictionary) -> bool:
		return event.type == "shot" and int(event.get("owner_id", local_id)) != local_id).size()
	check(moved == 5, "every bot physically travels through voxel collision on the ordinary arena")
	check(bot_diagnostics.fire_commands > 0 and accepted_shots > 0, "AI commands produce accepted shared firearm events")
	check(bot_diagnostics.cover_decisions > 0, "ordinary combat makes bots choose cover")
	check(bot_diagnostics.flank_decisions > 0, "ordinary combat makes bots choose a flank")
	check(bot_diagnostics.navigation.path_requests > 0, "movement uses planned bounded voxel routes")
	check(app._target_nodes.size() == 5 and app.session.simulation.actors.size() == 6, "combat and respawns do not duplicate actors or soldier views")
	for soldier: LabSoldier in app._target_nodes:
		var actor: SharedPlayerState = app.session.simulation.get_actor(soldier.target_id)
		check(actor != null and soldier.position.distance_to(actor.feet()) < .001, "rendered bot follows its live authority position: %d" % soldier.target_id)
	var deaths: int = 0
	for actor: SharedPlayerState in app.session.simulation.actors.values():
		deaths += actor.deaths
	check(deaths > 0 and app.session.team_scores[0] + app.session.team_scores[1] > 0, "unassisted bots cause authoritative deaths and team kill scores")
	print("OFFLINE TDM BOTS: " + JSON.stringify(diagnostics))


func damage_and_respawn() -> void:
	release_actions()
	app.hud.set_menu_visible(true)
	press_menu("Новый матч")
	await frames(3)
	check(app.session.team_scores == [0, 0] and app.session.winning_team == -1, "menu restart clears live team scores and winner")
	press_menu("Начать матч 3×3")
	await frames(3)
	var local := owner()
	var generation: int = local.spawn_generation
	var initial_hurt: int = hurt_events
	var initial_deaths: int = death_events
	var initial_respawns: int = respawn_events
	var enemy: int = 0
	var friend: int = 0
	for actor: SharedPlayerState in app.session.simulation.actors.values():
		if actor.player_id == local.player_id:
			continue
		if actor.team == local.team:
			friend = actor.player_id
		else:
			enemy = actor.player_id
	app.session.simulation.damage_actor(local.player_id, 20, friend)
	check(local.health == 100, "shared TDM policy rejects friendly damage")
	app.session.simulation.damage_actor(local.player_id, 30, enemy)
	await frames(1)
	check(local.health == 70 and app.session.health == 70 and hurt_events == initial_hurt + 1, "authoritative enemy hurt reaches the actual local adapter once")
	app.session.simulation.damage_actor(local.player_id, 100, enemy)
	await frames(2)
	check(app.session.health == 0 and death_events == initial_deaths + 1, "authoritative enemy death reaches the local presentation once")
	check(app.player.camera_mode == BlockfieldPlayer.CameraMode.DEATH and is_instance_valid(app._last_player_corpse), "actual controller uses death camera and creates a corpse")
	check(app.session.team_scores[1] == 1 and app.session.player_deaths == 1, "one enemy kill credits one team point and one local death")
	for unused in 240:
		if owner().spawn_generation > generation:
			break
		await frames(1)
	check(owner().spawn_generation > generation and app.session.health > 0 and respawn_events == initial_respawns + 1, "ordinary fixed frames respawn the local player with a new life")
	check(app.player.global_position.distance_to(owner().feet()) < .001 and app.player.camera_mode == BlockfieldPlayer.CameraMode.FIRST_PERSON, "respawn adopts arena spawn and restores the first person camera")
	check(app.session.team_scores[1] == 1, "respawn does not credit the same kill twice")


func end_and_restart() -> void:
	release_actions()
	app.hud.set_menu_visible(true)
	press_menu("Новый матч")
	await frames(2)
	app.session.kill_limit = 1
	press_menu("Начать матч 3×3")
	await frames(2)
	var victim: int = 0
	for actor: SharedPlayerState in app.session.simulation.actors.values():
		if actor.team == 1:
			victim = actor.player_id
	app.session.simulation.damage_actor(victim, 100, app.session.local_player_id())
	await frames(2)
	check(app.session.finished and app.session.winning_team == 0 and app.session.team_scores == [1, 0], "the first confirmed enemy kill reaches the configured team kill limit")
	check(app.hud._results.text.contains("Син") or app.hud._results.text.contains("Blue"), "the real HUD identifies the winning team")
	app.hud.set_menu_visible(true)
	press_menu("Новый матч")
	await frames(2)
	app.session.kill_limit = 25
	var initial_epoch: int = app.session.simulation.epoch
	app.session.match_duration_ticks = 30
	events.clear()
	press_menu("Начать матч 3×3")
	await frames(40)
	check(app.session.finished and app.session.get_diagnostics().finish_reason == "time_limit", "a configured time limit ends the actual match through normal fixed frames")
	check(not app.player.controls_enabled and not app.hud._results.text.is_empty(), "finished match gates gameplay and shows its result")
	var tick: int = app.session.simulation.tick
	var finishes: int = events.filter(func(event: Dictionary) -> bool: return event.type == "tdm_finished").size()
	await frames(20)
	check(app.session.simulation.tick == tick and finishes == 1, "finished authority freezes and emits one final result")
	app.hud.set_menu_visible(true)
	press_menu("Новый матч")
	await frames(3)
	check(app.session.simulation.epoch > initial_epoch and app.world.data == app.session.simulation.data, "restart adopts a fresh match epoch and one shared arena map")
	check(app.world.data.blocks == baseline_blocks, "restart restores every cell of the authored arena")
	check(not app.session.finished and app.session.team_scores == [0, 0] and app.session.winning_team == -1, "restart clears result and score before the next match")
	check(app.session.simulation.actors.size() == 6 and app._target_nodes.size() == 5 and app.session.simulation.grenades.is_empty(), "restart restores the roster with no retained projectiles")
	check(app._corpses.is_empty() and app.hud._results.text.is_empty(), "restart clears corpses and HUD result")
	check(app.hud.is_menu_open() and app.session.paused and not app.player.controls_enabled, "restart presents a paused entry menu")


func cleanup_scene() -> void:
	release_actions()
	app.stop_audio()
	app.player.stop_audio()
	var reference: WeakRef = weakref(app)
	app.queue_free()
	await frames(8)
	check(reference.get_ref() == null, "TDM scene is fully freed before another offline session")
	app = null


func normal_lab_regression() -> void:
	app = LAB_SCENE.instantiate()
	root.add_child(app)
	await frames(3)
	check(not app.offline_tdm_mode and not app.network_mode and app.network_client == null, "ordinary offline lab still opens without TDM or network transport")
	check(app.session.mode == "sandbox" and app.session.targets.size() == 6 and app._target_nodes.size() == 6, "normal lab preserves its six demonstration soldiers")
	check(app.hud.is_menu_open() and not app.player.controls_enabled, "normal lab preserves its entry menu")
	await cleanup_scene()
