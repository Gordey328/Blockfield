class_name BlockfieldPlayer
extends CharacterBody3D
## Movement acceleration/friction follows upstream Player::MovePlayer.
## Collision currently uses Godot's box solver; exact sample-based clip is tracked separately.

signal hit_confirmed(part: String, damage: float)
signal notice(message: String)
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
var base_fov: float = 90.0
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
var block_color := Color("9ea87d")
var _kick := 0.0
var _tool_clock := 0.0
var _step_distance := 0.0
var _line_start := Vector3i(-1, -1, -1)
var _grenade_cooking := false
var _native_velocity := Vector3.ZERO
var _pending_cell := Vector3i(-1, -1, -1)
var _block_health: Dictionary = {}
var _dig_held: bool = false
var _connected_session: LocalSession
var _connected_world: VoxelWorld
var _weapon_view: WeaponView
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

func _unhandled_input(event: InputEvent) -> void:
	if session == null or not controls_enabled:
		return
	_sync_camera_mode()
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_mouse_motion(event.relative)
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
			if _aim_toggled: _play_sound("Weapons/AimDownSightLocal")
	if event.is_action_pressed("primary") and session.current_tool == 3:
		_grenade_cooking = session.begin_grenade_cook()
	if event.is_action_released("primary") and _grenade_cooking:
		_throw_grenade()
	if event.is_action_pressed("secondary") and session.current_tool == 1:
		var hit := world.cast_voxel(get_aim_origin(), get_aim_direction(), 12.0)
		if hit.hit: _line_start = hit.cell + hit.normal
	if event.is_action_released("secondary") and session.current_tool == 1 and _line_start.x >= 0:
		_build_line()
		_line_start = Vector3i(-1, -1, -1)

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
		crouching = false
		sprinting = false
		aiming = false
		if camera_mode == CameraMode.FREE and controls_enabled: _move_free_camera(delta)
		session.update_player_position(_free_position if camera_mode == CameraMode.FREE else global_position)
		world.set_view_position(camera.global_position)
		_update_view(delta)
		return
	# Feet-based Godot collider adaptation; source GetWade uses eye-derived origin.
	wading = global_position.y < world.water_level + 0.5
	if not controls_enabled or session.health <= 0:
		aiming = false
		sprinting = false
		_native_velocity.x /= 1.0 + delta * 4.0
		_native_velocity.z /= 1.0 + delta * 4.0
		if session.team < 2:
			_native_velocity.y = (_native_velocity.y - delta) / (1.0 + delta)
			velocity = _native_velocity * 32.0
			move_and_slide()
			if is_on_floor(): _native_velocity.y = 0.0
			_apply_map_boundaries()
		session.update_player_position(global_position)
		_update_view(delta)
		return
	var axis := Input.get_vector("left", "right", "forward", "back")
	var wants_crouch := Input.is_action_pressed("crouch")
	if wants_crouch != crouching and (wants_crouch or can_stand()):
		# Player::SetInput only shifts the eye when grounded. In the air,
		# shrinking raises feet; uncrouching lowers them if that space is clear.
		if not is_on_floor():
			if wants_crouch: global_position.y += 0.9
			elif _body_fits(global_position - Vector3.UP * 0.9, 2.7): global_position.y -= 0.9
		crouching = wants_crouch
		head.position.y = 1.35 if crouching else 2.25
	sprinting = Input.is_action_pressed("sprint") and not crouching and axis.length() > 0.01
	aiming = (Input.is_action_pressed("secondary") if hold_aim_down_sight else _aim_toggled) \
		and session.current_tool == 2 and not sprinting and not session.is_reloading
	var sneak := Input.is_action_pressed("sneak")
	var camera_height := 1.35 if crouching else 2.25
	head.position.y = lerpf(head.position.y, camera_height, minf(15.0*delta, 1.0))
	(shape.shape as BoxShape3D).size.y = 1.8 if crouching else 2.7
	shape.position.y = (shape.shape as BoxShape3D).size.y * 0.5
	var accel := delta
	if not is_on_floor(): accel *= 0.1
	elif crouching: accel *= 0.3
	elif aiming or sneak: accel *= 0.5
	elif sprinting: accel *= 1.3
	var forward := -global_basis.z
	var right := global_basis.x
	var slowdown := 1.0 - maxf(absf(sin(head.rotation.x)) - 0.65, 0.0) / 0.35 * 0.9
	var movement := right * axis.x + forward * -axis.y * slowdown
	if session.team < 2:
		_native_velocity += movement * accel
		_native_velocity.y = (_native_velocity.y - delta) / (1.0 + delta)
		# Player.cpp:1157: wade overrides ground/air horizontal friction.
		var friction := 1.0 + delta * (6.0 if wading else (4.0 if is_on_floor() else 1.0))
		_native_velocity.x /= friction
		_native_velocity.z /= friction
		if Input.is_action_just_pressed("jump") and is_on_floor():
			_native_velocity.y = 0.36
			_play_sound("Player/WaterJump" if wading else "Player/Jump")
		var before := global_position
		var was_grounded := is_on_floor()
		var fall_speed := -_native_velocity.y
		velocity = _native_velocity * 32.0
		move_and_slide()
		_native_velocity.x = velocity.x / 32.0
		_native_velocity.z = velocity.z / 32.0
		if is_on_floor():
			if not was_grounded and fall_speed > 0.24:
				_native_velocity.x *= 0.5
				_native_velocity.z *= 0.5
				_play_sound("Player/FallHurt" if fall_speed > 0.58 else ("Player/WaterLand" if wading else "Player/Land"))
			if fall_speed > 0.58: session.damage_player(pow(fall_speed - 0.58, 2.0) * 4096.0)
			_native_velocity.y = 0.0
		if is_on_wall() and not crouching and not sprinting and head.rotation.x > -0.52:
			_try_step(movement)
		_apply_map_boundaries()
		_step_distance += before.distance_to(global_position)
		if is_on_floor() and _step_distance > 1.0 / 0.3 and not sneak and not crouching and not aiming:
			_step_distance = 0.0
			_play_sound("Player/Wade%d" % randi_range(1,8) if wading else "Player/Footstep%d" % randi_range(1,8))
			if sprinting and not wading: _play_sound("Player/Run%d" % randi_range(1,12))
		if global_position.y < -5.0: session.damage_player(1000.0)
	session.update_player_position(global_position)
	world.set_view_position(global_position)
	if _pending_cell.x >= 0 and is_on_floor(): _pending_cell = Vector3i(-1,-1,-1)
	if _pending_cell.x >= 0 and not _overlaps_player(_pending_cell):
		_place(_pending_cell)
		_pending_cell = Vector3i(-1,-1,-1)
	var digging := Input.is_action_pressed("secondary") and session.current_tool == 0
	if digging and not _dig_held:
		_tool_clock = 1.0 # Original first dig waits a full secondary interval.
	_dig_held = digging
	if not sprinting and session.team < 2:
		if Input.is_action_pressed("primary"):
			match session.current_tool:
				0:
					if not digging: _spade(false)
				1: _build_single()
				2: _shoot()
		if digging:
			_spade(true)
	if not Input.is_action_pressed("primary") or session.current_tool != 2: _dry_fire_held = false
	_update_view(delta)

