extends SceneTree
## Rush authority: canonical runs, committed hits, clock barriers and finite choices.
const SESSION = preload("res://gameplay/offline_survival_session.gd")
const SETTINGS = preload("res://gameplay/survival_settings.gd")
const MATCH = preload("res://simulation/match_simulation.gd")
const DATA = preload("res://world/voxel_data.gd")
const RULES = preload("res://simulation/player_rules.gd")
const MOTION = preload("res://gameplay/source_player_motion.gd")
const DIRECTOR = preload("res://ai/zombie_director.gd")
var assertions: int = 0
var failures: int = 0

class QuietDirector extends DIRECTOR:
	func commands(_simulation: MatchSimulation) -> Dictionary:
		return {}
	func choose_spawn(_simulation: MatchSimulation, _owner_id: int = 1, _min_distance: float = 12.0) -> Dictionary:
		return {"ok": false, "budget_deferred": true}
	func drain_attack_intents() -> Array[Dictionary]:
		return []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error("RUSH SESSION: " + message)

func map_fixture(epoch: int = 1) -> VoxelData:
	var data: VoxelData = DATA.new()
	data.clear(Vector3i(64, 24, 64), epoch)
	data.seed_box(Vector3i.ZERO, Vector3i(64, 4, 64), 0x0175664f)
	return data

func session_fixture(rush: bool = true) -> OfflineSurvivalSession:
	var session: OfflineSurvivalSession = SESSION.new()
	root.add_child(session)
	var arena: Dictionary = {"owner_spawn": Vector3(20.5, 4.01, 40.5), "supply_point": Vector3(45.5, 4.01, 45.5)}
	check(session.configure_survival(map_fixture(), arena, SETTINGS.rush_defaults() if rush else SETTINGS.defaults()).ok,
		"real serverless run configures its supported floor and bounded actors")
	session._zombie_director = QuietDirector.new()
	session.paused = false
	return session

func advance(session: OfflineSurvivalSession, ticks: int = 1) -> void:
	for index: int in range(ticks):
		var owner: SharedPlayerState = session.get_owner_state()
		check(session.step_local(0, Vector2.ZERO, owner.yaw, owner.pitch).ok, "valid fixed input advances or freezes")

func credit_kills(session: OfflineSurvivalSession, count: int) -> void:
	for index: int in range(count):
		if not session.simulation.get_actor(2).is_alive():
			check(session.simulation.spawn_zombie_slot(2, Vector3(40.5, 4.01, 20.5)).ok, "new enemy life admitted without unbounded actor IDs")
		var events: Array[Dictionary] = session.simulation.damage_actor(2, 100, 1)
		check(MATCH.events_of(events, "kill_credit").size() == 1, "one real committed death yields one owner credit")
	advance(session)

func match_fixture() -> MatchSimulation:
	var simulation: MatchSimulation = MATCH.new()
	check(simulation.configure(map_fixture()).ok, "fresh pure simulation configured")
	check(simulation.add_actor("Human", 2, 1, Vector3.INF, 1).ok
		and simulation.spawn_actor(1, 0, 0, Vector3(20.5, 4.01, 40.5)).ok, "human ready for real rules")
	check(simulation.register_zombie_slot(2).ok
		and simulation.spawn_zombie_slot(2, Vector3(20.5, 4.01, 30.5)).ok, "enemy ready for source hit volumes")
	return simulation

func fire_torso(simulation: MatchSimulation) -> Array[Dictionary]:
	var owner: SharedPlayerState = simulation.get_actor(1)
	var victim: SharedPlayerState = simulation.get_actor(2)
	owner.tool_raise = 1.0
	var direction: Vector3 = (victim.feet() + Vector3.UP * 1.5 - owner.motion.physics_eye()).normalized()
	var command: PlayerRules.Command = RULES.Command.new()
	command.sequence = owner.consumed_input_sequence + 1
	command.spawn_generation = owner.spawn_generation
	command.buttons = RULES.Buttons.PRIMARY
	command.yaw = atan2(-direction.x, -direction.z)
	command.pitch = asin(direction.y)
	return simulation.step_fixed({1: command})

