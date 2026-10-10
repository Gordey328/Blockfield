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
	for scenario in ["test_bindings","test_input_chat","test_resources_and_events","test_hottracked_follow","test_map_objectives","test_team_metadata_and_target_spawn","test_native_palette","test_native_reticle_alerts","test_target_animation_controls","test_console_chat","test_settings","test_mobile_bridge"]:
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
	var audio_deadline:=Time.get_ticks_msec()+200
	while Time.get_ticks_msec()<audio_deadline:
		OS.delay_msec(1)
		await process_frame
	if _settings_existed:
		var file:=FileAccess.open("user://settings.cfg",FileAccess.WRITE)
		file.store_buffer(_settings_before)
		file.close()
	else:DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ui-bindings-test.cfg"))
	print("UI: %d assertions, %d failures"%[assertions,failures])
	quit(0 if failures==0 else 1)

func test_mobile_bridge() -> bool:
	var desktop_scale:=root.content_scale_size
	var emulation:=Input.emulate_mouse_from_touch
	var mouse:=InputEventMouseButton.new()
	mouse.button_index=MOUSE_BUTTON_LEFT
	LabInputBindings.reset_defaults()
	hud.set_menu_visible(true)
	hud.set_mobile_controls_mode(1)
	check(hud.uses_mobile_controls() and not hud.mobile_controls.visible,"forced mobile mode keeps overlay out of menu")
	check(InputMap.action_has_event("primary",mouse),"menu retains mouse bindings for GUI")
	var config:=ConfigFile.new();config.load("user://settings.cfg")
	check(int(config.get_value("ui","touch_controls",-1))==1,"touch mode is persisted with other preferences")
	hud.set_menu_visible(false)
	await frames(3)
	check(hud.mobile_controls.visible and player.controls_enabled,"playing enables overlay and real controller")
	check(not hud._ammo.text.contains("\n"),"mobile inventory uses one footer row, leaving reload status readable")
	check(not Input.emulate_mouse_from_touch and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"touch gameplay needs no mouse capture/emulation")
	check(not InputMap.action_has_event("primary",mouse),"physical mouse primary filtered while overlay active")
	var regions: Dictionary=hud.mobile_controls.get_hit_regions()
	check(hud._native_palette.get_global_rect().end.y+8<=regions.reload.position.y,"mobile block palette stays above the action buttons")
	check(not hud._native_palette.get_global_rect().intersects(hud._map.get_global_rect()),"mobile block palette stays clear of the minimap")
	check(hud._build_status.get_global_rect().end.y+8<=regions.primary.position.y,"mobile building feedback stays above action buttons")
	var jump: Rect2=regions.jump
	mouse.position=hud.mobile_controls.get_global_transform_with_canvas()*jump.get_center()
	mouse.window_id=root.get_window_id()
	mouse.pressed=true
	mouse.button_mask=MOUSE_BUTTON_MASK_LEFT
	# Dummy has a 64px physical window; these positions are already logical.
	root.push_input(mouse,true);Input.flush_buffered_events()
	await frames(1)
	check(Input.is_action_pressed("jump") and not Input.is_action_pressed("primary"),"real mouse click on Jump cannot fire underneath touch overlay")
	mouse=mouse.duplicate();mouse.pressed=false;mouse.button_mask=0
	root.push_input(mouse,true);Input.flush_buffered_events()
	await frames(1)
	check(not Input.is_action_pressed("jump"),"mouse button release clears touch Jump bridge")
	var move: Rect2=regions.move
	hud.mobile_controls.handle_touch(0,move.get_center(),true)
	check(player.touch_movement==Vector2.ZERO,"floating stick starts neutral under the thumb")
	hud.mobile_controls.handle_drag(0,move.get_center()+Vector2(0,-200),Vector2(0,-200))
	check(player.touch_movement.is_equal_approx(Vector2.UP),"real HUD signal updates source analog movement")
	var look: Rect2=regions.look
	var yaw:=player.rotation.y
	hud.mobile_controls.handle_touch(1,look.get_center(),true)
	hud.mobile_controls.handle_drag(1,look.get_center()+Vector2(25,0),Vector2(25,0))
	check(not is_equal_approx(yaw,player.rotation.y),"real HUD look signal reaches player camera")
	hud.mobile_controls.handle_touch(2,regions.primary.get_center(),true)
	Input.flush_buffered_events();await frames(1)
	check(Input.is_action_pressed("primary"),"real HUD action bridge holds primary")
	hud.set_menu_visible(true)
	Input.flush_buffered_events();await frames(1)
	check(player.touch_movement==Vector2.ZERO and not Input.is_action_pressed("primary"),"opening menu clears touch motion and action ownership")
	check(InputMap.action_has_event("primary",mouse) and Input.emulate_mouse_from_touch==emulation,"menu restores physical mouse mappings and GUI emulation")
	hud.set_menu_visible(false)
	await frames(1)
	check(not Input.is_action_pressed("primary") and player.touch_movement==Vector2.ZERO,"return from menu does not revive held touch input")
	hud.mobile_controls.handle_touch(0,move.get_center(),true)
	hud.mobile_controls.handle_drag(0,move.get_center()+Vector2(0,-200),Vector2(0,-200))
	hud.open_chat()
	await frames(1)
	check(not hud.mobile_controls.visible and player.touch_movement==Vector2.ZERO,"chat owns input and clears touch movement")
	hud._chat.cancel_input();hud._sync_controls()
	hud.mobile_controls.handle_touch(0,move.get_center(),true)
	hud.mobile_controls.handle_drag(0,move.get_center()+Vector2(0,-200),Vector2(0,-200))
	hud._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not player.controls_enabled and player.touch_movement==Vector2.ZERO,"focus loss clears real player touch input")
	hud._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await frames(1)
	check(player.controls_enabled and player.touch_movement==Vector2.ZERO,"focus return starts with neutral touch movement")
	hud.mobile_controls.handle_touch(0,move.get_center(),true)
	hud.mobile_controls.handle_drag(0,move.get_center()+Vector2(0,-200),Vector2(0,-200))
	hud.set_mobile_controls_mode(2)
	await frames(2)
	check(not hud.mobile_controls.visible and player.touch_movement==Vector2.ZERO,"switching mode off clears ownership")
	check(root.content_scale_size==desktop_scale and InputMap.action_has_event("primary",mouse),"desktop scale and mouse binding restored")
	hud.set_menu_visible(true)
	hud.set_mobile_controls_mode(0)
	return true

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
	var viewed_team: int=session.team
	session.team=int(target.team)
	session.set_target_state(int(target.id),"standing",0,2)
	player.respawn_at(target.position+Vector3(0,0,5))
	player.look_at(Vector3(target.position.x,player.global_position.y,target.position.z),Vector3.UP)
	player.head.rotation.x=atan2(target.position.y+2.35-player.get_aim_origin().y,5)
	await frames(3)
	hud._update_hottracked_name()
	check(hud._name_under_crosshair.text==str(target.name),"actual target ray produces hottracked player name")
	session.team=1-int(target.team)
	hud._update_hottracked_name()
	check(hud._name_under_crosshair.text.is_empty(),"source hottracking does not reveal enemy names to an active team")
	session.team=viewed_team
	session.set_mode("ctf")
	session.update_player_position(session.ctf_bases[1])
	session._update_ctf()
	hud._process(0)
	check(hud._intel_icon.visible,"carried intel displays source icon")
	session.set_mode("sandbox")
	return true

