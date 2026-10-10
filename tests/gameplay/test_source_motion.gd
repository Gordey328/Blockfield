extends SceneTree
## Numerical terrain cases from pinned Player.cpp, not Godot physics queries.
## godot --headless --path game --script ../tests/gameplay/test_source_motion.gd --verbose

const MOTION = preload("res://gameplay/source_player_motion.gd")
var assertions: int = 0
var failures: int = 0
var world: VoxelWorld

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("SOURCE MOTION: " + message)

func vector(actual: Vector3, expected: Vector3, message: String) -> void:
	check(actual.distance_to(expected) < 0.00002, message + " actual=" + str(actual) + " expected=" + str(expected))

func reset_map() -> void:
	world.clear_world(Vector3i(32,64,32))

func block(x: int, y: int, z: int) -> void:
	world.set_block(Vector3i(x,y,z), VoxelWorld.pack_color(Color.WHITE))

func floor_plane(y: int) -> void:
	for x in 32:
		for z in 32:
			block(x,y,z)

func state(feet: Vector3 = Vector3(10.5,4.01,10.5), crouch: bool = false, grounded: bool = true) -> SourcePlayerMotion.State:
	return MOTION.create_state(feet,crouch,grounded)

func _run() -> void:
	# Keep the real voxel authority outside the tree: no generated lab, mesh,
	# rendering, user settings or CharacterBody3D can affect these cases.
	world = VoxelWorld.new()
	for scenario in ["test_clip_boundaries","test_free_flight","test_slide_order","test_vertical_contacts","test_step_rules","test_step_eye","test_crouch","test_uncrouch","test_wade","test_landing","test_long_walk","test_crouch_cycles"]:
		check(call(scenario) == true, "scenario completes: " + scenario)
	world.free()
	print("SOURCE MOTION: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)

func test_clip_boundaries() -> bool:
	reset_map()
	block(4,4,4)
	check(MOTION.source_clip_box(world,Vector3(4.5,4.999,4.5)), "solid interior uses reflected native floor")
	check(MOTION.source_clip_box(world,Vector3(4.5,5.0,4.5)), "integer top face belongs to lower voxel in native Z-down")
	check(not MOTION.source_clip_box(world,Vector3(4.5,5.001,4.5)), "epsilon above the top face is empty")
	check(not MOTION.source_clip_box(world,Vector3(4.5,4.0,4.5)), "integer bottom face probes the voxel below")
	for point in [Vector3(-0.001,8,4),Vector3(32,8,4),Vector3(4,8,-0.001),Vector3(4,8,32)]:
		check(MOTION.source_clip_box(world,point), "horizontal boundary is solid: " + str(point))
	check(not MOTION.source_clip_box(world,Vector3(4,64.001,4)), "native negative Z sky is empty")
	check(MOTION.source_clip_box(world,Vector3(4,0,4)), "native Z=64 bottom is solid")
	check(not MOTION.source_clip_box(world,Vector3(4,.5,4)), "empty Z=62 permits traversal through aliased Z=63")
	block(4,1,4)
	check(MOTION.source_clip_box(world,Vector3(4,.5,4)), "Z=63 aliases occupied Z=62 rather than bottom-layer color")
	check(MOTION.source_clip_box(world,Vector3(4,1,4)), "water plane is aliased lower voxel at exact integer boundary")
	return true

func test_free_flight() -> bool:
	reset_map()
	var before := state(Vector3(10.5,12,10.5),false,false)
	before.native_velocity = Vector3(.125,.0625,-.25)
	var result: SourcePlayerMotion.State = MOTION.clip_move(world,before,.125,1)
	vector(result.feet_position,Vector3(11,12.25,9.5), "free displacement uses native velocity*32*dt on all axes")
	vector(result.native_velocity,before.native_velocity, "clipping does not duplicate acceleration/gravity/friction")
	check(not result.grounded and not result.climbed and not result.vertical_collision, "free flight sets airborne without invented contact")
	vector(before.feet_position,Vector3(10.5,12,10.5), "clip_move leaves input state immutable")
	# Native probes the destination, so it can cross an intervening one-cell
	# wall in a sufficiently large tick. A swept Godot collider would stop it.
	for y in range(12,15): block(11,y,10)
	before.native_velocity = Vector3(1,0,0)
	result = MOTION.clip_move(world,before,.125,1)
	vector(result.feet_position,Vector3(14.5,12,10.5), "destination sampling retains native large-tick wall crossing")
	return true

func test_slide_order() -> bool:
	reset_map()
	for y in range(4,8): block(11,y,10)
	var before := state()
	before.native_velocity = Vector3(.125,0,-.125)
	var result: SourcePlayerMotion.State = MOTION.clip_move(world,before,.125,1)
	vector(result.feet_position,Vector3(10.5,4.01,10), "blocked X remains at old coordinate while Z slides")
	vector(result.native_velocity,Vector3(0,0,-.125), "only blocked horizontal component is cancelled")
	reset_map()
	for y in range(4,8): block(11,y,11)
	before.native_velocity = Vector3(.1,0,.1)
	result = MOTION.clip_move(world,before,.125,1)
	vector(result.feet_position,Vector3(10.9,4.01,10.5), "Y probes use the already-updated X position")
	vector(result.native_velocity,Vector3(.1,0,0), "corner ordering cancels native Y/Godot Z")
	reset_map()
	before = state(Vector3(.5,8,10.5))
	before.native_velocity = Vector3(-.125,0,0)
	result = MOTION.clip_move(world,before,.125,1)
	vector(result.feet_position,before.feet_position, "horizontal edge rejects a move without clamping position")
	check(result.native_velocity.x == 0, "solid map edge cancels outward speed")
	return true

func test_vertical_contacts() -> bool:
	reset_map()
	floor_plane(3)
	var before := state()
	before.native_velocity = Vector3(0,-.1,0)
	var result: SourcePlayerMotion.State = MOTION.clip_move(world,before,.125,1)
	vector(result.feet_position,before.feet_position, "floor contact retains previous height instead of snapping to a surface")
	check(result.grounded and result.vertical_collision and result.native_velocity.y == 0, "downward corner contact clears vertical velocity and airborne")
	for x in [10,11]:
		for z in [10,11]: block(x,7,z)
	before.native_velocity = Vector3(0,.2,0)
	result = MOTION.clip_move(world,before,.125,1)
	check(not result.grounded and result.vertical_collision and result.native_velocity.y == 0, "ceiling contact clears upward velocity while retaining airborne")
	vector(result.feet_position,before.feet_position, "ceiling contact restores previous vertical position")
	return true

func test_step_rules() -> bool:
	reset_map()
	block(11,4,10)
	var before := state()
	before.native_velocity = Vector3(.1,-.02,0)
	var result: SourcePlayerMotion.State = MOTION.clip_move(world,before,.125,2)
	vector(result.feet_position,Vector3(10.9,5.01,10.5), "one-cell step raises the physics feet by exactly one")
	vector(result.native_velocity,Vector3(.05,-.02,0), "step halves horizontal velocity without applying vertical displacement")
	check(result.climbed and result.last_climb_time == 2, "step records source climb clock")
	for rule in ["crouch","sprint","look_down"]:
		before = state(Vector3(10.5,4.01,10.5),rule == "crouch")
		before.sprint = rule == "sprint"
		before.front = Vector3(0,-.5,-sqrt(.75)) if rule == "look_down" else Vector3.FORWARD
		before.native_velocity = Vector3(.1,0,0)
		result = MOTION.clip_move(world,before,.125,2)
		check(not result.climbed and result.native_velocity.x == 0, "step rejected at source rule: " + rule)
		check(is_equal_approx(result.feet_position.x,10.5), "rejected step retains X: " + rule)
	before = state()
	before.front = Vector3(0,-.499,-sqrt(1-.499*.499))
	before.native_velocity = Vector3(.1,0,0)
	check(MOTION.clip_move(world,before,.125,2).climbed, "look-down condition is strict native front.z<.5")
	block(11,5,10)
	result = MOTION.clip_move(world,before,.125,2)
	check(not result.climbed and result.native_velocity.x == 0, "two-cell obstacle fails the four raised corner samples")
	reset_map()
	block(10,4,11)
	before = state()
	before.native_velocity = Vector3(0,0,.1)
	result = MOTION.clip_move(world,before,.125,2)
	vector(result.feet_position,Vector3(10.5,5.01,10.9), "second horizontal axis can initiate a step")
	reset_map()
	block(11,4,10)
	block(11,5,11)
	before = state()
	before.native_velocity = Vector3(.1,0,.1)
	result = MOTION.clip_move(world,before,.125,2)
	vector(result.feet_position,Vector3(10.9,5.01,10.5), "X step cannot also move into a blocked Y endpoint")
	vector(result.native_velocity,Vector3(.05,0,.05), "native failed Y after X climb retains and halves Y velocity")
	return true

func test_step_eye() -> bool:
	reset_map()
	block(11,4,10)
	var before := state()
	before.native_velocity = Vector3(.1,0,0)
	var result: SourcePlayerMotion.State = MOTION.clip_move(world,before,.125,2)
	vector(result.eye_position,Vector3(10.9,6.26,10.5), "first step frame keeps the old eye height")
	var halfway: SourcePlayerMotion.State = MOTION.reposition(result,2.125)
	vector(halfway.eye_position,Vector3(10.9,6.76,10.5), "source climb eye recovers half a block at .125 seconds")
	var settled: SourcePlayerMotion.State = MOTION.reposition(result,2.25)
	vector(settled.eye_position,Vector3(10.9,7.26,10.5), "source climb eye settles at .25 seconds")
	vector(settled.feet_position,result.feet_position, "camera smoothing never modifies physical feet")
	var initial := state(Vector3(4,8,4))
	vector(MOTION.reposition(initial,0).eye_position,Vector3(4,10.25,4), "constructor lastClimbTime=-100 does not sink spawn view")
	return true

func test_crouch() -> bool:
	reset_map()
	var before := state()
	var result: SourcePlayerMotion.State = MOTION.set_crouch(world,before,true)
	vector(result.feet_position,before.feet_position, "ground crouch keeps feet fixed")
	vector(result.physics_eye(),before.physics_eye()-Vector3.UP*.9, "ground crouch lowers physical eye by .9")
	vector(MOTION.set_crouch(world,result,false).feet_position,before.feet_position, "ground standing returns the same foot anchor")
	before.grounded = false
	result = MOTION.set_crouch(world,before,true)
	vector(result.feet_position,before.feet_position+Vector3.UP*.9, "air crouch raises feet by .9")
	vector(result.physics_eye(),before.physics_eye(), "air crouch preserves physical eye")
	var stood: SourcePlayerMotion.State = MOTION.set_crouch(world,result,false)
	vector(stood.feet_position,before.feet_position, "air uncrouch with clear feet reverses the shift")
	vector(stood.physics_eye(),before.physics_eye(), "air standing preserves physical eye")
	return true

func test_uncrouch() -> bool:
	reset_map()
	var before := state(Vector3(10.5,8,10.5),true,false)
	# A low ceiling must not reject airborne feet-lowering when feet are clear.
	block(10,10,10)
	var trial: Dictionary = MOTION.try_uncrouch(world,before,true)
	check(trial.allowed and trial.lower_feet, "air uncrouch prioritizes feet even beneath a ceiling")
	vector(trial.state.feet_position,before.feet_position, "feet-first TryUncrouch(true) has no position shift")
	reset_map()
	floor_plane(3)
	before = state(Vector3(10.5,4.01,10.5),true,false)
	trial = MOTION.try_uncrouch(world,before,false)
	check(trial.allowed and not trial.lower_feet, "blocked feet can use the head-clear fallback")
	vector(trial.state.feet_position,before.feet_position, "Client TryUncrouch(false) is only a clearance query")
	var client_stood: SourcePlayerMotion.State = MOTION.set_crouch(world,before,false)
	vector(client_stood.physics_eye(),before.physics_eye(), "native client head-clear fallback preserves airborne eye because it uses move=false")
	vector(client_stood.feet_position,before.feet_position-Vector3.UP*.9, "native client head-clear fallback lowers the airborne feet via SetInput")
	trial = MOTION.try_uncrouch(world,before,true)
	vector(trial.state.feet_position,before.feet_position+Vector3.UP*.9, "optional TryUncrouch(true) raises physical position")
	vector(trial.state.eye_position,before.eye_position+Vector3.UP*.9, "optional TryUncrouch(true) raises view eye too")
	block(10,6,10)
	trial = MOTION.try_uncrouch(world,before,true)
	check(not trial.allowed, "blocked feet and head reject uncrouch")
	check(MOTION.set_crouch(world,before,false).crouch, "client SetInput keeps crouch when clearance fails")
	before.grounded = true
	check(not MOTION.try_uncrouch(world,before).allowed, "grounded player cannot choose feet-lowering branch")
	reset_map()
	before = state(Vector3(10.9,8,10.9),true,true)
	block(11,10,11)
	check(not MOTION.try_uncrouch(world,before).allowed, "one blocked diagonal head corner prevents standing")
	return true

func test_wade() -> bool:
	reset_map()
	block(10,1,10)
	var before := state(Vector3(10.5,.5,10.5))
	before.native_velocity = Vector3(0,-.1,0)
	var result: SourcePlayerMotion.State = MOTION.clip_move(world,before,.125,1)
	check(result.grounded and result.wading, "physical wade starts on contact when source physics-eye z>61")
	check(MOTION.get_wade(world,result), "presentation origin z>62 independently reports wade")
	before = state(Vector3(10.5,.75,10.5))
	before.native_velocity = Vector3(0,-.1,0)
	result = MOTION.clip_move(world,before,.125,1)
	check(result.grounded and not result.wading, "physical threshold is strict at eye source-z61")
	check(MOTION.get_wade(world,result), "presentation can be wading while physical friction flag is false")
	before = state(Vector3(10.5,8.01,10.5),false,false)
	before.wading = true
	before.native_velocity = Vector3(0,.1,0)
	result = MOTION.clip_move(world,before,.125,1)
	check(not result.grounded and result.wading, "physical wade persists in flight until another downward contact")
	check(not MOTION.get_wade(world,result), "render wade is recomputed from smoothed eye, not stale friction flag")
	floor_plane(7)
	before.native_velocity = Vector3(0,-.1,0)
	result = MOTION.clip_move(world,before,.125,1)
	check(result.grounded and not result.wading, "dry land contact clears stale physical wade")
	var standing := state(Vector3(10.5,.95,10.5))
	check(not MOTION.get_wade(world,standing), "standing origin on source-z62 plane is dry")
	var crouched := state(Vector3(10.5,.95,10.5),true)
	check(MOTION.get_wade(world,crouched), "same feet anchor crouch has different native origin/wade threshold")
	reset_map()
	before = state(Vector3(10.5,.01,10.5),false,false)
	before.native_velocity = Vector3(0,-.1,0)
	result = MOTION.clip_move(world,before,.125,1)
	check(result.grounded and result.wading, "empty underwater alias still has a solid native Z=64 bottom")
	vector(result.feet_position,before.feet_position, "native solid bottom preserves previous valid feet instead of clamping to water plane")
	return true

func test_landing() -> bool:
	reset_map()
	# A thick native solid column avoids destination-sample tunnelling through
	# a one-cell floor at the intentionally large test tick.
	for y in range(1,4): floor_plane(y)
	for speed in [.2,.24,.3,.58,.6]:
		var before := state()
		before.native_velocity = Vector3(.1,-speed,.1)
		var clipped: SourcePlayerMotion.State = MOTION.clip_move(world,before,.125,1)
		check(not clipped.landed, "BoxClipMove does not duplicate caller's landing handling")
		var result: SourcePlayerMotion.State = MOTION.finish_landing(clipped,speed)
		check(result.landed == (speed > .24), "native strict fall slowdown threshold: " + str(speed))
		check(result.fall_hurt == (speed > .58), "native strict hurt-event threshold: " + str(speed))
		vector(result.native_velocity,Vector3(.05 if speed > .24 else .1,0,.05 if speed > .24 else .1), "landing slowdown applied once above threshold")
		check(is_equal_approx(result.fall_speed,speed), "fall event retains incoming native speed")
	var airborne := state(Vector3(10.5,12,10.5),false,false)
	airborne.native_velocity = Vector3(0,-.8,0)
	check(not MOTION.finish_landing(MOTION.clip_move(world,airborne,.125,1),.8).landed, "high downward speed without collision is not a landing")
	var contact := state()
	contact.native_velocity.y = -.016
	check(MOTION.is_on_ground_or_wade(contact), "source ground eligibility accepts vertical speed below .017")
	contact.native_velocity.y = -.017
	check(not MOTION.is_on_ground_or_wade(contact), "source ground eligibility rejects .017 boundary")
	contact.native_velocity.y = .001
	check(not MOTION.is_on_ground_or_wade(contact), "source ground eligibility rejects rising player")
	return true

func test_long_walk() -> bool:
	reset_map()
	floor_plane(3)
	block(11,4,10)
	var moving := state(Vector3(10.1,4.01,10.5))
	var climbs: int = 0
	var highest: float = moving.feet_position.y
	for tick in range(1,201):
		# The caller provides already-integrated velocity. A fixed binary tick
		# gives an independent exact X distance (200 * .125*32/64 = 12.5).
		moving.native_velocity = Vector3(.125,-.02,0)
		var previous_feet: float = moving.feet_position.y
		moving = MOTION.clip_move(world,moving,1.0/64.0,float(tick)/64.0)
		if moving.climbed:
			climbs += 1
			check(absf(moving.feet_position.y-previous_feet-1.0)<.00002, "long walk performs the authored one-block stair height")
			check(absf(moving.eye_position.y-previous_feet-2.25)<.00002, "long walk starts smoothing at the pre-step eye")
		highest = maxf(highest,moving.feet_position.y)
	check(climbs == 1, "200-tick walk climbs exactly once without phantom repeated steps")
	check(highest >= 5.0 and highest <= 5.01002, "step elevation is bounded by one block plus original ground clearance")
	check(absf(moving.feet_position.x-22.6)<.00015, "200-tick native walk retains independent expected horizontal distance")
	check(moving.grounded and absf(moving.feet_position.y-4.01)<.025, "walker leaves the step and lands back on original terrain")
	vector(moving.eye_position,moving.physics_eye(), "completed stair trajectory has no remaining camera smoothing")
	return true

func test_crouch_cycles() -> bool:
	reset_map()
	floor_plane(3)
	var moving := state()
	for tick in range(1,101):
		moving = MOTION.set_crouch(world,moving,tick%2 == 1)
		# This downward tick exceeds the initial .01 ground clearance so each
		# transition remains grounded rather than testing an airborne switch.
		moving.native_velocity = Vector3(0,-.1,0)
		moving = MOTION.clip_move(world,moving,1.0/64.0,float(tick)/64.0)
	check(moving.grounded and not moving.crouch, "repeated grounded crouch transitions retain standing contact")
	vector(moving.feet_position,Vector3(10.5,4.01,10.5), "100 native crouch transitions do not drift foot anchor")
	vector(moving.eye_position,Vector3(10.5,6.26,10.5), "100 native crouch transitions restore original eye height")
	return true
