extends Node3D

@onready var world: VoxelWorld=$VoxelWorld
@onready var session: LocalSession=$LocalSession
@onready var player: BlockfieldPlayer=$Player
@onready var hud: LabHUD=$HUD
var _target_nodes: Array[LabSoldier]=[]
var _player_view: CharacterView
var _notice_time:=0.0
var _objective_nodes: Array[Node3D]=[]
var _grenade_nodes: Dictionary={}
var player_name: String="Player"
var locale: String="ru"
var effects: OpenSpadesEffects

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
	var world_environment:=WorldEnvironment.new()
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
	OpenSpadesLocalization.set_locale(locale)
	hud.setup(self,session,player,world)
	session.player_respawned.connect(func():player.respawn_at(world.get_spawn_position()))
	session.reloaded.connect(func():hud.show_notice("Reload complete"))
	session.grenade_thrown.connect(_grenade_thrown)
	session.grenade_exploded.connect(_grenade_exploded)
	_player_view=CharacterView.new()
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
	if Input.is_action_just_pressed("scoreboard"): hud.toggle_scoreboard()
	if Input.is_action_just_pressed("map"): hud.toggle_map()
	if Input.is_action_just_pressed("pause"): hud.set_menu_visible(not hud.is_menu_open())
	if Input.is_action_just_pressed("chat"):hud.open_chat()

func _setup_input() -> void:
	var actions:={"forward":KEY_W,"back":KEY_S,"left":KEY_A,"right":KEY_D,"jump":KEY_SPACE,"crouch":KEY_CTRL,"sprint":KEY_SHIFT,"sneak":KEY_V,"reload":KEY_R,"tool_spade":KEY_1,"tool_block":KEY_2,"tool_weapon":KEY_3,"tool_grenade":KEY_4,"eyedropper":KEY_E,"view_toggle":KEY_F,"map":KEY_N,"scoreboard":KEY_TAB,"pause":KEY_ESCAPE,"chat":KEY_T,"last_tool":KEY_Q}
	for action in actions:
		if not InputMap.has_action(action):InputMap.add_action(action)
		var event:=InputEventKey.new()
		event.physical_keycode=actions[action]
		InputMap.action_add_event(action,event)
	for entry in [["primary",MOUSE_BUTTON_LEFT],["secondary",MOUSE_BUTTON_RIGHT]]:
		if not InputMap.has_action(entry[0]):InputMap.add_action(entry[0])
		var event:=InputEventMouseButton.new()
		event.button_index=entry[1]
		InputMap.action_add_event(entry[0],event)

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
	if effects!=null:effects.clear()
	for grenade in _grenade_nodes.values():
		if is_instance_valid(grenade):grenade.queue_free()
	_grenade_nodes.clear()
	world.generate_lab()
	session.reset_lab()
	player.respawn_at(world.get_spawn_position())
	_spawn_targets()
	_setup_objectives()
	hud.show_notice("Test grounds reset")

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
		_play_spatial("Weapons/Grenade/DropWater" if water else "Weapons/Grenade/Bounce",point)
		if water:effects.water_hit(point))
	player._play_sound("Weapons/Grenade/Throw")

func _explosion(point: Vector3) -> void:
	var underwater: bool=point.y<world.water_level
	effects.grenade_explosion(point,underwater)
	_play_spatial("Weapons/Grenade/WaterExplode" if underwater else "Weapons/Grenade/Explode1",point)

func _blocks_changed(changes: Array) -> void:
	if effects==null:return
	for change in changes:
		if int(change.before)!=0 and int(change.after)==0 and not bool(change.collapsed):
			effects.block_destroy(Vector3(change.cell)+Vector3.ONE*0.5,VoxelWorld.block_color(int(change.before)))

func _play_spatial(path: String,point: Vector3) -> void:
	var resource:="res://assets/openspades/sounds/%s.ogg"%path
	if not ResourceLoader.exists(resource):return
	var audio:=AudioStreamPlayer3D.new()
	audio.stream=load(resource)
	audio.max_distance=150.0
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
		for grenade in _grenade_nodes.values():
			if is_instance_valid(grenade):grenade.queue_free()
		_grenade_nodes.clear()
		effects.clear()
		session.reset_lab()
		player.respawn_at(world.get_spawn_position())
		_spawn_targets()
		_setup_objectives()
		hud.show_notice("Original Title.vxl loaded")
	else:hud.show_notice("Map load error: %s"%error_string(error))

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
	config.set_value("input","sensitivity",player.sensitivity)
	config.set_value("view","fov",player.base_fov)
	config.set_value("audio","volume",AudioServer.get_bus_volume_db(0))
	config.set_value("profile","name",player_name)
	config.set_value("profile","locale",locale)
	for property in ["hold_aim_down_sight","invert_mouse","mouse_exponent","ads_sensitivity","wheel_tool_direction"]:
		config.set_value("input",property,player.get(property))
	config.save("user://settings.cfg")

func set_locale(value: String) -> void:
	locale=OpenSpadesLocalization.set_locale(value)
	save_settings()

func _load_settings() -> void:
	var config:=ConfigFile.new()
	if config.load("user://settings.cfg")!=OK:return
	player.sensitivity=float(config.get_value("input","sensitivity",0.0025))
	player.base_fov=float(config.get_value("view","fov",90.0))
	AudioServer.set_bus_volume_db(0,float(config.get_value("audio","volume",0.0)))
	player_name=str(config.get_value("profile","name","Player"))
	locale=str(config.get_value("profile","locale","ru"))
	for property in ["hold_aim_down_sight","invert_mouse","mouse_exponent","ads_sensitivity","wheel_tool_direction"]:
		player.set(property,config.get_value("input",property,player.get(property)))

func stop_audio() -> void:
	for child in get_children():
		if child is AudioStreamPlayer3D:
			child.stop()
			child.stream=null
	if effects!=null:effects.stop_audio()
	if player!=null:player.stop_audio()

func _exit_tree() -> void:
	stop_audio()
	OpenSpadesLocalization.uninstall()
