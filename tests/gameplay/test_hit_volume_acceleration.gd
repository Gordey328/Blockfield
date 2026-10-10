extends SceneTree
## Frozen independent pre-optimization reference from c4f808990b84d068242dde47b8fe4f2951e322fe.
## Pure CPU query test: no Main, preferences, rendering, authority, or global RNG.
## --benchmark additionally measures 32 poses / 8 pellets, including pose preparation.
const HITS = preload("res://gameplay/lab_hit_volumes.gd")

class Legacy:
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

var assertions: int = 0
var failures: int = 0
var compared: int = 0
var hit_count: int = 0
var miss_count: int = 0

func _initialize() -> void: call_deferred("_run")
func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		if failures <= 12: push_error("HIT_ACCELERATION: " + message)

func same_number(a: float, b: float) -> bool:
	return a == b or (is_nan(a) and is_nan(b))
func same_result(a: Dictionary, b: Dictionary) -> bool:
	var ap: Vector3 = a.position; var bp: Vector3 = b.position
	return a.hit == b.hit and a.part == b.part and same_number(a.distance,b.distance) \
		and same_number(ap.x,bp.x) and same_number(ap.y,bp.y) and same_number(ap.z,bp.z)
func compare(origin: Vector3, direction: Vector3, feet: Vector3, yaw: float, crouch: bool, pitch: float, max_distance: float, label: String, prepared: HITS.PreparedPose = null) -> void:
	if prepared == null: prepared = HITS.prepare_pose(feet,yaw,crouch,pitch)
	var expected := Legacy.cast_ray(origin,direction,feet,yaw,crouch,pitch,max_distance)
	var actual := HITS.cast_prepared(origin,direction,prepared,max_distance)
	compared += 1
	if expected.hit: hit_count += 1
	else: miss_count += 1
	check(same_result(expected,actual), "exact legacy comparison %s: expected %s actual %s" % [label,expected,actual])
	if compared % 73 == 0:
		check(same_result(expected,HITS.cast_ray(origin,direction,feet,yaw,crouch,pitch,max_distance)),"legacy entrypoint remains exact: " + label)

func _run() -> void:
	_test_source_goldens()
	_test_inspection_isolation()
	_test_faces_corners_and_wraps()
	_test_near_parallel_and_input_fallbacks()
	_test_random_rays()
	check(hit_count > 1500 and miss_count > 1500,"differential corpus contains substantial hit and miss populations")
	if "--benchmark" in OS.get_cmdline_user_args() and failures == 0: _benchmark()
	print("HIT_ACCELERATION: %d assertions, %d failures; %d differential rays (%d hits, %d misses)" % [assertions,failures,compared,hit_count,miss_count])
	quit(0 if failures == 0 else 1)

func _world_bounds(matrix: Transform3D, box: AABB) -> AABB:
	var result := AABB(matrix * box.position,Vector3.ZERO)
	for corner in 8: result = result.expand(matrix * box.get_endpoint(corner))
	return result
