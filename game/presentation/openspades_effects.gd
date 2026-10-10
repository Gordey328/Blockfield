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
var _textures: Dictionary = {}
var _sounds: Array[AudioStreamPlayer3D] = []
var _tracer_material: StandardMaterial3D
var _tracer_mesh: QuadMesh
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

func _process(delta: float) -> void:
	update_effects(delta)

func _exit_tree() -> void:
	stop_audio()

func reload_resources() -> void:
	clear()
	_textures.clear()
	_tracer_material = null
	_tracer_mesh = null

func stats() -> Dictionary:
	return {"particles": _particles.size(), "casings": _casings.size(),
		"tracers": _tracers.size(), "lights": _lights.size(), "audio": _sounds.size()}

func clear() -> void:
	stop_audio()
	for collection in [_particles, _casings, _tracers, _lights]:
		for entry: Dictionary in collection:
			_dispose(entry.node)
		collection.clear()
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
	kick_camera((1.5 if underwater else 2.0) / (distance + 5.0))
	if distance > 170.0:
		return
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
	if weapon < 0 or weapon > 1 or _distance(position) > 130.0 or _casings.size() >= max_casings:
		return
	var node := Node3D.new()
	var model := OpenSpadesModels.create("Weapons/%s/Casing" % WEAPONS[weapon])
	model.scale = Vector3.ONE * 0.02
	node.add_child(model)
	add_child(node)
	node.global_position = position - front * 0.5
	node.global_basis = Basis(right.normalized(), up.normalized(), -front.normalized()).orthonormalized()
	var fly_direction := front * (0.5 if weapon == 0 else -0.2) + right + up * 0.2
	var axis := Vector3.UP.cross(fly_direction).normalized()
	_casings.append({"node": node, "velocity": fly_direction * 10.0, "axis": axis,
		"spin": 40.0, "weapon": weapon, "age": 0.0, "ground_time": -1.0,
		"ground_cell": Vector3i.ZERO, "played": false})

func tracer(origin: Vector3, end: Vector3, weapon: int, local_first_person: bool = false) -> void:
	if local_first_person or _tracers.size() >= max_tracers or origin.distance_to(end) < 0.001:
		return
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
	var node := MeshInstance3D.new()
	node.mesh = _tracer_mesh
	node.material_override = _tracer_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	var speed: float = TRACER_SPEEDS[clampi(weapon, 0, 2)]
	_tracers.append({"node": node, "origin": origin, "direction": origin.direction_to(end),
		"distance": -speed / 30.0 + rng.randf() / 30.0, "length": origin.distance_to(end),
		"speed": speed, "visible_length": speed / 30.0, "first": true})

func update_effects(delta: float) -> void:
	var duration := clampf(delta, 0.0, 0.1)
	var steps := maxi(1, ceili(duration * 60.0))
	for step in range(steps):
		var dt := duration / float(steps)
		_update_particles(dt)
		_update_casings(dt)
	_update_tracers(duration)
	for index in range(_lights.size() - 1, -1, -1):
		var entry: Dictionary = _lights[index]
		entry.life -= duration
		if entry.life <= 0:
			_dispose(entry.node)
			_lights.remove_at(index)
	_time += duration
	_fast_shake = maxf(0.0, _fast_shake - duration)
	_slow_shake = maxf(0.0, _slow_shake - duration)
	_camera_rotation = Vector3.ZERO
	if shake_level >= 1:
		var intensity := minf(_fast_shake * 10.0, 1.0)
		_camera_rotation = _random_vector() * Vector3(0.1, 0.1, 0.2) * intensity
	if shake_level >= 2:
		var intensity := pow(minf(_slow_shake * 4.0, 1.0), 2.0)
		_camera_rotation += Vector3(_noise.get_noise_1d(_time * 12.0),
			_noise.get_noise_1d(_time * 11.0 + 31.0), _noise.get_noise_1d(_time * 8.0 + 61.0)) * Vector3(0.1, 0.1, 0.2) * intensity

func _spawn(position: Vector3, velocity: Vector3, color: Color, radius: float, life: float, options: Dictionary = {}) -> void:
	if _particles.size() >= max_particles:
		return
	var smoke: int = options.get("smoke", 0)
	var image: String = options.get("image", "Gfx/White.png")
	if smoke != 0:
		image = "Textures/Smoke%d/000.png" % smoke
	var node := Sprite3D.new()
	node.texture = _texture(image)
	node.pixel_size = 1.0 / float(node.texture.get_width())
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.shaded = false
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	node.modulate = color
	node.scale = Vector3.ONE * radius * 2.0
	node.rotation.z = rng.randf() * TAU
	add_child(node)
	node.global_position = position
	_particles.append({"node": node, "velocity": velocity, "age": 0.0, "life": life,
		"radius": radius, "color": color, "gravity": options.get("gravity", 0.0),
		"damping": options.get("damping", 1.0), "growth": options.get("growth", 0.0),
		"radius_damping": options.get("radius_damping", 1.0),
		"fade_in": options.get("fade_in", 0.0), "fade_out": options.get("fade_out", 1.0),
		"collision": options.get("collision", DELETE), "smoke": smoke,
		"fps": options.get("fps", 60.0), "frame": 0})

