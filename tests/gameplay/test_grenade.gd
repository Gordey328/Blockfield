extends SceneTree
## Golden cases from Grenade::MoveGrenade, including vertical-priority collision.
var assertions := 0
var failures := 0
var bounce_count := 0
var water_count := 0

func _initialize() -> void:call_deferred("_run")

func check(value: bool,message: String) -> void:
	assertions+=1
	if not value:
		failures+=1
		push_error("GRENADE TESTS: "+message)

func _run() -> void:
	var world:=VoxelWorld.new()
	root.add_child(world)
	var session:=LocalSession.new()
	root.add_child(session)
	var grenade:=LabGrenade.new()
	grenade.world=world
	grenade.session=session
	root.add_child(grenade)
	grenade.set_physics_process(false)
	grenade.bounced.connect(func(_point:Vector3,_water:bool):bounce_count+=1)
	grenade.dropped_into_water.connect(func(_point:Vector3):water_count+=1)
	check(grenade.get_child_count()==1 and grenade.get_child(0) is Node3D and not grenade.get_child(0) is MeshInstance3D,"original grenade GLB is instantiated instead of a sphere")
	grenade.position=Vector3(10.5,15,10.5)
	grenade.velocity=Vector3(32,0,0)
	check(grenade.move_step(0.1)==0,"free flight has no collision")
	check(grenade.position.is_equal_approx(Vector3(13.7,14.68,10.5)),"native 32-scaled flight and gravity")
	check(is_equal_approx(grenade.orientation.length(),1.0) and is_equal_approx(grenade.basis.determinant(),1.0),"horizontal travel rolls a normalized quaternion")
	grenade.position=Vector3(10.5,4.1,10.5)
	grenade.velocity=Vector3(4,-8,-2)
	check(grenade.move_step(0.1)==2,"fast floor contact requests bounce audio")
	check(grenade.position.is_equal_approx(Vector3(10.5,4.1,10.5)),"collision restores the complete old position")
	check(grenade.velocity.is_equal_approx(Vector3(1.44,4.032,-0.72)),"only vertical velocity flips; all axes damp by .36")
	check(bounce_count==1,"land bounce emits once")
	grenade.position=Vector3(10.5,4.001,10.5)
	grenade.velocity=Vector3(0,-0.05,0)
	check(grenade.move_step(0.01)==1 and bounce_count==1,"quiet floor contact respects native .1 velocity threshold times32")
	world.set_block(Vector3i(11,10,10),VoxelWorld.pack_color(Color.WHITE))
	grenade.position=Vector3(10.8,10.5,10.5)
	grenade.velocity=Vector3(8,0,0)
	grenade.move_step(0.05)
	check(grenade.position.is_equal_approx(Vector3(10.8,10.5,10.5)) and grenade.velocity.is_equal_approx(Vector3(-2.88,-0.576,0)),"x wall flips horizontal x axis")
	grenade.position=Vector3(82.5,1.1,82.5)
	grenade.velocity=Vector3(0,-4,0)
	check(grenade.move_step(0.05)==0 and water_count==1,"entering the water plane emits drop without a terrain bounce")
	check(grenade.position.y<1 and bounce_count==2,"water entry uses its own event")
	var target_id:=session.add_target(Vector3(16.5,9.3,10.5))
	world.set_block(Vector3i(13,10,10),VoxelWorld.pack_color(Color.WHITE))
	grenade.position=Vector3(10.5,10.5,10.5)
	check(is_zero_approx(grenade._damage_at(Vector3(16.5,10.5,10.5))),"intact voxel cover blocks grenade damage")
	world.set_block(Vector3i(13,10,10),0)
	world.set_block(Vector3i(11,10,10),0)
	check(is_equal_approx(grenade._damage_at(Vector3(16.5,10.5,10.5)),39.0625),"offline quadratic falloff is explicit and stable")
	check(is_zero_approx(grenade._damage_at(Vector3(26.5,10.5,10.5))),"radius boundary excludes damage")
	grenade.detonate()
	check(int(session.get_target(target_id).health)==60,"one detonation applies ceil-rounded radial damage")
	grenade.detonate()
	check(int(session.get_target(target_id).health)==60,"repeated detonation cannot deal damage twice")
	await process_frame
	world.queue_free()
	session.queue_free()
	await process_frame
	print("GRENADE TESTS: %d assertions, %d failures"%[assertions,failures])
	quit(0 if failures==0 else 1)
