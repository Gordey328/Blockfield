class_name OpenSpadesEffects
extends Node3D
## Source: Client_LocalEnts.cpp, ParticleSpriteEntity.cpp, SmokeSpriteEntity.cpp,
## GunCasing.cpp, Tracer.cpp and Client_Scene.cpp in OpenSpades v0.1.3.
## World positions use Godot Y-up. The manager never edits gameplay blocks.

signal casing_contact(position: Vector3, water: bool, weapon: int)

const IMAGE_ROOT := "res://assets/openspades/images/"
const SOUND_ROOT := "res://assets/openspades/sounds/Weapons/"
const WEAPONS := ["Rifle", "SMG", "Shotgun"]
const EXTENSIONS = preload("res://presentation/openspades_extensions.gd")
const VOXEL_WORLD = preload("res://world/voxel_world.gd")
const TRACER_SPEEDS := [350.0, 180.0, 250.0] # Native velocities * 0.5 visual slowdown.
const IGNORE := 0
const DELETE := 1
const BOUNCE := 2

var quality := 2
var blood_enabled := true
var audio_enabled := true
var shake_level := 2
var max_particles := 512
var max_casings := 48
var max_tracers := 64
var max_lights := 8
var world: Node3D
var camera: Camera3D
var rng := RandomNumberGenerator.new()
var _particles: Array[Dictionary] = []
var _casings: Array[Dictionary] = []
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
	_trim_pool(_particle_pool, max_particles - _particles.size())
	_trim_pool(_rifle_casing_pool, max_casings)
	_trim_pool(_smg_casing_pool, max_casings)
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
	while _particle_pool.size() + _particles.size() < max_particles:
		_release(_new_particle(), _particle_pool, max_particles)
	for weapon in range(2):
		var pool := _casing_pool(weapon)
		var active := 0
		for entry in _casings:
			if entry.weapon == weapon:
				active += 1
		while pool.size() + active < max_casings:
			_release(_new_casing(weapon), pool, max_casings)
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
	for pool in [_particle_pool, _rifle_casing_pool, _smg_casing_pool, _tracer_pool, _light_pool]:
		for node: Node3D in pool:
			remove_child(node)
			_dispose(node)
		pool.clear()
	_textures.clear()
	_smoke_frames.clear()
	_tracer_material = null
	_tracer_mesh = null
	prewarm()

func stats() -> Dictionary:
	return {"particles": _particles.size(), "casings": _casings.size(),
		"tracers": _tracers.size(), "lights": _lights.size(), "audio": _sounds.size(),
		"pooled_particles": _particle_pool.size(),
		"pooled_casings": _rifle_casing_pool.size() + _smg_casing_pool.size(),
		"pooled_tracers": _tracer_pool.size(), "pooled_lights": _light_pool.size(),
		"created_nodes": _created_nodes, "batched_particles": _fragment_count,
		"fragment_substeps": _fragment_substeps,
		"fragment_position_writes": _fragment_position_writes,
		"fragment_scale_writes": _fragment_scale_writes,
		"fragment_color_writes": _fragment_color_writes}

func clear() -> void:
	stop_audio()
	for entry in _particles:
		_release(entry.node, _particle_pool, max_particles)
	for entry in _casings:
		_release(entry.node, _casing_pool(entry.weapon), max_casings)
	for entry in _tracers:
		_release(entry.node, _tracer_pool, max_tracers)
	for entry in _lights:
		_release(entry.node, _light_pool, max_lights)
	_particles.clear()
	_casings.clear()
	_tracers.clear()
	_lights.clear()
	_fragment_count = 0
	if _fragment_multimesh != null:
		_fragment_multimesh.visible_instance_count = 0
		_fragment_batch.visible = false
	_trim_pool(_particle_pool, max_particles)
	_trim_pool(_rifle_casing_pool, max_casings)
	_trim_pool(_smg_casing_pool, max_casings)
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
		_spawn(position, _random_vector() * 10.0, Color(0.5, 0.02, 0.04),
			0.1 + _product() * 0.2, 3.0, {"gravity": 0.7})
	if quality < 2:
		return
	for index in range(2):
		_spawn(position, _random_vector() * 0.7, Color(0.7, 0.35, 0.37, 0.6),
			0.5 + _product() * 0.2, 0.2 + rng.randf() * 0.2,
			{"smoke": 2, "fps": 100.0, "damping": 0.8, "growth": 2.0,
			"fade_in": 0.06, "fade_out": 0.2, "collision": IGNORE})
	_spawn(position, _random_vector() * 0.7, Color(0.7, 0.35, 0.37, 0.06),
		0.7 + _product() * 0.2, 0.8 + rng.randf() * 0.4,
		{"smoke": 1, "fps": 40.0, "damping": 0.8, "growth": 2.0,
		"radius_damping": 0.1, "fade_in": 0.06, "collision": IGNORE})

