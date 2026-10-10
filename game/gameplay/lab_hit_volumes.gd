class_name LabHitVolumes
extends RefCounted
## Player.cpp:1316–1385. W maps native world (X,Y,Z-down) to Godot (X,-Z,Y).
const WORLD_AXES := Basis(Vector3.RIGHT,Vector3.BACK,Vector3.DOWN)
const SOURCE_PARALLEL_EPSILON := 0.000001

class PreparedPose extends RefCounted:
	## Owned source matrices; only typed value copies are exposed for inspection.
	var _inverses: Array[Transform3D]
	var _boxes: Array[AABB]
	var _parts: Array[String]
	var _bounds: AABB
	func _init(inverses: Array[Transform3D], boxes: Array[AABB], parts: Array[String], bounds: AABB) -> void:
		_inverses = inverses.duplicate()
		_boxes = boxes.duplicate()
		_parts = parts.duplicate()
		_bounds = bounds
		_inverses.make_read_only(); _boxes.make_read_only(); _parts.make_read_only()
	func get_inverse_transforms() -> Array[Transform3D]: return _inverses.duplicate()
	func get_boxes() -> Array[AABB]: return _boxes.duplicate()
	func get_parts() -> Array[String]: return _parts.duplicate()
	func get_world_bounds() -> AABB: return _bounds
	func get_volume_count() -> int: return _boxes.size()

static func volumes(crouch: bool,pitch: float=0.0) -> Array[Dictionary]:
	var lower := Transform3D(WORLD_AXES,Vector3(0,0.6 if crouch else 1.05,0))
	if crouch:lower *= Transform3D(Basis.IDENTITY,Vector3(0,0,-0.4))
	var torso := lower * Transform3D(Basis.IDENTITY,Vector3(0,0,-0.3 if crouch else -1.1))
	var pivot := 0.15 if crouch else 0.1
	var head := torso * Transform3D(Basis.IDENTITY,Vector3(0,0,pivot)) \
		* Transform3D(Basis(Vector3.RIGHT,pitch),Vector3.ZERO) \
		* Transform3D(Basis.IDENTITY,Vector3(0,0,-pivot))
	return [
		{"part":"head","transform":head,"box":AABB(Vector3(-.3,-.3,-.45 if crouch else -.5),Vector3(.6,.6,.6))},
		{"part":"torso","transform":torso,"box":AABB(Vector3(-.4,-.15,.1),Vector3(.8,.8 if crouch else .3,.6 if crouch else .9))},
		{"part":"legs","transform":lower,"box":AABB(Vector3(-.4,-.15,.5 if crouch else 0),Vector3(.3,.3,.5 if crouch else 1))},
		{"part":"legs","transform":lower,"box":AABB(Vector3(.1,-.15,.5 if crouch else 0),Vector3(.3,.3,.5 if crouch else 1))},
		{"part":"arms","transform":torso,"box":AABB(Vector3(-.6,-.15,.1),Vector3(1.2,.3,.6 if crouch else .9))}
	]

static func prepare_pose(feet: Vector3, yaw: float, crouch: bool, pitch: float = 0.0) -> PreparedPose:
	var base := Transform3D(Basis(Vector3.UP,yaw),feet)
	var inverses: Array[Transform3D] = []
	var boxes: Array[AABB] = []
	var parts: Array[String] = []
	var bounds := AABB()
	for volume: Dictionary in volumes(crouch,pitch):
		# Preserve the exact source multiplication/inversion order per volume.
		var matrix: Transform3D = base * volume.transform
		inverses.append(matrix.affine_inverse())
		boxes.append(volume.box)
		parts.append(volume.part)
		var world_box: AABB = matrix * volume.box
		bounds = world_box if inverses.size() == 1 else bounds.merge(world_box)
	return PreparedPose.new(inverses,boxes,parts,bounds)

static func _max_abs(value: Vector3) -> float:
	return maxf(absf(value.x),maxf(absf(value.y),absf(value.z)))

static func _bounds_may_intersect(origin: Vector3, ray: Vector3, pose: PreparedPose, max_distance: float) -> bool:
	# Unsupported inputs keep the previous narrow-phase behavior. In particular,
	# never apply the source local-axis epsilon to a differently rotated world ray.
	if not origin.is_finite() or not ray.is_finite() or not is_finite(max_distance) or max_distance < 0.0 or absf(ray.length_squared()-1.0) > 0.00001:
		return true
	var box := pose._bounds
	if not box.position.is_finite() or not box.end.is_finite(): return true
	var scale := maxf(1.0,maxf(max_distance,maxf(_max_abs(origin),maxf(_max_abs(box.position),_max_abs(box.end)))))
	# A local component treated as parallel can drift by epsilon*distance on
	# each of three axes. Also allow float32 world/inverse/point roundoff.
	var padding := 2.0 * SOURCE_PARALLEL_EPSILON * max_distance + 0.000008 * scale
	box = box.grow(padding)
	var near := 0.0
	var far := max_distance
	for axis in range(3):
		if ray[axis] == 0.0:
			if origin[axis] < box.position[axis] or origin[axis] > box.end[axis]: return false
		else:
			var first := (box.position[axis]-origin[axis])/ray[axis]
			var last := (box.end[axis]-origin[axis])/ray[axis]
			if first > last:
				var swap := first; first = last; last = swap
			near = maxf(near,first); far = minf(far,last)
			if near > far: return false
	return true

static func cast_ray(origin: Vector3,direction: Vector3,feet: Vector3,yaw: float,crouch: bool,pitch: float=0.0,max_distance: float=500.0) -> Dictionary:
	# Keep the legacy pre-transform short circuit, including invalid pose inputs.
	if direction.length_squared()<0.000001:
		return {"hit":false,"part":"","distance":max_distance,"position":origin+direction*max_distance}
	return cast_prepared(origin,direction,prepare_pose(feet,yaw,crouch,pitch),max_distance)

static func cast_prepared(origin: Vector3, direction: Vector3, pose: PreparedPose, max_distance: float = 500.0) -> Dictionary:
	var result := {"hit":false,"part":"","distance":max_distance,"position":origin+direction*max_distance}
	if direction.length_squared()<0.000001:return result
	var ray := direction.normalized()
	if not _bounds_may_intersect(origin,ray,pose,max_distance): return result
	var closest_horizontal:=INF
	# Source tests head, torso, left/right leg, broad arms; exact ties retain first.
	for index in pose._boxes.size():
		var inverse := pose._inverses[index]
		var local_origin := inverse*origin
		var local_direction := inverse.basis*ray
		var hit_distance := ray_box(local_origin,local_direction,pose._boxes[index],max_distance)
		var point:=origin+ray*hit_distance
		var horizontal:=Vector2(point.x-origin.x,point.z-origin.z).length()
		if hit_distance>=0.0 and horizontal<closest_horizontal:
			closest_horizontal=horizontal
			result={"hit":true,"part":pose._parts[index],"distance":hit_distance,"position":point}
	return result

static func ray_box(origin: Vector3,direction: Vector3,box: AABB,max_distance: float) -> float:
	var near := 0.0
	var far := max_distance
	for axis in range(3):
		if absf(direction[axis])<0.000001:
			if origin[axis]<box.position[axis] or origin[axis]>box.end[axis]:return -1.0
		else:
			var first := (box.position[axis]-origin[axis])/direction[axis]
			var last := (box.end[axis]-origin[axis])/direction[axis]
			if first>last:
				var swap:=first;first=last;last=swap
			near=maxf(near,first)
			far=minf(far,last)
			if near>far:return -1.0
	return near
