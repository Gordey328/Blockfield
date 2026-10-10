extends Node3D

@onready var world: VoxelWorld=$VoxelWorld
@onready var session: LocalSession=$LocalSession
@onready var player: BlockfieldPlayer=$Player
@onready var hud: LabHUD=$HUD
var _target_nodes: Array[LabSoldier]=[]
var _player_view: Node3D
var skin_id := "original"
var _notice_time:=0.0
var _objective_nodes: Array[Node3D]=[]
var _grenade_nodes: Dictionary={}
var player_name: String="Player"
var locale: String="ru"
var effects: OpenSpadesEffects
var world_environment: WorldEnvironment
var post_effects: Node
var hdr_scene: Node
var graphics_options: Dictionary = {"lighting":true,"ambient_occlusion":true,"shadows":true,"fog":true,"water":true,"draw_distance":64.0,"particles":2,"blood":true,"shake":2,"fxaa":false,"msaa":0,"bloom":false,"lens":false,"lens_flare":false,"color_correction":true,"saturation":1.0,"exposure":0.0,"tone_map":false,"camera_blur":false,"dof":false,"manual_focus":false,"dof_strength":1.0,"ssao":false,"ssao_strength":1.0,"quality":1,"ambient_energy":0.75}
var positional_audio := true
var environmental_audio := true
var chat_beep:=true
var hit_feedback_gain:=.2
var audio: OpenSpadesAudio
var flashlight_on := false
var _flashlight: SpotLight3D
var _flashlight_fill: OmniLight3D
var _flashlight_age := 0.0
var _hurt_age := 100.0
var _capture_pending := false
var _upload_pending := false
var _upload_kind := ""
var _upload_callback: JavaScriptObject
var _export_callback: JavaScriptObject
var _fullscreen_callback: JavaScriptObject
var _pointer_callback: JavaScriptObject
var browser_pointer_fallback:=false
var _export_menu_was_open:=false
var _export_pending:=false
var _map_baseline := PackedByteArray()
var _map_baseline_name := ""
var focus_control := LabFocus.new()
var console_service:=preload("res://ui/lab_console.gd").new()
var _corpses: Array[OpenSpadesCorpse]=[]
var _last_player_corpse: OpenSpadesCorpse

func _ready() -> void:
	graphics_options.merge({"gi":false,"water_waves":true,"water_refraction":true,"water_reflections":false,"ragdolls":true})
	graphics_options.merge({"hdr":false,"hdr_min_ev":-1.5,"hdr_max_ev":.5,"hdr_speed":1.0})
	_setup_input()
	var environment:=Environment.new()
	environment.background_mode=Environment.BG_SKY
	var sky:=Sky.new()
	var sky_material:=ProceduralSkyMaterial.new()
	sky_material.sky_top_color=Color("557f9c")
	sky_material.sky_horizon_color=Color("c7d4d0")
	sky_material.ground_horizon_color=Color("c7d4d0")
	sky_material.ground_bottom_color=Color("343e3d")
	sky.sky_material=sky_material
	environment.sky=sky
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("b7c9d2")
	environment.ambient_light_energy=0.75
	environment.fog_enabled=true
	environment.fog_light_color=Color("b2c8cd")
	environment.fog_density=0.0025
	world_environment=WorldEnvironment.new()
	world_environment.environment=environment
	add_child(world_environment)
	player.world=world
	player.session=session
	player.lab=self
	player.add_to_group("local_player")
	player.respawn_at(world.get_spawn_position())
	audio=OpenSpadesAudio.new()
	add_child(audio)
	audio.setup(world,player.camera)
	# Keep spatial listening on the reference camera when HDR renders through
	# a shared-world clone in a different viewport.
	var listener:=AudioListener3D.new()
	player.camera.add_child(listener)
	listener.make_current()
	effects=OpenSpadesEffects.new()
	effects.setup(world,player.camera)
	effects.audio_service=audio
	add_child(effects)
	world.blocks_changed.connect(_blocks_changed)
	world.falling_cluster_created.connect(func(cluster: Node3D):_play_spatial("Misc/BlockFall",cluster.global_position))
	world.falling_cluster_finished.connect(func(point: Vector3,count: int,reason: String):
		if reason!="budget":effects.collapse_impact(point,count))
	player.hit_confirmed.connect(hud.show_hit)
	player.hit_confirmed.connect(func(part: String,_damage: float,_friendly: bool):
		if part=="head":player._play_sound("Feedback/HeadshotFeedback",hit_feedback_gain))
	player.notice.connect(hud.show_notice)
	player.build_error.connect(func(message: String):hud.show_alert(message,"warning"))
	_load_settings()
	_load_resource_packs()
	if skin_id not in OpenSpadesExtensions.get_skins():skin_id="original"
	player.skin_id=skin_id
	session.player_name=player_name
	_setup_graphics()
	session.player_hurt.connect(func(amount: float,_origin: Vector3,_kind: String):
		_hurt_age=0.0
		if audio!=null:audio.flesh_hit(player.global_position,true)
		if post_effects!=null:post_effects.damage(amount))
	OpenSpadesLocalization.set_locale(locale)
	console_service.setup(self)
	hud.setup(self,session,player,world)
	hud.alert_sound_requested.connect(func():player._play_sound("Feedback/Alert",1.0,OpenSpadesAudio.LOCAL_ORIGIN))
	hud.chat_sound_requested.connect(func():
		if chat_beep:player._play_sound("Feedback/Chat",1.0,OpenSpadesAudio.LOCAL_ORIGIN))
	if OS.has_feature("web"):
		_ensure_web_exports()
		_pointer_callback=JavaScriptBridge.create_callback(_pointer_capture_result)
		JavaScriptBridge.get_interface("BlockfieldExports").setPointerCallback(_pointer_callback)
	hud.ui_sound_requested.connect(func(kind: String):player._play_sound("Feedback/Limbo/"+kind.capitalize(),1.0,OpenSpadesAudio.LOCAL_ORIGIN))
	session.player_respawned.connect(func():player.respawn_at(world.get_spawn_position()))
	session.player_died.connect(_spawn_player_corpse)
	session.reloaded.connect(func():hud.show_notice("Reload complete"))
	session.restocked.connect(func():player._play_sound("Weapons/RestockLocal",1.0,OpenSpadesAudio.LOCAL_ORIGIN))
	session.grenade_thrown.connect(_grenade_thrown)
	session.grenade_exploded.connect(_grenade_exploded)
	session.match_event.connect(_match_event_audio)
	_player_view=OpenSpadesExtensions.create_third_person_skin(skin_id,{"player":player,"session":session})
	player.add_child(_player_view)
	_spawn_targets()
	_setup_objectives()
	hud.set_menu_visible(true)

