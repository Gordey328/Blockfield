extends Node
## Test-only Web scene: genuine Main/Controller/HUD with visible, timed scenarios.
## Packaged separately by tools/browser_fidelity_probe.py; never in Pages release.
const MAIN = preload("res://scenes/main.tscn")
const CELL := Vector3i(16,6,12)
var app: Node3D
var status: Label
var busy := false
var phase := "Ready"
var throws: Array[Dictionary] = []
var assertions := 0
var failures := 0

func _ready() -> void:
	app = MAIN.instantiate()
	add_child(app)
	app.set_locale("en")
	app.hud.set_mobile_controls_mode(2)
	app.hud.set_menu_visible(false)
	app.session.invulnerable = true
	app.session.unlimited_ammo = false
	for soldier: Node3D in app._target_nodes: soldier.queue_free()
	app._target_nodes.clear()
	app.session.targets.clear()
	prepare_world()
	app.session.grenade_thrown.connect(func(e: Dictionary):throws.append(e.duplicate(true)))
	var overlay := CanvasLayer.new()
	overlay.layer = 10
	add_child(overlay)
	var panel := VBoxContainer.new()
	panel.position = Vector2(12,90)
	panel.size = Vector2(280,160)
	overlay.add_child(panel)
	for spec in [["Block damage +10s recovery",_block],["Held grenade regression",_grenade],["Scoreboard colors ON",_colors.bind(true)],["Scoreboard colors OFF",_colors.bind(false)]]:
		var button := Button.new()
		button.text = spec[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(spec[1])
		panel.add_child(button)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(280,90)
	panel.add_child(status)
	print("FIDELITY WEB: test-only actual Main ready")

func prepare_world() -> void:
	app.world.clear_world(Vector3i(32,16,32))
	app.world.water_enabled = false
	app.world.data.seed_box(Vector3i.ZERO,Vector3i(32,4,32),0x01608070)
	for y in range(4,8): app.world.set_block(Vector3i(16,y,12),0x01ff8041)
	app.world._mark_all_chunks()
	app.world.rebuild_now()
	app.player.respawn_at(Vector3(16.5,4.01,17.5))
	app.player.rotation.y = 0
	app.player.head.rotation.x = 0

func _process(_delta: float) -> void:
	if status == null: return
	status.text = "TEST SCENE — " + phase + "\n" \
		+ "Block damaged: %s / original RGB: %06x\n"%[app.world.is_block_damaged(CELL),app.world.get_block(CELL)&0xffffff] \
		+ "Grenades: %d / cooking: %s / throws: %d\n"%[app.session.grenades,app.session.is_cooking_grenade,throws.size()] \
		+ "%d checks / %d failures"%[assertions,failures]

func check(ok: bool,message: String) -> void:
	assertions += 1
	if not ok: failures += 1
	print("FIDELITY WEB: ","PASS " if ok else "FAIL ",message)

func ready_tool(tool: int) -> bool:
	Input.action_release("primary")
	app.hud._scoreboard.hide()
	app.session.restock()
	app.session.select_weapon(LocalSession.Weapon.RIFLE)
	app.session.select_tool(tool)
	var deadline := Time.get_ticks_msec()+10000
	while not app.player.can_use_tool() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	if not app.player.can_use_tool():
		check(false,"tool readiness timed out")
		phase = "Readiness failed"; busy = false
		return false
	return true

func _block() -> void:
	if busy: return
	busy = true
	phase = "Block: source shot"
	prepare_world()
	if not await ready_tool(LocalSession.Tool.WEAPON): return
	app.player.rotation.y = 0
	app.player.head.rotation.x = 0
	app.world.set_block(CELL,0x01ff8041)
	Input.action_press("primary")
	await get_tree().create_timer(.05).timeout
	Input.action_release("primary")
	check(app.world.is_block_damaged(CELL) and app.world.get_block(CELL)==0x01ff8041,"real controller shot darkens surviving block")
	phase = "Block: damaged (wait10 seconds)"
	await get_tree().create_timer(10.2).timeout
	check(not app.world.is_block_damaged(CELL) and app.world.get_block(CELL)==0x01ff8041,"latest-hit ten-second recovery preserves original RGB")
	phase = "Block: recovered"
	busy = false

func _grenade() -> void:
	if busy: return
	busy = true
	phase = "Grenade: hold primary"
	prepare_world()
	if not await ready_tool(LocalSession.Tool.GRENADE): return
	throws.clear()
	Input.action_press("primary")
	var deadline := Time.get_ticks_msec()+8000
	while throws.is_empty() and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	if throws.is_empty():
		check(false,"automatic throw timed out")
		Input.action_release("primary")
		phase = "Grenade input failed"; busy = false
		return
	check(throws.size()==1 and throws[0].automatic and is_zero_approx(app.session.grenade_cooldown),"automatic throw has no manual-release cooldown")
	phase = "Grenade: primary still held"
	await get_tree().create_timer(1.2).timeout
	check(throws.size()==1 and app.session.grenades==2 and not app.session.is_cooking_grenade,"continuous held press cannot cook next grenade")
	Input.action_release("primary")
	await get_tree().physics_frame
	await get_tree().process_frame
	Input.action_press("primary")
	await get_tree().physics_frame
	await get_tree().process_frame
	check(app.session.is_cooking_grenade,"new press starts next cook")
	await get_tree().create_timer(.2).timeout
	Input.action_release("primary")
	await get_tree().physics_frame
	await get_tree().process_frame
	check(throws.size()==2 and not throws[1].automatic and app.session.grenade_cooldown>0.4,"manual release retains half-second delay")
	phase = "Grenade: regression complete"
	busy = false

func _colors(enabled: bool) -> void:
	if busy: return
	if app.session.targets.is_empty():
		var green: int = app.session.add_target(Vector3(25.5,4.01,16.5),0)
		var row: Dictionary = app.session.get_target(green)
		row.id = 7; row.name = "Palette green"; row.score = 4
		var yellow: int = app.session.add_target(Vector3(27.5,4.01,16.5),1)
		row = app.session.get_target(yellow)
		row.id = 3; row.name = "Palette yellow / dead"; row.score = 2
		row.alive = false; row.health = 0; row.respawn_remaining = -1.0
	app.hud.set_console_setting("minimap_player_colors",enabled)
	app.hud._scoreboard.show()
	phase = "Scoreboard: colors " + ("ON" if enabled else "OFF")
	check(app.hud._scoreboard.per_player_colors==enabled and app.hud._map.per_player_colors==enabled,"scoreboard and map share live preference")
