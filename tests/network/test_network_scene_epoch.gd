extends SceneTree
## Real network.tscn, its Controller/HUD/meshes, and two native socket clients.
## Headless node-graph coverage does not certify browser rendering or WSS.
const SCENE = preload("res://scenes/network.tscn")
const SERVER = preload("res://network/server_runtime.gd")
const CLIENT = preload("res://network/client_replica.gd")
const MATCH = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const RULES = preload("res://simulation/player_rules.gd")
const COMPAT = preload("res://network/compatibility.gd")
const OLD_EPOCH := 1101
const NEW_EPOCH := 1102
const AUTHORITY_STEP_US := 16667
const INPUT_WAIT_MS := 4000
var assertions := 0
var failures := 0
var polls := 0
var app: Node3D
var server := SERVER.new()
var other := CLIENT.new()
var other_events: Array[Dictionary] = []
var saved_files: Dictionary[String,Dictionary] = {}
var render_capture := false
var next_authority_step_us := 0
var clock_waits := 0
var remote_inputs := 0

func _initialize() -> void: call_deferred("_run")

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("NETWORK SCENE EPOCH: " + message)

func pump(count: int = 1) -> void:
	for frame in count:
		# --fixed-fps advances simulation frames, not Time.get_ticks_usec().
		# The production input clock deliberately uses wall time. Pace this
		# independently stepped authority at no more than 60 real steps/second;
		# after expensive scene work, drop the missed interval instead of a burst.
		var now := Time.get_ticks_usec()
		if now < next_authority_step_us: OS.delay_usec(next_authority_step_us - now)
		next_authority_step_us = Time.get_ticks_usec() + AUTHORITY_STEP_US
		server.poll()
		other.poll()
		for event: Dictionary in other.drain_events():
			if other_events.size() == 512: other_events.pop_front()
			other_events.append(event)
		if not server.step_once(): check(false, "authority fixed step")
		polls += 1
		await physics_frame
		await process_frame
		# process_frame is emitted before Node._process. Sample the actual mesh
		# transforms only after Main and its soldier/HUD children finish this frame.
		await create_timer(0.0).timeout

func submit_remote(buttons: int, move: Vector2, yaw: float, pitch: float) -> bool:
	# A real client can wait when its latest 20Hz snapshot has aged beyond the
	# unchanged future window. Preserve every authored command; never edit its
	# timestamps or treat a failed submit as successful input.
	var deadline := Time.get_ticks_msec() + INPUT_WAIT_MS
	while Time.get_ticks_msec() < deadline:
		other.poll()
		var before: Dictionary = other.prediction.get_status()
		var submitted: Dictionary = other.submit_input(buttons, move, yaw, pitch)
		if submitted.ok:
			remote_inputs += 1
			check(other.prediction.get_status().last_submitted == before.last_submitted + 1, "accepted remote input advances exactly one sequence")
			return true
		if other.status != "live" or submitted.error not in ["awaiting fresh authority clock", "awaiting fresh authority stream"]:
			check(false, "unexpected remote input failure: " + str(submitted.error))
			return false
		var after: Dictionary = other.prediction.get_status()
		check(after.last_submitted == before.last_submitted and after.pending == before.pending, "clock/ordered-stream wait cannot fabricate remote input or prediction")
		clock_waits += 1
		await pump()
	check(false, "remote input readiness timed out")
	return false

func wait_for(predicate: Callable, message: String) -> bool:
	var deadline := Time.get_ticks_msec() + 12000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		if app.network_client.status == "failed" or other.status == "failed": break
		await pump()
	var result: bool = predicate.call()
	check(result, "%s (%s/%s, errors %s / %s)" % [message, app.network_client.status, other.status, app.network_client.last_error, other.last_error])
	return result

