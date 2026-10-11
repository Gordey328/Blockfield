class_name OpenSpadesEffects
extends Node3D
## Source: Client_LocalEnts.cpp, ParticleSpriteEntity.cpp, SmokeSpriteEntity.cpp,
## GunCasing.cpp, Tracer.cpp and Client_Scene.cpp in OpenSpades v0.1.3.
## World positions use Godot Y-up. The manager never edits gameplay blocks.

signal casing_contact(position: Vector3, water: bool, weapon: int)

const IMAGE_ROOT := "res://assets/openspades/images/"
const WEAPONS := ["Rifle", "SMG", "Shotgun"]
const EXTENSIONS = preload("res://presentation/openspades_extensions.gd")
const TRACER_SPEEDS := [350.0, 180.0, 250.0] # Native velocities * 0.5 visual slowdown.
const IGNORE := 0
const DELETE := 1
const BOUNCE := 2
const PARTICLE_HARD_CAP: int = 50
const CASING_HARD_CAP: int = 16
const CASING_LIFETIME: float = 2.0

class ParticleState:
	extends RefCounted
	var position: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO
	var age: float = 0.0
	var life: float = 1.0
	var radius: float = 0.1
	var color: Color = Color.WHITE
	var display_color: Color = Color.WHITE
	var gravity: float = 0.0
	var damping: float = 1.0
	var damping_log: float = 0.0
	var growth: float = 0.0
	var radius_damping: float = 1.0
	var radius_damping_log: float = 0.0
	var fade_in: float = 0.0
	var fade_out: float = 1.0
	var smoke: int = 0
	var fps: float = 60.0
	var frame: int = 0
	var spin: float = 0.0
	var batched: bool = true
	var priority: int = 0
	var sequence: int = 0
	var node: Sprite3D

class CasingVisual:
	extends Node3D
	var fade_materials: Array[BaseMaterial3D] = []
	var original_colors: PackedColorArray = PackedColorArray()
	var original_transparency: PackedInt32Array = PackedInt32Array()

class CasingState:
	extends RefCounted
	var node: CasingVisual
	var position: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO
	var age: float = 0.0
	var axis: Vector3 = Vector3.UP
	var spin: float = 40.0
	var weapon: int = 0
	var opacity: float = 1.0
	var sequence: int = 0

var quality := 2
var blood_enabled := true
var audio_enabled := true
var shake_level := 2
var max_particles: int = PARTICLE_HARD_CAP:
	set(value):
		max_particles = clampi(value, 0, PARTICLE_HARD_CAP)
		# A runtime budget reduction is immediate, including visible sprites.
		while _particle_count > max_particles:
			_retire_particle(_lowest_priority_particle())
		if _fragment_multimesh != null:
			_sync_fragment_batch()
var max_casings: int = CASING_HARD_CAP:
	set(value):
		max_casings = clampi(value, 0, CASING_HARD_CAP)
		while _casing_count > max_casings:
			_retire_casing(_oldest_casing())
var max_tracers := 64
var max_lights := 8
var world: Node3D
var camera: Camera3D
var rng := RandomNumberGenerator.new()
var _particle_slots: Array[ParticleState] = []
var _active_particle_slots: PackedInt32Array = PackedInt32Array()
var _free_particle_slots: PackedInt32Array = PackedInt32Array()
var _particle_count: int = 0
var _free_particle_count: int = 0
var _particle_sprite_count: int = 0
var _particle_sequence: int = 0
var _particle_recycled: int = 0
var _particle_dropped: int = 0
var _particle_updates: int = 0
var _particle_state_allocations: int = 0
var _casing_slots: Array[CasingState] = []
var _active_casing_slots: PackedInt32Array = PackedInt32Array()
var _free_casing_slots: PackedInt32Array = PackedInt32Array()
var _casing_count: int = 0
var _free_casing_count: int = 0
var _rifle_casing_count: int = 0
var _smg_casing_count: int = 0
var _casing_sequence: int = 0
var _casing_recycled: int = 0
var _casing_updates: int = 0
var _casing_state_allocations: int = 0
var _tracers: Array[Dictionary] = []
var _lights: Array[Dictionary] = []
var _particle_pool: Array[Node3D] = []
var _rifle_casing_pool: Array[Node3D] = []
var _smg_casing_pool: Array[Node3D] = []
var _tracer_pool: Array[Node3D] = []
var _light_pool: Array[Node3D] = []
var _created_nodes := 0
var _textures: Dictionary = {}
var _smoke_frames: Dictionary = {}
var _sounds: Array[AudioStreamPlayer3D] = []
var audio_service: OpenSpadesAudio
var _tracer_material: StandardMaterial3D
var _tracer_mesh: QuadMesh
var _fragment_batch: MultiMeshInstance3D
var _fragment_multimesh: MultiMesh
var _fragment_material: StandardMaterial3D
var _fragment_count := 0
var _fragment_aspect := 1.0
var _fragment_substeps: int = 0
var _fragment_position_writes: int = 0
var _fragment_scale_writes: int = 0
var _fragment_color_writes: int = 0
var _fragment_batch_transform_writes: int = 0
var _fragment_batch_color_writes: int = 0
var _fast_shake := 0.0
var _slow_shake := 0.0
var _time := 0.0
var _camera_rotation := Vector3.ZERO
var _noise := FastNoiseLite.new()

func setup(voxel_world: Node3D, view_camera: Camera3D) -> void:
	world = voxel_world
	camera = view_camera
	rng.randomize()
	_noise.seed = 7341
	_noise.frequency = 1.0
	prewarm()

