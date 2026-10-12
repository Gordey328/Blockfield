class_name OpenSpadesCorpse
extends Node3D
## GPL-3.0-or-later. Adapted from OpenSpades v0.1.3 Sources/Client/Corpse.cpp.
## Source nine-point spring body, not Godot's unrelated rigid-body ragdoll solver.
const MODELS = preload("res://presentation/openspades_models.gd")
const VOXEL_WORLD_SCRIPT = preload("res://world/voxel_world.gd")
const VOXEL_DATA_SCRIPT = preload("res://world/voxel_data.gd")
const COLLISION_AXES: Array[int] = [0,2,1]
const HEAD_POINTS: Array[int] = [0,1,8]
const MAX_QUERY_CELLS: int = 256
const WORLD_AXES := Basis(Vector3.RIGHT,Vector3.BACK,Vector3.DOWN)
const MODEL_AXES_INVERSE := MODELS.SOURCE_AXES
const EDGE_PAIRS := [[0,1],[1,2],[2,3],[3,0],[0,4],[1,5],[2,6],[3,7]]
const LENGTHS := [[0,1,0.8],[2,3,0.8],[0,3,0.9],[1,2,0.9],
	[0,2,1.204],[1,3,1.204],[4,0,1.0],[5,1,1.0],[6,2,1.0],[7,3,1.0]]
const LINES := [[0,1],[1,2],[2,3],[3,0],[0,2],[1,3],[0,4],[1,5],[2,6],[3,7]]
enum Point { TORSO1,TORSO2,TORSO3,TORSO4,ARM1,ARM2,LEG1,LEG2,HEAD }

class LineRay extends RefCounted:
	var hit: bool = false
	var start_solid: bool = false
	var position := Vector3.ZERO
	var cell := Vector3i.ZERO
	var normal := Vector3i.ZERO

var player_id := -1
var team := 0
var color := MODELS.TEAM_COLORS[0]
var world: Node3D
var line_collision_enabled := true
var positions := PackedVector3Array()
var velocities := PackedVector3Array()
var last_positions := PackedVector3Array()
var last_forces := PackedVector3Array()
var simulation_time := 0.0
var _edge_velocities := PackedVector3Array()
var _edge_initialized := PackedByteArray()
var _parts: Dictionary = {}
var _active := false
var _step_world: VoxelWorld
var _step_cache_enabled: bool = false
var _last_step_cache_enabled: bool = false
var _step_cells: Dictionary[Vector3i,bool] = {}
var _step_dt: float = -1.0
var _step_damp: float = 1.0
var _step_vertical_damp: float = 1.0
var _step_spring_damp: float = 0.0
var _step_head_damp: float = 0.0
var _step_dimensions := Vector3i.ZERO
var _step_water_level: float = 1.0
var _first_line_ray: LineRay = LineRay.new()
var _second_line_ray: LineRay = LineRay.new()
var _static_mode: bool = false
var _static_pose_ready: bool = false
var _static_anchor := Vector3.ZERO
var _static_yaw: float = 0.0
var _static_pose := Transform3D.IDENTITY
var _static_center := Vector3.ZERO
var _static_points := PackedVector3Array()

