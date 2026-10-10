class_name BlockfieldPlayer
extends CharacterBody3D
## Movement acceleration/friction follows upstream Player::MovePlayer.
## SourcePlayerMotion retains native corner sampling, axis order and climb behavior.

signal hit_confirmed(part: String, damage: float,friendly: bool)
signal notice(message: String)
signal build_error(message: String)
signal dry_fired
signal camera_mode_changed(mode: int)

enum CameraMode { INTRO, FIRST_PERSON, THIRD_PERSON, DEATH, FREE, FOLLOW_FIRST_PERSON, FOLLOW_THIRD_PERSON }

var world: VoxelWorld
var session: LocalSession
var lab: Node3D
var sensitivity: float = 0.0025
var hold_aim_down_sight: bool = false
var invert_mouse: bool = false
var mouse_exponent: float = 1.0
var ads_sensitivity: float = 1.0
var wheel_tool_direction: int = 1
var eject_brass:=true
var animations_enabled:=true
var view_weapon_offset:=Vector3.ZERO
var base_fov: float = 68.0
var aiming := false
var crouching := false
var sprinting := false
var third_person := false
var wading: bool = false
var camera_mode: CameraMode = CameraMode.INTRO
var followed_target_id: int = -1
var follow_first_person: bool = false
## Gameplay permission belongs to menus/chat, independently of OS pointer lock.
var controls_enabled: bool = false
var block_color := Color8(111,111,111)
var _kick := 0.0
var _tool_clock := 0.0
var _step_distance := 0.0
var _walk_steps := 0
var _sprint_state := 0.0
var _dig_first := true
var _last_grenade_time := -10.0
var _last_view_front := Vector3.FORWARD
var _line_start := Vector3i(-1, -1, -1)
var _block_secondary_held:=false
var _grenade_cooking := false
var _native_velocity := Vector3.ZERO
var _motion: SourcePlayerMotion.State
var _pending_cell := Vector3i(-1, -1, -1)
var _block_health: Dictionary = {}
var _dig_held: bool = false
var _connected_session: LocalSession
var _connected_world: VoxelWorld
var _weapon_view: Node3D
var _spectator_view: OpenSpadesSpectatorView
var skin_id := "original"
var _was_reloading: bool = false
var _aim_toggled: bool = false
var _aim_down_state: float = 0.0
var _dry_fire_held: bool = false
var _observed_tool: int = -1
var _observed_weapon: int = -1
var _last_tool: int = -1
var _has_entered: bool = false
var _death_elapsed: float = 0.0
var _camera_yaw: float = 0.0
var _camera_pitch: float = 0.0
var _free_position: Vector3 = Vector3.ZERO
var _free_velocity: Vector3 = Vector3.ZERO
var _camera_effects:=SourceCameraEffects.new()
var camera_radial_blur:=0.0
var _last_spade_fire_time:=-1.0e20

func stop_audio() -> void:
	# Stop playback explicitly before scene teardown; the audio server owns a
	# separate playback reference until its next mixing cycle.
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null

func _exit_tree() -> void:
	stop_audio()

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon_root: Node3D = $Head/Camera3D/WeaponRoot
@onready var shape: CollisionShape3D = $CollisionShape3D
var _drag_look_active:=false
var _drag_look_position:=Vector2.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if session == null or not controls_enabled:
		return
	_sync_camera_mode()
	var drag_fallback:=lab!=null and bool(lab.get("browser_pointer_fallback"))
	if drag_fallback and event is InputEventMouseButton:
		_drag_look_active=event.pressed or event.button_mask!=0
		_drag_look_position=event.position
	if event is InputEventMouseMotion:
		if not drag_fallback and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:apply_mouse_motion(event.relative)
		elif drag_fallback:
			if event.button_mask!=0 and _drag_look_active:apply_mouse_motion(event.position-_drag_look_position)
			_drag_look_active=event.button_mask!=0
			_drag_look_position=event.position
	if lab != null and lab.handle_focus_input(event):
		get_viewport().set_input_as_handled()
		return
	if session.team >= 2 or session.health <= 0.0:
		if event.is_action_pressed("primary"): cycle_camera_target(1)
		if event.is_action_pressed("secondary"): cycle_camera_target(-1)
		if event.is_action_pressed("jump") and followed_target_id >= 0:
			if bool(session.get_target(followed_target_id).get("alive", false)):
				follow_first_person = not follow_first_person
		if event.is_action_pressed("reload") and session.team >= 2: stop_following()
		return
	if event.is_action_pressed("reload"):
		_aim_toggled = false
		session.reload_weapon()
	if event.is_action_pressed("tool_spade"): session.select_tool(0)
	if event.is_action_pressed("tool_block"): session.select_tool(1)
	if event.is_action_pressed("tool_weapon"): session.select_tool(2)
	if event.is_action_pressed("tool_grenade"): session.select_tool(3)
	if InputMap.has_action("last_tool") and event.is_action_pressed("last_tool"):
		select_last_tool()
	if event is InputEventMouseButton and event.pressed and wheel_tool_direction != 0:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: cycle_tool(signi(wheel_tool_direction))
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: cycle_tool(-signi(wheel_tool_direction))
	if event.is_action_pressed("eyedropper") and world != null:
		var hit := world.cast_voxel(get_aim_origin(), get_aim_direction(), 12.0)
		if hit.hit:
			block_color = VoxelWorld.block_color(world.get_block(hit.cell))
			notice.emit("Picked block color")
	if event.is_action_pressed("view_toggle"):
		third_person = not third_person
	if event.is_action_pressed("secondary") and session.current_tool == 2 and not hold_aim_down_sight:
		if not session.is_reloading:
			_aim_toggled = not _aim_toggled
			if _aim_toggled and can_use_tool(): _play_sound("Weapons/AimDownSightLocal",.08,OpenSpadesAudio.LOCAL_ORIGIN)
	if event.is_action_pressed("primary") and session.current_tool == 3 and can_use_tool():
		_begin_grenade_cook()
	if event.is_action_released("primary") and _grenade_cooking:
		_throw_grenade()
	if event.is_action_pressed("secondary") and session.current_tool == 1 and can_use_tool():
		_begin_block_line()
		_block_secondary_held=true
	if event.is_action_released("secondary") and session.current_tool == 1 and _line_start.x >= 0:
		if can_use_tool():_build_line()
		_line_start = Vector3i(-1, -1, -1)
		_block_secondary_held=false