func _test_source_goldens() -> void:
	var standing_centers: Array[Vector3] = [Vector3(0,2.35,0),Vector3(0,1.6,0),Vector3(-.25,.55,0),Vector3(.25,.55,0),Vector3(0,1.6,0)]
	var standing_sizes: Array[Vector3] = [Vector3(.6,.6,.6),Vector3(.8,.9,.3),Vector3(.3,1,.3),Vector3(.3,1,.3),Vector3(1.2,.9,.3)]
	var crouch_centers: Array[Vector3] = [Vector3(0,1.45,0),Vector3(0,.9,.25),Vector3(-.25,.25,0),Vector3(.25,.25,0),Vector3(0,.9,0)]
	var crouch_sizes: Array[Vector3] = [Vector3(.6,.6,.6),Vector3(.8,.6,.8),Vector3(.3,.5,.3),Vector3(.3,.5,.3),Vector3(1.2,.6,.3)]
	for crouch: bool in [false,true]:
		var pose := HITS.prepare_pose(Vector3.ZERO,0.0,crouch)
		check(pose.get_volume_count() == 5 and pose.get_parts() == ["head","torso","legs","legs","arms"],"source five-part order")
		var boxes := pose.get_boxes(); var inverses := pose.get_inverse_transforms()
		for index in 5:
			var bounds := _world_bounds(inverses[index].affine_inverse(),boxes[index])
			check(bounds.get_center().is_equal_approx(crouch_centers[index] if crouch else standing_centers[index]),"source center crouch=%s part=%d" % [crouch,index])
			check(bounds.size.is_equal_approx(crouch_sizes[index] if crouch else standing_sizes[index]),"source size crouch=%s part=%d" % [crouch,index])
		var pitched := HITS.prepare_pose(Vector3.ZERO,0.0,crouch,PI/2.0)
		var head_bounds := _world_bounds(pitched.get_inverse_transforms()[0].affine_inverse(),pitched.get_boxes()[0])
		check(head_bounds.get_center().is_equal_approx(Vector3(0,1.15 if crouch else 2.05,.3)),"native head offset pivot")
		var union := pose.get_world_bounds()
		check(union.position.is_equal_approx(Vector3(-.6,0 if crouch else .05,-.3)) and union.size.is_equal_approx(Vector3(1.2,1.75 if crouch else 2.6,.95 if crouch else .6)),"exact unpadded source union")
	var cases := [
		[Vector3(0,2.35,-5),false,"head"],[Vector3(0,1.6,-5),false,"torso"],
		[Vector3(.5,1.6,-5),false,"arms"],[Vector3(-.25,.5,-5),false,"legs"],
		[Vector3(.25,.5,-5),false,"legs"],[Vector3(0,.5,-5),false,""],
		[Vector3(-.25,.25,-5),true,"legs"],[Vector3(0,.25,-5),true,""],
		[Vector3(-.25,.55,-5),true,""],[Vector3(0,.9,-5),true,"torso"],
		[Vector3(.5,.9,-5),true,"arms"],[Vector3(0,1.45,-5),true,"head"]]
	for item: Array in cases:
		var result := HITS.cast_ray(item[0],Vector3.BACK,Vector3.ZERO,0.0,item[1])
		check(result.part == item[2] and result.hit == (item[2] != ""),"source part/gap golden " + str(item))
	var yaw_hit := HITS.cast_ray(Vector3(5,.9,0),Vector3.LEFT,Vector3.ZERO,PI/2.0,true)
	check(yaw_hit.hit and yaw_hit.part == "torso","yaw quarter-turn source golden")
	var tie := HITS.cast_ray(Vector3.ZERO,Vector3.UP,Vector3.ZERO,0.0,false)
	check(tie.hit and tie.part == "head" and tie.distance > 1.9,"horizontal zero-distance tie retains head rather than nearer legs/body")
	var far_hit := HITS.cast_ray(Vector3(0,2.35,-150),Vector3.BACK,Vector3.ZERO,0.0,false,0,500)
	check(far_hit.hit and far_hit.distance > 128,"helper does not invent caller's horizontal-range cutoff")
	var miss := HITS.cast_ray(Vector3(9,9,9),Vector3(0,0,3),Vector3.ZERO,0.0,false,0,2)
	check(not miss.hit and miss.distance == 2 and miss.position == Vector3(9,9,15),"miss position retains raw direction magnitude")
	var invalid_pose_zero := HITS.cast_ray(Vector3(9,9,9),Vector3.ZERO,Vector3(NAN,INF,0),INF,false,NAN,2)
	check(same_result(invalid_pose_zero,Legacy.cast_ray(Vector3(9,9,9),Vector3.ZERO,Vector3(NAN,INF,0),INF,false,NAN,2)),"zero ray returns before invalid pose transform construction")

