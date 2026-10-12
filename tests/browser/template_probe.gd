extends Node
## Test-only actual Main plus behavioral checks for retained Web engine modules.
## Activate by clicking its real canvas button; audio checks need that gesture.
## Normal export/Main settings are preserved by export_template_probe.py.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const CELL: Vector3i = Vector3i(12, 6, 8)
const PACK_ID: String = "web-template-original-fixture"
var app: Node3D
var status: Label
var button: Button
var multilingual: RichTextLabel
var busy: bool = false
var phase: String = "Preparing actual Main"
var assertions: int = 0
var failures: int = 0
var rows: Array[Dictionary] = []
var details: Dictionary = {}
var throws: Array[Dictionary] = []
var blasts: Array[Dictionary] = []
var proof_player: AudioStreamPlayer
var capture: AudioEffectCapture
var bus: int = -1


func _ready() -> void:
	seed(328)
	app = MAIN.instantiate()
	add_child(app)
	app.set_locale("en")
	app.hud.set_mobile_controls_mode(2)
	InputMap.action_erase_events("primary")
	app.session.invulnerable = true
	app.session.unlimited_ammo = false
	app.session.select_team(0)
	app.session.select_weapon(LocalSession.Weapon.RIFLE)
	app.session.select_tool(LocalSession.Tool.WEAPON)
	app.session.grenade_thrown.connect(func(event: Dictionary): throws.append(event.duplicate(true)))
	app.session.grenade_exploded.connect(func(event: Dictionary): blasts.append(event.duplicate(true)))
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var panel: VBoxContainer = VBoxContainer.new()
	panel.position = Vector2(12, 90)
	panel.custom_minimum_size = Vector2(350, 180)
	layer.add_child(panel)
	button = Button.new()
	button.text = "Run retained module checks"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(350, 46)
	button.pressed.connect(_run_checks)
	panel.add_child(button)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(350, 90)
	status.add_theme_color_override("font_color", Color.WHITE)
	status.add_theme_color_override("font_outline_color", Color.BLACK)
	status.add_theme_constant_override("outline_size", 5)
	panel.add_child(status)
	multilingual = RichTextLabel.new()
	multilingual.bbcode_enabled = true
	multilingual.text = "[b]Русский · 中文 · 日本語 · 한국어[/b]"
	multilingual.add_theme_font_override("normal_font", OpenSpadesLocalization.get_ui_font())
	multilingual.add_theme_font_override("bold_font", OpenSpadesLocalization.get_ui_font())
	multilingual.fit_content = true
	multilingual.custom_minimum_size = Vector2(350, 32)
	panel.add_child(multilingual)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("if(!document.getElementById('template-probe-report')){var r=document.createElement('pre');r.id='template-probe-report';r.hidden=true;document.body.appendChild(r);}", true)
	phase = "Ready — click the canvas button to activate audio and run"
	_publish("ready")
	if "--template-probe-native" in OS.get_cmdline_user_args():
		_native_run.call_deferred()


func _native_run() -> void:
	await _run_checks()
	_release()
	app.stop_audio()
	app.queue_free()
	await get_tree().create_timer(0.25).timeout
	get_tree().quit(0 if failures == 0 else 1)


func _publish(state: String = "running") -> void:
	status.text = "TEST-ONLY ACTUAL MAIN\n%s\n%d checks / %d failures" % [phase, assertions, failures]
	var result: Dictionary = {"state": state, "phase": phase, "checks": assertions,
		"failures": failures, "rows": rows, "details": details,
		"engine": Engine.get_version_info(), "renderer": RenderingServer.get_current_rendering_method()}
	if OS.has_feature("web"):
		var serialized: String = JSON.stringify(result)
		JavaScriptBridge.eval("window.templateProbeResult=" + serialized
			+ ";document.getElementById('template-probe-report').textContent=" + JSON.stringify(serialized) + ";", true)
	if state == "complete":
		print("TEMPLATE_WEB: " + JSON.stringify(result))