func prewarm() -> void:
	# Loading-screen work: firing never instantiates sprites, GLB shells or lights
	# within the configured budgets. Each shell variant retains its own GLB.
	_ensure_particle_storage()
	_ensure_casing_storage()
	_trim_pool(_tracer_pool, max_tracers - _tracers.size())
	_trim_pool(_light_pool, max_lights - _lights.size())
	_texture("Gfx/White.png")
	_texture("Textures/WaterExpl.png")
	_texture("Textures/Fluid.png")
	_ensure_fragment_batch()
	for smoke in range(1, 3):
		if not _smoke_frames.has(smoke):
			var frames: Array[Texture2D] = []
			for frame in range(180 if smoke == 1 else 48):
				frames.append(_texture("Textures/Smoke%d/%03d.png" % [smoke, frame]))
			_smoke_frames[smoke] = frames
	_ensure_tracer_resources()
	while _tracer_pool.size() + _tracers.size() < max_tracers:
		_release(_new_tracer(), _tracer_pool, max_tracers)
	while _light_pool.size() + _lights.size() < max_lights:
		_release(_new_light(), _light_pool, max_lights)

func _process(delta: float) -> void:
	update_effects(delta)

func _exit_tree() -> void:
	stop_audio()

func reload_resources() -> void:
	clear()
	if is_instance_valid(_fragment_batch):
		remove_child(_fragment_batch)
		_dispose(_fragment_batch)
	_fragment_batch = null
	_fragment_multimesh = null
	_fragment_material = null
	# Queued nodes leave the manager immediately and cannot be acquired again.
	for node: Node3D in _particle_pool:
		if is_instance_valid(node):
			remove_child(node)
			_dispose(node)
	_particle_pool.clear()
	_particle_sprite_count = 0
	for pool in [_rifle_casing_pool, _smg_casing_pool, _tracer_pool, _light_pool]:
		for node: Node3D in pool:
			if is_instance_valid(node):
				remove_child(node)
				_dispose(node)
		pool.clear()
	_rifle_casing_count = 0
	_smg_casing_count = 0
	_textures.clear()
	_smoke_frames.clear()
	_tracer_material = null
	_tracer_mesh = null
	prewarm()

func stats() -> Dictionary:
	return {"particles": _particle_count, "casings": _casing_count,
		"tracers": _tracers.size(), "lights": _lights.size(), "audio": _sounds.size(),
		"pooled_particles": max_particles - _particle_count,
		"pooled_particle_sprites": _particle_sprite_count,
		"particle_hard_cap": PARTICLE_HARD_CAP, "particle_capacity": max_particles,
		"particle_slot_capacity": _particle_slots.size(),
		"particle_state_allocations": _particle_state_allocations,
		"particle_recycled": _particle_recycled, "particle_dropped": _particle_dropped,
		"particle_updates": _particle_updates,
		"pooled_casings": mini(_rifle_casing_count, max_casings) + mini(_smg_casing_count, max_casings),
		"pooled_casing_models": _rifle_casing_count + _smg_casing_count,
		"casing_hard_cap": CASING_HARD_CAP, "casing_capacity": max_casings,
		"casing_slot_capacity": _casing_slots.size(),
		"casing_state_allocations": _casing_state_allocations,
		"casing_recycled": _casing_recycled, "casing_updates": _casing_updates,
		"pooled_tracers": _tracer_pool.size(), "pooled_lights": _light_pool.size(),
		"created_nodes": _created_nodes, "batched_particles": _fragment_count,
		"fragment_substeps": _fragment_substeps,
		"fragment_position_writes": _fragment_position_writes,
		"fragment_scale_writes": _fragment_scale_writes,
		"fragment_color_writes": _fragment_color_writes,
		"fragment_batch_transform_writes": _fragment_batch_transform_writes,
		"fragment_batch_color_writes": _fragment_batch_color_writes}

func particle_count() -> int:
	return _particle_count

func particle_snapshot(index: int) -> Dictionary:
	# Diagnostics allocate only on explicit request; rendering never uses this.
	if index < 0 or index >= _particle_count:
		return {}
	var entry: ParticleState = _particle_slots[_active_particle_slots[index]]
	var snapshot: Dictionary = {"position": entry.position, "velocity": entry.velocity,
		"age": entry.age, "life": entry.life, "radius": entry.radius,
		"color": entry.color, "display_color": entry.display_color, "spin": entry.spin,
		"smoke": entry.smoke, "frame": entry.frame, "batched": entry.batched,
		"visible": entry.batched or (is_instance_valid(entry.node) and entry.node.visible),
		"gravity": entry.gravity, "damping": entry.damping, "growth": entry.growth,
		"priority": entry.priority, "sequence": entry.sequence}
	if entry.node != null:
		snapshot["node"] = entry.node
	return snapshot

func casing_count() -> int:
	return _casing_count

func casing_snapshot(index: int) -> Dictionary:
	if index < 0 or index >= _casing_count:
		return {}
	var entry: CasingState = _casing_slots[_active_casing_slots[index]]
	return {"position": entry.position, "velocity": entry.velocity, "age": entry.age,
		"life": CASING_LIFETIME, "weapon": entry.weapon, "node": entry.node,
		"visible": is_instance_valid(entry.node) and entry.node.visible,
		"axis": entry.axis, "spin": entry.spin, "opacity": entry.opacity,
		"sequence": entry.sequence}

