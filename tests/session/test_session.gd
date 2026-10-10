extends SceneTree
## godot --headless --path game --script ../tests/session/test_session.gd

const SESSION = preload("res://gameplay/local_session.gd")
var assertions: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("SESSION TEST: " + message)


func new_session() -> SESSION:
	var session := SESSION.new()
	root.add_child(session)
	return session


func _run() -> void:
	_test_profiles_and_damage()
	_test_cadence_and_reload()
	_test_grenades_and_stocks()
	_test_targets_and_life_cycle()
	_test_ctf()
	_test_tc()
	_test_match_events()
	print("SESSION TESTS: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)


func _test_profiles_and_damage() -> void:
	var s := new_session()
	check(s.magazine == 10 and s.reserve == 50, "0.75 rifle must spawn with 10 + 50 ammo")
	check(s.compute_damage("head", 127.9) == 100, "rifle headshot at valid range must deal 100")
	check(s.compute_damage("torso", 5) == 49 and s.compute_damage("arms", 5) == 33,
		"rifle head/torso/limb balance must match pinned source")
	check(s.compute_damage("head", 128.0) == 0, "128-block horizontal firing range must be exclusive")
	s.select_weapon(1)
	check(s.magazine == 30 and s.reserve == 120 and is_equal_approx(float(s.get_weapon_info().delay), 0.11),
		"0.75 SMG magazine, stock and cadence")
	check(s.compute_damage("head", 5) == 75 and s.compute_damage("legs", 5) == 18 \
		and s.compute_damage("block", 5) == 35, "0.75 SMG hit-part and block damage")
	s.select_weapon(2)
	check(s.magazine == 6 and s.reserve == 48 and int(s.get_weapon_info().pellets) == 8,
		"0.75 shotgun must have 6 shells and 8 pellets")
	check(s.compute_damage("head", 5) == 37 and s.compute_damage("torso", 5) == 27,
		"shotgun computes per-pellet damage, not aggregate damage")
	s.set_profile_version("0.76")
	check(s.magazine == 8 and is_equal_approx(float(s.get_weapon_info().reload_time), 0.4),
		"0.76 shotgun profile must change clip and shell time")
	s.select_weapon(0)
	check(s.magazine == 8 and s.reserve == 48 and is_equal_approx(float(s.get_weapon_info().delay), 0.6),
		"0.76 rifle profile must change clip, stock and interval")
	s.select_weapon(1)
	check(s.reserve == 150 and s.compute_damage("block", 1) == 34,
		"0.76 SMG profile must change reserve and block damage")
	s.set_profile_version("unsupported")
	check(s.profile_version == "0.76", "invalid profile must not corrupt the session")
	s.free()


func _test_cadence_and_reload() -> void:
	var s := new_session()
	check(s.fire() and s.magazine == 9, "firing consumes one round")
	check(not s.fire(), "same-frame repeated firing must be rejected")
	s.update(0.49)
	check(not s.can_fire(), "rifle cannot fire before 0.5 s")
	s.update(0.011)
	check(s.fire() and s.magazine == 8, "rifle becomes ready after shot interval")
	s.reload_weapon()
	check(s.is_reloading and not s.can_fire(), "magazine reload must block firing")
	s.update(2.49)
	check(s.magazine == 8, "magazine rounds remain unchanged until reload completes")
	s.update(0.02)
	check(not s.is_reloading and s.magazine == 10 and s.reserve == 48,
		"magazine reload must transfer only missing rounds from reserve")
	s.magazine = 0
	s.reserve = 3
	s.reload_weapon()
	s.update(2.51)
	check(s.magazine == 3 and s.reserve == 0, "partial reserve reload must not create ammunition")
	s.select_weapon(2)
	s.magazine = 3
	s.reload_weapon()
	s.update(0.51)
	check(s.is_reloading and s.magazine == 4 and s.reserve == 47,
		"shotgun must load exactly one shell after its first interval")
	check(s.fire() and not s.is_reloading and s.magazine == 3,
		"shotgun firing must interrupt shell reload and consume one shell")
	s.update(1.01)
	s.reload_weapon()
	s.update(1.51)
	check(not s.is_reloading and s.magazine == 6 and s.reserve == 44,
		"shotgun must finish 3 shells and account for elapsed frame remainder")
	s.unlimited_ammo = true
	var old_mag := s.magazine
	check(s.fire() and s.magazine == old_mag, "unlimited ammo does not consume rounds")
	s.select_team(2)
	check(not s.can_fire() and not s.fire(), "spectator cannot shoot")
	s.free()


func _test_grenades_and_stocks() -> void:
	var s := new_session()
	var throws: Array[Dictionary] = []
	var explosions: Array[Dictionary] = []
	s.grenade_thrown.connect(func(data: Dictionary) -> void: throws.append(data.duplicate(true)))
	s.grenade_exploded.connect(func(data: Dictionary) -> void: explosions.append(data.duplicate(true)))
	s.select_tool(3)
	check(s.begin_grenade_cook(), "grenade pin pull starts cooking")
	check(s.release_grenade().is_empty() and s.grenades == 3,
		"releasing before 0.15 s must wait until pin is pulled")
	s.update(0.151)
	check(throws.size() == 1 and s.grenades == 2 and not s.is_cooking_grenade,
		"pending early release must throw once after minimum pin time")
	check(is_equal_approx(float(throws[0].fuse), 2.849), "remaining fuse excludes grenade cook time")
	check(not s.begin_grenade_cook(), "grenade cooldown must prevent immediate second pin pull")
	s.update(0.5)
	check(s.begin_grenade_cook(), "grenade can cook again after 0.5 s")
	s.update(2.91)
	check(throws.size() == 2 and s.grenades == 1, "cooked grenade must force-throw by 2.9 s")
	check(explosions.size() >= 1, "grenade fuse expiration must emit authoritative explosion")
	check(s.live_grenades.size() == 1 and float(s.live_grenades[0].fuse) > 0.08,
		"force-thrown grenade retains remaining fuse instead of aging by the cook interval twice")
	s.live_grenades.clear()
	s.update(0.51)
	check(s.begin_grenade_cook(), "remaining grenade can cook")
	s.update(0.2)
	s.damage_player(100)
	check(throws.size() == 3 and bool(throws[2].drop), "death drops a cooked grenade")
	s.respawn()
	s.select_tool(1)
	check(s.use_block(5) and s.blocks == 45, "line placement consumes its full block count")
	check(not s.use_block(), "block placement respects 0.5 s interval")
	s.update(0.51)
	s.blocks = 1
	check(not s.use_block(2) and s.blocks == 1, "insufficient-stock line fails atomically")
	check(s.use_block() and s.blocks == 0, "last block can be placed")
	s.recover_block()
	check(s.blocks == 1, "spade block recovery returns one block")
	s.magazine = 4
	s.restock()
	check(s.magazine == 4 and s.reserve == 50 and s.grenades == 3 and s.blocks == 50,
		"resupply replenishes reserve and tools without magically filling magazine")
	s.free()


func _test_targets_and_life_cycle() -> void:
	var s := new_session()
	var id := s.add_target(Vector3(10, 5, 10), 1, false)
	check(s.damage_target(id, "torso", 5) == 49 and int(s.get_target(id).health) == 51,
		"target accepts source torso damage")
	s.damage_target(id, "head", 5)
	check(not bool(s.get_target(id).alive) and s.score == 1,
		"lethal hit kills target once and increments score")
	s.damage_target(id, "head", 5)
	check(s.score == 1, "dead target cannot award repeated score")
	s.update(2.99)
	check(not bool(s.get_target(id).alive), "target remains dead until offline respawn time")
	s.update(0.02)
	check(bool(s.get_target(id).alive) and int(s.get_target(id).health) == 100,
		"target respawns with full HP")
	s.set_target_state(id, "dead")
	s.update(10)
	check(not bool(s.get_target(id).alive), "explicit lab dead pose does not auto-respawn")
	s.reset_lab()
	check(bool(s.get_target(id).alive) and s.score == 0, "reset restores targets and clears statistics")
	s.damage_player(40)
	check(s.health == 60, "player damage changes HP")
	s.invulnerable = true
	s.damage_player(1000)
	check(s.health == 60, "invulnerability suppresses damage")
	s.invulnerable = false
	s.damage_player(1000)
	check(s.health == 0 and s.respawn_remaining == 3, "lethal damage starts player respawn timer")
	s.update(3.01)
	check(s.health == 100 and s.magazine == 10 and s.grenades == 3,
		"player respawn resets combat supplies")
	s.remove_target(id)
	check(s.get_target(id).is_empty(), "target removal invalidates the old ID")
	s.free()


func _test_ctf() -> void:
	var s := new_session()
	s.configure_ctf(Vector3.ZERO, Vector3(100, 0, 0), 1)
	s.set_mode("ctf")
	s.update_player_position(Vector3(100, 0, 0))
	s.update(0.01)
	check(int(s.ctf_flags[1].carrier) == 0 and not bool(s.ctf_flags[1].at_base),
		"CTF player picks enemy intel at enemy base")
	s.update_player_position(Vector3(50, 0, 0))
	s.damage_player(100)
	check(int(s.ctf_flags[1].carrier) == -1 and s.ctf_flags[1].position == Vector3(50, 0, 0),
		"death drops intel at last player position")
	s.respawn()
	s.update_player_position(Vector3(50, 0, 0))
	s.update(0.01)
	check(int(s.ctf_flags[1].carrier) == 0, "dropped enemy intel can be picked up again")
	s.update_player_position(Vector3.ZERO)
	s.update(0.01)
	check(s.team_scores[0] == 1 and s.score == 10 and s.winning_team == 0,
		"CTF capture grants team point, ten player score and win at limit")
	check(bool(s.ctf_flags[1].at_base), "captured intel resets to enemy base")
	s.reset_lab()
	check(s.team_scores == [0, 0] and s.winning_team == -1, "CTF reset clears victory and objective state")
	s.free()


func _test_tc() -> void:
	var s := new_session()
	var positions: Array[Vector3] = [Vector3.ZERO, Vector3(100, 0, 0)]
	s.configure_tc(positions)
	s.set_mode("tc")
	s.update_player_position(Vector3.ZERO)
	s.update(10)
	check(is_equal_approx(float(s.territories[0].progress), 0.5) \
		and int(s.territories[0].owner) == 2, "TC captures at source display rate 0.05/s")
	var id := s.add_target(Vector3.ZERO, 1, false)
	s.update(5)
	check(bool(s.territories[0].contested) and is_equal_approx(float(s.territories[0].progress), 0.5),
		"equal opposing presence contests territory and freezes capture")
	s.remove_target(id)
	s.update(10.01)
	check(int(s.territories[0].owner) == 0 and s.team_scores[0] == 1,
		"completed capture changes territory ownership and team score")
	s.update_player_position(Vector3(100, 0, 0))
	s.update(20.01)
	check(s.winning_team == 0 and s.team_scores[0] == 2,
		"holding all territories wins the offline TC round")
	s.reset_lab()
	check(int(s.territories[0].owner) == 2 and s.winning_team == -1,
		"TC reset returns every territory to neutral")
	s.free()


func _test_match_events() -> void:
	var s := new_session()
	s.player_name = "Tester"
	var hurt: Array[Dictionary] = []
	var events: Array[Dictionary] = []
	s.player_hurt.connect(func(amount:float,origin:Vector3,kind:String):hurt.append({"amount":amount,"origin":origin,"kind":kind}))
	s.match_event.connect(func(event:Dictionary):events.append(event))
	s.damage_player(25,Vector3(3,5,7),"grenade")
	check(hurt.size()==1 and hurt[0].amount==25 and hurt[0].origin==Vector3(3,5,7) and hurt[0].kind=="grenade","hurt event preserves amount/source/kind")
	s.invulnerable=true
	s.damage_player(1000)
	check(hurt.size()==1 and events.is_empty(),"suppressed damage emits no feedback or death")
	s.invulnerable=false
	s.damage_player(1000,Vector3.INF,"fall")
	check(hurt[1].amount==75 and s.player_deaths==1,"feedback clamps lethal damage to remaining health")
	check(events[-1].type=="death" and events[-1].name=="Tester" and events[-1].kind=="fall","death carries profile and cause")
	s.respawn()
	check(events[-1].type=="respawn" and s.health==100,"player respawn emits once")
	var target_id:=s.add_target(Vector3.ZERO,1)
	s.apply_target_damage(target_id,100,"head")
	check(events[-1].type=="kill" and events[-1].part=="head" and events[-1].killer=="Tester" and events[-1].target_id==target_id,"kill event identifies hitter, victim and hit zone")
	check(s.get_target(target_id).deaths==1,"target scoreboard stores deaths")
	s.update(3.01)
	check(events[-1].type=="respawn" and events[-1].target_id==target_id,"target respawn includes stable ID")
	s.select_team(2)
	check(events[-1].type=="team" and events[-1].team==2,"spectator change produces match event")
	for index in 150:s.respawn()
	check(s.event_log.size()==128,"authoritative event journal has a bounded history")
	s.reset_lab()
	check(s.player_deaths==0 and s.event_log.size()==2 and s.event_log[-1].type=="reset","reset clears counters/history then records a fresh reset")
	check(s.get_target(target_id).deaths==0,"reset clears soldier scoreboard deaths")
	s.free()