func _physics_process(delta: float) -> void:
	if world == null or session == null:
		return
	_connect_simulation()
	# Player::BoxClipMove uses world-axis corner samples, independent of yaw.
	shape.rotation.y = -rotation.y
	_tool_clock = maxf(0.0, _tool_clock - delta)
	_kick = lerpf(_kick, 0.0, minf(delta * 12.0, 1.0))
	_restore_block_health()
	if session.health <= 0.0 and session.team < 2: _death_elapsed += delta
	_sync_camera_mode()
	if session.team >= 2:
		session.set_trigger_held(false)
		crouching = false
		sprinting = false
		aiming = false
		if camera_mode == CameraMode.FREE and controls_enabled: _move_free_camera(delta)
		session.update_player_position(_free_position if camera_mode == CameraMode.FREE else global_position)
		world.set_view_position(camera.global_position)
		_update_view(delta)
		return
	_sync_motion_state()
	wading = SourcePlayerMotion.get_wade(world,_motion)
	if not controls_enabled or session.health <= 0:
		session.set_trigger_held(false)
		aiming = false
		sprinting = false
		_native_velocity.x /= 1.0 + delta * 4.0
		_native_velocity.z /= 1.0 + delta * 4.0
		if session.team < 2:
			_native_velocity.y = (_native_velocity.y - delta) / (1.0 + delta)
			_clip_motion(delta)
		session.update_player_position(global_position)
		_update_view(delta)
		return
	var axis := Input.get_vector("left", "right", "forward", "back")
	var wants_crouch := Input.is_action_pressed("crouch")
	if wants_crouch != crouching:
		_motion=SourcePlayerMotion.set_crouch(world,_motion,wants_crouch)
		global_position=_motion.feet_position
		crouching=_motion.crouch
	sprinting = Input.is_action_pressed("sprint") and not crouching and axis.length() > 0.01 and Vector2(_native_velocity.x,_native_velocity.z).length()>=.1
	aiming = (Input.is_action_pressed("secondary") if hold_aim_down_sight else _aim_toggled) \
		and session.current_tool == 2 and can_use_tool() and not session.is_reloading
	var sneak := Input.is_action_pressed("sneak")
	(shape.shape as BoxShape3D).size.y = 1.8 if crouching else 2.7
	shape.position.y = (shape.shape as BoxShape3D).size.y * 0.5
	var accel := delta
	if not is_grounded(): accel *= 0.1
	elif crouching: accel *= 0.3
	elif aiming or sneak: accel *= 0.5
	elif sprinting: accel *= 1.3
	var forward := -global_basis.z
	var right := global_basis.x
	var slowdown := 1.0 - maxf(absf(sin(head.rotation.x)) - 0.65, 0.0) / 0.35 * 0.9
	var movement := right * axis.x + forward * -axis.y * slowdown
	if session.team < 2:
		if Input.is_action_pressed("jump") and SourcePlayerMotion.is_on_ground_or_wade(_motion):
			_native_velocity.y = 0.36
			_play_world_sound("Player/WaterJump" if wading else "Player/Jump")
		_native_velocity += movement * accel
		_native_velocity.y = (_native_velocity.y - delta) / (1.0 + delta)
		# Player.cpp:1157: wade overrides ground/air horizontal friction.
		var friction := 1.0 + delta * (6.0 if _motion.wading else (4.0 if is_grounded() else 1.0))
		_native_velocity.x /= friction
		_native_velocity.z /= friction
		_clip_motion(delta)
		if -_native_velocity.y>=0.0 and -_native_velocity.y<0.017 and not sneak and not crouching and not aiming:
			_step_distance += Vector2(_native_velocity.x,_native_velocity.z).length()*32.0*delta
		if _step_distance > 1.0 / 0.3:
			while _step_distance>1.0/0.3:
				_step_distance-=1.0/0.3
				_walk_steps+=1
			_play_world_sound("Player/Wade%d" % randi_range(1,8) if wading else "Player/Footstep%d" % randi_range(1,8))
			if sprinting and not wading: _play_world_sound("Player/Run%d" % randi_range(1,12),_sprint_state)
		if global_position.y < -5.0: session.damage_player(1000.0, Vector3.INF, "fall")
	session.update_player_position(global_position)
	world.set_view_position(global_position)
	if _pending_cell.x >= 0 and (is_grounded() or (session.blocks<=0 and not session.unlimited_ammo)): _pending_cell = Vector3i(-1,-1,-1)
	if _pending_cell.x >= 0 and _in_reach(_pending_cell) and not _overlaps_player(_pending_cell):
		_place(_pending_cell)
		_pending_cell = Vector3i(-1,-1,-1)
	var allowed:=can_use_tool()
	var digging := Input.is_action_pressed("secondary") and session.current_tool == 0 and allowed
	if not session.is_tool_selectable(session.current_tool):
		Input.action_release("primary")
		Input.action_release("secondary")
		cycle_tool(-1)
		digging=false
	if digging and not _dig_held:
		_tool_clock = 1.0 # Original first dig waits a full secondary interval.
		_dig_first=true
	_dig_held = digging
	allowed=can_use_tool()
	if _line_start.x>=0 and not _line_supported():
		_line_start=Vector3i(-1,-1,-1)
		build_error.emit("The line has no support")
	var block_secondary:=allowed and session.current_tool==1 and Input.is_action_pressed("secondary")
	if block_secondary and not _block_secondary_held:_begin_block_line()
	elif not block_secondary and _block_secondary_held and _line_start.x>=0:
		if allowed:_build_line()
		_line_start=Vector3i(-1,-1,-1)
	_block_secondary_held=block_secondary
	session.set_trigger_held(Input.is_action_pressed("primary") and session.current_tool==2 and allowed)
	if _grenade_cooking and not allowed:_throw_grenade()
	if allowed and session.team < 2:
		if Input.is_action_pressed("primary"):
			match session.current_tool:
				0:
					if not digging: _spade(false)
				1:
					if not block_secondary:_build_single()
				2: _shoot()
				3:
					if not session.is_cooking_grenade:_begin_grenade_cook()
		if digging:
			_spade(true)
	if not Input.is_action_pressed("primary") or session.current_tool != 2: _dry_fire_held = false
	_update_view(delta)

func can_stand() -> bool:
	_sync_motion_state()
	return bool(SourcePlayerMotion.try_uncrouch(world,_motion).allowed)