func test_hottracked_follow() -> bool:
	app.reset_lab()
	var names: int=hud._show_names
	hud._show_names=2
	for target: Dictionary in session.targets:target.alive=false
	var observed: Dictionary=session.targets[0]
	var ally: Dictionary=session.targets[1]
	observed.merge({"alive":true,"team":0,"position":Vector3(32,8,32),"yaw":0.0,"pitch":0.0,"state":"standing"},true)
	ally.merge({"alive":true,"team":0,"position":Vector3(32,8,24),"yaw":0.0,"pitch":0.0,"state":"standing"},true)
	player.respawn_at(Vector3(60,8,60))
	player.rotation.y=PI*.5
	player.head.rotation.x=0
	session.select_team(2)
	player.follow_first_person=true
	check(player.follow_target(int(observed.id)),"follow-name fixture selects the actual observed soldier")
	player._sync_camera_mode()
	player._update_camera_transform()
	hud._update_hottracked_name()
	check(hud._name_under_crosshair.text==str(ally.name),"follow name uses observed eye/front and excludes its own body despite unrelated local aim")
	check(hud._hottracked_player.visible and hud._hottracked_player.get_line_vertices().size()==120,"actual followed ally owns the five source OBB wireframes")
	hud._show_names=0
	hud._update_hottracked_name()
	check(hud._name_under_crosshair.text.is_empty() and hud._hottracked_player.visible,"source outline remains visible independently of the disabled name setting")
	hud._show_names=2
	ally.team=1
	hud._update_hottracked_name()
	check(hud._name_under_crosshair.text.is_empty(),"spectator follow inherits the observed team enemy-name gate")
	check(not hud._hottracked_player.visible,"enemy gate also hides the source wireframes")
	ally.team=0
	world.set_block(Vector3i(32,10,28),VoxelWorld.pack_color(Color.WHITE))
	hud._update_hottracked_name()
	check(hud._name_under_crosshair.text.is_empty(),"source terrain occludes the followed camera's ally OBB")
	check(not hud._hottracked_player.visible,"source terrain target rejection clears the previous outline")
	world.set_block(Vector3i(32,10,28),0)
	observed.state="crouching"
	observed.crouching=true
	observed.pitch=atan2(.9,8.0)
	hud._show_names=1
	hud._update_hottracked_name()
	var distance:=roundi(player.get_aim_origin().distance_to(Vector3(ally.position)+Vector3.UP*2.25))
	check(hud._name_under_crosshair.text==str(ally.name)+" [%dblocks]"%distance,"crouched follow uses its actual eye while displayed distance remains local-eye to target-eye")
	player.camera_mode=BlockfieldPlayer.CameraMode.FOLLOW_THIRD_PERSON
	hud._update_hottracked_name()
	check(hud._name_under_crosshair.text.is_empty(),"follow third-person cannot display a first-person hottracked name")
	check(not hud._hottracked_player.visible,"third-person camera hides the previous outline")
	hud._show_names=names
	player.followed_target_id=-1
	session.select_team(0)
	app.reset_lab()
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
	var surface: Vector2i=world.data.column_top(1+world.dimensions.x,world.dimensions.y-1)
	world.set_block(Vector3i(1,surface.y,1),VoxelWorld.pack_color(Color("c1283a")))
	hud._map._process(.3)
	for poll in 120:
		if not world.is_topdown_pending(): break
		await frames(1)
	hud._map._process(.3)
	# Dummy rendering cannot read back ImageTexture pixels. Verify the exact
	# progressively prepared source and the actual HUD's final upload state;
	# exported browser acceptance checks the rendered minimap separately.
	check(world.get_topdown_image_progressive().get_pixel(1,1).is_equal_approx(Color("c1283a")) and not hud._map._dirty,"terrain edit finishes shared map preparation and the HUD's final upload")
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
	for option in ["gi","water_waves","water_refraction","ragdolls"]:
		check(graphics.has(option) and hud._graphics_controls.has(option),"graphics backend and UI share option: " + option)
		if not graphics.has(option):continue
		var value:=not bool(graphics[option])
		hud._graphics_controls[option].toggled.emit(value)
		check(bool(app.get_graphics_options()[option])==value,"graphics checkbox updates backend option: " + option)
		app.set_graphics_option(option,graphics[option])
	var environmental:=controls_with_metadata(hud,"lab_audio_key","environmental_audio")
	check(environmental.size()==1,"audio settings expose environmental switch")
	if not environmental.is_empty():
		var original:=bool(app.environmental_audio)
		environmental[0].toggled.emit(not original)
		check(bool(app.environmental_audio)!=original,"environmental checkbox updates actual mixer property")
		environmental[0].toggled.emit(original)
	var efx:=controls_with_metadata(hud,"lab_audio_key","source_audio_efx")
	var source_gain_control:=find_control_metadata(hud,"lab_audio_key","source_audio_gain") as HSlider
	check(efx.size()==1 and source_gain_control!=null,"audio settings expose separate source gain and EAX environment controls")
	if not efx.is_empty() and source_gain_control!=null:
		var old_efx: bool=app.source_audio_efx
		var old_gain: float=app.source_audio_gain
		efx[0].toggled.emit(not old_efx)
		source_gain_control.value_changed.emit(.65)
		check(app.audio.efx_enabled!=old_efx and is_equal_approx(app.audio.source_gain,.65),"actual settings update the full audio service, separately from Master volume")
		var audio_config:=ConfigFile.new()
		audio_config.load("user://settings.cfg")
		check(audio_config.get_value("audio","efx")== (not old_efx) and is_equal_approx(float(audio_config.get_value("audio","source_gain")),.65),"source audio controls persist distinct native parameters")
		efx[0].toggled.emit(old_efx)
		source_gain_control.value_changed.emit(old_gain)
	hud._refresh_graphics_controls()
	check(controls_with_metadata(hud,"lab_export","event_log").size()==1,"Settings exposes session log download through main hook")
	check(controls_with_metadata(hud,"lab_window","fullscreen").size()==2 and app.has_method("toggle_fullscreen"),"Settings and main-menu buttons expose the actual web/desktop fullscreen owner")
	check(hud.get_console_setting("unknown")==null and not hud.set_console_setting("unknown",true),"typed HUD console rejects unknown key")
	check(not hud.set_console_setting("minimap_size",192.0) and not hud.set_console_setting("minimap_size",127) and not hud.set_console_setting("player_names",3),"typed HUD console rejects incompatible type or range")
	var saved_map:=hud._minimap_size
	check(hud.set_console_setting("minimap_size",192) and hud._map.size==Vector2(192,192) and is_equal_approx(hud._ui_settings_controls.minimap_size.value,192),"console setting changes actual map and refreshes matching UI widget")
	hud.set_console_setting("minimap_size",saved_map)
	var saved_hit:=hud._show_hit_feedback
	check(hud.set_console_setting("hit_indicator",not saved_hit) and hud._ui_settings_controls.hit_indicator.button_pressed==not saved_hit,"console boolean updates actual HUD state and checkbox")
	hud.set_console_setting("hit_indicator",saved_hit)
	for item in [["eject_brass",player],["animations_enabled",player],["chat_beep",app]]:
		var controls:=controls_with_metadata(hud,"native_preference",item[0])
		check(controls.size()==1,"Settings exposes source preference: "+item[0])
		if controls.is_empty():continue
		var previous: bool=item[1].get(item[0])
		controls[0].button_pressed=not previous
		check(bool(item[1].get(item[0]))==not previous,"actual preference checkbox updates backend: "+item[0])
		controls[0].button_pressed=previous
	var offsets_before:=player.view_weapon_offset
	for axis in 3:
		var control:=find_control_metadata(hud,"native_preference","weapon_offset_"+str(axis)) as HSlider
		check(control!=null,"Settings exposes source weapon offset axis: "+str(axis))
		if control==null:continue
		control.value=.125+axis*.05
		check(is_equal_approx(player.view_weapon_offset[axis],.125+axis*.05),"weapon offset slider changes only requested native axis: "+str(axis))
		control.value=offsets_before[axis]
	var gain:=find_control_metadata(hud,"native_preference","hit_feedback_gain") as HSlider
	check(gain!=null,"Settings exposes original headshot feedback gain")
	if gain!=null:
		var previous:=float(app.hit_feedback_gain)
		gain.value=.37
		check(is_equal_approx(float(app.hit_feedback_gain),.37),"gain slider changes actual headshot audio setting")
		var saved:=ConfigFile.new()
		saved.load("user://settings.cfg")
		check(is_equal_approx(float(saved.get_value("audio","hit_feedback_gain")),.37),"native audio preference persists in audio section")
		gain.value=previous
	return true