func setup(voxel_world: Node3D, state: Dictionary) -> void:
	clear()
	world = voxel_world
	player_id = int(state.get("player_id",-1))
	team = clampi(int(state.get("team",0)),0,1)
	color = state.get("color",MODELS.TEAM_COLORS[team])
	var feet: Vector3 = state.get("feet_position",Vector3.ZERO)
	var yaw := float(state.get("yaw",0.0))
	var crouch := bool(state.get("crouch",false))
	if not feet.is_finite() or not is_finite(yaw):
		return
	top_level = true
	transform = Transform3D.IDENTITY
	positions.resize(9)
	velocities.resize(9)
	last_positions.resize(9)
	last_forces.resize(9)
	_edge_velocities.resize(8)
	_edge_initialized.resize(8)
	var lower := Transform3D(Basis(Vector3.UP,yaw),feet + Vector3.UP*(0.7 if crouch else 1.1))
	if crouch: lower.origin += Vector3.UP*0.4
	var torso := lower
	torso.origin += Vector3.UP*(0.3 if crouch else 1.1)
	var local_points: Array = [Vector3(0.4,-0.15,0.1),Vector3(-0.4,-0.15,0.1),Vector3(-0.4,0.8,0.7),Vector3(0.4,0.8,0.7)] if crouch else [Vector3(0.4,0,0.1),Vector3(-0.4,0,0.1),Vector3(-0.4,0,1),Vector3(0.4,0,1)]
	for index in range(4): positions[index] = torso * (WORLD_AXES*local_points[index])
	positions[Point.ARM1] = torso * (WORLD_AXES*Vector3(0.2,-0.4,0.2))
	positions[Point.ARM2] = torso * (WORLD_AXES*Vector3(-0.2,-0.4,0.2))
	positions[Point.LEG1] = lower * (WORLD_AXES*Vector3(-0.4,0.1 if crouch else 0,1))
	positions[Point.LEG2] = lower * (WORLD_AXES*Vector3(0.4,0.1 if crouch else 0,1))
	positions[Point.HEAD] = (positions[0]+positions[1])*0.5 + Vector3.UP*0.6
	var rng := RandomNumberGenerator.new()
	if state.has("seed"): rng.seed = int(state.seed)
	else: rng.randomize()
	for index in range(9):
		velocities[index] = Vector3((rng.randf()-rng.randf())*2.0,0,(rng.randf()-rng.randf())*2.0)
		last_positions[index] = positions[index]
		last_forces[index] = Vector3.ZERO
	_active = true
	add_impulse(state.get("velocity",Vector3.ZERO)) # Already world m/s, not native velocity /32.
	add_impulse(state.get("impulse",Vector3.ZERO))
	refresh_resources()

func setup_static(voxel_world: Node3D, state: Dictionary) -> void:
	# Production uses the original already-prone Dead model. Retain setup/step
	# independently for the source-physics oracle and explicit legacy callers.
	clear()
	world = voxel_world
	player_id = int(state.get("player_id",-1))
	team = clampi(int(state.get("team",0)),0,1)
	color = state.get("color",MODELS.TEAM_COLORS[team])
	var feet: Vector3 = state.get("feet_position",Vector3.ZERO)
	var yaw: float = float(state.get("yaw",0.0))
	if not feet.is_finite() or not is_finite(yaw):return
	top_level = true
	transform = Transform3D.IDENTITY
	_static_mode = true
	_static_yaw = yaw
	_static_anchor = feet
	# One bounded vertical placement query, never a per-frame contact solver.
	var floor_hit: Dictionary = _ray(feet+Vector3.UP*.05,Vector3(feet.x,-1.0,feet.z),128)
	if bool(floor_hit.hit) and not bool(floor_hit.start_solid) and Vector3i(floor_hit.normal).y > 0:
		_static_anchor.y = Vector3(floor_hit.position).y
	_active = true
	refresh_resources()

func is_static() -> bool:
	return _static_mode

func clear() -> void:
	for part: Node3D in _parts.values():
		part.hide()
		part.queue_free()
	_parts.clear()
	positions.clear()
	velocities.clear()
	last_positions.clear()
	last_forces.clear()
	_edge_velocities.clear()
	_edge_initialized.clear()
	simulation_time = 0.0
	_active = false
	_static_mode = false
	_static_pose_ready = false
	_static_points.clear()
	_static_center = Vector3.ZERO

func refresh_resources() -> void:
	for part: Node3D in _parts.values():
		part.hide()
		part.queue_free()
	_parts.clear()
	if not _active:
		return
	if _static_mode:
		var part: Node3D = MODELS.create("Player/Dead")
		part.name = "StaticDead"
		add_child(part)
		MODELS.set_tint(part,color)
		_parts["Dead"] = part
		var local_bounds: AABB = _static_model_bounds(part,Transform3D.IDENTITY)
		if not _static_pose_ready:
			# Same mapped native basis as CharacterView's static Dead fallback,
			# with the captured yaw and bottom of its mesh resting on the floor.
			var basis := Basis(Vector3.UP,_static_yaw)*WORLD_AXES*Basis.IDENTITY.scaled(Vector3.ONE*.1)*MODEL_AXES_INVERSE
			var rotated: AABB = Transform3D(basis,Vector3.ZERO)*local_bounds
			_static_pose = Transform3D(basis,_static_anchor+Vector3.UP*(.01-rotated.position.y))
			_static_pose_ready = true
		part.transform = _static_pose
		_static_center = _static_pose*local_bounds.get_center()
		_static_points.resize(9)
		for index: int in range(8):_static_points[index] = _static_pose*local_bounds.get_endpoint(index)
		_static_points[8] = _static_center
		return
	for name in ["Torso","Head","Arm1","Arm2","Leg1","Leg2"]:
		var model: String = "Arm" if name.begins_with("Arm") else ("Leg" if name.begins_with("Leg") else name)
		var part := MODELS.create("Player/"+model)
		part.name = name
		add_child(part)
		MODELS.set_tint(part,color)
		_parts[name] = part
	_update_models()

