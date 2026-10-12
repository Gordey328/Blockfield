## Independent preoptimization baseline d5516eb; original SHA256
## f265dab2369eb362ae570d3c0c6d7067715168c144615f6b760e0c7e2614bc9e.
extends Node3D
## GPL-3.0-or-later. Adapted from OpenSpades v0.1.3 Sources/Client/Corpse.cpp.
## Source nine-point spring body, not Godot's unrelated rigid-body ragdoll solver.
const MODELS = preload("res://presentation/openspades_models.gd")
const WORLD_AXES := Basis(Vector3.RIGHT,Vector3.BACK,Vector3.DOWN)
const MODEL_AXES_INVERSE := MODELS.SOURCE_AXES
const EDGE_PAIRS := [[0,1],[1,2],[2,3],[3,0],[0,4],[1,5],[2,6],[3,7]]
const LENGTHS := [[0,1,0.8],[2,3,0.8],[0,3,0.9],[1,2,0.9],
	[0,2,1.204],[1,3,1.204],[4,0,1.0],[5,1,1.0],[6,2,1.0],[7,3,1.0]]
const LINES := [[0,1],[1,2],[2,3],[3,0],[0,2],[1,3],[0,4],[1,5],[2,6],[3,7]]
enum Point { TORSO1,TORSO2,TORSO3,TORSO4,ARM1,ARM2,LEG1,LEG2,HEAD }
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

func refresh_resources() -> void:
	for part: Node3D in _parts.values():
		part.hide()
		part.queue_free()
	_parts.clear()
	if not _active:
		return
	for name in ["Torso","Head","Arm1","Arm2","Leg1","Leg2"]:
		var model: String = "Arm" if name.begins_with("Arm") else ("Leg" if name.begins_with("Leg") else name)
		var part := MODELS.create("Player/"+model)
		part.name = name
		add_child(part)
		MODELS.set_tint(part,color)
		_parts[name] = part
	_update_models()

func add_impulse(impulse: Vector3) -> void:
	if not impulse.is_finite():
		return
	for index in range(velocities.size()): velocities[index] += impulse

func get_center() -> Vector3:
	var center := Vector3.ZERO
	for position in positions: center += position
	return center/float(positions.size()) if not positions.is_empty() else Vector3.ZERO

func is_visible_from(eye: Vector3) -> bool:
	if not _active or eye.distance_to(get_center()) > 150.0:
		return false
	# Use actual finite segments. Native Corpse's legacy CastRay prefilter passes an
	# endpoint to a direction API; retaining it would invert/misclassify visibility.
	for position in positions:
		if not _ray(eye,position,256).hit: return true
	return false

func step(delta: float) -> void:
	if not _active or not is_finite(delta) or delta <= 0:
		return
	# Native client uses four substeps per render frame. Keep that at >=60 Hz and
	# add substeps on slow frames; cap a paused-tab resume to .25 s of cosmetic work.
	var elapsed := minf(delta,0.25)
	var substeps := maxi(4,ceili(elapsed*240.0))
	var dt := elapsed/float(substeps)
	for index in range(substeps): _substep(dt)
	simulation_time += elapsed
	_update_models()

func _substep(dt: float) -> void:
	var damp := pow(0.9,dt)
	var damp_vertical := pow(0.371,dt)
	var water_level := 1.0
	if is_instance_valid(world):
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
			for axis in [0,2,1]:
				var sample := old
				for completed_axis in [0,2,1]:
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
	var damp := 1.0-pow(0.1,dt)
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
	var damp := 1.0-pow(0.05,dt)
	for index in [0,1,8]: velocities[index] += (midpoint-velocities[index])*damp

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
	var first := _ray(last_positions[a],last_positions[b],8)
	if not first.hit or first.start_solid: return
	var second := _ray(last_positions[b],last_positions[a],8)
	if not second.hit or second.start_solid: return
	var length_squared := positions[b].distance_squared_to(positions[a])
	if (first.position-last_positions[a]).dot(last_positions[b]-last_positions[a]) > length_squared: return
	if (second.position-last_positions[b]).dot(last_positions[a]-last_positions[b]) > length_squared: return
	var penetration: float = first.position.distance_to(second.position)
	var direction: Vector3 = Vector3(first.normal+second.normal)
	if direction == Vector3.ZERO:
		var escape := _escape(first.cell,Vector3i(positions[a].floor()),Vector3i(positions[b].floor()))
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
	return bool(world.call("clip_box",position)) if is_instance_valid(world) and world.has_method("clip_box") else false

func _solid_wrapped(cell: Vector3i) -> bool:
	if not is_instance_valid(world) or not world.has_method("get_block"): return false
	var size_value = world.get("dimensions")
	if size_value is Vector3i:
		var size: Vector3i = size_value
		if cell.y < 0: return true
		if cell.y >= size.y: return false
		cell.x = posmod(cell.x,size.x)
		cell.z = posmod(cell.z,size.z)
	return int(world.call("get_block",cell)) != 0

func _ray(origin: Vector3, endpoint: Vector3, max_steps: int) -> Dictionary:
	var difference := endpoint-origin
	var distance := difference.length()
	var miss := {"hit":false,"start_solid":false,"position":endpoint,"cell":Vector3i.ZERO,"normal":Vector3i.ZERO}
	if distance < 0.000001: return miss
	var ray := difference/distance
	var cell := Vector3i(origin.floor())
	if _solid_wrapped(cell): return {"hit":true,"start_solid":true,"position":origin,"cell":cell,"normal":Vector3i.ZERO}
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
		if traveled > distance: return miss
		next[axis] += delta[axis]
		cell[axis] += step[axis]
		if _solid_wrapped(cell):
			var normal := Vector3i.ZERO
			normal[axis] = -step[axis]
			return {"hit":true,"start_solid":false,"position":origin+ray*traveled,"cell":cell,"normal":normal}
	return miss

func _update_models() -> void:
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