func _test_inspection_isolation() -> void:
	var pose := HITS.prepare_pose(Vector3(1,2,3),.731,true,-.65)
	var ray_origin := Vector3(1,3.45,-5)
	var expected := HITS.cast_prepared(ray_origin,Vector3.BACK,pose)
	var inverses := pose.get_inverse_transforms(); var boxes := pose.get_boxes(); var parts := pose.get_parts()
	inverses[0] = Transform3D(Basis.IDENTITY,Vector3(1000,0,0)); boxes[0] = AABB(); parts[0] = "modified"
	inverses.clear(); boxes.clear(); parts.clear()
	var bound := pose.get_world_bounds(); bound.position = Vector3(1000,1000,1000)
	check(same_result(expected,HITS.cast_prepared(ray_origin,Vector3.BACK,pose)),"inspection value copies cannot change later prepared queries")
	check(pose.get_volume_count() == 5 and pose.get_parts()[0] == "head","inspection arrays do not alias pose")
	var shifted := HITS.prepare_pose(Vector3(1001,2,3),.731,true,-.65)
	check(not HITS.cast_prepared(ray_origin,Vector3.BACK,shifted).hit,"separate source poses are not reused across actors")
	check(same_result(expected,HITS.cast_prepared(ray_origin,Vector3.BACK,pose)),"preparing another pose does not invalidate existing pose")

func _test_faces_corners_and_wraps() -> void:
	var feet_cases: Array[Vector3] = [Vector3.ZERO,Vector3(511,40,511),Vector3(-513,-1,520),Vector3(100000,-100000,100000),Vector3(.03125,.0001,-.0001)]
	var yaws := [0.0,PI/2,-PI/2,PI,TAU+.731,32*PI+.002]
	var pitches := [-PI/2,-.75,0.0,.75,PI/2]
	var directions: Array[Vector3] = [Vector3.BACK,Vector3.FORWARD,Vector3.LEFT,Vector3.RIGHT,Vector3.UP,Vector3.DOWN,Vector3(.0000001,0,1),Vector3(.0000001,1,-.0000001)]
	var pose_index := 0
	for crouch: bool in [false,true]:
		for yaw: float in yaws:
			for pitch: float in pitches:
				var feet := feet_cases[pose_index % feet_cases.size()]; pose_index += 1
				var pose := HITS.prepare_pose(feet,yaw,crouch,pitch)
				var base := Transform3D(Basis(Vector3.UP,yaw),feet)
				var bound := pose.get_world_bounds()
				for volume: Dictionary in Legacy.volumes(crouch,pitch):
					var matrix: Transform3D = base * volume.transform
					var box: AABB = volume.box
					for corner in 8:
						var target: Vector3 = matrix * box.get_endpoint(corner)
						check(bound.grow(.04).has_point(target),"prepared union conservatively covers transformed volume corner")
						for direction: Vector3 in directions:
							var origin := target-direction.normalized()*5
							for distance: float in [5.0,5.00001,4.99999]:
								compare(origin,direction,feet,yaw,crouch,pitch,distance,"corner pose=%d corner=%d" % [pose_index,corner],pose)
					# Center rays establish interior hits separately from the exact edge cases.
					var center: Vector3 = matrix * box.get_center()
					for direction: Vector3 in directions:
						compare(center-direction.normalized()*10,direction,feet,yaw,crouch,pitch,11,"volume interior",pose)