func block_hit(position: Vector3, normal: Vector3, color: Color, water: bool = false) -> void:
	var origin := position + normal * 0.05
	if water:
		water_hit(origin)
		return
	var distance := _distance(origin)
	if quality < 1 or distance > 150.0:
		return
	for index in range(7):
		_spawn(origin, _random_vector() * 7.0, color, 0.2 + _product() * 0.1, 2.0,
			{"gravity": 0.9, "collision": BOUNCE if distance < 16.0 else DELETE})
	if quality < 2:
		return
	if distance < 32.0:
		for index in range(16):
			_spawn(origin, _random_vector() * 12.0, color, 0.1 + _product() * 0.14, 2.0,
				{"gravity": 0.9, "collision": BOUNCE if distance < 16.0 else DELETE})
	var dust := color.lerp(Color.WHITE, 0.2)
	dust.a = 0.2
	for index in range(2):
		_spawn(origin, _random_vector() * 0.7, dust, 0.6 + _product() * 0.2,
			0.3 + rng.randf() * 0.3, {"smoke": 1, "fps": 100.0, "growth": 0.8,
			"fade_in": 0.06, "fade_out": 0.4, "collision": IGNORE})

func block_destroy(position: Vector3, color: Color) -> void:
	# Direct deletions only. Falling connected clusters have world-owned batches.
	if quality < 1 or _distance(position) > 150.0:
		return
	for index in range(8):
		_spawn(position, _random_vector() * 7.0, color, 0.3 + _product() * 0.2,
			2.0, {"gravity": 1.0, "collision": BOUNCE})

func muzzle_fire(position: Vector3, _direction: Vector3, _weapon: int, _local: bool = true) -> void:
	_flash(position, 5.0, 0.045)
	if quality < 1:
		return
	for index in range(2):
		_spawn(position, (_random_vector() + Vector3.UP * 0.25) * 0.3,
			Color(0.8, 0.8, 0.8, 0.3), 0.4, 0.2 + rng.randf() * 0.1,
			{"smoke": 2, "fps": 120.0, "growth": 3.0,
			"radius_damping": 0.0000005, "fade_out": 0.3, "collision": IGNORE})

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
	var bias := Vector3.ZERO
	for axis in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		if _solid(position + axis):
			bias -= axis
	for index in range(4):
		_spawn(position, (_random_vector() + bias * 0.5) * 2.0, Color(0.6, 0.6, 0.6),
			0.6 + _product() * 0.4, 1.8 + rng.randf() * 0.1,
			{"smoke": 2, "fps": 60.0, "growth": 2.0, "radius_damping": 0.2,
			"fade_out": 0.2, "collision": IGNORE})
	for index in range(8):
		var velocity := _random_vector()
		velocity.y *= 0.2
		var life := 0.8 + rng.randf() if quality < 2 else 2.0 + rng.randf() * 5.0
		_spawn(position, velocity * 2.0, Color(0.6, 0.6, 0.6, 0.25),
			1.5 + _product() * 0.8, life,
			{"smoke": 1, "fps": 20.0, "growth": 0.2, "fade_in": 0.1,
			"fade_out": 8.0, "collision": IGNORE})
	for index in range(42):
		var radius := 0.1 + _product() * 0.2
		_spawn(position, (_random_vector() + bias * 0.5) * 20.0, Color(0.01, 0.03, 0),
			radius, 3.5 + rng.randf() * 2.0,
			{"damping": 0.1 + radius * 3.0, "gravity": 1.0, "collision": BOUNCE})
	for index in range(4):
		_spawn(position, (_random_vector() + bias) * 6.0, Color(5, 3.5, 2, 1),
			0.3 + _product() * 0.4, 0.18 + rng.randf() * 0.03,
			{"smoke": 2, "fps": 120.0, "growth": 3.0, "radius_damping": 0.1,
			"fade_out": 0.1, "collision": IGNORE})