func _process(delta: float) -> void:
	session.update(delta)
	audio.positional=positional_audio
	audio.environmental=environmental_audio
	for corpse in _corpses:corpse.step(delta)
	_player_view.set_team(session.team,session.get_team_info(session.team).color)
	_player_view.visible=player.camera_mode in [BlockfieldPlayer.CameraMode.THIRD_PERSON,BlockfieldPlayer.CameraMode.DEATH] and session.team<2
	for target_node in _target_nodes:
		target_node.visible=not (player.camera_mode==BlockfieldPlayer.CameraMode.FOLLOW_FIRST_PERSON and player.followed_target_id==target_node.target_id)
	_player_view.set_pose(player.crouching,session.health<=0,player.sprinting)
	_player_view.set_weapon(session.current_weapon,session.current_tool)
	if _player_view.has_method("set_motion_state"):
		_player_view.set_motion_state(player.velocity.dot(-player.global_basis.z),player.velocity.dot(player.global_basis.x),player.get_walk_progress())
	else:_player_view.animate_motion(Vector2(player.velocity.x,player.velocity.z).length(),session.session_time)
	_player_view.set_aim(player.head.rotation.x)
	if _player_view.has_method("set_ragdoll_enabled"):_player_view.set_ragdoll_enabled(is_instance_valid(_last_player_corpse) and session.health<=0)
	if _player_view.has_method("set_block_color"):_player_view.set_block_color(player.block_color)
	if _player_view.has_method("set_tool_action"):
		var action: Dictionary=player.get_tool_action()
		_player_view.set_tool_action(action.type,action.progress,session.grenade_cook_time,action.ready)
	var carries_intel:=false
	for flag in session.ctf_flags:
		if int(flag.carrier)==0:carries_intel=true
	_player_view.set_intel_carrier(carries_intel,session.get_team_info(1-session.team if session.team<2 else 1).color)
	_notice_time+=delta
	_update_objective_views()
	_hurt_age+=delta
	_update_graphics(delta)
	session.player_name=player_name

func _setup_input() -> void:
	var actions:={"forward":KEY_W,"back":KEY_S,"left":KEY_A,"right":KEY_D,"jump":KEY_SPACE,"crouch":KEY_CTRL,"sprint":KEY_SHIFT,"sneak":KEY_V,"reload":KEY_R,"tool_spade":KEY_1,"tool_block":KEY_2,"tool_weapon":KEY_3,"tool_grenade":KEY_4,"eyedropper":KEY_E,"view_toggle":KEY_F,"map":KEY_N,"scoreboard":KEY_TAB,"pause":KEY_ESCAPE,"chat":KEY_T,"last_tool":KEY_Q,"map_scale":KEY_M,"chat_team":KEY_Y,"chat_log":KEY_H,"hide_hud":KEY_F6,"stats":KEY_F7,"screenshot":KEY_0,"sceneshot":KEY_9,"save_map":KEY_8,"flashlight":KEY_L}
	actions.merge({"palette_left":KEY_LEFT,"palette_right":KEY_RIGHT,"palette_up":KEY_UP,"palette_down":KEY_DOWN})
	for action in actions:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var event:=InputEventKey.new()
		event.physical_keycode=actions[action]
		InputMap.action_add_event(action,event)
	for entry in [["primary",MOUSE_BUTTON_LEFT],["secondary",MOUSE_BUTTON_RIGHT],["autofocus",MOUSE_BUTTON_MIDDLE]]:
		if not InputMap.has_action(entry[0]):InputMap.add_action(entry[0])
		InputMap.action_erase_events(entry[0])
		var event:=InputEventMouseButton.new()
		event.button_index=entry[1]
		InputMap.action_add_event(entry[0],event)
	var helper_path:="res://ui/input_bindings.gd"
	if ResourceLoader.exists(helper_path):
		var helper: Script=load(helper_path)
		helper.load_bindings()

func _unhandled_input(event: InputEvent) -> void:
	if player.controls_enabled and session.health>0 and session.team<2 and event.is_action_pressed("flashlight"):
		flashlight_on=not flashlight_on
		_flashlight_age=0.0
		player._play_sound("Player/Flashlight")
		get_viewport().set_input_as_handled()

