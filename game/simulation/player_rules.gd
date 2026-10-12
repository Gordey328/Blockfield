class_name PlayerRules
extends RefCounted
## Source Player/Weapon/ClientPlayer rules plus explicitly authored authority.
## No presentation, Input singleton, variable-delta clock or global random stream.
const STATE = preload("res://simulation/player_state.gd")
const PROFILES = preload("res://simulation/weapon_profiles.gd")
const MOTION = preload("res://gameplay/source_player_motion.gd")
const HZ := 60
const DT := 1.0 / HZ
const MAX_UINT32 := 0xffffffff
const RESPAWN_TICKS := 180 # Authored local/server policy, not an upstream server.
enum Buttons { JUMP=1, CROUCH=2, SPRINT=4, SNEAK=8, PRIMARY=16, SECONDARY=32, RELOAD=64 }
enum Tool { SPADE, BLOCK, WEAPON, GRENADE }

class Command extends RefCounted:
	var sequence: int = 0
	var spawn_generation: int = 0
	var buttons: int = 0
	var move: Vector2 = Vector2.ZERO # +X right, -Y forward (wire move_z).
	var yaw: float = 0.0
	var pitch: float = 0.0
	var tool: int = 255
	var weapon: int = 255 # Class request; live inventory never changes/refills.

	static func from_record(record: Dictionary, generation: int) -> Command:
		var result := Command.new()
		result.sequence = int(record.get("input_sequence", 0))
		result.spawn_generation = generation
		result.buttons = int(record.get("buttons", 0))
		result.move = Vector2(float(record.get("move_x", 0)), float(record.get("move_z", 0)))
		result.yaw = float(record.get("yaw", 0))
		result.pitch = float(record.get("pitch", 0))
		result.tool = int(record.get("tool", 255))
		result.weapon = int(record.get("weapon", 255))
		return result

	func valid() -> bool:
		return sequence > 0 and sequence <= MAX_UINT32 and spawn_generation > 0 and spawn_generation <= MAX_UINT32 and buttons >= 0 and buttons & ~127 == 0 \
			and move.is_finite() and move.length_squared() <= 1.000001 \
			and is_finite(yaw) and absf(yaw) <= PI + .000001 \
			and is_finite(pitch) and absf(pitch) <= PI * .5 + .000001 \
			and tool in [0, 1, 2, 3, 255] and weapon in [0, 1, 2, 255]

static func spawn(actor: SharedPlayerState, tick: int, feet: Vector3, team: int,
		weapon: int = -1) -> Array[Dictionary]:
	if not actor.connected or actor.player_id <= 0 or actor.player_id > MAX_UINT32 or actor.match_epoch <= 0 \
			or actor.match_epoch > MAX_UINT32 or actor.spawn_generation >= MAX_UINT32 or tick < 0 or tick > MAX_UINT32 \
			or team not in [0, 1] or not feet.is_finite(): return frozen([])
	var selected := actor.pending_weapon if weapon < 0 and actor.pending_weapon >= 0 else (actor.weapon if weapon < 0 else weapon)
	if not PROFILES.valid(actor.profile, selected): return frozen([])
	actor.spawn_generation += 1
	actor.team = team
	actor.weapon = selected
	actor.pending_weapon = -1
	actor.health = 100
	var info := PROFILES.get_info(actor.profile, selected)
	actor.magazine = info.clip_size
	actor.reserve = info.max_stock
	actor.blocks = 50
	actor.grenades = 3
	actor.motion = MOTION.create_state(feet)
	actor.tool = Tool.WEAPON
	actor.displayed_tool = Tool.WEAPON
	actor.displayed_weapon = selected
	actor.tool_raise = 0.0
	actor.sprint_state = 0.0
	actor.aim_down_state = 0.0
	actor.aiming = false
	actor.sprinting = false
	actor.sneaking = false
	actor.yaw = 0
	actor.pitch = 0
	actor.input_move = Vector2.ZERO
	actor.input_buttons = 0
	actor.previous_buttons = 0
	actor.consumed_input_sequence = 0
	actor.last_tick = tick - 1
	actor.next_shot_tick = tick
	actor.last_shot_tick = -1
	actor.grenade_deadline_tick = tick
	actor.block_deadline_tick = tick
	actor.spade_deadline_tick = tick - 1
	actor.dig_deadline_tick = tick - 1
	actor.digging = false
	actor.first_dig = true
	actor.walk_steps = 0
	actor.walk_distance = 0
	actor.death_tick = -1
	actor.respawn_tick = -1
	actor.event_sequence = 0
	cancel_actions(actor)
	return frozen([event(actor, tick, "spawn", {"feet":feet,"team":team,"weapon":selected})])