func is_grounded() -> bool:
	return _motion!=null and _motion.grounded

func can_use_tool() -> bool:
	if session==null or session.health<=0 or session.team>=2 or not controls_enabled:return false
	if sprinting or _sprint_state>0.0:return false
	if _weapon_view==null:return false
	# Publish desired selection before reading the native lower/raise gate.
	_weapon_view.set_selection(session.current_tool,session.current_weapon)
	return not _weapon_view.is_changing_tool()

func _sync_motion_state() -> void:
	if _motion==null:_motion=SourcePlayerMotion.create_state(global_position,crouching,false)
	_motion.feet_position=global_position
	_motion.native_velocity=_native_velocity
	_motion.crouch=crouching
	_motion.sprint=sprinting
	_motion.front=-head.global_basis.z

func _clip_motion(delta: float) -> void:
	_sync_motion_state()
	var incoming_speed: float=-_native_velocity.y
	_motion=SourcePlayerMotion.finish_landing(SourcePlayerMotion.clip_move(world,_motion,delta,session.session_time),incoming_speed)
	global_position=_motion.feet_position
	_native_velocity=_motion.native_velocity
	velocity=_native_velocity*32.0
	head.position.y=_motion.eye_position.y-global_position.y
	wading=SourcePlayerMotion.get_wade(world,_motion)
	if _motion.landed:
		_play_world_sound("Player/FallHurt" if _motion.fall_hurt else ("Player/WaterLand" if wading else "Player/Land"))
		if _motion.fall_hurt:session.damage_player(pow(incoming_speed-.58,2)*4096.0,Vector3.INF,"fall")

func cycle_tool(direction: int) -> void:
	if session == null or session.team >= 2 or session.health <= 0.0 or direction == 0: return
	var tool := session.current_tool
	for attempt in range(4):
		tool = posmod(tool + signi(direction), 4)
		if session.is_tool_selectable(tool):
			session.select_tool(tool)
			return

func select_last_tool() -> void:
	if session != null and _last_tool >= 0 and session.team < 2 and session.health > 0.0:
		session.select_tool(_last_tool)

func _observe_selection() -> void:
	if _observed_tool != session.current_tool or _observed_weapon != session.current_weapon:
		if _observed_tool>=0:
			Input.action_release("primary")
			Input.action_release("secondary")
		_pending_cell=Vector3i(-1,-1,-1)
		_line_start=Vector3i(-1,-1,-1)
		_block_secondary_held=false
		_grenade_cooking=false
		_dig_held=false
		_tool_clock=0.0
		_was_reloading=false
		if _weapon_view!=null:_weapon_view.cancel_reload()
		if _observed_tool >= 0 and _observed_tool != session.current_tool: _last_tool = _observed_tool
		_observed_tool = session.current_tool
		_observed_weapon = session.current_weapon
		_aim_toggled = false
		aiming = false
		_dry_fire_held = false

func get_aim_down_state() -> float:
	return _aim_down_state

func get_walk_progress() -> float:
	return _step_distance*.3*.5+float(_walk_steps)*.5

func get_tool_action() -> Dictionary:
	var type:=0
	var progress:=0.0
	var ready:=1.0
	if session==null:return {"type":type,"progress":progress,"ready":ready}
	if session.current_tool==0:
		if Input.is_action_pressed("primary"):type=1;progress=1.0-_tool_clock/.2
		elif _dig_held:type=2 if _dig_first else 3;progress=1.0-_tool_clock
	elif session.current_tool==1:ready=1.0 if session.block_cooldown<=0.0 else 0.0
	elif session.current_tool==2:
		ready=(session.session_time-session.last_shot_time)/float(session.get_weapon_info().delay) if session.last_shot_time>=0 else 2.0
	elif session.current_tool==3:ready=(session.session_time-_last_grenade_time)/.5
	return {"type":type,"progress":clampf(progress,0,1),"ready":ready}

func get_aim_origin() -> Vector3:
	return head.global_position

func get_aim_direction() -> Vector3:
	# Presentation shake and third-person orbit must not alter authoritative rays.
	return -head.global_basis.z

func _effects() -> OpenSpadesEffects:
	return lab.get("effects") as OpenSpadesEffects if lab != null else null

func get_camera_aim_down_state() -> float:
	if camera_mode==CameraMode.FOLLOW_FIRST_PERSON and _spectator_view!=null:return _spectator_view.get_aim_down_state()
	return _aim_down_state

func get_camera_tool() -> int:
	if camera_mode==CameraMode.FOLLOW_FIRST_PERSON and _spectator_view!=null:return _spectator_view.get_displayed_tool()
	if _weapon_view!=null and _weapon_view.has_method("get_displayed_tool"):return int(_weapon_view.get_displayed_tool())
	return session.current_tool

func get_aim_zoom() -> float:
	# Client_Scene.cpp:120 uses the camera-target's tool, gun and eased ADS.
	var tool:=session.current_tool
	var weapon:=session.current_weapon
	if camera_mode==CameraMode.FOLLOW_FIRST_PERSON:
		var target:=session.get_target(followed_target_id)
		if target.is_empty() or not bool(target.alive):return 1.0
		tool=int(target.get("tool",2));weapon=int(target.get("weapon",0))
	elif session.health<=0 or session.team>=2:return 1.0
	if tool!=2:return 1.0
	var state:=get_camera_aim_down_state()
	var amount: float=[1.4,0.8,0.4][clampi(weapon,0,2)]
	return 1.0+(3.0-2.0*pow(state,1.5))*pow(state,3.0)*amount

func apply_mouse_motion(relative: Vector2) -> void:
	if not controls_enabled or session == null: return
	if camera_mode == CameraMode.FOLLOW_FIRST_PERSON: return
	if camera_mode in [CameraMode.DEATH, CameraMode.FREE, CameraMode.FOLLOW_THIRD_PERSON]:
		_camera_yaw -= relative.x * 0.003
		_camera_pitch = clampf(_camera_pitch - relative.y * 0.003 * (-1.0 if invert_mouse else 1.0), -PI * 0.45, PI * 0.45)
		return
	# Client_Input.cpp:161-198. Sensitivity is stored in radians per pixel.
	var delta := relative / get_aim_zoom()
	if not is_finite(mouse_exponent) or mouse_exponent < 0.001: mouse_exponent = 1.0
	var width := maxf(1.0, get_viewport().get_visible_rect().size.x)
	if delta.length_squared() > 0.0:
		var factor := pow(delta.length_squared() / pow(width * 0.1, 2.0), mouse_exponent * 0.5 - 0.5)
		if is_finite(factor): delta *= factor
	delta *= pow(maxf(ads_sensitivity, 0.001), _aim_down_state) * sensitivity
	rotate_y(-delta.x)
	head.rotation.x = clampf(head.rotation.x - delta.y * (-1.0 if invert_mouse else 1.0), -1.55,1.55)