func _spawn_targets() -> void:
	for target in _target_nodes:
		session.remove_target(target.target_id)
		target.queue_free()
	_target_nodes.clear()
	session.targets.clear()
	for i in 6:
		var point:=Vector3(35.0+i*5.0,4.0,48.0 if i<3 else 35.0)
		if world.dimensions.x>96:
			var origin:=world.get_spawn_position()
			point=_surface_position(origin.x+(i-2.5)*5.0,origin.z-(20.0 if i<3 else 35.0))
		var id:int=session.add_target(point,i%2,i>=3)
		session.set_target_state(id,["standing","crouching","dead","walking","sprinting","standing"][i],i%3,[2,0,2,1,2,3][i])
		var soldier:=LabSoldier.new()
		soldier.skin_id=skin_id
		add_child(soldier)
		soldier.setup(session,id,point)
		_target_nodes.append(soldier)

func reset_targets() -> void:
	clear_corpses()
	_spawn_targets()

func spawn_lab_target(moving: bool=false,target_team: int=1) -> int:
	if _target_nodes.size()>=32:
		hud.show_notice("Target limit: 32")
		return -1
	var direction:=Vector3(player.get_aim_direction().x,0,player.get_aim_direction().z).normalized()
	var point:=player.global_position+direction*8.0+player.global_basis.x*float(_target_nodes.size()%3-1)*2.0
	point=_surface_position(clampf(point.x,1,world.dimensions.x-2),clampf(point.z,1,world.dimensions.z-2))
	var identifier:=session.add_target(point,clampi(target_team,0,1),moving)
	if moving:session.set_target_state(identifier,"walking",session.current_weapon,2)
	var actor:=LabSoldier.new()
	actor.skin_id=skin_id
	add_child(actor)
	actor.setup(session,identifier,point)
	_target_nodes.append(actor)
	return identifier

func _setup_objectives() -> void:
	for node in _objective_nodes:node.queue_free()
	_objective_nodes.clear()
	var blue:=Vector3(20,4,70)
	var green:=Vector3(76,4,22)
	var territories: Array[Vector3]=[Vector3(20,4,40),Vector3(48,4,40),Vector3(76,4,40)]
	if world.dimensions.x>96:
		var origin:=world.get_spawn_position()
		blue=_surface_position(origin.x-25,origin.z+15)
		green=_surface_position(origin.x+25,origin.z-35)
		territories=[_surface_position(origin.x-20,origin.z-15),_surface_position(origin.x,origin.z-15),_surface_position(origin.x+20,origin.z-15)]
	session.configure_ctf(blue,green)
	session.configure_tc(territories)
	for entry in [[blue,Color("549cdf")],[green,Color("8cb66f")]]:
		var base:=OpenSpadesModels.create("MapObjects/CheckPoint")
		base.scale=Vector3.ONE*0.3
		base.position=entry[0]
		base.set_meta("objective","ctf_base")
		base.set_meta("index",_objective_nodes.size())
		OpenSpadesModels.set_tint(base,entry[1])
		add_child(base)
		_objective_nodes.append(base)
	for index in 2:
		var intel:=OpenSpadesModels.create("MapObjects/Intel")
		intel.scale=Vector3.ONE*0.1
		intel.set_meta("objective","intel")
		intel.set_meta("index",index)
		OpenSpadesModels.set_tint(intel,session.get_team_info(index).color)
		add_child(intel)
		_objective_nodes.append(intel)
	for index in territories.size():
		var checkpoint:=OpenSpadesModels.create("MapObjects/CheckPoint")
		checkpoint.scale=Vector3.ONE*0.3
		checkpoint.position=territories[index]
		checkpoint.set_meta("objective","tc")
		checkpoint.set_meta("index",index)
		add_child(checkpoint)
		_objective_nodes.append(checkpoint)
	_update_objective_views()

func _update_objective_views() -> void:
	for node in _objective_nodes:
		var kind: String=node.get_meta("objective","")
		node.visible=session.mode=="ctf" if kind!="tc" else session.mode=="tc"
		var index: int=node.get_meta("index",0)
		if kind in ["ctf_base","intel"]:OpenSpadesModels.set_tint(node,session.get_team_info(index).color)
		if kind=="intel" and index<session.ctf_flags.size():
			var flag: Dictionary=session.ctf_flags[index]
			node.position=flag.position
			node.visible=node.visible and int(flag.carrier)<0
		elif kind=="tc" and index<session.territories.size():
			var owner: int=session.territories[index].owner
			OpenSpadesModels.set_tint(node,session.get_team_info(owner).color if owner<2 else Color.WHITE)

func _surface_position(x: float,z: float) -> Vector3:
	var cell:=Vector3i(clampi(floori(x),1,world.dimensions.x-2),world.dimensions.y-1,clampi(floori(z),1,world.dimensions.z-2))
	while cell.y>0 and world.get_block(cell)==0:cell.y-=1
	return Vector3(cell.x+0.5,cell.y+1.0,cell.z+0.5)

func reset_lab() -> void:
	clear_corpses()
	_map_baseline=PackedByteArray()
	_map_baseline_name=""
	if effects!=null:effects.clear()
	for grenade in _grenade_nodes.values():
		if is_instance_valid(grenade):grenade.queue_free()
	_grenade_nodes.clear()
	world.generate_lab()
	flashlight_on=false
	session.reset_lab()
	player.respawn_at(world.get_spawn_position())
	_spawn_targets()
	_setup_objectives()
	hud.show_notice("Test grounds reset")

func reset_match() -> void:
	if _map_baseline.is_empty():
		reset_lab()
		return
	_finish_map_load(world.load_vxl_bytes(_map_baseline,_map_baseline_name))
	hud.show_notice("Map and match reset")

func spawn_tracer(start: Vector3, end: Vector3) -> void:
	var visual:=MeshInstance3D.new()
	var mesh:=CylinderMesh.new()
	mesh.top_radius=0.009
	mesh.bottom_radius=0.009
	mesh.height=start.distance_to(end)
	mesh.radial_segments=4
	visual.mesh=mesh
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color("ffdda2")
	visual.material_override=material
	add_child(visual)
	visual.global_position=(start+end)*0.5
	if absf((end-start).normalized().dot(Vector3.UP))<0.999:
		visual.look_at(end,Vector3.UP)
		visual.rotate_object_local(Vector3.RIGHT,PI/2)
	get_tree().create_timer(0.055).timeout.connect(visual.queue_free)