static func can_act(actor: SharedPlayerState) -> bool:
	return actor.connected and actor.player_id > 0 and actor.is_alive()

static func is_changing_tool(actor: SharedPlayerState) -> bool:
	return actor.displayed_tool != actor.tool or actor.tool_raise < .999

static func can_use_tool(actor: SharedPlayerState) -> bool:
	return can_act(actor) and not actor.sprinting and actor.sprint_state <= 0.0 and not is_changing_tool(actor)

static func tool_selectable(actor: SharedPlayerState, tool: int) -> bool:
	match tool:
		Tool.SPADE: return true
		Tool.BLOCK: return actor.blocks > 0
		Tool.WEAPON: return actor.magazine > 0 or actor.reserve > 0
		Tool.GRENADE: return actor.grenades > 0
	return false

static func request_class(actor: SharedPlayerState, weapon: int, tick: int) -> Array[Dictionary]:
	if not actor.connected or not PROFILES.valid(actor.profile, weapon) or weapon == actor.pending_weapon: return frozen([])
	if weapon == actor.weapon and actor.pending_weapon < 0: return frozen([])
	actor.pending_weapon = weapon
	return frozen([event(actor, tick, "class_pending", {"weapon":weapon})])

static func select_tool(actor: SharedPlayerState, tool: int, tick: int) -> Array[Dictionary]:
	if not can_act(actor) or tool == actor.tool or not tool_selectable(actor, tool): return frozen([])
	actor.tool = tool
	cancel_actions(actor)
	actor.input_buttons &= ~(Buttons.PRIMARY | Buttons.SECONDARY)
	return frozen([event(actor, tick, "tool_selected", {"tool":tool})])

static func cancel_actions(actor: SharedPlayerState) -> void:
	actor.reloading = false
	actor.reload_started_tick = 0
	actor.reload_deadline_tick = 0
	actor.cooking = false
	actor.cook_started_tick = -1
	actor.cook_action_sequence = 0
	actor.release_pending = false
	actor.trigger_held = false
	actor.dry_fire_held = false
	actor.digging = false

static func can_fire(actor: SharedPlayerState, tick: int) -> bool:
	return PROFILES.valid(actor.profile, actor.weapon) and can_use_tool(actor) and actor.tool == Tool.WEAPON and actor.magazine > 0 \
		and tick + .000000001 >= actor.next_shot_tick and (not actor.reloading or PROFILES.is_slow_reload(actor.profile, actor.weapon))

static func begin_reload(actor: SharedPlayerState, tick: int) -> Array[Dictionary]:
	var info := PROFILES.get_info(actor.profile, actor.weapon)
	if info.is_empty() or not can_use_tool(actor) or actor.tool != Tool.WEAPON or actor.reloading or actor.reserve <= 0 \
			or actor.magazine >= int(info.clip_size) or (bool(info.slow_reload) and actor.magazine > 0 and actor.trigger_held): return frozen([])
	actor.reloading = true
	actor.reload_started_tick = tick
	actor.reload_deadline_tick = tick + float(info.reload_time) * HZ
	actor.trigger_held = false
	return frozen([event(actor, tick, "reload_started", {"weapon":actor.weapon})])

static func reload_progress(actor: SharedPlayerState, tick: int) -> float:
	if not actor.reloading: return 0.0
	return clampf((tick - actor.reload_started_tick) / maxf(1, actor.reload_deadline_tick - actor.reload_started_tick), 0, 1)

static func restock(actor: SharedPlayerState, tick: int, authorized: bool = false) -> Array[Dictionary]:
	if not authorized or not can_act(actor) or not PROFILES.valid(actor.profile,actor.weapon): return frozen([])
	actor.health = 100
	actor.blocks = 50
	actor.grenades = 3
	actor.reserve = PROFILES.get_info(actor.profile, actor.weapon).max_stock
	return frozen([event(actor, tick, "restock")]) # Source preserves the clip.

