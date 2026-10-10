extends SceneTree
## Actual input edges from Client_Input.cpp, without synthetic server authority.
const SCENE=preload("res://scenes/main.tscn")
var checks:=0
var failures:=0
var app: Node3D
var saved: Dictionary={}

func _initialize() -> void:call_deferred("_run")
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error("SOURCE INPUT: "+message)
func frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame
		await create_timer(0.0).timeout
func action(name: String,pressed: bool) -> void:
	var event:=InputEventAction.new()
	event.action=name;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()
func voices(path: String) -> Array[Node]:
	var found: Array[Node]=[]
	for voice: Node in app.audio._voices:
		if voice.get_meta("path","")==path:found.append(voice)
	return found
func ready_tool() -> void:
	for frame in 150:
		if app.player.can_use_tool():return
		await frames(1)
	check(false,"actual source equipment reaches ready state")

func _run() -> void:
	for path: String in ["user://settings.cfg","user://servers.cfg"]:
		var exists:=FileAccess.file_exists(path)
		saved[path]={"exists":exists,"bytes":FileAccess.get_file_as_bytes(path) if exists else PackedByteArray()}
	app=SCENE.instantiate();root.add_child(app)
	app.set_skin("original");app.set_locale("en")
	app.session.select_team(0)
	app.session.select_weapon(0)
	app.hud.set_menu_visible(false)
	await ready_tool()
	for pair: Array in [["forward","back",Vector2.UP,Vector2.DOWN],["left","right",Vector2.LEFT,Vector2.RIGHT]]:
		action(pair[0],true)
		check(app.player.get_source_movement_axis()==pair[2],"first movement press selects "+pair[0])
		action(pair[1],true)
		check(app.player.get_source_movement_axis()==pair[3],"new opposing press wins without cancelling "+pair[1])
		action(pair[1],false)
		check(app.player.get_source_movement_axis()==pair[2],"release restores the still-held opposite direction")
		action(pair[1],true);action(pair[0],false)
		check(app.player.get_source_movement_axis()==pair[3],"releasing the older key does not cancel the newer direction")
		action(pair[1],false)
		check(app.player.get_source_movement_axis()==Vector2.ZERO,"both releases clear movement")
	action("forward",true);action("right",true)
	check(app.player.get_source_movement_axis().is_equal_approx(Vector2(1,-1).normalized()),"exclusive axes retain source diagonal normalization")
	LabInputBindings.release_actions()
	app.player._native_velocity=Vector3.ZERO
	app.player.respawn_at(Vector3(48,4,70));app.player.rotation.y=0
	var start: Vector3=app.player.global_position
	action("forward",true);action("back",true)
	await frames(6)
	check(app.player.global_position.z>start.z,"normal offline physics consumes the newer backwards direction")
	LabInputBindings.release_actions()
	app.player.respawn_at(Vector3(48,4,70));app.player.rotation.y=0
	action("back",true);action("forward",true)
	start=app.player.global_position
	await frames(6)
	check(app.player.global_position.z<start.z,"normal offline physics consumes a newer forwards press")
	LabInputBindings.release_actions()
	await ready_tool()
	for hold: bool in [true,false]:
		app.player.hold_aim_down_sight=hold
		app.player._aim_toggled=false;app.player._secondary_held=false
		var before:=voices("Weapons/AimDownSightLocal").size()
		action("secondary",true)
		check(voices("Weapons/AimDownSightLocal").size()==before+1,"fresh ADS edge plays one original sound, hold="+str(hold))
		action("secondary",true)
		check(voices("Weapons/AimDownSightLocal").size()==before+1,"repeated held edge or toggle-off does not duplicate ADS sound")
		action("secondary",false)
		app.player._aim_toggled=false
	app.player.hold_aim_down_sight=true
	app.player._sprint_state=.5
	var count:=voices("Weapons/AimDownSightLocal").size()
	action("secondary",true);action("secondary",false)
	check(voices("Weapons/AimDownSightLocal").size()==count,"residual sprint blocks ADS sound")
	app.player._sprint_state=0
	app.session.magazine=1;app.session.reserve=20
	app.session.reload_weapon()
	action("secondary",true);action("secondary",false)
	check(app.session.is_reloading and voices("Weapons/AimDownSightLocal").size()==count,"reload blocks ADS sound without cancelling itself")
	app.session.end_reload()
	app.session.select_tool(0)
	app.player._weapon_view.initialize_selection(0,0)
	var magazine: int=app.session.magazine
	var reserve: int=app.session.reserve
	action("reload",true);action("reload",false)
	check(not app.session.is_reloading and app.session.magazine==magazine and app.session.reserve==reserve,"actual reload shortcut with spade leaves gun inventory unchanged")
	app.session.select_tool(2)
	action("secondary",true);action("secondary",false)
	check(voices("Weapons/AimDownSightLocal").size()==count,"native lowering/raising gate blocks ADS sound")
	var alerts: Array[int]=[]
	var alert_callback:=func():alerts.append(1)
	app.hud.alert_sound_requested.connect(alert_callback)
	app.session.unlimited_ammo=false
	app.session.blocks=0;app.session.grenades=0;app.session.magazine=0;app.session.reserve=0
	app.session.select_tool(0)
	for tool: Array in [["tool_block","Out of Blocks"],["tool_weapon","Out of Ammo"],["tool_grenade","Out of Grenades"]]:
		var previous:=alerts.size()
		action(tool[0],true);action(tool[0],false)
		check(app.session.current_tool==0 and app.hud._alert_kind=="error" and app.hud._notice.text==tool[1] and alerts.size()==previous+1,"depleted hotkey rejects selection with source error and sound: "+tool[0])
	app.hud._show_alerts=false
	var previous:=alerts.size()
	action("tool_block",true);action("tool_block",false)
	check(alerts.size()==previous+1 and not app.hud._alert_panel.visible,"disabled source alerts retain the depleted-item feedback sound")
	app.hud._show_alerts=true
	app.hud.alert_sound_requested.disconnect(alert_callback)
	var alert_voices:=voices("Feedback/Alert")
	check(not alert_voices.is_empty() and alert_voices.all(func(voice):return voice.get_meta("origin")==Vector3.ZERO and not voice.get_meta("efx_eligible") and voice.get_meta("copies").is_empty()),"actual error UI uses dry centered2D source routing")
	var map_sounds: Array[String]=[]
	var map_callback:=func(path: String):map_sounds.append(path)
	app.hud.map_sound_requested.connect(map_callback)
	action("map",true);action("map",false)
	action("map",true);action("map",false)
	action("map_scale",true);action("map_scale",false)
	check(map_sounds==["Misc/OpenMap","Misc/CloseMap","Misc/SwitchMapZoom"],"real map shortcuts play exactly the three native operation sounds")
	for path: String in map_sounds:
		var active:=voices(path)
		check(not active.is_empty() and active.back().get_meta("origin")==Vector3.ZERO and not active.back().get_meta("efx_eligible"),"map UI sound uses actual dry source playback: "+path)
	app.hud.map_sound_requested.disconnect(map_callback)
	var slash:=InputEventKey.new();slash.keycode=KEY_SLASH;slash.unicode=47;slash.pressed=true
	Input.parse_input_event(slash);Input.flush_buffered_events()
	check(app.hud.is_chat_open() and app.hud._chat.get_input_text()=="/" and not app.player.controls_enabled,"native slash shortcut opens command input with one prefix and captures gameplay")
	slash.pressed=false;Input.parse_input_event(slash);Input.flush_buffered_events()
	app.hud._chat.cancel_input()
	LabInputBindings.release_actions()
	app.stop_audio();app.queue_free()
	await frames(8)
	var deadline:=Time.get_ticks_msec()+200
	while Time.get_ticks_msec()<deadline:OS.delay_msec(1);await process_frame
	for path: String in saved:
		if saved[path].exists:
			var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(saved[path].bytes);file.close()
		else:DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("SOURCE INPUT: %d assertions, %d failures"%[checks,failures])
	quit(1 if failures else 0)