func _underwater_explosion(position: Vector3) -> void:
	if quality < 1:
		return
	for index in range(7):
		var velocity := _random_vector()
		velocity.y = rng.randf() * 7.0
		_spawn(position, velocity * 2.5, Color(0.95, 0.95, 0.95, 0.6),
			1.5 + _product() * 0.4, 3.0 + rng.randf() * 0.3,
			{"image": "Textures/WaterExpl.png", "damping": 0.3, "gravity": 0.6,
			"growth": 1.3, "fade_out": 0.6, "collision": IGNORE})
	for index in range(16):
		var velocity := _random_vector()
		velocity.y = rng.randf() * 10.0
		_spawn(position, velocity * 3.5, Color(0.95, 0.95, 0.95, 0.9),
			0.9 + _product() * 0.4, 3.0 + rng.randf() * 0.3,
			{"image": "Textures/Fluid.png", "gravity": 1.0, "growth": 0.7,
			"fade_in": 0.7, "fade_out": 0.6, "collision": IGNORE})
	for index in range(8):
		var velocity := _random_vector()
		velocity.y = rng.randf() * 0.2
		_spawn(position, velocity * 2.0, Color(0.95, 0.95, 0.95, 0.4),
			1.4 + _product() * 0.8, 6.0 + rng.randf() * 5.0,
			{"smoke": 1, "fps": 20.0, "growth": 0.2, "fade_in": 0.1,
			"fade_out": 8.0, "collision": IGNORE})
	for index in range(42):
		var velocity := _random_vector()
		velocity.y = rng.randf() * 3.0
		var radius := 0.1 + _product() * 0.2
		_spawn(position, velocity * 13.0, Color(0.95, 0.95, 0.95), radius,
			3.5 + rng.randf() * 2.0, {"damping": 0.1 + radius * 3.0, "gravity": 1.0})

func water_hit(position: Vector3) -> void:
	if quality < 1 or _distance(position) > 150.0:
		return
	for index in range(2):
		var velocity := _random_vector()
		velocity.y = rng.randf() * 7.0
		_spawn(position, velocity, Color(0.95, 0.95, 0.95, 0.3),
			0.6 + _product() * 0.4, 3.0 + rng.randf() * 0.3,
			{"image": "Textures/WaterExpl.png", "damping": 0.3, "gravity": 0.6,
			"growth": 0.7, "fade_in": 0.1, "fade_out": 0.6, "collision": IGNORE})
	for index in range(6):
		var velocity := _random_vector()
		velocity.y = rng.randf() * 10.0
		_spawn(position, velocity * 2.0, Color(0.95, 0.95, 0.95, 0.9),
			0.6 + _product() * 0.6, 3.0 + rng.randf() * 0.3,
			{"image": "Textures/Fluid.png", "gravity": 1.0, "growth": 0.6,
			"fade_in": rng.randf() * 0.3, "fade_out": 0.6, "collision": IGNORE})