func clear() -> void:
	stop_audio()
	while _particle_count > 0:
		_retire_particle(_particle_count - 1)
	while _casing_count > 0:
		_retire_casing(_casing_count - 1)
	for entry in _tracers:
		_release(entry.node, _tracer_pool, max_tracers)
	for entry in _lights:
		_release(entry.node, _light_pool, max_lights)
	_tracers.clear()
	_lights.clear()
	_fragment_count = 0
	if _fragment_multimesh != null:
		_fragment_multimesh.visible_instance_count = 0
		_fragment_batch.visible = false
	_trim_pool(_tracer_pool, max_tracers)
	_trim_pool(_light_pool, max_lights)
	_fast_shake = 0.0
	_slow_shake = 0.0
	_camera_rotation = Vector3.ZERO

func stop_audio() -> void:
	for sound in _sounds:
		if is_instance_valid(sound):
			sound.stop()
			sound.stream = null
			_dispose(sound)
	_sounds.clear()

func get_camera_rotation() -> Vector3:
	# Add this temporary Euler offset to the controller's unshaken camera pose.
	return _camera_rotation

func kick_camera(strength: float) -> void:
	_fast_shake = minf(_fast_shake + maxf(strength, 0.0), 0.4)
	_slow_shake = minf(_slow_shake + maxf(strength, 0.0) * 5.0, 0.4)

func collapse_impact(position: Vector3,block_count: int) -> void:
	var distance:=_distance(position)
	if distance>170.0:return
	# A large grenade-triggered collapse must not restore a distant full kick.
	var strength: float = minf(1.0, maxf(0.0, float(block_count)) / 100.0 / (distance + 5.0))
	_slow_shake=minf(1.0,_slow_shake+strength*GrenadeFeedback.distance_gain(distance))

func blood(position: Vector3) -> void:
	if not blood_enabled or quality < 1 or _distance(position) > 150.0:
		return
	for index in range(10):
		_emit(position, _random_vector() * 10.0, Color(0.5, 0.02, 0.04),
			0.1 + _product() * 0.2, 3.0, 0.7)
	if quality < 2:
		return
	for index in range(2):
		_emit(position, _random_vector() * 0.7, Color(0.7, 0.35, 0.37, 0.6),
			0.5 + _product() * 0.2, 0.2 + rng.randf() * 0.2,
			0.0, 0.8, 2.0, 1.0, 0.06, 0.2, 2, 100.0)
	_emit(position, _random_vector() * 0.7, Color(0.7, 0.35, 0.37, 0.06),
		0.7 + _product() * 0.2, 0.8 + rng.randf() * 0.4,
		0.0, 0.8, 2.0, 0.1, 0.06, 1.0, 1, 40.0)

func block_hit(position: Vector3, normal: Vector3, color: Color, water: bool = false) -> void:
	var origin := position + normal * 0.05
	if water:
		water_hit(origin)
		return
	var distance := _distance(origin)
	if quality < 1 or distance > 150.0:
		return
	for index in range(7):
		_emit(origin, _random_vector() * 7.0, color, 0.2 + _product() * 0.1, 2.0, 0.9)
	if quality < 2:
		return
	if distance < 32.0:
		for index in range(16):
			_emit(origin, _random_vector() * 12.0, color, 0.1 + _product() * 0.14, 2.0, 0.9)
	var dust := color.lerp(Color.WHITE, 0.2)
	dust.a = 0.2
	for index in range(2):
		_emit(origin, _random_vector() * 0.7, dust, 0.6 + _product() * 0.2,
			0.3 + rng.randf() * 0.3, 0.0, 1.0, 0.8, 1.0, 0.06, 0.4, 1, 100.0)

func block_destroy(position: Vector3, color: Color) -> void:
	# Direct deletions only. Falling connected clusters have world-owned batches.
	if quality < 1 or _distance(position) > 150.0:
		return
	for index in range(8):
		_emit(position, _random_vector() * 7.0, color, 0.3 + _product() * 0.2, 2.0, 1.0)

func muzzle_fire(position: Vector3, _direction: Vector3, _weapon: int, _local: bool = true) -> void:
	_flash(position, 5.0, 0.045)
	if quality < 1:
		return
	for index in range(2):
		_emit(position, (_random_vector() + Vector3.UP * 0.25) * 0.3,
			Color(0.8, 0.8, 0.8, 0.3), 0.4, 0.2 + rng.randf() * 0.1,
			0.0, 1.0, 3.0, 0.0000005, 0.0, 0.3, 2, 120.0, "Gfx/White.png", 3)

func grenade_explosion(position: Vector3, underwater: bool = false) -> void:
	var distance := _distance(position)
	if distance > 170.0:
		return
	kick_camera((1.5 if underwater else 2.0) / (distance + 5.0) * GrenadeFeedback.distance_gain(distance))
	if underwater:
		_underwater_explosion(position)
		return
	_flash(position, 16.0, 0.09)
	if quality < 1:
		return
	# Decorative particles have no terrain query path, including emission bias.
	for index in range(4):
		_emit(position, _random_vector() * 2.0, Color(0.6, 0.6, 0.6),
			0.6 + _product() * 0.4, 1.8 + rng.randf() * 0.1,
			0.0, 1.0, 2.0, 0.2, 0.0, 0.2, 2, 60.0)
	for index in range(8):
		var velocity := _random_vector()
		velocity.y *= 0.2
		var life := 0.8 + rng.randf() if quality < 2 else 2.0 + rng.randf() * 5.0
		_emit(position, velocity * 2.0, Color(0.6, 0.6, 0.6, 0.25),
			1.5 + _product() * 0.8, life,
			0.0, 1.0, 0.2, 1.0, 0.1, 8.0, 1, 20.0)
	for index in range(42):
		var radius := 0.1 + _product() * 0.2
		_emit(position, _random_vector() * 20.0, Color(0.01, 0.03, 0),
			radius, 3.5 + rng.randf() * 2.0,
			1.0, 0.1 + radius * 3.0)
	for index in range(4):
		_emit(position, _random_vector() * 6.0, Color(5, 3.5, 2, 1),
			0.3 + _product() * 0.4, 0.18 + rng.randf() * 0.03,
			0.0, 1.0, 3.0, 0.1, 0.0, 0.1, 2, 120.0, "Gfx/White.png", 3)