static func use_blocks(actor: SharedPlayerState, tick: int, count: int = 1) -> Array[Dictionary]:
	# Called only after the coordinator's reach/support/overlap/map validation.
	if not can_use_tool(actor) or actor.tool != Tool.BLOCK or count <= 0 \
			or count > actor.blocks or tick < actor.block_deadline_tick: return frozen([])
	actor.blocks -= count
	actor.block_deadline_tick = tick + HZ * .5
	return frozen([event(actor, tick, "blocks_used", {"count":count})])

static func recover_block(actor: SharedPlayerState, tick: int) -> Array[Dictionary]:
	if not can_act(actor) or actor.blocks >= 50: return frozen([])
	actor.blocks += 1
	return frozen([event(actor, tick, "block_recovered")])

static func begin_cook(actor: SharedPlayerState, tick: int) -> Array[Dictionary]:
	if not can_use_tool(actor) or actor.tool != Tool.GRENADE or actor.cooking or actor.grenades <= 0 \
			or tick < actor.grenade_deadline_tick: return frozen([])
	actor.cooking = true
	actor.cook_started_tick = tick
	actor.cook_action_sequence = actor.consumed_input_sequence
	actor.release_pending = false
	return frozen([event(actor, tick, "grenade_pin")])

static func release_grenade(actor: SharedPlayerState, tick: int, force_death: bool = false, automatic: bool = false) -> Array[Dictionary]:
	if not actor.cooking or (not force_death and not can_act(actor)): return frozen([])
	var elapsed := maxi(0, tick - actor.cook_started_tick)
	if elapsed < 9 and not force_death:
		actor.release_pending = true
		return frozen([])
	actor.cooking = false # Before emitting: repeated death/release cannot duplicate.
	actor.release_pending = false
	actor.grenades = maxi(0, actor.grenades - 1)
	# SetWeaponInput starts .5s after manual release; Update's forced cook
	# throw calls ThrowGrenade directly and leaves nextGrenadeTime unchanged.
	if not automatic: actor.grenade_deadline_tick = tick + 30
	var direction := actor.front()
	var details := {"position":actor.motion.physics_eye() + direction * .1,
		"native_velocity":actor.motion.native_velocity + (Vector3.ZERO if force_death else direction),
		"fuse":maxf(0, (180.0 - elapsed) / HZ), "cook_time":float(elapsed) / HZ,
		"drop":force_death, "team":actor.team, "cook_action_sequence":actor.cook_action_sequence,"automatic":automatic}
	actor.cook_started_tick = -1
	actor.cook_action_sequence = 0
	return frozen([event(actor, tick, "grenade_thrown", details)])

static func damage(actor: SharedPlayerState, amount: float, tick: int, attacker_id: int = 0,
		cause: String = "weapon", action_id: String = "") -> Array[Dictionary]:
	if not can_act(actor) or not is_finite(amount) or amount <= 0: return frozen([])
	var dealt := int(ceilf(minf(amount,float(actor.health)))) # Clamp before float->int overflow.
	actor.health -= dealt
	var events: Array[Dictionary] = [event(actor, tick, "hurt", {"amount":dealt,"attacker_id":attacker_id,"cause":cause,"action_id":action_id})]
	if actor.health <= 0:
		events.append_array(release_grenade(actor, tick, true))
		actor.deaths += 1
		actor.death_tick = tick
		actor.respawn_tick = tick + RESPAWN_TICKS
		actor.input_buttons = 0
		actor.input_move = Vector2.ZERO
		cancel_actions(actor)
		events.append(event(actor, tick, "death", {"attacker_id":attacker_id,"cause":cause,"action_id":action_id}))
	return frozen(events)