func _grenade_thrown(data: Dictionary) -> void:
	var forward: Vector3=player.get_aim_direction()
	var point: Vector3=player.get_aim_origin()+forward*0.1
	var speed: Vector3=player.velocity+forward*32.0
	if bool(data.get("drop",false)):
		speed=player.velocity
	spawn_grenade(point,speed,float(data.fuse),int(data.id))
	session.set_grenade_position(int(data.id),point)

func _grenade_exploded(data: Dictionary) -> void:
	var grenade: LabGrenade=_grenade_nodes.get(int(data.id))
	if is_instance_valid(grenade):grenade.detonate()
	_grenade_nodes.erase(int(data.id))

func spawn_grenade(point: Vector3, speed: Vector3, fuse: float, identifier: int=-1) -> void:
	var grenade:=LabGrenade.new()
	grenade.world=world
	grenade.session=session
	grenade.velocity=speed
	grenade.fuse=fuse
	grenade.grenade_id=identifier
	add_child(grenade)
	grenade.global_position=point
	_grenade_nodes[identifier]=grenade
	grenade.detonated.connect(_explosion)
	grenade.bounced.connect(func(point: Vector3,water: bool):
		if not water:_play_spatial("Weapons/Grenade/Bounce",point))
	grenade.dropped_into_water.connect(func(point: Vector3):
		_play_spatial("Weapons/Grenade/DropWater",point)
		effects.water_hit(point))
	player._play_sound("Weapons/Grenade/Throw",1.0,Vector3(.4,.1,.3))

func _explosion(point: Vector3) -> void:
	var underwater: bool=point.y<world.water_level
	effects.grenade_explosion(point,underwater)
	_play_explosion_audio(point,underwater)

func _blocks_changed(changes: Array) -> void:
	if effects==null:return
	for change in changes:
		if int(change.before)!=0 and int(change.after)==0 and not bool(change.collapsed):
			effects.block_destroy(Vector3(change.cell)+Vector3.ONE*0.5,VoxelWorld.block_color(int(change.before)))
	if not changes.is_empty() and int(changes[0].before)!=0 and int(changes[0].after)==0 and not bool(changes[0].collapsed):
		_play_spatial("Misc/BlockDestroy",Vector3(changes[0].cell)+Vector3.ONE*0.5)

func _play_spatial(path: String,point: Vector3) -> void:
	if audio!=null:audio.play_spatial(path,point)

func load_original_map() -> void:
	hud.show_notice("Loading original OpenSpades map…")
	await get_tree().process_frame
	var error:=world.load_vxl("res://assets/openspades/maps/Title.vxl")
	if error==OK:
		_map_baseline=FileAccess.get_file_as_bytes("res://assets/openspades/maps/Title.vxl")
		_map_baseline_name="Title.vxl"
	_finish_map_load(error)

func _finish_map_load(error: Error) -> void:
	if error==OK:
		clear_corpses()
		for grenade in _grenade_nodes.values():
			if is_instance_valid(grenade):grenade.queue_free()
		_grenade_nodes.clear()
		effects.clear()
		flashlight_on=false
		session.reset_lab()
		player.respawn_at(world.get_spawn_position())
		_spawn_targets()
		_setup_objectives()
		hud.show_notice("Map loaded: %s" % _map_baseline_name)
	else:hud.show_alert("Map load error: %s"%error_string(error),"error")

func load_map_file() -> void:
	_choose_upload("map")

func import_resource_pack() -> void:
	_choose_upload("pack")

func _choose_upload(kind: String) -> void:
	if _upload_pending:return
	_upload_pending=true
	_upload_kind=kind
	if OS.has_feature("web"):
		_upload_callback=JavaScriptBridge.create_callback(_receive_upload)
		var window:=JavaScriptBridge.get_interface("window")
		window.BlockfieldFileReceiver=_upload_callback
		var maximum:=32*1024*1024 if kind=="pack" else 80*1024*1024
		var extension:=".zip" if kind=="pack" else ".vxl"
		# Only this fixed application code is evaluated; selected file contents
		# stay binary data and are passed to the validated format loader.
		JavaScriptBridge.eval("""
			(function(){
				const input=document.createElement('input');
				input.type='file';input.accept='%s';
				input.addEventListener('cancel',()=>window.BlockfieldFileReceiver(null,'','cancelled'));
				input.addEventListener('change',async()=>{
					const file=input.files[0];
					if(!file){window.BlockfieldFileReceiver(null,'','cancelled');return;}
					if(file.size>%d){window.BlockfieldFileReceiver(null,file.name,'File is too large');return;}
					try{window.BlockfieldFileReceiver(await file.arrayBuffer(),file.name,'');}
					catch(error){window.BlockfieldFileReceiver(null,file.name,String(error));}
				});input.click();
			})();
		"""%[extension,maximum])
	else:
		var dialog:=FileDialog.new()
		dialog.access=FileDialog.ACCESS_FILESYSTEM
		dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE
		dialog.filters=PackedStringArray(["*.zip ; Blockfield resource pack"] if kind=="pack" else ["*.vxl ; VXL voxel map"])
		add_child(dialog)
		dialog.file_selected.connect(func(path: String):
			_apply_upload(FileAccess.get_file_as_bytes(path),path.get_file())
			dialog.queue_free())
		dialog.canceled.connect(func():_upload_pending=false;dialog.queue_free())
		dialog.popup_centered_ratio(0.8)