func find_control_metadata(node: Node,key: String,value: String) -> Control:
	if node is Control and str(node.get_meta(key,""))==value:return node
	for child in node.get_children():
		var result:=find_control_metadata(child,key,value)
		if result!=null:return result
	return null

func controls_with_metadata(node: Node,key: String,value: String) -> Array[Button]:
	var result: Array[Button]=[]
	if node is Button and str(node.get_meta(key,""))==value:result.append(node)
	for child in node.get_children():result.append_array(controls_with_metadata(child,key,value))
	return result

func test_team_metadata_and_target_spawn() -> bool:
	app.reset_lab()
	var saved_names: Array[String]=session.team_names.duplicate()
	var saved_colors: Array[Color]=session.team_colors.duplicate()
	var first_color:=Color(.8,.2,.1)
	var second_color:=Color(.1,.7,.9)
	check(session.set_team_info(0,"Alpha [b]",first_color) and session.set_team_info(1,"Bravo",second_color),"authority accepts match team names/colors")
	check(not session.set_team_info(2,"Invalid",Color.WHITE) and not session.set_team_info(0,"",Color.WHITE) and not session.set_team_info(0,"Broken",Color(NAN,0,0)),"authority rejects spectator mutation, empty name and nonfinite team color")
	await frames(2)
	check(hud._team_buttons[0].text=="Alpha [b]" and hud._team_buttons[1].text=="Bravo","live team chooser uses literal match names")
	check(hud._team_buttons[0].get_theme_color("font_color").is_equal_approx(first_color),"team chooser tint follows authority color")
	hud._scoreboard.show()
	hud._scoreboard._process(0)
	check(hud._scoreboard._columns[0].get_parsed_text().contains("Alpha [b]") and hud._scoreboard._columns[1].get_parsed_text().contains("Bravo"),"scoreboard headers preserve custom name without BBCode interpretation")
	hud._scoreboard.hide()
	hud._map.per_player_colors=false
	check(hud._map.player_color(1,0).is_equal_approx(Color(.6666666667,.4266666667,.3866666667)),"map team palette applies native ModifyColor to match-provided RGB")
	hud._map.per_player_colors=true
	session.winning_team=1
	hud._process(0)
	check(hud._results.text.contains("Bravo"),"winner banner names actual winning match team")
	check(hud._event_text({"type":"territory_capture","team":1,"territory":0}).contains("Bravo") and hud._event_text({"type":"team","team":0,"name":"Player"}).contains("Alpha [b]"),"objective/team event messages use supplied team names")
	session.winning_team=-1
	for kind in ["stationary","moving"]:
		var buttons:=controls_with_metadata(hud,"lab_spawn",kind)
		check(buttons.size()==1,"Soldiers tab exposes actual " + kind + " spawn button")
		if buttons.is_empty():continue
		hud._spawn_team.selected=0 if kind=="stationary" else 1
		var count:=session.targets.size()
		buttons[0].pressed.emit()
		await frames(2)
		var target: Dictionary=session.targets.back()
		check(session.targets.size()==count+1 and bool(target.moving)==(kind=="moving") and int(target.team)==hud._spawn_team.selected,"spawn button creates correct authoritative target state/team")
		var actors: Array[LabSoldier]=[]
		for node in app.get_children():
			if node is LabSoldier and node.target_id==int(target.id):actors.append(node)
		check(actors.size()==1 and actors[0].is_visible_in_tree(),"spawned authority has exactly one visible original soldier")
	var moving: Dictionary=session.targets.back()
	var previous: Vector3=moving.position
	session.update(.2)
	check(not Vector3(moving.position).is_equal_approx(previous),"moving spawn advances through local authoritative simulation")
	var reset:=controls_with_metadata(hud,"lab_spawn","reset")
	check(reset.size()==1,"Soldiers tab exposes reset-target button")
	if not reset.is_empty():reset[0].pressed.emit()
	await frames(2)
	var actors:=0
	for node in app.get_children():
		if node is LabSoldier:actors+=1
	check(session.targets.size()==6 and actors==6,"reset-target button removes spawned authorities and visuals together")
	check(session.get_team_info(0).name=="Alpha [b]" and session.get_team_info(1).color.is_equal_approx(second_color),"target reset preserves match team metadata")
	for index in 2:session.set_team_info(index,saved_names[index],saved_colors[index])
	return true