func _static_model_bounds(node: Node3D, local: Transform3D) -> AABB:
	var bounds := AABB()
	var found: bool = false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		bounds = local*(node as MeshInstance3D).get_aabb()
		found = true
	for child: Node in node.get_children():
		if not child is Node3D:continue
		var part := child as Node3D
		var child_bounds: AABB = _static_model_bounds(part,local*part.transform)
		if child_bounds.size == Vector3.ZERO:continue
		bounds = bounds.merge(child_bounds) if found else child_bounds
		found = true
	return bounds

func add_impulse(impulse: Vector3) -> void:
	if _static_mode:return
	if not impulse.is_finite():
		return
	for index in range(velocities.size()): velocities[index] += impulse

func get_center() -> Vector3:
	if _static_mode:return _static_center
	var center := Vector3.ZERO
	for position in positions: center += position
	return center/float(positions.size()) if not positions.is_empty() else Vector3.ZERO

func is_visible_from(eye: Vector3) -> bool:
	if not _active or eye.distance_to(get_center()) > 150.0:
		return false
	# Use actual finite segments. Native Corpse's legacy CastRay prefilter passes an
	# endpoint to a direction API; retaining it would invert/misclassify visibility.
	for position: Vector3 in _static_points if _static_mode else positions:
		if not _ray(eye,position,256).hit: return true
	return false

func step(delta: float) -> void:
	if _static_mode:return
	if not _active or not is_finite(delta) or delta <= 0:
		return
	# Native client uses four substeps per render frame. Keep that at >=60 Hz and
	# add substeps on slow frames; cap a paused-tab resume to .25 s of cosmetic work.
	var elapsed := minf(delta,0.25)
	var substeps := maxi(4,ceili(elapsed*240.0))
	var dt := elapsed/float(substeps)
	# The whole source spring step is synchronous. Repeated point/line queries
	# see one map version; no cache survives into another rendered frame.
	_step_world = world as VoxelWorld if is_instance_valid(world) else null
	var own_script: Script = get_script()
	_step_cache_enabled = _step_world != null and own_script.get_base_script() == null and _step_world.get_script() == VOXEL_WORLD_SCRIPT and _step_world.data.get_script() == VOXEL_DATA_SCRIPT
	_last_step_cache_enabled = _step_cache_enabled
	if _step_cache_enabled:
		_step_dimensions = _step_world.dimensions
		_step_water_level = _step_world.water_level
	else:
		# Custom callbacks may replace world mid-step. Each following query must
		# read the live adapter, and inherited corpses retain virtual _ray calls.
		_step_world = null
	_step_cells.clear()
	_step_dt = dt
	_step_damp = pow(0.9,dt)
	_step_vertical_damp = pow(0.371,dt)
	_step_spring_damp = 1.0-pow(0.1,dt)
	_step_head_damp = 1.0-pow(0.05,dt)
	for index in range(substeps): _substep(dt)
	_step_world = null
	_step_cache_enabled = false
	_step_cells.clear()
	_step_dt = -1.0
	simulation_time += elapsed
	_update_models()

func _substep(dt: float) -> void:
	var damp: float = _step_damp if dt == _step_dt else pow(0.9,dt)
	var damp_vertical: float = _step_vertical_damp if dt == _step_dt else pow(0.371,dt)
	var water_level := 1.0
	if _step_cache_enabled:
		water_level = _step_water_level
	elif _step_world != null:
		water_level = _step_world.water_level
	elif is_instance_valid(world):
		var value = world.get("water_level")
		if value != null: water_level = float(value)
	for index in range(9):
		var old := last_positions[index]
		var position := positions[index] + velocities[index]*dt
		var velocity := velocities[index]
		if position.y < water_level:
			velocity.y += dt*6.0
			velocity *= damp
		else:
			velocity.y = (velocity.y-dt*32.0)*damp_vertical
		if not _clip(old):
			# Native X/Y/Z axes map to Godot X/Z/Y, including collision order.
			for axis: int in COLLISION_AXES:
				var sample := old
				for completed_axis: int in COLLISION_AXES:
					sample[completed_axis] = position[completed_axis]
					if completed_axis == axis: break
				if _clip(sample):
					velocity[axis] = -velocity[axis]*0.2
					if absf(velocity[axis]) < 0.3: velocity[axis] = 0.0
					position[axis] = old[axis]
					for other in range(3):
						if other != axis: velocity[other] *= 0.5
		positions[index] = position
		velocities[index] = velocity
		last_positions[index] = position
		last_forces[index] = velocity
	_apply_constraints(dt)
	for index in range(9): last_forces[index] = velocities[index]-last_forces[index]

