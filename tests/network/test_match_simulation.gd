extends SceneTree
const MATCH = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const RULES = preload("res://simulation/player_rules.gd")
var assertions: int = 0
var failures: int = 0

func _initialize() -> void: call_deferred("_run")

func check(value: bool,message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("MATCH SIMULATION: " + message)

func fixture(mode: String = "sandbox") -> MatchSimulation:
	var data := DATA.new()
	data.clear(Vector3i(64,64,64),7)
	data.seed_box(Vector3i(0,1,0),Vector3i(64,4,64),0x01608040)
	var sim := MATCH.new()
	check(sim.configure(data,"0.75",mode).ok,"fresh authority configuration")
	return sim

func spawn(sim: MatchSimulation,name: String,team: int,feet: Vector3,weapon: int = 0) -> SharedPlayerState:
	var admitted := sim.add_actor(name)
	check(admitted.ok,"actor admitted: " + name)
	var actor: SharedPlayerState = sim.get_actor(admitted.actor_id)
	check(sim.spawn_actor(actor.player_id,team,weapon,feet).ok,"trusted safe spawn: " + name)
	actor.tool_raise = 1
	return actor

func input(actor: SharedPlayerState,buttons: int = 0,yaw: float = 0,pitch: float = 0,move: Vector2 = Vector2.ZERO) -> PlayerRules.Command:
	var command := RULES.Command.new()
	command.sequence = actor.consumed_input_sequence+1
	command.spawn_generation = actor.spawn_generation
	command.buttons = buttons
	command.yaw = yaw
	command.pitch = pitch
	command.move = move
	return command

func count(events: Array[Dictionary],type: String) -> int:
	return MATCH.events_of(events,type).size()

func _run() -> void:
	for scenario: String in ["lifecycle","gun_authority","map_occlusion","melee_and_goldens","block_building","pending_build","block_damage","grenade_death_and_owner","objectives_and_limits","snapshots_and_overflow"]:
		check(call(scenario) == true,"scenario completes: " + scenario)
	print("MATCH SIMULATION: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)

func lifecycle() -> bool:
	var sim := fixture()
	var joined := sim.add_actor("Игрок")
	var actor := sim.get_actor(joined.actor_id)
	check(actor.team == 2 and actor.spawn_generation == 1 and not actor.is_alive() and actor.last_tick == -1,"valid inactive joining spectator, no actor0")
	check(sim.spawn_actor(actor.player_id,0,0,Vector3(20.5,4.01,40.5)).ok,"join becomes playing only with trusted spawn")
	check(actor.spawn_generation == 2 and actor.magazine == 10,"spawn creates new generation and original class")
	actor.magazine = 1
	RULES.request_class(actor,2,0)
	check(not sim.spawn_actor(actor.player_id,0).ok and actor.magazine == 1 and actor.weapon == 0,"live actor cannot request spawn refills/class switch")
	check(not sim.spawn_actor(actor.player_id,1,0,Vector3(-2,4,2)).ok,"out-of-map spawn rejected")
	sim.step_fixed()
	check(sim.tick == 0 and actor.last_tick == 0,"one coordinator call advances exactly one fixed tick")
	var late := sim.add_actor("Late")
	check(sim.get_actor(late.actor_id).last_tick == 0,"joining spectator starts at current authority clock")
	sim.step_fixed()
	check(sim.get_actor(late.actor_id).last_tick == 1,"late spectator accepts next fixed step")
	check(not sim.spawn_actor(late.actor_id,1,0,actor.feet()).ok,"server spawn rejects live actor overlap")
	check(sim.spawn_actor(late.actor_id,1).ok,"authored default spawn finds an unoccupied map location")
	check(sim.set_team(actor.player_id,2).ok and actor.team == 2 and actor.health == 0,"playing-to-spectator transition stops combat")
	check(actor.deaths == 1 and not sim.spawn_actor(actor.player_id,1).ok,"authored team-change death obeys respawn eligibility")
	for unused in range(180): sim.step_fixed()
	check(sim.spawn_actor(actor.player_id,1).ok and actor.weapon == 2 and actor.magazine == 6,"eligible explicit respawn applies pending class")
	check(sim.disconnect_actor(actor.player_id).ok and not actor.connected,"disconnect retains stable actor")
	check(count(sim.disconnect_actor(actor.player_id).events,"actor_disconnected") == 0,"repeated disconnect deduplicates lifecycle event")
	check(sim.reconnect_actor(actor.player_id).ok and actor.connected and actor.last_tick == sim.tick,"reconnect restores binding without actor identity reset")
	check(sim.remove_actor(actor.player_id).ok and sim.get_actor(actor.player_id) == null,"grace-expired actor removed")
	var successor := sim.add_actor("Successor")
	check(successor.actor_id > late.actor_id,"removed IDs never reused within an epoch")
	var empty := DATA.new()
	empty.clear(Vector3i(32,32,32),9)
	var prior: VoxelData = sim.data
	check(not sim.configure(empty).ok and sim.data == prior and sim.get_actor(late.actor_id) != null,"failed no-spawn configuration preserves running match")
	check(not sim.configure(prior).ok,"running match reset requires a different epoch")
	return true

func gun_authority() -> bool:
	var sim := fixture()
	var owner := spawn(sim,"Shooter",0,Vector3(20.5,4.01,40.5))
	var victim := spawn(sim,"Victim",1,Vector3(20.5,4.01,30.5))
	var events := sim.step_fixed({owner.player_id:input(owner,RULES.Buttons.PRIMARY)})
	check(owner.magazine == 9 and victim.health == 0,"actual input shot resolves original head volume/damage")
	check(owner.kills == 1 and owner.score == 1 and victim.deaths == 1,"explicit enemy kill credit, separate victim death")
	check(count(events,"shot") == 1 and count(events,"death") == 1 and count(events,"hit_confirmed") == 1,"one shot/hit/death event sequence")
	check(count(events,"tracer") == 1 and MATCH.events_of(events,"tracer")[0].position.z > victim.feet().z,"authority emits resolved tracer endpoint at victim surface")
	var hit: Dictionary = MATCH.events_of(events,"hit_confirmed")[0]
	check(hit.owner_id == owner.player_id and hit.victim_id == victim.player_id and hit.part == "head" and not hit.friendly,"hit feedback has authoritative attribution")
	check(count(sim.damage_actor(victim.player_id,100,owner.player_id),"death") == 0 and owner.kills == 1,"repeated dead-victim damage cannot credit extra kill")
	var friend := spawn(sim,"Friend",0,Vector3(20.5,4.01,32.5))
	sim.friendly_fire = false
	for unused in range(30): sim.step_fixed({owner.player_id:input(owner,RULES.Buttons.PRIMARY)})
	check(friend.health == 100 and owner.magazine == 8,"friendly damage rejected while valid shot still costs ammo")
	sim.friendly_fire = true
	sim.damage_actor(friend.player_id,100,owner.player_id,"weapon","fixture-friendly")
	check(friend.deaths == 1 and owner.kills == 1 and owner.score == 1,"authored friendly kill gives no enemy score")
	var unbound := fixture()
	var ready := spawn(unbound,"Never fired",0,Vector3(20.5,4.01,40.5))
	var unknown := unbound.step_fixed({99999:input(ready,RULES.Buttons.PRIMARY)})
	check(count(unknown,"shot") == 0 and ready.magazine == 10,"unbound command dictionary entry cannot select a ready authority actor")
	return true

func map_occlusion() -> bool:
	var sim := fixture()
	var owner := spawn(sim,"Cover shooter",0,Vector3(20.5,4.01,40.5))
	var victim := spawn(sim,"Covered",1,Vector3(20.5,4.01,30.5))
	sim.data.seed_box(Vector3i(20,4,35),Vector3i(21,8,36),0x01dddddd)
	var first := sim.step_fixed({owner.player_id:input(owner,RULES.Buttons.PRIMARY)})
	check(victim.health == 100 and count(first,"block_hit") == 1,"nearer voxel occludes source player volume")
	check(sim.drain_transactions().is_empty(),"first rifle block hit50HP does not immediately delete")
	for unused in range(30): sim.step_fixed({owner.player_id:input(owner,RULES.Buttons.PRIMARY)})
	var transactions := sim.drain_transactions()
	check(transactions.size() == 1 and sim.data.get_block(Vector3i(20,6,35)) == 0,"second rifle hit deletes authority cell")
	check(transactions[0].actor_id == owner.player_id and transactions[0].tick == 30 and transactions[0].action_id > 0,"map edit carries server tick and stable owner/action attribution")
	check(transactions[0].changes.size() >= 2 and transactions[0].changes[-1].flags == 1,"authority collapse included in same ordered map transaction")
	check(victim.health == 100,"destroying cover does not also hit victim with same rifle pellet")
	for unused in range(30): sim.step_fixed({owner.player_id:input(owner,RULES.Buttons.PRIMARY)})
	check(victim.health == 0 and owner.magazine == 7,"later shot traverses destroyed cover, no fake precomputed hit")
	return true

func melee_and_goldens() -> bool:
	var sim := fixture()
	check(MATCH.source_weapon_hit(Vector3.ZERO,{"hit":true,"position":Vector3.UP},{"position":Vector3.UP*3}) == "player","source horizontal-zero map tie retains player")
	check(MATCH.source_weapon_hit(Vector3.ZERO,{"hit":true,"position":Vector3(128,0,0)}, {}) == "none","exact horizontal128 map boundary excluded")
	check(MATCH.source_weapon_hit(Vector3.ZERO,{"hit":false},{"position":Vector3(128,0,0)}) == "none","exact horizontal128 actor boundary excluded")
	var expected: Array[Vector3i] = [Vector3i(20,20,20),Vector3i(19,20,20),Vector3i(19,20,19),Vector3i(19,19,19)]
	check(sim.cube_line(Vector3i(20,20,20),Vector3i(8,9,9),4) == expected,"native odd crossing cube-line golden")
	var reversed: Array[Vector3i] = [Vector3i(8,9,9),Vector3i(9,9,9),Vector3i(9,10,9),Vector3i(9,10,10)]
	check(sim.cube_line(Vector3i(8,9,9),Vector3i(20,20,20),4) == reversed,"reversed cube-line source asymmetry golden")
	var owner := spawn(sim,"Spade",0,Vector3(20.5,4.01,40.5))
	var victim := spawn(sim,"Off axis",1,Vector3(23,4.01,38))
	check(sim.find_melee_target(owner.player_id,owner.motion.physics_eye(),Vector3.FORWARD,Vector3.RIGHT,Vector3.UP) == victim.player_id,"broad melee Chebyshev/cone includes off-axis actor beyond Euclidean3")
	victim.motion.feet_position.x = 23.5
	check(sim.find_melee_target(owner.player_id,owner.motion.physics_eye(),Vector3.FORWARD,Vector3.RIGHT,Vector3.UP) == -1,"melee strict3 boundary excluded")
	victim.motion.feet_position.x = 23
	sim.data.seed_box(Vector3i(20,4,39),Vector3i(21,7,40),0x01aaaaaa)
	owner.tool = 0
	owner.displayed_tool = 0
	var events := sim.step_fixed({owner.player_id:input(owner,RULES.Buttons.PRIMARY)})
	check(victim.health == 0 and count(events,"spade_block_hit") == 0,"source melee target selection precedes wall hit, does not add firearm occlusion")
	check(count(events,"hit_confirmed") == 1 and MATCH.events_of(events,"hit_confirmed")[0].part == "melee","source melee also produces attributed hit feedback")
	return true

func block_building() -> bool:
	var sim := fixture()
	var owner := spawn(sim,"Builder",0,Vector3(20.5,4.01,40.5))
	owner.tool = 1
	owner.displayed_tool = 1
	sim.data.seed_box(Vector3i(18,4,38),Vector3i(24,7,39),0x01aaaaaa)
	check(sim.set_block_color(owner.player_id,0x123456),"trusted block color accepted")
	var events := sim.step_fixed({owner.player_id:input(owner,RULES.Buttons.PRIMARY)})
	check(owner.blocks == 49 and sim.data.get_block(Vector3i(20,6,39)) == 0x01123456,"canonical ray endpoint creates colored block and charges one stock")
	check(count(events,"blocks_built") == 1 and sim.drain_transactions().size() == 1,"one authority build event/transaction")
	for unused in range(29): sim.step_fixed({owner.player_id:input(owner,RULES.Buttons.PRIMARY)})
	check(owner.blocks == 49,"block cooldown prevents held input repetition")
	var line := fixture()
	var actor := spawn(line,"Line",0,Vector3(20.5,4.01,40.5))
	actor.tool = 1
	actor.displayed_tool = 1
	line.data.seed_box(Vector3i(18,4,38),Vector3i(24,7,39),0x01aaaaaa)
	line.data.seed_box(Vector3i(21,6,39),Vector3i(22,7,40),0x01ff0000)
	line.step_fixed({actor.player_id:input(actor,RULES.Buttons.SECONDARY)})
	check(actor.blocks == 50 and line.snapshot_for(actor.player_id).line_start.has(actor.player_id),"secondary begins validated anchor without consuming stock")
	# Move the source eye to the endpoint side: the occupied middle cell
	# must not become the nearer ray hit while selecting the final endpoint.
	actor.motion.feet_position.x = 22.5
	var built := line.step_fixed({actor.player_id:input(actor)})
	check(count(built,"blocks_built") == 1 and actor.blocks == 47,"release charges all three source line cells, including occupied one")
	check(line.data.get_block(Vector3i(21,6,39)) == 0x01ff0000 and line.data.get_block(Vector3i(22,6,39)) != 0,"line preserves existing color and creates endpoint")
	check(line.drain_transactions().size() == 2,"two empty line cells produce ordered attributed edits")
	var guarded := fixture()
	var builder := spawn(guarded,"Guarded builder",0,Vector3(20.5,4.01,40.5))
	spawn(guarded,"Blocking actor",1,Vector3(20.5,4.01,39.5))
	builder.tool = 1
	builder.displayed_tool = 1
	guarded.data.seed_box(Vector3i(20,4,38),Vector3i(21,7,39),0x01aaaaaa)
	guarded.step_fixed({builder.player_id:input(builder,RULES.Buttons.PRIMARY)})
	check(builder.blocks == 50 and guarded.data.get_block(Vector3i(20,6,39)) == 0,"server placement checks every live actor overlap")
	var raising := fixture()
	var slow := spawn(raising,"Raising builder",0,Vector3(20.5,4.01,40.5))
	slow.tool=1
	slow.displayed_tool=1
	slow.tool_raise=.95
	raising.data.seed_box(Vector3i(20,4,38),Vector3i(21,7,39),0x01aaaaaa)
	raising.step_fixed({slow.player_id:input(slow,RULES.Buttons.PRIMARY)})
	check(slow.blocks == 50 and slow.tool_raise == 1,"block gate uses pre-update native raise state")
	raising.step_fixed({slow.player_id:input(slow,RULES.Buttons.PRIMARY)})
	check(slow.blocks == 49,"build opens only next input phase after complete raising")
	return true

func pending_build() -> bool:
	var sim := fixture()
	var actor := spawn(sim,"Air builder",0,Vector3(20.5,8.1,40.5))
	actor.tool = 1
	actor.displayed_tool = 1
	sim.data.seed_box(Vector3i(20,4,39),Vector3i(21,10,40),0x01bbbbbb)
	sim.step_fixed({actor.player_id:input(actor,RULES.Buttons.PRIMARY,0,-PI*.25)})
	check(sim.snapshot_for(actor.player_id).pending_cell.has(actor.player_id) and actor.blocks == 50,"airborne self overlap queues delayed source placement")
	actor.motion.feet_position.x += 1.5
	sim.step_fixed({actor.player_id:input(actor,0,0,-PI*.25)})
	check(sim.data.get_block(Vector3i(20,9,40)) != 0 and actor.blocks == 49,"pending cell builds only when within reach and clear")
	sim.step_fixed({actor.player_id:input(actor)})
	check(actor.blocks == 49 and sim.snapshot_for(actor.player_id).pending_cell.is_empty(),"pending placement is consumed once")
	return true

func block_damage() -> bool:
	var sim := fixture()
	var owner := spawn(sim,"Damage",0,Vector3(20.5,4.01,40.5))
	var cell := Vector3i(20,4,35)
	sim.data.seed_box(cell,cell+Vector3i.ONE,0x01aaaaaa)
	sim.step_fixed()
	check(not sim._damage_block(owner,cell,35),"block first35 damage survives")
	for unused in range(601): sim.step_fixed()
	check(sim.tick == 601 and sim.data.get_block(cell) == 0x01aaaaaa and sim.snapshot_for(owner.player_id).block_health.get(cell,{}).get("health",-1) == 65.0,"block retains prior HP beyond the former600-tick recovery deadline")
	for unused in range(3600): sim.step_fixed()
	check(sim.tick == 4201 and sim.snapshot_for(owner.player_id).block_health.get(cell,{}).get("health",-1) == 65.0,"a further minute of idle simulation cannot regenerate block health")
	check(sim._damage_block(owner,cell,70) and sim.data.get_block(cell) == 0,"later strike destroys using damage retained through long idle")
	check(not sim.snapshot_for(owner.player_id).block_health.has(cell) and not sim._damage_block(owner,cell,35),"destroyed air retains no block-health state and ignores further strikes")

	sim._commit(sim.data.set_block(cell,0x01aaaaaa,sim._metadata(owner)))
	check(not sim._damage_block(owner,cell,35),"newly placed block begins at100HP")
	var unchanged_sequence: int = sim.data.map_sequence
	sim._commit(sim.data.set_block(cell,0x01aaaaaa,sim._metadata(owner)))
	check(sim.data.map_sequence == unchanged_sequence and sim.snapshot_for(owner.player_id).block_health.get(cell,{}).get("health",-1) == 65.0,"same-color no-op does not repair the surviving block")
	sim._commit(sim.data.set_block(cell,0,sim._metadata(owner)))
	sim._commit(sim.data.set_block(cell,0x01aaaaaa,sim._metadata(owner)))
	check(not sim.snapshot_for(owner.player_id).block_health.has(cell),"same-color replacement through real removal/placement transactions clears old HP")
	check(not sim._damage_block(owner,cell,70) and sim.data.get_block(cell) == 0x01aaaaaa,"replacement starts fresh even with the old palette")
	check(sim._damage_block(owner,cell,35),"replacement accumulates its own new damage")

	sim._commit(sim.data.set_block(cell,0x01aaaaaa,sim._metadata(owner)))
	sim._damage_block(owner,cell,35)
	sim.data.seed_box(cell,cell+Vector3i.ONE,0x01ff0000)
	check(not sim._damage_block(owner,cell,70),"cell replacement invalidates prior material health")
	sim._commit(sim.data.set_block(cell,0x01aaaaaa,sim._metadata(owner)))
	check(not sim.snapshot_for(owner.player_id).block_health.has(cell),"committed palette repaint clears previous damage")
	sim._damage_block(owner,cell,35)
	check(not sim.configure(sim.data).ok and sim.snapshot_for(owner.player_id).block_health.get(cell,{}).get("health",-1) == 65.0,"rejected same-epoch reset preserves running block damage")
	var replacement_map := DATA.new()
	replacement_map.clear(sim.data.dimensions,sim.epoch+1)
	replacement_map.seed_box(Vector3i(0,1,0),Vector3i(64,4,64),0x01608040)
	replacement_map.seed_box(cell,cell+Vector3i.ONE,0x01aaaaaa)
	check(sim.configure(replacement_map).ok and sim.tick == -1 and sim._block_health.is_empty(),"accepted map/epoch reset clears all prior block damage")
	var reset_owner := spawn(sim,"Fresh damage",0,Vector3(20.5,4.01,40.5))
	sim.step_fixed()
	check(not sim._damage_block(reset_owner,cell,70) and sim.data.get_block(cell) == 0x01aaaaaa,"same-cell same-palette block in new epoch begins at100HP")
	var pellets := fixture()
	var shooter := spawn(pellets,"Eight pellets",0,Vector3(20.5,4.01,40.5),2)
	pellets.data.seed_box(Vector3i(19,4,37),Vector3i(22,7,39),0x01aaaaaa)
	pellets.tick = 0
	var directions: Array[Vector3] = []
	for unused in range(8): directions.append(Vector3.FORWARD)
	var shot := RULES.event(shooter,0,"shot",{"origin":shooter.motion.physics_eye(),"weapon":2,"directions":directions})
	pellets._resolve_shot(shooter,shot)
	check(pellets.data.get_block(Vector3i(20,6,38)) == 0 and pellets.data.get_block(Vector3i(20,6,37)) != 0,"shotgun destroys at most one directly hit block per discharge")
	check(pellets.drain_transactions().size() == 1,"one shotgun removal transaction despite eight pellets")
	var tools := fixture()
	var spade := spawn(tools,"Recover",0,Vector3(20.5,4.01,40.5))
	spade.tool=0
	spade.displayed_tool=0
	spade.blocks=49
	tools.data.seed_box(Vector3i(20,4,39),Vector3i(21,8,40),0x01aaaaaa)
	tools.step_fixed({spade.player_id:input(spade,RULES.Buttons.PRIMARY)})
	check(spade.blocks == 49,"surviving spade block hit does not grant inventory")
	for unused in range(13): tools.step_fixed({spade.player_id:input(spade,RULES.Buttons.PRIMARY)})
	check(spade.blocks == 50 and tools.data.get_block(Vector3i(20,6,39)) == 0,"confirmed primary destruction recovers exactly one block")
	tools.data.seed_box(Vector3i(20,5,39),Vector3i(21,8,40),0x01aaaaaa)
	tools.drain_transactions()
	spade.blocks=49
	for unused in range(62): tools.step_fixed({spade.player_id:input(spade,RULES.Buttons.SECONDARY)})
	var dug := tools.drain_transactions()
	check(dug.size() == 1 and dug[0].changes.size() == 3 and spade.blocks == 49,"secondary dig removes source three-cell column without primary recovery award")
	return true

func grenade_death_and_owner() -> bool:
	var sim := fixture()
	var owner := spawn(sim,"Grenadier",0,Vector3(20.5,4.01,40.5))
	owner.tool = 3
	owner.displayed_tool = 3
	sim.step_fixed({owner.player_id:input(owner,RULES.Buttons.PRIMARY)})
	check(owner.cooking and sim.grenades.is_empty(),"pin is actor state, no projectile until release")
	sim.clear_controls(owner.player_id)
	for unused in range(9): sim.step_fixed()
	check(sim.grenades.size() == 1 and owner.grenades == 2 and not owner.cooking,"neutral lease releases once after minimum source pin time")
	var projectile: SharedGrenadeState = sim.grenades.values()[0]
	check(projectile.owner_id == owner.player_id and projectile.owner_generation == owner.spawn_generation,"projectile retains actor and generation")
	check(sim.remove_actor(owner.player_id).ok and sim.grenades.size() == 1,"removing thrower does not delete authoritative grenade")
	for unused in range(181): sim.step_fixed()
	check(sim.grenades.is_empty() and count(sim.drain_events(),"grenade_exploded") == 1,"orphaned grenade expires exactly once")
	var death := fixture()
	var cooked := spawn(death,"Dying cook",0,Vector3(20.5,4.01,40.5))
	cooked.tool = 3
	cooked.displayed_tool = 3
	death.step_fixed({cooked.player_id:input(cooked,RULES.Buttons.PRIMARY)})
	death.damage_actor(cooked.player_id,100)
	check(death.grenades.size() == 1 and cooked.deaths == 1 and cooked.grenades == 2,"death creates one grenade from forced release")
	death.damage_actor(cooked.player_id,100)
	check(death.grenades.size() == 1 and cooked.deaths == 1,"repeat death event does not create duplicate projectile")
	var full := fixture()
	var a := spawn(full,"Last slot",0,Vector3(20.5,4.01,40.5))
	var b := spawn(full,"Wait for slot",1,Vector3(24.5,4.01,40.5))
	for actor: SharedPlayerState in [a,b]: actor.tool=3;actor.displayed_tool=3
	for id in range(1,MATCH.MAX_GRENADES):
		full.grenades[id]=GrenadeRules.create(id,a.player_id,a.spawn_generation,7,0,Vector3(10,10,10),Vector3.ZERO,3)
	full._next_grenade_id=MATCH.MAX_GRENADES
	full.step_fixed({a.player_id:input(a,RULES.Buttons.PRIMARY),b.player_id:input(b,RULES.Buttons.PRIMARY)})
	check(a.cooking and not b.cooking and b.grenades == 3,"bounded projectile slots reserve active cooks before charging stock")
	full.damage_actor(a.player_id,100)
	check(full.grenades.size() == MATCH.MAX_GRENADES and a.grenades == 2,"reserved forced death release is retained at exact capacity")
	full.grenades.erase(1)
	full.step_fixed({b.player_id:input(b,RULES.Buttons.PRIMARY)})
	check(b.cooking and b.grenades == 3,"held action may pull pin when an authoritative slot becomes available")
	return true

func objectives_and_limits() -> bool:
	var sim := fixture("ctf")
	var actor := spawn(sim,"Flag",0,Vector3(20.5,4.01,40.5))
	var bases: Array[Vector3] = [Vector3(20.5,4.01,40.5),Vector3(20.5,4.01,30.5)]
	var territories: Array[Vector3] = []
	sim.objectives.configure(7,"ctf",bases,territories,1)
	actor.motion.feet_position = bases[1]
	var picked := sim.step_fixed()
	check(count(picked,"intel_pickup") == 1 and sim.objectives.flags[1].carrier == actor.player_id,"coordinator advances actor-aware CTF")
	check(count(sim.disconnect_actor(actor.player_id).events,"intel_drop") == 1,"disconnect drops carried flag exactly once")
	check(count(sim.disconnect_actor(actor.player_id).events,"intel_drop") == 0,"repeat disconnect cannot drop again")
	sim.reconnect_actor(actor.player_id)
	actor.motion.feet_position = bases[1]
	sim.step_fixed()
	actor.motion.feet_position = bases[0]
	var captured := sim.step_fixed()
	check(count(captured,"intel_capture") == 1 and count(captured,"round_won") == 1 and actor.score == 10,"flag capture score separate from kill count")
	check(actor.kills == 0,"objective score does not fabricate kills")
	var crowded := fixture()
	check(not crowded.add_actor("Bad\nName").ok and crowded.actors.is_empty(),"control characters rejected before actor allocation")
	for index in range(32): check(crowded.add_actor("Actor%d" % index).ok,"bounded admission %d" % index)
	check(not crowded.add_actor("Overflow").ok and crowded.actors.size() == 32,"33rd actor rejected before state allocation")
	return true

func snapshots_and_overflow() -> bool:
	var sim := fixture()
	var actor := spawn(sim,"Snapshot",0,Vector3(20.5,4.01,40.5))
	var damaged_cell := Vector3i(20,4,35)
	var stale_color := Vector3i(21,4,35)
	var stale_air := Vector3i(22,4,35)
	var undamaged_cell := Vector3i(23,4,35)
	sim.data.seed_box(damaged_cell,undamaged_cell+Vector3i.ONE,0x01aaaaaa)
	for cell: Vector3i in [damaged_cell,stale_color,stale_air]: sim._damage_block(actor,cell,35)
	sim._damage_block(actor,undamaged_cell,0)
	# A bootstrap mutation deliberately bypasses _commit to exercise filtering.
	sim.data.seed_box(stale_color,stale_color+Vector3i.ONE,0x01ff0000)
	sim.data.seed_box(stale_air,stale_air+Vector3i.ONE,0)
	var damaged_baseline: Dictionary[Vector3i,bool] = sim.get_damaged_blocks()
	check(damaged_baseline.size() == 1 and damaged_baseline.get(damaged_cell,false),"joining damage baseline contains only valid damaged solid cells with matching palette")
	damaged_baseline.clear()
	check(sim.get_damaged_blocks().has(damaged_cell) and sim._block_health.size() == 4,"baseline is an independent bool copy and filtering does not sweep authority HP")
	var snapshot := sim.snapshot_for(actor.player_id)
	check(snapshot.block_health.size() == 4 and snapshot.block_health[damaged_cell].health == 65.0,"default trusted snapshot preserves private block-health shape")
	snapshot.block_health[damaged_cell].health = 1.0
	check(sim.snapshot_for(actor.player_id).block_health[damaged_cell].health == 65.0,"default private HP snapshot remains a deep copy")
	var lean_snapshot := sim.snapshot_for(actor.player_id,false)
	check(lean_snapshot.has("block_health") and lean_snapshot.block_health.is_empty() and lean_snapshot.keys() == snapshot.keys(),"wire-facing snapshot omits private HP copying while retaining dictionary shape")
	check(lean_snapshot.owner_id == snapshot.owner_id and lean_snapshot.map_sequence == snapshot.map_sequence and lean_snapshot.dimensions == snapshot.dimensions and lean_snapshot.block_colors == snapshot.block_colors,"omitting private HP retains owner and public map state")
	snapshot.owner_state.magazine = 0
	snapshot.actors[0].motion.feet_position.x += 8
	check(actor.magazine == 10 and actor.feet().x == 20.5,"owner and public actor snapshot copies cannot mutate authority")
	check(snapshot.objectives.is_read_only() and snapshot.map_sequence == sim.data.map_sequence,"objective snapshot frozen and map barrier included")
	check(sim.snapshot_for(99999).is_empty(),"unknown owner cannot acquire snapshot")
	var initial_events := sim.drain_events()
	check(initial_events.size() == 2 and initial_events[0].match_sequence == 1 and initial_events[1].match_sequence == 2,"global cursor orders join and new-generation spawn")
	check(initial_events[0].is_read_only() and initial_events[1].is_read_only(),"recorded event copies remain immutable")
	var source := RULES.event(actor,0,"dry_fire")
	sim._record_events([source])
	check(not source.has("match_sequence") and sim.drain_events()[0].match_sequence == 3,"recording annotates copy without mutating rule event")
	var many: Array[Dictionary] = []
	for index in range(2049): many.append(RULES.event(actor,0,"fixture",{"index":index}))
	sim._record_events(many)
	var overflow := sim.drain_events()
	check(overflow.size() == 1 and overflow[0].type == "events_resync_required" and overflow[0].resync_required,"event ring overflow explicit, no guessed partial history")
	check(overflow[0].match_sequence == sim.event_sequence and overflow[0].is_read_only(),"overflow marker retains global lost-history cursor")
	check(sim.drain_events().is_empty(),"event drain consumes marker once")
	var cell := Vector3i(30,4,30)
	for index in range(257): sim._commit(sim.data.set_block(cell,0x01000001+index,{"tick":0,"actor_id":actor.player_id,"action_id":index}))
	var transactions := sim.drain_transactions()
	check(transactions.size() == 1 and transactions[0].type == "map_resync_required" and transactions[0].map_sequence == sim.data.map_sequence,"bounded transaction queue announces fresh baseline requirement")
	check(sim.drain_transactions().size() == 1 and sim.resync_required,"map overflow stays explicit until trusted baseline acknowledgement")
	var baseline: VoxelData = sim.data.frozen_copy()
	var replica := DATA.new()
	check(replica.load_snapshot_bytes(baseline.snapshot_bytes(),baseline.dimensions,baseline.epoch,baseline.map_sequence) == OK,"new immutable baseline replaces gap on replica")
	check(sim.acknowledge_map_resync() and not sim.resync_required and sim.drain_transactions().is_empty(),"trusted runtime acknowledges only after invalidating old stream")
	sim._commit(sim.data.set_block(cell,0x01ffffff,{"tick":0,"actor_id":actor.player_id,"action_id":258}))
	var resumed := sim.drain_transactions()
	check(resumed.size() == 1 and resumed[0].ok and resumed[0].is_read_only() and resumed[0].changes.is_read_only(),"after resync marker new transaction stream resumes immutable")
	check(replica.apply_transaction(resumed[0]).ok and replica.get_block(cell) == sim.data.get_block(cell),"next ordered edit applies after fresh baseline without a guessed gap")
	return true
