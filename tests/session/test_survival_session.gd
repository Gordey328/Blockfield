extends SceneTree
## Serial engine lease: godot --headless --path game --script ../tests/session/test_survival_session.gd
const SESSION = preload("res://gameplay/offline_survival_session.gd")
const ARENA = preload("res://ai/tdm_arena.gd")
const ZOMBIES = preload("res://ai/zombie_director.gd")
const RULES = preload("res://simulation/player_rules.gd")
const MOTION = preload("res://gameplay/source_player_motion.gd")
const DATA = preload("res://world/voxel_data.gd")
var assertions: int = 0
var failures: int = 0

class DeterministicDirector extends ZOMBIES:
	var hidden: bool = true
	var unavailable: bool = false
	var deferred: bool = false
	var attack_intents: Array[Dictionary] = []
	var calls: int = 0

	func commands(_simulation: MatchSimulation) -> Dictionary:
		return {}

	func choose_spawn(simulation: MatchSimulation, _owner_id: int = 1, _min_distance: float = 12.0) -> Dictionary:
		calls += 1
		if unavailable:
			return {"ok": false}
		if deferred:
			return {"ok": false, "budget_deferred": true}
		for z: float in [18.5, 22.5, 26.5, 30.5, 34.5, 38.5]:
			for x: float in [68.5, 72.5]:
				var point: Vector3 = Vector3(x, 4.01, z)
				if simulation._spawn_clear(point):
					return {"ok": true, "point": point, "hidden": hidden, "route_valid": true}
		return {"ok": false}

	func drain_attack_intents() -> Array[Dictionary]:
		return attack_intents.duplicate(true)

	func get_diagnostics() -> Dictionary:
		return {"calls": calls}


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("SURVIVAL SESSION: " + message)


func fixture(duration: int = 30, interval: int = 30, quota: int = 1, limit: int = 12, preparation: int = 0) -> OfflineSurvivalSession:
	var session: OfflineSurvivalSession = SESSION.new()
	root.add_child(session)
	var arena: Dictionary = ARENA.metadata()
	arena.owner_spawn = arena.team_spawns[0][0]
	arena.supply_point = arena.owner_spawn
	var settings: Dictionary = {"duration_seconds": duration, "wave_interval_seconds": interval,
		"zombies_per_wave": quota, "growth_per_minute": 0.0, "live_limit": limit, "preparation_seconds": preparation}
	var configured: Dictionary = session.configure_survival(ARENA.build(), arena, settings, "Survivor", true)
	check(configured.ok, "authored fixture configured: %s" % str(configured.get("error", "")))
	var director: DeterministicDirector = DeterministicDirector.new()
	session._zombie_director = director
	session.drain_presentation_events()
	return session


func advance(session: OfflineSurvivalSession, count: int) -> void:
	for index: int in range(count):
		var owner: SharedPlayerState = session.get_owner_state()
		var result: Dictionary = session.step_local(0, Vector2.ZERO, owner.yaw, owner.pitch)
		if not result.ok:
			check(false, "accepted fixed step: " + str(result.get("error", "")))
		session.drain_presentation_events()


func place(actor: SharedPlayerState, point: Vector3) -> void:
	actor.motion = MOTION.create_state(point)
	actor.tool_raise = 1.0