func can_stand() -> bool:
	# Source TryUncrouch checks four corner samples. With the retained Godot
	# collider, conservatively test the entire expanded box against voxels.
	return (not is_on_floor() and _body_fits(global_position - Vector3.UP * 0.9, 2.7)) or _body_fits(global_position, 2.7)

func _body_fits(feet: Vector3, height: float) -> bool:
	var low := Vector3i((feet + Vector3(-0.449, 0.01, -0.449)).floor())
	var high := Vector3i((feet + Vector3(0.449, height - 0.01, 0.449)).floor())
	if low.x < 0 or low.z < 0 or high.x >= world.dimensions.x or high.z >= world.dimensions.z: return false
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			for z in range(low.z, high.z + 1):
				if world.get_block(Vector3i(x,y,z)) != 0: return false
	return true

func _apply_map_boundaries() -> void:
	# GameMap::ClipBox: solid horizontal boundaries, empty sky, solid bottom.
	var limited := Vector3(clampf(global_position.x, 0.45, world.dimensions.x - 0.45),
		maxf(global_position.y, 0.0), clampf(global_position.z, 0.45, world.dimensions.z - 0.45))
	for axis in range(3):
		if limited[axis] != global_position[axis]:
			_native_velocity[axis] = 0.0
			velocity[axis] = 0.0
	global_position = limited

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
		if _observed_tool >= 0 and _observed_tool != session.current_tool: _last_tool = _observed_tool
		_observed_tool = session.current_tool
		_observed_weapon = session.current_weapon
		_aim_toggled = false
		aiming = false
		_dry_fire_held = false

