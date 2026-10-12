extends Node3D
@export var offline_tdm_mode: bool = false
@export var offline_survival_mode: bool = false
const OFFLINE_TDM = preload("res://gameplay/offline_tdm_session.gd")
const OFFLINE_SURVIVAL = preload("res://gameplay/offline_survival_session.gd")
const SURVIVAL_ARENA = preload("res://ai/survival_arena.gd")
const SURVIVAL_LEVELS = preload("res://ai/survival_levels.gd")
var _survival_arena_data: Dictionary = {}
var _warm_resources: Array[Resource] = []
const ZOMBIE_VIEW = preload("res://presentation/zombie_view.gd")
const SURVIVAL_SETTINGS = preload("res://gameplay/survival_settings.gd")
const TDM_ARENA = preload("res://ai/tdm_arena.gd")
const BLOCKFIELD_MAP = preload("res://world/blockfield_map.gd")
const LAUNCH_CATALOG = preload("res://ui/map_catalog.gd")
const LAUNCH_OVERLAY = preload("res://ui/launch_overlay.gd")
var _launch_configuration: Dictionary = {}
var _launch_status: String = "idle"
var _launch_in_progress: bool = false
var _launch_error: String = ""
var _launch_overlay: CanvasLayer
var arsenal_coordinator: ArsenalCoordinator
var _shell_utility: String = ""
var _match_objective_signature := ""
var _impact_colors: Dictionary[Vector3i,int] = {}
var _match_block_edit_ticks: Dictionary[Vector3i,int] = {}
var _match_raise_key := ""
var _match_raise := 1.0

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
var source_audio_gain: float = 1.0:
	set(value):
		if not is_finite(value): return
		source_audio_gain = clampf(value, 0.0, 4.0)
		if is_instance_valid(audio): audio.set("source_gain", source_audio_gain)
var source_audio_efx: bool = true:
	set(value):
		source_audio_efx=value
		if is_instance_valid(audio): audio.set("efx_enabled",value)
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
var _export_transfer_request: int = -1
var _export_transfer_stats: Dictionary = {}
var _map_baseline := PackedByteArray()
var _map_baseline_name := ""
var _map_metadata: Dictionary = {}
var _vxl_request_id: int = 0
var _vxl_notice_caption: String = ""
var _vxl_notice_percent: int = -1
var focus_control := LabFocus.new()
var console_service:=preload("res://ui/lab_console.gd").new()
var _corpses: Array[OpenSpadesCorpse]=[]
var _zombie_views: Dictionary[int, Node3D] = {}
var _survival_supply_views: Array[Node3D] = []
var _spawn_warning_marker: MeshInstance3D
var _spawn_warning_until_tick: int = -1
var _last_player_corpse: OpenSpadesCorpse

func _enter_tree() -> void:
	# Child _ready runs first: avoid generating/meshing a lab that will be
	# discarded immediately by the authored match map in this parent's _ready.
	if offline_tdm_mode:
		(get_node("VoxelWorld") as VoxelWorld).bootstrap_lab = false

