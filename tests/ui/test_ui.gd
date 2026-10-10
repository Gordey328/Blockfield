extends SceneTree
## Actual lab scene and input routing; preserves user's settings byte-for-byte.
const MAIN_SCENE=preload("res://scenes/main.tscn")
var assertions:=0
var failures:=0
var app: Node3D
var session: LocalSession
var player: BlockfieldPlayer
var hud: LabHUD
var world: VoxelWorld
var _settings_existed:=false
var _settings_before:=PackedByteArray()

func _initialize() -> void:call_deferred("_run")
func check(condition: bool,message: String) -> void:
	assertions+=1
	if not condition:failures+=1;push_error("UI: "+message)
func frames(count: int) -> void:
	for index in count:await process_frame

func key(code: Key,pressed: bool=true) -> void:
	var event:=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _run() -> void:
	_settings_existed=FileAccess.file_exists("user://settings.cfg")
	if _settings_existed:_settings_before=FileAccess.get_file_as_bytes("user://settings.cfg")
	ConfigFile.new().save("user://settings.cfg")
	app=MAIN_SCENE.instantiate()
	root.add_child(app)
	app.set_locale("ru")
	session=app.get_node("LocalSession")
	player=app.get_node("Player")
	hud=app.get_node("HUD")
	world=app.get_node("VoxelWorld")
	await frames(4)
	check(hud.is_menu_open() and not player.controls_enabled,"startup menu owns input")
	for scenario in ["test_bindings","test_input_chat","test_resources_and_events","test_map_objectives","test_settings"]:
		var completed: Variant=await call(scenario)
		check(completed==true,"scenario reaches completion: "+scenario)
	LabInputBindings.release_actions()
	LabInputBindings.reset_defaults()
	app.stop_audio()
	await frames(3)
	var reference: WeakRef=weakref(app)
	app.queue_free()
	for index in 12:
		await frames(1)
		if index>=2 and reference.get_ref()==null:break
	check(reference.get_ref()==null,"scene freed before exit")
	if _settings_existed:
		var file:=FileAccess.open("user://settings.cfg",FileAccess.WRITE)
		file.store_buffer(_settings_before)
		file.close()
	else:DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ui-bindings-test.cfg"))
	print("UI: %d assertions, %d failures"%[assertions,failures])
	quit(0 if failures==0 else 1)

func test_bindings() -> bool:
	var config:=ConfigFile.new()
	config.set_value("profile","name","kept")
	config.set_value("ui","minimap_size",144)
	config.save("user://ui-bindings-test.cfg")
	var arrow:=InputEventKey.new()
	arrow.physical_keycode=KEY_UP
	LabInputBindings.bind_action("forward",arrow)
	check(InputMap.action_has_event("forward",arrow),"remap changes the real InputMap")
	LabInputBindings.bind_action("reload",arrow)
	check(InputMap.action_get_events("forward").is_empty(),"duplicate binding clears prior action")
	check(InputMap.action_has_event("reload",arrow),"duplicate reassigned to requested action")
	LabInputBindings.bind_action("reload",null)
	check(InputMap.action_get_events("reload").is_empty(),"unbind clears action")
	var mouse:=InputEventMouseButton.new()
	mouse.button_index=MOUSE_BUTTON_MIDDLE
	LabInputBindings.bind_action("primary",mouse)
	check(LabInputBindings.save_bindings("user://ui-bindings-test.cfg")==OK,"key and mouse bindings save")
	LabInputBindings.reset_defaults()
	LabInputBindings.load_bindings("user://ui-bindings-test.cfg")
	check(InputMap.action_get_events("reload").is_empty(),"saved unbound action remains unbound")
	check(InputMap.action_has_event("primary",mouse),"mouse binding round-trips")
	config.load("user://ui-bindings-test.cfg")
	check(config.get_value("profile","name")=="kept" and config.get_value("ui","minimap_size")==144,"binding save preserves other settings")
	LabInputBindings.reset_defaults()
	hud._binding_action="forward"
	key(KEY_UP)
	key(KEY_UP,false)
	check(InputMap.action_has_event("forward",arrow),"UI captures physical key")
	hud._binding_action="forward"
	key(KEY_BACKSPACE)
	key(KEY_BACKSPACE,false)
	check(InputMap.action_get_events("forward").is_empty(),"UI Backspace unbinds")
	hud._binding_action="reload"
	key(KEY_ESCAPE)
	key(KEY_ESCAPE,false)
	check(InputMap.action_get_events("reload").size()==1,"UI Escape cancels capture without changing binding")
	LabInputBindings.reset_defaults()
	LabInputBindings.save_bindings()
	hud.set_menu_visible(false)
	player.respawn_at(Vector3(48.5,4.01,70.5))
	await frames(4)
	LabInputBindings.bind_action("forward",arrow)
	var initial:=player.global_position
	key(KEY_UP)
	await frames(12)
	key(KEY_UP,false)
	check(player.global_position.distance_to(initial)>.1,"remapped key moves the real player")
	LabInputBindings.reset_defaults()
	return true