static func step_fixed(actor: SharedPlayerState, tick: int, command: Command = null,
		query: Variant = null, rng: RandomNumberGenerator = null, authoritative_damage: bool = true) -> Array[Dictionary]:
	# Runtime chooses tick; command has neither trusted dt nor authoritative feet.
	if tick < 0 or tick != actor.last_tick + 1 or not PROFILES.valid(actor.profile, actor.weapon): return frozen([])
	actor.last_tick = tick
	var events: Array[Dictionary] = []
	if command != null and command.valid() and command.spawn_generation == actor.spawn_generation \
			and command.sequence > actor.consumed_input_sequence:
		actor.consumed_input_sequence = command.sequence
		actor.input_move = command.move
		actor.input_buttons = command.buttons
		actor.yaw = command.yaw
		actor.pitch = clampf(command.pitch, -PI * .5, PI * .5)
		if command.weapon != 255: events.append_array(request_class(actor, command.weapon, tick))
		if command.tool != 255: events.append_array(select_tool(actor, command.tool, tick))
	if not can_act(actor):
		actor.input_buttons = 0
		actor.input_move = Vector2.ZERO
	if can_act(actor) and not tool_selectable(actor, actor.tool):
		for attempt in range(1, 5):
			var next := posmod(actor.tool - attempt, 4)
			if tool_selectable(actor, next):
				events.append_array(select_tool(actor, next, tick))
				break
	if query != null:
		actor.motion = MOTION.set_crouch(query, actor.motion, can_act(actor) and actor.input_buttons & Buttons.CROUCH != 0)
	actor.sprinting = can_act(actor) and actor.input_buttons & Buttons.SPRINT != 0 and not actor.motion.crouch \
		and actor.input_move.length_squared() > .0001 and Vector2(actor.motion.native_velocity.x, actor.motion.native_velocity.z).length() >= .1
	actor.sneaking = can_act(actor) and actor.input_buttons & Buttons.SNEAK != 0
	actor.aiming = can_use_tool(actor) and actor.tool == Tool.WEAPON and actor.input_buttons & Buttons.SECONDARY != 0 and not actor.reloading
	if query != null:
		events.append_array(advance_motion(actor, tick, query, authoritative_damage))
	var allowed := can_use_tool(actor)
	var primary := allowed and actor.input_buttons & Buttons.PRIMARY != 0
	if actor.tool == Tool.WEAPON:
		var held := primary
		if actor.reloading:
			var slow_reload: bool = PROFILES.is_slow_reload(actor.profile, actor.weapon)
			if held and slow_reload:
				actor.reloading = false
				actor.reload_deadline_tick = 0
				events.append(event(actor, tick, "reload_cancelled"))
			elif not slow_reload: held = false
		if held and not actor.trigger_held: actor.next_shot_tick = maxf(actor.next_shot_tick, tick)
		actor.trigger_held = held
		if held:
			if can_fire(actor, tick): events.append_array(fire(actor, tick, rng))
			elif actor.magazine <= 0 and tick >= actor.next_shot_tick and not actor.dry_fire_held:
				actor.dry_fire_held = true
				events.append(event(actor, tick, "dry_fire"))
		else: actor.dry_fire_held = false
	else: actor.trigger_held = false
	# Weapon::FrameNext handles shooting/slow-reload interruption BEFORE the
	# shell-completion boundary. A pressed empty shotgun must not load+fire.
	events.append_array(advance_reload(actor, tick))
	if allowed and actor.input_buttons & Buttons.RELOAD != 0 and actor.previous_buttons & Buttons.RELOAD == 0:
		events.append_array(begin_reload(actor, tick))
	if actor.tool == Tool.GRENADE:
		if primary and actor.previous_buttons & Buttons.PRIMARY == 0: events.append_array(begin_cook(actor, tick))
		if actor.cooking:
			var elapsed := tick - actor.cook_started_tick
			if not primary or actor.release_pending or elapsed > 174:
				events.append_array(release_grenade(actor,tick,false,primary and not actor.release_pending and elapsed > 174))
	if actor.tool == Tool.SPADE and allowed:
		var digging := actor.input_buttons & Buttons.SECONDARY != 0
		if digging and not actor.digging:
			actor.dig_deadline_tick = tick + HZ
			actor.first_dig = true
		actor.digging = digging
		if digging and tick > actor.dig_deadline_tick:
			actor.dig_deadline_tick = tick + HZ
			actor.first_dig = false
			events.append(event(actor, tick, "spade_dig"))
		elif not digging and primary and tick > actor.spade_deadline_tick:
			actor.spade_deadline_tick = tick + .2 * HZ
			events.append(event(actor, tick, "spade_bash"))
	else: actor.digging = false
	# ClientPlayer advances these states after input/tool gating for this tick.
	actor.sprint_state = f32(clampf(f32(actor.sprint_state + f32(DT * (4 if actor.sprinting else -3))), 0, 1))
	actor.aim_down_state = f32(clampf(f32(actor.aim_down_state + f32(DT * (8 if actor.aiming else -3))), 0, 1))
	if actor.displayed_tool == actor.tool:
		actor.tool_raise = minf(1, f32(actor.tool_raise + f32(DT * 4)))
	else:
		actor.tool_raise = f32(actor.tool_raise - f32(DT * 4))
		if actor.tool_raise < 0:
			actor.tool_raise = 0
			actor.displayed_tool = actor.tool
			actor.displayed_weapon = actor.weapon
			events.append(event(actor, tick, "tool_swapped", {"tool":actor.tool,"weapon":actor.weapon}))
	actor.previous_buttons = actor.input_buttons
	return frozen(events)

