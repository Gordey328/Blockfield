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
var graphics_options: Dictionary = {"lighting":true,"ambient_occlusion":true,"shadows":true,"fog":true,"water":true,"draw_distance":64.0,"particles":2,"blood":true,"shake":2,"fxaa":false,"msaa":0,"bloom":false,"lens":false,"lens_flare":false,"color_correction":true,"saturation":1.0,"exposure":0.0,"tone_map":false,"camera_blur":false,"dof":false,"manual_focus":false,"dof_strength":1.0,"ssao":false,"ssao_strength":1.0,"quality":1,"ambient_energy":0.75}
var positional_audio := true
var flashlight_on := false
var _flashlight: SpotLight3D
var _flashlight_fill: OmniLight3D
var _flashlight_age := 0.0
var _hurt_age := 100.0
var _capture_pending := false
var _upload_pending := false
var _upload_kind := ""
var _upload_callback: JavaScriptObject
var _map_baseline := PackedByteArray()
var _map_baseline_name := ""

func _ready() -> void:
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
	effects=OpenSpadesEffects.new()
	effects.setup(world,player.camera)
	add_child(effects)
	world.blocks_changed.connect(_blocks_changed)
	world.falling_cluster_created.connect(func(cluster: Node3D):_play_spatial("Misc/BlockFall",cluster.global_position))
	player.hit_confirmed.connect(hud.show_hit)
	player.notice.connect(hud.show_notice)
	_load_settings()
	_load_resource_packs()
	if skin_id not in OpenSpadesExtensions.get_skins():skin_id="original"
	player.skin_id=skin_id
	session.player_name=player_name
	_setup_graphics()
	session.player_hurt.connect(func(amount: float,_origin: Vector3,_kind: String):
		_hurt_age=0.0
		if post_effects!=null:post_effects.damage(amount))
	OpenSpadesLocalization.set_locale(locale)
	hud.setup(self,session,player,world)
	session.player_respawned.connect(func():player.respawn_at(world.get_spawn_position()))
	session.reloaded.connect(func():hud.show_notice("Reload complete"))
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
	_player_view.set_team(session.team)
	_player_view.visible=player.camera_mode in [BlockfieldPlayer.CameraMode.THIRD_PERSON,BlockfieldPlayer.CameraMode.DEATH] and session.team<2
	for target_node in _target_nodes:
		target_node.visible=not (player.camera_mode==BlockfieldPlayer.CameraMode.FOLLOW_FIRST_PERSON and player.followed_target_id==target_node.target_id)
	_player_view.set_pose(player.crouching,session.health<=0,player.sprinting)
	_player_view.set_weapon(session.current_weapon,session.current_tool)
	_player_view.animate_motion(Vector2(player.velocity.x,player.velocity.z).length(),Time.get_ticks_msec()/1000.0)
	_player_view.set_aim(player.head.rotation.x)
	var carries_intel:=false
	for flag in session.ctf_flags:
		if int(flag.carrier)==0:carries_intel=true
	_player_view.set_intel_carrier(carries_intel)
	_notice_time+=delta
	_update_objective_views()
	_hurt_age+=delta
	_update_graphics(delta)
	session.player_name=player_name

func _setup_input() -> void:
	var actions:={"forward":KEY_W,"back":KEY_S,"left":KEY_A,"right":KEY_D,"jump":KEY_SPACE,"crouch":KEY_CTRL,"sprint":KEY_SHIFT,"sneak":KEY_V,"reload":KEY_R,"tool_spade":KEY_1,"tool_block":KEY_2,"tool_weapon":KEY_3,"tool_grenade":KEY_4,"eyedropper":KEY_E,"view_toggle":KEY_F,"map":KEY_N,"scoreboard":KEY_TAB,"pause":KEY_ESCAPE,"chat":KEY_T,"last_tool":KEY_Q,"map_scale":KEY_M,"chat_team":KEY_Y,"chat_log":KEY_H,"hide_hud":KEY_F6,"stats":KEY_F7,"screenshot":KEY_0,"sceneshot":KEY_9,"save_map":KEY_8,"flashlight":KEY_L}
	for action in actions:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var event:=InputEventKey.new()
		event.physical_keycode=actions[action]
		InputMap.action_add_event(action,event)
	for entry in [["primary",MOUSE_BUTTON_LEFT],["secondary",MOUSE_BUTTON_RIGHT]]:
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
		OpenSpadesModels.set_tint(intel,OpenSpadesModels.TEAM_COLORS[index])
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
		if kind in ["ctf_base","intel"]:OpenSpadesModels.set_tint(node,OpenSpadesModels.TEAM_COLORS[index])
		if kind=="intel" and index<session.ctf_flags.size():
			var flag: Dictionary=session.ctf_flags[index]
			node.position=flag.position
			node.visible=node.visible and int(flag.carrier)<0
		elif kind=="tc" and index<session.territories.size():
			var owner: int=session.territories[index].owner
			OpenSpadesModels.set_tint(node,OpenSpadesModels.TEAM_COLORS[owner] if owner<2 else Color.WHITE)