func _connect_simulation() -> void:
	if _spectator_view==null:
		_spectator_view=OpenSpadesSpectatorView.new()
		camera.add_child(_spectator_view)
		_spectator_view.setup(camera,session,skin_id)
	if _weapon_view == null:
		_weapon_view = OpenSpadesExtensions.create_first_person_skin(skin_id,{"player":self,"session":session,"world":world})
		weapon_root.position = Vector3.ZERO
		weapon_root.add_child(_weapon_view)
		_connect_skin_signals()
	if _connected_session != session:
		_connected_session = session
		_observe_selection()
		session.changed.connect(_observe_selection)
		session.player_died.connect(func():
			_death_elapsed = 0.0
			followed_target_id = -1
			_camera_yaw = rotation.y
			_camera_pitch = -PI / 6.0)
		session.grenade_thrown.connect(func(_data: Dictionary):
			_grenade_cooking = false
			_last_grenade_time=session.session_time
			_weapon_view.fire())
		session.shot_fired.connect(func():
			if _was_reloading:
				_weapon_view.cancel_reload()
				_was_reloading = false
			_weapon_view.set_ammo(session.magazine, int(session.get_weapon_info().clip_size))
			_weapon_view.fire())
		session.reloaded.connect(func():
			_weapon_view.reload_completed()
			if lab!=null and lab.audio!=null:lab.audio.weapon_reloaded(session.current_weapon,camera_mode==CameraMode.FIRST_PERSON,get_aim_origin())
			_was_reloading = false)
		session.player_respawned.connect(_clear_input_state)
	if _connected_world != world:
		_connected_world = world
		world.map_loaded.connect(func(_map_name: String): _clear_action_state())
		world.blocks_changed.connect(_on_blocks_changed)

func _connect_skin_signals() -> void:
	if _weapon_view.has_signal("tool_raised"):
		_weapon_view.tool_raised.connect(func(tool: int,weapon: int):
			var name: String=["Spade","Block",["Rifle","SMG","Shotgun"][clampi(weapon,0,2)],"Grenade"][clampi(tool,0,3)]
			_play_sound("Weapons/"+name+"/RaiseLocal",1.0,OpenSpadesAudio.LOCAL_ORIGIN))

func _clear_action_state() -> void:
	_block_health.clear()
	_clear_input_state()

func _clear_input_state() -> void:
	_drag_look_active=false
	_last_spade_fire_time=-1.0e20
	camera_radial_blur=0.0
	_pending_cell = Vector3i(-1, -1, -1)
	_line_start = Vector3i(-1, -1, -1)
	_block_secondary_held=false
	_grenade_cooking = false
	_dig_held = false
	_dig_first=true
	_tool_clock = 0.0
	_was_reloading = false
	_aim_toggled = false
	aiming = false
	_aim_down_state = 0.0
	_dry_fire_held = false
	_death_elapsed = 0.0
	followed_target_id = -1
	if _weapon_view != null: _weapon_view.cancel_reload()

func _on_blocks_changed(changes: Array) -> void:
	for change in changes:
		_block_health.erase(change.cell)

func _restore_block_health() -> void:
	for cell in _block_health.keys():
		if session.session_time - float(_block_health[cell].time) >= 10.0:
			_block_health.erase(cell)

func _shoot() -> void:
	if not session.fire():
		# Weapon.cpp:144: play once on the transition into an empty trigger hold.
		var slow_reload := bool(session.get_weapon_info().slow_reload)
		if session.magazine <= 0 and not session.unlimited_ammo and session.fire_cooldown <= 0.0 \
			and (not session.is_reloading or slow_reload) and not _dry_fire_held:
			_dry_fire_held = true
			_play_sound("Weapons/DryFire",1.0,OpenSpadesAudio.LOCAL_ORIGIN)
			dry_fired.emit()
		return
	_dry_fire_held = false
	var info: Dictionary = session.get_weapon_info()
	var origin := get_aim_origin()+get_aim_direction()*0.01
	var accumulated_direction := get_aim_direction()
	var spread: float = float(info.spread) * (0.5 if aiming else 1.0)
	if lab!=null and lab.audio!=null:
		lab.audio.weapon_fire(session.current_weapon,camera_mode==CameraMode.FIRST_PERSON,get_aim_origin(),get_aim_origin()+get_aim_direction()*.5-head.global_basis.y*.3+head.global_basis.x*.4)
	var effects := _effects()
	if effects != null:
		var muzzle: Vector3 = _weapon_view.get_muzzle_transform().origin if _weapon_view != null and camera_mode == CameraMode.FIRST_PERSON else origin + accumulated_direction * 0.5
		effects.muzzle_fire(muzzle,accumulated_direction,session.current_weapon)
		if session.current_weapon != 2 and eject_brass:
			effects.eject_shell(muzzle,accumulated_direction,head.global_basis.x,head.global_basis.y,session.current_weapon)
	var destroyed_block := false
	for pellet in int(info.pellets):
		# Player::FireWeapon accumulates all pellets into the unnormalized vector.
		accumulated_direction += Vector3(randf()-randf(), randf()-randf(), randf()-randf()) * spread
		var direction := accumulated_direction.normalized()
		var map_hit := world.cast_voxel(origin, direction, 500.0)
		var result := raycast_targets(origin,direction,500.0)
		var chosen := source_weapon_hit(origin,map_hit,result)
		var end := origin+direction*128.0
		if chosen=="player":
			if result.has("target_id"):
				var part: String = result.part
				var horizontal_distance := _horizontal_distance(origin, result.position)
				var damage := session.damage_target(int(result.target_id), part, horizontal_distance)
				if damage > 0.0:
					hit_confirmed.emit(part, damage,int(session.get_target(int(result.target_id)).team)==session.team)
					if lab!=null and lab.audio!=null:lab.audio.flesh_hit(result.position)
					if effects != null: effects.blood(result.position)
				end = result.position
		elif chosen=="map":
			end=map_hit.position
			if lab!=null and lab.audio!=null:lab.audio.bullet_impact(map_hit.position,Vector3(map_hit.normal),int(map_hit.cell.y)==0)
			if effects != null:
				effects.block_hit(map_hit.position,Vector3(map_hit.normal),VoxelWorld.block_color(world.get_block(map_hit.cell)),map_hit.position.y <= world.water_level + 0.2)
			if _damage_block(map_hit.cell, float(info.block), not destroyed_block):
				destroyed_block = true
		if effects != null:
			effects.tracer(origin,end,session.current_weapon,camera_mode == CameraMode.FIRST_PERSON)
		elif lab != null: lab.spawn_tracer(origin-head.global_basis.y*0.12, end)
		if lab != null and lab.hud != null:
			lab.hud.add_map_tracer(origin,end,session.current_weapon,camera_mode == CameraMode.FIRST_PERSON)
	var recoil_direction := source_recoil(get_aim_direction(),head.global_basis.x,head.global_basis.y,info.recoil,session.session_time,crouching)
	rotation.y=atan2(-recoil_direction.x,-recoil_direction.z)
	head.rotation.x=asin(clampf(recoil_direction.y,-1.0,1.0))
	_kick = 0.12

