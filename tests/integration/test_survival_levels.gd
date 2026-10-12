extends SceneTree
## Downloaded geometry -> safe real roster -> bounded movement/attack timeline.
const LEVELS = preload("res://ai/survival_levels.gd")
var checks: int = 0
var failures: int = 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SURVIVAL LEVELS: " + message)
func run() -> void:
	check(not LEVELS.load_level("../../user-map").ok, "no arbitrary external level path")
	for id: String in ["crossroads", "minecraft_chunk", "mira_hq"]:
		var level: Dictionary = LEVELS.load_level(id)
		check(level.ok, "actual level decodes and validates: " + id)
		if not level.ok: continue
		var settings: Dictionary = SurvivalSettings.defaults()
		settings.preparation_seconds = 0
		settings.duration_seconds = 60
		settings.wave_interval_seconds = 30
		settings.zombies_per_wave = 4
		settings.live_limit = 4
		settings.growth_per_minute = 0.0
		# Keep the stationary oracle alive long enough to observe the fourth
		# admission's real throw, rather than dying before its windup completes.
		settings.zombie_damage = 1
		var session: OfflineSurvivalSession = OfflineSurvivalSession.new()
		root.add_child(session)
		check(session.configure_survival(level.data, level.arena, settings, "Level fixture", true, 2).ok, "real level authority configures: " + id)
		check(session.get_owner_state().weapon == 2, "selected weapon granted in first registry")
		session.paused = false
		var spawned: int = 0
		var grenade_throws: int = 0
		var hurt: int = 0
		var invalid_spawn: bool = false
		for tick: int in range(2400):
			var owner: SharedPlayerState = session.get_owner_state()
			var result: Dictionary = session.step_local(0, Vector2.ZERO, owner.yaw, owner.pitch)
			if not result.ok:
				check(false, "real fixed step accepted: " + id)
				break
			for event: Dictionary in session.drain_presentation_events():
				if str(event.get("type", "")) == "spawn" and int(event.get("owner_id", 1)) != 1:
					spawned += 1
					invalid_spawn = invalid_spawn or not OfflineSurvivalSession._supported_spawn(session.simulation.data, event.feet)
				if str(event.get("type", "")) == "grenade_thrown" and int(event.get("owner_id", 1)) != 1: grenade_throws += 1
				if str(event.get("type", "")) == "hurt": hurt += 1
			if session.finished: break
		var diagnostics: Dictionary = session._zombie_director.get_diagnostics()
		var moved: float = 0.0
		for row: Dictionary in diagnostics.bots: moved += float(row.distance_moved)
		check(spawned == 4 and not invalid_spawn, "four distant supported lives actually appear: " + id)
		check(moved > 10 and hurt > 0, "real navigation pursues and damages owner: " + id)
		check(grenade_throws > 0, "real first-wave grenadier throws on level: " + id)
		check(not session.finished or session.outcome == "defeat", "no route/spawn interruption or phantom victory: " + id)
		check(int(diagnostics.navigation.max_jobs_per_tick) <= 1, "one shared planning job per tick: " + id)
		print("LEVEL TIMELINE %s spawned=%d throws=%d hurt=%d moved=%.2f outcome=%s nav=%s" % [id, spawned, grenade_throws, hurt, moved, session.outcome, str(diagnostics.navigation)])
		session.free()
		await stress_level(id)
	print("SURVIVAL LEVELS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func stress_level(id: String) -> void:
	var level: Dictionary = LEVELS.load_level(id)
	var settings: Dictionary = SurvivalSettings.defaults()
	settings.preparation_seconds = 0
	settings.duration_seconds = 60
	settings.zombies_per_wave = 12
	settings.zombie_damage = 1
	settings.zombie_block_damage = 1
	settings.growth_per_minute = 0.0
	var session: OfflineSurvivalSession = OfflineSurvivalSession.new()
	root.add_child(session)
	check(session.configure_survival(level.data, level.arena, settings, "Stress", true).ok, "full horde authority configures: " + id)
	session.paused = false
	var max_live: int = 0
	var max_ordnance: int = 0
	var sum_usec: int = 0
	var max_usec: int = 0
	for tick: int in range(1500):
		var owner: SharedPlayerState = session.get_owner_state()
		var began: int = Time.get_ticks_usec()
		session.step_local(0, Vector2.ZERO, owner.yaw, owner.pitch)
		var elapsed: int = Time.get_ticks_usec() - began
		sum_usec += elapsed
		max_usec = maxi(max_usec, elapsed)
		max_live = maxi(max_live, session._live_count())
		max_ordnance = maxi(max_ordnance, session.simulation.zombie_projectile_count())
		session.drain_presentation_events()
		if session.finished: break
	check(max_live == 12 and max_ordnance <= 4, "real capped12 lives and capped ordnance: " + id)
	check(not session.finished or session.outcome == "defeat", "full horde has no route/spawn interruption: " + id)
	print("LEVEL STRESS %s live=%d hostile_projectiles=%d mean_tick_ms=%.3f max_tick_ms=%.3f" % [id, max_live, max_ordnance, sum_usec/1500.0/1000.0, max_usec/1000.0])
	session.free()