func _apply_constraints(dt: float) -> void:
	for index in range(8):
		var a: int = EDGE_PAIRS[index][0]
		var b: int = EDGE_PAIRS[index][1]
		var difference := velocities[b]-velocities[a]
		if _edge_initialized[index]:
			var force := (_edge_velocities[index]-difference)*0.5
			velocities[b] += force
			velocities[a] -= force
		else: _edge_initialized[index] = 1
		_edge_velocities[index] = difference
	for spring in LENGTHS: _spring(spring[0],spring[1],spring[2],dt)
	_angle_spring(0,4,2,-1.0,0.6,dt)
	_angle_spring(1,5,3,-1.0,0.6,dt)
	_angle_spring(2,6,1,-1.0,-0.2,dt)
	_angle_spring(3,7,0,-1.0,-0.2,dt)
	_head_spring(dt)
	if line_collision_enabled:
		for line in LINES: _line_collision(line[0],line[1],dt)

func _spring(a: int, b: int, distance: float, dt: float) -> void:
	var difference := positions[b]-positions[a]
	var length := difference.length()
	if length < 0.000001: return
	var correction := difference/length*(distance-length)
	var force := correction*dt*50.0
	velocities[b] += force
	velocities[a] -= force
	positions[b] += correction*0.5
	positions[a] -= correction*0.5
	var midpoint := (velocities[a]+velocities[b])*0.5
	var damp: float = _step_spring_damp if dt == _step_dt else 1.0-pow(0.1,dt)
	velocities[a] += (midpoint-velocities[a])*damp
	velocities[b] += (midpoint-velocities[b])*damp

func _head_spring(dt: float) -> void:
	var difference := positions[8]-(positions[0]+positions[1])*0.5
	var length := difference.length()
	if length < 0.000001: return
	var force := difference/length*(0.6-length)*dt*50.0
	velocities[8] += force
	velocities[0] -= force*0.5
	velocities[1] -= force*0.5
	var midpoint := (velocities[0]+velocities[1])*0.25+velocities[8]*0.5
	var damp: float = _step_head_damp if dt == _step_dt else 1.0-pow(0.05,dt)
	for index: int in HEAD_POINTS: velocities[index] += (midpoint-velocities[index])*damp

func _angle_spring(base: int, a: int, b: int, minimum: float, maximum: float, dt: float) -> void:
	var first := positions[a]-positions[base]
	var second := positions[b]-positions[base]
	var dot := first.dot(second)/(first.length()*second.length()+0.0000001)
	if dot >= minimum and dot <= maximum: return
	var difference := positions[b]-positions[a]
	var axis := first.cross(first.cross(difference)).normalized()
	var bound := maximum if dot > maximum else minimum
	var strength := (acos(clampf(dot,-1.0,1.0))-acos(bound))*20.0*dt
	# Native implementation explicitly multiplies the second axis by zero.
	var force := axis*strength
	velocities[b] += force
	velocities[base] -= force

func _line_collision(a: int, b: int, dt: float) -> void:
	# Pure production queries cannot re-enter this cast. Custom worlds keep the
	# original owned Dictionary path, including virtual _ray overrides.
	if _step_cache_enabled:
		_cast_ray_into(last_positions[a],last_positions[b],8,_first_line_ray)
		if not _first_line_ray.hit or _first_line_ray.start_solid:return
		_cast_ray_into(last_positions[b],last_positions[a],8,_second_line_ray)
		if not _second_line_ray.hit or _second_line_ray.start_solid:return
		_resolve_line_collision(a,b,dt,_first_line_ray.position,_second_line_ray.position,
			_first_line_ray.normal,_second_line_ray.normal,_first_line_ray.cell)
		return
	var first := _ray(last_positions[a],last_positions[b],8)
	if not first.hit or first.start_solid: return
	var second := _ray(last_positions[b],last_positions[a],8)
	if not second.hit or second.start_solid: return
	_resolve_line_collision(a,b,dt,first.position,second.position,first.normal,second.normal,first.cell)