func test_input_chat() -> bool:
	hud.set_menu_visible(false)
	player.respawn_at(Vector3(48.5,4.01,70.5))
	await frames(3)
	key(KEY_TAB)
	check(hud._scoreboard.visible,"scoreboard displays while key held")
	key(KEY_TAB,false)
	check(not hud._scoreboard.visible,"scoreboard closes on release")
	key(KEY_T)
	key(KEY_T,false)
	check(hud.is_chat_open() and not player.controls_enabled,"global chat captures gameplay input")
	var initial:=player.global_position
	key(KEY_W)
	await frames(4)
	check(Vector2(player.global_position.x,player.global_position.z).distance_to(Vector2(initial.x,initial.z))<.01,"typing movement key does not move player")
	hud._chat.set_input_text("[color=red]literal[/color]")
	key(KEY_ENTER)
	key(KEY_ENTER,false)
	check(not hud.is_chat_open() and player.controls_enabled,"send restores gameplay input")
	check(not Input.is_action_pressed("forward"),"chat release prevents stale held gameplay action")
	check(hud._chat.messages.back().text=="[color=red]literal[/color]" and not hud._chat.messages.back().team_channel,"global text retained literally")
	check(hud._chat.get_log_text().contains("[color=red]literal[/color]"),"chat cannot inject rich-text formatting")
	key(KEY_Y)
	key(KEY_Y,false)
	hud._chat.set_input_text("team message")
	key(KEY_ENTER)
	key(KEY_ENTER,false)
	check(bool(hud._chat.messages.back().team_channel),"team channel saved with message")
	hud.open_chat()
	hud._chat.set_input_text("unfinished draft")
	key(KEY_UP)
	key(KEY_UP,false)
	check(hud._chat.get_input_text()=="team message","Up recalls shared global/team history")
	key(KEY_DOWN)
	key(KEY_DOWN,false)
	check(hud._chat.get_input_text()=="unfinished draft","Down restores draft")
	key(KEY_ESCAPE)
	key(KEY_ESCAPE,false)
	hud.open_chat()
	check(hud._chat.get_input_text()=="unfinished draft","Cancel preserves draft across openings")
	hud._chat.cancel_input()
	hud._chat._process(16)
	check(hud._chat.get_log_text().is_empty(),"compact chat expires after 15 seconds")
	hud._chat.set_expanded(true)
	check(hud._chat.get_log_text().contains("team message") and hud._chat._log.scroll_active,"expanded history restores expired messages with scrolling")
	hud._chat.set_expanded(false)
	hud.open_chat()
	hud._chat.set_input_text("/mode tc")
	key(KEY_ENTER)
	key(KEY_ENTER,false)
	check(session.mode=="tc","offline chat command changes actual match mode")
	return true

