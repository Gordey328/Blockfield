extends Node
## Test-only exported scene: genuine offline TDM plus visible diagnostic controls.
## Normal Pages entry stays unchanged. Use export_offline_tdm_probe.py on a freeze.
const TDM_SCENE = preload("res://scenes/offline_tdm.tscn")
var app: Node3D
var status: Label
var busy: bool = false
var clock: float = 0.0
var assertions: int = 0
var failures: int = 0
var shared_shots: int = 0
var bot_shots: int = 0
var deaths: int = 0
var phase: String = "Ready — use the normal match menu"


func _ready() -> void:
	app = TDM_SCENE.instantiate()
	add_child(app)
	app.set_locale("en")
	app.session.match_event.connect(_on_event)
	var overlay := CanvasLayer.new()
	overlay.layer = 20
	add_child(overlay)
	var panel := VBoxContainer.new()
	panel.position = Vector2(12, 94)
	panel.size = Vector2(350, 240)
	overlay.add_child(panel)
	for spec: Array in [["Read match diagnostics", _report], ["Walk + fire through controller (2s)", _input_scenario], ["Pause and prove frozen tick", _pause_scenario]]:
		var button := Button.new()
		button.text = spec[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(spec[1])
		panel.add_child(button)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(350, 140)
	status.add_theme_color_override("font_color", Color.WHITE)
	status.add_theme_color_override("font_outline_color", Color.BLACK)
	status.add_theme_constant_override("outline_size", 5)
	panel.add_child(status)
	_report()


func _on_event(event: Dictionary) -> void:
	if event.type == "shot":
		shared_shots += 1
		if int(event.get("owner_id", app.session.local_player_id())) != app.session.local_player_id():
			bot_shots += 1
	elif event.type == "death":
		deaths += 1


func _process(delta: float) -> void:
	clock += delta
	if clock < .25:
		return
	clock = 0.0
	_publish()


func _publish() -> void:
	if not is_instance_valid(app) or status == null:
		return
	var diagnostics: Dictionary = app.session.get_diagnostics()
	var bots: Dictionary = diagnostics.bots
	status.text = "TEST-ONLY ACTUAL TDM — " + phase + "\n" \
		+ "3×3 / bots %d / tick %d / paused %s\n" % [diagnostics.bot_count, diagnostics.tick, diagnostics.paused] \
		+ "Score %s / time %.1f / health %d\n" % [str(diagnostics.scores), diagnostics.time_remaining, app.session.health] \
		+ "Shared shots %d / bot shots %d / deaths %d\n" % [shared_shots, bot_shots, deaths] \
		+ "Cover %d / flank %d / checks %d / failures %d" % [bots.cover_decisions, bots.flank_decisions, assertions, failures]
	var report := {"diagnostics": diagnostics, "shared_shots": shared_shots, "bot_shots": bot_shots, "deaths": deaths,
		"checks": assertions, "failures": failures, "phase": phase, "player_feet": app.player.global_position,
		"magazine": app.session.magazine, "health": app.session.health, "rendered_bots": app._target_nodes.size()}
	JavaScriptBridge.eval("window.offlineTDMProbe=" + JSON.stringify(report) + ";", true)


func _report() -> void:
	_publish()
	print("OFFLINE TDM WEB: " + JSON.stringify(app.session.get_diagnostics()))


func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
	print("OFFLINE TDM WEB: " + ("PASS " if value else "FAIL ") + message)


func action(name: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _input_scenario() -> void:
	if busy or app.session.finished:
		return
	busy = true
	phase = "Normal controller movement and fire"
	app.hud.set_menu_visible(false)
	var deadline: int = Time.get_ticks_msec() + 10000
	while not app.player.can_use_tool() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var point: Vector3 = app.player.global_position
	var shots: int = app.session.shots_fired
	action("forward", true)
	action("primary", true)
	await get_tree().create_timer(2.0).timeout
	action("forward", false)
	action("primary", false)
	await get_tree().physics_frame
	await get_tree().process_frame
	check(app.player.global_position.distance_to(point) > .2, "ordinary forward action moves the rendered player")
	check(app.session.shots_fired > shots, "ordinary trigger receives confirmed shared shots")
	check(app.session.simulation.actors.size() == 6 and app._target_nodes.size() == 5, "controller input retains exactly one human and five rendered bots")
	phase = "Movement and fire complete — bots continue fighting"
	busy = false
	_report()


func _pause_scenario() -> void:
	if busy:
		return
	busy = true
	phase = "Pause: tick must stop for one real second"
	app.hud.set_menu_visible(true)
	var tick: int = app.session.simulation.tick
	await get_tree().create_timer(1.0).timeout
	check(app.session.simulation.tick == tick and not app.player.controls_enabled, "actual HUD pause freezes human and bot authority")
	app.hud.set_menu_visible(false)
	await get_tree().create_timer(.25).timeout
	check(app.session.finished or app.session.simulation.tick > tick, "resume advances the shared match")
	phase = "Pause/resume complete"
	busy = false
	_report()


func _exit_tree() -> void:
	Input.action_release("forward")
	Input.action_release("primary")
	if is_instance_valid(app):
		app.stop_audio()
