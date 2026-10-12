extends SceneTree
## Real shared launch/flight/bounce/fuse plus survival authority windup/lifecycle.
const MATCH = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const RULES = preload("res://simulation/player_rules.gd")
const MOTION = preload("res://gameplay/source_player_motion.gd")
const SESSION = preload("res://gameplay/offline_survival_session.gd")
const DIRECTOR = preload("res://ai/zombie_director.gd")
const ARENA = preload("res://ai/tdm_arena.gd")
var assertions: int = 0
var failures: int = 0

class IntentDirector extends DIRECTOR:
	var attack_ids: Array[int] = []
	var allowed: Dictionary[int, bool] = {}
	var intents: Array[Dictionary] = []

	func set_zombie_loadout(id: int, _generation: int, _type: String, can_throw: bool) -> void:
		allowed[id] = can_throw

	func commands(simulation: MatchSimulation) -> Dictionary:
		intents.clear()
		for id: int in attack_ids:
			if bool(allowed.get(id, false)):
				intents.append({"actor_id": id, "kind": "throw", "target": simulation.get_actor(1).feet() + Vector3.UP * 1.1})
		return {}

	func drain_attack_intents() -> Array[Dictionary]:
		return intents.duplicate(true)

	func choose_spawn(simulation: MatchSimulation, _owner_id: int = 1, _min_distance: float = 12.0) -> Dictionary:
		for z: float in [18.5, 22.5, 26.5, 30.5, 34.5, 38.5]:
			for x: float in [68.5, 72.5]:
				var point: Vector3 = Vector3(x, 4.01, z)
				if simulation._spawn_clear(point):
					return {"ok": true, "point": point, "hidden": true, "route_valid": true}
		return {"ok": false}


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("ZOMBIE GRENADES: " + message)


func simulation_fixture() -> MatchSimulation:
	var data: VoxelData = DATA.new()
	data.clear(Vector3i(64, 24, 64))
	data.seed_box(Vector3i.ZERO, Vector3i(64, 4, 64), 0x0175664f)
	var simulation: MatchSimulation = MATCH.new()
	check(simulation.configure(data).ok, "fresh real grenade authority configured")
	simulation.friendly_fire = false
	check(simulation.add_actor("Human", 2, 1, Vector3.INF, 1).ok
		and simulation.spawn_actor(1, 0, 0, Vector3(20.5, 4.01, 20.5)).ok, "human admitted on safe source floor")
	check(simulation.register_zombie_slot(2).ok and simulation.spawn_zombie_slot(2, Vector3(8.5, 4.01, 20.5)).ok
		and simulation.assign_zombie_type(2, "grenadier"), "real grenadier has explicit per-life loadout")
	simulation.step_fixed()
	simulation.drain_events()
	return simulation


func session_fixture() -> OfflineSurvivalSession:
	var arena: Dictionary = ARENA.metadata()
	arena.owner_spawn = arena.team_spawns[0][0]
	arena.supply_point = arena.owner_spawn
	var session: OfflineSurvivalSession = SESSION.new()
	root.add_child(session)
	check(session.configure_survival(ARENA.build(), arena, {"duration_seconds": 3,
		"wave_interval_seconds": 2, "preparation_seconds": 0, "zombies_per_wave": 4,
		"growth_per_minute": 0.0, "live_limit": 4, "zombie_damage": 40, "zombie_block_damage": 17}, "Human", true).ok,
		"short explicit survival fixture includes real fourth-life role")
	session._zombie_director = IntentDirector.new()
	session.drain_presentation_events()
	session.paused = false
	advance(session, 91)
	check(session.simulation.get_zombie_loadout(5).type == "grenadier", "fourth admitted life is throwable role")
	session.simulation.get_actor(5).motion = MOTION.create_state(session.get_owner_state().feet() + Vector3(12, 0, 0))
	(session._zombie_director as IntentDirector).attack_ids = [5]
	return session


func advance(session: OfflineSurvivalSession, ticks: int) -> void:
	for index: int in range(ticks):
		var owner: SharedPlayerState = session.get_owner_state()
		var result: Dictionary = session.step_local(0, Vector2.ZERO, owner.yaw, owner.pitch)
		if not result.ok:
			check(false, "valid session grenade timeline advances")
		session.drain_presentation_events()