func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
	rows.append({"pass": ok, "message": message})
	print("TEMPLATE_WEB: ", "PASS " if ok else "FAIL ", message)
	_publish()


func action(name: String, pressed: bool) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = name
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _release() -> void:
	for name: String in ["primary", "secondary", "forward", "back", "left", "right"]:
		action(name, false)


func _primary_physics_pulse() -> Dictionary:
	var start_frame: int = Engine.get_physics_frames()
	var start_usec: int = Time.get_ticks_usec()
	action("primary", true)
	# A short process timer can expire in the frame that created it under load.
	# physics_frame precedes node callbacks; the final process frame makes both
	# delivered physics ticks observable before releasing the real input action.
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	var held: bool = Input.is_action_pressed("primary")
	action("primary", false)
	return {"physics_frames": Engine.get_physics_frames() - start_frame,
		"wall_ms": float(Time.get_ticks_usec() - start_usec) / 1000.0,
		"pressed_before_release": held, "pressed_after_release": Input.is_action_pressed("primary")}


func _inventory_state() -> Dictionary:
	return {"weapon": app.session.current_weapon, "tool": app.session.current_tool,
		"magazine": app.session.magazine, "reserve": app.session.reserve,
		"blocks": app.session.blocks, "shots": app.session.shots_fired,
		"unlimited_ammo": app.session.unlimited_ammo,
		"controls_enabled": app.player.controls_enabled, "can_use_tool": app.player.can_use_tool()}


func _ready_tool(tool: int, weapon: int = LocalSession.Weapon.RIFLE) -> bool:
	_release()
	app.session.restock()
	app.session.select_weapon(weapon)
	app.session.select_tool(tool)
	# Selection observers and the original raise animation need real frames.
	await get_tree().physics_frame
	await get_tree().process_frame
	var deadline: int = Time.get_ticks_msec() + 10000
	while not app.player.can_use_tool() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var ready: bool = app.player.can_use_tool()
	check(ready, "actual tool ready: %d / firearm %d" % [tool, weapon])
	return ready


func _prepare_world() -> void:
	for soldier: Node3D in app._target_nodes:
		soldier.queue_free()
	app._target_nodes.clear()
	app.session.targets.clear()
	app.clear_corpses()
	app.world.clear_world(Vector3i(24, 16, 24))
	app.world.water_enabled = false
	app.world.data.seed_box(Vector3i.ZERO, Vector3i(24, 4, 24), 0x01608070)
	for y: int in range(4, 8):
		app.world.set_block(Vector3i(12, y, 8), 0x01ff8041)
	app.world._mark_all_chunks()
	app.world.rebuild_now()
	_respawn(Vector3(12.5, 4.01, 13.5))


func _respawn(point: Vector3) -> void:
	app.player.respawn_at(point)
	app.player.rotation.y = 0.0
	app.player.head.rotation.x = 0.0
	app.player.camera.rotation = Vector3.ZERO


func _run_checks() -> void:
	if busy:
		return
	busy = true
	button.disabled = true
	rows.clear()
	details.clear()
	assertions = 0
	failures = 0
	phase = "Starting genuine offline lab"
	check(app.hud.is_menu_open() and not app.player.controls_enabled, "actual startup menu gates gameplay")
	app.hud.set_menu_visible(false)
	_prepare_world()
	if await _ready_tool(LocalSession.Tool.WEAPON):
		check(app.player.controls_enabled and app.player.camera_mode == BlockfieldPlayer.CameraMode.FIRST_PERSON,
			"ordinary lab entry enables first-person controller")
		await _gameplay()
	phase = "Runtime GLTF / ZIP / RegEx / Unicode / GUI"
	_publish()
	_modules()
	await _render_and_physics()
	phase = "Mix original PCM and Vorbis through the Web audio server"
	_publish()
	await _audio()
	await _optional_tdm()
	_release()
	phase = "Complete — %d checks / %d failures" % [assertions, failures]
	busy = false
	_publish("complete")