func eject_shell(position: Vector3, front: Vector3, right: Vector3, up: Vector3, weapon: int) -> void:
	# Original source has no shotgun firing ejection (pump ejection is a FIXME).
	_trim_pool(_rifle_casing_pool, max_casings)
	_trim_pool(_smg_casing_pool, max_casings)
	if weapon < 0 or weapon > 1 or _distance(position) > 130.0 or _casings.size() >= max_casings:
		return
	var pool := _casing_pool(weapon)
	var node: Node3D = pool.pop_back() if not pool.is_empty() else _new_casing(weapon)
	node.transform = Transform3D.IDENTITY
	node.visible = true
	node.global_position = position - front * 0.5
	node.global_basis = Basis(right.normalized(), up.normalized(), -front.normalized()).orthonormalized()
	var fly_direction := front * (0.5 if weapon == 0 else -0.2) + right + up * 0.2
	var axis := Vector3.UP.cross(fly_direction).normalized()
	_casings.append({"node": node, "velocity": fly_direction * 10.0, "axis": axis,
		"spin": 40.0, "weapon": weapon, "age": 0.0, "ground_time": -1.0,
		"ground_cell": Vector3i.ZERO, "played": false})

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
	var elapsed := maxf(delta, 0.0)
	var duration := clampf(delta, 0.0, 0.1)
	var steps := maxi(1, ceili(duration * 60.0))
	for entry in _particles:
		entry.frame_age = entry.age
		if entry.batched:
			# Respect external node/manager movement at the frame boundary. White
			# fragments render through the MultiMesh; substeps need no sprite writes.
			entry.frame_position = entry.node.global_position
	for entry in _casings:
		entry.frame_age = entry.age
	var consumed := 0.0
	for step in range(steps):
		var dt := duration / float(steps)
		var frame_elapsed := elapsed if step == steps - 1 else elapsed * float(step + 1) / float(steps)
		var lifetime_dt := frame_elapsed - consumed
		_update_particles(dt, lifetime_dt, frame_elapsed)
		_update_casings(dt, lifetime_dt, frame_elapsed)
		consumed = frame_elapsed
	_sync_fragment_batch()
	_update_tracers(elapsed, elapsed - duration)
	for index in range(_lights.size() - 1, -1, -1):
		var entry: Dictionary = _lights[index]
		entry.life -= elapsed
		if entry.life <= 0:
			_release(entry.node, _light_pool, max_lights)
			_lights.remove_at(index)
	# Collision integration is bounded, but camera vibration must decay in real
	# elapsed time even when a slow frame exceeds the particle step budget.
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
	_trim_pool(_particle_pool, max_particles - _particles.size())
	if _particles.size() >= max_particles:
		return
	var smoke: int = options.get("smoke", 0)
	var image: String = options.get("image", "Gfx/White.png")
	var batched := smoke == 0 and image == "Gfx/White.png"
	var node: Sprite3D = (_particle_pool.pop_back() if not _particle_pool.is_empty() else _new_particle()) as Sprite3D
	node.transform = Transform3D.IDENTITY
	node.texture = _smoke_texture(smoke, 0) if smoke != 0 else _texture(image)
	node.pixel_size = 1.0 / float(node.texture.get_width())
	node.modulate = color
	node.scale = Vector3.ONE * radius * 2.0
	node.rotation.z = rng.randf() * TAU
	node.visible = not batched
	node.global_position = position
	_particles.append({"node": node, "velocity": velocity, "age": 0.0, "life": life,
		"radius": radius, "color": color, "gravity": options.get("gravity", 0.0),
		"damping": options.get("damping", 1.0), "growth": options.get("growth", 0.0),
		"radius_damping": options.get("radius_damping", 1.0),
		"fade_in": options.get("fade_in", 0.0), "fade_out": options.get("fade_out", 1.0),
		"collision": options.get("collision", DELETE), "smoke": smoke,
		"fps": options.get("fps", 60.0), "frame": 0, "batched": batched,
		"frame_position": node.global_position, "frame_color": color})