func _ready() -> void:
	set_process(false)
	player.set_process(false)
	player.set_physics_process(false)
	hud.set_process(false)
	hud.set_process_input(false)
	if get_tree().has_meta("blockfield_warm_resources"):
		_warm_resources.assign(get_tree().get_meta("blockfield_warm_resources"))
		get_tree().remove_meta("blockfield_warm_resources")
	if get_tree().has_meta("blockfield_launch"):
		var requested: Variant = get_tree().get_meta("blockfield_launch")
		get_tree().remove_meta("blockfield_launch")
		_launch_configuration = requested.duplicate(true) if requested is Dictionary else {}
		_launch_status = "loading"
	var staged: bool = _launch_status == "loading" and offline_survival_mode
	if staged:
		_launch_overlay = LAUNCH_OVERLAY.new()
		add_child(_launch_overlay)
		_launch_overlay.home_requested.connect(open_game_home)
		_launch_overlay.retry_requested.connect(_apply_game_launch)
		_launch_overlay.show_progress("Выживание", "Подготовка снаряжения…", true)
		await get_tree().process_frame
		if not is_inside_tree(): return
	if get_tree().has_meta("blockfield_utility"):
		_shell_utility = str(get_tree().get_meta("blockfield_utility"))
		get_tree().remove_meta("blockfield_utility")
	if offline_tdm_mode:
		var level: Dictionary = SURVIVAL_LEVELS.load_level(str(_launch_configuration.get("map_id", "crossroads"))) if offline_survival_mode else {}
		if offline_survival_mode and not bool(level.get("ok", false)):
			_launch_status = "error"
			_launch_error = "Не удалось подготовить уровень: " + str(level.get("error", ""))
			if _launch_overlay != null: _launch_overlay.show_error(_launch_error, false, true)
			return
		var arena_data: VoxelData = level.data if offline_survival_mode else TDM_ARENA.build()
		var arena: Dictionary = level.arena if offline_survival_mode else TDM_ARENA.metadata()
		if offline_survival_mode:
			_survival_arena_data = arena
			_map_metadata = level.metadata
		var start_feet: Vector3 = arena.owner_spawn if offline_survival_mode else arena.team_spawns[0][0]
		world.set_map_data(arena_data,(str(level.title) + " · Выживание") if offline_survival_mode else "Crossroads · 3×3",true,start_feet)
		# Effects and actor views sample the current rendered camera pose.
		player.process_priority = process_priority-1
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
	audio.set("source_gain",source_audio_gain)
	audio.set("efx_enabled",source_audio_efx)
	# Keep spatial listening on the reference camera when HDR renders through
	# a shared-world clone in a different viewport.
	var listener:=AudioListener3D.new()
	player.camera.add_child(listener)
	listener.make_current()
	effects=OpenSpadesEffects.new()
	effects.setup(world,player.camera,staged)
	effects.audio_service=audio
	add_child(effects)
	if staged:
		await effects.prewarm_async()
		if not is_inside_tree(): return
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
	if offline_tdm_mode:
		var configured: Dictionary
		if offline_survival_mode:
			configured = (session as OFFLINE_SURVIVAL).configure_survival(world.data, _survival_arena_data, _launch_configuration.get("survival", SURVIVAL_SETTINGS.defaults()), player_name, false, int(_launch_configuration.get("weapon", 0)))
		else:
			configured = (session as OFFLINE_TDM).configure_match(world.data,TDM_ARENA.metadata(),player_name)
		if not configured.get("ok",false):
			push_error("Offline TDM configuration failed: %s" % configured.get("error","unknown"))
			return
		player._adopt_match_owner((session as OFFLINE_TDM).get_owner_state())
	_load_resource_packs()
	if skin_id not in OpenSpadesExtensions.get_skins():skin_id="original"
	player.skin_id=skin_id
	session.player_name=player_name
	_setup_graphics()
	if staged:
		await get_tree().process_frame
		if not is_inside_tree(): return
	session.player_hurt.connect(func(amount: float,_origin: Vector3,_kind: String):
		_hurt_age=0.0
		if audio!=null:audio.flesh_hit(player.global_position,true)
		if post_effects!=null:post_effects.damage(amount))
	OpenSpadesLocalization.set_locale(locale)
	console_service.setup(self)
	hud.setup(self,session,player,world)
	if staged:
		player._connect_simulation()
		player._update_view(0.0)
		await get_tree().process_frame
		if not is_inside_tree(): return
	hud.alert_sound_requested.connect(func():player._play_sound("Feedback/Alert"))
	hud.chat_sound_requested.connect(func():
		if chat_beep:player._play_sound("Feedback/Chat"))
	hud.map_sound_requested.connect(func(path: String):player._play_sound(path))
	if OS.has_feature("web"):
		_ensure_web_exports()
		_pointer_callback=JavaScriptBridge.create_callback(_pointer_capture_result)
		JavaScriptBridge.get_interface("BlockfieldExports").setPointerCallback(_pointer_callback)
	hud.ui_sound_requested.connect(func(kind: String):player._play_sound("Feedback/Limbo/"+kind.capitalize()))
	session.player_respawned.connect(func():
		if not offline_tdm_mode: player.respawn_at(world.get_spawn_position())
		else: clear_corpses())
	session.player_died.connect(_spawn_player_corpse)
	session.reloaded.connect(func():hud.show_notice("Reload complete"))
	session.restocked.connect(func():player._play_sound("Weapons/RestockLocal",1.0,OpenSpadesAudio.LOCAL_ORIGIN))
	session.grenade_thrown.connect(_grenade_thrown)
	session.grenade_exploded.connect(_grenade_exploded)
	session.match_event.connect(_match_event_audio)
	_player_view=OpenSpadesExtensions.create_third_person_skin(skin_id,{"player":player,"session":session})
	player.add_child(_player_view)
	if staged:
		await get_tree().process_frame
		if not is_inside_tree(): return
	if not offline_tdm_mode:
		_spawn_targets()
		_setup_objectives()
	elif offline_tdm_mode:
		_update_shared_actor_views()
		if offline_survival_mode: _create_survival_supply_views()
	hud.set_menu_visible(true)
	if _launch_status == "loading":
		if _launch_overlay == null:
			_launch_overlay = LAUNCH_OVERLAY.new()
			add_child(_launch_overlay)
			_launch_overlay.home_requested.connect(open_game_home)
			_launch_overlay.retry_requested.connect(_apply_game_launch)
		_apply_game_launch.call_deferred()
	elif _shell_utility == "settings":
		hud.open_settings_menu()
	player.set_process(true)
	player.set_physics_process(true)
	hud.set_process(true)
	hud.set_process_input(true)
	set_process(true)
	arsenal_coordinator = ArsenalCoordinator.new()
	arsenal_coordinator.configure(self)
	add_child(arsenal_coordinator)

func get_launch_state() -> Dictionary:
	return {"status": _launch_status, "configuration": _launch_configuration.duplicate(true), "error": _launch_error}

func _apply_game_launch() -> void:
	# This request is consumed once by Main. UI never grants a live inventory.
	if not is_inside_tree(): return
	if _launch_status == "ready" or _launch_in_progress: return
	_launch_in_progress = true
	_launch_status = "loading"
	_launch_error = ""
	hud.set_menu_visible(true)
	var russian: bool = locale == "ru"
	var checked: Dictionary = LAUNCH_CATALOG.validate(_launch_configuration)
	if not checked.ok:
		_fail_game_launch("Выберите доступную карту и оружие." if russian else "Choose an available map and weapon.", false)
		return
	var configuration: Dictionary = checked.configuration
	var expected_mode: String = "survival" if offline_survival_mode else ("tdm" if offline_tdm_mode else "training")
	if str(configuration.mode) != expected_mode:
		_fail_game_launch("Режим запуска не соответствует матчу." if russian else "The launch mode does not match this session.", false)
		return
	_launch_configuration = configuration.duplicate(true)
	var entry: Dictionary = LAUNCH_CATALOG.get_entry(configuration.map_id)
	var map_name: String = str(entry.name_ru if russian else entry.name_en)
	_launch_overlay.show_progress(map_name, "Подготовка карты…" if russian else "Preparing map…", russian)
	# Allow the real loading state to paint before foreground map work starts.
	await get_tree().process_frame
	if not is_inside_tree(): return
	if not offline_tdm_mode and configuration.map_id != "lab":
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(str(entry.resource))
		if bytes.is_empty():
			_fail_game_launch("Не удалось прочитать карту." if russian else "The map could not be read.", true)
			return
		var request: int = _begin_vxl_request("Подготовка карты…" if russian else "Preparing map…")
		var error: Error = await _load_map_bytes(bytes, str(entry.resource).get_file(), request)
		if not _vxl_request_current(request): return
		_vxl_notice_caption = ""
		if error != OK:
			_fail_game_launch(("Не удалось загрузить карту: " if russian else "Map loading failed: ") + error_string(error), true)
			return
		_map_baseline = bytes
		_map_baseline_name = str(entry.resource).get_file()
		_finish_map_load(OK)
	if offline_tdm_mode:
		# Do not start the combat clock/input while initial chunk publication is
		# still competing with the first gameplay frames. World keeps its normal
		# bounded slices, and the loading overlay remains responsive/cancellable.
		world.get_topdown_image_progressive()
		var deadline: int = Time.get_ticks_msec() + 30000
		while true:
			var preparation: Dictionary = world.get_visual_preparation_stats()
			if bool(preparation.ready): break
			if Time.get_ticks_msec() >= deadline:
				_fail_game_launch("Подготовка карты заняла слишком много времени." if russian else "Map preparation took too long.", true)
				return
			await get_tree().process_frame
			if not is_inside_tree(): return
		# Present completed terrain once before admitting live input.
		await get_tree().process_frame
		if not is_inside_tree(): return
	if not offline_survival_mode: session.select_weapon(int(configuration.weapon))
	var rush_launch: bool = offline_survival_mode and str(configuration.get("survival", {}).get("run_style", "classic")) == "rush"
	if not rush_launch: LAUNCH_CATALOG.save_selection(configuration)
	_launch_status = "ready"
	_launch_in_progress = false
	_launch_overlay.queue_free()
	_launch_overlay = null
	hud.set_menu_visible(false)