func test_native_palette() -> bool:
	var colors:=LabPalette.palette_colors()
	check(colors.size()==64,"native palette contains eight families with eight shades")
	for item in [[0,Vector3i(15,15,15)],[3,Vector3i(111,111,111)],[7,Vector3i(239,239,239)],[8,Vector3i(31,0,0)],[15,Vector3i(255,223,223)],[16,Vector3i(31,15,0)],[63,Vector3i(255,223,255)]]:
		var color: Color=colors[item[0]]
		check(Vector3i(roundi(color.r*255),roundi(color.g*255),roundi(color.b*255))==item[1],"source integer palette color fixture: " + str(item[0]))
	app.reset_lab()
	hud.set_menu_visible(false)
	session.select_tool(LocalSession.Tool.BLOCK)
	player.block_color=Color("a1b2c3")
	key(KEY_RIGHT)
	key(KEY_RIGHT,false)
	check(hud._native_palette.get_selected_index()==4,"nonpalette color starts keyboard selection at native fallback3 before right increment")
	player.block_color=colors[0]
	key(KEY_LEFT)
	key(KEY_LEFT,false)
	check(hud._native_palette.get_selected_index()==63,"palette left wraps first color to last")
	key(KEY_DOWN)
	key(KEY_DOWN,false)
	check(hud._native_palette.get_selected_index()==7,"palette down wraps row while preserving column")
	key(KEY_UP)
	key(KEY_UP,false)
	check(hud._native_palette.get_selected_index()==63,"palette up wraps row while preserving column")
	session.select_tool(LocalSession.Tool.WEAPON)
	key(KEY_LEFT)
	key(KEY_LEFT,false)
	check(hud._native_palette.get_selected_index()==63,"palette keys do not change held color on other tools")
	session.select_tool(LocalSession.Tool.BLOCK)
	hud.set_menu_visible(true)
	key(KEY_LEFT)
	key(KEY_LEFT,false)
	check(hud._native_palette.get_selected_index()==63,"menu blocks palette shortcuts")
	hud.set_menu_visible(false)
	player.respawn_at(Vector3(48.5,4.01,70.5))
	player.rotation=Vector3.ZERO
	player.head.look_at(Vector3(48.5,5.5,68.5),Vector3.UP)
	world.set_block(Vector3i(48,5,68),VoxelWorld.pack_color(colors[19]))
	await frames(2)
	key(KEY_E)
	key(KEY_E,false)
	check(hud._native_palette.get_selected_index()==19,"actual eyedropper hit selects exact matching native palette color")
	world.set_block(Vector3i(48,5,68),VoxelWorld.pack_color(Color("a1b2c3")))
	key(KEY_E)
	key(KEY_E,false)
	check(hud._native_palette.get_selected_index()==-1,"eyedropped arbitrary RGB remains valid with no false palette highlight")
	hud._process(0)
	check(hud._native_palette.visible and hud._palette.color.is_equal_approx(player.block_color),"in-game palette and custom picker agree with authoritative held RGB")
	world.set_block(Vector3i(48,5,68),0)
	world.set_block(Vector3i(48,5,55),VoxelWorld.pack_color(colors[21]))
	player.head.look_at(Vector3(48.5,5.5,55.5),Vector3.UP)
	key(KEY_E);key(KEY_E,false)
	check(hud._native_palette.get_selected_index()==21,"source256-step eyedropper captures a block beyond the twelve-step build cursor")
	player.head.rotation.x=PI*.5
	key(KEY_E);key(KEY_E,false)
	check(player.block_color.is_equal_approx(app.world_environment.environment.fog_light_color),"source eyedropper uses the actual fog color when its ray misses terrain")
	session.select_tool(LocalSession.Tool.WEAPON)
	hud._process(0)
	check(not hud._native_palette.visible,"source palette appears only for live block tool")
	return true