func _gameplay() -> void:
	var start: Vector3 = app.player.global_position
	action("forward", true)
	await get_tree().create_timer(0.3).timeout
	action("forward", false)
	check(app.player.global_position.distance_to(start) > 0.2, "normal forward action moves actual controller")
	_respawn(Vector3(12.5, 4.01, 13.5))
	for weapon: int in [LocalSession.Weapon.RIFLE, LocalSession.Weapon.SMG, LocalSession.Weapon.SHOTGUN]:
		if not await _ready_tool(LocalSession.Tool.WEAPON, weapon):
			continue
		var shots: int = app.session.shots_fired
		var magazine: int = app.session.magazine
		var before: Dictionary = _inventory_state()
		var pulse: Dictionary = await _primary_physics_pulse()
		details["firearm_%d" % weapon] = {"before": before, "after": _inventory_state(), "pulse": pulse}
		check(app.session.shots_fired > shots and app.session.magazine < magazine,
			"original firearm %d fires and consumes ammo through real controller" % weapon)
	_prepare_world()
	_respawn(Vector3(12.5, 4.01, 10.5))
	if await _ready_tool(LocalSession.Tool.SPADE):
		action("primary", true)
		await get_tree().create_timer(0.42).timeout
		action("primary", false)
		check(app.world.get_block(CELL) == 0, "ordinary spade trigger removes the aimed voxel")
	_prepare_world()
	_respawn(Vector3(12.5, 4.01, 10.5))
	if await _ready_tool(LocalSession.Tool.BLOCK):
		var preview: Dictionary = app.player.get_build_preview()
		check(preview.valid and not preview.cells.is_empty(), "actual controller produces supported block preview")
		var blocks: int = app.session.blocks
		var before: Dictionary = _inventory_state()
		var pulse: Dictionary = await _primary_physics_pulse()
		var built: bool = false
		if not preview.cells.is_empty():
			built = app.world.get_block(preview.cells[0]) != 0
		details["block_trigger"] = {"before": before, "after": _inventory_state(), "pulse": pulse,
			"preview_valid": preview.valid, "preview_cells": str(preview.cells), "built": built}
		check(built and app.session.blocks == blocks - 1, "ordinary block trigger edits terrain and consumes material")
	_prepare_world()
	if await _ready_tool(LocalSession.Tool.GRENADE):
		throws.clear()
		blasts.clear()
		action("primary", true)
		await get_tree().create_timer(0.2).timeout
		action("primary", false)
		var deadline: int = Time.get_ticks_msec() + 6000
		while blasts.is_empty() and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		check(throws.size() == 1 and blasts.size() == 1 and app.session.grenades == 2,
			"ordinary grenade press/release drives throw, fuse, detonation and inventory")
		details["grenade"] = {"throws": throws.size(), "explosions": blasts.size()}
	_prepare_world()
	await _ready_tool(LocalSession.Tool.WEAPON)