func _fail_game_launch(message: String, can_retry: bool) -> void:
	_launch_status = "error"
	_launch_in_progress = false
	_launch_error = message
	hud.set_menu_visible(true)
	_launch_overlay.show_error(message, can_retry, locale == "ru")

func open_game_home() -> void:
	player.controls_enabled = false
	hud.set_menu_visible(true)
	_cancel_vxl_request()
	LabInputBindings.release_actions()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/entry.tscn")

func _process(delta: float) -> void:
	_update_vxl_progress()
	if not offline_tdm_mode: session.update(delta)
	if offline_tdm_mode: _update_shared_actor_views()
	if offline_survival_mode and is_instance_valid(_spawn_warning_marker):
		_spawn_warning_marker.visible = (session as OFFLINE_TDM).simulation.tick < _spawn_warning_until_tick
	audio.positional=positional_audio
	audio.environmental=environmental_audio
	# Static death models need no per-frame solver or terrain queries.
	# Original skins publish the final pose once; extension skins retain setters.
	var batch_pose: bool = _player_view.has_method("begin_pose_update") and _player_view.has_method("end_pose_update")
	if batch_pose: _player_view.begin_pose_update()
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
	var carries_intel:=session.is_local_intel_carrier()
	_player_view.set_intel_carrier(carries_intel,session.get_team_info(1-session.team if session.team<2 else 1).color)
	if batch_pose: _player_view.end_pose_update()
	_notice_time+=delta
	_update_objective_views()
	_hurt_age+=delta
	_update_graphics(delta)
	if not offline_tdm_mode: session.player_name=player_name

func _setup_input() -> void:
	var actions:={"forward":KEY_W,"back":KEY_S,"left":KEY_A,"right":KEY_D,"jump":KEY_SPACE,"crouch":KEY_CTRL,"sprint":KEY_SHIFT,"sneak":KEY_V,"reload":KEY_R,"tool_spade":KEY_1,"tool_block":KEY_2,"tool_weapon":KEY_3,"tool_grenade":KEY_4,"eyedropper":KEY_E,"view_toggle":KEY_F,"map":KEY_N,"scoreboard":KEY_TAB,"pause":KEY_ESCAPE,"chat":KEY_T,"last_tool":KEY_Q,"map_scale":KEY_M,"chat_team":KEY_Y,"chat_log":KEY_H,"hide_hud":KEY_F6,"stats":KEY_F7,"screenshot":KEY_0,"sceneshot":KEY_9,"save_map":KEY_8,"flashlight":KEY_L}
	actions.merge({"palette_left":KEY_LEFT,"palette_right":KEY_RIGHT,"palette_up":KEY_UP,"palette_down":KEY_DOWN})
	actions.merge({"arsenal":KEY_B,"arsenal_bomb":KEY_G,"arsenal_strat_one":KEY_Z,"arsenal_strat_two":KEY_C})
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
	if offline_tdm_mode: return
	for target in _target_nodes:
		session.remove_target(target.target_id)
		target.queue_free()
	_target_nodes.clear()
	session.targets.clear()
	# Imported maps have their own playable layout. Add lab soldiers explicitly
	# instead of placing the test-ground roster inside arbitrary buildings.
	if not _map_metadata.is_empty(): return
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
		if kind=="ctf_base" and index<session.ctf_bases.size():node.position=session.ctf_bases[index]
		if kind=="intel" and index<session.ctf_flags.size():
			var flag: Dictionary=session.ctf_flags[index]
			node.position=flag.position
			node.visible=node.visible and int(flag.carrier)<0
		elif kind=="tc" and index<session.territories.size():
			node.position=session.territories[index].position
			var owner: int=session.territories[index].owner
			OpenSpadesModels.set_tint(node,session.get_team_info(owner).color if owner<2 else Color.WHITE)

func _surface_position(x: float,z: float) -> Vector3:
	var cell:=Vector3i(clampi(floori(x),1,world.dimensions.x-2),world.dimensions.y-1,clampi(floori(z),1,world.dimensions.z-2))
	while cell.y>0 and world.get_block(cell)==0:cell.y-=1
	return Vector3(cell.x+0.5,cell.y+1.0,cell.z+0.5)

func reset_lab() -> void:
	if offline_tdm_mode:
		restart_offline_tdm()
		return
	_cancel_vxl_request()
	clear_corpses()
	_map_baseline=PackedByteArray()
	_map_baseline_name=""
	_map_metadata.clear()
	world.set_water_enabled(_map_water_enabled())
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
	if offline_tdm_mode:
		restart_offline_tdm()
		return
	if _map_baseline.is_empty():
		reset_lab()
		return
	var request := _begin_vxl_request("Восстановление карты…" if locale == "ru" else "Restoring map…")
	var error: Error = await _load_map_bytes(_map_baseline,_map_baseline_name,request)
	if not _vxl_request_current(request): return
	_vxl_notice_caption = ""
	_finish_map_load(error)
	if error == OK: hud.show_notice("Map and match reset")

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
	if offline_tdm_mode: return # Shared projectiles are authority visuals.
	var forward: Vector3=player.get_aim_direction()
	var point: Vector3=player.get_aim_origin()+forward*0.1
	var speed: Vector3=player.velocity+forward*32.0
	if bool(data.get("drop",false)):
		speed=player.velocity
	spawn_grenade(point,speed,float(data.fuse),int(data.id))
	session.set_grenade_position(int(data.id),point)