func test_native_reticle_alerts() -> bool:
	app.reset_lab()
	hud.set_menu_visible(false)
	player.third_person=false
	player._sync_camera_mode()
	session.select_tool(2)
	player._weapon_view.initialize_selection(2,session.current_weapon)
	player._aim_down_state=0.6
	hud._update_reticle(0)
	check(hud._cross.texture==OpenSpadesExtensions.texture("Gfx/Sight.tga") and hud._hit.texture==OpenSpadesExtensions.texture("Gfx/HitFeedback.png"),"native reticle and hit feedback resolve original textures")
	check(hud._cross.size==Vector2(64,64) and hud._cross.offset_left==-32 and hud._cross.get_global_rect().get_center().is_equal_approx(root.get_visible_rect().size*.5),"native sight uses centered original dimensions")
	check(hud._cross.visible,"weapon sight remains at ADS exactly0.6")
	player._aim_down_state=.6001
	hud._update_reticle(0)
	check(not hud._cross.visible,"weapon sight hides only above ADS0.6")
	for tool in [0,1,3]:
		session.select_tool(tool)
		player._weapon_view.initialize_selection(tool,session.current_weapon)
		player._aim_down_state=1.0
		hud._update_reticle(0)
		check(hud._cross.visible,"nonweapon skin retains source sight while secondary is active: "+str(tool))
	session.select_tool(2)
	player._weapon_view.initialize_selection(2,session.current_weapon)
	player.sprinting=true
	player._aim_down_state=0.0
	hud._update_reticle(0)
	check(hud._cross.visible,"source Draw2D retains crosshair while sprinting")
	player.sprinting=false
	hud.show_hit("head",100,false)
	hud._process(.125)
	check(is_equal_approx(hud._hit_time,.5) and hud._hit.modulate.is_equal_approx(Color(1,.02,.04,.5)),"hostile source hit color and4/s half-opacity at125ms")
	hud._process(.125)
	check(not hud._hit.visible and is_zero_approx(hud._hit_time),"hit indicator expires at250ms")
	hud.show_hit("arms",18,true)
	check(hud._hit.modulate.is_equal_approx(Color(.02,1,.02,1)),"friendly source hit color is green")
	player.third_person=true
	player._sync_camera_mode()
	hud._update_reticle(0)
	check(not hud._cross.visible and not hud._hit.visible,"third-person camera excludes first-person skin HUD")
	player.third_person=false
	session.select_team(2)
	var target: Dictionary=session.targets[0]
	session.set_target_state(int(target.id),"standing",0,2)
	check(player.follow_target(int(target.id)),"spectator follows live test soldier")
	player.follow_first_person=true
	player._sync_camera_mode()
	player._spectator_view.show_target(int(target.id),true)
	player._spectator_view.update_view(0)
	player._spectator_view._skin._aim=.6
	hud._update_reticle(0)
	check(hud._cross.visible,"follow first-person uses observed soldier sight, despite spectator local team")
	player._spectator_view._skin._aim=.6001
	hud._update_reticle(0)
	check(not hud._cross.visible,"follow reticle reads actual observed skin ADS threshold")
	target.tool=3
	player._spectator_view._skin.initialize_selection(3,0)
	hud._update_reticle(0)
	check(hud._cross.visible,"follow reticle chooses observed tool instead of local selected weapon")
	target.alive=false
	hud._update_reticle(0)
	check(not hud._cross.visible and not hud._hit.visible,"dead observed target hides skin HUD")
	target.alive=true
	var requested: Array[int]=[]
	var listener:=func():requested.append(1)
	hud.alert_sound_requested.connect(listener)
	hud._show_alerts=false
	hud.show_alert("Cannot place block","error")
	check(requested.size()==1 and not hud._alert_panel.visible,"disabled alerts keep source error sound")
	hud._show_alerts=true
	hud.show_alert("Warning","warning",true)
	check(requested.size()==1 and hud._alert_icon.visible and hud._alert_icon.modulate==Color.YELLOW,"quiet warning preserves yellow icon without sound")
	check(hud._alert_style.border_color.is_equal_approx(Color(1,1,0,.7)),"source warning initial border color")
	hud._process(1.0/3.0)
	check(is_equal_approx(hud._alert_style.border_color.a,.35),"source border fades at1.5/s")
	hud.show_alert("Error","error")
	check(requested.size()==2 and hud._alert_icon.modulate==Color.RED,"error requests audio and red source icon")
	hud.set_menu_visible(true)
	check(hud._alert_panel.is_visible_in_tree() and hud._alert_panel.get_parent()==hud._root and hud._alert_panel.mouse_filter==Control.MOUSE_FILTER_IGNORE,"menu-open loading/upload/error alerts render above menu without blocking input")
	hud.set_menu_visible(false)
	hud.set_hud_hidden(true)
	check(not hud._alert_panel.visible,"native cg_hideHud suppresses independently rooted alert")
	hud.set_hud_hidden(false)
	hud._process(3.5)
	check(hud._alert_panel.visible and is_equal_approx(hud._alert_panel.modulate.a,.5),"error remains half-visible during final one-second fade")
	hud._process(.5)
	check(not hud._alert_panel.visible,"error disappears after3+1seconds")
	hud.show_notice("Notice")
	check(not hud._alert_icon.visible and is_zero_approx(hud._alert_style.border_color.a) and requested.size()==2,"notice has no warning icon, border or sound")
	hud._process(2.5)
	check(hud._alert_panel.visible and is_equal_approx(hud._alert_panel.modulate.a,1),"source notice holds2.5seconds before fading")
	hud._process(.5)
	check(is_equal_approx(hud._alert_panel.modulate.a,.5),"source notice1second fade")
	hud.alert_sound_requested.disconnect(listener)
	hud.reload_resources()
	check(hud._alert_icon.texture==OpenSpadesExtensions.texture("Gfx/AlertIcon.png"),"resource refresh includes original alert texture")
	var sounds: Array[String]=[]
	var ui_listener:=func(kind: String):sounds.append(kind)
	hud.ui_sound_requested.connect(ui_listener)
	hud.set_menu_visible(true)
	var buttons:=controls_with_metadata(hud,"lab_spawn","reset")
	var parent: Node=buttons[0]
	while parent!=null and not parent is TabContainer:parent=parent.get_parent()
	if parent is TabContainer:parent.current_tab=1
	buttons[0].mouse_entered.emit()
	buttons[0].pressed.emit()
	check(sounds==["hover","select"],"real menu buttons request native Hover/Select feedback")
	hud.ui_sound_requested.disconnect(ui_listener)
	app.reset_lab()
	hud.set_menu_visible(false)
	return true