static func advance_reload(actor: SharedPlayerState, tick: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not actor.reloading or not can_act(actor) or tick + .000000001 < actor.reload_deadline_tick: return frozen(events)
	var info := PROFILES.get_info(actor.profile, actor.weapon)
	if bool(info.slow_reload):
		actor.magazine += 1
		actor.reserve -= 1
		events.append(event(actor, tick, "shell_loaded"))
		if actor.magazine < int(info.clip_size) and actor.reserve > 0:
			actor.reload_started_tick = actor.reload_deadline_tick
			actor.reload_deadline_tick += float(info.reload_time) * HZ
		else: actor.reloading = false
	else:
		var loaded := mini(int(info.clip_size) - actor.magazine, actor.reserve)
		actor.magazine += loaded
		actor.reserve -= loaded
		actor.reloading = false
	if not actor.reloading:
		actor.reload_deadline_tick = 0
		events.append(event(actor, tick, "reload_completed"))
	return frozen(events)

static func fire(actor: SharedPlayerState, tick: int, rng: RandomNumberGenerator = null) -> Array[Dictionary]:
	if not can_fire(actor, tick): return frozen([])
	var info := PROFILES.get_info(actor.profile, actor.weapon)
	actor.reloading = false
	actor.reload_deadline_tick = 0
	actor.magazine -= 1
	actor.next_shot_tick = (actor.next_shot_tick if actor.trigger_held else maxf(actor.next_shot_tick, tick)) + float(info.delay) * HZ
	actor.last_shot_tick = tick
	actor.dry_fire_held = false
	var front := actor.front()
	var directions := spread_directions(front, float(info.spread) * (.5 if actor.aiming else 1), int(info.pellets), rng if rng != null else actor.shot_rng)
	var right := Vector3(cos(actor.yaw), 0, -sin(actor.yaw))
	var recoil := source_recoil(front, right, right.cross(front), info.recoil, float(tick) / HZ, actor.motion.crouch)
	actor.yaw = atan2(-recoil.x, -recoil.z)
	actor.pitch = asin(clampf(recoil.y, -1, 1))
	return frozen([event(actor, tick, "shot", {"weapon":actor.weapon,"profile":actor.profile,
		"origin":actor.motion.physics_eye() + front * .01,"directions":directions,"recoil_direction":recoil})])

static func integrated_velocity(actor: SharedPlayerState, active: bool = true) -> Vector3:
	var velocity := actor.motion.native_velocity
	if not active:
		velocity.x /= 1 + DT * 4
		velocity.z /= 1 + DT * 4
	else:
		if actor.input_buttons & Buttons.JUMP != 0 and MOTION.is_on_ground_or_wade(actor.motion): velocity.y = .36
		var acceleration := DT
		if not actor.motion.grounded: acceleration *= .1
		elif actor.motion.crouch: acceleration *= .3
		elif actor.aiming or actor.sneaking: acceleration *= .5
		elif actor.sprinting: acceleration *= 1.3
		var slowdown := 1 - maxf(absf(sin(actor.pitch)) - .65, 0) / .35 * .9
		var forward := Vector3(-sin(actor.yaw), 0, -cos(actor.yaw))
		var right := Vector3(cos(actor.yaw), 0, -sin(actor.yaw))
		velocity += (right * actor.input_move.x + forward * -actor.input_move.y * slowdown) * acceleration
	velocity.y = (velocity.y - DT) / (1 + DT)
	if active:
		var friction := 1 + DT * (6 if actor.motion.wading else (4 if actor.motion.grounded else 1))
		velocity.x /= friction
		velocity.z /= friction
	return velocity

static func advance_motion(actor: SharedPlayerState, tick: int, query: Variant, authoritative_damage: bool = true) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var jumping := can_act(actor) and actor.input_buttons & Buttons.JUMP != 0 and MOTION.is_on_ground_or_wade(actor.motion)
	actor.motion.native_velocity = integrated_velocity(actor, can_act(actor))
	actor.motion.front = actor.front()
	actor.motion.sprint = actor.sprinting
	var incoming := -actor.motion.native_velocity.y
	actor.motion = MOTION.finish_landing(MOTION.clip_move(query, actor.motion, DT, float(tick) / HZ), incoming)
	if jumping: events.append(event(actor, tick, "jump"))
	if actor.motion.landed: events.append(event(actor, tick, "land", {"hurt":actor.motion.fall_hurt}))
	if authoritative_damage and actor.motion.fall_hurt: events.append_array(damage(actor, pow(incoming - .58, 2) * 4096, tick, 0, "fall"))
	if authoritative_damage and can_act(actor) and actor.motion.feet_position.y < -5: events.append_array(damage(actor, 1000, tick, 0, "fall"))
	if can_act(actor) and -actor.motion.native_velocity.y >= 0 and -actor.motion.native_velocity.y < .017 \
			and not actor.sneaking and not actor.motion.crouch and not actor.aiming:
		actor.walk_distance += Vector2(actor.motion.native_velocity.x, actor.motion.native_velocity.z).length() * 32 * DT
		if actor.walk_distance > 1 / .3:
			while actor.walk_distance > 1 / .3:
				actor.walk_distance -= 1 / .3
				actor.walk_steps += 1
			events.append(event(actor, tick, "footstep", {"wade":MOTION.get_wade(query, actor.motion)}))
	return frozen(events)

static func spread_directions(front: Vector3, spread: float, pellets: int, rng: RandomNumberGenerator) -> Array[Vector3]:
	var samples := PackedFloat32Array()
	if rng == null or pellets < 1 or pellets > 8: return []
	for sample in range(pellets * 6): samples.append(rng.randf())
	return spread_from_samples(front, spread, samples)

static func spread_from_samples(front: Vector3, spread: float, samples: PackedFloat32Array) -> Array[Vector3]:
	var directions: Array[Vector3] = []
	if not front.is_finite() or front.length_squared() < .000001 or not is_finite(spread) or spread < 0 \
			or samples.is_empty() or samples.size() % 6 != 0 or samples.size() > 48: return directions
	for value in samples:
		if not is_finite(value) or value < 0 or value > 1: return directions
	var accumulated := front
	for offset in range(0, samples.size(), 6):
		accumulated += Vector3(samples[offset] - samples[offset+1], samples[offset+2] - samples[offset+3], samples[offset+4] - samples[offset+5]) * spread
		directions.append(accumulated.normalized()) # Never normalize the accumulator.
	directions.make_read_only()
	return directions

static func source_recoil(front: Vector3, right: Vector3, up: Vector3, recoil: Vector3, time: float, crouch: bool) -> Vector3:
	var multiplier := .5 if crouch else 1.0
	var horizontal := Vector3(front.x, 0, front.z).normalized()
	var up_limit := horizontal.dot(front) - .03
	var phase := fposmod(time * .9788, 1)
	var wave := phase * 4 - 1 if phase < .5 else 3 - phase * 4
	return (front + up * minf(recoil.y, maxf(0, up_limit)) * multiplier + right * recoil.x * wave * multiplier).normalized()

static func deadline_tick(value: float) -> int:
	return ceili(value - .000000001)

static func f32(value: float) -> float:
	return Vector3(value, 0, 0).x

static func event(actor: SharedPlayerState, tick: int, kind: String, details: Dictionary = {}) -> Dictionary:
	actor.event_sequence += 1
	var result := details.duplicate(true)
	result.type = kind
	result.owner_id = actor.player_id
	result.spawn_generation = actor.spawn_generation
	result.epoch = actor.match_epoch
	result.tick = tick
	result.action_sequence = actor.consumed_input_sequence
	result.actor_event_sequence = actor.event_sequence
	result.event_id = "%d:%d:%d:%d" % [actor.match_epoch, actor.player_id, actor.spawn_generation, actor.event_sequence]
	freeze_value(result)
	return result

static func freeze_value(value: Variant) -> void:
	if value is Dictionary:
		for key: Variant in value: freeze_value(value[key])
		value.make_read_only()
	elif value is Array:
		for child: Variant in value: freeze_value(child)
		value.make_read_only()

static func frozen(events: Array[Dictionary]) -> Array[Dictionary]:
	events.make_read_only()
	return events
