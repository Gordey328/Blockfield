class_name BlockfieldPlayer
extends CharacterBody3D
## Movement acceleration/friction follows upstream Player::MovePlayer.
## Collision currently uses Godot's box solver; exact sample-based clip is tracked separately.

signal hit_confirmed(part: String, damage: float)
signal notice(message: String)

var world: VoxelWorld
var session: LocalSession
var lab: Node3D
var sensitivity: float = 0.0025
var base_fov: float = 90.0
var aiming := false
var crouching := false
var sprinting := false
var third_person := false
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
	if session == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * sensitivity)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * sensitivity, -1.55, 1.55)
	if event.is_action_pressed("reload"):
		session.reload_weapon()
	if event.is_action_pressed("tool_spade"): session.select_tool(0)
	if event.is_action_pressed("tool_block"): session.select_tool(1)
	if event.is_action_pressed("tool_weapon"): session.select_tool(2)
	if event.is_action_pressed("tool_grenade"): session.select_tool(3)
	if event.is_action_pressed("eyedropper") and world != null:
		var hit := world.cast_voxel(camera.global_position, -camera.global_basis.z, 12.0)
		if hit.hit:
			block_color = VoxelWorld.block_color(world.get_block(hit.cell))
			notice.emit("Picked block color")
	if event.is_action_pressed("view_toggle"):
		third_person = not third_person
	if not controls_enabled:
		return
	if event.is_action_pressed("primary") and session.current_tool == 3:
		_grenade_cooking = session.begin_grenade_cook()
	if event.is_action_released("primary") and _grenade_cooking:
		_throw_grenade()
	if event.is_action_pressed("secondary") and session.current_tool == 1:
		var hit := world.cast_voxel(camera.global_position, -camera.global_basis.z, 12.0)
		if hit.hit: _line_start = hit.cell + hit.normal
	if event.is_action_released("secondary") and session.current_tool == 1 and _line_start.x >= 0:
		_build_line()
		_line_start = Vector3i(-1, -1, -1)

func _physics_process(delta: float) -> void:
	if world == null or session == null:
		return
	_connect_simulation()
	_tool_clock = maxf(0.0, _tool_clock - delta)
	_kick = lerpf(_kick, 0.0, minf(delta * 12.0, 1.0))
	_restore_block_health()
	if not controls_enabled or session.health <= 0:
		_native_velocity.x /= 1.0 + delta * 4.0
		_native_velocity.z /= 1.0 + delta * 4.0
		if session.team < 2:
			_native_velocity.y = (_native_velocity.y - delta) / (1.0 + delta)
			velocity = _native_velocity * 32.0
			move_and_slide()
			if is_on_floor(): _native_velocity.y = 0.0
		session.update_player_position(global_position)
		_update_view(delta)
		return
	var axis := Input.get_vector("left", "right", "forward", "back")
	crouching = Input.is_action_pressed("crouch") and session.team < 2
	sprinting = Input.is_action_pressed("sprint") and not crouching and axis.length() > 0.01
	aiming = Input.is_action_pressed("secondary") and session.current_tool == 2 and not sprinting
	var sneak := Input.is_action_pressed("sneak")
	var camera_height := 0.9 if crouching else 1.8
	head.position.y = lerpf(head.position.y, camera_height, minf(15.0*delta, 1.0))
	(shape.shape as BoxShape3D).size.y = 1.4 if crouching else 2.4
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
	if session.team >= 2:
		var vertical := float(Input.is_action_pressed("jump")) - float(Input.is_action_pressed("crouch"))
		velocity = (movement + Vector3.UP*vertical) * (25.0 if sprinting else 10.0)
		global_position += velocity * delta
		_native_velocity = velocity / 32.0
	else:
		_native_velocity += movement * accel
		_native_velocity.y = (_native_velocity.y - delta) / (1.0 + delta)
		var friction := 1.0 + delta * (4.0 if is_on_floor() else 1.0)
		_native_velocity.x /= friction
		_native_velocity.z /= friction
		if Input.is_action_just_pressed("jump") and is_on_floor():
			_native_velocity.y = 0.36
			_play_sound("Player/Jump")
		var before := global_position
		var fall_speed := -_native_velocity.y
		velocity = _native_velocity * 32.0
		move_and_slide()
		if is_on_floor():
			if fall_speed > 0.58: session.damage_player(pow(fall_speed - 0.58, 2.0) * 4096.0)
			_native_velocity.y = 0.0
		if is_on_wall() and not crouching and not sprinting and head.rotation.x > -0.52:
			_try_step(movement)
		_step_distance += before.distance_to(global_position)
		if is_on_floor() and _step_distance > 2.5 and not sneak and not crouching:
			_step_distance = 0.0
			_play_sound("Player/Footstep1")
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
	_update_view(delta)