func _receive_upload(arguments: Array) -> void:
	if arguments.size()<3 or arguments[0]==null:
		_upload_pending=false
		if arguments.size()>=3 and str(arguments[2])!="cancelled":hud.show_alert(str(arguments[2]),"error")
		return
	if not JavaScriptBridge.is_js_buffer(arguments[0]):
		_upload_pending=false
		hud.show_alert("Invalid file buffer","error")
		return
	_apply_upload(JavaScriptBridge.js_buffer_to_packed_byte_array(arguments[0]),str(arguments[1]))

func _apply_upload(bytes: PackedByteArray,filename: String) -> void:
	_upload_pending=false
	if _upload_kind=="map":
		var error:=world.load_vxl_bytes(bytes,filename)
		if error==OK:
			_map_baseline=bytes.duplicate()
			_map_baseline_name=filename
		_finish_map_load(error)
	else:
		var result:=OpenSpadesExtensions.load_pack_bytes(bytes)
		if not bool(result.ok):hud.show_alert(str(result.error),"error");return
		var directory:="user://packs"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		var archive:=FileAccess.open(directory+"/"+str(result.id)+".zip",FileAccess.WRITE)
		if archive!=null:archive.store_buffer(bytes);archive.close()
		var config:=ConfigFile.new()
		config.load("user://settings.cfg")
		var ids:=PackedStringArray()
		for pack in OpenSpadesExtensions.get_packs():ids.append(str(pack.id))
		config.set_value("resources","packs",ids)
		config.save("user://settings.cfg")
		_refresh_resource_overrides()
		hud.show_notice("Resource pack loaded: "+str(result.id))

func clear_resource_packs() -> void:
	for pack in OpenSpadesExtensions.get_packs():
		var id: String=str(pack.id)
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://packs/"+id+".zip"))
	OpenSpadesExtensions.clear()
	var config:=ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("resources","packs",PackedStringArray())
	config.save("user://settings.cfg")
	set_skin("original")
	_refresh_resource_overrides()
	hud.show_notice("Original resources restored")

func _refresh_resource_overrides() -> void:
	for corpse in _corpses:corpse.refresh_resources()
	if world.has_method("reload_resources"):world.reload_resources()
	_player_view.refresh_resources()
	player.refresh_resources()
	for target in _target_nodes:target.refresh_resources()
	effects.reload_resources()
	if post_effects!=null:post_effects.reload_resources()
	if hdr_scene!=null and hdr_scene.exposure!=null:hdr_scene.exposure.set_bloom_dust_texture(OpenSpadesExtensions.texture("res://assets/openspades/images/Textures/LensDustTexture.png"))
	if hud.has_method("reload_resources"):hud.reload_resources()
	# Preserve match state while replacing object meshes, without reconfiguring
	# objectives or resetting pickups/capture progress.
	for index in _objective_nodes.size():
		var old:=_objective_nodes[index]
		var kind: String=old.get_meta("objective","")
		var replacement:=OpenSpadesModels.create("MapObjects/Intel" if kind=="intel" else "MapObjects/CheckPoint")
		replacement.transform=old.transform
		for key in old.get_meta_list():replacement.set_meta(key,old.get_meta(key))
		add_child(replacement)
		old.queue_free()
		_objective_nodes[index]=replacement
	_update_objective_views()

func _load_resource_packs() -> void:
	var config:=ConfigFile.new()
	if config.load("user://settings.cfg")!=OK:return
	var ids: Variant=config.get_value("resources","packs",PackedStringArray())
	if not ids is PackedStringArray and not ids is Array:return
	for identifier in ids:
		var id:=str(identifier)
		if id.is_empty() or id==".." or "/" in id or "\\" in id or ":" in id:continue
		var path:="user://packs/"+id+".zip"
		if FileAccess.file_exists(path):
			var result:=OpenSpadesExtensions.load_pack_file(path)
			if not bool(result.ok):push_warning("Resource pack could not be restored: "+id)

func set_skin(id: String) -> void:
	if id not in OpenSpadesExtensions.get_skins():return
	skin_id=id
	player.set_skin(id)
	if _player_view!=null:
		_player_view.hide()
		_player_view.queue_free()
	_player_view=OpenSpadesExtensions.create_third_person_skin(id,{"player":player,"session":session})
	player.add_child(_player_view)
	for target in _target_nodes:target.set_skin(id)
	save_settings()

func save_map() -> void:
	hud.show_notice("Encoding VXL map…")
	await get_tree().process_frame
	var bytes: PackedByteArray=world.encode_vxl()
	if bytes.is_empty():
		hud.show_alert("Map encoding failed","error")
		return
	if OS.has_feature("web"):
		_show_web_export(bytes,"blockfield-map.vxl","application/octet-stream")
	else:
		var file:=FileAccess.open("user://blockfield-map.vxl",FileAccess.WRITE)
		if file==null:
			hud.show_alert("Map save failed","error")
			return
		file.store_buffer(bytes)
	hud.show_notice("VXL map ready" if OS.has_feature("web") else "VXL map saved")

func _show_web_export(bytes: PackedByteArray,filename: String,mime: String) -> void:
	if _export_pending:return
	_export_pending=true
	_export_menu_was_open=hud.is_menu_open()
	hud.set_menu_visible(true)
	if _export_callback==null:
		_ensure_web_exports()
		_export_callback=JavaScriptBridge.create_callback(_web_export_closed)
	var exports:=JavaScriptBridge.get_interface("BlockfieldExports")
	exports.begin(filename,mime,_export_callback)
	# 48 KiB chunks bound transient base64 strings and avoid a single giant
	# JavaScript source string. Bytes and filenames are passed as data.
	for offset in range(0,bytes.size(),49152):
		exports.append(Marshalls.raw_to_base64(bytes.slice(offset,mini(bytes.size(),offset+49152))))
	exports.finish(locale)