func test_resources_and_events() -> bool:
	session.set_mode("sandbox")
	session.select_team(0)
	session.select_tool(1)
	session.blocks=17
	hud._process(0)
	check(hud._ammo.text.ends_with("17") and not hud._ammo.text.contains(" / "),"block HUD displays block stock")
	session.select_tool(3)
	session.grenades=2
	hud._process(0)
	check(hud._ammo.text.ends_with("2"),"grenade HUD displays grenade stock")
	session.begin_grenade_cook()
	hud._process(0)
	check(hud._weapon_status.text.contains("Фитиль"),"grenade cook indicator visible")
	session.release_grenade()
	session.select_tool(2)
	session.magazine=3
	session.reload_weapon()
	hud._process(0)
	check(not hud._weapon_status.text.is_empty() and hud._weapon_status.text.contains("%"),"reload progress is visible")
	session.end_reload()
	app.set_locale("en")
	hud.show_hit("head",100)
	check(hud._notice.text.contains("damage") and not hud._notice.text.contains("урона"),"dynamic hit notification follows locale")
	app.set_locale("ru")
	session.invulnerable=false
	session.health=100
	session.damage_player(25,player.global_position+Vector3.RIGHT*5,"weapon")
	check(hud._status_effects.hurt_items.size()==1,"real damage creates directional hurt ring")
	check(hud._status_effects.hurt_sprites.size()==12,"original sprite count depends on remaining health")
	for sprite in hud._status_effects.hurt_sprites:
		check(float(sprite.scale)>=.2 and float(sprite.scale)<=.9 and float(sprite.strength)>=.225 and float(sprite.strength)<=.75,"hurt sprite samples obey original ranges")
	hud._status_effects._process(3.1)
	check(hud._status_effects.hurt_items.is_empty(),"hurt ring expires after three seconds")
	session.damage_player(1,Vector3.INF,"fall")
	check(hud._status_effects.hurt_items.is_empty() and not hud._status_effects.hurt_sprites.is_empty(),"fall damage creates sprites without a fabricated direction")
	var target_id:=int(session.targets[0].id)
	session.apply_target_damage(target_id,100,"head")
	check(hud._feed.get_parsed_text().contains(str(session.get_target(target_id).name)),"kill event reaches visible feed")
	var rows:=hud._scoreboard.get_rows()
	check(rows[0].local and int(rows[0].score)>0,"scoreboard sorts actual local score first")
	session.damage_player(1000)
	check(not bool(hud._scoreboard.get_rows()[0].alive),"scoreboard represents local death")
	session.respawn()
	var target: Dictionary=session.targets.back()
	session.set_target_state(int(target.id),"standing",0,2)
	player.respawn_at(target.position+Vector3(0,0,5))
	player.look_at(Vector3(target.position.x,player.global_position.y,target.position.z),Vector3.UP)
	player.head.rotation.x=atan2(target.position.y+2.35-player.get_aim_origin().y,5)
	await frames(3)
	hud._update_hottracked_name()
	check(hud._name_under_crosshair.text==str(target.name),"actual target ray produces hottracked player name")
	session.set_mode("ctf")
	session.update_player_position(session.ctf_bases[1])
	session._update_ctf()
	hud._process(0)
	check(hud._intel_icon.visible,"carried intel displays source icon")
	session.set_mode("sandbox")
	return true