func make_map(epoch: int, dimensions: Vector3i, floor_height: int, ground: int, marker: int) -> DATA:
	var data := DATA.new()
	check(data.clear(dimensions, epoch) == OK, "canonical writable map")
	data.seed_box(Vector3i.ZERO, Vector3i(dimensions.x, floor_height, dimensions.z), ground)
	data.seed_box(Vector3i(12, floor_height, 12), Vector3i(14, floor_height + 2, 14), marker)
	return data

func soldier_for(id: int) -> Node3D:
	for soldier: Node3D in app._target_nodes:
		if soldier.target_id == id: return soldier
	return null

func objective_counts() -> Dictionary:
	var result := {"ctf_base":0, "intel":0, "tc":0}
	for node: Node3D in app._objective_nodes:
		var kind := str(node.get_meta("objective", ""))
		if result.has(kind): result[kind] += 1
	return result

func select_team(team: int) -> void:
	app.hud.set_menu_visible(true)
	app.hud._network_menu.controls.team.item_selected.emit(team)

func remote_hp_private(id: int, expected_owner_hp: int) -> void:
	var target: Dictionary = app.session.get_target(id)
	check(not target.is_empty() and target.alive and target.health == -1 and not target.health_known, "alive remote HP remains explicitly unknown")
	var public_state: Dictionary = app.network_client.get_public_state()
	var actor: Dictionary = {}
	for record: Dictionary in public_state.actors:
		if record.id == id: actor = record
	check(not actor.is_empty() and not actor.has("health") and not actor.has("magazine") and not actor.has("input_buttons") and not actor.has("shot_rng"), "remote wire contains no private health, resources, input or RNG")
	check(other.get_owner_state().health == expected_owner_hp, "second owner receives its own actual HP")
	var soldier := soldier_for(id)
	check(soldier != null and soldier._label.text == "Remote epoch guest", "real soldier uses public name instead of invented HP")
	if soldier != null:
		check(not soldier.character._dead and soldier._zones.all(func(zone): return zone.collision_layer == 2), "unknown negative HP does not render an alive remote as dead")

func capture_scene(label: String, remote_id: int = 0) -> void:
	if not render_capture: return
	if remote_id > 0:
		app.hud.set_menu_visible(false)
		var soldier := soldier_for(remote_id)
		var direction: Vector3 = (soldier.position + Vector3.UP * 1.2 - app.player.get_aim_origin()).normalized()
		app.player.rotation.y = atan2(-direction.x, -direction.z)
		app.player.head.rotation.x = asin(clampf(direction.y,-1,1))
		await pump(3)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var colors: Dictionary[int,bool] = {}
	for y in range(0,image.get_height(),16):
		for x in range(0,image.get_width(),16): colors[image.get_pixel(x,y).to_rgba32()] = true
	check(image.get_width() >= 800 and image.get_height() >= 600 and colors.size() > 12, "real Compatibility viewport contains rendered scene/UI pixels: " + label)
	var folder := ProjectSettings.globalize_path("res://../.cache/previews/network-scene-epoch")
	DirAccess.make_dir_recursive_absolute(folder)
	check(image.save_png(folder.path_join(label + ".png")) == OK, "actual GPU frame saved: " + label)
	if remote_id > 0: app.hud.set_menu_visible(true)

