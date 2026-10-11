extends SceneTree
## Actual Compatibility-rendered combat screenshots; restores user preferences.
const LAB = preload("res://scenes/main.tscn")
const TDM = preload("res://scenes/offline_tdm.tscn")
var app: Node3D
var hud: LabHUD
var session: LocalSession
var original := PackedByteArray()
var existed: bool = false
var folder: String

func _initialize() -> void: call_deferred("run")

func run() -> void:
	existed=FileAccess.file_exists("user://settings.cfg")
	if existed: original=FileAccess.get_file_as_bytes("user://settings.cfg")
	ConfigFile.new().save("user://settings.cfg")
	folder=ProjectSettings.globalize_path("res://../.cache/previews/combat-ui")
	DirAccess.make_dir_recursive_absolute(folder)
	app=LAB.instantiate()
	root.add_child(app)
	await frames(4)
	hud=app.get_node("HUD")
	session=app.get_node("LocalSession")
	app.set_locale("ru")
	hud.set_mobile_controls_mode(2)
	hud.set_menu_visible(false)
	await capture("desktop-rifle")
	session.invulnerable=false
	session.health=23
	session.select_weapon(1)
	session.magazine=4
	await capture("desktop-low-health")
	session.select_tool(1)
	await capture("desktop-blocks")
	session.health=100
	session.select_tool(3)
	session.is_cooking_grenade=true
	session.grenade_cook_time=1.1
	await capture("desktop-grenade")
	session.is_cooking_grenade=false
	session.select_tool(2)
	root.size=Vector2i(844,390)
	hud.set_mobile_controls_mode(1)
	await capture("touch-landscape")
	root.size=Vector2i(390,844)
	hud._update_mobile_layout()
	await capture("touch-portrait")
	await free_app()
	root.size=Vector2i(1280,720)
	app=TDM.instantiate()
	root.add_child(app)
	await frames(4)
	hud=app.get_node("HUD")
	session=app.get_node("LocalSession")
	app.set_locale("ru")
	hud.set_mobile_controls_mode(2)
	hud.set_menu_visible(false)
	await capture("team-battle")
	await free_app()
	if existed:
		var file:=FileAccess.open("user://settings.cfg",FileAccess.WRITE)
		file.store_buffer(original)
	else: DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	print("COMBAT RENDER: 7 actual scene captures; "+folder)
	quit()

func frames(count: int) -> void:
	for index: int in count: await process_frame

func capture(title: String) -> void:
	# Let progressive terrain/map preparation finish before judging pixels.
	await create_timer(0.6).timeout
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(title+".png"))

func free_app() -> void:
	app.stop_audio()
	await frames(2)
	app.queue_free()
	await frames(4)
