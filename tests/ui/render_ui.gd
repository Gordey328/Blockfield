extends SceneTree
## Real Compatibility render QA. No headless renderer; settings are restored.
const MAIN_SCENE=preload("res://scenes/main.tscn")
var app: Node3D
var hud: LabHUD
var session: LocalSession
var player: BlockfieldPlayer
var output: String
var _settings_before:=PackedByteArray()
var _settings_existed:=false

func _initialize() -> void:call_deferred("_run")

func _run() -> void:
	output=ProjectSettings.globalize_path("res://../.cache/previews/ui")
	DirAccess.make_dir_recursive_absolute(output)
	# Recover from a terminated renderer before taking a new preference snapshot.
	if FileAccess.file_exists("user://ui-render-settings-before.bin"):
		var backup:=FileAccess.get_file_as_bytes("user://ui-render-settings-before.bin")
		if not backup.is_empty():
			_settings_existed=backup[0]==1
			_settings_before=backup.slice(1)
			restore_settings()
	_settings_existed=FileAccess.file_exists("user://settings.cfg")
	if _settings_existed:_settings_before=FileAccess.get_file_as_bytes("user://settings.cfg")
	var backup_file:=FileAccess.open("user://ui-render-settings-before.bin",FileAccess.WRITE)
	backup_file.store_8(1 if _settings_existed else 0)
	backup_file.store_buffer(_settings_before)
	backup_file.close()
	ConfigFile.new().save("user://settings.cfg")
	app=MAIN_SCENE.instantiate()
	root.add_child(app)
	if not app.has_method("set_locale"):
		push_error("UI_GPU: main script failed to load")
		app.queue_free()
		await process_frame
		restore_settings()
		quit(1)
		return
	app.set_locale("ru")
	hud=app.get_node("HUD")
	session=app.get_node("LocalSession")
	player=app.get_node("Player")
	await capture("menu")
	hud.set_menu_visible(false)
	player.respawn_at(Vector3(48.5,4.01,70.5))
	await process_frame
	await process_frame
	await capture("hud")
	hud.toggle_scoreboard()
	await capture("scoreboard")
	hud.toggle_scoreboard()
	hud.toggle_map()
	await capture("map")
	hud.toggle_map()
	for index in 25:hud._chat.receive("Тестовое сообщение %d — Unicode кириллица"%index,"Player",index%2==0,index%2)
	hud.open_chat(true)
	hud._chat.set_input_text("Можно проверить оружие без сервера")
	await capture("chat")
	hud._chat.cancel_input()
	session.invulnerable=false
	session.damage_player(40,player.global_position+Vector3.RIGHT*8,"weapon")
	hud._status_effects.set_process(false)
	hud._status_effects._process(.05)
	await capture("hurt")
	hud._status_effects._process(4)
	hud._status_effects.set_process(true)
	session.configure_tc([player.global_position+Vector3(4,0,0)])
	session.set_mode("tc")
	session.territories[0].capturing_team=0
	session.territories[0].progress=.6
	await capture("tc")
	session.winning_team=0
	await capture("results")
	session.set_team_info(0,"Оранжевые",Color(.8,.2,.1))
	session.set_team_info(1,"Бирюзовые",Color(.1,.7,.9))
	session.winning_team=-1
	app.spawn_lab_target(false,0)
	app.spawn_lab_target(true,1)
	hud.set_menu_visible(true)
	# Open the actual Soldiers tab containing team metadata and spawn controls.
	var tabs: TabContainer=find_tabs(hud._menu)
	tabs.current_tab=1
	await capture("custom_teams_menu")
	var scroll: ScrollContainer=tabs.get_tab_control(1).get_child(0)
	scroll.scroll_vertical=int(scroll.get_v_scroll_bar().max_value)
	await capture("target_spawn_controls")
	hud.set_menu_visible(false)
	hud.toggle_scoreboard()
	await capture("custom_teams_scoreboard")
	hud.toggle_scoreboard()
	session.set_mode("sandbox")
	await capture("spawned_targets")
	session.select_tool(LocalSession.Tool.BLOCK)
	player.block_color=LabPalette.palette_colors()[19]
	await capture("native_palette")
	app.stop_audio()
	await process_frame
	await process_frame
	app.queue_free()
	await process_frame
	await process_frame
	await process_frame
	restore_settings()
	print("UI_GPU: 13 captures saved to "+output)
	quit()

func restore_settings() -> void:
	if _settings_existed:
		var file:=FileAccess.open("user://settings.cfg",FileAccess.WRITE)
		file.store_buffer(_settings_before)
		file.close()
	else:DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	if FileAccess.file_exists("user://ui-render-settings-before.bin"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ui-render-settings-before.bin"))

func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	image.save_png(output.path_join(name+".png"))

func find_tabs(node: Node) -> TabContainer:
	if node is TabContainer:return node
	for child in node.get_children():
		var result:=find_tabs(child)
		if result!=null:return result
	return null
