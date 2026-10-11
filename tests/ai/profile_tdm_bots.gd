extends SceneTree
## Bounded native authority run. Does not establish browser/render/input performance.
const ARENA = preload("res://ai/tdm_arena.gd")
const SESSION = preload("res://gameplay/offline_tdm_session.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var session: OfflineTDMSession = SESSION.new()
	var admitted: Dictionary = session.configure_match(ARENA.build(), ARENA.metadata(), "Observer")
	if not admitted.ok:
		push_error("TDM PROFILE: configuration failed")
		quit(1)
		return
	session.paused = false
	session.kill_limit = 1000
	var shots: Dictionary = {}
	var accepted_hits: Dictionary = {}
	var elapsed_usec: int = 0
	var slowest_usec: int = 0
	for tick: int in range(3600):
		var owner: SharedPlayerState = session.simulation.get_actor(1)
		var started: int = Time.get_ticks_usec()
		session.step_local(0, Vector2.ZERO, owner.yaw, 0.0)
		var elapsed: int = Time.get_ticks_usec() - started
		elapsed_usec += elapsed
		slowest_usec = maxi(slowest_usec, elapsed)
		for event: Dictionary in session.drain_presentation_events():
			var id: int = int(event.get("owner_id", 0))
			if event.type == "shot":
				shots[id] = int(shots.get(id, 0)) + 1
			elif event.type == "hit_confirmed":
				accepted_hits[id] = int(accepted_hits.get(id, 0)) + 1
		if tick % 600 == 599:
			var actors: Array[Dictionary] = []
			for actor: SharedPlayerState in session.simulation.actors.values():
				actors.append({"id":actor.player_id, "feet":actor.feet(), "yaw":actor.yaw,
					"weapon":actor.weapon, "magazine":actor.magazine, "reserve":actor.reserve,
					"alive":actor.is_alive(), "kills":actor.kills})
			print("TDM PROFILE %d: %s" % [tick + 1, JSON.stringify({"actors":actors, "diagnostics":session.get_diagnostics().bots})])
	var active: int = 0
	for id: int in [2, 3, 4, 5, 6]:
		if int(shots.get(id, 0)) > 0:
			active += 1
	print("TDM PROFILE RESULT: %s" % JSON.stringify({"ticks":3600, "all_bots_fired":active == 5,
		"accepted_shots":shots, "accepted_hits":accepted_hits, "scores":session.team_scores,
		"mean_step_usec":float(elapsed_usec) / 3600.0, "max_step_usec":slowest_usec}))
	session.free()
	quit(0 if active == 5 else 1)
