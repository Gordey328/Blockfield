class_name LabHitVolumes
extends RefCounted
## Player.cpp:1316–1385. W maps native world (X,Y,Z-down) to Godot (X,-Z,Y).
const WORLD_AXES := Basis(Vector3.RIGHT,Vector3.BACK,Vector3.DOWN)

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

static func cast_ray(origin: Vector3,direction: Vector3,feet: Vector3,yaw: float,crouch: bool,pitch: float=0.0,max_distance: float=500.0) -> Dictionary:
	var result := {"hit":false,"part":"","distance":max_distance,"position":origin+direction*max_distance}
	if direction.length_squared()<0.000001:return result
	var ray := direction.normalized()
	var base := Transform3D(Basis(Vector3.UP,yaw),feet)
	var closest_horizontal:=INF
	# Source tests head, torso, left/right leg, broad arms; exact ties retain first.
	for volume in volumes(crouch,pitch):
		var matrix: Transform3D=base*volume.transform
		var inverse := matrix.affine_inverse()
		var local_origin := inverse*origin
		var local_direction := inverse.basis*ray
		var hit_distance := ray_box(local_origin,local_direction,volume.box,max_distance)
		var point:=origin+ray*hit_distance
		var horizontal:=Vector2(point.x-origin.x,point.z-origin.z).length()
		if hit_distance>=0.0 and horizontal<closest_horizontal:
			closest_horizontal=horizontal
			result={"hit":true,"part":volume.part,"distance":hit_distance,"position":point}
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
