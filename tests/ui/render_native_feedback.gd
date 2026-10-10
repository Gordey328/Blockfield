extends SceneTree
## Real Compatibility pixels for native source reticle/feedback and lab controls.
const MAIN_SCENE=preload("res://scenes/main.tscn")
var app: Node3D
var hud: LabHUD
var session: LocalSession
var player: BlockfieldPlayer
var assertions:=0
var failures:=0
var output: String
var _settings_before:=PackedByteArray()
var _settings_existed:=false

func _initialize() -> void:call_deferred("_run")
func check(condition: bool,message: String) -> void:
	assertions+=1
	if not condition:failures+=1;push_error("NATIVE_UI_GPU: "+message)

func _run() -> void:
	output=ProjectSettings.globalize_path("res://../.cache/previews/native-ui")
	DirAccess.make_dir_recursive_absolute(output)
	if FileAccess.file_exists("user://native-ui-settings-before.bin"):
		var previous:=FileAccess.get_file_as_bytes("user://native-ui-settings-before.bin")
		_settings_existed=not previous.is_empty() and previous[0]==1
		_settings_before=previous.slice(1)
		restore_settings()
	_settings_existed=FileAccess.file_exists("user://settings.cfg")
	if _settings_existed:_settings_before=FileAccess.get_file_as_bytes("user://settings.cfg")
	var backup:=FileAccess.open("user://native-ui-settings-before.bin",FileAccess.WRITE)
	backup.store_8(1 if _settings_existed else 0)
	backup.store_buffer(_settings_before)
	backup.close()
	ConfigFile.new().save("user://settings.cfg")
	app=MAIN_SCENE.instantiate()
	root.add_child(app)
	if not app.has_method("set_locale"):
		check(false,"main script loads")
		await finish()
		return
	app.set_locale("en")
	hud=app.get_node("HUD")
	session=app.get_node("LocalSession")
	player=app.get_node("Player")
	await process_frame
	await process_frame
	app.set_process(false)
	player.set_physics_process(false)
	hud.set_process(false)
	app.post_effects.set_process(false)
	app.effects.set_process(false)
	hud.set_menu_visible(false)
	player.respawn_at(Vector3(48.5,4.01,70.5))
	player._sync_camera_mode()
	player._update_camera_transform()
	session.select_tool(2)
	player._aim_down_state=0.0
	hud._update_reticle(0)
	hud._cross.hide()
	hud._hit.hide()
	var baseline: Image=await capture("baseline")
	hud._update_reticle(0)
	var sight: Image=await capture("original_sight")
	check(center_difference(baseline,sight)>30,"original Sight visibly changes screen-center pixels")
	player.sprinting=true
	hud._update_reticle(0)
	check(hud._cross.visible,"source sprint sight remains visible")
	player.sprinting=false
	hud.show_hit("head",100,false)
	hud._cross.hide()
	var hostile: Image=await capture("hostile_hit")
	var hostile_pixels:=center_colored_pixels(hostile,false)
	check(hostile_pixels>=12 and hostile_pixels<128,"native hostile hit renders sparse source red pixels, not opaque rectangle")
	hud.show_hit("arms",18,true)
	hud._cross.hide()
	var friendly: Image=await capture("friendly_hit")
	var friendly_pixels:=center_colored_pixels(friendly,true)
	check(friendly_pixels>=12 and friendly_pixels<128,"native friendly hit renders sparse source green pixels")
	check(center_difference(hostile,friendly)>30,"friendly/hostile GPU feedback differs")
	hud._hit_time=0
	hud.show_alert("Cannot place a block there.","warning",true)
	var warning: Image=await capture("source_warning")
	check(hud._alert_icon.visible and icon_colored_pixels(warning,true)>10,"source warning original icon renders yellow pixels")
	hud.show_alert("Insufficient blocks.","error",true)
	var error: Image=await capture("source_error")
	check(icon_colored_pixels(error,false)>10,"source error original icon renders red pixels")
	hud._process(3.5)
	await capture("source_error_half_fade")
	check(is_equal_approx(hud._alert_panel.modulate.a,.5),"source alert final GPU fade state")
	hud._process(.5)
	session.select_team(2)
	var target: Dictionary=session.targets[0]
	session.set_target_state(int(target.id),"standing",0,2)
	player.follow_target(int(target.id))
	player.follow_first_person=true
	player._sync_camera_mode()
	player._update_camera_transform()
	target.aiming=true
	player._spectator_view.show_target(int(target.id),true)
	player._spectator_view.update_view(.125)
	hud._update_reticle(.125)
	await capture("observed_rifle_ads")
	check(not hud._cross.visible and player.get_camera_aim_down_state()>.6,"observed weapon actual ADS hides source sight")
	target.aiming=false
	target.tool=3
	player._spectator_view._skin.initialize_selection(3,0)
	player._spectator_view.update_view(0)
	hud._update_reticle(0)
	await capture("observed_grenade_sight")
	check(hud._cross.visible,"observed grenade retains original source sight")
	hud.set_menu_visible(true)
	var tabs:=find_tabs(hud._menu)
	tabs.current_tab=1
	var scroll: ScrollContainer=tabs.get_tab_control(1).get_child(0)
	await process_frame
	scroll.scroll_vertical=int(scroll.get_v_scroll_bar().max_value)
	await capture("target_animation_controls_en")
	check(hud._target_preview_controls.shot.is_visible_in_tree() and hud._target_preview_controls.reload_progress.is_visible_in_tree(),"real target animation controls appear in actual Soldiers tab")
	hud.show_alert("Loading OpenSpades map...","warning",true)
	var menu_warning: Image=await capture("menu_warning")
	check(hud._alert_panel.is_visible_in_tree() and icon_colored_pixels(menu_warning,true)>10,"menu-open source warning icon renders above actual menu")
	hud._process(4.0)
	app.set_locale("ru")
	await capture("target_animation_controls_ru")
	check(hud._target_preview_controls.action.get_item_text(1)=="Удар","Russian preview option labels remain readable")
	hud.set_menu_visible(false)
	hud.open_chat(true)
	hud._chat.set_input_text("/cg_h")
	hud._chat._complete_command()
	await capture("console_completion")
	check(hud._chat._completion_hint.visible and hud._chat.team_channel,"real console suggestions render without switching team channel")
	hud._chat.cancel_input()
	await finish()