func _run() -> void:
	render_capture = "--render-scene-epoch" in OS.get_cmdline_user_args()
	# Main settings setup can write preferences; restore the original bytes/existence.
	for path: String in ["user://settings.cfg", "user://servers.cfg"]:
		var existed := FileAccess.file_exists(path)
		saved_files[path] = {"existed":existed, "bytes":FileAccess.get_file_as_bytes(path) if existed else PackedByteArray()}
	var data := make_map(OLD_EPOCH, Vector3i(32,16,32), 4, 0x01608070, 0x01dd4455)
	var simulation := MATCH.new()
	check(simulation.configure(data, "0.75", "ctf").ok, "source-profile CTF authority")
	check(server.configure(simulation, COMPAT.build_hash(), COMPAT.rules_hash()), "configured native Runtime")
	var ports := server.start()
	check(ports.ok, "two real socket listeners")
	if not ports.ok: await cleanup(); return
	app = SCENE.instantiate()
	root.add_child(app)
	await pump(2)
	# Choose the committed original skin as this presentation fixture, not a user pack.
	app.set_skin("original")
	check(app.network_mode and app.session is NetworkSession, "actual inherited network scene and read-only session")
	check(app.hud.is_menu_open() and not app.player.controls_enabled and app._target_nodes.is_empty(), "idle UI has no offline actor presentation")
	var menu: Node = app.hud._network_menu
	menu.controls.game_url.text = "ws://127.0.0.1:%d/play" % ports.game_port
	menu.controls.map_url.text = "ws://127.0.0.1:%d/map" % ports.map_port
	menu.controls.player_name.text = "Scene epoch owner"
	menu.controls.spectator.button_pressed = false
	menu.refresh()
	check(not menu.controls.connect.disabled and menu.controls.enter.disabled, "connection form enables connect but gates gameplay")
	menu.controls.connect.pressed.emit()
	check(app.network_client.status == "connecting", "real connect button starts the client")
	check(other.connect_to(menu.controls.game_url.text, menu.controls.map_url.text, "Remote epoch guest").ok, "second independent replica")
	menu.refresh()
	check(menu.controls.progress.visible and menu.controls.enter.disabled and not menu.controls.game_url.editable, "joining UI shows progress and locks connection fields")
	if not await wait_for(func(): return app.network_client.status == "live" and other.status == "live", "both initial map/state barriers complete"):
		await cleanup(); return
	await pump(28)
	menu.refresh()
	var own_id: int = app.session.local_player_id()
	var other_id: int = other.actor_id
	check(own_id > 0 and other_id > 0 and own_id != other_id, "two canonical positive actor identities")
	check(not menu.controls.enter.disabled and not menu.controls.progress.visible and menu.controls.team.selected == app.session.team, "live connection UI mirrors confirmed team and enables entry")
	menu.controls.enter.pressed.emit()
	await pump(2)
	check(not app.hud.is_menu_open() and app.player.controls_enabled and app.player._has_entered, "initial Enter transitions the actual camera out of its intro state")
	app.hud.set_menu_visible(true)
	check(app.world.data == app.network_client.data and app.world.data.blocks == data.blocks and app.world.dimensions == data.dimensions, "Main adopts exact authoritative baseline")
	check(objective_counts() == {"ctf_base":2, "intel":2, "tc":0}, "CTF renders only two bases and two intel objects")
	check(app._target_nodes.size() == 1 and app.session.targets.size() == 1 and soldier_for(other_id) != null, "one actual remote soldier, no local-ID zero duplicate")
	# Trusted server fixture makes the privacy assertion distinguish HP from 100.
	simulation.get_actor(other_id).health = 37
	await pump(5)
	remote_hp_private(other_id, 37)
	for frame in 36:
		var submitted := await submit_remote(RULES.Buttons.CROUCH | RULES.Buttons.SECONDARY, Vector2(.3,-.2), .7, -.25)
		check(submitted, "real remote input accepted")
		if not submitted: await cleanup(); return
		await pump()
	await pump(10)
	var target: Dictionary = app.session.get_target(other_id)
	var remote := soldier_for(other_id)
	check(target.crouching and target.aim_down_state > 0 and absf(target.yaw - .7) < .002 and absf(target.pitch + .25) < .002, "confirmed remote source pose carries crouch, ADS and view angles")
	check(remote.position.distance_to(target.position) < .001 and absf(wrapf(remote.rotation.y - target.yaw, -PI, PI)) < .001, "actual soldier applies interpolated feet and canonical yaw: mesh=%s view=%s yaw=%f/%f" % [remote.position,target.position,remote.rotation.y,target.yaw])
	check(remote.character._crouching and not remote.character._dead and absf(remote.character._pitch - target.pitch) < .001, "native character skin applies remote crouch/pitch without private HP")
	await capture_scene("01-ctf-remote-pose", other_id)
	var released := await submit_remote(0, Vector2.ZERO, .7, -.25)
	check(released, "remote source controls released")
	if not released: await cleanup(); return
	await pump(5)
	await wait_for(func(): return other.prediction.get_status().pending == 0, "all 36 pose commands and neutral release are acknowledged")
	var remote_owner := simulation.get_actor(other_id)
	check(remote_inputs == 37 and remote_owner.consumed_input_sequence == other.prediction.get_status().last_submitted and remote_owner.input_buttons == 0 and remote_owner.input_move == Vector2.ZERO, "actual authority consumed every authored remote command and neutralized controls")
	var initial_magazine: int = simulation.get_actor(own_id).magazine
	menu.controls.weapon_2.pressed.emit()
	await wait_for(func(): return simulation.get_actor(own_id).pending_weapon == 2, "actual weapon UI queues a pending class")
	check(simulation.get_actor(own_id).weapon == 0 and simulation.get_actor(own_id).magazine == initial_magazine and app.session.current_weapon == 0, "live class selection cannot replace or refill current inventory")
	select_team(2)
	if not await wait_for(func(): return simulation.get_actor(own_id).team == 2 and app.session.team == 2, "actual team UI enters spectator authority"):
		await cleanup(); return
	await pump(3)
	check(app.session.health == 0 and app.session.local_player_id() == own_id and app.player.camera_mode == BlockfieldPlayer.CameraMode.FREE, "spectator view preserves canonical owner and has no living resources")
	check(not app.hud._events.is_empty() and not app.hud._feed.get_parsed_text().is_empty(), "real team-change death populates HUD feed before reset")
	select_team(1)
	if not await wait_for(func(): return simulation.get_actor(own_id).is_alive() and app.session.health > 0 and app.session.current_weapon == 2, "source respawn applies queued class after team request"):
		await cleanup(); return
	await pump(3)
	check(app.session.magazine == 6 and app.session.reserve == 48 and app.session.local_player_id() == own_id and app.session.spawn_generation > 1, "0.75 shotgun inventory and new generation are server-confirmed")
	# A genuine server map receipt exercises Main's old impact/topdown/mesh caches.
	var marker := Vector3i(12,5,12)
	var changed: Dictionary = data.set_block(marker, 0x01ffaa22, {"tick":simulation.tick, "actor_id":own_id, "action_id":1})
	check(changed.ok and changed.changed, "trusted server terrain repaint transaction")
	simulation._commit(changed)
	await wait_for(func(): return app.world.data.map_sequence == 1 and app.world.get_block(marker) == 0x01ffaa22, "real transaction reaches rendering map once")
	check(app._impact_colors.get(marker,0) == 0x01dd4455, "Main retains actual old impact color before reset")
	await pump(18)
	var old_image: Image = app.world.get_topdown_image()
	var old_chunks: Array = app.world._chunks.values().duplicate()
	var old_objectives: Array = app._objective_nodes.duplicate()
	var old_remote: Node3D = soldier_for(other_id)
	check(old_chunks.size() > 0 and old_image.get_size() == Vector2i(32,32), "old renderer has real chunk and map caches")
	app.session.select_tool(3)
	menu.controls.enter.pressed.emit()
	check(not app.hud.is_menu_open() and app.player.controls_enabled, "actual Enter button enables live controller input")
	if not await wait_for(func(): return simulation.get_actor(own_id).tool == 3 and simulation.get_actor(own_id).displayed_tool == 3 and simulation.get_actor(own_id).tool_raise >= 1.0, "source grenade lower/swap/raise gate completes"):
		await cleanup(); return
	Input.action_press("primary")
	await pump(14)
	Input.action_release("primary")
	if not await wait_for(func(): return not app.session.live_grenades.is_empty() and not app._grenade_nodes.is_empty(), "actual Controller cook/release creates confirmed grenade view"):
		await cleanup(); return
	await pump(5)
	var grenade: Dictionary = app.session.live_grenades.front()
	var old_grenade: Node3D = app._grenade_nodes[grenade.id]
	check(grenade.visual_only and old_grenade.position.distance_to(grenade.position) < .0001, "grenade mesh copies confirmed raw position without client authority physics")
	check(absf(grenade.orientation.dot(Quaternion.IDENTITY)) < .9999, "moving source grenade has nontrivial confirmed rotation")
	check(absf(old_grenade.basis.orthonormalized().get_rotation_quaternion().dot(grenade.orientation)) > .99999, "actual grenade mesh applies wire quaternion as well as position")
	var new_data := make_map(NEW_EPOCH, Vector3i(64,24,48), 6, 0x01114477, 0x0134cc99)
	var reset: Dictionary = server.reset_match(new_data, "0.76", "tc")
	check(reset.ok and reset.epoch == NEW_EPOCH, "trusted coordinator resets live CTF to new TC/profile/map epoch")
	if not reset.ok: await cleanup(); return
	if not await wait_for(func(): return app.network_client.epoch == NEW_EPOCH and app.network_client.status in ["preparing","joining","loading","synchronizing"], "Main observes greater epoch before the new live barrier"):
		await cleanup(); return
	menu.refresh()
	check(app.hud.is_menu_open() and not app.player.controls_enabled and menu.controls.enter.disabled and menu.controls.progress.visible, "reset loading UI blocks input and shows map progress")
	check(app.session.health == 0 and app.session.targets.is_empty() and app._target_nodes.is_empty(), "loading has no stale owner inventory or remote actor presentation")
	check(app._objective_nodes.is_empty(), "loading has no regenerated old CTF objective nodes")
	check(app._grenade_nodes.is_empty() and app._impact_colors.is_empty(), "loading clears old projectile and impact-color caches")
	check(app.hud._events.is_empty() and app.hud._feed.get_parsed_text().is_empty(), "greater WELCOME clears the old HUD event cache and rendered feed")
	await capture_scene("02-reset-loading")
	if not await wait_for(func(): return app.network_client.status == "live" and other.status == "live" and other.epoch == NEW_EPOCH, "both replicas complete the new baseline/state barriers"):
		await cleanup(); return
	await pump(20)
	check(app.session.local_player_id() == own_id and other.actor_id == other_id, "Main and independent replica retain canonical actor IDs across epoch")
	check(app.world.data == app.network_client.data and app.world.dimensions == new_data.dimensions and app.world.data.blocks == new_data.blocks and app.world.data.map_sequence == 0, "new adopted map is exact and has no old transaction sequence")
	check(app.session.mode == "tc" and app.session.profile_version == "0.76" and app.session.current_weapon == 2 and app.session.magazine == 8 and app.session.reserve == 48, "new confirmed mode/profile restores class with fresh 0.76 inventory")
	check(objective_counts() == {"ctf_base":0, "intel":0, "tc":3} and app._objective_nodes.size() == app.session.territories.size(), "TC creates only its three confirmed checkpoint meshes")
	for node: Node3D in app._objective_nodes:
		var index: int = node.get_meta("index")
		check(node.position.distance_to(app.session.territories[index].position) < .0001, "new TC checkpoint uses its authoritative position")
	check(app.hud._mode.text.contains("TC"), "real HUD mode caption changes to TC")
	check(old_objectives.all(func(node): return not is_instance_valid(node)) and not is_instance_valid(old_remote), "old CTF meshes and remote soldier are freed, not reused across epoch")
	check(old_chunks.all(func(node): return not is_instance_valid(node)), "old map chunk/collision nodes are freed")
	check(not is_instance_valid(old_grenade) and app._grenade_nodes.is_empty() and app.session.live_grenades.is_empty(), "old grenade is removed from both mesh graph and public view")
	var image: Image = app.world.get_topdown_image()
	check(image != old_image and image.get_size() == Vector2i(64,48) and image.get_pixel(12,12).is_equal_approx(Color("34cc99")), "topdown cache is rebuilt from new dimensions and highest palette color")
	check(app.hud._map._texture.get_size() == Vector2(64,48) and app.hud._large_map._terrain_source == app.hud._map, "actual mini/full maps share the new terrain texture source")
	check(app._impact_colors.is_empty() and app.world._falling_clusters.is_empty() and app._corpses.is_empty(), "new epoch contains no old impact, collapse or corpse presentation")
	check(app.hud._events.all(func(event): return int(event.get("epoch",NEW_EPOCH)) == NEW_EPOCH), "new HUD feed contains no old epoch events")
	check(app._target_nodes.size() == 1 and app.session.targets.size() == 1 and soldier_for(other_id) != null, "TC contains only the rebuilt canonical remote soldier")
	server.simulation.get_actor(other_id).health = 47
	await pump(5)
	remote_hp_private(other_id, 47)
	await capture_scene("03-tc-remote-pose", other_id)
	menu.refresh()
	check(not menu.controls.enter.disabled and not menu.controls.team.disabled and not menu.controls.progress.visible, "new live UI restores entry and typed selection controls")
	# New-epoch UI requests restart their sequence and still route through authority.
	menu.controls.weapon_1.pressed.emit()
	await wait_for(func(): return server.simulation.get_actor(own_id).pending_weapon == 1, "new-epoch class intent reaches actual authority")
	check(app.session.current_weapon == 2 and app.session.magazine == 8, "new live class request does not locally refill/replace shotgun")
	select_team(2)
	await wait_for(func(): return app.session.team == 2 and server.simulation.get_actor(own_id).team == 2, "new-epoch spectator request is confirmed")
	await pump(3)
	check(app.session.health == 0 and app.session.local_player_id() == own_id, "spectator request preserves canonical identity after reset")
	select_team(0)
	await wait_for(func(): return app.session.team == 0 and app.session.health > 0 and app.session.current_weapon == 1, "new-epoch team/respawn applies pending SMG class")
	await pump(3)
	check(app.session.magazine == 30 and app.session.reserve == 150 and server.simulation.get_actor(own_id).profile == "0.76", "fresh 0.76 SMG resources come from source rules")
	menu.controls.enter.pressed.emit()
	check(not app.hud.is_menu_open() and app.player.controls_enabled, "new live entry restores actual controls")
	await cleanup()

func cleanup() -> void:
	for action: String in ["primary","secondary","forward","back","left","right","crouch","sprint","sneak","jump","reload"]:
		if InputMap.has_action(action): Input.action_release(action)
	if is_instance_valid(app): app.network_disconnect()
	other.close()
	server.stop()
	if is_instance_valid(app): app.queue_free()
	for frame in 8: await process_frame
	# --fixed-fps advances simulated frames faster than the audio driver's wall
	# clock. Give its deferred stop commands real mixer cycles before quitting.
	var drain_deadline := Time.get_ticks_msec()+200
	while Time.get_ticks_msec()<drain_deadline:
		OS.delay_msec(1)
		await process_frame
	for path: String in saved_files:
		var record: Dictionary = saved_files[path]
		if record.existed:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(record.bytes)
			file.close()
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		check(FileAccess.file_exists(path) == record.existed and (not record.existed or FileAccess.get_file_as_bytes(path) == record.bytes), "exact bytes/existence restored for " + path)
	print("NETWORK SCENE EPOCH: %d assertions, %d failures, %d fixed-step polls, %d remote inputs, %d bounded clock waits" % [assertions,failures,polls,remote_inputs,clock_waits])
	quit(0 if failures == 0 else 1)