func _underwater_explosion(position: Vector3) -> void:
	if quality < 1:
		return
	for index in range(7):
		var velocity := _random_vector()
		velocity.y = rng.randf() * 7.0
		_emit(position, velocity * 2.5, Color(0.95, 0.95, 0.95, 0.6),
			1.5 + _product() * 0.4, 3.0 + rng.randf() * 0.3,
			0.6, 0.3, 1.3, 1.0, 0.0, 0.6, 0, 60.0, "Textures/WaterExpl.png")
	for index in range(16):
		var velocity := _random_vector()
		velocity.y = rng.randf() * 10.0
		_emit(position, velocity * 3.5, Color(0.95, 0.95, 0.95, 0.9),
			0.9 + _product() * 0.4, 3.0 + rng.randf() * 0.3,
			1.0, 1.0, 0.7, 1.0, 0.7, 0.6, 0, 60.0, "Textures/Fluid.png")
	for index in range(8):
		var velocity := _random_vector()
		velocity.y = rng.randf() * 0.2
		_emit(position, velocity * 2.0, Color(0.95, 0.95, 0.95, 0.4),
			1.4 + _product() * 0.8, 6.0 + rng.randf() * 5.0,
			0.0, 1.0, 0.2, 1.0, 0.1, 8.0, 1, 20.0)
	for index in range(42):
		var velocity := _random_vector()
		velocity.y = rng.randf() * 3.0
		var radius := 0.1 + _product() * 0.2
		_emit(position, velocity * 13.0, Color(0.95, 0.95, 0.95), radius,
			3.5 + rng.randf() * 2.0, 1.0, 0.1 + radius * 3.0)

func water_hit(position: Vector3) -> void:
	if quality < 1 or _distance(position) > 150.0:
		return
	for index in range(2):
		var velocity := _random_vector()
		velocity.y = rng.randf() * 7.0
		_emit(position, velocity, Color(0.95, 0.95, 0.95, 0.3),
			0.6 + _product() * 0.4, 3.0 + rng.randf() * 0.3,
			0.6, 0.3, 0.7, 1.0, 0.1, 0.6, 0, 60.0, "Textures/WaterExpl.png")
	for index in range(6):
		var velocity := _random_vector()
		velocity.y = rng.randf() * 10.0
		_emit(position, velocity * 2.0, Color(0.95, 0.95, 0.95, 0.9),
			0.6 + _product() * 0.6, 3.0 + rng.randf() * 0.3,
			1.0, 1.0, 0.6, 1.0, rng.randf() * 0.3, 0.6, 0, 60.0, "Textures/Fluid.png")

func eject_shell(position: Vector3, front: Vector3, right: Vector3, up: Vector3, weapon: int) -> void:
	# Original source has no shotgun firing ejection (pump ejection is a FIXME).
	if max_casings == 0 or weapon < 0 or weapon > 1 or _distance(position) > 130.0:
		return
	if _casing_slots.is_empty() or _rifle_casing_pool.is_empty():
		_ensure_casing_storage()
	if _casing_count >= max_casings:
		_retire_casing(_oldest_casing())
		_casing_recycled += 1
	var pool := _casing_pool(weapon)
	var pool_index: int = _rifle_casing_count - 1 if weapon == 0 else _smg_casing_count - 1
	var node: CasingVisual = pool[pool_index] as CasingVisual
	pool[pool_index] = null
	if weapon == 0:
		_rifle_casing_count -= 1
	else:
		_smg_casing_count -= 1
	node.transform = Transform3D.IDENTITY
	node.visible = true
	node.global_position = position - front * 0.5
	node.global_basis = Basis(right.normalized(), up.normalized(), -front.normalized()).orthonormalized()
	var fly_direction := front * (0.5 if weapon == 0 else -0.2) + right + up * 0.2
	var axis := Vector3.UP.cross(fly_direction).normalized()
	_free_casing_count -= 1
	var slot: int = _free_casing_slots[_free_casing_count]
	_active_casing_slots[_casing_count] = slot
	_casing_count += 1
	var entry: CasingState = _casing_slots[slot]
	entry.node = node
	entry.position = node.global_position
	entry.velocity = fly_direction * 10.0
	entry.axis = axis
	entry.spin = 40.0
	entry.weapon = weapon
	entry.age = 0.0
	entry.opacity = 1.0
	_casing_sequence += 1
	entry.sequence = _casing_sequence

func _ensure_casing_storage() -> void:
	if _casing_slots.is_empty():
		_casing_slots.resize(CASING_HARD_CAP)
		_active_casing_slots.resize(CASING_HARD_CAP)
		_free_casing_slots.resize(CASING_HARD_CAP)
		for index: int in range(CASING_HARD_CAP):
			_casing_slots[index] = CasingState.new()
			_free_casing_slots[index] = index
			_casing_state_allocations += 1
		_free_casing_count = CASING_HARD_CAP
	if _rifle_casing_pool.is_empty():
		_rifle_casing_pool.resize(CASING_HARD_CAP)
		_smg_casing_pool.resize(CASING_HARD_CAP)
		for index: int in range(CASING_HARD_CAP):
			_rifle_casing_pool[index] = _new_casing(0)
			_smg_casing_pool[index] = _new_casing(1)
		_rifle_casing_count = CASING_HARD_CAP
		_smg_casing_count = CASING_HARD_CAP