func get_aim_down_state() -> float:
	return _aim_down_state

func get_aim_origin() -> Vector3:
	return head.global_position

func get_aim_direction() -> Vector3:
	# Presentation shake and third-person orbit must not alter authoritative rays.
	return -head.global_basis.z

func _effects() -> OpenSpadesEffects:
	return lab.get("effects") as OpenSpadesEffects if lab != null else null

func get_aim_zoom() -> float:
	# Client_Scene.cpp:120: source weapon-specific eased ADS zoom.
	if session.current_tool != 2 or session.health <= 0.0: return 1.0
	var amount: float = [1.4,0.8,0.4][session.current_weapon]
	return 1.0 + (3.0 - 2.0 * pow(_aim_down_state,1.5)) * pow(_aim_down_state,3.0) * amount

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
	if _weapon_view == null:
		_weapon_view = WeaponView.new()
		weapon_root.position = Vector3.ZERO
		weapon_root.add_child(_weapon_view)
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
			_weapon_view.fire())
		session.shot_fired.connect(func():
			if _was_reloading:
				_weapon_view.cancel_reload()
				_was_reloading = false
			_weapon_view.set_ammo(session.magazine, int(session.get_weapon_info().clip_size))
			_weapon_view.fire())
		session.reloaded.connect(func():
			_weapon_view.reload_completed()
			_was_reloading = false)
		session.player_respawned.connect(_clear_input_state)
	if _connected_world != world:
		_connected_world = world
		world.map_loaded.connect(func(_map_name: String): _clear_action_state())
		world.blocks_changed.connect(_on_blocks_changed)

func _clear_action_state() -> void:
	_block_health.clear()
	_clear_input_state()

func _clear_input_state() -> void:
	_pending_cell = Vector3i(-1, -1, -1)
	_line_start = Vector3i(-1, -1, -1)
	_grenade_cooking = false
	_dig_held = false
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

func _try_step(direction: Vector3) -> void:
	if direction.length_squared() < 0.01: return
	var raised := global_transform
	raised.origin.y += 1.01
	var destination := raised.origin + direction.normalized() * 0.3
	if _body_fits(raised.origin, 2.7) and _body_fits(destination, 2.7) and not test_move(raised, direction.normalized()*0.3):
		global_position.y += 1.01
		_native_velocity.x *= 0.5
		_native_velocity.z *= 0.5