func _nodes(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in node.get_children():
		found.append(child)
		found.append_array(_nodes(child))
	return found


func _modules() -> void:
	var optional_classes: Dictionary = {}
	for name: String in ["CharacterBody2D", "NavigationAgent2D", "NavigationAgent3D", "XROrigin3D", "CSGBox3D", "GridMap",
		"VideoStreamTheora", "WebSocketPeer", "ENetMultiplayerPeer", "WebRTCPeerConnection", "UPNP", "VisualShader", "AudioStreamMP3"]:
		optional_classes[name] = ClassDB.class_exists(name)
	details["optional_classes"] = optional_classes
	var expression: RegEx = RegEx.new()
	check(expression.compile("^([A-Za-z]+):([0-9]+)$") == OK, "RegEx compiles anchored resource-style pattern")
	var matched: RegExMatch = expression.search("Blockfield:123")
	check(matched != null and matched.get_string(1) == "Blockfield" and matched.get_string(2) == "123"
		and expression.search("bad/input") == null, "RegEx extracts captures and rejects invalid input")
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = 328
	check(is_finite(noise.get_noise_3d(1.25, 2.5, 3.75))
		and noise.get_noise_3d(1.25, 2.5, 3.75) != noise.get_noise_3d(8.75, 3.25, 1.5),
		"retained Noise computes distinct finite camera/effect samples")
	app.set_locale("ru")
	check(OpenSpadesLocalization.text("Rifle", "Client") == "Винтовка", "original Russian catalog resolves contextual message")
	var font: Font = OpenSpadesLocalization.get_ui_font()
	for code: int in [0x0410, 0x4e2d, 0x65e5, 0xd55c]:
		check(font.has_char(code), "actual fallback contains glyph U+%04X" % code)
	check(font.get_string_size("中文 日本語 한국어", HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x > 100,
		"retained text stack shapes multilingual text with bundled fonts")
	check(multilingual.get_parsed_text() == "Русский · 中文 · 日本語 · 한국어" and multilingual.get_content_height() > 0,
		"visible RichTextLabel parses BBCode and lays out bundled multilingual glyphs")
	app.set_locale("en")
	var list: ItemList = ItemList.new()
	list.add_item("Русский")
	list.add_item("日本語")
	list.select(1)
	check(list.get_selected_items() == PackedInt32Array([1]) and list.get_item_text(1) == "日本語",
		"ItemList retains Unicode content and selection state")
	list.free()
	var color_picker: ColorPicker = ColorPicker.new()
	color_picker.color = Color(0.2, 0.4, 0.6, 1)
	check(color_picker.color.is_equal_approx(Color(0.2, 0.4, 0.6, 1)), "ColorPicker preserves selected block color")
	color_picker.free()
	var dialog: FileDialog = FileDialog.new()
	dialog.access = FileDialog.ACCESS_RESOURCES
	dialog.add_filter("*.vxl", "Voxel map")
	dialog.current_dir = "res://__probe"
	check(dialog.filters.size() == 1 and dialog.current_dir == "res://__probe", "FileDialog applies resource directory and map filter")
	dialog.free()
	var glb: PackedByteArray = FileAccess.get_file_as_bytes("res://__probe/head.glb.bin")
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	var decoded: Error = document.append_from_buffer(glb, "", state)
	check(decoded == OK and not state.get_meshes().is_empty(), "runtime GLTF reads genuine bundled Head GLB and exposes mesh data")
	if decoded == OK:
		var model: Node3D = document.generate_scene(state)
		var faces: int = 0
		if model != null:
			for node: Node in _nodes(model):
				if node is MeshInstance3D and node.mesh != null:
					faces += node.mesh.get_faces().size() / 3
		check(model != null and faces > 0, "runtime GLTF generates nonempty original triangle geometry")
		details["gltf_triangles"] = faces
		if model != null:
			model.free()
	var pack_bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://__probe/original-pack.zip")
	var loaded: Dictionary = OpenSpadesExtensions.load_pack_bytes(pack_bytes)
	check(loaded.get("ok", false) and loaded.get("resources", 0) == 3, "ZIPReader validates and decodes genuine GLB/PNG/Vorbis resource override pack")
	check(OpenSpadesExtensions.model_override("Player/Head") is PackedScene
		and OpenSpadesExtensions.texture("Gfx/AlertIcon.png") is Texture2D
		and OpenSpadesExtensions.sound("Sounds/Feedback/Alert.opus") is AudioStreamOggVorbis,
		"model, texture and audio original virtual paths resolve through loaded ZIP")
	check(OpenSpadesExtensions.remove_pack(PACK_ID) and OpenSpadesExtensions.model_override("Player/Head") == null,
		"removing override pack restores the original resource path")


func _render_and_physics() -> void:
	await get_tree().physics_frame
	var from: Vector3 = Vector3(12.5, 6.5, 13.5)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, Vector3(12.5, 6.5, 7.5))
	query.exclude = [app.player.get_rid()]
	var hit: Dictionary = app.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and hit.position.distance_to(Vector3(12.5, 6.5, 9.0)) < 0.05,
		"GodotPhysics3D query hits actual voxel collider at expected surface")
	if DisplayServer.get_name() == "headless":
		details["render_readback"] = "Skipped: headless has no GPU framebuffer"
		return
	await RenderingServer.frame_post_draw
	var pixels: Image = get_viewport().get_texture().get_image()
	var colors: Dictionary = {}
	if pixels != null and not pixels.is_empty():
		for x: int in range(0, pixels.get_width(), maxi(1, pixels.get_width() / 32)):
			for y: int in range(0, pixels.get_height(), maxi(1, pixels.get_height() / 24)):
				colors[pixels.get_pixel(x, y).to_rgba32()] = true
	check(pixels != null and not pixels.is_empty() and colors.size() > 16,
		"actual rendered Main framebuffer contains diverse scene/UI pixels")
	details["framebuffer"] = {"width": pixels.get_width() if pixels != null else 0,
		"height": pixels.get_height() if pixels != null else 0, "sample_colors": colors.size()}