func _oldest_casing() -> int:
	var result: int = 0
	var sequence: int = _casing_slots[_active_casing_slots[0]].sequence
	for index: int in range(1, _casing_count):
		var candidate: CasingState = _casing_slots[_active_casing_slots[index]]
		if candidate.sequence < sequence:
			sequence = candidate.sequence
			result = index
	return result

func _retire_casing(index: int) -> void:
	var slot: int = _active_casing_slots[index]
	var entry: CasingState = _casing_slots[slot]
	entry.node.visible = false
	entry.node.transform = Transform3D.IDENTITY
	if entry.opacity != 1.0:
		_set_casing_opacity(entry.node, 1.0)
	var pool: Array[Node3D] = _casing_pool(entry.weapon)
	if entry.weapon == 0:
		pool[_rifle_casing_count] = entry.node
		_rifle_casing_count += 1
	else:
		pool[_smg_casing_count] = entry.node
		_smg_casing_count += 1
	entry.node = null
	_casing_count -= 1
	_active_casing_slots[index] = _active_casing_slots[_casing_count]
	_free_casing_slots[_free_casing_count] = slot
	_free_casing_count += 1

func tracer(origin: Vector3, end: Vector3, weapon: int, local_first_person: bool = false) -> void:
	_trim_pool(_tracer_pool, max_tracers - _tracers.size())
	if local_first_person or _tracers.size() >= max_tracers or origin.distance_to(end) < 0.001:
		return
	_ensure_tracer_resources()
	var node: MeshInstance3D = (_tracer_pool.pop_back() if not _tracer_pool.is_empty() else _new_tracer()) as MeshInstance3D
	# The first tracer update supplies its transform and visibility.
	node.transform = Transform3D.IDENTITY
	node.visible = false
	var speed: float = TRACER_SPEEDS[clampi(weapon, 0, 2)]
	_tracers.append({"node": node, "origin": origin, "direction": origin.direction_to(end),
		"distance": -speed / 30.0 + rng.randf() / 30.0, "length": origin.distance_to(end),
		"speed": speed, "visible_length": speed / 30.0, "first": true})

func _ensure_tracer_resources() -> void:
	if _tracer_material == null:
		_tracer_material = StandardMaterial3D.new()
		_tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_tracer_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_tracer_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_tracer_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_tracer_material.albedo_texture = _texture("Gfx/Ball.png")
		_tracer_material.albedo_color = Color(1.0, 0.6, 0.2, 0.4)
		_tracer_mesh = QuadMesh.new()
		_tracer_mesh.size = Vector2(1.0, 0.1)

func update_effects(delta: float) -> void:
	var elapsed: float = maxf(delta, 0.0) if is_finite(delta) else 0.0
	_update_particles(elapsed, elapsed, elapsed)
	_update_casings(elapsed, elapsed, elapsed)
	_sync_fragment_batch()
	_update_tracers(elapsed, maxf(0.0, elapsed - 0.1))
	for index in range(_lights.size() - 1, -1, -1):
		var entry: Dictionary = _lights[index]
		entry.life -= elapsed
		if entry.life <= 0:
			_release(entry.node, _light_pool, max_lights)
			_lights.remove_at(index)
	# Lifetime, free flight and camera vibration use the real elapsed time.
	_time += elapsed
	_fast_shake = maxf(0.0, _fast_shake - elapsed)
	_slow_shake = maxf(0.0, _slow_shake - elapsed)
	_camera_rotation = Vector3.ZERO
	if shake_level >= 1:
		var intensity := minf(_fast_shake * 10.0, 1.0)
		_camera_rotation = _random_vector() * Vector3(0.1, 0.1, 0.2) * intensity
	if shake_level >= 2:
		var intensity := pow(minf(_slow_shake * 4.0, 1.0), 2.0)
		_camera_rotation += Vector3(_noise.get_noise_1d(_time * 12.0),
			_noise.get_noise_1d(_time * 11.0 + 31.0), _noise.get_noise_1d(_time * 8.0 + 61.0)) * Vector3(0.1, 0.1, 0.2) * intensity

func _spawn(position: Vector3, velocity: Vector3, color: Color, radius: float, life: float, options: Dictionary = {}) -> void:
	# Legacy diagnostic callers can still supply options; collision is ignored.
	# All gameplay emission paths below use the typed emitter without Dictionaries.
	_emit(position, velocity, color, radius, life, options.get("gravity", 0.0),
		options.get("damping", 1.0), options.get("growth", 0.0),
		options.get("radius_damping", 1.0), options.get("fade_in", 0.0),
		options.get("fade_out", 1.0), options.get("smoke", 0), options.get("fps", 60.0),
		options.get("image", "Gfx/White.png"), options.get("priority", -1))

func _ensure_particle_storage() -> void:
	if _particle_slots.is_empty():
		_particle_slots.resize(PARTICLE_HARD_CAP)
		_active_particle_slots.resize(PARTICLE_HARD_CAP)
		_free_particle_slots.resize(PARTICLE_HARD_CAP)
		for index: int in range(PARTICLE_HARD_CAP):
			_particle_slots[index] = ParticleState.new()
			_free_particle_slots[index] = index
			_particle_state_allocations += 1
		_free_particle_count = PARTICLE_HARD_CAP
	if _particle_pool.is_empty():
		_particle_pool.resize(PARTICLE_HARD_CAP)
		for index: int in range(PARTICLE_HARD_CAP):
			_particle_pool[index] = _new_particle()
		_particle_sprite_count = PARTICLE_HARD_CAP