func _shoot() -> void:
	if not session.fire():
		# Weapon.cpp:144: play once on the transition into an empty trigger hold.
		var slow_reload := bool(session.get_weapon_info().slow_reload)
		if session.magazine <= 0 and not session.unlimited_ammo and session.fire_cooldown <= 0.0 \
			and (not session.is_reloading or slow_reload) and not _dry_fire_held:
			_dry_fire_held = true
			_play_sound("Weapons/DryFire")
			dry_fired.emit()
		return
	_dry_fire_held = false
	var info: Dictionary = session.get_weapon_info()
	var origin := get_aim_origin()
	var accumulated_direction := get_aim_direction()
	var spread: float = float(info.spread) * (0.5 if aiming else 1.0)
	_play_sound("Weapons/%s/FireLocal" % str(info.name))
	var effects := _effects()
	if effects != null:
		var muzzle := _weapon_view.get_muzzle_transform().origin if _weapon_view != null and camera_mode == CameraMode.FIRST_PERSON else origin + accumulated_direction * 0.5
		effects.muzzle_fire(muzzle,accumulated_direction,session.current_weapon)
		if session.current_weapon != 2:
			effects.eject_shell(muzzle,accumulated_direction,head.global_basis.x,head.global_basis.y,session.current_weapon)
	var destroyed_block := false
	for pellet in int(info.pellets):
		# Player::FireWeapon accumulates all pellets into the unnormalized vector.
		accumulated_direction += Vector3(randf()-randf(), randf()-randf(), randf()-randf()) * spread
		var direction := accumulated_direction.normalized()
		var map_hit := world.cast_voxel(origin, direction, 500.0)
		var distance := origin.distance_to(map_hit.position) if map_hit.hit else 500.0
		var query := PhysicsRayQueryParameters3D.create(origin, origin+direction*distance, 2)
		query.collide_with_areas = true
		var result := get_world_3d().direct_space_state.intersect_ray(query)
		var end := origin+direction*minf(distance, 128.0)
		if not result.is_empty():
			var area: Area3D = result.collider
			if area.has_meta("target_id"):
				var part: String = area.get_meta("hit_part", "torso")
				var horizontal_distance := _horizontal_distance(origin, result.position)
				var damage := session.damage_target(int(area.get_meta("target_id")), part, horizontal_distance)
				if damage > 0.0:
					hit_confirmed.emit(part, damage)
					if effects != null: effects.blood(result.position)
				end = result.position
		elif map_hit.hit and _horizontal_distance(origin, map_hit.position) < 128.0:
			if effects != null:
				effects.block_hit(map_hit.position,Vector3(map_hit.normal),VoxelWorld.block_color(world.get_block(map_hit.cell)),map_hit.position.y <= world.water_level + 0.2)
			if _damage_block(map_hit.cell, float(info.block), not destroyed_block):
				destroyed_block = true
		if effects != null:
			effects.tracer(origin,end,session.current_weapon,camera_mode == CameraMode.FIRST_PERSON)
		elif lab != null: lab.spawn_tracer(origin-head.global_basis.y*0.12, end)
	var recoil: Vector3 = info.recoil
	var multiplier := 0.5 if crouching else 1.0
	head.rotation.x = clampf(head.rotation.x+recoil.y*multiplier, -1.55,1.55)
	rotate_y(randf_range(-recoil.x,recoil.x)*multiplier)
	_kick = 0.12
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
	_tool_clock = 1.0 if dig else 0.2
	if _weapon_view != null: _weapon_view.fire()
	_play_sound("Weapons/Spade/Miss")
	var origin := get_aim_origin()
	var direction := get_aim_direction()
	var hit := world.cast_voxel(origin, direction, 6.0)
	if not dig:
		var reach := minf(3.0, origin.distance_to(hit.position)) if hit.hit else 3.0
		var query := PhysicsRayQueryParameters3D.create(origin,origin+direction*reach,2)
		query.collide_with_areas = true
		var result := get_world_3d().direct_space_state.intersect_ray(query)
		if not result.is_empty() and result.collider.has_meta("target_id"):
			var amount := session.damage_target(int(result.collider.get_meta("target_id")),"melee", _horizontal_distance(origin, result.position))
			if amount > 0.0: hit_confirmed.emit("melee", amount)
			_play_sound("Weapons/Spade/HitPlayer")
			return
	if hit.hit and _in_reach(hit.cell):
		_play_sound("Weapons/Spade/HitBlock")
		var effects := _effects()
		if effects != null: effects.block_hit(hit.position,Vector3(hit.normal),VoxelWorld.block_color(world.get_block(hit.cell)))
		if dig:
			world.remove_blocks([hit.cell+Vector3i.DOWN,hit.cell,hit.cell+Vector3i.UP],true)
		else:
			var before: int = world.get_block(hit.cell)
			_damage_block(hit.cell,55.0)
			if before != 0 and world.get_block(hit.cell)==0: session.recover_block()
		return

func _in_reach(cell: Vector3i) -> bool:
	var diff := (Vector3(cell)+Vector3.ONE*0.5-get_aim_origin()).abs()
	return maxf(diff.x,maxf(diff.y,diff.z)) < 3.0

func _overlaps_player(cell: Vector3i) -> bool:
	var center := Vector3(cell)+Vector3.ONE*0.5
	return absf(center.x-global_position.x)<0.95 and absf(center.z-global_position.z)<0.95 and center.y>global_position.y-0.5 and center.y<global_position.y+(1.8 if crouching else 2.7)+0.5

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
			result.pending = _line_start.x < 0 and not is_on_floor()
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
		if not is_on_floor(): _pending_cell=cell
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
		notice.emit("The line has no support")
		return
	var hit := world.cast_voxel(get_aim_origin(),get_aim_direction(),12.0)
	if not hit.hit: return
	var end: Vector3i = hit.cell+hit.normal
	if not _in_reach(end):
		notice.emit("Line endpoint is out of reach")
		return
	var cells := _cube_line(_line_start, end, 256)
	if cells.size() > 50 or (not session.unlimited_ammo and cells.size() > session.blocks):
		notice.emit("Insufficient blocks for this line")
		return
	for cell in cells:
		if not world.is_in_bounds(cell) or cell.y <= 1 or _overlaps_player(cell):
			notice.emit("Invalid block line")
			return
	if not session.use_block(cells.size()): return
	for cell in cells:
		if world.get_block(cell) == 0:
			world.set_block(cell, VoxelWorld.pack_color(block_color))
	_tool_clock = 0.5
	if _weapon_view != null: _weapon_view.fire()
	_play_sound("Weapons/Block/Build")