func _run() -> void:
	_pause_preparation_and_class()
	_timed_overlap_cap_and_recycling()
	_visible_spawn_warning()
	_deferred_budget_has_no_backlog()
	_cleanup_death_restart_and_failure()
	_bite_windup_wall_and_crowd()
	_shared_breach_damage_and_transactions()
	_three_height_breach_passage()
	_real_high_player_tower(4)
	_real_high_player_tower(2)
	_confirmed_shared_queue_progress()
	_supply_once_per_wave()
	_no_route_cleanup_timeout()
	print("SURVIVAL SESSION: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _pause_preparation_and_class() -> void:
	var session: OfflineSurvivalSession = fixture(30, 30, 1, 12, 1)
	check(session.simulation.actors.size() == 13 and session.targets.size() == 12, "bounded admitted slots include one human and 12 dormant zombies")
	check(session.mode == "survival" and session.simulation.mode == "sandbox", "new adapter owns mode without altering source sandbox rules")
	for id: int in SESSION.ZOMBIE_IDS:
		check(session.simulation.get_actor(id).registry_kind == "zombie" and not session.simulation.get_actor(id).is_alive(),
			"slot %d is a real inactive zombie, never a team soldier" % id)
	advance(session, 100)
	session.update(100.0)
	check(session.simulation.tick == -1 and session.wave == 0, "paused views and input freeze authority")
	session.select_weapon(2)
	check(session.current_weapon == 2 and session.magazine == 6 and session.get_survival_state().settings.preparation_seconds == 1,
		"initial class reconfiguration preserves settings")
	session._zombie_director = DeterministicDirector.new()
	session.paused = false
	advance(session, 59)
	check(session.phase == "preparation" and session.wave == 0 and session._active_ticks == 0, "preparation does not count as active survival time")
	advance(session, 1)
	check(session.phase == "active" and session.wave == 0, "preparation boundary has no premature wave")
	advance(session, 1)
	check(session.wave == 1 and session._active_ticks == 1 and session._live_count() == 1, "first active tick creates first wave")
	var owner: SharedPlayerState = session.simulation.get_actor(1)
	owner.magazine = 2
	session.select_weapon(1)
	advance(session, 1)
	check(owner.weapon == 2 and owner.magazine == 2 and owner.pending_weapon == -1, "live class selection cannot refill or promise respawn")
	session.paused = true
	var tick: int = session.simulation.tick
	var active: int = session._active_ticks
	advance(session, 100)
	check(session.simulation.tick == tick and session._active_ticks == active, "pause freezes spawn and elapsed clocks")
	var state: Dictionary = session.get_survival_state()
	state.settings.duration_seconds = 999
	check(session.get_survival_state().settings.duration_seconds == 30, "view settings are independent authority copies")
	var prior: MatchSimulation = session.simulation
	var invalid_arena: Dictionary = session._arena.duplicate(true)
	invalid_arena.owner_spawn = Vector3.INF
	check(not session.configure_survival(ARENA.build(), invalid_arena, session._settings, "Invalid", true).ok
		and session.simulation == prior, "nonfinite authored spawn rejects without changing live authority")
	session.free()


func _timed_overlap_cap_and_recycling() -> void:
	var session: OfflineSurvivalSession = fixture(4, 1, 6, 2)
	session.paused = false
	advance(session, 60)
	check(session.wave == 1 and session._live_count() == 2 and session._wave_spawned == 2 and session._wave_skipped == 4,
		"first timed window gradually admits up-to quota under live cap")
	advance(session, 1)
	check(session.wave == 2 and session._live_count() == 2 and session._wave_skipped == 1,
		"second wave starts on timer while prior enemies remain alive")
	var killed: SharedPlayerState = session.simulation.get_actor(2)
	var generation: int = killed.spawn_generation
	session.simulation.damage_actor(2, 100, 1)
	advance(session, 9)
	check(not killed.is_alive(), "dead zombie has no autonomous timed respawn")
	advance(session, 1)
	check(killed.is_alive() and killed.spawn_generation == generation + 1 and session._live_count() == 2,
		"new allocation reuses a slot immediately with a new generation")
	check(session.simulation.actors.size() == 13 and session.player_kills == 1, "recycling neither grows registry nor duplicates kill credit")
	advance(session, 49)
	check(session.wave == 2 and session._wave_spawned == 1 and session._wave_skipped == 5,
		"expired skipped quota is not added to later wave")
	advance(session, 1)
	check(session.wave == 3 and session._wave_planned == 6, "strict third wave has its own quota")
	for target: Dictionary in session.targets:
		check(target.kind == "zombie" and target.has("slot_alive") and target.has("attack_phase") and target.has("spawn_generation"),
			"view exposes zombie identity and life generation")
	session.free()


func _visible_spawn_warning() -> void:
	var session: OfflineSurvivalSession = fixture()
	var director: DeterministicDirector = session._zombie_director as DeterministicDirector
	director.hidden = false
	session.paused = false
	var owner: SharedPlayerState = session.get_owner_state()
	session.step_local(0, Vector2.ZERO, owner.yaw, owner.pitch)
	var events: Array[Dictionary] = session.drain_presentation_events()
	check(MatchSimulation.events_of(events, "zombie_spawn_warning").size() == 1 and session._live_count() == 0,
		"visible fallback warns before admission")
	advance(session, 59)
	check(session._live_count() == 0, "visible spawn remains absent for full one-second warning")
	advance(session, 1)
	check(session._live_count() == 1, "visible spawn arrives at exact warning deadline")
	session.free()
	var changed: OfflineSurvivalSession = fixture()
	(changed._zombie_director as DeterministicDirector).hidden = false
	changed.paused = false
	advance(changed, 1)
	var point: Vector3 = changed._pending_spawn.point
	place(changed.simulation.get_actor(1), point)
	advance(changed, 60)
	check(changed._live_count() == 0 and changed._skipped == 1, "spawn revalidates player distance at actual admission")
	changed.free()


func _deferred_budget_has_no_backlog() -> void:
	var session: OfflineSurvivalSession = fixture(4, 1, 6, 12)
	var director: DeterministicDirector = session._zombie_director as DeterministicDirector
	director.deferred = true
	session.paused = false
	advance(session, 35)
	check(session._spawned == 0 and session._skipped == 3, "expired deferred allocations expire at their next due interval")
	director.deferred = false
	advance(session, 1)
	check(session._spawned == 1, "recovered navigation admits only the current interval")
	advance(session, 4)
	check(session._spawned == 1, "missed allocations cannot issue a per-frame catch-up burst")
	advance(session, 20)
	check(session._spawned == 3 and session._skipped == 3, "window exposes actual and skipped counts rather than exact quota promise")
	session.free()


func _cleanup_death_restart_and_failure() -> void:
	var session: OfflineSurvivalSession = fixture(1, 1, 1)
	session.paused = false
	advance(session, 60)
	check(session.phase == "cleanup" and not session.finished and session._live_count() == 1,
		"timer expiry stops allocations and waits for real survivors")
	var spawned: int = session._spawned
	advance(session, 20)
	check(session._spawned == spawned and session.wave == 1 and session.round_remaining == 0.0,
		"cleanup neither creates new waves nor a fresh supply quota")
	var ended: Dictionary = {"count": 0}
	session.round_won.connect(func(_team: int): ended.count += 1)
	session.simulation.damage_actor(2, 100, 1)
	advance(session, 1)
	check(session.finished and session.outcome == "win" and session.finish_reason == "survived" and ended.count == 1,
		"last real enemy death completes one victory")
	var old_epoch: int = session.simulation.epoch
	var changed_cell: Vector3i = Vector3i(21, 4, 22)
	var original: int = session.simulation.data.get_block(changed_cell)
	session.simulation.data.blocks[session.simulation.data.index(changed_cell)] = 0
	var restarted: Dictionary = session.restart_match()
	check(restarted.ok and session.simulation.epoch == old_epoch + 1 and session.simulation.tick == -1
		and session.simulation.data.get_block(changed_cell) == original and session._spawned == 0 and session.player_kills == 0,
		"repeat restores baseline in a fresh epoch with clean counts")
	check(session._settings.duration_seconds == 1 and not session.finished and session.paused,
		"repeat preserves chosen settings and returns to paused preparation")
	session.free()
	var dead: OfflineSurvivalSession = fixture()
	dead.paused = false
	advance(dead, 1)
	dead.simulation.damage_actor(1, 100, 2)
	advance(dead, 1)
	check(dead.finished and dead.outcome == "defeat" and dead.phase == "finished", "owner death ends survival without waiting for respawn")
	dead.paused = false
	var tick: int = dead.simulation.tick
	advance(dead, RULES.RESPAWN_TICKS + 10)
	check(dead.simulation.tick == tick and not dead.simulation.get_actor(1).is_alive(), "finished flag freezes even after pause flag override")
	dead.free()
	var no_spawn: OfflineSurvivalSession = fixture(1, 1, 1)
	(no_spawn._zombie_director as DeterministicDirector).unavailable = true
	no_spawn.paused = false
	advance(no_spawn, 60)
	check(no_spawn.finished and no_spawn.outcome == "interrupted" and no_spawn.finish_reason == "spawn_unavailable",
		"unavailable spawn cannot give an empty victory")
	no_spawn.free()


func _bite_windup_wall_and_crowd() -> void:
	var session: OfflineSurvivalSession = fixture()
	session.paused = false
	advance(session, 1)
	var owner: SharedPlayerState = session.simulation.get_actor(1)
	var zombie: SharedPlayerState = session.simulation.get_actor(2)
	place(zombie, owner.feet() + Vector3(2.0, 0, 0))
	var director: DeterministicDirector = session._zombie_director as DeterministicDirector
	director.attack_intents = [{"actor_id": 2, "kind": "bite"}]
	advance(session, 27)
	check(owner.health == 100 and session.get_target(2).attack_phase > 0.9, "bite visibly winds up for 27 ticks without early damage")
	advance(session, 1)
	check(owner.health == 80 and session.damage_taken == 20, "one confirmed bite does 20 damage after windup")
	advance(session, 71)
	check(owner.health == 80, "next bite cannot land sooner than 72 ticks after previous hit")
	advance(session, 1)
	check(owner.health == 60, "bite cadence counts start-to-start exactly 72 ticks")
	var wall: Vector3i = Vector3i(8, 5, 28)
	session.simulation.data.seed_box(wall, wall + Vector3i.ONE, 0x018899aa)
	advance(session, 150)
	check(owner.health == 60 and not session._attacks.has(2), "wall blocks both windup and confirmed bite")
	check(session.simulation.resolve_zombie_bite(2, 1).is_empty(), "shared rules independently reject bite through terrain")
	session.free()
	var crowd: OfflineSurvivalSession = fixture()
	crowd.paused = false
	advance(crowd, 1)
	var victim: SharedPlayerState = crowd.simulation.get_actor(1)
	place(crowd.simulation.get_actor(2), victim.feet() + Vector3(-1.5, 0, 0))
	check(crowd.simulation.spawn_zombie_slot(3, victim.feet() + Vector3(1.5, 0, 0)).ok, "second attacker has an independent clear slot")
	(crowd._zombie_director as DeterministicDirector).attack_intents = [
		{"actor_id": 2, "kind": "bite"}, {"actor_id": 3, "kind": "bite"}]
	advance(crowd, 28)
	check(victim.health == 80, "shared crowd protection admits one simultaneous bite, not both")
	var malicious: PlayerRules.Command = RULES.Command.new()
	malicious.sequence = 1
	malicious.spawn_generation = crowd.simulation.get_actor(2).spawn_generation
	malicious.buttons = RULES.Buttons.PRIMARY | RULES.Buttons.SECONDARY | RULES.Buttons.RELOAD
	malicious.tool = RULES.Tool.WEAPON
	malicious.weapon = 2
	var raw: Array[Dictionary] = crowd.simulation.step_fixed({2: malicious})
	check(MatchSimulation.events_of(raw, "shot").is_empty() and MatchSimulation.events_of(raw, "spade_bash").is_empty()
		and MatchSimulation.events_of(raw, "spade_dig").is_empty() and crowd.simulation.get_actor(2).pending_weapon == -1,
		"registry policy rejects firearm/class/spade damage even from malicious director command")
	crowd.free()


func _shared_breach_damage_and_transactions() -> void:
	var timed: OfflineSurvivalSession = fixture()
	timed.paused = false
	advance(timed, 1)
	var timed_cell: Vector3i = Vector3i(9, 5, 28)
	timed.simulation.data.seed_box(timed_cell, timed_cell + Vector3i.ONE, 0x018899aa)
	place(timed.simulation.get_actor(2), Vector3(7.5, 4.01, 28.5))
	place(timed.simulation.get_actor(1), Vector3(20.5, 4.01, 28.5))
	(timed._zombie_director as DeterministicDirector).attack_intents = [{"actor_id": 2, "kind": "breach", "cell": timed_cell}]
	advance(timed, 45)
	check(timed.simulation.get_block_remaining_health(timed_cell) == 100.0 and timed.get_target(2).attack_kind == "breach",
		"breach has its own45-tick visible windup and no early damage")
	advance(timed, 1)
	check(timed.simulation.get_block_remaining_health(timed_cell) == 60.0, "session applies first breach only after full windup")
	advance(timed, 89)
	check(timed.simulation.get_block_remaining_health(timed_cell) == 60.0, "breach cycle cannot apply damage before90 ticks")
	advance(timed, 1)
	check(timed.simulation.get_block_remaining_health(timed_cell) == 20.0, "session breach cadence matches planner90-tick estimate")
	timed.free()
	var session: OfflineSurvivalSession = fixture()
	session.paused = false
	advance(session, 1)
	var cell: Vector3i = Vector3i(9, 5, 28)
	session.simulation.data.seed_box(cell, cell + Vector3i.ONE, 0x018899aa)
	place(session.simulation.get_actor(2), Vector3(7.5, 4.01, 28.5))
	place(session.simulation.get_actor(1), Vector3(20.5, 4.01, 28.5))
	check(session.simulation.get_block_remaining_health(cell) == 100.0, "untouched breach block has authoritative 100 health")
	var hit: Array[Dictionary] = session.simulation.resolve_zombie_breach(2, cell)
	check(hit.size() == 1 and session.simulation.get_block_remaining_health(cell) == 60.0
		and session.simulation.drain_transactions().is_empty(), "first slow breach damages persistent health without terrain receipt")
	check(session.simulation.resolve_zombie_breach(2, cell).is_empty(), "same cell cannot take another crowd strike in its cadence")
	advance(session, 90)
	session.simulation.resolve_zombie_breach(2, cell)
	check(session.simulation.get_block_remaining_health(cell) == 20.0, "wait does not repair damaged block")
	advance(session, 90)
	session.simulation.resolve_zombie_breach(2, cell)
	var transactions: Array[Dictionary] = session.simulation.drain_transactions()
	check(session.simulation.data.get_block(cell) == 0 and transactions.size() == 1,
		"final breach mutates Data once and emits one adopted terrain receipt")
	check(session.simulation.resolve_zombie_breach(2, Vector3i(7, 1, 28)).is_empty(), "nondestructible foundation excluded")
	var hidden: Vector3i = Vector3i(10, 5, 28)
	session.simulation.data.seed_box(cell, hidden + Vector3i.ONE, 0x01778899)
	advance(session, 90)
	check(session.simulation.resolve_zombie_breach(2, hidden).is_empty(), "breach cannot damage a hidden block through nearer terrain")
	session.free()


func _supply_once_per_wave() -> void:
	var session: OfflineSurvivalSession = fixture(15, 30, 1)
	session.paused = false
	advance(session, 1)
	var owner: SharedPlayerState = session.simulation.get_actor(1)
	owner.health = 40
	owner.reserve = 0
	owner.blocks = 0
	owner.grenades = 0
	owner.magazine = 3
	advance(session, 717)
	check(owner.reserve == 0 and session._supply_ticks == 0, "supply unavailable during spawn window")
	advance(session, 2)
	check(session._supply_ticks == 1, "supply progress starts at exact window close")
	advance(session, 118)
	check(owner.reserve == 0, "finite supply requires full uninterrupted two-second stand")
	advance(session, 1)
	check(owner.health == 65 and owner.reserve == 50 and owner.blocks == 50 and owner.grenades == 1 and owner.magazine == 3,
		"supply heals only25 and adds one grenade while preserving clip")
	owner.reserve = 0
	owner.health = 40
	advance(session, 200)
	check(owner.reserve == 0 and owner.health == 40 and session._supply_used_wave == 1 and session.phase == "cleanup" and not session.finished,
		"last-wave cleanup cannot create another treatment quota")
	session.free()
	var unsafe: OfflineSurvivalSession = fixture(30, 30, 1)
	unsafe.paused = false
	advance(unsafe, 780)
	check(unsafe._supply_ticks > 0, "safe player starts supply stand")
	var near: SharedPlayerState = unsafe.simulation.get_actor(2)
	place(near, unsafe.simulation.get_actor(1).feet() + Vector3(5, 0, 0))
	advance(unsafe, 1)
	check(unsafe._supply_ticks == 0 and unsafe._supply_status == "unsafe", "enemy danger resets supply progress entirely")
	place(near, Vector3(68.5, 4.01, 18.5))
	advance(unsafe, 40)
	check(unsafe._supply_ticks > 0, "a new safe uninterrupted stand begins after danger leaves")
	unsafe.simulation.damage_actor(1, 5, 2, "bite")
	advance(unsafe, 1)
	check(unsafe._supply_ticks == 0 and unsafe._supply_status == "unsafe", "recent actual damage resets safe supply progress")
	advance(unsafe, 119)
	check(unsafe._supply_ticks == 0, "recent-damage safety lasts a full two seconds")
	unsafe.free()


func _three_height_breach_passage() -> void:
	var session: OfflineSurvivalSession = fixture()
	session.paused = false
	advance(session, 1)
	place(session.simulation.get_actor(2), Vector3(7.5, 4.01, 28.5))
	place(session.simulation.get_actor(1), Vector3(20.5, 4.01, 28.5))
	# Adjacent side columns keep the upper body cell supported after the middle
	# is destroyed, so this proves real angled hits rather than incidental collapse.
	session.simulation.data.seed_box(Vector3i(9, 4, 27), Vector3i(10, 7, 30), 0x018899aa)
	var body: Vector3 = Vector3(9.5, 4.01, 28.5)
	check(not session.simulation._spawn_clear(body), "standing passage starts blocked across all three body cells")
	for height: int in [5, 4, 6]:
		var cell: Vector3i = Vector3i(9, height, 28)
		check(session.simulation.data.get_block(cell) != 0, "remaining passage cell stays supported at height%d" % height)
		for strike: int in range(3):
			(session._zombie_director as DeterministicDirector).attack_intents = [{"actor_id": 2, "kind": "breach", "cell": cell}]
			check(session._valid_attack(session.simulation.get_actor(2), {"kind": "breach", "cell": cell}),
				"authority windup admits exposed angled body cell%d" % height)
			var events: Array[Dictionary] = session.simulation.resolve_zombie_breach(2, cell)
			check(not events.is_empty(), "shared metric ray confirms actual body-cell strike%d/%d" % [height, strike])
			(session._zombie_director as DeterministicDirector).attack_intents.clear()
			advance(session, 90)
		check(session.simulation.data.get_block(cell) == 0, "each body cell is destroyed by its own authoritative strikes")
	check(session.simulation._spawn_clear(body) and session.simulation.data.get_block(Vector3i(9, 3, 28)) != 0,
		"full standing passage is clear and its floor support remains solid")
	session.free()


func _no_route_cleanup_timeout() -> void:
	var session: OfflineSurvivalSession = fixture(1, 1, 1)
	session.paused = false
	advance(session, 60)
	advance(session, 1201)
	check(session.finished and session.outcome == "interrupted" and session.finish_reason == "route_unavailable"
		and session.player_kills == 0 and session._live_count() == 1,
		"stalled cleanup interrupts honestly without phantom kill or victory")
	session.free()


func tower_fixture(floor_height: int) -> OfflineSurvivalSession:
	var data: VoxelData = DATA.new()
	data.clear(Vector3i(32, 24, 32))
	data.seed_box(Vector3i.ZERO, Vector3i(32, floor_height, 32), 0x0175664f)
	data.seed_box(Vector3i(16, floor_height, 16), Vector3i(17, floor_height + 8, 17), 0x018899aa)
	# The slab has one destructible support, so a real authoritative breach must
	# eventually cause unsupported-component collapse and the owner's fall.
	data.seed_box(Vector3i(15, floor_height + 7, 15), Vector3i(18, floor_height + 8, 18), 0x018899aa)
	var top: Vector3 = Vector3(16.5, floor_height + 8.01, 16.5)
	var sectors: Array[Vector3] = [Vector3(3.5, floor_height + 0.01, 16.5),
		Vector3(28.5, floor_height + 0.01, 16.5), Vector3(16.5, floor_height + 0.01, 3.5),
		Vector3(16.5, floor_height + 0.01, 28.5)]
	var arena: Dictionary = {"owner_spawn": top, "supply_point": top, "spawn_sectors": sectors,
		"floor_y": floor_height, "navigation_ceiling": 20, "walk_speed": 3.2, "authored": true}
	var settings: Dictionary = {"duration_seconds": 40, "wave_interval_seconds": 30,
		"zombies_per_wave": 3, "growth_per_minute": 0.0, "live_limit": 3, "preparation_seconds": 0}
	var session: OfflineSurvivalSession = SESSION.new()
	root.add_child(session)
	var configured: Dictionary = session.configure_survival(data, arena, settings, "Tower player", true)
	check(configured.ok, "real tower authority configures above floor%d: %s" % [floor_height, str(configured.get("error", ""))])
	session.drain_presentation_events()
	session.paused = false
	return session


func _real_high_player_tower(floor_height: int) -> void:
	var session: OfflineSurvivalSession = tower_fixture(floor_height)
	var initial_top: float = session.get_owner_state().feet().y
	var spawned: int = 0
	var breaches: int = 0
	var collapsed: int = 0
	var bites_at_height: int = 0
	var invalid_bite: bool = false
	var protected_hit: bool = false
	var invalid_spawn: bool = false
	var invalid_receipt: bool = false
	var fell: bool = false
	for tick_index: int in range(1800):
		var before: SharedPlayerState = session.get_owner_state()
		var result: Dictionary = session.step_local(0, Vector2.ZERO, before.yaw, before.pitch)
		if not result.ok:
			check(false, "actual tower fixed step accepted")
			break
		var owner: SharedPlayerState = session.get_owner_state()
		fell = fell or owner.feet().y < initial_top - 2.0
		for event: Dictionary in session.drain_presentation_events():
			if str(event.get("type", "")) == "spawn" and int(event.owner_id) != 1:
				spawned += 1
				invalid_spawn = invalid_spawn or (event.feet as Vector3).distance_to(before.feet()) < 12.0 \
					or not SESSION._supported_spawn(session.simulation.data, event.feet)
			elif str(event.get("type", "")) == "zombie_breach":
				breaches += 1
				protected_hit = protected_hit or event.cell.y <= 1
			elif str(event.get("type", "")) == "hurt" and str(event.get("cause", "")) == "bite":
				if owner.feet().y > initial_top - 0.5:
					bites_at_height += 1
				var attacker: SharedPlayerState = session.simulation.get_actor(int(event.attacker_id))
				var origin: Vector3 = attacker.feet() + Vector3.UP * 1.1
				var delta: Vector3 = owner.feet() - attacker.feet()
				var obstruction: Dictionary = session.simulation.data.cast_voxel(origin, delta, delta.length())
				invalid_bite = invalid_bite or delta.length() > SESSION.BITE_RANGE + 0.001 \
					or bool(obstruction.hit) and origin.distance_to(obstruction.position) < delta.length() - 0.05
		for transaction: Dictionary in result.transactions:
			invalid_receipt = invalid_receipt or not bool(transaction.get("ok", false))
			for change: Dictionary in transaction.get("changes", []):
				if (int(change.get("flags", 0)) & 1) != 0:
					collapsed += 1
		if session.finished or fell and collapsed > 0:
			break
	check(spawned > 0 and session._spawned == spawned and not invalid_spawn,
		"high player admits actually supported distant lives using projected lower approach above floor%d" % floor_height)
	check(breaches >= 3 and collapsed > 0 and fell and not invalid_receipt,
		"real director→windup→shared breach→receipt/collapse→owner fall completes tower timeline above floor%d" % floor_height)
	check(bites_at_height == 0 and not invalid_bite,
		"elevated player receives no distant/vertical/occluded bite above floor%d" % floor_height)
	check(not protected_hit and session.simulation.data.get_block(Vector3i(16, 1, 16)) != 0,
		"tower demolition preserves protected foundation above floor%d" % floor_height)
	check(not session.finished or session.outcome == "defeat",
		"real tower progress causes neither spawn/route interruption nor phantom victory above floor%d" % floor_height)
	session.free()


func _confirmed_shared_queue_progress() -> void:
	var session: OfflineSurvivalSession = fixture()
	session.paused = false
	advance(session, 1)
	var actor: SharedPlayerState = session.simulation.get_actor(2)
	place(actor, Vector3(7.5, 4.01, 28.5))
	place(session.simulation.get_actor(1), Vector3(20.5, 12.01, 28.5))
	check(session.simulation.spawn_zombie_slot(3, Vector3(7.5, 4.01, 29.5)).ok, "shared-cell queue admits second clear attacker")
	var cell: Vector3i = Vector3i(9, 5, 28)
	session.simulation.data.seed_box(cell, cell + Vector3i.ONE, 0x018899aa)
	(session._zombie_director as DeterministicDirector).attack_intents = [
		{"actor_id": 2, "kind": "breach", "cell": cell}, {"actor_id": 3, "kind": "breach", "cell": cell}]
	advance(session, 46)
	check(session.simulation.get_block_remaining_health(cell) == 60.0
		and int(session._progress[2].tick) == session.simulation.tick and int(session._progress[3].tick) == session.simulation.tick,
		"one real cell hit refreshes both valid queued attackers; windup alone grants no progress")
	session._progress[3].tick = session.simulation.tick - SESSION.STALL_TICKS + 1
	# A stale proposal cannot evade timeout solely by reopening its windup.
	session._attacks[3] = {"kind": "breach", "started": session.simulation.tick,
		"deadline": session.simulation.tick + 45, "windup": 45, "cell": cell}
	advance(session, 1)
	check(session.finished and session.finish_reason == "route_unavailable",
		"unconfirmed repeated windup is not mistaken for real route/health progress")
	session.free()