func _update_particles(delta: float, lifetime_delta: float, frame_elapsed: float) -> void:
	# Only the concrete renderer has the get_block -> Data contract. Custom
	# worlds/subclasses retain their query override. This reference lasts for
	# one synchronous substep; no packed-map storage is copied or retained.
	var collision_data: VoxelData = null
	if is_instance_valid(world) and world.get_script() == VOXEL_WORLD:
		collision_data = (world as VoxelWorld).data
	for index in range(_particles.size() - 1, -1, -1):
		var entry: Dictionary = _particles[index]
		entry.age = entry.frame_age + frame_elapsed
		var smoke: int = entry.smoke
		var frame: int = floori(entry.age * entry.fps) if smoke > 0 else 0
		if entry.age >= entry.life or (smoke == 2 and frame >= 48):
			_release(entry.node, _particle_pool, max_particles)
			_particles.remove_at(index)
			continue
		var node: Sprite3D = entry.node
		if entry.batched:
			_fragment_substeps += 1
		var previous: Vector3 = entry.frame_position if entry.batched else node.global_position
		var velocity: Vector3 = entry.velocity
		var next: Vector3 = previous + velocity * delta
		velocity.y -= 32.0 * entry.gravity * delta
		if entry.collision != IGNORE and _solid(next, collision_data):
			if entry.collision == DELETE:
				_release(node, _particle_pool, max_particles)
				_particles.remove_at(index)
				continue
			velocity = _bounce(previous, next, velocity, collision_data) * 0.36
			next = previous
		if entry.batched:
			entry.frame_position = next
		else:
			node.global_position = next
		var damping: float = entry.damping
		if damping != 1.0:
			velocity *= pow(damping, lifetime_delta)
		entry.velocity = velocity
		var growth: float = entry.growth
		var radius: float = entry.radius
		if growth != 0.0 or radius < 0.0001:
			entry.radius = maxf(0.0001, radius + growth * lifetime_delta)
		if growth != 0.0:
			var radius_damping: float = entry.radius_damping
			if radius_damping != 1.0:
				entry.growth = growth * pow(radius_damping, lifetime_delta)
		if not entry.batched:
			node.scale = Vector3.ONE * entry.radius * 2.0
			node.modulate = _particle_color(entry)
		if smoke > 0:
			frame = frame % (180 if smoke == 1 else 48)
			if frame != entry.frame:
				node.texture = _smoke_texture(smoke, frame)
				entry.frame = frame

func _particle_color(entry: Dictionary) -> Color:
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

func _update_casings(delta: float, lifetime_delta: float, frame_elapsed: float) -> void:
	for index in range(_casings.size() - 1, -1, -1):
		var entry: Dictionary = _casings[index]
		var node: Node3D = entry.node
		entry.age = entry.frame_age + frame_elapsed
		if entry.age > 15.0 or (entry.ground_time >= 0 and (entry.ground_time > 2.0 or not _solid_cell(entry.ground_cell))):
			_release(node, _casing_pool(entry.weapon), max_casings)
			_casings.remove_at(index)
			continue
		if entry.ground_time >= 0:
			entry.ground_time += lifetime_delta
			if entry.ground_time > 1.0:
				node.position.y -= lifetime_delta * 0.2
			continue
		var previous := node.global_position
		var next: Vector3 = previous + entry.velocity * delta
		entry.velocity.y -= 32.0 * delta
		node.rotate_object_local(entry.axis, entry.spin * delta)
		if next.y < _water_level():
			_contact(previous, true, entry.weapon)
			_release(node, _casing_pool(entry.weapon), max_casings)
			_casings.remove_at(index)
			continue
		if _solid(next):
			var ground_hit := next.y < previous.y and floori(next.y) != floori(previous.y)
			if ground_hit and entry.played and entry.velocity.length() < 0.5 + delta * 100.0:
				entry.ground_time = 0.0
				entry.ground_cell = Vector3i(next.floor())
				node.global_position.y = float(entry.ground_cell.y + 1)
				node.rotation.x = PI * 0.5
			elif ground_hit and not entry.played:
				entry.played = true
				_contact(previous, false, entry.weapon)
			entry.velocity = _bounce(previous, next, entry.velocity) * 0.2 + _random_vector() * 0.1
			entry.spin *= 0.2
			entry.axis = _random_vector().normalized()
		else:
			node.global_position = next

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