func capture(name: String) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	check(image.save_png(output.path_join(name+".png"))==OK,"save real GPU capture: "+name)
	return image

func center_difference(first: Image,second: Image) -> int:
	var count:=0
	var origin:=Vector2i(first.get_size()/2)-Vector2i(32,32)
	for y in range(origin.y,origin.y+64):
		for x in range(origin.x,origin.x+64):
			var a:=first.get_pixel(x,y)
			var b:=second.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>.08:count+=1
	return count

func center_colored_pixels(image: Image,green: bool) -> int:
	var origin:=Vector2i(image.get_size()/2)-Vector2i(32,32)
	var count:=0
	for y in range(origin.y,origin.y+64):
		for x in range(origin.x,origin.x+64):
			var color:=image.get_pixel(x,y)
			if green:
				if color.g>.8 and color.r<.15 and color.b<.15:count+=1
			elif color.r>.8 and color.g<.15 and color.b<.15:count+=1
	return count

func icon_colored_pixels(image: Image,yellow: bool) -> int:
	var point:=Vector2i(hud._alert_panel.position+hud._alert_icon.position)
	return colored_pixels(image,Rect2i(point,Vector2i(16,16)),false,yellow)

func colored_pixels(image: Image,region: Rect2i,green: bool,yellow: bool) -> int:
	var count:=0
	for y in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			var color:=image.get_pixel(x,y)
			if yellow:
				if color.r>.5 and color.g>.5 and color.b<.25:count+=1
			elif green:
				if color.g>color.r+.2 and color.g>color.b+.2:count+=1
			elif color.r>color.g+.2 and color.r>color.b+.2:count+=1
	return count

func find_tabs(node: Node) -> TabContainer:
	if node is TabContainer:return node
	for child in node.get_children():
		var value:=find_tabs(child)
		if value!=null:return value
	return null

func restore_settings() -> void:
	if _settings_existed:
		var file:=FileAccess.open("user://settings.cfg",FileAccess.WRITE)
		file.store_buffer(_settings_before)
		file.close()
	else:DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://native-ui-settings-before.bin"))

func finish() -> void:
	if is_instance_valid(app):
		if app.has_method("stop_audio"):app.stop_audio()
		await process_frame
		await process_frame
		app.queue_free()
		for index in 5:await process_frame
	restore_settings()
	print("NATIVE_UI_GPU: %d assertions, %d failures; captures %s"%[assertions,failures,output])
	quit(0 if failures==0 else 1)