func _test_near_parallel_and_input_fallbacks() -> void:
	for yaw: float in [0.0,.71,PI/2,TAU+.00001]:
		var feet := Vector3(511.25,4.125,-.001)
		var base := Transform3D(Basis(Vector3.UP,yaw),feet)
		for crouch: bool in [false,true]:
			var pose := HITS.prepare_pose(feet,yaw,crouch,.42)
			for epsilon: float in [0.0,.00000001,.0000007,.00000099,.000001,.00000101,-.0000007]:
				# Ignored local X can leave the tight world union before a distant hit.
				var origin := base * Vector3(.6-.000001,.9 if crouch else 1.6,-499.7)
				var direction := base.basis * Vector3(epsilon,0,1)
				compare(origin,direction,feet,yaw,crouch,.42,500,"local epsilon long ray",pose)
				# World near-zero axes differ from the rotated source local axes.
				compare(feet+Vector3(.599999,.9 if crouch else 1.6,-499.7),Vector3(epsilon,0,1),feet,yaw,crouch,.42,500,"world epsilon long ray",pose)
	var pose := HITS.prepare_pose(Vector3.ZERO,0,false)
	for direction: Vector3 in [Vector3.ZERO,Vector3(.000999,0,0),Vector3(0,0,.001),Vector3(0,0,3),Vector3(1e30,0,0)]:
		for distance: float in [-5.0,0.0,5.0,1e30,1e100,1e308,INF,NAN]:
			compare(Vector3(0,1.6,-5),direction,Vector3.ZERO,0,false,0,distance,"unsupported input retains narrow behavior",pose)
	for origin: Vector3 in [Vector3(INF,1,0),Vector3(NAN,1,0)]:
		compare(origin,Vector3.BACK,Vector3.ZERO,0,false,0,500,"non-finite origin fallback",pose)
	# Godot deliberately warns while normalizing these invalid vectors. Suppress
	# only those expected engine diagnostics; failures still change the exit code.
	var previous_print_errors := Engine.print_error_messages
	Engine.print_error_messages = false
	for direction: Vector3 in [Vector3(INF,0,0),Vector3(NAN,0,1)]:
		for distance: float in [-5.0,0.0,5.0,INF,NAN]:
			compare(Vector3(0,1.6,-5),direction,Vector3.ZERO,0,false,0,distance,"non-finite direction fallback",pose)
	Engine.print_error_messages = previous_print_errors
	compare(Vector3(.599999,1.6,-499.7),Vector3(.0000007,0,1),Vector3.ZERO,0,false,0,500,"source epsilon drift must not become a false miss",pose)
	check(Legacy.cast_ray(Vector3(.599999,1.6,-499.7),Vector3(.0000007,0,1),Vector3.ZERO,0,false).hit,"epsilon drift fixture is an actual original hit outside tight world bounds")

func _test_random_rays() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 0x3417116
	for index in 240:
		var scale := 1.0 if index % 7 != 0 else 10000.0
		var feet := Vector3(rng.randf_range(-550,550),rng.randf_range(-4,64),rng.randf_range(-550,550))*scale
		var crouch := index % 2 == 0
		var yaw := rng.randf_range(-48*PI,48*PI); var pitch := rng.randf_range(-PI/2,PI/2)
		var pose := HITS.prepare_pose(feet,yaw,crouch,pitch)
		var base := Transform3D(Basis(Vector3.UP,yaw),feet)
		var legacy_volumes := Legacy.volumes(crouch,pitch)
		for sample in 24:
			var volume: Dictionary = legacy_volumes[sample % 5]
			var matrix: Transform3D = base * volume.transform
			var box: AABB = volume.box
			var target: Vector3 = matrix * (box.position+box.size*Vector3(rng.randf(),rng.randf(),rng.randf()))
			var offset := Vector3(rng.randf_range(-100,100),rng.randf_range(-100,100),rng.randf_range(-100,100))
			var origin := target + offset
			var direction := -offset.normalized()
			if sample % 3 == 0: direction = Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1))
			if sample % 4 == 0: direction *= 3.25
			var distance: float = [500.0,offset.length(),5.0,0.0][sample % 4]
			compare(origin,direction,feet,yaw,crouch,pitch,distance,"seeded random pose=%d ray=%d" % [index,sample],pose)