func _resolve_line_collision(a: int, b: int, dt: float, first_position: Vector3,
		second_position: Vector3, first_normal: Vector3i, second_normal: Vector3i,
		first_cell: Vector3i) -> void:
	var length_squared := positions[b].distance_squared_to(positions[a])
	if (first_position-last_positions[a]).dot(last_positions[b]-last_positions[a]) > length_squared: return
	if (second_position-last_positions[b]).dot(last_positions[a]-last_positions[b]) > length_squared: return
	var penetration: float = first_position.distance_to(second_position)
	var direction: Vector3 = Vector3(first_normal+second_normal)
	if direction == Vector3.ZERO:
		var escape := _escape(first_cell,Vector3i(positions[a].floor()),Vector3i(positions[b].floor()))
		if not escape.ok: return
		direction = escape.direction
		penetration = escape.distance+0.1
	for index in [a,b]:
		var velocity := velocities[index]
		velocity -= direction*minf(direction.dot(velocity),0.0)
		velocity += direction*dt*penetration*5.0
		velocity -= (velocity-direction*direction.dot(velocity))*0.2
		velocities[index] = velocity

func _escape(hit: Vector3i, a: Vector3i, b: Vector3i) -> Dictionary:
	var best := 1000.0
	var direction := Vector3.ZERO
	# Source CheckEscape takes integer endpoints: negative source directions have
	# distance zero, positive ones two. Preserve that source choice/order.
	for candidate in [Vector3i.RIGHT,Vector3i.LEFT,Vector3i.BACK,Vector3i.FORWARD,Vector3i.DOWN,Vector3i.UP]:
		if _solid_wrapped(hit+candidate) or _solid_wrapped(a+candidate) or _solid_wrapped(b+candidate): continue
		var distance := 0.0 if candidate in [Vector3i.LEFT,Vector3i.FORWARD,Vector3i.UP] else 2.0
		if distance < best: best = distance; direction = Vector3(candidate)
	return {"ok":best <= 10.0,"direction":direction,"distance":best}

func _clip(position: Vector3) -> bool:
	if _step_cache_enabled:
		# Match VoxelData.clip_box exactly before using the shared occupancy key.
		var cell := Vector3i(position.floor())
		var size: Vector3i = _step_dimensions
		if cell.x < 0 or cell.z < 0 or cell.x >= size.x or cell.z >= size.z or cell.y < 0:return true
		if cell.y >= size.y:return false
		if cell.y == 0:cell.y = 1
		return _query_cell(cell)
	if _step_world != null:return _step_world.clip_box(position)
	if not is_instance_valid(world):return false
	if world is VoxelWorld:return (world as VoxelWorld).clip_box(position)
	return bool(world.call("clip_box",position)) if is_instance_valid(world) and world.has_method("clip_box") else false

func _solid_wrapped(cell: Vector3i) -> bool:
	if _step_world != null:
		var size: Vector3i = _step_dimensions if _step_cache_enabled else _step_world.dimensions
		if cell.y < 0:return true
		if cell.y >= size.y:return false
		cell.x = posmod(cell.x,size.x)
		cell.z = posmod(cell.z,size.z)
		return _query_cell(cell) if _step_cache_enabled else _step_world.get_block(cell) != 0
	if not is_instance_valid(world):return false
	if world is VoxelWorld:
		var typed_world := world as VoxelWorld
		var size: Vector3i = typed_world.dimensions
		if cell.y < 0:return true
		if cell.y >= size.y:return false
		cell.x = posmod(cell.x,size.x)
		cell.z = posmod(cell.z,size.z)
		return typed_world.get_block(cell) != 0
	if not is_instance_valid(world) or not world.has_method("get_block"): return false
	var size_value = world.get("dimensions")
	if size_value is Vector3i:
		var size: Vector3i = size_value
		if cell.y < 0: return true
		if cell.y >= size.y: return false
		cell.x = posmod(cell.x,size.x)
		cell.z = posmod(cell.z,size.z)
	return int(world.call("get_block",cell)) != 0

func _query_cell(cell: Vector3i) -> bool:
	if not _step_cache_enabled:
		if not is_instance_valid(world):return false
		return (world as VoxelWorld).get_block(cell) != 0 if world is VoxelWorld else (world.has_method("get_block") and int(world.call("get_block",cell)) != 0)
	if _step_cells.has(cell):return _step_cells[cell]
	var solid: bool = _step_world.get_block(cell) != 0
	if _step_cells.size() < MAX_QUERY_CELLS:_step_cells[cell] = solid
	return solid

