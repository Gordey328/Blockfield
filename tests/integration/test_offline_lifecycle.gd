extends SceneTree
## Actual offline Main authority/presentation: death camera, corpse budgets and rounds.
const SCENE = preload("res://scenes/main.tscn")
var assertions := 0
var failures := 0
var app: Node3D
var before: Dictionary = {}

func _initialize() -> void: call_deferred("_run")

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("OFFLINE LIFECYCLE: " + message)

func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame
		await create_timer(0.0).timeout

func _run() -> void:
	for path: String in ["user://settings.cfg", "user://servers.cfg"]:
		var exists := FileAccess.file_exists(path)
		before[path] = {"exists":exists,"bytes":FileAccess.get_file_as_bytes(path) if exists else PackedByteArray()}
	app = SCENE.instantiate()
	root.add_child(app)
	app.set_skin("original")
	app.set_locale("en")
	await frames(3)
	app.hud.set_menu_visible(false)
	app.session.invulnerable = false
	app.set_graphics_option("ragdolls", true)
	app.player.respawn_at(Vector3(40,14,40))
	app.player.velocity = Vector3(3,0,0)
	await frames(2)
	app.session.damage_player(100, Vector3(38,14,40), "weapon")
	await frames(2)
	var own_corpse: OpenSpadesCorpse = app._last_player_corpse
	check(app.session.health == 0 and is_instance_valid(own_corpse), "real damage signal creates the local static corpse")
	check(app.player.camera_mode == BlockfieldPlayer.CameraMode.DEATH, "actual controller enters death camera")
	if is_instance_valid(own_corpse):
		var center := own_corpse.get_center()
		await frames(8)
		check(own_corpse.is_static() and own_corpse.get_center() == center and own_corpse.positions.is_empty(), "approved death body remains static without solver state in the actual scene")
		check(app.get_player_corpse_center().distance_to(own_corpse.get_center()) < .00001, "death camera focus retains the fixed visible corpse center")
	app.hud.set_menu_visible(true)
	app.clear_corpses()
	await frames(2)
	check(app._corpses.is_empty() and app._last_player_corpse == null and not is_instance_valid(own_corpse), "clear frees corpse meshes and its camera reference")
	# Freeze presentation between creations: an unobstructed high eye sees every
	# body. More than sixteen visible deaths must still evict the oldest bodies.
	app.player.camera.global_position = Vector3(40,80,40)
	var oldest: OpenSpadesCorpse
	for index in 20:
		var body: OpenSpadesCorpse = app.spawn_corpse({"player_id":index+1,"feet_position":Vector3(40+index*.1,12,40),"seed":index+1})
		if index == 0: oldest = body
	check(app._corpses.size() == 16 and oldest.is_queued_for_deletion(), "hard limit removes the oldest body even when all are visible")
	app.clear_corpses()
	await frames(2)
	app.player.camera.global_position = Vector3(1000,80,1000)
	for index in 10:
		app.spawn_corpse({"player_id":index+1,"feet_position":Vector3(40,12,40),"seed":index+1})
	check(app._corpses.size() == 6, "invisible older corpses are pruned to the six-body soft limit")
	app.reset_lab()
	await frames(3)
	check(app._corpses.is_empty() and app._last_player_corpse == null and app.session.targets.size() == 6, "actual reset removes bodies and restores the testing soldiers")
	# Walk the source-equivalent local authority through a complete one-capture
	# CTF round without a server. Rendering/menu nodes consume its normal events.
	app.session.select_team(0)
	app.session.set_mode("ctf")
	app.session.configure_ctf(Vector3(16,4,48), Vector3(80,4,48), 1)
	app.hud.set_menu_visible(false)
	app.player.respawn_at(app.session.ctf_bases[1])
	await frames(3)
	check(app.session.is_local_intel_carrier(), "entering the enemy base picks up its real intel")
	app.player.respawn_at(app.session.ctf_bases[0])
	await frames(3)
	check(app.session.team_scores[0] == 1 and app.session.winning_team == 0, "returning to the base completes the offline CTF round")
	check(app.hud._results.text.contains("Blue") and app.hud._events.any(func(event): return event.type == "round_won"), "real HUD displays the winner and receives round events")
	app.reset_match()
	await frames(3)
	check(app.session.winning_team == -1 and app.session.team_scores == [0,0] and app.hud._results.text.is_empty(), "actual round reset clears winner, score and result caption")
	# A trusted fixture puts the three actual checkpoints within native18m
	# capture range. Progress still comes from twenty seconds of normal frames.
	app.session.set_mode("tc")
	var point := Vector3(8,4,8)
	var checkpoints: Array[Vector3] = [point, point+Vector3.RIGHT, point+Vector3.BACK]
	app.session.configure_tc(checkpoints)
	app.player.respawn_at(point)
	await frames(2)
	for node: Node3D in app._objective_nodes:
		if node.get_meta("objective", "") == "tc":
			check(node.position == app.session.territories[int(node.get_meta("index"))].position, "actual TC mesh follows configured authority position")
	await frames(1210)
	check(app.session.winning_team == 0 and app.session.team_scores == [3,0], "normal offline frames complete all three TC captures and win")
	check(app.session.territories.all(func(territory): return territory.owner == 0), "all checkpoint ownership is authority-confirmed")
	check(app.hud._results.text.contains("Blue"), "actual TC result caption is visible after the win")
	app.reset_match()
	await frames(3)
	check(app.session.winning_team == -1 and app.session.territories.all(func(territory): return territory.owner == 2), "actual TC reset restores neutral checkpoints")
	app.stop_audio()
	app.queue_free()
	await frames(8)
	var drain_deadline := Time.get_ticks_msec()+200
	while Time.get_ticks_msec() < drain_deadline:
		OS.delay_msec(1)
		await process_frame
	for path: String in before:
		if before[path].exists:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(before[path].bytes)
			file.close()
		else: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("OFFLINE LIFECYCLE: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)
