extends SceneTree
## World::WeaponRayCast camera semantics, separate from firearm128m queries.
const HITS=preload("res://gameplay/lab_hit_volumes.gd")
var checks:=0
var failures:=0

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error("CAMERA TARGET RAYS: "+message)

func _initialize() -> void:
	var upward:=HITS.cast_camera_ray(Vector3(-.25,-2,0),Vector3.UP,Vector3.ZERO,0,false)
	check(upward.hit and upward.part=="legs" and is_equal_approx(upward.distance,2.05),"vertical camera ray chooses the nearest leg by Euclidean distance")
	check(upward.parts==["head","torso","legs"],"source camera hit flags retain earlier farther parts of the same player")
	var limited:=HITS.cast_camera_ray(Vector3(-.25,-2,0),Vector3.UP,Vector3.ZERO,0,false,0,2.5)
	check(limited.hit and limited.parts==["legs"],"prior closer actor excludes farther parts before another actor becomes the nearest")
	check(not HITS.cast_camera_ray(Vector3(-.25,-2,0),Vector3.UP,Vector3.ZERO,0,false,0,2.0).hit,"candidate beyond the prior nearest actor cannot replace it")
	var firearm:=HITS.cast_ray(Vector3(-.25,-2,0),Vector3.UP,Vector3.ZERO,0,false)
	check(firearm.hit and firearm.part=="head","existing firearm horizontal tie policy is independent")
	var feet:=Vector3(700,40,-700)
	var eye:=feet+Vector3.UP*2.35
	var origin:=Vector3(0,42.35,0)
	var far:=HITS.cast_camera_ray(origin,eye-origin,feet,0,false)
	check(far.hit and far.distance>900 and far.part=="head","finite per-pose endpoint does not impose a500m camera cutoff")
	var crouch:=HITS.cast_camera_ray(Vector3(0,1.5,4),Vector3.FORWARD,Vector3.ZERO,0,true)
	check(crouch.hit and crouch.part=="head","crouching source head remains targetable")
	var zero:=HITS.cast_camera_ray(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,0,false)
	check(not zero.hit and zero.position==Vector3.ZERO,"zero direction safely has no camera target")
	var box:=AABB(Vector3(-.3,-.3,-.5),Vector3(.6,.6,.6))
	var edge:=Vector3(.30000004,0,0)
	var near_parallel:=Vector3(-.0000001,0,-1)
	check(HITS.ray_box(edge,near_parallel,box,2,0.0)>=0,"camera slab keeps a finite nonzero near-parallel entering direction")
	check(HITS.ray_box(edge,near_parallel,box,2)<0,"existing firearm epsilon is an explicit unchanged numeric adaptation")
	check(HITS.ray_box(Vector3(.31,0,0),Vector3.FORWARD,box,2,0.0)<0,"exact-zero parallel direction outside the face misses")
	print("CAMERA TARGET RAYS: %d assertions, %d failures"%[checks,failures])
	quit(1 if failures else 0)
