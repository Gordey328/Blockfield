extends SceneTree
const CATALOG = preload("res://gameplay/arsenal_catalog.gd")
const RUNTIME = preload("res://gameplay/arsenal_runtime.gd")
const BRIDGE = preload("res://gameplay/arsenal_bridge.gd")
const DATA = preload("res://world/voxel_data.gd")
const SESSION = preload("res://gameplay/local_session.gd")
const TDM = preload("res://gameplay/offline_tdm_session.gd")
const MATCH = preload("res://simulation/match_simulation.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("ARSENAL: "+label)

func fixture(item: String = "x01") -> Dictionary:
	var data: VoxelData = DATA.new()
	data.clear(Vector3i(48,24,48),1)
	data.seed_box(Vector3i.ZERO,Vector3i(48,4,48),0x016c7367)
	var session: LocalSession = SESSION.new()
	root.add_child(session)
	session.player_position = Vector3(24.5,4.01,40.5)
	session.invulnerable = true
	var bridge: ArsenalBridge = BRIDGE.new()
	bridge.configure_data(session,data)
	var runtime: ArsenalRuntime = RUNTIME.new()
	runtime.configure(bridge,CATALOG.defaults())
	runtime.select(item)
	return {"data":data,"session":session,"bridge":bridge,"runtime":runtime,"host":0,
		"origin":Vector3(24.5,5.35,40.5),"direction":Vector3.FORWARD}

func target(f: Dictionary,offset: Vector3 = Vector3(0,0,-6)) -> int:
	return f.session.add_target(f.session.player_position+offset,1,false)

func advance(f: Dictionary,count: int = 1) -> void:
	for index: int in range(count):
		f.host += 1
		f.session.session_time = float(f.host)/60.0
		f.runtime.step()

func fire(f: Dictionary,item: String,origin: Vector3 = Vector3.INF,direction: Vector3 = Vector3.INF) -> Dictionary:
	return f.runtime.apply(item,f.origin if not origin.is_finite() else origin,f.direction if not direction.is_finite() else direction)

func ground_aim(f: Dictionary,offset: Vector3 = Vector3(0,0,-9)) -> Vector3:
	return (Vector3(f.session.player_position)+offset-f.origin).normalized()

func health(f: Dictionary,id: int) -> int:
	return int(f.session.get_target(id).health)

func finish(f: Dictionary) -> void:
	f.runtime.clear()
	f.bridge.dispose()
	f.session.free()

func events_of(f: Dictionary,type: String) -> int:
	var count: int = 0
	for event: Dictionary in f.runtime.drain_events():
		if event.type == type: count += 1
	return count

func _run() -> void:
	_drill_and_charge()
	_brick_and_arc()
	_fire_freeze_shatter()
	_saw_rockets_vacuum()
	_foam_hammer()
	_charges_popcorn_hole()
	_lure_mines_sun()
	_stratagems()
	_authority_caps_pause_reset()
	_deployable_occlusion()
	_future_terrain_backpressure()
	_drill_span_cover()
	_cold_fire_life_and_self_harm()
	_lab_fixed_clock_and_cancel()
	_bounded_status_and_motion()
	_lab_actual_respawn_identity()
	_match_credit_and_power()
	print("ARSENAL: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

func _drill_and_charge() -> void:
	var f: Dictionary = fixture()
	f.data.seed_box(Vector3i(24,4,31),Vector3i(25,7,39),0x01807353)
	var first: int = target(f,Vector3(0,0,-11))
	var second: int = target(f,Vector3(0,0,-13))
	var third: int = target(f,Vector3(0,0,-15))
	check(fire(f,"x01").ok,"x01 accepts real charge")
	advance(f,71)
	check(health(f,first)==100,"gauss does not damage before the 72-tick charge")
	advance(f)
	check(health(f,first)==10 and health(f,second)==10 and health(f,third)==100,"gauss pierces exactly two real hit volumes behind eight queued cells")
	advance(f,30)
	check(f.data.get_block(Vector3i(24,5,38))==0 and f.data.get_block(Vector3i(24,5,31))==0,"drill actually removes the eight canonical wall cells")
	check(f.runtime.readout().magazine==2,"one completed drill consumes one round")
	finish(f)

func _brick_and_arc() -> void:
	var f: Dictionary = fixture("x02")
	var id: int = target(f,Vector3(0,0,-5))
	check(fire(f,"x02").ok,"brick admitted")
	advance(f,30)
	check(health(f,id)<100,"arc-flight brick strikes an actual source volume")
	check(not f.bridge._lab_motion.is_empty(),"brick applies bounded collision motion to real lab target")
	finish(f)
	f=fixture("x03")
	var ids: Array[int] = []
	for index: int in range(5): ids.append(target(f,Vector3(float(index)*1.5,0,-5)))
	check(fire(f,"x03").ok,"electric chain admitted")
	advance(f)
	var damaged: int = 0
	for actor_id: int in ids:
		if health(f,actor_id)<100: damaged += 1
	check(damaged==4 and events_of(f,"chain")==4,"four real actors receive four distinct links; fifth remains unharmed")
	check(f.runtime.movement_scale(ids[0])<1.0,"electric hit creates life-bound movement friction")
	finish(f)

func _fire_freeze_shatter() -> void:
	var f: Dictionary = fixture("x04")
	var id: int = target(f,Vector3(0,0,-3))
	f.data.seed_box(Vector3i(24,4,34),Vector3i(25,8,35),0x015c6847)
	f.runtime.set_trigger(true,f.origin,f.direction)
	advance(f,60)
	check(health(f,id)<100 and f.runtime.readout().fields>0,"flamethrower damages real actor and leaves limited surface fire")
	check(f.runtime.readout().magazine==180 and f.runtime.readout().heat>0.0,"continuous fire spends exact fuel ticks and heats")
	f.runtime.set_trigger(false,f.origin,f.direction)
	var before: float = f.runtime.readout().heat
	advance(f,10)
	check(f.runtime.readout().heat<before,"releasing flame dissipates heat while sticky fire retains its own clock")
	finish(f)
	f=fixture("x05")
	id=target(f,Vector3(0,0,-3))
	f.runtime.set_trigger(true,f.origin,f.direction)
	advance(f,19)
	check(f.runtime.movement_scale(id)==0.0,"four real cold hits freeze the target")
	f.runtime.set_trigger(false,f.origin,f.direction)
	f.runtime.select("x10")
	check(fire(f,"x10").ok,"hammer windup accepts frozen target")
	advance(f,24)
	check(not bool(f.session.get_target(id).alive),"heavy hammer shatters frozen actor through existing death/score path")
	check(f.session.score==1,"shatter awards exactly one laboratory kill")
	finish(f)

func _saw_rockets_vacuum() -> void:
	var f: Dictionary = fixture("x06")
	f.data.seed_box(Vector3i(24,4,36),Vector3i(25,8,37),0x01708070)
	check(fire(f,"x06").ok,"one saw admitted")
	advance(f,15)
	var bounced: bool = false
	for state: Dictionary in f.runtime.visuals():
		if state.kind=="saw" and int(state.bounces)>0: bounced=true
	check(bounced,"swept saw reflects from a real voxel wall")
	check(not fire(f,"x06").ok,"second saw is rejected during flight")
	advance(f,180)
	check(f.runtime.readout().projectiles==0,"saw lifetime terminates")
	finish(f)
	f=fixture("x07")
	var id: int = target(f,Vector3(0,0,-7))
	check(fire(f,"x07").ok,"visible rocket lock admitted")
	advance(f,29)
	check(f.runtime.readout().projectiles==0,"lock takes thirty fixed ticks")
	advance(f)
	check(f.runtime.readout().projectiles==3,"one lock creates exactly three admitted micro rockets")
	advance(f,45)
	check(health(f,id)<100,"guided rockets strike real target instead of visual-only flight")
	finish(f)
	f=fixture("x08")
	id=target(f,Vector3(0,0,-3))
	var old: Vector3 = f.session.get_target(id).position
	f.runtime.set_trigger(true,f.origin,f.direction)
	advance(f,20)
	check(Vector3(f.session.get_target(id).position).z>old.z,"vacuum pulls through collision-checked laboratory motion")
	f.runtime.set_trigger(false,f.origin,f.direction)
	advance(f)
	check(f.bridge._lab_motion[id].native_velocity.z<0.0,"release changes pull to a forward push")
	finish(f)

func _foam_hammer() -> void:
	var f: Dictionary = fixture("x09")
	check(fire(f,"x09",f.origin,ground_aim(f)).ok,"foam admission checks real supported ground")
	advance(f,5)
	var foam: int = 0
	for color: int in f.data.blocks:
		if color==0x01ff93ce: foam+=1
	check(foam==9,"nine canonical solid foam cells form cover")
	advance(f,750)
	foam=0
	for color: int in f.data.blocks:
		if color==0x01ff93ce: foam+=1
	check(foam==0,"temporary cover expires on authority clock")
	finish(f)
	f=fixture("x10")
	var id: int = target(f,Vector3(0,0,-2))
	check(fire(f,"x10").ok,"hammer admitted")
	advance(f,23)
	check(health(f,id)==100,"hammer cannot damage before windup")
	advance(f)
	check(health(f,id)==35 and not f.bridge._lab_motion.is_empty(),"hammer impacts real target and imparts collision movement")
	finish(f)

func _charges_popcorn_hole() -> void:
	var f: Dictionary = fixture("x11")
	f.data.seed_box(Vector3i(24,4,32),Vector3i(25,8,33),0x01756453)
	var id: int = target(f,Vector3(1.2,0,-7))
	check(fire(f,"x11").ok,"sticky charge attaches to real voxel support")
	advance(f)
	check(f.runtime.readout().devices==1 and health(f,id)==100,"attachment is not an immediate explosion")
	check(f.runtime.alternate().ok,"remote alternate command accepted")
	advance(f)
	check(f.runtime.readout().devices==0 and health(f,id)<100,"one remote command detonates existing charge with real radial damage")
	check(not f.runtime.alternate().ok,"duplicate detonation cannot reuse consumed charges")
	finish(f)
	f=fixture("x12")
	check(fire(f,"x12").ok,"popcorn grenade reserves children")
	advance(f,61)
	var children: int = 0
	for state: Dictionary in f.runtime.visuals():
		if state.kind=="pop": children+=1
	check(children==5,"popcorn creates exactly five bouncing child charges")
	f.runtime.drain_events()
	advance(f,100)
	check(events_of(f,"explosion")==5,"children explode once each without recursive splitting")
	finish(f)
	f=fixture("x13")
	var pulled: int = target(f,Vector3(2,0,-7))
	check(fire(f,"x13",f.origin,ground_aim(f)).ok,"black hole admitted on visible ground")
	advance(f,20)
	check(f.runtime.readout().fields==1 and not f.bridge._lab_motion.is_empty(),"black-hole field applies actual pulling motion")
	advance(f,110)
	check(f.runtime.readout().fields==0 and health(f,pulled)<100,"bounded attraction ends with one damaging explosion")
	finish(f)

func _lure_mines_sun() -> void:
	var f: Dictionary = fixture("x14")
	check(fire(f,"x14",f.origin,ground_aim(f)).ok,"lure admitted")
	advance(f)
	check(f.runtime.lure_target(Vector3(26,5.5,31)).is_finite(),"live lure offers a visible finite pursuit goal")
	f.data.seed_box(Vector3i(25,4,29),Vector3i(26,9,35),0x01746764)
	check(not f.runtime.lure_target(Vector3(27,5.5,31)).is_finite(),"wall occludes lure influence")
	advance(f,365)
	check(not f.runtime.lure_target(Vector3(24,5.5,31)).is_finite(),"lure expires instead of leaving an AI goal forever")
	finish(f)
	f=fixture("x15")
	check(fire(f,"x15",f.origin,ground_aim(f)).ok,"three mines admitted")
	advance(f)
	check(f.runtime.readout().devices==3 and f.runtime.readout().stock.x15==0,"one application lays and spends the finite three-mine set")
	var mine_position: Vector3 = f.runtime.visuals()[0].position
	var id: int = f.session.add_target(mine_position+Vector3(0,.02,0),1,false)
	advance(f,58)
	check(health(f,id)==100,"mine respects its one-second arm delay")
	advance(f,40)
	check(health(f,id)<100 and f.runtime.readout().devices==0,"one step triggers a bounded three-mine launch chain")
	finish(f)
	f=fixture("x16")
	f.data.seed_box(Vector3i(20,4,26),Vector3i(30,9,35),0x017a6a59)
	var old_count: int = 0
	for color: int in f.data.blocks:
		if color!=0: old_count+=1
	check(fire(f,"x16",f.origin,ground_aim(f)).ok,"one sun bomb admitted")
	advance(f,239)
	check(events_of(f,"explosion")==0,"sun warning lasts a full four seconds")
	advance(f,60)
	var new_count: int = 0
	for color: int in f.data.blocks:
		if color!=0: new_count+=1
	check(new_count<old_count and f.runtime.readout().stock.x16==0,"sun commits a bounded real crater and consumes its only charge")
	check(not fire(f,"x16",f.origin,ground_aim(f)).ok,"one-shot sun cannot refill itself")
	finish(f)

func _stratagems() -> void:
	var f: Dictionary = fixture("x17")
	f.data.seed_box(Vector3i(23,4,30),Vector3i(26,16,33),0x017a6a59)
	check(fire(f,"x17").ok,"orbital drill targets visible terrain")
	advance(f,119)
	check(f.data.get_block(Vector3i(24,15,32))!=0,"drill preserves terrain through warning")
	advance(f,30)
	check(f.data.get_block(Vector3i(24,15,32))==0,"orbital drill removes actual column from above")
	finish(f)
	f=fixture("x18")
	check(fire(f,"x18",f.origin,ground_aim(f)).ok,"five-piano line admitted")
	advance(f)
	var pianos: int = 0
	for state: Dictionary in f.runtime.visuals():
		if state.kind=="piano": pianos+=1
	check(pianos==5,"one support call shows five distinct finite strike windows")
	f.runtime.drain_events()
	advance(f,240)
	check(events_of(f,"piano")==5,"all five piano drops complete on separate deadlines")
	finish(f)
	f=fixture("x19")
	var id: int = target(f,Vector3(2,0,-10))
	check(fire(f,"x19",f.origin,ground_aim(f)).ok,"turret supported floor admission")
	advance(f,50)
	check(health(f,id)<100,"turret autonomously damages a visible real target")
	var turret_position: Vector3 = Vector3.ZERO
	for state: Dictionary in f.runtime.visuals():
		if state.kind=="turret": turret_position=state.position
	f.runtime.damage_deployables_at(turret_position,3.0,100.0)
	advance(f)
	check(f.runtime.readout().devices==0,"hostile splash destroys turret without free replacement")
	finish(f)
	f=fixture("x20")
	check(fire(f,"x20").ok,"jet support admitted")
	advance(f)
	check(f.runtime.readout().jet_remaining>2.9 and f.runtime.readout().stock.x20==1,"jet has finite thrust and one consumed call")
	advance(f,180)
	check(f.runtime.readout().jet_remaining==0.0,"jet cannot retain infinite fuel")
	finish(f)

func _authority_caps_pause_reset() -> void:
	var f: Dictionary = fixture("x12")
	f.session.unlimited_ammo=true
	for index: int in range(4):
		check(fire(f,"x12").ok,"cluster admission reserves bounded descendant capacity")
		advance(f,1 if index==3 else 121)
	check(f.runtime.readout().projectiles<=24,"projectile budget never exceeds24 including reservations")
	check(not fire(f,"x17",f.origin+Vector3.RIGHT*10,f.direction).ok,"remote arbitrary origin cannot generate a support strike")
	var tick: int = f.runtime.readout().tick
	f.runtime.step()
	check(f.runtime.readout().tick==tick,"duplicate host tick cannot advance fuse")
	f.runtime.clear()
	check(f.runtime.visuals().is_empty() and not f.runtime.readout().enabled,"clear cancels dangerous state")
	finish(f)

func _match_credit_and_power() -> void:
	var data: VoxelData = DATA.new()
	data.clear(Vector3i(48,24,48),1)
	data.seed_box(Vector3i.ZERO,Vector3i(48,4,48),0x016c7367)
	var simulation: MatchSimulation = MATCH.new()
	check(simulation.configure(data).ok,"real match authority configures")
	simulation.add_actor("Owner",2,1,Vector3.INF,1)
	simulation.spawn_actor(1,0,0,Vector3(24.5,4.01,40.5))
	simulation.register_zombie_slot(2)
	simulation.spawn_zombie_slot(2,Vector3(24.5,4.01,34.5))
	var session: OfflineTDMSession = TDM.new()
	root.add_child(session)
	session.simulation=simulation
	session._owner=simulation.get_actor(1)
	session.paused=false
	var bridge: ArsenalBridge = BRIDGE.new()
	bridge.configure_data(session,data)
	var runtime: ArsenalRuntime = RUNTIME.new()
	runtime.configure(bridge,{"primary":"x01","bomb":"x12","stratagems":["x17","x20"]})
	check(not runtime.apply("x16",Vector3(24.5,5.35,40.5),Vector3.FORWARD).ok,"match cannot use unequipped sun despite catalog availability")
	check(simulation.set_survival_firearm_level(1,1),"Rush power attaches to real owner only")
	runtime.set_trigger(true,Vector3(24.5,5.35,40.5),Vector3.FORWARD)
	for index: int in range(72):
		simulation.step_fixed()
		runtime.step()
	check(not simulation.get_actor(2).is_alive() and simulation.get_actor(1).kills==1,"explicit gauss power tag applies real boosted damage and one canonical kill credit")
	check(simulation.get_actor(1).score==1,"kill routes through shared score exactly once")
	var tick: int = runtime.readout().tick
	session.paused=true
	for index: int in range(20): runtime.step()
	check(runtime.readout().tick==tick,"ordinary pause freezes charge and custom clocks")
	session.paused=false
	runtime.set_trigger(false,Vector3(24.5,5.35,40.5),Vector3.FORWARD)
	check(runtime.apply("x20",Vector3(24.5,5.35,40.5),Vector3.FORWARD).ok,"real matched jet admitted")
	var height: float = simulation.get_actor(1).feet().y
	for index: int in range(60):
		simulation.step_fixed()
		runtime.step()
	check(simulation.get_actor(1).feet().y>height+1.0,"jet uses native-scaled authoritative movement and actually lifts the owner")
	check(simulation.get_actor(1).motion.native_velocity.length()<=.75001,"jet thrust is bounded in original native velocity units")
	data.clear(Vector3i(48,24,48),2)
	runtime.step()
	check(not runtime.readout().enabled and runtime.visuals().is_empty(),"new map epoch cancels all old dangerous identities")
	bridge.dispose()
	session.free()

func _deployable_occlusion() -> void:
	var f: Dictionary = fixture("x11")
	check(fire(f,"x11",f.origin,ground_aim(f,Vector3(0,0,-9))).ok,"far charge admitted first")
	advance(f,25)
	check(fire(f,"x11",f.origin,ground_aim(f,Vector3(0,0,-4))).ok,"near charge admitted second")
	advance(f)
	check(f.runtime.damage_deployable(Vector3(24.5,4.3,40.5),Vector3.FORWARD,30.0),"ray damages the nearest device despite opposite insertion order")
	check(f.runtime.last_deployable_hit.is_finite() and f.runtime.last_deployable_hit.z>35,"source tracer endpoint is the near charge")
	advance(f)
	var states: Array[Dictionary] = f.runtime.visuals()
	check(states.size()==1 and Vector3(states[0].position).z<33,"far charge remains after nearer one absorbs the shot")
	f.data.seed_box(Vector3i(24,4,35),Vector3i(25,7,36),0x01746655)
	check(not f.runtime.damage_deployable(Vector3(24.5,4.3,40.5),Vector3.FORWARD,30.0),"near voxel wall occludes far device")
	check(not f.runtime.last_deployable_hit.is_finite(),"miss cannot reuse a prior source tracer endpoint")
	var removed: Array[Vector3i] = [Vector3i(24,4,35),Vector3i(24,5,35),Vector3i(24,6,35)]
	f.data.remove_blocks(removed,true,{"tick":f.host})
	target(f,Vector3(.25,0,-3))
	check(not f.runtime.damage_deployable(Vector3(24.5,4.3,40.5),Vector3.FORWARD,30.0),"near source actor volume also occludes a device")
	finish(f)

func _future_terrain_backpressure() -> void:
	var f: Dictionary = fixture("x16")
	check(fire(f,"x16",f.origin,ground_aim(f)).ok,"future crater reserves terrain admission before spending stock")
	advance(f,240)
	var center: Vector3 = Vector3.ZERO
	for state: Dictionary in f.runtime.visuals():
		if state.kind=="sun": center=state.position
	var block: Vector3i = Vector3i((center+Vector3.DOWN*.6).floor())
	var before: int = f.data.get_block(block)
	for index: int in range(8):
		var cells: Array[Vector3i] = [Vector3i(index+1,0,2)]
		check(f.bridge.terrain.queue_remove(cells,{"tick":f.host,"actor_id":0,"action_id":index}).ok,"helper queue saturates with trusted existing work")
	advance(f)
	check(events_of(f,"explosion")==1 and f.runtime.has_pending(),"full helper queue retains dangerous completion debt after one real explosion")
	check(f.data.get_block(block)==before,"crater is not rendered as an uncommitted hole")
	advance(f,10)
	check(f.data.get_block(block)==0,"reserved crater is retried and eventually commits when bounded queue frees")
	check(events_of(f,"explosion")==0,"retry cannot repeat actor damage/explosion feedback")
	finish(f)
	f=fixture("x16")
	for index: int in range(8):
		var guarded: Array[Vector3i] = [Vector3i(index+1,0,2)]
		check(f.bridge.terrain.queue_remove(guarded,{"tick":0}).ok,"old helper work reserves each bounded queue slot")
	var cell: Vector3i = Vector3i(24,3,30)
	var cells: Array[Vector3i] = [cell]
	var original: int = f.data.get_block(cell)
	check(f.bridge.reserve(1) and f.bridge.remove(cells,true).ok,"real impact keeps guarded deferred deletion")
	f.data.set_block(cell,0,{"tick":0})
	f.data.set_block(cell,original,{"tick":0})
	advance(f,3)
	check(f.data.get_block(cell)==original,"old deferred impact cannot delete a later same-color source replacement")
	check(f.bridge._watched_cells.is_empty(),"completed deferred guards release sparse mutation watches")
	finish(f)

func _drill_span_cover() -> void:
	var f: Dictionary = fixture("x17")
	f.data.seed_box(Vector3i(24,4,31),Vector3i(25,21,32),0x017a6a59)
	var below: int = target(f,Vector3(0,0,-9))
	check(fire(f,"x17").ok,"tall pillar gives a real finite-depth orbital target")
	advance(f,122)
	check(health(f,below)==100,"actor below the twelve-cell drill span remains protected")
	finish(f)
	f=fixture("x17")
	f.data.seed_box(Vector3i(24,4,31),Vector3i(25,15,32),0x017a6a59)
	f.data.seed_box(Vector3i(25,17,31),Vector3i(26,18,32),0x017a6a59)
	var covered: int = target(f,Vector3(.8,0,-9))
	check(fire(f,"x17").ok,"central pillar sets drill span independently of adjacent higher roof")
	advance(f,122)
	check(health(f,covered)==100,"an unlisted adjacent roof occludes actor damage even inside horizontal blast width")
	finish(f)

func _cold_fire_life_and_self_harm() -> void:
	var f: Dictionary = fixture("x05")
	var id: int = target(f,Vector3(0,0,-3))
	f.runtime.set_trigger(true,f.origin,f.direction)
	advance(f,19)
	check(f.runtime.movement_scale(id)==0.0,"cold test begins with a real frozen actor")
	f.runtime.set_trigger(false,f.origin,f.direction)
	f.runtime.select("x04")
	f.runtime.set_trigger(true,f.origin,f.direction)
	advance(f,6)
	check(f.runtime.movement_scale(id)==1.0,"actual flame removes cold before applying burning damage")
	f.runtime.set_trigger(false,f.origin,f.direction)
	f.session.apply_target_damage(id,100.0)
	f.session.get_target(id).alive=true
	f.session.get_target(id).health=100
	check(f.runtime.movement_scale(id)==1.0,"old cold identity cannot slow a recycled target life")
	finish(f)
	f=fixture("x16")
	f.session.invulnerable=false
	check(fire(f,"x16",f.origin,ground_aim(f,Vector3(0,0,-2))).ok,"risky sun admits a nearby visible point")
	advance(f,242)
	check(f.session.health==0 and not f.runtime.readout().enabled,"nearby sun really kills owner and cancels remaining dangerous arsenal")
	check(f.runtime.visuals().is_empty(),"owner death cannot leave hazardous ordnance visuals running")
	finish(f)

func _lab_fixed_clock_and_cancel() -> void:
	var f: Dictionary = fixture("x16")
	check(fire(f,"x16",f.origin,ground_aim(f)).ok,"fixed-clock test admits a real delayed bomb")
	check(f.bridge.advance_lab_tick(),"first allowed lab physics step adopts its own counter")
	f.runtime.step()
	var first: float = f.runtime.visuals()[0].remaining
	check(f.bridge.advance_lab_tick(),"second physics step advances without a session render update")
	f.runtime.step()
	check(f.session.session_time==0.0 and f.runtime.readout().tick==2,"two physics ticks advance independently of the unchanged render clock")
	check(f.runtime.visuals()[0].remaining<first,"same-frame second step advances the actual bomb fuse")
	var frozen: float = f.runtime.visuals()[0].remaining
	check(not f.bridge.advance_lab_tick(false),"pause/loading gate cannot increment the lab authority counter")
	f.runtime.step()
	check(f.runtime.visuals()[0].remaining==frozen,"paused duplicate counter cannot advance delayed ordnance")
	finish(f)
	f=fixture("x09")
	check(fire(f,"x09",f.origin,ground_aim(f)).ok,"death cleanup begins with real temporary cover")
	advance(f,5)
	f.session.invulnerable=false
	f.session.damage_player(100.0)
	for index: int in range(12):
		check(f.bridge.advance_lab_tick(),"dead lab owner does not stop the separately gated world cleanup clock")
		f.runtime.step()
	var remaining_foam: int = 0
	for color: int in f.data.blocks:
		if color==0x01ff93ce: remaining_foam+=1
	check(not f.runtime.readout().enabled and remaining_foam==0 and not f.runtime.has_pending(),"dead-owner fixed ticks clear danger and finish foam transactions without waiting for respawn")
	finish(f)
	f=fixture("x16")
	check(fire(f,"x16",f.origin,ground_aim(f)).ok,"uncommitted bomb confirmation can be queued before a context change")
	f.runtime.cancel_trigger()
	advance(f,250)
	check(f.runtime.visuals().is_empty() and f.runtime.readout().stock.x16==1,"pause/GUI cancellation discards uncommitted bomb edges without spending stock or a deferred explosion")
	finish(f)
	f=fixture("x01")
	var id: int = target(f,Vector3(0,0,-6))
	f.runtime.set_trigger(true,f.origin,f.direction)
	advance(f,71)
	check(f.runtime.readout().charge>.98 and health(f,id)==100,"real held gauss reaches a nearly complete charge")
	f.runtime.cancel_trigger()
	advance(f,80)
	check(health(f,id)==100 and f.runtime.readout().magazine==3 and f.runtime.readout().charge==0.0,"GUI cancellation cannot defer a held charged shot until resume")
	check(fire(f,"x01").ok,"queued primary charge accepts an explicit tap")
	advance(f,20)
	f.runtime.cancel_trigger()
	advance(f,80)
	check(health(f,id)==100 and f.runtime.readout().magazine==3,"modal cancellation also discards an uncommitted queued primary windup")
	finish(f)
	f=fixture("x08")
	id=target(f,Vector3(0,0,-3))
	f.runtime.set_trigger(true,f.origin,f.direction)
	advance(f,8)
	var before: float = f.bridge.velocity_mps(id).z
	check(before>0.0,"vacuum holds a real target moving toward owner")
	f.runtime.cancel_trigger()
	advance(f)
	check(f.bridge.velocity_mps(id).z>=0.0,"focus/GUI cancellation does not turn a vacuum hold into its attack release push")
	finish(f)

func _bounded_status_and_motion() -> void:
	var f: Dictionary = fixture("x05")
	var ids: Array[int] = []
	# Public lab admission remains independent of decorative/status budgets.
	# Trusted ray resolution fills one simultaneous status batch for this fixture.
	for index: int in range(33):
		var angle: float = float(index)*TAU/33.0
		ids.append(target(f,Vector3(cos(angle)*6.0,0,sin(angle)*6.0)))
	for index: int in range(32):
		var point: Vector3 = Vector3(f.session.get_target(ids[index]).position)+Vector3.UP*1.25
		f.runtime._freeze_ray(f.origin,(point-f.origin).normalized())
	check(f.runtime.readout().statuses==32 and f.session.targets.size()==33,"32 active status records cap metadata without restricting the real lab roster")
	var last: int = ids[32]
	var point: Vector3 = Vector3(f.session.get_target(last).position)+Vector3.UP*1.25
	f.runtime._freeze_ray(f.origin,(point-f.origin).normalized())
	check(health(f,last)==96 and f.runtime.readout().statuses==32,"saturated cold status still deals real target damage and never dereferences an empty record")
	check(f.runtime.movement_scale(last)==1.0 and f.runtime.movement_scale(ids[0])<1.0,"status saturation refuses the new modifier without evicting an existing live one")
	f.runtime._slow(last,120,.25)
	check(f.runtime.movement_scale(last)==1.0,"arc slow also safely refuses a saturated status slot")
	advance(f,121)
	check(f.runtime.readout().statuses==0 and f.runtime.movement_scale(ids[0])==1.0,"fully expired statuses retire while their original actors remain alive")
	f.runtime._freeze_ray(f.origin,(point-f.origin).normalized())
	check(f.runtime.readout().statuses==1 and health(f,last)==92,"retired capacity can admit new real cold damage and a modifier")
	f.session.get_target(last).health=4
	f.runtime._freeze_ray(f.origin,(point-f.origin).normalized())
	check(not bool(f.session.get_target(last).alive),"lethal cold damage safely finishes before requesting a nonexistent target status")
	finish(f)
	f=fixture("x05")
	var id: int = target(f,Vector3(0,0,-3))
	f.session.get_target(id).health=1000
	for index: int in range(4): f.runtime._freeze_ray(f.origin,f.direction)
	check(f.runtime.movement_scale(id)==0.0,"actual cold damage begins a same-life freeze and immunity interval")
	advance(f,100)
	check(f.runtime.readout().statuses==1 and f.runtime.movement_scale(id)>0.0,"expired freeze retains immunity instead of reclaiming its live record early")
	for index: int in range(4): f.runtime._freeze_ray(f.origin,f.direction)
	check(f.runtime.movement_scale(id)>0.0,"new cold hits cannot bypass retained same-life immunity")
	advance(f,171)
	check(f.runtime.readout().statuses==0,"immunity deadline permits retiring a fully expired live-actor record")
	for index: int in range(4): f.runtime._freeze_ray(f.origin,f.direction)
	check(f.runtime.movement_scale(id)==0.0,"after immunity expires cold can freeze that same living actor again")
	var new_life: Dictionary = f.session.get_target(id)
	new_life.deaths+=1
	new_life.health=1000
	check(f.runtime.movement_scale(id)==1.0,"recycled target life cannot inherit the old frozen modifier")
	f.runtime._hit(id,65.0,"x10",true)
	check(health(f,id)==935,"a stale freeze cannot grant a heavy shatter bonus against a new life")
	finish(f)
	f=fixture("x08")
	ids.clear()
	for index: int in range(40):
		var angle: float = float(index)*TAU/40.0
		ids.append(target(f,Vector3(cos(angle)*6.0,0,sin(angle)*6.0)))
	for actor_id: int in ids: f.bridge.impulse(actor_id,Vector3.RIGHT*6.0)
	check(f.bridge._lab_motion.size()==32 and f.session.targets.size()==40,"32 motion slots cap impulses without restricting original actor admission")
	var extra: int = ids[39]
	var refused_position: Vector3 = f.session.get_target(extra).position
	var old_position: Vector3 = f.session.get_target(ids[0]).position
	advance(f)
	check(Vector3(f.session.get_target(ids[0]).position).x>old_position.x,"admitted impulses still move actual source-clipped targets")
	check(f.session.get_target(extra).position==refused_position and f.bridge.velocity_mps(extra)==Vector3.ZERO,"overflow actor remains unchanged instead of creating an unbounded impulse record")
	var old_velocity: float = f.bridge.velocity_mps(ids[0]).x
	f.bridge.impulse(ids[0],Vector3.RIGHT*6.0)
	check(f.bridge.velocity_mps(ids[0]).x>old_velocity and f.bridge._lab_motion.size()==32,"saturated motion pool still updates an existing admitted actor")
	f.bridge.damage(extra,10.0,"x08")
	check(health(f,extra)==90,"refused impulse does not suppress ordinary authoritative target damage")
	advance(f,150)
	check(f.bridge._lab_motion.is_empty() and f.bridge._lab_motion_generation.is_empty(),"grounded impulses and their life guards retire after natural velocity decay")
	f.bridge.impulse(extra,Vector3.RIGHT*6.0)
	check(f.bridge._lab_motion.size()==1,"expired impulse capacity admits a new actual actor")
	var recycled: Dictionary = f.session.get_target(extra)
	recycled.deaths+=1
	check(f.bridge.velocity_mps(extra)==Vector3.ZERO,"recycled lab life cannot expose stale impulse velocity")
	advance(f)
	check(f.bridge._lab_motion.is_empty(),"fixed processing retires a recycled motion life before moving it")
	finish(f)

func _lab_actual_respawn_identity() -> void:
	var f: Dictionary = fixture("x16")
	var original_map: PackedInt32Array = f.data.blocks.duplicate()
	var original_generation: int = f.bridge.generation()
	var original_deaths: int = f.session.player_deaths
	f.session.select_team(2)
	advance(f)
	check(not f.runtime.readout().enabled and f.bridge.generation()==original_generation,"spectator clears actions without inventing a new spawned life")
	f.session.select_team(0)
	check(f.bridge.generation()==original_generation+1 and f.session.player_deaths==original_deaths,"spectator to Blue gets a real new identity despite unchanged death count")
	f.runtime.configure(f.bridge,CATALOG.defaults())
	check(f.runtime.readout().enabled,"coordinator can reconfigure the previously disabled lab arsenal on the new actual life")
	check(fire(f,"x16",f.origin,ground_aim(f)).ok,"Blue life admits pending sun")
	advance(f)
	check(not f.runtime.visuals().is_empty(),"pending Blue ordnance is genuinely active before team switch")
	f.session.select_team(1)
	check(f.bridge.generation()==original_generation+2 and f.session.player_deaths==original_deaths,"direct Blue to Green respawn increments identity exactly once")
	advance(f)
	check(not f.runtime.readout().enabled and f.runtime.visuals().is_empty(),"next fixed step cancels old Blue ordnance against a living Green replacement")
	f.runtime.configure(f.bridge,CATALOG.defaults())
	check(fire(f,"x16",f.origin,ground_aim(f)).ok,"Green replacement starts its own admitted bomb")
	advance(f)
	f.session.respawn()
	check(f.bridge.generation()==original_generation+3,"manual actual respawn creates a fresh life without a death")
	advance(f)
	check(not f.runtime.readout().enabled and f.runtime.visuals().is_empty(),"manual respawn cancels previous pending ordnance at the next fixed boundary")
	check(f.data.blocks==original_map,"spectator/team/manual life transitions preserve original canonical terrain")
	var old_session: LocalSession = f.session
	var replacement: LocalSession = SESSION.new()
	root.add_child(replacement)
	replacement.player_position=old_session.player_position
	f.bridge.configure_data(replacement,f.data)
	var callback: Callable = Callable(f.bridge,"_on_lab_respawn")
	check(not old_session.player_respawned.is_connected(callback) and replacement.player_respawned.is_connected(callback),"reconfigure disconnects the original observer and connects exactly the replacement session")
	var replacement_generation: int = f.bridge.generation()
	check(replacement_generation>original_generation+3,"reconfigure starts a new monotonic identity even when the replacement has fewer deaths")
	old_session.respawn()
	check(f.bridge.generation()==replacement_generation,"an old session respawn cannot mutate the replacement bridge life")
	replacement.respawn()
	check(f.bridge.generation()==replacement_generation+1,"replacement's real respawn owns its monotonic life counter")
	# Simulate a host replacing the public adapter before disposal. Disconnect
	# must still resolve the independently observed weak source, without retaining it.
	f.bridge.session=old_session
	f.bridge.dispose()
	check(not replacement.player_respawned.is_connected(callback) and f.bridge._lab_respawn_source==null,"dispose disconnects the observed source even after the public session field was replaced")
	f.runtime.clear()
	old_session.free()
	replacement.free()