func _connect_simulation() -> void:
	if _weapon_view == null:
		_weapon_view = WeaponView.new()
		weapon_root.position = Vector3.ZERO
		weapon_root.add_child(_weapon_view)
	if _connected_session != session:
		_connected_session = session
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
	if not test_move(raised, direction.normalized()*0.3):
		global_position.y += 1.01
		_native_velocity.x *= 0.5
		_native_velocity.z *= 0.5

func _shoot() -> void:
	if not session.fire(): return
	var info: Dictionary = session.get_weapon_info()
	var accumulated_direction := -camera.global_basis.z
	var spread: float = float(info.spread) * (0.5 if aiming else 1.0)
	_play_sound("Weapons/%s/FireLocal" % str(info.name))
	var destroyed_block := false
	for pellet in int(info.pellets):
		# Player::FireWeapon accumulates all pellets into the unnormalized vector.
		accumulated_direction += Vector3(randf()-randf(), randf()-randf(), randf()-randf()) * spread
		var direction := accumulated_direction.normalized()
		var map_hit := world.cast_voxel(camera.global_position, direction, 500.0)
		var distance := camera.global_position.distance_to(map_hit.position) if map_hit.hit else 500.0
		var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position+direction*distance, 2)
		query.collide_with_areas = true
		var result := get_world_3d().direct_space_state.intersect_ray(query)
		var end := camera.global_position+direction*minf(distance, 128.0)
		if not result.is_empty():
			var area: Area3D = result.collider
			if area.has_meta("target_id"):
				var part: String = area.get_meta("hit_part", "torso")
				var horizontal_distance := _horizontal_distance(camera.global_position, result.position)
				var damage := session.damage_target(int(area.get_meta("target_id")), part, horizontal_distance)
				if damage > 0.0: hit_confirmed.emit(part, damage)
				end = result.position
		elif map_hit.hit and _horizontal_distance(camera.global_position, map_hit.position) < 128.0:
			if _damage_block(map_hit.cell, float(info.block), not destroyed_block):
				destroyed_block = true
		if lab != null: lab.spawn_tracer(camera.global_position-camera.global_basis.y*0.12, end)
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
	var hit := world.cast_voxel(camera.global_position, -camera.global_basis.z, 6.0)
	if not dig:
		var reach := minf(3.0, camera.global_position.distance_to(hit.position)) if hit.hit else 3.0
		var query := PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position-camera.global_basis.z*reach,2)
		query.collide_with_areas = true
		var result := get_world_3d().direct_space_state.intersect_ray(query)
		if not result.is_empty() and result.collider.has_meta("target_id"):
			var amount := session.damage_target(int(result.collider.get_meta("target_id")),"melee", _horizontal_distance(camera.global_position, result.position))
			if amount > 0.0: hit_confirmed.emit("melee", amount)
			_play_sound("Weapons/Spade/HitPlayer")
			return
	if hit.hit and _in_reach(hit.cell):
		_play_sound("Weapons/Spade/HitBlock")
		if dig:
			world.remove_blocks([hit.cell+Vector3i.DOWN,hit.cell,hit.cell+Vector3i.UP],true)
		else:
			var before: int = world.get_block(hit.cell)
			_damage_block(hit.cell,55.0)
			if before != 0 and world.get_block(hit.cell)==0: session.recover_block()
		return

func _in_reach(cell: Vector3i) -> bool:
	var diff := (Vector3(cell)+Vector3.ONE*0.5-camera.global_position).abs()
	return maxf(diff.x,maxf(diff.y,diff.z)) < 3.0

func _overlaps_player(cell: Vector3i) -> bool:
	var center := Vector3(cell)+Vector3.ONE*0.5
	return absf(center.x-global_position.x)<0.95 and absf(center.z-global_position.z)<0.95 and center.y>global_position.y-0.5 and center.y<global_position.y+(1.4 if crouching else 2.4)+0.5

func _build_single() -> void:
	if _tool_clock > 0.0: return
	var hit := world.cast_voxel(camera.global_position,-camera.global_basis.z,12.0)
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
	var hit := world.cast_voxel(camera.global_position,-camera.global_basis.z,12.0)
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
	camera.fov = lerpf(camera.fov,base_fov*(0.55 if aiming else 1.0),minf(14.0*delta,1.0))
	camera.position.z = 4.0 if third_person else 0.0
	weapon_root.visible = not third_person and session.team<2 and session.health>0
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
	global_position=point
	_native_velocity=Vector3.ZERO
	velocity=Vector3.ZERO
