extends SceneTree
## Actual Compatibility pixels, source palette goldens and live HUD preferences.
const MAIN_SCENE=preload("res://scenes/main.tscn")
const BACKUP_PATH: String="user://scoreboard-colors-settings-before.bin"
var app: Node3D
var hud: LabHUD
var session: LocalSession
var board: LabScoreboard
var network_view: NetworkSession
var assertions: int=0
var failures: int=0
var output: String
var _settings_before:=PackedByteArray()
var _settings_existed: bool=false

func _initialize() -> void:call_deferred("_run")

func check(condition: bool,message: String) -> void:
	assertions+=1
	if not condition:failures+=1;push_error("SCOREBOARD_COLORS_GPU: "+message)

func _run() -> void:
	output=ProjectSettings.globalize_path("res://../.cache/previews/scoreboard-colors")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output=argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	if FileAccess.file_exists(BACKUP_PATH):
		var previous:=FileAccess.get_file_as_bytes(BACKUP_PATH)
		_settings_existed=not previous.is_empty() and previous[0]==1
		_settings_before=previous.slice(1)
		restore_settings()
	_settings_existed=FileAccess.file_exists("user://settings.cfg")
	if _settings_existed:_settings_before=FileAccess.get_file_as_bytes("user://settings.cfg")
	var backup:=FileAccess.open(BACKUP_PATH,FileAccess.WRITE)
	backup.store_8(1 if _settings_existed else 0)
	backup.store_buffer(_settings_before)
	backup.close()
	ConfigFile.new().save("user://settings.cfg")
	root.size=Vector2i(1280,720)
	root.content_scale_size=Vector2i(1280,720)
	app=MAIN_SCENE.instantiate()
	root.add_child(app)
	if not app.has_method("set_locale"):
		check(false,"main script loads")
		await finish()
		return
	app.set_locale("en")
	hud=app.get_node("HUD")
	session=app.get_node("LocalSession")
	board=hud._scoreboard
	await process_frame
	await process_frame
	app.set_process(false)
	app.get_node("Player").set_physics_process(false)
	hud.set_process(false)
	app.post_effects.set_process(false)
	app.effects.set_process(false)
	for child: Node in app.get_children():
		if child is LabSoldier:child.set_process(false)
	hud.set_mobile_controls_mode(2)
	hud.set_menu_visible(false)
	hud._hud.hide()
	# An opaque backing makes the text measurement independent of world motion.
	board.add_theme_stylebox_override("panel",hud._style(Color(.06,.1,.13,1),Color("536f7a")))
	app.player_name="Local [b]"
	session.team=0
	session.health=100
	session.score=30
	session.targets.assign([
		{"id":7,"name":"Alive [b]","team":0,"score":20,"deaths":0,"alive":true},
		{"id":3,"name":"Dead","team":1,"score":10,"deaths":1,"alive":false}
	])
	board.show()
	hud.set_console_setting("minimap_player_colors",true)
	var enabled: Image=await capture("offline_enabled")
	# Independently calculated source ModifyColor goldens for black, green,
	# yellow. They are not obtained from the production palette/color helper.
	check_id_pixels(enabled,0,0,Color(.2,.2,.2),"offline local slot0")
	check_id_pixels(enabled,0,7,Color(1.0/3.0,11.0/15.0,1.0/3.0),"alive remote slot7")
	check_id_pixels(enabled,1,3,Color(13.0/15.0,13.0/15.0,7.0/15.0),"dead remote slot3")
	var checkbox: CheckButton=hud._ui_settings_controls.minimap_player_colors
	checkbox.button_pressed=false
	var disabled: Image=await capture("offline_disabled")
	check_id_pixels(disabled,0,0,Color.WHITE,"disabled local ID")
	check_id_pixels(disabled,0,7,Color.WHITE,"disabled alive ID")
	check_id_pixels(disabled,1,3,Color.WHITE,"disabled dead ID")
	for row: Dictionary in [{"team":0,"id":0},{"team":0,"id":7},{"team":1,"id":3}]:
		check(suffix_difference(enabled,disabled,int(row.team),int(row.id))==0,"name and score pixels retain local/alive/dead tint when toggling slot"+str(row.id))
	check(not board.per_player_colors and not hud._map.per_player_colors and not hud._large_map.per_player_colors,"actual checkbox reaches all three views")
	hud._send_chat("/cg_minimapPlayerColor 1")
	var console_enabled: Image=await capture("console_enabled")
	check_id_pixels(console_enabled,0,7,Color(1.0/3.0,11.0/15.0,1.0/3.0),"chat cvar re-enabled ID")
	check(checkbox.button_pressed and board.per_player_colors,"chat cvar refreshes actual checkbox and scoreboard")
	hud.set_console_setting("minimap_player_colors",false)
	hud._map_player_colors=true
	hud._apply_map_settings()
	hud._load_ui_settings()
	var loaded: Image=await capture("loaded_disabled")
	check_id_pixels(loaded,1,3,Color.WHITE,"loaded disabled preference")
	check(not board.per_player_colors and not checkbox.button_pressed,"preference reload reaches scoreboard and widget")

	# Real adapter identity: source slots wrap through the shared 32-color
	# palette while protocol IDs remain unchanged in the printed scoreboard.
	var replica:=BlockfieldClientReplica.new()
	replica.actor_id=35
	network_view=NetworkSession.new()
	network_view.bind_replica(replica)
	network_view.team=1
	network_view.health=100
	network_view.score=99
	network_view.targets.assign([
		{"id":7,"name":"Remote canonical","team":1,"score":4,"deaths":0,"alive":true},
		{"id":3,"name":"Dead canonical","team":1,"score":2,"deaths":1,"alive":false}
	])
	board.session=network_view
	hud.set_console_setting("minimap_player_colors",true)
	var network: Image=await capture("network_canonical_ids")
	check_id_pixels(network,1,35,Color(13.0/15.0,13.0/15.0,7.0/15.0),"canonical owner35 wraps source palette to slot3")
	check_id_pixels(network,1,7,Color(1.0/3.0,11.0/15.0,1.0/3.0),"canonical remote7")
	check_id_pixels(network,1,3,Color(13.0/15.0,13.0/15.0,7.0/15.0),"canonical dead3")
	check(board._columns[1].get_parsed_text().contains("#35   Local [b]") and not board._columns[1].get_parsed_text().contains("#00"),"network text retains canonical owner ID and literal name")
	await finish()