func _surface_position(x: float,z: float) -> Vector3:
	var cell:=Vector3i(clampi(floori(x),1,world.dimensions.x-2),world.dimensions.y-1,clampi(floori(z),1,world.dimensions.z-2))
	while cell.y>0 and world.get_block(cell)==0:cell.y-=1
	return Vector3(cell.x+0.5,cell.y+1.0,cell.z+0.5)

func reset_lab() -> void:
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
	var point: Vector3=player.get_aim_origin()+forward*0.5
	var speed: Vector3=player.velocity+forward*32.0
	if bool(data.get("drop",false)):
		point=player.global_position+Vector3.UP
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
	player._play_sound("Weapons/Grenade/Throw")

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
	var resource:="res://assets/openspades/sounds/%s.ogg"%path
	if not ResourceLoader.exists(resource):return
	var audio:=AudioStreamPlayer3D.new()
	audio.stream=OpenSpadesExtensions.sound(resource)
	audio.max_distance=150.0
	audio.panning_strength=1.0 if positional_audio else 0.0
	audio.volume_db=-8
	add_child(audio)
	audio.global_position=point
	audio.finished.connect(audio.queue_free)
	audio.play()

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
	else:hud.show_notice("Map load error: %s"%error_string(error))

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
		if arguments.size()>=3 and str(arguments[2])!="cancelled":hud.show_notice(str(arguments[2]))
		return
	if not JavaScriptBridge.is_js_buffer(arguments[0]):
		_upload_pending=false
		hud.show_notice("Invalid file buffer")
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
		if not bool(result.ok):hud.show_notice(str(result.error));return
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
	_player_view.refresh_resources()
	player.refresh_resources()
	for target in _target_nodes:target.refresh_resources()
	effects.reload_resources()
	if post_effects!=null:post_effects.reload_resources()
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
		hud.show_notice("Map encoding failed")
		return
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(bytes,"blockfield-map.vxl","application/octet-stream")
	else:
		var file:=FileAccess.open("user://blockfield-map.vxl",FileAccess.WRITE)
		if file==null:
			hud.show_notice("Map save failed")
			return
		file.store_buffer(bytes)
	hud.show_notice("VXL map saved")

func save_settings() -> void:
	var config:=ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("input","sensitivity",player.sensitivity)
	config.set_value("view","fov",player.base_fov)
	config.set_value("view","skin",skin_id)
	config.set_value("audio","volume",AudioServer.get_bus_volume_db(0))
	config.set_value("audio","positional",positional_audio)
	config.set_value("profile","name",player_name)
	config.set_value("profile","locale",locale)
	for property in ["hold_aim_down_sight","invert_mouse","mouse_exponent","ads_sensitivity","wheel_tool_direction"]:
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
	player.base_fov=float(config.get_value("view","fov",90.0))
	skin_id=str(config.get_value("view","skin","original"))
	AudioServer.set_bus_volume_db(0,float(config.get_value("audio","volume",0.0)))
	positional_audio=bool(config.get_value("audio","positional",true))
	player_name=str(config.get_value("profile","name","Player"))
	locale=str(config.get_value("profile","locale","ru"))
	for property in ["hold_aim_down_sight","invert_mouse","mouse_exponent","ads_sensitivity","wheel_tool_direction"]:
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
	_apply_graphics()