func _ensure_web_exports() -> void:
	JavaScriptBridge.eval("if(!window.BlockfieldExports){"+FileAccess.get_file_as_string("res://web/exports.js")+"}")

func toggle_fullscreen() -> void:
	if OS.has_feature("web"):
		_ensure_web_exports()
		if _fullscreen_callback==null:_fullscreen_callback=JavaScriptBridge.create_callback(_fullscreen_result)
		JavaScriptBridge.get_interface("BlockfieldExports").toggleFullscreen(_fullscreen_callback)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _fullscreen_result(arguments: Array) -> void:
	if not arguments.is_empty() and not str(arguments[0]).is_empty():hud.show_alert("Fullscreen: "+str(arguments[0]),"error")

func _pointer_capture_result(arguments: Array) -> void:
	if arguments.is_empty():return
	browser_pointer_fallback=not bool(arguments[0])
	if browser_pointer_fallback:
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		hud.show_alert("Захват мыши недоступен: удерживайте кнопку мыши и тяните для обзора." if locale=="ru" else "Mouse capture unavailable: hold a mouse button and drag to look.","warning",true)

func _web_export_closed(_arguments: Array) -> void:
	_export_pending=false
	hud.set_menu_visible(_export_menu_was_open)

func save_settings() -> void:
	var config:=ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("input","sensitivity",player.sensitivity)
	config.set_value("view","fov",player.base_fov)
	config.set_value("view","skin",skin_id)
	config.set_value("audio","volume",AudioServer.get_bus_volume_db(0))
	config.set_value("audio","positional",positional_audio)
	config.set_value("audio","environmental",environmental_audio)
	config.set_value("audio","chat_beep",chat_beep)
	config.set_value("audio","hit_feedback_gain",hit_feedback_gain)
	config.set_value("view","weapon_offset",player.view_weapon_offset)
	config.set_value("focus","speed",focus_control.speed)
	config.set_value("profile","name",player_name)
	config.set_value("profile","locale",locale)
	for property in ["hold_aim_down_sight","invert_mouse","mouse_exponent","ads_sensitivity","wheel_tool_direction","animations_enabled","eject_brass"]:
		config.set_value("input",property,player.get(property))
	for key in graphics_options:config.set_value("graphics",key,graphics_options[key])
	config.save("user://settings.cfg")

func set_locale(value: String) -> void:
	locale=OpenSpadesLocalization.set_locale(value)
	save_settings()

func _load_settings() -> void:
	var config:=ConfigFile.new()
	if config.load("user://settings.cfg")!=OK:return
	player.sensitivity=float(config.get_value("input","sensitivity",0.0025))
	player.base_fov=float(config.get_value("view","fov",68.0))
	skin_id=str(config.get_value("view","skin","original"))
	AudioServer.set_bus_volume_db(0,float(config.get_value("audio","volume",0.0)))
	positional_audio=bool(config.get_value("audio","positional",true))
	environmental_audio=bool(config.get_value("audio","environmental",true))
	chat_beep=bool(config.get_value("audio","chat_beep",true))
	hit_feedback_gain=clampf(float(config.get_value("audio","hit_feedback_gain",.2)),0,1)
	var saved_offset: Variant=config.get_value("view","weapon_offset",Vector3.ZERO)
	if saved_offset is Vector3 and saved_offset.is_finite():player.view_weapon_offset=saved_offset.clamp(Vector3.ONE*-5,Vector3.ONE*5)
	focus_control.speed=clampf(float(config.get_value("focus","speed",.4)),0,5)
	player_name=str(config.get_value("profile","name","Player"))
	locale=str(config.get_value("profile","locale","ru"))
	for property in ["hold_aim_down_sight","invert_mouse","mouse_exponent","ads_sensitivity","wheel_tool_direction","animations_enabled","eject_brass"]:
		player.set(property,config.get_value("input",property,player.get(property)))
	for key in graphics_options:graphics_options[key]=config.get_value("graphics",key,graphics_options[key])

func _setup_graphics() -> void:
	_flashlight=SpotLight3D.new()
	_flashlight.light_color=Color(1.0,0.7,0.5)
	_flashlight.spot_range=40.0
	_flashlight.spot_angle=30.0
	_flashlight.position=Vector3(0,-0.1,-0.05)
	player.head.add_child(_flashlight)
	_flashlight_fill=OmniLight3D.new()
	_flashlight_fill.light_color=_flashlight.light_color
	_flashlight_fill.omni_range=10.0
	_flashlight.add_child(_flashlight_fill)
	var post_path:="res://presentation/openspades_post_effects.gd"
	if ResourceLoader.exists(post_path):
		post_effects=(load(post_path) as Script).new()
		add_child(post_effects)
		post_effects.setup(player.camera,world_environment)
	hdr_scene=preload("res://presentation/hdr_scene_viewport.gd").new()
	add_child(hdr_scene)
	hdr_scene.setup(player.camera,get_viewport())
	_apply_graphics()

func get_graphics_options() -> Dictionary:
	return graphics_options.duplicate(true)

func handle_focus_input(event: InputEvent) -> bool:
	if not bool(graphics_options.manual_focus):return false
	if event.is_action_pressed("autofocus"):
		focus_control.automatic=true
		return true
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var near_button:=MOUSE_BUTTON_WHEEL_DOWN if player.wheel_tool_direction>0 else MOUSE_BUTTON_WHEEL_UP
		focus_control.adjust_wheel(event.button_index==near_button)
		return true
	return false