func _audio() -> void:
	app.stop_audio()
	AudioServer.add_bus()
	bus = AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(bus, "TemplateWebProof")
	capture = AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(bus, capture)
	proof_player = AudioStreamPlayer.new()
	# Web DEFAULT selects browser SAMPLE playback, which bypasses Godot bus
	# effects. Production voices explicitly STREAM through the same mixer.
	proof_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	proof_player.bus = "TemplateWebProof"
	add_child(proof_player)
	details["audio_driver"] = {"driver": AudioServer.get_driver_name(), "mix_rate": AudioServer.get_mix_rate(),
		"speaker_mode": AudioServer.get_speaker_mode(), "playback_type": proof_player.playback_type,
		"playback_mode": "STREAM", "project_default": ProjectSettings.get_setting_with_override("audio/general/default_playback_type"),
		"bus": proof_player.bus, "bus_volume_db": AudioServer.get_bus_volume_db(bus),
		"bus_muted": AudioServer.is_bus_mute(bus), "master_muted": AudioServer.is_bus_mute(0)}
	var pcm: AudioStream = OpenSpadesExtensions.sound("Sounds/Weapons/Rifle/FireStereo.opus")
	var ogg: AudioStream = load("res://assets/openspades/sounds/Feedback/Alert.ogg") as AudioStream
	check(pcm is AudioStreamWAV and pcm.get_length() > 0.1, "selected original firing sample remains decoded PCM WAV")
	check(ogg is AudioStreamOggVorbis and ogg.get_length() > 0.01, "original alert remains an Ogg Vorbis stream")
	if DisplayServer.get_name() == "headless":
		details["audio_capture"] = "Skipped: headless audio backend cannot establish browser activation"
	else:
		var records: Array[Dictionary] = []
		for stream: AudioStream in [pcm, ogg]:
			if stream == null:
				continue
			proof_player.stop()
			await get_tree().create_timer(0.1).timeout
			capture.clear_buffer()
			var discarded: int = capture.get_discarded_frames()
			proof_player.stream = stream
			proof_player.play()
			var started: int = Time.get_ticks_usec()
			var playing_at_start: bool = proof_player.playing
			var energy: float = 0.0
			var frames: int = 0
			var nonzero_frames: int = 0
			var first_signal_ms: float = -1.0
			var finite: bool = true
			var deadline: int = Time.get_ticks_msec() + 4000
			while frames < AudioServer.get_mix_rate() / 4 and Time.get_ticks_msec() < deadline:
				await get_tree().create_timer(0.02).timeout
				var available: int = capture.get_frames_available()
				if available == 0:
					continue
				for sample: Vector2 in capture.get_buffer(available):
					energy += sample.length_squared()
					if sample.length_squared() > 0.00000000000001:
						nonzero_frames += 1
						if first_signal_ms < 0.0:
							first_signal_ms = float(Time.get_ticks_usec() - started) / 1000.0
					finite = finite and sample.is_finite()
					frames += 1
			var record: Dictionary = {"class": stream.get_class(), "frames": frames,
				"rms": sqrt(energy / maxf(1.0, frames * 2.0)), "finite": finite,
				"overflow": capture.get_discarded_frames() - discarded, "playback_type": proof_player.playback_type,
				"playing_at_start": playing_at_start, "playing_at_end": proof_player.playing,
				"playback_position": proof_player.get_playback_position(), "stream_length": stream.get_length(),
				"capture_wall_ms": float(Time.get_ticks_usec() - started) / 1000.0,
				"nonzero_frames": nonzero_frames, "first_signal_ms": first_signal_ms}
			records.append(record)
			check(frames >= AudioServer.get_mix_rate() / 4 and finite and record.rms > 0.00001 and record.overflow == 0,
				"real Web mixer decodes finite audible samples with no capture overflow: " + stream.get_class())
		details["audio_capture"] = records
	proof_player.stop()
	proof_player.stream = null
	proof_player.queue_free()
	AudioServer.remove_bus_effect(bus, 0)
	AudioServer.remove_bus(bus)
	bus = -1
	await get_tree().process_frame


