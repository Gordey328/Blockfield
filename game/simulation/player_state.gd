class_name SharedPlayerState
extends RefCounted
## Per-actor simulation only. IDs are stable actors, never transport peer IDs.
const MOTION = preload("res://gameplay/source_player_motion.gd")
var player_id: int = 1
var match_epoch: int = 1
var spawn_generation: int = 0
var connected: bool = true
var player_name: String = "Player"
var team: int = 2
var profile: String = "0.75"
var weapon: int = 0
var pending_weapon: int = -1
var tool: int = 2 # Desired/authority tool, as Player::GetTool.
var displayed_tool: int = 2 # Native lower/swap/raise gate, not a renderer object.
var displayed_weapon: int = 0
var tool_raise: float = 0.0
var sprint_state: float = 0.0
var aim_down_state: float = 0.0
var aiming: bool = false
var sprinting: bool = false
var sneaking: bool = false
var yaw: float = 0.0
var pitch: float = 0.0
var motion: SourcePlayerMotion.State = MOTION.create_state(Vector3.ZERO)
var health: int = 0
var magazine: int = 0
var reserve: int = 0
var blocks: int = 0
var grenades: int = 0
var kills: int = 0
var deaths: int = 0
var score: int = 0 # Coordinator assigns kill/objective scores explicitly.
var last_tick: int = -1
var consumed_input_sequence: int = 0
var input_move: Vector2 = Vector2.ZERO
var input_buttons: int = 0
var previous_buttons: int = 0
var trigger_held: bool = false
var dry_fire_held: bool = false
## Fractional tick deadlines retain native overshoot during one trigger hold.
var next_shot_tick: float = 0.0
var last_shot_tick: int = -1
var reloading: bool = false
var reload_started_tick: float = 0.0
var reload_deadline_tick: float = 0.0
var grenade_deadline_tick: float = 0.0
var block_deadline_tick: float = 0.0
var spade_deadline_tick: float = -1.0
var dig_deadline_tick: float = -1.0
var digging: bool = false
var first_dig: bool = true
var cooking: bool = false
var cook_started_tick: int = -1
var cook_action_sequence: int = 0
var release_pending: bool = false
var death_tick: int = -1
var respawn_tick: int = -1
var event_sequence: int = 0
var walk_distance: float = 0.0
var walk_steps: int = 0
var shot_rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _init(id: int = 1, name: String = "Player", epoch: int = 1,
		version: String = "0.75", seed_value: int = 1) -> void:
	player_id = id
	player_name = name
	match_epoch = epoch
	profile = version
	shot_rng.seed = seed_value

func is_alive() -> bool:
	return spawn_generation > 0 and team in [0,1] and health > 0

func feet() -> Vector3:
	return motion.feet_position

func front() -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))

func walk_progress() -> float:
	return .5 * (walk_steps + walk_distance * .3)

func copy() -> SharedPlayerState:
	var result := SharedPlayerState.new(player_id, player_name, match_epoch, profile)
	# Only this script's scalar/value properties are copied. Motion/RNG are owned
	# copies, so replay cannot mutate another actor or cosmetic RNG stream.
	if get_script() != SharedPlayerState:
		# Retain the original reflective behavior for extension scripts, including
		# their extra properties and setter semantics. Base actors use typed reads.
		for property: Dictionary in get_script().get_script_property_list():
			var key: String = property.name
			if key in ["motion", "shot_rng"]: continue
			result.set(key, get(key))
	else:
		result.player_id = player_id
		result.match_epoch = match_epoch
		result.spawn_generation = spawn_generation
		result.connected = connected
		result.player_name = player_name
		result.team = team
		result.profile = profile
		result.weapon = weapon
		result.pending_weapon = pending_weapon
		result.tool = tool
		result.displayed_tool = displayed_tool
		result.displayed_weapon = displayed_weapon
		result.tool_raise = tool_raise
		result.sprint_state = sprint_state
		result.aim_down_state = aim_down_state
		result.aiming = aiming
		result.sprinting = sprinting
		result.sneaking = sneaking
		result.yaw = yaw
		result.pitch = pitch
		result.health = health
		result.magazine = magazine
		result.reserve = reserve
		result.blocks = blocks
		result.grenades = grenades
		result.kills = kills
		result.deaths = deaths
		result.score = score
		result.last_tick = last_tick
		result.consumed_input_sequence = consumed_input_sequence
		result.input_move = input_move
		result.input_buttons = input_buttons
		result.previous_buttons = previous_buttons
		result.trigger_held = trigger_held
		result.dry_fire_held = dry_fire_held
		result.next_shot_tick = next_shot_tick
		result.last_shot_tick = last_shot_tick
		result.reloading = reloading
		result.reload_started_tick = reload_started_tick
		result.reload_deadline_tick = reload_deadline_tick
		result.grenade_deadline_tick = grenade_deadline_tick
		result.block_deadline_tick = block_deadline_tick
		result.spade_deadline_tick = spade_deadline_tick
		result.dig_deadline_tick = dig_deadline_tick
		result.digging = digging
		result.first_dig = first_dig
		result.cooking = cooking
		result.cook_started_tick = cook_started_tick
		result.cook_action_sequence = cook_action_sequence
		result.release_pending = release_pending
		result.death_tick = death_tick
		result.respawn_tick = respawn_tick
		result.event_sequence = event_sequence
		result.walk_distance = walk_distance
		result.walk_steps = walk_steps
	result.motion = motion.copy()
	result.shot_rng.state = shot_rng.state
	return result