func get_graphics_options() -> Dictionary:
	return graphics_options.duplicate(true)

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
	if world.has_method("set_draw_distance"):graphics_options.draw_distance=world.set_draw_distance(float(graphics_options.draw_distance))
	world.set_water_enabled(bool(graphics_options.water))
	# Native sunLightDirection=(0,-1,-1); map axes convert this to (0,1,-1).
	$Sun.rotation_degrees=Vector3(-45,180,0)
	$Sun.shadow_enabled=bool(graphics_options.shadows)
	$Sun.directional_shadow_max_distance=float(graphics_options.draw_distance)
	world_environment.environment.ambient_light_energy=clampf(float(graphics_options.ambient_energy),0,1.5)
	world_environment.environment.fog_enabled=bool(graphics_options.fog)
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

func _update_graphics(delta: float) -> void:
	_flashlight_age+=delta
	if _flashlight!=null:
		_flashlight.visible=flashlight_on and session.health>0 and session.team<2
		_flashlight.light_energy=1.5*(1.0-exp(-_flashlight_age*5.0))
		_flashlight_fill.light_energy=_flashlight.light_energy*0.3
	if post_effects!=null:
		var focus:=world.cast_voxel(player.get_aim_origin(),player.get_aim_direction(),128.0)
		var focus_distance:=player.get_aim_origin().distance_to(focus.position) if focus.hit else 128.0
		post_effects.update_state(delta,session.health,_hurt_age,player.sprinting,player.get_aim_down_state(),focus_distance)
		var sun_direction: Vector3=$Sun.global_basis.z
		var sun_occluded: bool=world.cast_voxel(player.camera.global_position,sun_direction,float(graphics_options.draw_distance)).hit
		var flare_sources: Array[Dictionary]=[{"direction":sun_direction,"color":$Sun.light_color,"energy":0.6,"radius":0.03,"visible":not sun_occluded}]
		post_effects.set_flare_sources(flare_sources)

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
	if OS.has_feature("web"):JavaScriptBridge.download_buffer(bytes,filename,"image/png")
	else:
		var file:=FileAccess.open("user://"+filename,FileAccess.WRITE)
		if file!=null:file.store_buffer(bytes)
	_capture_pending=false
	hud.show_notice("Screenshot saved")

func _play_explosion_audio(point: Vector3,underwater: bool) -> void:
	if underwater:
		_play_spatial("Weapons/Grenade/WaterExplode",point)
		_play_spatial("Weapons/Grenade/WaterExplodeFar",point)
		player._play_sound("Weapons/Grenade/WaterExplodeStereo")
	else:
		var variant:=randi_range(1,2)
		_play_spatial("Weapons/Grenade/Explode%d"%variant,point)
		_play_spatial("Weapons/Grenade/ExplodeFar",point)
		player._play_sound("Weapons/Grenade/ExplodeStereo%d"%variant)
		player._play_sound("Weapons/Grenade/ExplodeFarStereo")
		var ground:=world.cast_voxel(point,Vector3.DOWN,8.0)
		_play_spatial("Weapons/Grenade/Debris",ground.position+Vector3.UP*0.2 if ground.hit else point)

func _match_event_audio(event: Dictionary) -> void:
	match str(event.type):
		"intel_pickup":player._play_sound("Feedback/CTF/PickedUp")
		"intel_capture":player._play_sound("Feedback/CTF/YourTeamCaptured" if int(event.team)==session.team else "Feedback/CTF/EnemyCaptured")
		"territory_capture":player._play_sound("Feedback/TC/YourTeamCaptured" if int(event.team)==session.team else "Feedback/TC/EnemyCaptured")
		"round_won":player._play_sound("Feedback/Win" if int(event.team)==session.team else "Feedback/Lose")
		"kill":
			if str(event.get("part",""))=="head":player._play_sound("Feedback/HeadshotFeedback")

func stop_audio() -> void:
	for child in get_children():
		if child is AudioStreamPlayer3D:
			child.stop()
			child.stream=null
	if effects!=null:effects.stop_audio()
	if player!=null:player.stop_audio()

func _exit_tree() -> void:
	stop_audio()
	if OS.has_feature("web"):JavaScriptBridge.eval("delete window.BlockfieldFileReceiver;")
	OpenSpadesLocalization.uninstall()
