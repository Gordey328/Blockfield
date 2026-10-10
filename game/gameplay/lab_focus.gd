class_name LabFocus
extends RefCounted
## Client_LocalEnts.cpp:632–704; focus changes at constant reciprocal-distance speed.
var distance := 20.0
var target_distance := 20.0
var automatic := true
var speed := 0.4

func adjust_wheel(toward_near: bool) -> void:
	target_distance = 1.0 / clampf(1.0 / target_distance + (0.01 if toward_near else -0.01),1.0/128.0,1.0)
	automatic = false

func accept_distances(measurements: Array[float]) -> void:
	var valid: Array[float] = []
	for value in measurements:
		if is_finite(value) and value > 0.8:valid.append(value)
	if valid.is_empty():return
	valid.sort()
	var middle := valid.size()/2
	target_distance = valid[middle] if valid.size()%2 else (valid[middle]+valid[middle-1])*0.5

func advance(delta: float) -> void:
	distance = 1.0 / move_toward(1.0/distance,1.0/target_distance,maxf(speed,0.0)*maxf(delta,0.0))

func sample(camera: Camera3D, world: VoxelWorld) -> void:
	if not automatic:return
	var forward := -camera.global_basis.z.normalized()
	var extent := tan(deg_to_rad(camera.fov)*0.5)*0.2
	var axis_x := camera.global_basis.x.normalized()*extent
	var axis_y := camera.global_basis.y.normalized()*extent
	var values: Array[float] = []
	for x in range(4):
		for y in range(4):
			var ray := (forward + axis_x*(float(x)*2.0/3.0-1.0) + axis_y*(float(y)*2.0/3.0-1.0)).normalized()
			var hit := world.cast_voxel(camera.global_position,ray,500.0)
			var maximum := camera.global_position.distance_to(hit.position) if hit.hit else 500.0
			var query := PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position+ray*maximum,2)
			query.collide_with_areas = true
			var actor_hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
			if not actor_hit.is_empty():values.append((Vector3(actor_hit.position)-camera.global_position).dot(forward))
			elif hit.hit:values.append((Vector3(hit.position)-camera.global_position).dot(forward))
	accept_distances(values)