func test_map_objectives() -> bool:
	session.select_team(0)
	var ids:=hud._map.get_visible_target_ids()
	for id in ids:check(int(session.get_target(id).team)==0 and bool(session.get_target(id).alive),"active map only shows living allies")
	session.select_team(2)
	var both:=hud._map.get_visible_target_ids()
	check(both.size()>ids.size(),"spectator map shows both teams")
	for id in both:check(bool(session.get_target(id).alive),"spectator map excludes dead players")
	session.select_team(0)
	hud._map.scale_mode=0
	hud._map._process(1)
	player.global_position=Vector3(.5,4.01,.5)
	var view:=hud._map.get_view_rect()
	check(view.position==Vector2.ZERO and view.size.x<world.dimensions.x,"zoomed minimap clamps at map boundary")
	var mode:=hud._map.scale_mode
	for index in 4:hud._map.switch_scale()
	check(hud._map.scale_mode==mode,"four source zoom levels cycle")
	check(hud._large_map.get_view_rect().size==Vector2(world.dimensions.x,world.dimensions.z),"large map covers entire world")
	var count:=hud._map._tracers.size()
	hud.add_map_tracer(Vector3(10,4,10),Vector3(80,4,80),0,true)
	check(hud._map._tracers.size()==count,"local first-person map tracers suppressed as source")
	hud.add_map_tracer(Vector3(10,4,10),Vector3(80,4,80),1,false)
	hud._map._process(.01)
	hud._map._process(.05)
	var segment:=hud._map.get_tracer_segment(hud._map._tracers.back())
	check(segment.size()==2 and segment[0].distance_to(segment[1])>1,"map tracer advances a visible source shutter segment")
	hud._map._process(1)
	check(hud._map._tracers.size()==count,"map tracer disappears beyond hit endpoint")
	check(root.get_visible_rect().encloses(hud._map.get_global_rect()),"minimap is inside viewport after applying settings")
	hud.toggle_map()
	hud._process(0)
	check(root.get_visible_rect().encloses(hud._large_map.get_global_rect()),"large map is centered inside viewport")
	hud.toggle_map()
	world.set_block(Vector3i(1,8,1),VoxelWorld.pack_color(Color("c1283a")))
	hud._map._process(.3)
	check(world.get_topdown_image().get_pixel(1,1).is_equal_approx(Color("c1283a")) and not hud._map._dirty,"terrain edit updates shared full-resolution map texture")
	player.respawn_at(Vector3(48.5,4.01,70.5))
	session.configure_tc([player.global_position+Vector3(5,0,0)])
	session.set_mode("tc")
	session.territories[0].capturing_team=0
	session.territories[0].progress=.25
	var tc:=hud._status_effects.get_tc_state()
	check(not tc.is_empty() and int(tc.left_team)==0 and float(tc.display_progress)>.5,"TC bar orients capturing local team on left")
	player.global_position=Vector3(90,20,90)
	session.session_time+=1
	tc=hud._status_effects.get_tc_state()
	check(not tc.is_empty() and float(tc.fade)>.4 and float(tc.fade)<.6,"TC bar retains last territory with two-second fade")
	session.session_time+=1.1
	check(hud._status_effects.get_tc_state().is_empty(),"TC bar expires when player leaves territory")
	session.winning_team=0
	hud._process(0)
	check(hud._results.text.contains("Победа"),"round result displays actual winning team")
	session.set_mode("sandbox")
	player.respawn_at(Vector3(48.5,4.01,70.5))
	player.head.rotation.x=-PI/4
	session.select_tool(1)
	await frames(3)
	hud._build_cursor._process(0)
	check(not hud._build_cursor.preview.get("cells",[]).is_empty(),"building cursor derives selected cells from real ray")
	check(hud._build_cursor._cells.size()>0,"real selected cell produces 3D outline")
	hud.set_capture_visible(false)
	check(not hud.visible and not hud._build_cursor.visible,"scene screenshot hides HUD and 3D cursor")
	hud.set_capture_visible(true)
	return true

func test_settings() -> bool:
	hud.set_hud_hidden(true)
	check(not hud._hud.visible and not hud._build_cursor.enabled,"hide HUD also hides build feedback")
	app.save_settings()
	var config:=ConfigFile.new()
	config.load("user://settings.cfg")
	check(bool(config.get_value("ui","hidden",false)) and config.has_section("controls"),"main settings save preserves UI and control sections")
	hud.set_hud_hidden(false)
	hud._minimap_size=144
	hud._save_ui_settings()
	hud._minimap_size=256
	hud._load_ui_settings()
	check(hud._minimap_size==144 and hud._map.size==Vector2(144,144),"minimap preference loads and affects layout")
	var graphics: Dictionary=app.get_graphics_options()
	check(hud._graphics_controls.has("draw_distance") and hud._graphics_controls.has("dof"),"graphics settings expose underlying implemented options")
	var draw_distance:=float(graphics.draw_distance)
	hud._graphics_controls.draw_distance.value=32
	check(is_equal_approx(float(app.get_graphics_options().draw_distance),32),"graphics slider changes actual render option")
	app.set_graphics_option("draw_distance",draw_distance)
	hud._refresh_graphics_controls()
	check(is_equal_approx(float(hud._graphics_controls.draw_distance.value),draw_distance),"graphics settings refresh after external preset")
	return true