func _grenade_exploded(data: Dictionary) -> void:
	if offline_tdm_mode:
		_explosion(data.position)
		return
	var grenade: LabGrenade=_grenade_nodes.get(int(data.id))
	if is_instance_valid(grenade):grenade.detonate()
	_grenade_nodes.erase(int(data.id))

func spawn_grenade(point: Vector3, speed: Vector3, fuse: float, identifier: int=-1) -> void:
	if offline_tdm_mode: return
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
	var request := _begin_vxl_request("Загрузка карты…" if locale == "ru" else "Loading map…")
	var bytes := FileAccess.get_file_as_bytes("res://assets/openspades/maps/Title.vxl")
	var budget := _vxl_work_budget()
	var error: Error = await world.load_vxl_bytes_incremental(bytes,"Title.vxl",budget.x,budget.y)
	if not _vxl_request_current(request): return
	_vxl_notice_caption = ""
	if error==OK:
		_map_baseline=bytes
		_map_baseline_name="Title.vxl"
		_map_metadata.clear()
		world.set_water_enabled(_map_water_enabled())
	_finish_map_load(error)

func _load_map_bytes(bytes: PackedByteArray, title: String, request: int) -> Error:
	if bytes.slice(0,4).get_string_from_ascii() != BLOCKFIELD_MAP.MAGIC and not title.to_lower().ends_with(".bfmap"):
		var budget: Vector2i = _vxl_work_budget()
		var error: Error = await world.load_vxl_bytes_incremental(bytes,title,budget.x,budget.y)
		if error == OK:
			_map_metadata.clear()
			world.set_water_enabled(_map_water_enabled())
		return error
	# Publish the loading notice before the bounded native decode. Adoption is
	# atomic and a reset or newer request can cancel this foreground operation.
	await get_tree().process_frame
	if not _vxl_request_current(request): return ERR_SKIP
	var decoded: Dictionary = BLOCKFIELD_MAP.load_bytes(bytes,world.data.epoch+1)
	if decoded.error != OK: return decoded.error
	var metadata: Dictionary = decoded.metadata
	var spawn_values: Array = metadata.spawn
	var spawn: Vector3 = Vector3(float(spawn_values[0]),float(spawn_values[1]),float(spawn_values[2]))
	var error: Error = world.set_map_data(decoded.data,str(metadata.title),true,spawn)
	if error == OK:
		_map_metadata = metadata
		world.set_water_enabled(_map_water_enabled())
	return error

func _map_water_enabled() -> bool:
	return bool(graphics_options.water) and _map_metadata.get("water_enabled",true) != false

func get_local_map_paths() -> Array[String]:
	var paths: Array[String] = []
	var names: Dictionary = {}
	for directory: String in ["res://assets/maps","res://assets/local_maps"]:
		var folder: DirAccess = DirAccess.open(directory)
		if folder == null: continue
		for filename: String in folder.get_files():
			var key: String = filename.to_lower()
			if key.ends_with(".bfmap") and not names.has(key):
				names[key] = true
				paths.append(directory+"/"+filename)
	paths.sort()
	return paths

func load_local_map(path: String) -> void:
	if offline_tdm_mode or _upload_pending or not get_local_map_paths().has(path): return
	_upload_kind = "map"
	await _apply_upload(FileAccess.get_file_as_bytes(path),path.get_file())

func _finish_map_load(error: Error) -> void:
	if error == ERR_SKIP: return
	if error==OK:
		clear_corpses()
		for grenade in _grenade_nodes.values():
			if is_instance_valid(grenade):grenade.queue_free()
		_grenade_nodes.clear()
		effects.clear()
		flashlight_on=false
		session.reset_lab()
		player.respawn_at(world.get_spawn_position())
		var yaw_value: Variant = _map_metadata.get("yaw_radians")
		if typeof(yaw_value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(yaw_value)):
			player.rotation.y = float(yaw_value)
			player.head.rotation.x = 0.0
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
		var extension:=".zip" if kind=="pack" else ".vxl,.bfmap"
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
		dialog.filters=PackedStringArray(["*.zip ; Blockfield resource pack"] if kind=="pack" else ["*.vxl ; VXL voxel map","*.bfmap ; Blockfield voxel map"])
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
	if offline_tdm_mode and _upload_kind == "map": return
	if _upload_kind=="map":
		var request := _begin_vxl_request("Загрузка карты…" if locale == "ru" else "Loading map…")
		var error: Error = await _load_map_bytes(bytes,filename,request)
		if not _vxl_request_current(request): return
		_vxl_notice_caption = ""
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
	audio.reload_resources()
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
	var request := _begin_vxl_request("Сохранение карты…" if locale == "ru" else "Saving map…")
	var bytes: PackedByteArray
	var filename: String = "blockfield-map.vxl"
	if _map_metadata.is_empty():
		var budget: Vector2i = _vxl_work_budget()
		bytes = await world.encode_vxl_incremental(budget.x,budget.y)
	else:
		await get_tree().process_frame
		if not _vxl_request_current(request): return
		bytes = BLOCKFIELD_MAP.encode(world.data,_native_save_metadata())
		filename = "blockfield-map.bfmap"
	if not _vxl_request_current(request): return
	_vxl_notice_caption = ""
	if bytes.is_empty():
		if filename.ends_with(".vxl") and int(world.get_vxl_job_stats().get("error",OK)) == ERR_SKIP: return
		hud.show_alert("Map encoding failed","error")
		return
	if OS.has_feature("web"):
		if not await _show_web_export_incremental(bytes,filename,"application/octet-stream",request): return
	else:
		var file:=FileAccess.open("user://"+filename,FileAccess.WRITE)
		if file==null:
			hud.show_alert("Map save failed","error")
			return
		file.store_buffer(bytes)
	hud.show_notice("Map ready: "+filename if OS.has_feature("web") else "Map saved: "+filename)