func set_graphics_option(key: String,value: Variant) -> void:
	if not graphics_options.has(key):return
	graphics_options[key]=value
	_apply_graphics()
	save_settings()

func set_graphics_preset(name: String) -> void:
	if post_effects!=null:
		post_effects.preset(name)
		graphics_options.merge(post_effects.get_options(),true)
	graphics_options["shadows"]=name!="low"
	graphics_options["ambient_occlusion"]=name!="low"
	graphics_options["draw_distance"]=64.0 if name!="high" else 128.0
	graphics_options["particles"]=0 if name=="low" else 2
	_apply_graphics()
	save_settings()

func _apply_graphics() -> void:
	if world.has_method("set_lighting_enabled"):world.set_lighting_enabled(bool(graphics_options.lighting))
	if world.has_method("set_ambient_occlusion_enabled"):world.set_ambient_occlusion_enabled(bool(graphics_options.ambient_occlusion))
	if world.has_method("set_irradiance_enabled"):
		world.set_irradiance_enabled(bool(graphics_options.gi))
		world.set_irradiance_light($Sun.light_color,$Sun.light_energy)
	if world.has_method("set_water_waves_enabled"):world.set_water_waves_enabled(bool(graphics_options.water_waves))
	if world.has_method("set_water_refraction_enabled"):world.set_water_refraction_enabled(bool(graphics_options.water_refraction))
	world.set_reflection_camera(player.camera)
	world.set_water_reflections_enabled(bool(graphics_options.water_reflections))
	if not bool(graphics_options.ragdolls):clear_corpses()
	if world.has_method("set_draw_distance"):graphics_options.draw_distance=world.set_draw_distance(float(graphics_options.draw_distance))
	world.set_water_enabled(bool(graphics_options.water))
	# Native sunLightDirection=(0,-1,-1); map axes convert this to (0,1,-1).
	$Sun.rotation_degrees=Vector3(-45,180,0)
	$Sun.shadow_enabled=bool(graphics_options.shadows)
	$Sun.directional_shadow_max_distance=float(graphics_options.draw_distance)
	world_environment.environment.ambient_light_energy=clampf(float(graphics_options.ambient_energy),0,1.5)
	world_environment.environment.fog_enabled=bool(graphics_options.fog)
	world.set_water_fog_enabled(bool(graphics_options.fog))
	world_environment.environment.fog_density=1.0/maxf(16.0,float(graphics_options.draw_distance))*0.3
	effects.quality=clampi(int(graphics_options.particles),0,2)
	effects.blood_enabled=bool(graphics_options.blood)
	effects.shake_level=clampi(int(graphics_options.shake),0,2)
	if _flashlight!=null:_flashlight.shadow_enabled=bool(graphics_options.shadows)
	if post_effects!=null:
		var post_options: Dictionary={}
		for key in post_effects.get_options():
			if graphics_options.has(key):post_options[key]=graphics_options[key]
		post_effects.set_options(post_options)
	if hdr_scene!=null:
		var hdr_result: Dictionary=hdr_scene.set_options({"min_ev":float(graphics_options.hdr_min_ev),"max_ev":float(graphics_options.hdr_max_ev),"speed":float(graphics_options.hdr_speed),"bloom":bool(graphics_options.bloom)})
		if bool(hdr_result.ok):
			graphics_options.hdr_min_ev=hdr_result.options.min_ev
			graphics_options.hdr_max_ev=hdr_result.options.max_ev
			graphics_options.hdr_speed=hdr_result.options.speed
		hdr_scene.set_enabled(bool(graphics_options.hdr))
		# Float target availability can differ between browser GPUs.
		graphics_options.hdr=hdr_scene.enabled
		if post_effects!=null:
			post_effects.set_hdr_active(hdr_scene.enabled)
			if hdr_scene.exposure!=null:
				hdr_scene.exposure.set_bloom_dust_texture(OpenSpadesExtensions.texture("res://assets/openspades/images/Textures/LensDustTexture.png"))
		_update_hdr_correction()

func _update_hdr_correction() -> void:
	if hdr_scene==null or not hdr_scene.enabled or post_effects==null:return
	var material: ShaderMaterial=hdr_scene.exposure.get_present_material()
	var values: Dictionary=post_effects.get_hdr_correction()
	for key in values:material.set_shader_parameter(key,values[key])

func _update_graphics(delta: float) -> void:
	_flashlight_age+=delta
	if _flashlight!=null:
		_flashlight.visible=flashlight_on and session.health>0 and session.team<2
		_flashlight.light_energy=1.5*(1.0-exp(-_flashlight_age*5.0))
		_flashlight_fill.light_energy=_flashlight.light_energy*0.3
	if post_effects!=null:
		if bool(graphics_options.manual_focus):focus_control.sample(player.camera,world)
		focus_control.advance(delta)
		post_effects.update_state(delta,session.health,_hurt_age,player.sprinting,player.get_camera_aim_down_state(),focus_control.distance,player.camera_radial_blur)
		var sun_direction: Vector3=$Sun.global_basis.z
		var sun_occluded: bool=world.cast_voxel(player.camera.global_position,sun_direction,float(graphics_options.draw_distance)).hit
		var flare_sources: Array[Dictionary]=[{"direction":sun_direction,"color":$Sun.light_color,"energy":0.6,"radius":0.03,"visible":not sun_occluded}]
		post_effects.set_flare_sources(flare_sources)
		_update_hdr_correction()