func _run() -> void:
	_flight_profile_and_persistent_blocks()
	_capacity_stock_and_life()
	_survival_windup_pause_cleanup_restart()
	_cancel_invalid_throw()
	print("ZOMBIE GRENADES: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _flight_profile_and_persistent_blocks() -> void:
	var simulation: MatchSimulation = simulation_fixture()
	var owner: SharedPlayerState = simulation.get_actor(1)
	var target: Vector3 = owner.feet() + Vector3.UP * 1.1
	check(not simulation.throw_zombie_grenade(2, target, 40, 17).is_empty(), "trusted finite throw creates one attributed projectile")
	var projectile: SharedGrenadeState = simulation.grenades.values()[0]
	var origin: Vector3 = projectile.position
	var created: int = projectile.created_tick
	check(projectile.owner_id == 2 and projectile.owner_generation == simulation.get_actor(2).spawn_generation
		and simulation.grenades.size() == 1, "shared state retains role life and epoch")
	var bounced: int = 0
	var exploded: Dictionary = {}
	for tick_index: int in range(151):
		var events: Array[Dictionary] = simulation.step_fixed()
		bounced += MATCH.events_of(events, "grenade_bounced").size()
		var explosions: Array[Dictionary] = MATCH.events_of(events, "grenade_exploded")
		if not explosions.is_empty():
			exploded = explosions[0]
		if tick_index == 0:
			check(projectile.position != origin and owner.health == 100, "throw begins real movement without teleport explosion or early damage")
		if tick_index == 149:
			check(not projectile.finished and owner.health == 100, "exact2.5second zero fuse still flies under original strict boundary")
		simulation.drain_events()
	check(not exploded.is_empty() and simulation.tick == created + 151 and bounced > 0,
		"real bounce/fuse emits one explosion after strict deadline")
	var distance: float = owner.feet().distance_to(exploded.get("position", owner.feet()) - Vector3.UP * 0.9)
	var expected: int = ceili(40.0 * pow(maxf(0.0, 1.0 - distance / MATCH.ZOMBIE_GRENADE_RADIUS), 2.0))
	check(expected > 0 and 100 - owner.health == expected, "actual blast applies configured40peak quadraticplayer damage at real flight endpoint")
	var damaged: Dictionary[Vector3i, bool] = simulation.get_damaged_blocks()
	check(not damaged.is_empty() and simulation.drain_transactions().is_empty(), "configured17 block damage persists instead of human instant terrain deletion")
	var cell: Vector3i = damaged.keys()[0]
	check(simulation.get_block_remaining_health(cell) == 83.0, "exposed block independently takes17 damage")
	check(simulation.zombie_projectile_count() == 0 and simulation.grenades.is_empty(), "detonation releases hostile projectile capacity")
	# Deterministic ordinary flight repeats to the same exposed floor. The second
	# blast proves persistent health, independent of time and actor stock display.
	check(not simulation.throw_zombie_grenade(2, target, 40, 17).is_empty(), "second finite trusted throw accepted")
	for index: int in range(151):
		simulation.step_fixed()
		simulation.drain_events()
	check(simulation.get_block_remaining_health(cell) == 66.0, "a later real blast accumulates persistent independent block damage")
	check(simulation.data.get_block(Vector3i(cell.x, 1, cell.z)) != 0, "hostile blast preserves nondestructible foundation")
	var strong: MatchSimulation = simulation_fixture()
	check(not strong.throw_zombie_grenade(2, strong.get_actor(1).feet() + Vector3.UP * 1.1, 1, 100).is_empty(), "separate weakplayer/strongblock profile accepted")
	for index: int in range(151):
		strong.step_fixed()
		strong.drain_events()
	var receipts: Array[Dictionary] = strong.drain_transactions()
	check(receipts.size() == 1 and bool(receipts[0].changed) and receipts[0].changes.size() <= MATCH.MAX_ZOMBIE_BLAST_CELLS,
		"many blast-cell destructions commit once and collapse once")
	check(strong.get_actor(1).health >= 99, "100blockdamage cannot become100playerdamage")


func _capacity_stock_and_life() -> void:
	var simulation: MatchSimulation = simulation_fixture()
	var target: Vector3 = simulation.get_actor(1).feet() + Vector3.UP * 1.1
	for id: int in range(3, 7):
		check(simulation.register_zombie_slot(id).ok and simulation.spawn_zombie_slot(id, Vector3(8.5, 4.01, 20.5 + (id - 2) * 4)).ok
			and simulation.assign_zombie_type(id, "grenadier"), "capacity fixture admits bounded role%d" % id)
	for id: int in range(2, 6):
		check(not simulation.throw_zombie_grenade(id, target, 20, 40).is_empty(), "hostile cap admits projectile%d" % id)
	check(simulation.throw_zombie_grenade(6, target, 20, 40).is_empty() and simulation.get_zombie_loadout(6).remaining == 3,
		"four-projectile limit rejects without consuming stock or queuing debt")
	var generation: int = simulation.get_actor(2).spawn_generation
	simulation.damage_actor(2, 100, 1)
	check(simulation.throw_zombie_grenade(2, target, 20, 40).is_empty(), "dead role cannot release another projectile")
	check(simulation.spawn_zombie_slot(2, Vector3(8.5, 4.01, 20.5)).ok and simulation.assign_zombie_type(2, "walker"), "dead slot reuses a different finite role")
	var oldest: SharedGrenadeState = simulation.grenades.values()[0]
	check(oldest.owner_generation == generation and simulation.get_actor(2).spawn_generation > generation,
		"launched ordnance retains old life when registry slot recycles")
	check(not simulation.assign_zombie_type(2, "grenadier") and simulation.throw_zombie_grenade(2, target, 20, 40).is_empty(),
		"loadout assignment cannot refill ammo or upgrade current walker")
	var malicious: PlayerRules.Command = RULES.Command.new()
	malicious.sequence = 1
	malicious.spawn_generation = simulation.get_actor(3).spawn_generation
	malicious.tool = RULES.Tool.GRENADE
	malicious.buttons = RULES.Buttons.PRIMARY | RULES.Buttons.SECONDARY
	var stock: int = simulation.get_zombie_loadout(3).remaining
	simulation.step_fixed({3: malicious})
	check(not simulation.get_actor(3).cooking and simulation.get_zombie_loadout(3).remaining == stock
		and simulation.zombie_projectile_count() == 4, "director sourcebuttons cannot create/cook a second grenade authority")
	for index: int in range(151):
		simulation.step_fixed()
		simulation.drain_events()
	check(simulation.zombie_projectile_count() == 0, "dead/recycled thrower projectiles expire honestly")
	var finite: MatchSimulation = simulation_fixture()
	var finite_target: Vector3 = finite.get_actor(1).feet() + Vector3.UP * 1.1
	for attempt: int in range(3):
		check(not finite.throw_zombie_grenade(2, finite_target, 1, 1).is_empty(), "perlife finite throw%d accepted" % attempt)
	check(finite.throw_zombie_grenade(2, finite_target, 1, 1).is_empty()
		and finite.get_zombie_loadout(2).remaining == 0, "fourth perlife throw cannot borrow later-wave ammo")


func _survival_windup_pause_cleanup_restart() -> void:
	var session: OfflineSurvivalSession = session_fixture()
	advance(session, 60)
	check(session.simulation.grenades.is_empty() and session.get_target(5).attack_kind == "throw"
		and session.get_target(5).attack_phase > 0.9, "real role visibly winds up60ticks without early release")
	advance(session, 1)
	check(session.simulation.zombie_projectile_count() == 1 and session.get_target(5).throw_remaining == 2,
		"one trusted release consumes exactly one finite stock after windup")
	var projectile: SharedGrenadeState = session.simulation.grenades.values()[0]
	var tick: int = session.simulation.tick
	var position: Vector3 = projectile.position
	session.paused = true
	advance(session, 90)
	check(session.simulation.tick == tick and projectile.position == position and not projectile.finished, "pause freezes actual fuse and projectile motion")
	session.paused = false
	for id: int in [2, 3, 4, 5]:
		session.simulation.damage_actor(id, 100, 1)
	advance(session, 60)
	check(session.phase == "cleanup" and session._live_count() == 0 and not session.finished
		and session.get_survival_state().active_grenades == 1, "cleanup cannot win before a launched dead-role grenade resolves")
	advance(session, 91)
	check(session.finished and session.outcome == "win" and session.simulation.grenades.is_empty()
		and session.damage_taken > 0, "late real explosion applies configured damage before honest victory")
	var restarted: Dictionary = session.restart_match()
	check(restarted.ok and session.simulation.grenades.is_empty() and session._throw_deadlines.is_empty()
		and session._settings.zombie_damage == 40 and session._settings.zombie_block_damage == 17,
		"restart clears projectiles/cooldown and retains bothdamage settings")
	session.free()
	var cooldown: OfflineSurvivalSession = session_fixture()
	advance(cooldown, 61)
	advance(cooldown, 479)
	check(not cooldown._can_throw(5) and cooldown.get_target(5).throw_remaining == 2,
		"release cooldown cannot restart throw before480 active ticks")
	advance(cooldown, 1)
	check(cooldown._can_throw(5) and cooldown.get_target(5).throw_remaining == 2,
		"cooldown exact boundary restores eligibility, without delayed instantrelease or ammo debt")
	cooldown.free()


func _cancel_invalid_throw() -> void:
	var session: OfflineSurvivalSession = session_fixture()
	advance(session, 30)
	check(session.get_target(5).attack_kind == "throw", "cancellation fixture has actual rolewindup")
	var owner: SharedPlayerState = session.simulation.get_actor(1)
	var actor: SharedPlayerState = session.simulation.get_actor(5)
	check(not session._valid_attack(actor, {"kind": "throw", "target": Vector3.INF})
		and not session._valid_attack(actor, {"kind": "throw", "target": owner.feet() + Vector3(20, 0, 0)}),
		"nonfinite and redirected director targets reject authoritatively")
	session.simulation.data.seed_box(Vector3i(13, 4, 28), Vector3i(14, 8, 29), 0x018899aa)
	advance(session, 45)
	check(session.simulation.grenades.is_empty() and session.get_target(5).throw_remaining == 3,
		"player-built cover cancels windup with no stock/debt/projectile")
	session.free()
	var killed: OfflineSurvivalSession = session_fixture()
	advance(killed, 30)
	killed.simulation.damage_actor(5, 100, 1)
	advance(killed, 31)
	check(killed.simulation.grenades.is_empty(), "grenadier death during windup cannot manufacture delayed ordnance")
	killed.free()
