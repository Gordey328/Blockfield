extends SceneTree
## Serial lease only: godot --headless --path game --script ../tests/session/test_offline_tdm.gd
const SESSION = preload("res://gameplay/offline_tdm_session.gd")
const ARENA = preload("res://ai/tdm_arena.gd")
const RULES = preload("res://simulation/player_rules.gd")
const MOTION = preload("res://gameplay/source_player_motion.gd")
var assertions: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("OFFLINE TDM: " + message)


func fixture(active_bots: bool = false) -> OfflineTDMSession:
	var session: OfflineTDMSession = SESSION.new()
	root.add_child(session)
	var configured: Dictionary = session.configure_match(ARENA.build(), ARENA.metadata(), "Игрок")
	check(configured.ok, "fresh authored arena admits six shared actors")
	if not active_bots:
		# Isolate coordinator policy from stochastic combat. The separate AI and
		# real-scene fixtures retain the director and exercise actual gunfire.
		session._director = null
	check(session.drain_presentation_events().size() == 12, "one join and spawn event per actor")
	return session


func advance(session: OfflineTDMSession, count: int, buttons: int = 0) -> void:
	for tick_index: int in range(count):
		var owner: SharedPlayerState = session.get_owner_state()
		var result: Dictionary = session.step_local(buttons, Vector2.ZERO, owner.yaw, owner.pitch)
		if not result.ok:
			check(false, "valid fixed-step command: " + str(result.get("error", "")))
			session.drain_presentation_events()


func place(actor: SharedPlayerState, feet: Vector3) -> void:
	actor.motion = MOTION.create_state(feet)
	actor.tool_raise = 1.0
	actor.yaw = -PI * 0.5
	actor.pitch = 0.0