func _native_save_metadata() -> Dictionary:
	var document: Dictionary = _map_metadata.duplicate(true)
	var candidates: Array = [document.get("spawn"),[player.global_position.x,player.global_position.y,player.global_position.z]]
	var teams: Variant = document.get("team_spawns")
	if teams is Dictionary:
		for roster: Variant in teams.values():
			if roster is Array: candidates.append_array(roster.slice(0,64))
			if candidates.size() >= 130: break
	for values: Variant in candidates:
		if not values is Array or values.size() != 3: continue
		var valid_numbers: bool = true
		for value: Variant in values:
			if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)): valid_numbers = false
		if not valid_numbers: continue
		var feet: Vector3 = Vector3(float(values[0]),float(values[1]),float(values[2]))
		if BLOCKFIELD_MAP.is_valid_spawn(world.data,feet):
			document.spawn = values.duplicate()
			break
	return document

func _begin_vxl_request(caption: String) -> int:
	_cancel_vxl_request()
	_vxl_notice_caption = caption
	hud.show_notice(caption)
	return _vxl_request_id

func _vxl_work_budget() -> Vector2i:
	# Menus can spend more of a frame on foreground loading; live play keeps
	# the narrow default budget. Both paths still yield after a bounded batch.
	return Vector2i(4096,8000) if hud.is_menu_open() else Vector2i(1024,2000)

func _cancel_vxl_request() -> void:
	_vxl_request_id += 1
	_vxl_notice_caption = ""
	_vxl_notice_percent = -1
	if is_instance_valid(world): world.cancel_vxl_jobs()
	if _export_transfer_request >= 0:
		_export_transfer_request = -1
		_export_pending = false
		_export_transfer_stats["active"] = false
		_export_transfer_stats["cancelled"] = true
		if OS.has_feature("web"): JavaScriptBridge.get_interface("BlockfieldExports").abort()
		if is_inside_tree(): hud.set_menu_visible(_export_menu_was_open)

func _vxl_request_current(request: int) -> bool:
	return is_inside_tree() and request == _vxl_request_id

func _update_vxl_progress() -> void:
	if _vxl_notice_caption.is_empty() or not is_instance_valid(world): return
	var stats: Dictionary = world.get_vxl_job_stats()
	var percent := clampi(int(float(stats.get("progress",0.0))*100.0),0,100)
	if percent == _vxl_notice_percent: return
	_vxl_notice_percent = percent
	hud.show_notice("%s %d%%" % [_vxl_notice_caption,percent])
	if _launch_status == "loading" and is_instance_valid(_launch_overlay):
		var entry: Dictionary = LAUNCH_CATALOG.get_entry(str(_launch_configuration.get("map_id", "")))
		if not entry.is_empty():
			_launch_overlay.show_progress(str(entry.name_ru if locale == "ru" else entry.name_en), "%s %d%%" % [_vxl_notice_caption, percent], locale == "ru")

func _show_web_export(bytes: PackedByteArray,filename: String,mime: String) -> bool:
	var exports := _begin_web_export(filename,mime)
	if exports == null:return false
	# Small PNG/JSON exports retain their synchronous path.
	for offset in range(0,bytes.size(),49152):
		exports.append(Marshalls.raw_to_base64(bytes.slice(offset,mini(bytes.size(),offset+49152))))
	exports.finish(locale)
	return true

func _begin_web_export(filename: String,mime: String) -> JavaScriptObject:
	if _export_pending:
		hud.show_notice("Дождитесь завершения текущего экспорта" if locale == "ru" else "Wait for the current export to finish")
		return null
	_export_pending=true
	_export_menu_was_open=hud.is_menu_open()
	hud.set_menu_visible(true)
	if _export_callback==null:
		_ensure_web_exports()
		_export_callback=JavaScriptBridge.create_callback(_web_export_closed)
	var exports:=JavaScriptBridge.get_interface("BlockfieldExports")
	exports.begin(filename,mime,_export_callback)
	return exports