static func source_recoil(front: Vector3,right: Vector3,up: Vector3,recoil: Vector3,time: float,crouch: bool) -> Vector3:
	var multiplier:=0.5 if crouch else 1.0
	var horizontal := Vector3(front.x,0,front.z).normalized()
	var up_limit := horizontal.dot(front)-0.03
	var phase := fposmod(time*0.9788,1.0)
	var wave := phase*4.0-1.0 if phase<0.5 else 3.0-phase*4.0
	return (front+up*minf(recoil.y,maxf(0.0,up_limit))*multiplier+right*recoil.x*wave*multiplier).normalized()

static func source_weapon_hit(origin: Vector3,map_hit: Dictionary,player_hit: Dictionary) -> String:
	# Player.cpp:646–697 compares horizontal distance, with a strict map tie.
	var map_distance:=Vector2(origin.x-map_hit.get("position",origin).x,origin.z-map_hit.get("position",origin).z).length()
	var player_distance:=Vector2(origin.x-player_hit.get("position",origin).x,origin.z-player_hit.get("position",origin).z).length()
	if bool(map_hit.get("hit",false)) and map_distance<128.0 and (player_hit.is_empty() or map_distance<player_distance):return "map"
	if not player_hit.is_empty() and player_distance<128.0:return "player"
	return "none"

func raycast_targets(origin: Vector3,direction: Vector3,max_distance: float=500.0) -> Dictionary:
	var result: Dictionary={}
	var closest_horizontal:=INF
	for target in session.targets:
		if not bool(target.alive) or int(target.team)>=2:continue
		var hit:=LabHitVolumes.cast_ray(origin,direction,target.position,float(target.get("yaw",0.0)),str(target.state)=="crouching",float(target.get("pitch",0.0)),max_distance)
		if hit.hit:
			var horizontal:=_horizontal_distance(origin,hit.position)
			if horizontal<closest_horizontal:
				closest_horizontal=horizontal
				result=hit
				result["target_id"]=int(target.id)
	return result
func _horizontal_distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x - second.x, first.z - second.z).length()

func _damage_block(cell: Vector3i, damage: float, allow_destroy: bool = true) -> bool:
	if cell.y <= 1 or world.get_block(cell) == 0: return false
	var health: float = float(_block_health.get(cell, {"health":100.0}).health) - damage
	if health <= 0.0 and allow_destroy:
		world.set_block(cell,0)
		_block_health.erase(cell)
		return true
	else:
		_block_health[cell] = {"health":maxf(0.0, health),"time":session.session_time}
	return false

func _spade(dig: bool) -> void:
	if _tool_clock > 0.0: return
	_last_spade_fire_time=session.session_time
	_tool_clock = 1.0 if dig else 0.2
	if dig:_dig_first=false
	if _weapon_view != null: _weapon_view.fire()
	var origin := get_aim_origin()
	var direction := get_aim_direction()
	var hit := world.cast_voxel(origin, direction, 6.0)
	if not dig:
		var target_id:=find_melee_target(origin,direction)
		if target_id>=0:
			var amount := session.apply_target_damage(target_id,LocalSession.LOCAL_MELEE_DAMAGE,"melee")
			if amount > 0.0: hit_confirmed.emit("melee", amount,int(session.get_target(target_id).team)==session.team)
			if amount>0 and lab!=null and lab.audio!=null:lab.audio.flesh_hit(session.get_target(target_id).position+Vector3.UP*2.25)
			if lab!=null and lab.audio!=null:lab.audio.play_spatial("Weapons/Spade/HitPlayer",session.get_target(target_id).position+Vector3.UP*2.25)
			return
	if hit.hit and _in_reach(hit.cell+hit.normal):
		_play_sound("Weapons/Spade/HitBlock",1.0,Vector3(.1,-.1,1.2))
		var effects := _effects()
		if effects != null: effects.block_hit(hit.position,Vector3(hit.normal),VoxelWorld.block_color(world.get_block(hit.cell)))
		if dig:
			world.remove_blocks([hit.cell+Vector3i.DOWN,hit.cell,hit.cell+Vector3i.UP],true)
		else:
			var before: int = world.get_block(hit.cell)
			_damage_block(hit.cell,55.0)
			if before != 0 and world.get_block(hit.cell)==0: session.recover_block()
		return
	_play_sound("Weapons/Spade/Miss",1.0,Vector3(.2,-.1,.7))

func _in_reach(cell: Vector3i) -> bool:
	var diff := (Vector3(cell)+Vector3.ONE*0.5-get_aim_origin()).abs()
	return maxf(diff.x,maxf(diff.y,diff.z)) < 3.0

func _overlaps_player(cell: Vector3i) -> bool:
	var eye:=get_aim_origin()
	var height:=0.85 if crouching else 1.75
	return AABB(Vector3(cell),Vector3.ONE).intersects(AABB(eye-Vector3(.45,height,.45),Vector3(.9,height,.9)))