func _emit(position: Vector3, velocity: Vector3, color: Color, radius: float, life: float,
	gravity: float = 0.0, damping: float = 1.0, growth: float = 0.0,
	radius_damping: float = 1.0, fade_in: float = 0.0, fade_out: float = 1.0,
	smoke: int = 0, fps: float = 60.0, image: String = "Gfx/White.png", importance: int = -1) -> void:
	if max_particles == 0 or life <= 0.0 or not is_finite(life) or not position.is_finite() or not velocity.is_finite():
		return
	if _particle_slots.is_empty() or _particle_pool.is_empty():
		_ensure_particle_storage()
	var kind: int = clampi(smoke, 0, 2)
	var rank: int = _particle_priority(position, importance if importance >= 0 else (0 if kind == 1 else 1 if kind == 2 else 2))
	if _particle_count >= max_particles:
		var victim_index: int = _lowest_priority_particle()
		var victim: ParticleState = _particle_slots[_active_particle_slots[victim_index]]
		if rank < victim.priority:
			_particle_dropped += 1
			return
		_retire_particle(victim_index)
		_particle_recycled += 1
	_free_particle_count -= 1
	var slot: int = _free_particle_slots[_free_particle_count]
	_active_particle_slots[_particle_count] = slot
	_particle_count += 1
	var entry: ParticleState = _particle_slots[slot]
	entry.position = position
	entry.velocity = velocity
	entry.age = 0.0
	entry.life = life
	entry.radius = maxf(0.0001, radius)
	entry.color = color
	entry.gravity = gravity
	entry.damping = clampf(damping, 0.000000000000000000000000000001, 1.0)
	entry.damping_log = log(entry.damping) if entry.damping != 1.0 else 0.0
	entry.growth = growth
	entry.radius_damping = clampf(radius_damping, 0.000000000000000000000000000001, 1.0)
	entry.radius_damping_log = log(entry.radius_damping) if entry.radius_damping != 1.0 else 0.0
	entry.fade_in = maxf(0.0, fade_in)
	entry.fade_out = maxf(0.0, fade_out)
	entry.smoke = kind
	entry.fps = maxf(0.0, fps)
	entry.frame = 0
	entry.spin = rng.randf() * TAU
	entry.batched = kind == 0 and image == "Gfx/White.png"
	entry.priority = rank
	_particle_sequence += 1
	entry.sequence = _particle_sequence
	entry.display_color = _particle_color(entry)
	if not entry.batched:
		_particle_sprite_count -= 1
		entry.node = _particle_pool[_particle_sprite_count] as Sprite3D
		_particle_pool[_particle_sprite_count] = null
		entry.node.texture = _smoke_texture(kind, 0) if kind != 0 else _texture(image)
		entry.node.pixel_size = 1.0 / float(entry.node.texture.get_width())
		entry.node.modulate = entry.display_color
		entry.node.scale = Vector3.ONE * entry.radius * 2.0
		entry.node.rotation.z = entry.spin
		entry.node.global_position = position
		entry.node.visible = true

func _particle_priority(position: Vector3, importance: int) -> int:
	var distance: float = _distance(position)
	return clampi(importance, 0, 3) * 4 + (3 if distance < 16.0 else 2 if distance < 32.0 else 1 if distance < 64.0 else 0)

func _lowest_priority_particle() -> int:
	var result: int = 0
	var lowest: ParticleState = _particle_slots[_active_particle_slots[0]]
	for index: int in range(1, _particle_count):
		var candidate: ParticleState = _particle_slots[_active_particle_slots[index]]
		if candidate.priority < lowest.priority or (candidate.priority == lowest.priority and candidate.sequence < lowest.sequence):
			lowest = candidate
			result = index
	return result

func _retire_particle(index: int) -> void:
	var slot: int = _active_particle_slots[index]
	var entry: ParticleState = _particle_slots[slot]
	if entry.node != null:
		entry.node.visible = false
		entry.node.transform = Transform3D.IDENTITY
		entry.node.modulate = Color.WHITE
		_particle_pool[_particle_sprite_count] = entry.node
		_particle_sprite_count += 1
		entry.node = null
	_particle_count -= 1
	_active_particle_slots[index] = _active_particle_slots[_particle_count]
	_free_particle_slots[_free_particle_count] = slot
	_free_particle_count += 1

func _update_particles(delta: float, _lifetime_delta: float, _frame_elapsed: float) -> void:
	for index: int in range(_particle_count - 1, -1, -1):
		var entry: ParticleState = _particle_slots[_active_particle_slots[index]]
		entry.age += delta
		if entry.age >= entry.life:
			_retire_particle(index)
			continue
		var frame: int = floori(entry.age * entry.fps) if entry.smoke > 0 else 0
		if entry.smoke == 2 and frame >= 48:
			_retire_particle(index)
			continue
		_particle_updates += 1
		if entry.batched:
			_fragment_substeps += 1
		# Exact constant-acceleration/drag integration needs one update per frame.
		var exponent: float = entry.damping_log * delta
		var decay: float = exp(exponent) if entry.damping_log != 0.0 else 1.0
		var travel: float = delta
		var acceleration_travel: float = delta * delta * 0.5
		if absf(exponent) < 0.001:
			travel *= 1.0 + exponent * (0.5 + exponent / 6.0)
			acceleration_travel *= 1.0 + exponent * (1.0 / 3.0 + exponent / 12.0)
		else:
			travel = (decay - 1.0) / entry.damping_log
			acceleration_travel = (travel - delta) / entry.damping_log
		var acceleration: Vector3 = Vector3(0.0, -32.0 * entry.gravity, 0.0)
		entry.position += entry.velocity * travel + acceleration * acceleration_travel
		entry.velocity = entry.velocity * decay + acceleration * travel
		if entry.growth != 0.0:
			var growth_exponent: float = entry.radius_damping_log * delta
			var growth_decay: float = exp(growth_exponent) if entry.radius_damping_log != 0.0 else 1.0
			var growth_travel: float = delta
			if absf(growth_exponent) < 0.001:
				growth_travel *= 1.0 + growth_exponent * (0.5 + growth_exponent / 6.0)
			else:
				growth_travel = (growth_decay - 1.0) / entry.radius_damping_log
			entry.radius = maxf(0.0001, entry.radius + entry.growth * growth_travel)
			entry.growth *= growth_decay
		entry.display_color = _particle_color(entry)
		if entry.node != null:
			entry.node.global_position = entry.position
			entry.node.scale = Vector3.ONE * entry.radius * 2.0
			entry.node.modulate = entry.display_color
			if entry.smoke > 0:
				frame %= 180 if entry.smoke == 1 else 48
				if frame != entry.frame:
					entry.node.texture = _smoke_texture(entry.smoke, frame)
					entry.frame = frame