func test_target_animation_controls() -> bool:
	app.reset_lab()
	var magazine:=session.magazine
	var rounds:=session.shots_fired
	var healths: Array=[]
	for target in session.targets:healths.append(target.health)
	var settings_before:=FileAccess.get_file_as_bytes("user://settings.cfg")
	for key in ["aiming","reloading","reload_progress","cook_time","action","action_progress","block_color","shot","reset"]:
		check(hud._target_preview_controls.has(key),"Soldiers tab exposes test animation control: "+key)
	hud._target_preview_controls.aiming.toggled.emit(true)
	hud._target_preview_controls.reloading.toggled.emit(true)
	hud._target_preview_controls.reload_progress.value=.45
	hud._target_preview_controls.cook_time.value=1.7
	hud._target_preview_controls.action.item_selected.emit(1)
	hud._target_preview_controls.action_progress.value=.25
	hud._target_preview_controls.block_color.color_changed.emit(Color(.8,.1,.4))
	var target: Dictionary=session.targets[0]
	check(bool(target.aiming) and bool(target.is_reloading) and is_equal_approx(target.reload_progress,.45) and is_equal_approx(target.grenade_cook_time,1.7),"actual preview controls update observed aiming, reload and grenade snapshot")
	check(target.action_type==1 and is_equal_approx(target.action_progress,.25) and target.block_color.is_equal_approx(Color(.8,.1,.4)),"actual preview controls update native bash phase and held RGB")
	var actor: LabSoldier
	for node in app.get_children():
		if node is LabSoldier and node.target_id==int(target.id):actor=node;break
	check(actor!=null,"preview target has real third-person actor")
	session.set_target_state(int(target.id),"standing",0,0)
	actor._process(0)
	var bash_basis: Basis=actor.character._arms.basis
	check(actor.character._tool_action==1 and is_equal_approx(actor.character._action_progress,.25) and is_equal_approx(actor.character._cook_time,1.7),"LabSoldier forwards native tool/cook state to actual CharacterView")
	hud._target_preview_controls.action.item_selected.emit(0)
	actor._process(0)
	check(not actor.character._arms.basis.is_equal_approx(bash_basis),"bash preview changes original third-person arm pitch")
	session.set_target_state(int(target.id),"standing",0,1)
	actor._process(0)
	check(actor.character._block_color.is_equal_approx(Color(.8,.1,.4)),"LabSoldier forwards actual custom block tint")
	hud._target_preview_controls.reload_progress.value=1.1
	check(is_equal_approx(target.reload_progress,1.1),"test reload slider preserves native final shotgun stage above1")
	session.set_target_state(int(target.id),"standing",2,2)
	session.select_team(2)
	player.follow_first_person=true
	player.follow_target(int(target.id))
	player._sync_camera_mode()
	player._spectator_view.show_target(int(target.id),true)
	player._spectator_view.update_view(.125)
	check(player.get_camera_aim_down_state()>.6,"observed snapshot drives real FP ADS animation")
	check(is_equal_approx(player._spectator_view._last_reload_progress,1.1),"observed FP skin retains final shotgun reload progress")
	hud._target_preview_controls.reloading.toggled.emit(false)
	player._spectator_view.update_view(0)
	hud._target_preview_controls.shot.pressed.emit()
	player._spectator_view.update_view(0)
	check(int(target.shot_sequence)==1 and int(target.ammo)==int(LocalSession.WEAPON_PROFILES[session.profile_version][2].clip_size)-1,"preview shot updates only observed sequence and profile clip")
	check(is_zero_approx(player._spectator_view._skin._fire_elapsed),"first preview shot triggers actual observed skin recoil")
	hud._update_target_shots(.25)
	check(is_equal_approx(target.ready_state,.25/float(LocalSession.WEAPON_PROFILES[session.profile_version][2].delay)),"preview shot readiness follows current weapon profile delay")
	check(session.magazine==magazine and session.shots_fired==rounds,"target animation previews do not consume local player ammunition or fire authority")
	var unchanged:=true
	for index in session.targets.size():unchanged=unchanged and session.targets[index].health==healths[index]
	check(unchanged,"preview shots never damage soldiers")
	check(FileAccess.get_file_as_bytes("user://settings.cfg")==settings_before,"ephemeral target animation state never writes native preferences")
	hud._target_preview_controls.reset.pressed.emit()
	check(not target.has("aiming") and not target.has("ammo") and not target.has("shot_sequence") and hud._target_shot_ages.is_empty(),"reset removes authored preview snapshot fields and timers")
	check(is_zero_approx(hud._target_preview_controls.cook_time.value) and is_zero_approx(hud._target_preview_controls.reload_progress.value),"reset restores actual phase widgets without callbacks")
	app.set_locale("en")
	check(hud._target_preview_controls.action.get_item_text(1)=="Bash","authored preview options respond to locale change")
	app.set_locale("ru")
	app.reset_lab()
	hud.set_menu_visible(false)
	return true