func _ray(origin: Vector3, endpoint: Vector3, max_steps: int) -> Dictionary:
	# Inspection/visibility callers own a fresh result. A local record also
	# preserves correctness if a custom world's query re-enters this helper.
	var result := LineRay.new()
	_cast_ray_into(origin,endpoint,max_steps,result)
	return {"hit":result.hit,"start_solid":result.start_solid,"position":result.position,"cell":result.cell,"normal":result.normal}

func _cast_ray_into(origin: Vector3, endpoint: Vector3, max_steps: int, result: LineRay) -> void:
	result.hit = false
	result.start_solid = false
	result.position = endpoint
	result.cell = Vector3i.ZERO
	result.normal = Vector3i.ZERO
	var difference := endpoint-origin
	var distance := difference.length()
	if distance < 0.000001: return
	var ray := difference/distance
	var cell := Vector3i(origin.floor())
	if _solid_wrapped(cell):
		result.hit = true
		result.start_solid = true
		result.position = origin
		result.cell = cell
		return
	var step := Vector3i(signi(roundi(ray.x*1000000)),signi(roundi(ray.y*1000000)),signi(roundi(ray.z*1000000)))
	var delta := Vector3(INF,INF,INF)
	var next := Vector3(INF,INF,INF)
	for axis in range(3):
		if absf(ray[axis]) > 0.000001:
			delta[axis] = absf(1.0/ray[axis])
			var boundary := float(cell[axis]+(1 if step[axis] > 0 else 0))
			next[axis] = (boundary-origin[axis])/ray[axis]
	for index in range(max_steps):
		var axis := 0
		if next.z < next[axis]: axis = 2
		if next.y < next[axis]: axis = 1
		var traveled := next[axis]
		if traveled > distance: return
		next[axis] += delta[axis]
		cell[axis] += step[axis]
		if _solid_wrapped(cell):
			var normal := Vector3i.ZERO
			normal[axis] = -step[axis]
			result.hit = true
			result.position = origin+ray*traveled
			result.cell = cell
			result.normal = normal
			return

func _update_models() -> void:
	if _static_mode:return
	if not _active or _parts.is_empty(): return
	# Build the native source bases, then W*native*S^-1 for imported mesh vectors.
	var source := PackedVector3Array()
	for point in positions: source.append(WORLD_AXES.inverse()*point)
	var x := ((source[0]-source[1]+source[3]-source[2])*0.5).normalized()
	var y := ((source[2]+source[3]-source[0]-source[1])*0.5).normalized()
	var z := x.cross(y).normalized()
	y = x.cross(z).normalized()
	var origin := (source[0]+source[1])*0.5
	var torso := Transform3D(Basis(x,-z,-y),origin)
	if absf(torso.basis.determinant()) < 0.000001: return
	_apply_model("Torso",torso.basis,torso.origin)
	var head_z := (-torso.basis.z).normalized() # Native overrides head point direction.
	var head_y := (source[1]-source[0]).cross(head_z).normalized()
	var head_x := head_y.cross(head_z).normalized()
	_apply_model("Head",Basis(-head_x,head_y,-head_z),origin)
	for index in range(2):
		var arm_point := 4+index
		var shoulder := index
		var arm_z := (source[arm_point]-source[shoulder]).normalized()
		var across := source[1]-source[0] if index == 0 else source[0]-source[1]
		var arm_y := across.cross(arm_z).normalized()
		var arm_x := arm_y.cross(arm_z).normalized()
		var arm_origin := torso*Vector3(0.4 if index == 0 else -0.4,0,0.2)
		_apply_model("Arm"+str(index+1),Basis(arm_x,arm_y,arm_z),arm_origin)
		var leg_z := (source[6+index]-source[2+index]).normalized()
		var leg_y := (source[0]-source[1]).cross(leg_z).normalized()
		var leg_x := leg_y.cross(leg_z).normalized()
		var leg_origin := torso*Vector3(0.25 if index == 0 else -0.25,0,0.9)
		_apply_model("Leg"+str(index+1),Basis(leg_x,leg_y,leg_z),leg_origin)

func _apply_model(name: String, native_basis: Basis, native_origin: Vector3) -> void:
	var basis := WORLD_AXES*native_basis*MODEL_AXES_INVERSE
	if not basis.is_finite() or absf(basis.determinant()) < 0.000001: return
	(_parts[name] as Node3D).transform = Transform3D(basis.scaled(Vector3.ONE*0.1),WORLD_AXES*native_origin)
