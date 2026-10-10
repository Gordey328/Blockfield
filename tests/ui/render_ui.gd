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
	_settings_existed=FileAccess.file_exists("user://settings.cfg")
	if _settings_existed:_settings_before=FileAccess.get_file_as_bytes("user://settings.cfg")
	ConfigFile.new().save("user://settings.cfg")
	app=MAIN_SCENE.instantiate()
	root.add_child(app)
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
	session.configure_tc([player.global_position+Vector3(4,0,0)])
	session.set_mode("tc")
	session.territories[0].capturing_team=0
	session.territories[0].progress=.6
	await capture("tc")
	session.winning_team=0
	await capture("results")
	app.stop_audio()
	await process_frame
	await process_frame
	app.queue_free()
	await process_frame
	await process_frame
	await process_frame
	if _settings_existed:
		var file:=FileAccess.open("user://settings.cfg",FileAccess.WRITE)
		file.store_buffer(_settings_before)
		file.close()
	else:DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	print("UI_GPU: 8 captures saved to "+output)
	quit()

func capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	image.save_png(output.path_join(name+".png"))