func find_melee_target(origin: Vector3,direction: Vector3) -> int:
	# Native melee uses a broad view-space test, not exact firearm hit volumes.
	for target in session.targets:
		if not bool(target.alive) or int(target.team)>=2:continue
		var eye: Vector3=target.position+Vector3.UP*(1.35 if str(target.state)=="crouching" else 2.25)
		var diff:=eye-origin
		if maxf(absf(diff.x),maxf(absf(diff.y),absf(diff.z)))>=3.0:continue
		var forward:=diff.dot(direction)
		if forward<=0.0:continue
		if maxf(absf(diff.dot(head.global_basis.x)/forward),absf(diff.dot(head.global_basis.y)/forward))>=5.0:continue
		if not raycast_approx(origin,direction,eye):continue
		return int(target.id)
	return -1

static func raycast_approx(origin: Vector3,direction: Vector3,eye: Vector3) -> bool:
	var diff:=eye-origin
	var projection:=diff.dot(direction)
	return (diff-direction*projection).length_squared()<64.0

func get_build_preview() -> Dictionary:
	var cells: Array[Vector3i] = []
	var result := {"cells":cells,"valid":false,"reason":"","pending":false}
	if world == null or session == null or session.current_tool != 1 or session.team >= 2 or session.health <= 0.0:
		return result
	var hit := world.cast_voxel(get_aim_origin(),get_aim_direction(),12.0)
	if not hit.hit:
		result.reason = "No block in view"
		return result
	var endpoint: Vector3i = hit.cell + hit.normal
	if _line_start.x >= 0: cells = _cube_line(_line_start,endpoint,256)
	else: cells.append(endpoint)
	result.cells = cells
	if cells.is_empty(): result.reason = "Outside the map"
	elif not _in_reach(endpoint): result.reason = "Out of reach"
	elif cells.size() > 50 or (not session.unlimited_ammo and cells.size() > session.blocks): result.reason = "Insufficient blocks"
	elif session.block_cooldown > 0.0 or _tool_clock > 0.0: result.reason = "Tool is cooling down"
	elif _line_start.x >= 0:
		var supported := false
		for direction in [Vector3i.UP,Vector3i.DOWN,Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
			if world.get_block(_line_start + direction) != 0: supported = true
		if not supported: result.reason = "The line has no support"
	for cell in cells:
		if not world.is_in_bounds(cell): result.reason = "Outside the map"
		elif cell.y <= 1: result.reason = "Bedrock cannot be changed"
		elif _overlaps_player(cell):
			result.reason = "Block intersects player"
			result.pending = _line_start.x < 0 and not is_grounded()
		elif _line_start.x < 0 and world.get_block(cell) != 0: result.reason = "Block is occupied"
	result.valid = str(result.reason).is_empty() and not cells.is_empty()
	result.pending = bool(result.pending) or _pending_cell.x >= 0
	return result

func _build_single() -> void:
	if _tool_clock > 0.0: return
	var hit := world.cast_voxel(get_aim_origin(),get_aim_direction(),12.0)
	if not hit.hit: return
	var cell: Vector3i = hit.cell+hit.normal
	if not _in_reach(cell): return
	if _overlaps_player(cell):
		if not is_grounded(): _pending_cell=cell
		return
	if _place(cell): _tool_clock=0.5

func _place(cell: Vector3i) -> bool:
	if cell.y <= 1 or not world.is_in_bounds(cell) or world.get_block(cell)!=0 or not session.use_block(): return false
	world.set_block(cell,VoxelWorld.pack_color(block_color))
	if _weapon_view != null: _weapon_view.fire()
	_play_sound("Weapons/Block/Build")
	return true

func _build_line() -> void:
	if _line_start.x < 0 or session.block_cooldown > 0.0: return
	var attached := false
	for direction in [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
		if world.get_block(_line_start + direction) != 0: attached = true
	if not attached:
		build_error.emit("The line has no support")
		return
	var hit := world.cast_voxel(get_aim_origin(),get_aim_direction(),12.0)
	if not hit.hit: return
	var end: Vector3i = hit.cell+hit.normal
	if not _in_reach(end):
		build_error.emit("Line endpoint is out of reach")
		return
	var cells := _cube_line(_line_start, end, 256)
	if cells.size() > 50 or (not session.unlimited_ammo and cells.size() > session.blocks):
		build_error.emit("Insufficient blocks for this line")
		return
	for cell in cells:
		if not world.is_in_bounds(cell) or cell.y <= 1 or _overlaps_player(cell):
			build_error.emit("Invalid block line")
			return
	if not session.use_block(cells.size()): return
	for cell in cells:
		if world.get_block(cell)==0:world.set_block(cell, VoxelWorld.pack_color(block_color))
	_tool_clock = 0.5
	if _weapon_view != null: _weapon_view.fire()
	_play_sound("Weapons/Block/Build")

func _begin_block_line() -> void:
	var preview:=get_build_preview()
	if not bool(preview.valid):
		build_error.emit(str(preview.reason))
		return
	_line_start=preview.cells[0]

func _line_supported() -> bool:
	for direction in [Vector3i.UP,Vector3i.DOWN,Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
		var neighbor: Vector3i=_line_start+direction
		neighbor.x=posmod(neighbor.x,world.dimensions.x)
		neighbor.z=posmod(neighbor.z,world.dimensions.z)
		if world.get_block(neighbor)!=0:return true
	return false

func _cube_line(start: Vector3i, end: Vector3i, limit: int) -> Array[Vector3i]:
	# World::CubeLine, with source (x,y,z-down) axes mapped to Godot (x,y-up,z).
	var difference := end - start
	var dominant := maxi(absi(difference.x), maxi(absi(difference.y), absi(difference.z)))
	var increment := Vector3i.ZERO
	var next_crossing := Vector3i.ZERO
	var step := Vector3i(1 if difference.x >= 0 else -1, 1 if difference.y >= 0 else -1, 1 if difference.z >= 0 else -1)
	for axis in range(3):
		increment[axis] = int(float(dominant * 1024) / absi(difference[axis])) if difference[axis] != 0 else 0x3fffffff
		var source_step:= -step[axis] if axis==1 else step[axis]
		next_crossing[axis] = increment[axis] - int(increment[axis] / 2) if source_step > 0 else int(increment[axis] / 2)
	var cells: Array[Vector3i] = []
	var cell := start
	while cells.size() < limit and world.is_in_bounds(cell):
		cells.append(cell)
		if cell == end: break
		var axis := 1 if next_crossing.y <= next_crossing.x and next_crossing.y <= next_crossing.z else (0 if next_crossing.x < next_crossing.z else 2)
		cell[axis] += step[axis]
		next_crossing[axis] += increment[axis]
	return cells

func _begin_grenade_cook() -> void:
	_grenade_cooking=session.begin_grenade_cook()
	if _grenade_cooking:_play_sound("Weapons/Grenade/Fire",1.0,OpenSpadesAudio.LOCAL_ORIGIN)

func _throw_grenade() -> void:
	_grenade_cooking=false
	session.release_grenade()

func _update_view(delta: float) -> void:
	_aim_down_state = clampf(_aim_down_state + delta * (8.0 if aiming else -3.0),0.0,1.0)
	if not animations_enabled:_aim_down_state=1.0 if aiming else 0.0
	_sprint_state=clampf(_sprint_state+delta*(4.0 if sprinting else -3.0),0,1)
	_sync_camera_mode()
	_update_camera_transform()
	weapon_root.visible = camera_mode == CameraMode.FIRST_PERSON and session.team<2 and session.health>0
	if _spectator_view!=null:
		_spectator_view.animations_enabled=animations_enabled
		_spectator_view.show_target(followed_target_id,camera_mode==CameraMode.FOLLOW_FIRST_PERSON)
		_spectator_view.update_view(delta)
	_update_camera_effects(delta)
	if _weapon_view == null: return
	_weapon_view.set_selection(session.current_tool, session.current_weapon)
	_weapon_view.set_team(session.team,session.get_team_info(session.team).color)
	_weapon_view.set_block_color(block_color)
	_weapon_view.set_ammo(session.magazine, int(session.get_weapon_info().clip_size))
	_weapon_view.set_grenade_cook(session.grenade_cook_time if session.is_cooking_grenade else 0.0)
	var action:=get_tool_action()
	if _weapon_view.has_method("set_tool_action"):_weapon_view.set_tool_action(action.type,action.progress,action.ready)
	else:_weapon_view.set_spade_action(_dig_held,action.progress)
	var front:=get_aim_direction()
	if _weapon_view.has_method("set_motion_state"):
		_weapon_view.set_motion_state(head.global_basis.inverse()*velocity,get_walk_progress(),head.global_basis.inverse()*(front-_last_view_front),view_weapon_offset)
	if _weapon_view.has_method("set_animations_enabled"):_weapon_view.set_animations_enabled(animations_enabled)
	_last_view_front=front
	if session.is_reloading and not _was_reloading:
		_weapon_view.reload()
		if lab!=null and lab.audio!=null:lab.audio.weapon_reload(session.current_weapon,camera_mode==CameraMode.FIRST_PERSON,get_aim_origin()+get_aim_direction()*.5-head.global_basis.y*.3+head.global_basis.x*.4)
	elif not session.is_reloading and _was_reloading:
		_weapon_view.cancel_reload()
	_was_reloading = session.is_reloading
	_weapon_view.update_pose(delta, aiming, sprinting, crouching, velocity.length(), session.get_reload_progress())

func _update_camera_effects(delta: float) -> void:
	var first_person:=camera_mode in [CameraMode.FIRST_PERSON,CameraMode.FOLLOW_FIRST_PERSON]
	var motion: Dictionary={"raw_sprint":_sprint_state,"walk_phase":get_walk_progress(),"last_fire_time":maxf(session.last_shot_time if session.last_shot_time>=0 else -1.0e20,_last_spade_fire_time)}
	if camera_mode==CameraMode.FOLLOW_FIRST_PERSON and _spectator_view!=null:
		motion=_spectator_view.get_camera_motion_state()
		motion.last_fire_time=session.session_time-float(motion.fire_age)
	var shake:=clampi(int(lab.graphics_options.shake),0,2) if lab!=null else 0
	if first_person and shake>=2:
		var pulse:=pow(cos(float(motion.walk_phase)*TAU-.8),16.0)
		camera.position+=camera.basis.y*pulse*.06*smoothstep(0.0,1.0,float(motion.raw_sprint))
	var effects:=_effects()
	var zoom:=get_aim_zoom() if first_person else 1.0
	motion.merge({"shake_level":shake,"first_person":first_person,"raw_ads":get_camera_aim_down_state(),"tool":get_camera_tool(),"ads_zoom_scale":zoom,"grenade_fast":effects._fast_shake if effects!=null else 0.0,"grenade_slow":effects._slow_shake if effects!=null else 0.0})
	var sample:=_camera_effects.sample(motion,session.session_time,delta)
	camera.basis=camera.basis*sample.basis_delta
	var zoomed_fov:=rad_to_deg(2.0*atan(tan(deg_to_rad(clampf(base_fov,45.0,90.0))*.5)/zoom))
	camera.fov=SourceCameraEffects.apply_fov_degrees(zoomed_fov,float(sample.fov_scale))
	camera_radial_blur=float(sample.radial_blur_strength)

func _sync_camera_mode() -> void:
	if controls_enabled: _has_entered = true
	if followed_target_id >= 0 and session.get_target(followed_target_id).is_empty(): followed_target_id = -1
	var next_mode: CameraMode
	if not _has_entered:
		next_mode = CameraMode.INTRO
	elif session.team < 2 and session.health > 0.0:
		followed_target_id = -1
		next_mode = CameraMode.THIRD_PERSON if third_person else CameraMode.FIRST_PERSON
	elif followed_target_id >= 0:
		var target := session.get_target(followed_target_id)
		next_mode = CameraMode.FOLLOW_FIRST_PERSON if follow_first_person and bool(target.alive) else CameraMode.FOLLOW_THIRD_PERSON
	else:
		next_mode = CameraMode.FREE if session.team >= 2 else CameraMode.DEATH
	if next_mode != camera_mode:
		if next_mode == CameraMode.FREE:
			_free_position = camera.global_position
			_free_velocity = Vector3.ZERO
			_camera_yaw = camera.global_rotation.y
			_camera_pitch = camera.global_rotation.x
		elif next_mode == CameraMode.THIRD_PERSON:
			_camera_yaw = rotation.y
			_camera_pitch = head.rotation.x
		camera_mode = next_mode
		camera_mode_changed.emit(camera_mode)

func follow_target(identifier: int) -> bool:
	if session.team < 2 and (session.health > 0.0 or _death_elapsed <= 1.3): return false
	var target := session.get_target(identifier)
	if target.is_empty() or int(target.team) >= 2: return false
	if session.team < 2 and (int(target.team) != session.team or not bool(target.alive)): return false
	followed_target_id = identifier
	_sync_camera_mode()
	return true

func cycle_camera_target(direction: int) -> void:
	if direction == 0 or session.targets.is_empty(): return
	var index := -1 if direction > 0 else 0
	for slot in range(session.targets.size()):
		if int(session.targets[slot].id) == followed_target_id: index = slot
	for attempt in range(session.targets.size()):
		index = posmod(index + signi(direction), session.targets.size())
		if follow_target(int(session.targets[index].id)): return

func stop_following() -> void:
	followed_target_id = -1
	_sync_camera_mode()

func _update_camera_transform() -> void:
	if camera_mode in [CameraMode.INTRO, CameraMode.FIRST_PERSON]:
		camera.transform = Transform3D.IDENTITY
		return
	if camera_mode == CameraMode.FREE:
		camera.global_transform = Transform3D(Basis.from_euler(Vector3(_camera_pitch,_camera_yaw,0.0)),_free_position)
		return
	var center := head.global_position
	if camera_mode == CameraMode.DEATH:
		center=lab.get_player_corpse_center() if lab!=null else global_position+Vector3.UP*0.35
	if followed_target_id >= 0:
		var target := session.get_target(followed_target_id)
		center = Vector3(target.position) + Vector3.UP * (1.35 if str(target.state) == "crouching" else 2.25)
		if camera_mode == CameraMode.FOLLOW_FIRST_PERSON:
			camera.global_transform = Transform3D(Basis.from_euler(Vector3(float(target.get("pitch",0.0)),float(target.get("yaw",0.0)),0.0)),center)
			return
	var distance := 5.0
	if camera_mode == CameraMode.DEATH: distance -= 3.0 * exp(-_death_elapsed)
	var orbit_basis := Basis.from_euler(Vector3(_camera_pitch,_camera_yaw,0.0))
	if world.get_block(Vector3i(center.floor())) != 0:
		for upward in range(1,6):
			var raised := center + Vector3.UP * upward
			if world.get_block(Vector3i(raised.floor())) == 0:
				center = raised
				break
	if camera_mode == CameraMode.THIRD_PERSON: orbit_basis = head.global_basis
	var direction := orbit_basis.z
	var hit := world.cast_voxel(center,direction,distance)
	if hit.hit: distance = maxf(0.05,center.distance_to(hit.position) - 0.3)
	camera.global_position = center + direction * distance
	camera.look_at(center,Vector3.UP)

func _move_free_camera(delta: float) -> void:
	# Client_Update.cpp:279: inertial free camera, .3^dt damping, 10dt
	# acceleration (sprint x3), with 27 short offset rays and a soft bounce.
	_free_velocity *= pow(0.3,delta)
	var displacement := _free_velocity * delta
	var distance := displacement.length()
	if distance > 0.0001:
		var minimum := distance
		var normal := Vector3.ZERO
		for x in range(-1,2):
			for y in range(-1,2):
				for z in range(-1,2):
					var shift := Vector3(x,y,z) * 0.1
					if world.get_block(Vector3i((_free_position + shift).floor())) != 0: continue
					var hit := world.cast_voxel(_free_position + shift,displacement / distance,distance)
					if hit.hit:
						var found := (_free_position + shift).distance_to(hit.position)
						if found < minimum:
							minimum = found
							normal = Vector3(hit.normal)
		_free_position += displacement.normalized() * minimum
		if normal.length_squared() > 0.0:
			_free_position += normal * 0.02
			_free_velocity -= normal * _free_velocity.dot(normal) * 1.2
	for axis in [0,2]:
		var maximum := float(world.dimensions[axis]) - 0.1
		if _free_position[axis] < 0.1 or _free_position[axis] > maximum:
			_free_position[axis] = clampf(_free_position[axis],0.1,maximum)
			_free_velocity[axis] *= -0.2
	_free_position.y = maxf(0.1,_free_position.y)
	var axis := Input.get_vector("left","right","forward","back")
	var vertical := float(Input.is_action_pressed("jump")) - float(Input.is_action_pressed("crouch"))
	var basis := Basis.from_euler(Vector3(_camera_pitch,_camera_yaw,0.0))
	var acceleration := 10.0 * delta * (3.0 if Input.is_action_pressed("sprint") else 1.0)
	_free_velocity += (basis.x * axis.x + basis.z * axis.y + basis.y * vertical) * acceleration
	velocity = _free_velocity

func _play_sound(path: String,gain: float=1.0,offset: Vector3=Vector3.ZERO) -> void:
	if lab!=null and lab.audio!=null:lab.audio.play_local(path,gain,offset)

func _play_world_sound(path: String,gain: float=1.0) -> void:
	if lab!=null and lab.audio!=null:lab.audio.play_spatial(path,global_position+Vector3.UP*(.6 if crouching else 1.05),gain)

func refresh_resources() -> void:
	if _weapon_view!=null:_weapon_view.refresh_resources()
	if _spectator_view!=null:_spectator_view.refresh_resources()

func set_skin(id: String) -> void:
	if id not in OpenSpadesExtensions.get_skins():return
	var replacement:=OpenSpadesExtensions.create_first_person_skin(id,{"player":self,"session":session,"world":world})
	if replacement==null:return
	if _weapon_view!=null:
		_weapon_view.hide()
		_weapon_view.queue_free()
	skin_id=id
	if _spectator_view!=null:_spectator_view.set_skin(id)
	_weapon_view=replacement
	weapon_root.add_child(_weapon_view)
	_connect_skin_signals()
	_weapon_view.set_selection(session.current_tool,session.current_weapon)
	_weapon_view.set_team(session.team,session.get_team_info(session.team).color)
	_weapon_view.set_block_color(block_color)
	_weapon_view.set_ammo(session.magazine,int(session.get_weapon_info().clip_size))
	if session.is_reloading:_weapon_view.reload()

func respawn_at(point: Vector3) -> void:
	_clear_input_state()
	global_position=point
	crouching = false
	head.position.y = 2.25
	(shape.shape as BoxShape3D).size.y = 2.7
	shape.position.y = 1.35
	_native_velocity=Vector3.ZERO
	_motion=SourcePlayerMotion.create_state(point,false,false)
	velocity=Vector3.ZERO
	_last_view_front=-head.global_basis.z
	_step_distance=0.0
	_walk_steps=0
	_sprint_state=0.0