func _show_web_export_incremental(bytes: PackedByteArray,filename: String,mime: String,request: int) -> bool:
	if not _vxl_request_current(request):return false
	var exports := _begin_web_export(filename,mime)
	if exports == null:return false
	_export_transfer_request = request
	_export_transfer_stats = {"active":true,"cancelled":false,"bytes":bytes.size(),"staged_bytes":0,"batches":0,"max_batch_usec":0}
	var tree: SceneTree = get_tree()
	var offset: int = 0
	var caption := "Подготовка файла…" if locale == "ru" else "Preparing download…"
	while offset < bytes.size():
		if not _vxl_request_current(request):return false
		var started: int = Time.get_ticks_usec()
		var chunks: int = 0
		while offset < bytes.size() and chunks < 2:
			var end: int = mini(bytes.size(),offset+16384)
			exports.append(Marshalls.raw_to_base64(bytes.slice(offset,end)))
			offset = end
			chunks += 1
			if Time.get_ticks_usec()-started >= 2000:break
		_export_transfer_stats["staged_bytes"] = offset
		_export_transfer_stats["batches"] += 1
		_export_transfer_stats["max_batch_usec"] = maxi(int(_export_transfer_stats.max_batch_usec),Time.get_ticks_usec()-started)
		hud.show_notice("%s %d%%" % [caption,int(float(offset)/bytes.size()*100)])
		if offset < bytes.size():await tree.process_frame
	if not _vxl_request_current(request):return false
	_export_transfer_request = -1
	_export_transfer_stats["active"] = false
	var finish_started: int = Time.get_ticks_usec()
	exports.finish(locale)
	_export_transfer_stats["finish_usec"] = Time.get_ticks_usec()-finish_started
	return true

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
	if hud.uses_mobile_controls():return
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
	config.set_value("input","touch_sensitivity",player.touch_sensitivity)
	config.set_value("input","touch_ads_sensitivity",player.touch_ads_sensitivity)
	config.set_value("input","invert_touch",player.invert_touch)
	config.set_value("input","touch_aim_assist",player.touch_aim_assist)
	config.set_value("view","fov",player.base_fov)
	config.set_value("view","skin",skin_id)
	config.set_value("audio","volume",AudioServer.get_bus_volume_db(0))
	config.set_value("audio","source_gain",source_audio_gain)
	config.set_value("audio","efx",source_audio_efx)
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
	player.touch_sensitivity=float(config.get_value("input","touch_sensitivity",1.0))
	player.touch_ads_sensitivity=float(config.get_value("input","touch_ads_sensitivity",1.0))
	player.invert_touch=bool(config.get_value("input","invert_touch",false))
	player.touch_aim_assist=bool(config.get_value("input","touch_aim_assist",true))
	player.base_fov=float(config.get_value("view","fov",68.0))
	skin_id=str(config.get_value("view","skin","original"))
	AudioServer.set_bus_volume_db(0,float(config.get_value("audio","volume",0.0)))
	source_audio_gain=clampf(float(config.get_value("audio","source_gain",1.0)),0,4)
	source_audio_efx=bool(config.get_value("audio","efx",true))
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
	var post_path: String = "res://presentation/openspades_post_effects.gd"
	if ResourceLoader.exists(post_path):
		post_effects=(load(post_path) as Script).new()
		add_child(post_effects)
		post_effects.setup(player.camera,world_environment)
	hdr_scene=preload("res://presentation/hdr_scene_viewport.gd").new()
	add_child(hdr_scene)
	hdr_scene.available = hdr_scene.supports_float_target()
	if bool(graphics_options.hdr): hdr_scene.setup(player.camera,get_viewport())
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
	world.set_water_enabled(_map_water_enabled())
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
		if not bool(graphics_options.lens_flare):
			var empty_flare_sources: Array[Dictionary] = []
			post_effects.set_flare_sources(empty_flare_sources)
	if hdr_scene!=null:
		if hdr_scene.exposure == null and bool(graphics_options.hdr):
			hdr_scene.setup(player.camera,get_viewport())
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
		if bool(graphics_options.lens_flare):
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
	if OS.has_feature("web"):
		if not _show_web_export(bytes,filename,"image/png"):
			_capture_pending=false
			return
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
	if OS.has_feature("web"):
		if not _show_web_export(bytes,filename,"application/json"):return
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
		"tdm_finished":
			if int(event.get("winner",-1))>=0: player._play_sound("Feedback/Win" if int(event.winner)==session.team else "Feedback/Lose")
		"kill":
			_spawn_target_corpse(event)

func _spawn_target_corpse(event: Dictionary) -> void:
	if offline_survival_mode: return # Zombie slots own their bounded prone death pose.
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
	_last_player_corpse=spawn_corpse({"player_id":session.local_player_id(),"feet_position":player.global_position,"yaw":player.rotation.y,"crouch":player.crouching,"team":session.team,"color":session.get_team_info(session.team).color,"velocity":player.velocity,"impulse":Vector3.UP*randf_range(4,8) if cause=="grenade" else Vector3.ZERO})

func spawn_corpse(state: Dictionary) -> OpenSpadesCorpse:
	var corpse:=OpenSpadesCorpse.new()
	add_child(corpse)
	corpse.setup_static(world,state)
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
	_warm_resources.clear()
	_cancel_vxl_request()
	stop_audio()
	if OS.has_feature("web"):JavaScriptBridge.eval("delete window.BlockfieldFileReceiver; if(window.BlockfieldExports)window.BlockfieldExports.clear();")
	OpenSpadesLocalization.uninstall()

func open_offline_tdm() -> void:
	LabInputBindings.release_actions()
	get_tree().change_scene_to_file("res://scenes/offline_tdm.tscn")

func open_offline_lab() -> void:
	LabInputBindings.release_actions()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func restart_offline_tdm() -> void:
	if not offline_tdm_mode: return
	if _launch_in_progress: return
	var result: Dictionary = (session as OFFLINE_TDM).restart_match()
	if not result.get("ok",false):
		hud.show_notice(str(result.get("error","Match restart failed")))
		return
	_clear_match_views()
	world.set_map_data(result.data,world.map_name,true,(session as OFFLINE_TDM).get_owner_state().feet())
	if offline_survival_mode:
		_create_survival_supply_views()
	_update_shared_actor_views()
	hud.set_menu_visible(true)
	if offline_survival_mode and bool((session as OFFLINE_SURVIVAL).get_rush_state().get("enabled", false)):
		# A one-click replay waits for the restored terrain before opening controls.
		_launch_status = "idle"
		_launch_overlay = LAUNCH_OVERLAY.new()
		add_child(_launch_overlay)
		_launch_overlay.home_requested.connect(open_game_home)
		_launch_overlay.retry_requested.connect(_apply_game_launch)
		_apply_game_launch.call_deferred()