func _contact(position: Vector3, water: bool, weapon: int) -> void:
	casing_contact.emit(position, water, weapon)
	if not audio_enabled or _distance(position) >= 40.0 or _sounds.size() >= 16:
		return
	var relative: String = WEAPONS[weapon] + ("/ShellWater.ogg" if water else "/ShellDrop%d.ogg" % rng.randi_range(1, 2))
	if audio_service!=null:
		var voice: Node=audio_service.play_spatial("Weapons/"+relative.trim_suffix(".ogg"),position,1.0,.6)
		if voice!=null:voice.pitch_scale=.9+rng.randf()*.2 if water else 1.0
		return
	var stream := EXTENSIONS.sound(SOUND_ROOT + relative)
	if stream == null:
		return
	var node := AudioStreamPlayer3D.new()
	node.stream = stream
	node.unit_size = 0.6
	node.max_distance = 40.0
	node.pitch_scale = 0.9 + rng.randf() * 0.2 if water else 1.0
	add_child(node)
	node.global_position = position
	_sounds.append(node)
	node.finished.connect(func():
		_sounds.erase(node)
		node.stream = null
		_dispose(node), CONNECT_ONE_SHOT)
	node.play()

func _bounce(previous: Vector3, next: Vector3, velocity: Vector3, query: VoxelData = null) -> Vector3:
	var result := velocity
	var before := Vector3i(previous.floor())
	var after := Vector3i(next.floor())
	if before.y != after.y and (before.x == after.x and before.z == after.z or not _solid(Vector3(next.x, previous.y, next.z), query)):
		result.y = -result.y
	elif before.x != after.x and (before.y == after.y and before.z == after.z or not _solid(Vector3(previous.x, next.y, next.z), query)):
		result.x = -result.x
	else:
		result.z = -result.z
	return result

func _solid(position: Vector3, query: VoxelData = null) -> bool:
	return _solid_cell(Vector3i(position.floor()), query)

func _solid_cell(cell: Vector3i, query: VoxelData = null) -> bool:
	if query != null:
		return query.get_block(cell) != 0
	return is_instance_valid(world) and int(world.call("get_block", cell)) != 0

func _water_level() -> float:
	var level = world.get("water_level") if is_instance_valid(world) else null
	return float(level) if level != null else 0.0

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

func _new_casing(weapon: int) -> Node3D:
	var node := Node3D.new()
	var model := OpenSpadesModels.create("Weapons/%s/Casing" % WEAPONS[weapon])
	model.scale = Vector3.ONE * 0.02
	node.add_child(model)
	_register_node(node)
	return node

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
	if _fragment_multimesh.instance_count != maxi(0, max_particles):
		_fragment_multimesh.instance_count = maxi(0, max_particles)
		_fragment_multimesh.visible_instance_count = 0
		_fragment_count = 0
		_fragment_batch.visible = false

func _sync_fragment_batch() -> void:
	_ensure_fragment_batch()
	_fragment_count = 0
	var billboard := camera.global_basis.orthonormalized() if is_instance_valid(camera) else Basis.IDENTITY
	var to_local := _fragment_batch.global_transform.affine_inverse()
	for entry in _particles:
		if entry.batched and _fragment_count < _fragment_multimesh.instance_count:
			# Mirror the final state once, preserving post-update node inspection
			# and inherited transforms while eliminating invisible substep work.
			var node: Sprite3D = entry.node
			entry.frame_color = _particle_color(entry)
			node.global_position = entry.frame_position
			_fragment_position_writes += 1
			var target_scale: Vector3 = Vector3.ONE * entry.radius * 2.0
			if node.scale != target_scale:
				node.scale = target_scale
				_fragment_scale_writes += 1
			if node.modulate != entry.frame_color:
				node.modulate = entry.frame_color
				_fragment_color_writes += 1
			_write_fragment(_fragment_count, entry, billboard, to_local)
			_fragment_count += 1
	_fragment_multimesh.visible_instance_count = _fragment_count
	_fragment_batch.visible = _fragment_count > 0

func _write_fragment(index: int, entry: Dictionary, billboard: Basis, to_local: Transform3D) -> void:
	var node: Sprite3D = entry.node
	# Match a camera-facing Sprite3D, including its random in-plane spin and
	# inherited scale. MultiMesh transforms are local to the manager's batch.
	var facing := billboard * Basis(Vector3.BACK, node.rotation.z) * Basis.from_scale(node.global_basis.get_scale())
	var pose := Transform3D(facing, node.global_position)
	var local_pose := to_local * pose
	_fragment_multimesh.set_instance_transform(index, local_pose)
	_fragment_multimesh.set_instance_color(index, node.modulate)

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