func _benchmark_batch(poses: Array[Dictionary], rays: Array[Vector3], batches: int, prepared_mode: bool) -> Dictionary:
	var hits := 0; var distance_checksum := 0.0
	var started := Time.get_ticks_usec()
	for batch in batches:
		var prepared: Array[HITS.PreparedPose] = []
		if prepared_mode:
			for pose: Dictionary in poses: prepared.append(HITS.prepare_pose(pose.feet,pose.yaw,pose.crouch,pose.pitch))
		for ray: Vector3 in rays:
			for index in poses.size():
				var pose: Dictionary = poses[index]
				var result: Dictionary
				if prepared_mode: result = HITS.cast_prepared(Vector3(0,1.6,-40),ray,prepared[index])
				else: result = Legacy.cast_ray(Vector3(0,1.6,-40),ray,pose.feet,pose.yaw,pose.crouch,pose.pitch)
				if result.hit: hits += 1; distance_checksum += result.distance
	return {"elapsed_us":Time.get_ticks_usec()-started,"hits":hits,"distance_checksum":distance_checksum}

func _benchmark() -> void:
	var poses: Array[Dictionary] = []
	for index in 32:
		poses.append({"feet":Vector3(0 if index == 0 else 3+index*1.7,0,(index % 5)*2),"yaw":0.0 if index == 0 else index*.21,"crouch":false if index == 0 else index % 2 == 0,"pitch":0.0 if index == 0 else sin(index)*.4})
	var rays: Array[Vector3] = []
	for index in 8: rays.append(Vector3((index-3.5)*.0015,(index % 3-1)*.002,1).normalized())
	var warm_legacy := _benchmark_batch(poses,rays,2,false)
	var warm_prepared := _benchmark_batch(poses,rays,2,true)
	check(warm_legacy.hits == warm_prepared.hits and warm_legacy.distance_checksum == warm_prepared.distance_checksum,"benchmark representative salvo is behaviorally identical")
	var samples: Array[Dictionary] = []
	var legacy_times: Array[int] = []; var prepared_times: Array[int] = []
	const BATCHES := 96
	for sample in 5:
		var legacy: Dictionary; var prepared: Dictionary
		if sample % 2 == 0:
			legacy = _benchmark_batch(poses,rays,BATCHES,false); prepared = _benchmark_batch(poses,rays,BATCHES,true)
		else:
			prepared = _benchmark_batch(poses,rays,BATCHES,true); legacy = _benchmark_batch(poses,rays,BATCHES,false)
		check(legacy.hits == prepared.hits and legacy.distance_checksum == prepared.distance_checksum,"timed salvo results retain exact legacy hit/distance checksum")
		legacy_times.append(legacy.elapsed_us); prepared_times.append(prepared.elapsed_us)
		samples.append({"legacy_us":legacy.elapsed_us,"prepared_including_build_us":prepared.elapsed_us,"hits":legacy.hits,"distance_checksum":legacy.distance_checksum})
	legacy_times.sort(); prepared_times.sort()
	var output := {"engine":Engine.get_version_info().string,"cpu":OS.get_processor_name(),"reference_commit":"c4f808990b84d068242dde47b8fe4f2951e322fe","poses":32,"pellets":8,"batches_per_sample":BATCHES,"samples":samples,"legacy_median_us":legacy_times[2],"prepared_median_us":prepared_times[2],"speedup":float(legacy_times[2])/prepared_times[2],"miss_ratio":1.0-float(warm_legacy.hits)/(2*32*8),"includes_preparation":true,"scope":"pure hit query only; no match/transport/frame-budget claim"}
	var path := ProjectSettings.globalize_path("res://../.cache/benchmarks/hit-volume-acceleration.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path,FileAccess.WRITE)
	check(file != null,"benchmark JSON output can be written")
	if file != null: file.store_string(JSON.stringify(output,"\t")); file.close()
	print("HIT_ACCELERATION benchmark: %.2fx; legacy %.3fms / prepared+build %.3fms per 32-pose, 8-pellet salvo; %.2f%% misses" % [output.speedup,float(legacy_times[2])/BATCHES/1000,float(prepared_times[2])/BATCHES/1000,output.miss_ratio*100])