func capture(name: String) -> Image:
	board._process(0)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image=root.get_texture().get_image()
	check(image.save_png(output.path_join(name+".png"))==OK,"save actual GPU capture: "+name)
	return image

func row_region(team: int,id: int,id_only: bool) -> Rect2i:
	var label: RichTextLabel=board._columns[team]
	var text: String=label.get_parsed_text()
	var id_text: String="#%02d"%id
	var index: int=text.find(id_text+"   ")
	if index<0:return Rect2i()
	var line: int=label.get_character_line(index)
	var font: Font=label.get_theme_font("normal_font")
	var font_size: int=label.get_theme_font_size("normal_font_size")
	var id_width: int=ceili(font.get_string_size(id_text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x)
	var point: Vector2=label.global_position+Vector2(0,label.get_line_offset(line))
	var region:=Rect2i(Vector2i(point),Vector2i(id_width+2,label.get_line_height(line)))
	if not id_only:
		region.position.x+=id_width+8
		region.size.x=maxi(0,int(label.size.x)-id_width-8)
	return region

func check_id_pixels(image: Image,team: int,id: int,expected: Color,message: String) -> void:
	var region: Rect2i=row_region(team,id,true).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	var count: int=0
	for y: int in range(region.position.y,region.end.y):
		for x: int in range(region.position.x,region.end.x):
			var color: Color=image.get_pixel(x,y)
			if absf(color.r-expected.r)<.045 and absf(color.g-expected.g)<.045 and absf(color.b-expected.b)<.045:count+=1
	check(count>=6,message+" renders source-golden #ID pixels ("+str(count)+")")

func suffix_difference(first: Image,second: Image,team: int,id: int) -> int:
	var region: Rect2i=row_region(team,id,false).intersection(Rect2i(Vector2i.ZERO,first.get_size()))
	var count: int=0
	for y: int in range(region.position.y,region.end.y):
		for x: int in range(region.position.x,region.end.x):
			var a: Color=first.get_pixel(x,y)
			var b: Color=second.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>.02:count+=1
	return count

func restore_settings() -> void:
	if _settings_existed:
		var file:=FileAccess.open("user://settings.cfg",FileAccess.WRITE)
		file.store_buffer(_settings_before)
		file.close()
	else:DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP_PATH))

func finish() -> void:
	if is_instance_valid(board):board.session=session
	if is_instance_valid(network_view):network_view.free()
	if is_instance_valid(app):
		if app.has_method("stop_audio"):app.stop_audio()
		await process_frame
		await process_frame
		app.queue_free()
		for index: int in 5:await process_frame
	restore_settings()
	print("SCOREBOARD_COLORS_GPU: %d assertions, %d failures; captures %s"%[assertions,failures,output])
	quit(0 if failures==0 else 1)