func present_offline_tick(transactions: Array) -> void:
	# Both authority and renderer share Data. Present each committed edit once;
	# applying it again would corrupt the transaction sequence and collapse.
	var refresh_requested: bool = false
	for transaction: Dictionary in transactions:
		if transaction.get("refresh_required",false):
			refresh_requested = true
			continue
		for change: Dictionary in transaction.changes:
			if change.before != 0: _impact_colors[change.cell] = change.before
			if change.after != 0: _match_block_edit_ticks[change.cell] = int(transaction.tick)
			else: _match_block_edit_ticks.erase(change.cell)
		world._present_transaction(transaction)
	while _impact_colors.size() > 4096: _impact_colors.erase(_impact_colors.keys()[0])
	for event: Dictionary in (session as OFFLINE_TDM).drain_presentation_events():
		if str(event.get("type","")) == "events_overflow":
			refresh_requested = true
			continue
		if str(event.get("type","")) in ["tdm_finished", "survival_finished"]:
			hud.set_menu_visible(true)
			continue
		if str(event.get("type", "")) == "survival_wave":
			hud.show_notice(("Волна %d" if locale == "ru" else "Wave %d") % int(event.get("wave", 1)))
			player._play_sound("Feedback/Alert", 0.5)
			continue
		if str(event.get("type", "")) in ["survival_warning", "zombie_spawn_warning"]:
			hud.show_notice("Орда приближается" if locale == "ru" else "Horde approaching")
			player._play_sound("Feedback/Alert", 0.35)
			if event.get("position") is Vector3:
				_show_zombie_spawn_warning(event.position, int(event.get("tick", 0)), float(event.get("seconds", 1.0)))
			continue
		_match_present_event(event)
	# Older effects cannot re-darken a replacement whose receipt was dropped.
	# Restore the canonical terrain/damage mask after all queued effects.
	if refresh_requested: _refresh_match_terrain()

func _clear_match_views() -> void:
	clear_corpses()
	for node: Node3D in _zombie_views.values(): node.queue_free()
	_zombie_views.clear()
	for node: Node3D in _survival_supply_views: node.queue_free()
	_survival_supply_views.clear()
	if is_instance_valid(_spawn_warning_marker): _spawn_warning_marker.queue_free()
	_spawn_warning_marker = null
	_spawn_warning_until_tick = -1
	for target in _target_nodes: target.queue_free()
	_target_nodes.clear()
	for node in _objective_nodes: node.queue_free()
	_objective_nodes.clear()
	for node: Node3D in _grenade_nodes.values(): node.queue_free()
	_grenade_nodes.clear()
	_impact_colors.clear()
	_match_block_edit_ticks.clear()
	if world != null: world.clear_block_damage()
	_match_raise_key = ""
	_match_raise = 1.0
	_match_objective_signature = ""
	if effects != null: effects.clear()
	if hud != null: hud.clear_match_feedback()

func _match_mark_block_damage(event: Dictionary) -> void:
	if event.get("dig",false): return
	var cell: Vector3i = event.cell
	var hit_tick: int = event.tick
	if cell.y <= 1 or world.get_block(cell) == 0 \
			or hit_tick <= _match_block_edit_ticks.get(cell,-1): return
	world.set_block_damaged(cell,true)

func _update_shared_actor_views() -> void:
	var owner: SharedPlayerState = (session as OFFLINE_TDM).get_owner_state()
	if owner != null and owner.is_alive():
		var key := "%d:%d:%d:%d" % [owner.match_epoch,owner.spawn_generation,owner.displayed_tool,owner.displayed_weapon]
		if key != _match_raise_key:
			_match_raise_key = key
			_match_raise = owner.tool_raise
		elif _match_raise < 1.0 and owner.tool_raise >= 1.0:
			var tool_name: String = ["Spade","Block",["Rifle","SMG","Shotgun"][owner.displayed_weapon],"Grenade"][owner.displayed_tool]
			player._play_sound("Weapons/"+tool_name+"/RaiseLocal",1.0,OpenSpadesAudio.LOCAL_ORIGIN)
		_match_raise = owner.tool_raise
	var present: Dictionary[int,bool] = {}
	for target: Dictionary in session.targets:
		if int(target.team) >= 2: continue
		if offline_survival_mode:
			var zombie: ZOMBIE_VIEW = _zombie_views.get(int(target.id)) as ZOMBIE_VIEW
			if zombie == null:
				zombie = ZOMBIE_VIEW.new()
				add_child(zombie)
				zombie.setup(target)
				_zombie_views[int(target.id)] = zombie
			zombie.set_paused((session as OFFLINE_TDM).paused)
			zombie.update_state(target)
			continue
		present[target.id] = true
		var exists := false
		for node in _target_nodes:
			if node.target_id == target.id: exists = true; break
		if not exists:
			var node := LabSoldier.new()
			node.skin_id = skin_id
			add_child(node)
			node.setup(session,target.id,target.position)
			_target_nodes.append(node)
	for index in range(_target_nodes.size()-1,-1,-1):
		if not present.has(_target_nodes[index].target_id):
			_target_nodes[index].queue_free()
			_target_nodes.remove_at(index)

	var signature := "%s:%d:%d" % [session.mode,session.ctf_bases.size(),session.territories.size()]
	if signature != _match_objective_signature and not session.ctf_bases.is_empty():
		_match_objective_signature = signature
		for node in _objective_nodes: node.queue_free()
		_objective_nodes.clear()
		if session.mode == "ctf":
			for index in session.ctf_bases.size(): _match_objective("ctf_base",index,session.ctf_bases[index])
			for index in session.ctf_flags.size(): _match_objective("intel",index,session.ctf_flags[index].position)
		elif session.mode == "tc":
			for index in session.territories.size(): _match_objective("tc",index,session.territories[index].position)
	var projectiles: Dictionary[int,bool] = {}
	for grenade: Dictionary in session.live_grenades:
		projectiles[grenade.id] = true
		if not _grenade_nodes.has(grenade.id):
			var node := OpenSpadesModels.create("Weapons/Grenade/Grenade")
			node.scale = Vector3.ONE*.03
			add_child(node)
			_grenade_nodes[grenade.id] = node
		_grenade_nodes[grenade.id].position = grenade.position
		_grenade_nodes[grenade.id].quaternion = grenade.orientation
	for id: int in _grenade_nodes.keys():
		if not projectiles.has(id):
			_grenade_nodes[id].queue_free()
			_grenade_nodes.erase(id)

func _show_zombie_spawn_warning(point: Vector3, tick: int, seconds: float) -> void:
	if not point.is_finite(): return
	if not is_instance_valid(_spawn_warning_marker):
		_spawn_warning_marker = MeshInstance3D.new()
		var mesh: TorusMesh = TorusMesh.new()
		mesh.inner_radius = 0.7
		mesh.outer_radius = 1.0
		mesh.rings = 12
		mesh.ring_segments = 12
		_spawn_warning_marker.mesh = mesh
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color("ed7b65")
		material.emission_enabled = true
		material.emission = Color("7c3024")
		_spawn_warning_marker.material_override = material
		add_child(_spawn_warning_marker)
	_spawn_warning_marker.position = point + Vector3.UP * 0.12
	_spawn_warning_marker.visible = true
	_spawn_warning_until_tick = tick + maxi(1, ceili(seconds * 60.0))