func _cube_line(start: Vector3i, end: Vector3i, limit: int) -> Array[Vector3i]:
	# World::CubeLine, with source (x,y,z-down) axes mapped to Godot (x,y-up,z).
	var difference := end - start
	var dominant := maxi(absi(difference.x), maxi(absi(difference.y), absi(difference.z)))
	var increment := Vector3i.ZERO
	var next_crossing := Vector3i.ZERO
	var step := Vector3i(1 if difference.x >= 0 else -1, 1 if difference.y >= 0 else -1, 1 if difference.z >= 0 else -1)
	for axis in range(3):
		increment[axis] = int(float(dominant * 1024) / absi(difference[axis])) if difference[axis] != 0 else 0x3fffffff
		next_crossing[axis] = increment[axis] - int(increment[axis] / 2) if step[axis] > 0 else int(increment[axis] / 2)
	var cells: Array[Vector3i] = []
	var cell := start
	while cells.size() < limit and world.is_in_bounds(cell):
		cells.append(cell)
		if cell == end: break
		var axis := 1 if next_crossing.y <= next_crossing.x and next_crossing.y <= next_crossing.z else (0 if next_crossing.x < next_crossing.z else 2)
		cell[axis] += step[axis]
		next_crossing[axis] += increment[axis]
	return cells

func _throw_grenade() -> void:
	_grenade_cooking=false
	session.release_grenade()

func _update_view(delta: float) -> void:
	_aim_down_state = clampf(_aim_down_state + delta * (8.0 if aiming else -3.0),0.0,1.0)
	_sync_camera_mode()
	_update_camera_transform()
	var effects := _effects()
	if effects != null: camera.rotation += effects.get_camera_rotation()
	var zoom := get_aim_zoom() if camera_mode == CameraMode.FIRST_PERSON else 1.0
	camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(clampf(base_fov,45.0,90.0)) * 0.5) / zoom))
	weapon_root.visible = camera_mode == CameraMode.FIRST_PERSON and session.team<2 and session.health>0
	if _weapon_view == null: return
	_weapon_view.set_selection(session.current_tool, session.current_weapon)
	_weapon_view.set_team(session.team)
	_weapon_view.set_block_color(block_color)
	_weapon_view.set_ammo(session.magazine, int(session.get_weapon_info().clip_size))
	_weapon_view.set_grenade_cook(session.grenade_cook_time if session.is_cooking_grenade else 0.0)
	_weapon_view.set_spade_action(_dig_held, 1.0 - clampf(_tool_clock, 0.0, 1.0))
	if session.is_reloading and not _was_reloading:
		_weapon_view.reload()
		_play_sound("Weapons/%s/ReloadLocal" % str(session.get_weapon_info().name))
	elif not session.is_reloading and _was_reloading:
		_weapon_view.cancel_reload()
	_was_reloading = session.is_reloading
	_weapon_view.update_pose(delta, aiming, sprinting, crouching, velocity.length(), session.get_reload_progress())

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
	if camera_mode == CameraMode.DEATH: center = global_position + Vector3.UP * 0.35
	if followed_target_id >= 0:
		var target := session.get_target(followed_target_id)
		center = Vector3(target.position) + Vector3.UP * (1.5 if str(target.state) == "crouching" else 2.35)
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

func _play_sound(path: String) -> void:
	if path.ends_with("FireLocal") and not ResourceLoader.exists("res://assets/openspades/sounds/%s.ogg" % path):
		path = path.trim_suffix("FireLocal") + "FireStereo"
	for extension in ["ogg","wav","opus"]:
		var full_path := "res://assets/openspades/sounds/%s.%s" % [path,extension]
		if ResourceLoader.exists(full_path):
			var audio:=AudioStreamPlayer.new()
			audio.stream=load(full_path)
			audio.volume_db=-8.0
			add_child(audio)
			audio.finished.connect(audio.queue_free)
			audio.play()
			return

func respawn_at(point: Vector3) -> void:
	_clear_input_state()
	global_position=point
	crouching = false
	head.position.y = 2.25
	(shape.shape as BoxShape3D).size.y = 2.7
	shape.position.y = 1.35
	_native_velocity=Vector3.ZERO
	velocity=Vector3.ZERO
