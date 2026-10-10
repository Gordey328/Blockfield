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
	player.hit_confirmed.connect(hud.show_hit)
	player.notice.connect(hud.show_notice)
	_load_settings()
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
	_player_view.visible=player.third_person and session.team<2
	_player_view.set_pose(player.crouching,session.health<=0,player.sprinting)
	_player_view.set_weapon(session.current_weapon,session.current_tool)
	_player_view.animate_motion(Vector2(player.velocity.x,player.velocity.z).length(),Time.get_ticks_msec()/1000.0)
	_player_view.set_aim(player.head.rotation.x)
	_notice_time+=delta
	if Input.is_action_just_pressed("scoreboard"): hud.toggle_scoreboard()
	if Input.is_action_just_pressed("map"): hud.toggle_map()
	if Input.is_action_just_pressed("pause"): hud.set_menu_visible(not hud.is_menu_open())
	if Input.is_action_just_pressed("chat"):hud.open_chat()

func _setup_input() -> void:
	var actions:={"forward":KEY_W,"back":KEY_S,"left":KEY_A,"right":KEY_D,"jump":KEY_SPACE,"crouch":KEY_CTRL,"sprint":KEY_SHIFT,"sneak":KEY_V,"reload":KEY_R,"tool_spade":KEY_1,"tool_block":KEY_2,"tool_weapon":KEY_3,"tool_grenade":KEY_4,"eyedropper":KEY_E,"view_toggle":KEY_F,"map":KEY_N,"scoreboard":KEY_TAB,"pause":KEY_ESCAPE,"chat":KEY_T}
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
		var id:int=session.add_target(point,i%2,i>=3)
		session.set_target_state(id,["standing","crouching","dead","walking","sprinting","standing"][i],i%3,[2,0,2,1,2,3][i])
		var soldier:=LabSoldier.new()
		add_child(soldier)
		soldier.setup(session,id,point)
		_target_nodes.append(soldier)

func _setup_objectives() -> void:
	for node in _objective_nodes:node.queue_free()
	_objective_nodes.clear()
	session.configure_ctf(Vector3(20,4,70),Vector3(76,4,22))
	session.configure_tc([Vector3(20,4,40),Vector3(48,4,40),Vector3(76,4,40)])
	for entry in [[Vector3(20,4,70),Color("549cdf")],[Vector3(76,4,22),Color("8cb66f")]]:
		var mesh:=MeshInstance3D.new()
		var box:=BoxMesh.new()
		box.size=Vector3(2.5,0.2,2.5)
		mesh.mesh=box
		mesh.position=entry[0]
		var material:=StandardMaterial3D.new()
		material.albedo_color=entry[1]
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override=material
		add_child(mesh)
		_objective_nodes.append(mesh)

func reset_lab() -> void:
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
	var forward: Vector3=-player.camera.global_basis.z
	var point: Vector3=player.camera.global_position+forward*0.5
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
	player._play_sound("Weapons/Grenade/Throw")

func _explosion(point: Vector3) -> void:
	player._play_sound("Weapons/Grenade/Explode1")
	var particles:=CPUParticles3D.new()
	particles.amount=32
	particles.one_shot=true
	particles.lifetime=0.8
	particles.explosiveness=1.0
	particles.direction=Vector3.UP
	particles.spread=180.0
	particles.initial_velocity_min=3.0
	particles.initial_velocity_max=12.0
	particles.gravity=Vector3(0,-16,0)
	particles.color=Color("d0b088")
	var cube:=BoxMesh.new()
	cube.size=Vector3.ONE*0.1
	particles.mesh=cube
	add_child(particles)
	particles.global_position=point
	particles.emitting=true
	get_tree().create_timer(1.2).timeout.connect(particles.queue_free)

func load_original_map() -> void:
	hud.show_notice("Loading original OpenSpades map…")
	await get_tree().process_frame
	var error:=world.load_vxl("res://assets/openspades/maps/Title.vxl")
	if error==OK:
		player.respawn_at(world.get_spawn_position())
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
	config.save("user://settings.cfg")

func _load_settings() -> void:
	var config:=ConfigFile.new()
	if config.load("user://settings.cfg")!=OK:return
	player.sensitivity=float(config.get_value("input","sensitivity",0.0025))
	player.base_fov=float(config.get_value("view","fov",90.0))
	AudioServer.set_bus_volume_db(0,float(config.get_value("audio","volume",0.0)))