func _update_particles(delta: float) -> void:
	for index in range(_particles.size() - 1, -1, -1):
		var entry: Dictionary = _particles[index]
		entry.age += delta
		var frame: int = floori(entry.age * entry.fps)
		if entry.age >= entry.life or (entry.smoke == 2 and frame >= 48):
			_dispose(entry.node)
			_particles.remove_at(index)
			continue
		var node: Sprite3D = entry.node
		var previous := node.global_position
		var next: Vector3 = previous + entry.velocity * delta
		entry.velocity.y -= 32.0 * entry.gravity * delta
		if entry.collision != IGNORE and _solid(next):
			if entry.collision == DELETE:
				_dispose(node)
				_particles.remove_at(index)
				continue
			entry.velocity = _bounce(previous, next, entry.velocity) * 0.36
			next = previous
		node.global_position = next
		entry.velocity *= pow(entry.damping, delta)
		entry.radius = maxf(0.0001, entry.radius + entry.growth * delta)
		entry.growth *= pow(entry.radius_damping, delta)
		node.scale = Vector3.ONE * entry.radius * 2.0
		var fade := 1.0
		if entry.fade_in > 0.0:
			fade *= minf(entry.age / entry.fade_in, 1.0)
		if entry.fade_out > 0.0:
			fade *= minf((entry.life - entry.age) / entry.fade_out, 1.0)
		var color: Color = entry.color
		color.a *= clampf(fade, 0.0, 1.0)
		node.modulate = color
		if entry.smoke > 0:
			frame = frame % (180 if entry.smoke == 1 else 48)
			if frame != entry.frame:
				node.texture = _texture("Textures/Smoke%d/%03d.png" % [entry.smoke, frame])
				entry.frame = frame

func _update_casings(delta: float) -> void:
	for index in range(_casings.size() - 1, -1, -1):
		var entry: Dictionary = _casings[index]
		var node: Node3D = entry.node
		entry.age += delta
		if entry.age > 15.0 or (entry.ground_time >= 0 and (entry.ground_time > 2.0 or not _solid_cell(entry.ground_cell))):
			_dispose(node)
			_casings.remove_at(index)
			continue
		if entry.ground_time >= 0:
			entry.ground_time += delta
			if entry.ground_time > 1.0:
				node.position.y -= delta * 0.2
			continue
		var previous := node.global_position
		var next: Vector3 = previous + entry.velocity * delta
		entry.velocity.y -= 32.0 * delta
		node.rotate_object_local(entry.axis, entry.spin * delta)
		if next.y < _water_level():
			_contact(previous, true, entry.weapon)
			_dispose(node)
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

func _update_tracers(delta: float) -> void:
	for index in range(_tracers.size() - 1, -1, -1):
		var entry: Dictionary = _tracers[index]
		if not entry.first:
			entry.distance += entry.speed * delta
		entry.first = false
		if entry.distance > entry.length:
			_dispose(entry.node)
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
	if _lights.size() >= max_lights:
		return
	var node := OmniLight3D.new()
	node.omni_range = radius
	node.light_color = Color(1.0, 1.6 / 3.0, 0.5 / 3.0)
	node.light_energy = 3.0
	node.shadow_enabled = false
	add_child(node)
	node.global_position = position
	_lights.append({"node": node, "life": life})

func _contact(position: Vector3, water: bool, weapon: int) -> void:
	casing_contact.emit(position, water, weapon)
	if not audio_enabled or _distance(position) >= 40.0 or _sounds.size() >= 16:
		return
	var relative: String = WEAPONS[weapon] + ("/ShellWater.ogg" if water else "/ShellDrop%d.ogg" % rng.randi_range(1, 2))
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

func _bounce(previous: Vector3, next: Vector3, velocity: Vector3) -> Vector3:
	var result := velocity
	var before := Vector3i(previous.floor())
	var after := Vector3i(next.floor())
	if before.y != after.y and (before.x == after.x and before.z == after.z or not _solid(Vector3(next.x, previous.y, next.z))):
		result.y = -result.y
	elif before.x != after.x and (before.y == after.y and before.z == after.z or not _solid(Vector3(previous.x, next.y, next.z))):
		result.x = -result.x
	else:
		result.z = -result.z
	return result

func _solid(position: Vector3) -> bool:
	return _solid_cell(Vector3i(position.floor()))

func _solid_cell(cell: Vector3i) -> bool:
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

func _dispose(node: Node) -> void:
	if is_instance_valid(node) and not node.is_queued_for_deletion():
		if node is Node3D:
			node.visible = false
		node.queue_free()