func _optional_tdm() -> void:
	# Dynamic loading keeps this same fixture compatible with the fe843 baseline
	# while exercising the later authored bot/navigation scripts when present.
	var path: String = "res://scenes/offline_tdm.tscn"
	if not ResourceLoader.exists(path):
		details["offline_tdm"] = {"available": false, "reason": "This frozen source predates offline 3x3"}
		return
	phase = "Latest offline 3×3: genuine scene, five bots and voxel routes"
	_publish()
	var scene: PackedScene = load(path) as PackedScene
	check(scene != null, "latest offline TDM scene and authored bot resources load")
	if scene == null:
		return
	_release()
	app.stop_audio()
	app.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	app = scene.instantiate()
	add_child(app)
	app.set_locale("en")
	app.hud.set_mobile_controls_mode(2)
	await get_tree().physics_frame
	await get_tree().process_frame
	check(app.session.has_method("get_diagnostics"), "latest TDM instantiates its shared-authority adapter")
	if not app.session.has_method("get_diagnostics"):
		return
	var initial: Dictionary = app.session.get_diagnostics()
	check(initial.bot_count == 5 and initial.team_counts == [3, 3]
		and app.session.simulation.actors.size() == 6 and app._target_nodes.size() == 5,
		"latest TDM loads exactly one human, five bot actors and five soldier views")
	check(initial.paused and app.hud.is_menu_open() and not app.player.controls_enabled,
		"latest TDM entry menu pauses all shared actors")
	app.hud.set_menu_visible(false)
	var start_tick: int = app.session.simulation.tick
	var deadline: int = Time.get_ticks_msec() + 20000
	while app.session.simulation.tick - start_tick < 240 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var diagnostics: Dictionary = app.session.get_diagnostics()
	var bots: Dictionary = diagnostics.bots
	var moved: int = 0
	for bot: Dictionary in bots.bots:
		if float(bot.distance_moved) > 0.1:
			moved += 1
	check(diagnostics.tick - start_tick >= 240, "latest TDM advances at least four seconds through normal controller physics")
	check(moved == 5, "all five latest bots physically move through shared voxel collision")
	check(bots.navigation.path_requests > 0 and bots.navigation.expanded_nodes > 0,
		"latest bots plan and expand authored voxel routes")
	app.hud.set_menu_visible(true)
	var paused_tick: int = app.session.simulation.tick
	await get_tree().create_timer(0.25).timeout
	check(app.session.simulation.tick == paused_tick and app.session.paused,
		"latest TDM pause freezes the bot and human authority clock")
	details["offline_tdm"] = {"available": true, "diagnostics": diagnostics,
		"rendered_bots": app._target_nodes.size(), "bots_moved": moved}
	# Leave the actual TDM visible for the coordinator's final browser screenshot.
	app.hud.set_menu_visible(false)


func _exit_tree() -> void:
	if is_instance_valid(proof_player):
		proof_player.stop()
		proof_player.stream = null
	if is_instance_valid(app):
		app.stop_audio()
	if bus >= 0:
		AudioServer.remove_bus_effect(bus, 0)
		AudioServer.remove_bus(bus)