func _run() -> void:
	_roster_pause_and_views()
	_class_selection()
	_guns_and_kill_events()
	_shared_tools()
	_respawn_safety()
	_physical_supply()
	_rounds_and_restart()
	_bot_integration()
	print("OFFLINE TDM: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _roster_pause_and_views() -> void:
	var session: OfflineTDMSession = fixture()
	var diagnostics: Dictionary = session.get_diagnostics()
	check(diagnostics.bot_count == 5 and diagnostics.team_counts == [3, 3], "human plus two allies versus three enemies")
	check(session.local_player_id() == 1 and session.targets.size() == 5, "positive owner ID and five actor view copies")
	check(session.mode == "tdm" and session.simulation.mode == "sandbox", "offline round label does not widen shared wire modes")
	check(not session.simulation.friendly_fire and not session.invulnerable and not session.unlimited_ammo,
		"authored friendly-fire policy with ordinary finite resources and damage")
	for actor: SharedPlayerState in session.simulation.actors.values():
		check(actor.is_alive() and actor.health == 100 and actor.magazine > 0 and actor.reserve > 0,
			"all six actors start alive with normal inventory")
	var tick: int = session.simulation.tick
	var feet: Vector3 = session.get_owner_state().feet()
	for frame: int in range(10):
		session.update(10.0)
		session.step_local(RULES.Buttons.PRIMARY, Vector2(0, -1), -PI * 0.5, 0.0)
	check(session.simulation.tick == tick and session.get_owner_state().feet() == feet,
		"paused inputs and view updates cannot advance time, movement or fire")
	var copy: SharedPlayerState = session.get_owner_state()
	copy.health = 1
	copy.motion.feet_position = Vector3.ZERO
	var target: Dictionary = session.get_target(4)
	target.health = 0
	target.position = Vector3.ZERO
	check(session.simulation.get_actor(1).health == 100 and session.get_owner_state().feet() == feet
		and session.simulation.get_actor(4).health == 100, "owner and target getters never expose authority references")
	check(not bool(session.get_target(4).health_known) and bool(session.get_target(4).visual_only),
		"opponent view follows the normal name-based shared presentation")
	var owner: SharedPlayerState = session.simulation.get_actor(1)
	owner.magazine = 3
	session.magazine = 999
	session.health = 1
	session.restock()
	session.respawn()
	session.damage_player(100)
	session.apply_target_damage(4, 100)
	session.add_score(99)
	session.reset_lab()
	session.update(0.0)
	check(owner.magazine == 3 and owner.health == 100 and session.magazine == 3 and session.score == 0,
		"legacy lab mutations cannot supply ammo, damage or score in TDM")
	session.paused = false
	var invalid: Dictionary = session.step_local(0, Vector2(2, 0), 0.0, 0.0)
	check(not invalid.ok and session.simulation.tick == -1, "invalid input rejected without stepping")
	var valid: Dictionary = session.step_local(0, Vector2.ZERO, owner.yaw, owner.pitch)
	check(valid.ok and valid.advanced and session.simulation.tick == 0 and owner.last_tick == 0,
		"one accepted call advances all actors exactly one shared 60Hz tick")
	session.free()


func _class_selection() -> void:
	var session: OfflineTDMSession = fixture()
	session.select_weapon(2)
	check(session.current_weapon == 2 and session.magazine == 6 and session.reserve == 48
		and session.simulation.tick == -1 and session.paused, "lobby weapon selection configures the initial shared class")
	session.drain_presentation_events()
	session._director = null
	session.paused = false
	advance(session, 1)
	var owner: SharedPlayerState = session.simulation.get_actor(1)
	owner.magazine = 2
	session.select_weapon(1)
	advance(session, 1)
	check(owner.weapon == 2 and owner.magazine == 2 and owner.pending_weapon == 1,
		"live class request is pending until respawn and never refills the clip")
	session.simulation.damage_actor(1, 100, 4)
	advance(session, RULES.RESPAWN_TICKS + 1)
	check(owner.is_alive() and owner.weapon == 1 and owner.magazine == 30 and owner.reserve == 120,
		"normal eligible respawn applies queued class and finite initial ammo")
	session.select_tool(0)
	var intent: Dictionary = session.drain_intent()
	check(intent.tool == 0 and session.drain_intent().tool == 255, "controller consumes each selection intent once")
	var result: Dictionary = session.step_local(0, Vector2.ZERO, owner.yaw, owner.pitch, intent.tool, intent.weapon)
	check(result.ok and owner.tool == 0, "drained controller intent is applied by shared rules")
	session.free()
	var boundary: OfflineTDMSession = fixture()
	boundary.paused = false
	boundary.simulation.damage_actor(1, 100, 4)
	advance(boundary, RULES.RESPAWN_TICKS)
	check(not boundary.get_owner_state().is_alive(), "class boundary fixture reaches the last inactive tick")
	boundary.select_weapon(2)
	advance(boundary, 1)
	var respawned: SharedPlayerState = boundary.get_owner_state()
	check(respawned.is_alive() and respawned.weapon == 2 and respawned.magazine == 6 and respawned.pending_weapon == -1,
		"class selected on the exact respawn boundary applies to that new life")
	boundary.free()


func _guns_and_kill_events() -> void:
	var session: OfflineTDMSession = fixture()
	session.paused = false
	var owner: SharedPlayerState = session.simulation.get_actor(1)
	var victim: SharedPlayerState = session.simulation.get_actor(4)
	place(owner, Vector3(10.5, 4.01, 28.5))
	place(victim, Vector3(18.5, 4.01, 28.5))
	var seen: Dictionary = {"shots": 0, "target_deaths": 0}
	session.shot_fired.connect(func(): seen.shots += 1)
	session.target_died.connect(func(id: int):
		if id == 4: seen.target_deaths += 1)
	var result: Dictionary = session.step_local(RULES.Buttons.PRIMARY, Vector2.ZERO, -PI * 0.5, 0.0)
	check(result.ok and owner.magazine == 9 and victim.health == 0,
		"human primary command spends original ammo and hits a real shared enemy")
	check(session.team_scores == [1, 0] and owner.kills == 1 and victim.deaths == 1,
		"enemy death contributes exactly one team kill")
	check(seen.shots == 1 and seen.target_deaths == 1 and session.shots_fired == 1 and session.hits_landed == 1,
		"one authoritative shot/death produces one presentation signal and hit count")
	var events: Array[Dictionary] = session.drain_presentation_events()
	check(MatchSimulation.events_of(events, "shot").size() == 1 and MatchSimulation.events_of(events, "tracer").size() == 1,
		"shared raw shot/tracer events reach the renderer once")
	check(session.drain_presentation_events().is_empty(), "presentation event drain cannot replay a shot")
	var kills: Array[Dictionary] = []
	for entry: Dictionary in session.event_log:
		if entry.type == "kill": kills.append(entry)
	check(kills.size() == 1 and kills[0].killer == "Игрок" and kills[0].victim == victim.player_name,
		"killfeed names and teams come from shared actor attribution")
	var ally: SharedPlayerState = session.simulation.get_actor(2)
	var friendly: Array[Dictionary] = session.simulation.damage_actor(2, 100, 1)
	check(friendly.is_empty() and ally.health == 100 and owner.kills == 1,
		"friendly-fire policy rejects ally damage and false kill credit")
	session.simulation.damage_actor(4, 100, 1)
	advance(session, 1)
	check(owner.kills == 1 and session.team_scores == [1, 0] and seen.target_deaths == 1,
		"repeated damage of a dead victim cannot duplicate deaths or score")
	session.free()


func _shared_tools() -> void:
	var session: OfflineTDMSession = fixture()
	session.paused = false
	var owner: SharedPlayerState = session.simulation.get_actor(1)
	var victim: SharedPlayerState = session.simulation.get_actor(4)
	place(owner, Vector3(10.5, 4.01, 28.5))
	place(victim, Vector3(12.5, 4.01, 28.5))
	session.select_tool(0)
	advance(session, 35)
	session.step_local(RULES.Buttons.PRIMARY, Vector2.ZERO, -PI * 0.5, 0.0)
	check(victim.health == 0 and session.team_scores == [1, 0], "spade command uses shared melee and kill scoring")
	session.select_tool(3)
	advance(session, 35)
	advance(session, 10, RULES.Buttons.PRIMARY)
	advance(session, 1)
	check(owner.grenades == 2 and session.simulation.grenades.size() == 1,
		"shared grenade cook/release spends one stock and creates one authority projectile")
	check(session.live_grenades.size() == 1 and session.live_grenades[0].has("orientation")
		and bool(session.live_grenades[0].visual_only), "renderer receives full visual-only projectile pose")
	session.free()


func _respawn_safety() -> void:
	var session: OfflineTDMSession = fixture()
	session.paused = false
	var spawns: Array = ARENA.metadata().team_spawns
	var owner: SharedPlayerState = session.simulation.get_actor(1)
	place(session.simulation.get_actor(2), spawns[0][0])
	place(session.simulation.get_actor(3), spawns[0][1])
	var seen: Dictionary = {"deaths": 0, "spawns": 0}
	session.player_died.connect(func(): seen.deaths += 1)
	session.player_respawned.connect(func(): seen.spawns += 1)
	session.simulation.damage_actor(1, 100, 4)
	advance(session, RULES.RESPAWN_TICKS)
	check(not owner.is_alive() and seen.deaths == 1 and seen.spawns == 0,
		"shared death keeps player inactive until explicit 180-tick deadline")
	advance(session, 1)
	check(owner.is_alive() and owner.feet().distance_to(spawns[0][2]) < 0.1 and seen.spawns == 1,
		"occupied primary/secondary spawn selects a clear team alternative: feet=%s expected=%s alive=%s spawns=%s deadline=%s tick=%s" %
		[owner.feet(), spawns[0][2], owner.is_alive(), seen.spawns, owner.respawn_tick, session.simulation.tick])
	advance(session, 3)
	check(seen.spawns == 1, "view refresh never emits duplicate respawn signals")
	session.free()
	var blocked: OfflineTDMSession = fixture()
	blocked.paused = false
	place(blocked.simulation.get_actor(2), spawns[0][0])
	place(blocked.simulation.get_actor(3), spawns[0][1])
	place(blocked.simulation.get_actor(4), spawns[0][2])
	blocked.simulation.damage_actor(1, 100, 4)
	advance(blocked, RULES.RESPAWN_TICKS + 2)
	check(not blocked.get_owner_state().is_alive() and blocked.get_diagnostics().respawn_deferred > 0,
		"all occupied team spawns defer rather than overlap or spawn in terrain")
	place(blocked.simulation.get_actor(4), spawns[1][0])
	advance(blocked, 1)
	check(blocked.get_owner_state().is_alive(), "deferred respawn succeeds when a team spawn becomes clear")
	blocked.free()


func _physical_supply() -> void:
	var session: OfflineTDMSession = fixture()
	session.paused = false
	var owner: SharedPlayerState = session.simulation.get_actor(1)
	owner.magazine = 3
	owner.reserve = 0
	owner.health = 40
	owner.blocks = 0
	owner.grenades = 0
	advance(session, 61)
	check(owner.health == 100 and owner.reserve == 50 and owner.blocks == 50 and owner.grenades == 3,
		"physical own supply zone restores standard finite stock through shared restock")
	check(owner.magazine == 3, "supply preserves partially depleted magazine; reload remains necessary")
	place(owner, Vector3(15.5, 4.01, 28.5))
	owner.reserve = 0
	owner.health = 40
	advance(session, 61)
	check(owner.reserve == 0 and owner.health == 40, "resources do not regenerate away from own supply")
	place(owner, ARENA.metadata().team_spawns[1][0])
	advance(session, 61)
	check(owner.reserve == 0 and owner.health == 40, "enemy supply cannot refill the human's team")
	session.free()


func _rounds_and_restart() -> void:
	var timed: OfflineTDMSession = fixture()
	timed.match_duration_ticks = 2
	timed.paused = false
	advance(timed, 2)
	check(timed.finished and timed.paused and timed.winning_team == -1 and timed.finish_reason == "time_limit",
		"elapsed fixed time ends a tied match with an explicit draw")
	check(timed.round_remaining == 0.0 and timed.get_diagnostics().time_remaining == 0.0,
		"time limit reaches exactly zero")
	var tick: int = timed.simulation.tick
	timed.paused = false
	timed.step_local(RULES.Buttons.PRIMARY, Vector2(0, -1), 0.0, 0.0)
	check(timed.simulation.tick == tick, "finished match remains frozen even if resume flag is changed")
	timed.free()
	var session: OfflineTDMSession = fixture()
	session.kill_limit = 1
	session.paused = false
	var won: Dictionary = {"count": 0}
	session.round_won.connect(func(_team: int): won.count += 1)
	session.simulation.damage_actor(4, 100, 1)
	session.step_local(0, Vector2.ZERO, -PI * 0.5, 0.0)
	check(session.finished and session.winning_team == 0 and session.team_scores == [1, 0]
		and won.count == 1 and session.finish_reason == "kill_limit", "real enemy kill reaches limit and emits one winning result")
	var events: Array[Dictionary] = session.drain_presentation_events()
	check(MatchSimulation.events_of(events, "tdm_finished").size() == 1, "one authored completion event includes the final shared score")
	var prior: MatchSimulation = session.simulation
	var failed: Dictionary = session.configure_match(session.simulation.data, {"team_spawns": []})
	check(not failed.ok and session.simulation == prior, "invalid configuration leaves the existing match intact")
	var cell: Vector3i = Vector3i(21, 4, 22)
	var original: int = session.simulation.data.get_block(cell)
	session.simulation.data.blocks[session.simulation.data.index(cell)] = 0
	var restarted: Dictionary = session.restart_match()
	check(restarted.ok and restarted.data != prior.data and restarted.data.get_block(cell) == original,
		"new match restores pristine map cells into a separate authority map")
	check(session.simulation.epoch == prior.epoch + 1 and session.simulation.tick == -1
		and session.team_scores == [0, 0] and not session.finished and session.paused,
		"manual restart creates a fresh epoch, six actors, scores and paused round clock")
	check(session.simulation.actors.size() == 6 and session.player_deaths == 0 and session.player_kills == 0,
		"restart clears every actor's statistics and restores exact 3x3 roster")
	session.free()


func _bot_integration() -> void:
	var session: OfflineTDMSession = fixture(true)
	session.paused = false
	advance(session, 600)
	var diagnostics: Dictionary = session.get_diagnostics()
	check(diagnostics.tick == 599 and diagnostics.bot_count == 5 and diagnostics.team_counts == [3, 3],
		"director and human advance together in one shared offline authority")
	var moved: bool = false
	var spawns: Array = ARENA.metadata().team_spawns
	for id: int in range(2, 7):
		var actor: SharedPlayerState = session.simulation.get_actor(id)
		check(actor.feet().is_finite() and actor.last_tick == session.simulation.tick,
			"bot pose and rule clock remain valid at actor %d" % id)
		if actor.feet().distance_to(spawns[actor.team][(id - 1) % 3]) > 1.0:
			moved = true
	check(moved, "active bots travel through the playable arena")
	session.free()