func _particle_color(entry: ParticleState) -> Color:
	var fade: float = 1.0
	var age: float = entry.age
	var fade_in: float = entry.fade_in
	var fade_out: float = entry.fade_out
	if fade_in > 0.0:
		fade *= minf(age / fade_in, 1.0)
	if fade_out > 0.0:
		fade *= minf((entry.life - age) / fade_out, 1.0)
	var color: Color = entry.color
	color.a *= clampf(fade, 0.0, 1.0)
	return color

func _update_casings(delta: float, _lifetime_delta: float, _frame_elapsed: float) -> void:
	for index: int in range(_casing_count - 1, -1, -1):
		var entry: CasingState = _casing_slots[_active_casing_slots[index]]
		entry.age += delta
		if entry.age >= CASING_LIFETIME:
			_retire_casing(index)
			continue
		_casing_updates += 1
		entry.position += entry.velocity * delta + Vector3.DOWN * 16.0 * delta * delta
		entry.velocity.y -= 32.0 * delta
		entry.node.global_position = entry.position
		entry.node.rotate_object_local(entry.axis, entry.spin * delta)
		var opacity: float = minf(1.0, (CASING_LIFETIME - entry.age) / 0.5)
		if opacity != entry.opacity:
			entry.opacity = opacity
			_set_casing_opacity(entry.node, opacity)

func _set_casing_opacity(node: CasingVisual, opacity: float) -> void:
	# Per-model material copies are prepared on loading. GeometryInstance3D's
	# transparency property does not work with the Compatibility renderer.
	for index: int in range(node.fade_materials.size()):
		var material: BaseMaterial3D = node.fade_materials[index]
		var color: Color = node.original_colors[index]
		color.a *= opacity
		material.albedo_color = color
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if opacity < 1.0 else node.original_transparency[index]

func _update_tracers(delta: float, first_frame_hitch: float = 0.0) -> void:
	for index in range(_tracers.size() - 1, -1, -1):
		var entry: Dictionary = _tracers[index]
		if not entry.first:
			entry.distance += entry.speed * delta
		else:
			# Preserve the native initial segment at normal frame times while
			# accounting for real time lost beyond the first collision frame.
			entry.distance += entry.speed * first_frame_hitch
		entry.first = false
		if entry.distance > entry.length:
			_release(entry.node, _tracer_pool, max_tracers)
			_tracers.remove_at(index)
			continue
		var start := maxf(entry.distance, 0.0)
		var end := minf(entry.distance + entry.visible_length, entry.length)
		var node: MeshInstance3D = entry.node
		node.visible = end > start
		if not node.visible:
			continue
		var middle: Vector3 = entry.origin + entry.direction * (start + end) * 0.5
		var view: Vector3 = camera.global_position - middle if is_instance_valid(camera) else Vector3.UP
		var y: Vector3 = entry.direction.cross(view).normalized()
		if y.length_squared() < 0.1:
			y = entry.direction.cross(Vector3.RIGHT if absf(entry.direction.x) < 0.8 else Vector3.UP).normalized()
		node.global_transform = Transform3D(Basis(entry.direction * (end - start), y, entry.direction.cross(y)), middle)

func _flash(position: Vector3, radius: float, life: float) -> void:
	_trim_pool(_light_pool, max_lights - _lights.size())
	if _lights.size() >= max_lights:
		return
	var node: OmniLight3D = (_light_pool.pop_back() if not _light_pool.is_empty() else _new_light()) as OmniLight3D
	node.transform = Transform3D.IDENTITY
	node.omni_range = radius
	node.light_color = Color(1.0, 1.6 / 3.0, 0.5 / 3.0)
	node.light_energy = 3.0
	node.shadow_enabled = false
	node.visible = true
	node.global_position = position
	_lights.append({"node": node, "life": life})

func _distance(position: Vector3) -> float:
	return camera.global_position.distance_to(position) if is_instance_valid(camera) else 0.0

func _random_vector() -> Vector3:
	return Vector3(rng.randf() - rng.randf(), rng.randf() - rng.randf(), rng.randf() - rng.randf())

func _product() -> float:
	return rng.randf() * rng.randf()

func _texture(relative: String) -> Texture2D:
	if not _textures.has(relative):
		_textures[relative] = EXTENSIONS.texture(IMAGE_ROOT + relative)
	return _textures[relative]