func _run() -> void:
	_settings_contract()
	_thresholds_freeze_and_choices()
	_power_real_hits_and_original_terrain()
	_armor_real_bite_and_grenade()
	_field_kit_caps_and_reset()
	_finish_priority_and_score()
	print("RUSH SESSION: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)

func _settings_contract() -> void:
	var canonical: Dictionary = SETTINGS.rush_defaults()
	check(SETTINGS.validate({"run_style": "rush"}).settings == canonical, "Rush identity fills its canonical comparable preset")
	check(canonical.duration_seconds == 180 and canonical.preparation_seconds == 5
		and canonical.wave_interval_seconds == 30 and canonical.zombies_per_wave == 3,
		"quick run has three active minutes, five-second preparation and half-minute waves")
	for raw: Dictionary in [{"run_style": "unknown"}, {"run_style": true},
			{"run_style": "rush", "duration_seconds": 60}, {"run_style": "rush", "zombie_damage": 1},
			{"run_style": "rush", "preparation_seconds": 0}, {"run_style": "rush", "growth_per_minute": NAN}]:
		check(not SETTINGS.validate(raw).ok and not SETTINGS.validate(raw, true).ok,
			"unsupported identity or changed Rush balance cannot create comparable records")
	check(SETTINGS.validate({}).settings == SETTINGS.defaults(), "old saved settings remain classic")
	check(SETTINGS.defaults().preparation_seconds == 20 and SETTINGS.defaults().duration_seconds == 600,
		"classic duration and preparation retain prior behavior")
	var session: OfflineSurvivalSession = session_fixture()
	advance(session, 299)
	check(session.phase == "preparation" and session._active_ticks == 0, "Rush preparation excludes active score time")
	advance(session)
	check(session.phase == "active" and session._active_ticks == 0, "exact five-second boundary begins quick waves")
	session.free()

func _thresholds_freeze_and_choices() -> void:
	var session: OfflineSurvivalSession = session_fixture()
	advance(session, 301)
	credit_kills(session, 2)
	check(not session.get_rush_state().pending and session.get_rush_state().next_kills == 3,
		"two committed kills cannot earn the first three-kill choice")
	credit_kills(session, 1)
	check(session.get_rush_state().pending and session.get_rush_state().choices.size() == 3 and not session.paused,
		"first milestone offers all three upgrades without taking HUD pause ownership")
	check(session.simulation.spawn_zombie_slot(2, Vector3(20.5, 4.01, 28.5)).ok
		and session.simulation.assign_zombie_type(2, "grenadier"), "pending fixture retains a real live enemy")
	check(not session.simulation.throw_zombie_grenade(2, session.get_owner_state().feet() + Vector3.UP * 1.1, 15, 40).is_empty(),
		"pending choice retains genuine flying ordnance")
	var projectile: SharedGrenadeState = session.simulation.grenades.values()[0]
	var position: Vector3 = projectile.position
	var actor_position: Vector3 = session.simulation.get_actor(2).feet()
	var tick: int = session.simulation.tick
	var clock: int = session._active_ticks
	var sequence: int = session._input_sequence
	var frozen: Dictionary = session.step_local(RULES.Buttons.PRIMARY, Vector2(1, 0), 0.0, 0.0)
	check(frozen.ok and not frozen.advanced and session.simulation.tick == tick and session._active_ticks == clock,
		"choice freezes simulation and wave clock at one fixed boundary")
	check(projectile.position == position and projectile.last_tick == tick
		and session.simulation.get_actor(2).feet() == actor_position and session._input_sequence == sequence,
		"choice freezes ordnance, bodies and command sequence")
	check(not session.choose_upgrade("unknown").ok and session.get_rush_state().pending, "unoffered IDs preserve pending choice")
	session.paused = true
	check(not session.choose_upgrade("power").ok, "ordinary menu/focus pause prevents reward activation")
	session.paused = false
	var external: Dictionary = session.get_rush_state()
	external.levels.power = 99
	external.choices[0].id = "injected"
	check(session.get_rush_state().levels.power == 0 and session.get_rush_state().choices[0].id == "power",
		"UI receives independent choice and level data")
	session.reload_weapon()
	check(session.choose_upgrade("power").ok and session.get_rush_state().levels.power == 1
		and not session.get_rush_state().pending and not session._pending_reload,
		"valid choice applies once and clears buffered inputs")
	check(not session.choose_upgrade("power").ok, "replayed choice cannot award a second rank")
	advance(session)
	check(projectile.position != position and session.simulation.tick == tick + 1, "resume advances old projectile once without catch-up")
	session.simulation.grenades.clear()
	credit_kills(session, 4)
	check(session.get_rush_state().next_kills == 7 and session.choose_upgrade("power").ok, "second distinct threshold grants rank two")
	credit_kills(session, 5)
	check(session.choose_upgrade("power").ok and session.get_rush_state().levels.power == 3, "third threshold caps power at rank three")
	credit_kills(session, 6)
	var capped_choices: Array = session.get_rush_state().choices
	check(capped_choices.size() == 2 and str(capped_choices[0].id) == "armor"
		and not session.choose_upgrade("power").ok, "capped perk disappears and cannot be replayed at later thresholds")
	check(session.choose_upgrade("field_kit").ok, "repeatable kit remains available after a capped perk")
	credit_kills(session, 7)
	check(session.choose_upgrade("field_kit").ok and session.get_rush_state().next_kills == 0,
		"fifth choice completes the finite milestone schedule")
	credit_kills(session, 8)
	check(not session.get_rush_state().pending and session.get_rush_state().levels.field_kit == 2,
		"more kills after five choices do not create unbounded reward dialogs")
	session.free()
	var classic: OfflineSurvivalSession = session_fixture(false)
	credit_kills(classic, 3)
	check(not classic.get_rush_state().enabled and not classic.get_rush_state().pending,
		"classic kills keep their original flow")
	classic.free()

func _power_real_hits_and_original_terrain() -> void:
	for rank: int in range(4):
		var simulation: MatchSimulation = match_fixture()
		check(simulation.set_survival_firearm_level(1, rank), "bounded human firearm policy accepts rank %d" % rank)
		var events: Array[Dictionary] = fire_torso(simulation)
		var hits: Array[Dictionary] = MATCH.events_of(events, "hit_confirmed")
		var expected_health: Array[int] = [51, 38, 26, 14]
		check(hits.size() == 1 and hits[0].part == "torso" and simulation.get_actor(2).health == expected_health[rank]
			and simulation.get_actor(1).magazine == 9, "real aimed rifle hit applies rank %d without changing ammunition/cadence" % rank)
	var wall: MatchSimulation = match_fixture()
	check(wall.set_survival_firearm_level(1, 3), "wall shooter receives maximum damage perk")
	wall.data.seed_box(Vector3i(20, 4, 35), Vector3i(21, 8, 36), 0x01dddddd)
	var events: Array[Dictionary] = fire_torso(wall)
	var blocks: Array[Dictionary] = MATCH.events_of(events, "block_hit")
	check(blocks.size() == 1 and wall.get_block_remaining_health(blocks[0].cell) == 50.0
		and wall.get_actor(2).health == 100, "power preserves source50blockdamage and terrain occlusion")
	check(not wall.set_survival_firearm_level(1, 4) and not wall.set_survival_firearm_level(1, -1)
		and not wall.set_survival_firearm_level(2, 1) and not wall.set_survival_firearm_level(999, 1),
		"invalid ranks, zombies and missing actors cannot receive human power")
	check(wall.add_actor("Observer", 2, 1, Vector3.INF, 3).ok and not wall.set_survival_firearm_level(3, 1),
		"spectators cannot receive living survival policy")
	var ctf: MatchSimulation = MATCH.new()
	check(ctf.configure(map_fixture(), "0.75", "ctf").ok and ctf.add_actor("CTF", 2, 1, Vector3.INF, 1).ok
		and ctf.spawn_actor(1, 0, 0, Vector3(20.5, 4.01, 40.5)).ok and not ctf.set_survival_firearm_level(1, 1),
		"non-sandbox match rejects authored survival policy")

func _armor_real_bite_and_grenade() -> void:
	for rank: int in [0, 1, 3]:
		var simulation: MatchSimulation = match_fixture()
		check(simulation.set_survival_armor_level(1, rank), "living human accepts bounded armor rank")
		simulation.get_actor(2).motion = MOTION.create_state(Vector3(20.5, 4.01, 38.5))
		var bites: Array[Dictionary] = simulation.resolve_zombie_bite(2, 1, 20)
		var expected_bite: Dictionary = {0: 80, 1: 83, 3: 89}
		check(not MATCH.events_of(bites, "hurt").is_empty() and simulation.get_actor(1).health == expected_bite[rank],
			"confirmed reachable bite applies armor rank%d" % rank)
		simulation.get_actor(1).health = 100
		simulation.get_actor(2).motion = MOTION.create_state(Vector3(20.5, 4.01, 28.5))
		check(simulation.assign_zombie_type(2, "grenadier"), "grenadier profile admitted for real blast")
		simulation.step_fixed()
		check(not simulation.throw_zombie_grenade(2, simulation.get_actor(1).feet() + Vector3.UP * 1.1, 40, 40).is_empty(),
			"actual trusted zombie projectile exists before explosion")
		var projectile: SharedGrenadeState = simulation.grenades.values()[0]
		projectile.position = simulation.get_actor(1).feet() + Vector3.UP * 0.9
		projectile.fuse_deadline_tick = simulation.tick
		var exploded: Array[Dictionary] = simulation.step_fixed()
		var expected_blast: Dictionary = {0: 60, 1: 66, 3: 78}
		check(MATCH.events_of(exploded, "grenade_exploded").size() == 1
			and simulation.get_actor(1).health == expected_blast[rank] and simulation.grenades.is_empty(),
			"real shared zombie explosion applies armor rank%d and releases ordnance" % rank)
		simulation.get_actor(1).health = 100
		simulation.damage_actor(1, 20, 1, "grenade")
		check(simulation.get_actor(1).health == 80, "armor never reduces human grenade damage")
	check(not match_fixture().set_survival_armor_level(2, 1), "zombie cannot receive player armor")

func _field_kit_caps_and_reset() -> void:
	var session: OfflineSurvivalSession = session_fixture()
	credit_kills(session, 3)
	var owner: SharedPlayerState = session.simulation.get_actor(1)
	owner.health = 50
	owner.reserve = 2
	owner.magazine = 1
	owner.blocks = 35
	owner.grenades = 2
	check(session.choose_upgrade("field_kit").ok and owner.health == 85 and owner.reserve == 50
		and owner.magazine == 1 and owner.blocks == 50 and owner.grenades == 3,
		"kit heals35 and restores capped reserve/resources without refilling the magazine: %s" % str([owner.health, owner.reserve, owner.magazine, owner.blocks, owner.grenades, owner.weapon]))
	credit_kills(session, 4)
	check(session.choose_upgrade("field_kit").ok and owner.health == 100 and owner.blocks == 50
		and owner.grenades == 3 and session.get_rush_state().levels.field_kit == 2, "kit is repeatable but cannot overflow source caps: %s" % str([owner.health, owner.blocks, owner.grenades, session.get_rush_state().levels]))
	credit_kills(session, 5)
	check(session.choose_upgrade("power").ok, "run acquires an actual power modifier before reset")
	credit_kills(session, 6)
	check(session.get_rush_state().pending, "reset starts from an outstanding choice")
	var prior_epoch: int = session.simulation.epoch
	check(session.restart_match().ok and session.simulation.epoch == prior_epoch + 1,
		"restart adopts a fresh authoritative map epoch")
	var state: Dictionary = session.get_rush_state()
	check(state.enabled and not state.pending and state.kills == 0 and state.next_kills == 3 and state.score == 0
		and state.levels == {"power": 0, "armor": 0, "field_kit": 0}, "restart clears run rewards, score and milestones")
	check(session.simulation.capture_state(1).survival_firearm_levels.is_empty()
		and session.simulation.capture_state(1).survival_armor_levels.is_empty(), "reset clears shared damage policies")
	session.free()

func _finish_priority_and_score() -> void:
	var victory: OfflineSurvivalSession = session_fixture()
	victory.phase = "cleanup"
	victory._active_ticks = 180 * RULES.HZ
	victory._spawned = 3
	credit_kills(victory, 3)
	check(victory.outcome == "win" and not victory.get_rush_state().pending
		and victory.get_rush_state().score == 2200, "last cleanup kill awards win before offering an unusable upgrade")
	check(not victory.choose_upgrade("power").ok, "finished run rejects reward activation")
	victory.free()
	var defeat: OfflineSurvivalSession = session_fixture()
	credit_kills(defeat, 2)
	check(defeat.simulation.spawn_zombie_slot(2, Vector3(40.5, 4.01, 20.5)).ok, "third target alive in lethal boundary")
	defeat.simulation.damage_actor(2, 100, 1)
	defeat.simulation.damage_actor(1, 100, 2, "bite")
	advance(defeat)
	check(defeat.outcome == "defeat" and not defeat.get_rush_state().pending
		and not defeat.choose_upgrade("field_kit").ok, "death takes priority over simultaneous kill milestone")
	defeat.free()
	var interrupted: OfflineSurvivalSession = session_fixture()
	credit_kills(interrupted, 3)
	interrupted._finish("interrupted", "route_unavailable")
	check(interrupted.get_rush_state().score == 0 and not interrupted.get_rush_state().pending,
		"technical interruption clears choice and yields no record score")
	interrupted.free()