func _create_survival_supply_views() -> void:
	for node: Node3D in _survival_supply_views: node.queue_free()
	_survival_supply_views.clear()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("6bbb99")
	material.emission_enabled = true
	material.emission = Color("204c3d")
	for point: Vector3 in SURVIVAL_ARENA.metadata().get("supply_points", []):
		var pad: MeshInstance3D = MeshInstance3D.new()
		var mesh: CylinderMesh = CylinderMesh.new()
		mesh.top_radius = 2.0
		mesh.bottom_radius = 2.0
		mesh.height = 0.04
		mesh.radial_segments = 24
		pad.mesh = mesh
		pad.material_override = material
		pad.position = point + Vector3.UP * 0.02
		add_child(pad)
		_survival_supply_views.append(pad)
		var label: Label3D = Label3D.new()
		label.text = "СНАБЖЕНИЕ" if locale == "ru" else "SUPPLY"
		label.font_size = 36
		label.pixel_size = 0.002
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = point + Vector3.UP * 3.2
		add_child(label)
		_survival_supply_views.append(label)

func _match_objective(kind: String, index: int, point: Vector3) -> void:
	var node := OpenSpadesModels.create("MapObjects/Intel" if kind == "intel" else "MapObjects/CheckPoint")
	node.scale = Vector3.ONE*(.1 if kind == "intel" else .3)
	node.position = point
	node.set_meta("objective",kind)
	node.set_meta("index",index)
	add_child(node)
	_objective_nodes.append(node)

func _match_present_event(event: Dictionary) -> void:
	var own: bool = event.owner_id == session.local_player_id()
	if own and event.type in ["shot","spade_bash","spade_dig"]:
		var cosmetic := event.duplicate(true)
		cosmetic.kind = event.type
		player.apply_match_cosmetic(cosmetic)
	match str(event.type):
		"hit_confirmed":
			if own: player.hit_confirmed.emit(event.part,float(event.damage),event.friendly)
			effects.blood(event.position)
			if event.part == "melee": _play_spatial("Weapons/Spade/HitPlayer",event.position)
			else: audio.flesh_hit(event.position,false)
		"tracer":
			effects.tracer(event.origin,event.position,event.weapon,own and player.camera_mode == BlockfieldPlayer.CameraMode.FIRST_PERSON)
			hud.add_map_tracer(event.origin,event.position,event.weapon,own and player.camera_mode == BlockfieldPlayer.CameraMode.FIRST_PERSON)
		"block_hit", "spade_block_hit", "zombie_breach":
			_match_mark_block_damage(event)
			var color: int = world.get_block(event.cell)
			if color == 0: color = _impact_colors.get(event.cell,0x016f6f6f)
			var normal: Vector3 = Vector3(event.get("normal", Vector3.UP))
			effects.block_hit(event.position,normal,VoxelWorld.block_color(color),event.position.y < world.water_level)
			if event.type in ["spade_block_hit", "zombie_breach"]: _play_spatial("Weapons/Spade/HitBlock",event.position)
			else: audio.bullet_impact(event.position,normal,event.position.y < world.water_level)
		"grenade_bounced": _play_spatial("Weapons/Grenade/Bounce",event.position)
		"grenade_water":
			_play_spatial("Weapons/Grenade/DropWater",event.position)
			effects.water_hit(event.position)
		"spade_miss":
			if own: player._play_sound("Weapons/Spade/Miss",1.0,OpenSpadesAudio.LOCAL_ORIGIN)
			else: _play_spatial("Weapons/Spade/Miss",session.get_target(event.owner_id).get("position",Vector3.ZERO))
	_match_cosmetic_audio(event.type,event,own)

func _match_cosmetic_audio(kind: String, event: Dictionary, own: bool) -> void:
	var point: Vector3 = player.get_aim_origin() if own else session.get_target(event.owner_id).get("position",Vector3.ZERO)+Vector3.UP*2.25
	var first_person: bool = own and player.camera_mode == BlockfieldPlayer.CameraMode.FIRST_PERSON
	match kind:
		"shot":
			audio.weapon_fire(event.weapon,first_person,point,event.get("origin",point))
			if not own: effects.muzzle_fire(event.origin,event.directions[0],event.weapon,false)
		"reload_started":
			if not own: audio.weapon_reload(event.weapon,false,point)
		"reload_completed":
			if not own: audio.weapon_reloaded(session.get_target(event.owner_id).get("weapon",0),false,point)
		"dry_fire": player._play_sound("Weapons/DryFire",1.0,OpenSpadesAudio.LOCAL_ORIGIN)
		"grenade_pin":
			if own: player._play_sound("Weapons/Grenade/Fire",1.0,OpenSpadesAudio.LOCAL_ORIGIN)
		"grenade_thrown", "grenade_release":
			if own: player._play_sound("Weapons/Grenade/Throw",1.0,OpenSpadesAudio.LOCAL_ORIGIN)
			else: _play_spatial("Weapons/Grenade/Throw",point)
		"jump":
			if own: player._play_world_sound("Player/WaterJump" if player.wading else "Player/Jump")
			else: _play_spatial("Player/Jump",point)
		"land": _play_spatial("Player/Land",point)
		"footstep": _play_spatial("Player/Wade1" if event.get("wade",false) else "Player/Footstep1",point)

func _refresh_match_terrain() -> void:
	var match_session: OFFLINE_TDM = session as OFFLINE_TDM
	if world.set_map_data(match_session.simulation.data,world.map_name,true) != OK:
		push_error("Offline terrain presentation refresh failed")
		return
	for cell: Vector3i in match_session.simulation.get_damaged_blocks():
		world.set_block_damaged(cell,true)
