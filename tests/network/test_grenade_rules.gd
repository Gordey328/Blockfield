extends SceneTree
## Real pure voxel query; no Main, visual grenade or local-player singleton.
const DATA = preload("res://world/voxel_data.gd")
const RULES = preload("res://simulation/grenade_rules.gd")
var assertions := 0
var failures := 0

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func _initialize() -> void:
	var world := DATA.new()
	world.clear(Vector3i(32,32,32),7)
	# Journal-free bootstrap, with a native floor and an open water column.
	for z in range(32):
		for x in range(24):
			for y in range(4): world.blocks[world.index(Vector3i(x,y,z))] = 0x01ffffff
	var flight := RULES.create(1,23,5,7,100,Vector3(10.5,15,10.5),Vector3(32,0,0),3,72)
	var second := RULES.create(2,81,9,7,100,Vector3(10.5,15,10.5),Vector3.ZERO,3,6)
	check(flight != null and second != null,"two independent attributed projectiles")
	check(RULES.create(0,23,5,7,100,Vector3.ZERO,Vector3.ZERO,3)==null,"invalid projectile ID rejected")
	check(RULES.create(3,0,5,7,100,Vector3.ZERO,Vector3.ZERO,3)==null,"transport peer zero cannot become owner")
	check(RULES.create(3,23,5,7,100,Vector3.ZERO,Vector3.ZERO,4)==null,"invalid trusted fuse rejected")
	check(RULES.step_fixed(flight,102,world).is_empty() and flight.last_tick==100,"skipped tick does not advance projectile")
	check(RULES.step_fixed(flight,101,world).is_empty(),"free flight emits no effects")
	check(flight.position.is_equal_approx(Vector3(11.033333,14.991111,10.5)),"fixed native32 displacement and gravity")
	check(flight.velocity.is_equal_approx(Vector3(32,-.533333,0)),"metre velocity has source gravity")
	check(is_equal_approx(flight.orientation.length(),1),"source rolling quaternion stays normalized")
	check(second.last_tick==100 and second.position==Vector3(10.5,15,10.5),"one projectile cannot advance another")
	var old_position: Vector3 = flight.position
	check(RULES.step_fixed(flight,101,world).is_empty() and flight.position==old_position,"duplicate tick has no motion/effect")
	var bounce := RULES.create(3,23,5,7,0,Vector3(10.5,4.1,10.5),Vector3(4,-8,-2),3)
	var events: Array[Dictionary] = RULES.step_fixed(bounce,1,world)
	check(bounce.position==Vector3(10.5,4.1,10.5),"floor collision restores complete previous position")
	check(bounce.velocity.is_equal_approx(Vector3(1.44,3.072,-.72)),"vertical priority flips one axis then damps every axis")
	check(events.size()==1 and events[0].type=="grenade_bounced","audible bounce emitted once")
	check(events.is_read_only() and events[0].is_read_only(),"effect events are immutable")
	check(events[0].owner_id==23 and events[0].spawn_generation==5 and events[0].epoch==7,"bounce retains thrower generation")
	var quiet := RULES.create(4,23,5,7,0,Vector3(10.5,4.001,10.5),Vector3(0,-.05,0),3)
	check(RULES.step_fixed(quiet,1,world).is_empty(),"native bounce threshold suppresses quiet contact")
	var water := RULES.create(5,81,9,7,0,Vector3(26.5,1.01,10.5),Vector3(0,-4,0),3)
	events = RULES.step_fixed(water,1,world)
	check(events.size()==1 and events[0].type=="grenade_water" and water.position.y<1,"water entry emits its own event")
	var expired := RULES.create(6,23,5,7,10,Vector3(10.5,10.5,10.5),Vector3.ZERO,0,91)
	events = RULES.step_fixed(expired,11,world)
	check(expired.finished and events.size()==1 and events[0].type=="grenade_exploded","zero fuse explodes before moving on next tick")
	check(expired.position==Vector3(10.5,10.5,10.5),"expired projectile does not integrate gravity")
	check(events[0].owner_id==23 and events[0].action_sequence==91,"detonation keeps original attribution after owner death")
	check(RULES.step_fixed(expired,12,world).is_empty(),"finished projectile cannot detonate twice")
	var exact := RULES.create(7,23,5,7,0,Vector3(10.5,10.5,10.5),Vector3.ZERO,1.0/60)
	check(RULES.step_fixed(exact,1,world).is_empty() and not exact.finished,"exact zero fuse preserves upstream strict boundary")
	check(RULES.step_fixed(exact,2,world).size()==1 and exact.finished,"negative fuse expires once")
	var reset := RULES.create(8,23,5,6,0,Vector3.ZERO,Vector3.ZERO,0)
	check(RULES.step_fixed(reset,1,world).is_empty() and reset.last_tick==0,"old epoch projectile cannot affect reset world")
	var cloned := second.copy()
	cloned.position.x=2
	check(second.position.x==10.5 and cloned.owner_id==81,"copy separates motion and preserves identity")
	var origin := Vector3(10.5,10.5,10.5)
	check(is_equal_approx(RULES.damage_at(origin,Vector3(16.5,10.5,10.5),world),39.0625),"authored quadratic radial damage preserved")
	check(RULES.damage_at(origin,Vector3(26.5,10.5,10.5),world)==0,"radius boundary excludes damage")
	world.blocks[world.index(Vector3i(13,10,10))]=0x01ffffff
	check(RULES.damage_at(origin,Vector3(16.5,10.5,10.5),world)==0,"intact voxel cover blocks damage")
	world.blocks[world.index(Vector3i(13,10,10))]=0
	check(RULES.damage_at(origin,origin,world)==100,"same point gives full radial damage without a zero ray")
	print("SHARED GRENADE: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures==0 else 1)