func test_console_chat() -> bool:
	hud.set_menu_visible(false)
	var chat_sounds: Array[int]=[]
	var sound_listener:=func():chat_sounds.append(1)
	hud.chat_sound_requested.connect(sound_listener)
	var previous_fov:=player.base_fov
	var previous_gain:=float(app.hit_feedback_gain)
	hud.open_chat(true)
	hud._chat.set_input_text("/cg_hitF")
	key(KEY_TAB)
	key(KEY_TAB,false)
	check(hud._chat.get_input_text()=="/cg_hitFeedbackSoundGain" and hud._chat.team_channel,"actual command Tab completes mapped cvar and preserves team channel")
	hud._chat.set_input_text("/cg_h")
	key(KEY_TAB)
	key(KEY_TAB,false)
	check(hud._chat.completion_suggestions.size()>1 and hud._chat._completion_hint.visible and hud._chat._completion_hint.text.split("   ").size()<=8,"actual command Tab shows bounded ambiguous native-style suggestions")
	hud._chat.set_input_text("/cg_fov 72")
	key(KEY_ENTER)
	key(KEY_ENTER,false)
	check(is_equal_approx(player.base_fov,72) and hud._chat.messages.back().author=="Консоль","actual chat submit updates mapped camera option and echoes console result")
	hud.open_chat()
	hud._chat.set_input_text("/cg_fov NaN")
	key(KEY_ENTER)
	key(KEY_ENTER,false)
	check(is_equal_approx(player.base_fov,72) and hud._chat.messages.back().text.contains("Invalid"),"invalid command through actual chat cannot write nonfinite camera config")
	hud._send_chat("/cg_hitFeedbackSoundGain .37")
	check(is_equal_approx(float(app.hit_feedback_gain),.37),"console submit reaches original feedback gain")
	hud._send_chat("/cg_hitIndicator 0")
	check(not hud._show_hit_feedback and not hud._ui_settings_controls.hit_indicator.button_pressed,"mapped cvar updates actual HUD state and refreshes checkbox")
	hud._send_chat("/cg_hitIndicator 1")
	check(chat_sounds.is_empty(),"console replies do not request ordinary chat notification audio")
	hud._send_chat("Offline chat notification")
	check(chat_sounds.size()==1,"ordinary chat echo requests source Chat feedback")
	var copied_chat:=hud.get_chat_messages()
	copied_chat.back()["text"]="Mutated exported copy"
	check(hud._chat.messages.back().text=="Offline chat notification","exported chat messages are deeply copied and cannot mutate the live chat")
	hud.chat_sound_requested.disconnect(sound_listener)
	player.base_fov=previous_fov
	app.hit_feedback_gain=previous_gain
	app.save_settings()
	return true