func _smoke_texture(smoke: int, frame: int) -> Texture2D:
	if not _smoke_frames.has(smoke):
		# Supports tools which reload resources then emit before setup/prewarm.
		var frames: Array[Texture2D] = []
		for index in range(180 if smoke == 1 else 48):
			frames.append(_texture("Textures/Smoke%d/%03d.png" % [smoke, index]))
		_smoke_frames[smoke] = frames
	return _smoke_frames[smoke][frame]

func _casing_pool(weapon: int) -> Array[Node3D]:
	return _rifle_casing_pool if weapon == 0 else _smg_casing_pool

func _new_particle() -> Sprite3D:
	var node := Sprite3D.new()
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.shaded = false
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_register_node(node)
	return node

func _new_casing(weapon: int) -> CasingVisual:
	var node := CasingVisual.new()
	var model := OpenSpadesModels.create("Weapons/%s/Casing" % WEAPONS[weapon])
	model.scale = Vector3.ONE * 0.02
	node.add_child(model)
	_prepare_casing_materials(model, node)
	_register_node(node)
	return node

func _prepare_casing_materials(model: Node, visual: CasingVisual) -> void:
	if model is MeshInstance3D:
		var mesh_node: MeshInstance3D = model as MeshInstance3D
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mesh_node.mesh != null:
			for surface: int in range(mesh_node.mesh.get_surface_count()):
				var source: BaseMaterial3D = mesh_node.get_surface_override_material(surface) as BaseMaterial3D
				if source == null:
					source = mesh_node.mesh.surface_get_material(surface) as BaseMaterial3D
				if source != null:
					var material: BaseMaterial3D = source.duplicate() as BaseMaterial3D
					mesh_node.set_surface_override_material(surface, material)
					visual.fade_materials.append(material)
					visual.original_colors.append(material.albedo_color)
					visual.original_transparency.append(material.transparency)
	for child: Node in model.get_children():
		_prepare_casing_materials(child, visual)

func _new_tracer() -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = _tracer_mesh
	node.material_override = _tracer_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_register_node(node)
	return node

func _new_light() -> OmniLight3D:
	var node := OmniLight3D.new()
	node.shadow_enabled = false
	_register_node(node)
	return node

func _ensure_fragment_batch() -> void:
	if _fragment_multimesh == null:
		var texture := _texture("Gfx/White.png")
		_fragment_aspect = float(texture.get_height()) / float(texture.get_width())
		_fragment_material = StandardMaterial3D.new()
		_fragment_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_fragment_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_fragment_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_fragment_material.vertex_color_use_as_albedo = true
		_fragment_material.albedo_texture = texture
		_fragment_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		var mesh := QuadMesh.new()
		mesh.size = Vector2(1.0, _fragment_aspect)
		mesh.material = _fragment_material
		_fragment_multimesh = MultiMesh.new()
		_fragment_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		_fragment_multimesh.use_colors = true
		_fragment_multimesh.mesh = mesh
		_fragment_batch = MultiMeshInstance3D.new()
		_fragment_batch.multimesh = _fragment_multimesh
		_fragment_batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_register_node(_fragment_batch)
	if _fragment_multimesh.instance_count != PARTICLE_HARD_CAP:
		_fragment_multimesh.instance_count = PARTICLE_HARD_CAP
		_fragment_multimesh.visible_instance_count = 0
		_fragment_count = 0
		_fragment_batch.visible = false

func _sync_fragment_batch() -> void:
	if _fragment_multimesh == null:
		_ensure_fragment_batch()
	_fragment_count = 0
	if _particle_count == 0:
		_fragment_multimesh.visible_instance_count = 0
		_fragment_batch.visible = false
		return
	var billboard := camera.global_basis.orthonormalized() if is_instance_valid(camera) else Basis.IDENTITY
	var to_local := _fragment_batch.global_transform.affine_inverse()
	for active_index: int in range(_particle_count):
		var entry: ParticleState = _particle_slots[_active_particle_slots[active_index]]
		if entry.batched:
			_write_fragment(_fragment_count, entry, billboard, to_local)
			_fragment_count += 1
	_fragment_multimesh.visible_instance_count = _fragment_count
	_fragment_batch.visible = _fragment_count > 0

func _write_fragment(index: int, entry: ParticleState, billboard: Basis, to_local: Transform3D) -> void:
	# White fragments own no nodes. Their world-space state feeds the batch.
	var facing := billboard * Basis(Vector3.BACK, entry.spin) * Basis.from_scale(Vector3.ONE * entry.radius * 2.0)
	var pose := Transform3D(facing, entry.position)
	var local_pose := to_local * pose
	_fragment_multimesh.set_instance_transform(index, local_pose)
	_fragment_multimesh.set_instance_color(index, entry.display_color)
	_fragment_batch_transform_writes += 1
	_fragment_batch_color_writes += 1

func _register_node(node: Node3D) -> void:
	_created_nodes += _node_count(node)
	node.visible = false
	node.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(node)

func _node_count(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _node_count(child)
	return count

func _release(node: Node3D, pool: Array[Node3D], limit: int) -> void:
	node.visible = false
	node.transform = Transform3D.IDENTITY
	if node is Sprite3D:
		node.modulate = Color.WHITE
	elif node is OmniLight3D:
		node.light_energy = 0.0
	if pool.size() < maxi(0, limit):
		pool.append(node)
	else:
		remove_child(node)
		_dispose(node)

func _trim_pool(pool: Array[Node3D], limit: int) -> void:
	while pool.size() > maxi(0, limit):
		var node: Node3D = pool.pop_back()
		remove_child(node)
		_dispose(node)

func _dispose(node: Node) -> void:
	if is_instance_valid(node) and not node.is_queued_for_deletion():
		if node is Node3D:
			node.visible = false
		node.queue_free()
