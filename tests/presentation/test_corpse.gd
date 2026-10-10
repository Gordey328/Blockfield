extends SceneTree
const Corpse = preload("res://presentation/corpse.gd")
const Models = preload("res://presentation/openspades_models.gd")
class TestWorld extends Node3D:
	var dimensions := Vector3i(32,32,32)
	var water_level := -10.0
	var floor_enabled := false
	var blocks: Dictionary = {}
	func get_block(cell: Vector3i) -> int:
		return 1 if floor_enabled and cell.y == 0 else blocks.get(cell,0)
	func clip_box(point: Vector3) -> bool:
		return (floor_enabled and point.y < 1.0) or blocks.has(Vector3i(point.floor()))
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var world := TestWorld.new()
	root.add_child(world)
	var corpse := Corpse.new()
	root.add_child(corpse)
	var state := {"feet_position":Vector3(8,4,8),"yaw":0.0,"team":1,"player_id":7,"seed":42}
	corpse.setup(world,state)
	_check(corpse.positions.size() == 9 and corpse._parts.size() == 6,"Native nine-point body assembles six original meshes")
	_check(corpse.player_id == 7 and corpse.team == 1,"Corpse records owning player/team")
	for expectation in [[0,Vector3(8.4,6.1,8)],[1,Vector3(7.6,6.1,8)],[2,Vector3(7.6,5.2,8)],
		[6,Vector3(7.6,4.1,8)],[4,Vector3(8.2,6,7.6)],[8,Vector3(8,6.7,8)]]:
		_check(corpse.positions[expectation[0]].is_equal_approx(expectation[1]),"Native first-frame standing point " + str(expectation[0]))
	# Literal source-formula fixtures from Corpse::AddToScene, not imported screenshots.
	# Standing Torso is native identity; Head/Leg axes are (-X,-Y,+Z).
	_check(corpse._parts.Torso.transform.is_equal_approx(Transform3D(Basis(Vector3(0.1,0,0),Vector3(0,0.1,0),Vector3(0,0,-0.1)),Vector3(8,6.1,8))),"Source first-frame torso mesh matrix fixture")
	_check(corpse._parts.Head.transform.is_equal_approx(Transform3D(Basis(Vector3(-0.1,0,0),Vector3(0,0.1,0),Vector3(0,0,0.1)),Vector3(8,6.1,8))),"Source first-frame head mesh matrix fixture")
	_check(corpse._parts.Leg1.position.is_equal_approx(Vector3(8.25,5.2,8)) and corpse._parts.Leg2.position.is_equal_approx(Vector3(7.75,5.2,8)),"Source first-frame leg mesh bases use torso .25/.9 offsets")
	var arm_basis := Basis(Vector3(0.08997354,-0.01058512,-0.04234049),Vector3(0.04364358,0.02182179,0.08728716),Vector3(0,0.09701425,-0.02425356))
	_check(corpse._parts.Arm1.transform.basis.is_equal_approx(arm_basis),"Source first-frame arm mesh basis fixture")
	_check(corpse._parts.Arm1.position.is_equal_approx(Vector3(8.4,5.9,8)) and corpse._parts.Arm2.position.is_equal_approx(Vector3(7.6,5.9,8)),"Source first-frame arm mesh bases use torso .4/.2 offsets")
	var velocities := corpse.velocities.duplicate()
	corpse.add_impulse(Vector3(3.5,0,0))
	for index in range(9): _check((corpse.velocities[index]-velocities[index]).is_equal_approx(Vector3(3.5,0,0)),"Kill impulse moves every node")
	state.crouch = true
	corpse.setup(world,state)
	_check(corpse.positions[0].is_equal_approx(Vector3(8.4,5.3,7.85)),"Native first-frame crouching shoulder uses .4 lower and .3 torso offsets")
	_check(corpse.positions[6].is_equal_approx(Vector3(7.6,4.1,8.1)),"Native crouching leg origin")
	state.crouch = false
	state.yaw = PI*0.5
	corpse.setup(world,state)
	_check(corpse.positions[0].is_equal_approx(Vector3(8,6.1,7.6)),"Godot yaw rotates source first-frame body correctly")
	state.yaw = 0.0
	corpse.setup(world,state)
	corpse.velocities.fill(Vector3.ZERO)
	var initial_center := corpse.get_center()
	corpse.step(1.0/60.0)
	_check(corpse.get_center().y < initial_center.y,"Source gravity falls from a standing pose")
	_check(is_equal_approx(corpse.simulation_time,1.0/60.0),"Four source substeps cover elapsed frame")
	var unchanged := corpse.positions.duplicate()
	corpse.step(0.0)
	_check(corpse.positions == unchanged,"Zero elapsed time cannot move a cosmetic corpse")
	_check(corpse.is_visible_from(Vector3(8,8,12)),"Unobstructed body is visible")
	for x in range(32):
		for y in range(16): world.blocks[Vector3i(x,y,10)] = 1
	_check(not corpse.is_visible_from(Vector3(8,8,12)),"Opaque voxel wall occludes every body point for soft-limit pruning")
	world.blocks.clear()
	_check(not corpse.is_visible_from(Vector3(8,8,200)),"Source 150-meter distance cull")
	state.feet_position = Vector3(8,-5,8)
	corpse.setup(world,state)
	corpse.velocities.fill(Vector3.ZERO)
	world.water_level = 1.0
	initial_center = corpse.get_center()
	corpse.step(1.0/60.0)
	_check(corpse.get_center().y > initial_center.y,"Source submerged buoyancy raises a body")
	world.water_level = -10
	world.floor_enabled = true
	state.feet_position = Vector3(8,1,8)
	corpse.setup(world,state)
	corpse.add_impulse(Vector3(2.8,0,0))
	for frame in range(600):
		corpse.step(1.0/60.0)
		for point in corpse.positions: _check(point.is_finite(),"Source corpse point remains finite through collisions")
		for part: Node3D in corpse._parts.values(): _check(part.transform.basis.is_finite() and absf(part.transform.basis.determinant()) > 0.0000001,"Rendered body axes remain nondegenerate")
	_check(corpse.get_center().y < 1.8 and corpse.get_center().y > 0.7,"Source corpse settles on the voxel floor")
	for point in corpse.positions: _check(point.y >= 0.65,"Node floor collision limits spring penetration")
	var center := corpse.get_center()
	corpse.refresh_resources()
	_check(corpse.get_center() == center,"Resource reload preserves body physics state")
	world.floor_enabled = false
	world.blocks[Vector3i(10,5,8)] = 1
	corpse.positions[0] = Vector3(9.5,5.5,8.5)
	corpse.positions[1] = Vector3(11.5,5.5,8.5)
	corpse.last_positions = corpse.positions.duplicate()
	corpse.velocities.fill(Vector3.ZERO)
	corpse._line_collision(0,1,0.01)
	_check(corpse.velocities[0].z < 0 and corpse.velocities[1].z < 0,"Source line collision escapes a wall between clear endpoints")
	world.blocks.clear()
	world.blocks[Vector3i(0,5,8)] = 1
	_check(corpse._solid_wrapped(Vector3i(32,5,8)),"Source line collision wraps horizontal voxel addresses")
	corpse.clear()
	_check(corpse.positions.is_empty() and corpse._parts.is_empty(),"Clear releases points and visual parts")
	corpse.queue_free()
	world.queue_free()
	await process_frame
	await process_frame
	Models.clear_cache()
	print("CORPSE_CHECKS: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
func _check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