func screenshot(scene_only: bool=false) -> void:
	if _capture_pending:return
	_capture_pending=true
	var was_visible:=hud.visible
	if scene_only:hud.set_capture_visible(false)
	await RenderingServer.frame_post_draw
	var image:=get_viewport().get_texture().get_image()
	if scene_only:hud.set_capture_visible(was_visible)
	var bytes:=image.save_png_to_buffer()
	var filename:="blockfield-%s-%d.png"%["scene" if scene_only else "screen",Time.get_unix_time_from_system()]
	if OS.has_feature("web"):_show_web_export(bytes,filename,"image/png")
	else:
		var file:=FileAccess.open("user://"+filename,FileAccess.WRITE)
		if file==null:
			_capture_pending=false
			hud.show_alert("Screenshot save failed","error")
			return
		file.store_buffer(bytes)
	_capture_pending=false
	hud.show_notice("Screenshot ready" if OS.has_feature("web") else "Screenshot saved")

func export_event_log() -> void:
	var record: Dictionary={"format":"blockfield-session-log","version":1,"utc":Time.get_datetime_string_from_system(true),"profile":session.profile_version,"mode":session.mode,"events":session.event_log.duplicate(true),"chat":hud.get_chat_messages()}
	var bytes:=JSON.stringify(record,"\t").to_utf8_buffer()
	var filename:="blockfield-session-%d.json"%Time.get_unix_time_from_system()
	if OS.has_feature("web"):_show_web_export(bytes,filename,"application/json")
	else:
		var file:=FileAccess.open("user://"+filename,FileAccess.WRITE)
		if file==null:
			hud.show_alert("Session log save failed","error")
			return
		file.store_buffer(bytes)
	hud.show_notice("Session log ready" if OS.has_feature("web") else "Session log saved")

func _play_explosion_audio(point: Vector3,underwater: bool) -> void:
	if audio!=null:audio.explosion(point,underwater)

func _match_event_audio(event: Dictionary) -> void:
	match str(event.type):
		"intel_pickup":player._play_sound("Feedback/CTF/PickedUp")
		"intel_capture":player._play_sound("Feedback/CTF/YourTeamCaptured" if int(event.team)==session.team else "Feedback/CTF/EnemyCaptured")
		"territory_capture":player._play_sound("Feedback/TC/YourTeamCaptured" if int(event.team)==session.team else "Feedback/TC/EnemyCaptured")
		"round_won":player._play_sound("Feedback/Win" if int(event.team)==session.team else "Feedback/Lose")
		"kill":
			_spawn_target_corpse(event)

func _spawn_target_corpse(event: Dictionary) -> void:
	if not bool(graphics_options.ragdolls):return
	var target:=session.get_target(int(event.get("target_id",-1)))
	if target.is_empty():return
	var part:=str(event.get("part","weapon"))
	var impulse: Vector3=Vector3.UP*randf_range(4,8) if part=="grenade" else (Vector3(target.position)-player.global_position).normalized()*(6.0 if part=="melee" else [3.5,2.8,4.5][int(event.get("weapon",0))])
	spawn_corpse({"player_id":int(target.id),"feet_position":target.position,"yaw":float(target.get("yaw",0.0)),"crouch":bool(target.get("death_crouch",false)),"team":int(target.team),"color":session.get_team_info(int(target.team)).color,"velocity":target.get("death_velocity",Vector3.ZERO),"impulse":impulse})
	for node in _target_nodes:
		if node.target_id==int(target.id) and node.character.has_method("set_ragdoll_enabled"):node.character.set_ragdoll_enabled(true)

func _spawn_player_corpse() -> void:
	if not bool(graphics_options.ragdolls):return
	var cause:=session.last_death_kind
	_last_player_corpse=spawn_corpse({"player_id":0,"feet_position":player.global_position,"yaw":player.rotation.y,"crouch":player.crouching,"team":session.team,"color":session.get_team_info(session.team).color,"velocity":player.velocity,"impulse":Vector3.UP*randf_range(4,8) if cause=="grenade" else Vector3.ZERO})

func spawn_corpse(state: Dictionary) -> OpenSpadesCorpse:
	var corpse:=OpenSpadesCorpse.new()
	add_child(corpse)
	corpse.setup(world,state)
	_corpses.append(corpse)
	if _corpses.size()>16:
		var oldest: OpenSpadesCorpse=_corpses.pop_front()
		if oldest==_last_player_corpse:_last_player_corpse=null
		oldest.clear();oldest.queue_free()
	elif _corpses.size()>6:
		var candidates:=_corpses.size()-6
		for index in range(candidates):
			var old:=_corpses[index]
			if not old.is_visible_from(player.camera.global_position):
				if old==_last_player_corpse:_last_player_corpse=null
				old.clear();old.queue_free()
		_corpses=_corpses.filter(func(value):return not value.is_queued_for_deletion())
	return corpse

func get_player_corpse_center() -> Vector3:
	return _last_player_corpse.get_center() if is_instance_valid(_last_player_corpse) else player.global_position+Vector3.UP*0.35

func clear_corpses() -> void:
	for corpse in _corpses:corpse.clear();corpse.queue_free()
	_corpses.clear()
	_last_player_corpse=null
	for target in _target_nodes:
		if is_instance_valid(target) and target.character!=null and target.character.has_method("set_ragdoll_enabled"):target.character.set_ragdoll_enabled(false)

func stop_audio() -> void:
	if audio!=null:audio.stop()
	for child in get_children():
		if child is AudioStreamPlayer3D:
			child.stop()
			child.stream=null
	if effects!=null:effects.stop_audio()
	if player!=null:player.stop_audio()

func _exit_tree() -> void:
	stop_audio()
	if OS.has_feature("web"):JavaScriptBridge.eval("delete window.BlockfieldFileReceiver; if(window.BlockfieldExports)window.BlockfieldExports.clear();")
	OpenSpadesLocalization.uninstall()
