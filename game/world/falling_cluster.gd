class_name FallingVoxelCluster
extends Node3D
## Cosmetic OpenSpades FallingBlock: never writes its cubes back into the map.

signal shattered(position: Vector3, block_count: int, reason: String)
signal completed

const CHUNK = preload("res://world/voxel_chunk.gd")
const EXTENSIONS = preload("res://presentation/openspades_extensions.gd")
const FALL_GRAVITY := 4.0
const ROTATION_RATE := 1.4
const FALL_LIFETIME := 1.0
const FRAGMENT_GRAVITY := 32.0 * 0.6
const FRAGMENTS_PER_SURFACE := 6
const FRAGMENT_LIFETIME := 2.0
enum Phase { FALLING, DEBRIS, COMPLETE }

static var _smoke_frames: Dictionary = {}
static var _texture_generation := -1
var phase: int = Phase.FALLING
var elapsed := 0.0
var debris_elapsed := 0.0
var block_count := 0
var surface_count := 0
var shatter_reason := ""
var precise_physics := false
var fragment_limit := 4096
var smoke_limit := 1024
var _world: Node3D
var _observer := Vector3.ZERO
var _mesh: MeshInstance3D
var _cells: Array[Vector3i] = []
var _colors := PackedColorArray()
var _surface_indices := PackedInt32Array()
var _center := Vector3.ZERO
var _last_transform := Transform3D.IDENTITY
var _fragments: MultiMeshInstance3D
var _smoke: MultiMeshInstance3D
var _smoke_material: StandardMaterial3D
var _fragment_positions := PackedVector3Array()
var _fragment_velocities := PackedVector3Array()
var _fragment_colors := PackedColorArray()
var _fragment_radii := PackedFloat32Array()
var _fragment_angles := PackedFloat32Array()
var _fragment_alive := PackedByteArray()
var _smoke_positions := PackedVector3Array()
var _smoke_velocities := PackedVector3Array()
var _smoke_colors := PackedColorArray()
var _smoke_lifetimes := PackedFloat32Array()
var _smoke_angles := PackedFloat32Array()
var _random := RandomNumberGenerator.new()

func setup(world: Node3D, cells: Array[Vector3i], packed_colors: PackedInt32Array, observer: Vector3, material: Material, seed_value: int = -1) -> void:
	_world = world
	_cells = cells.duplicate()
	block_count = cells.size()
	_observer = observer
	if seed_value >= 0:
		_random.seed = seed_value
	else:
		_random.randomize()
	var lookup: Dictionary = {}
	for i in range(cells.size()):
		_center += Vector3(cells[i]) + Vector3.ONE * 0.5
		lookup[cells[i]] = true
		var packed := packed_colors[i]
		_colors.append(Color(float((packed >> 16) & 255) / 255.0, float((packed >> 8) & 255) / 255.0, float(packed & 255) / 255.0))
	_center /= float(maxi(block_count, 1))
	position = _center
	_last_transform = transform
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for i in range(cells.size()):
		var surface := false
		for face in range(6):
			if lookup.has(cells[i] + CHUNK.DIRECTIONS[face]):
				continue
			surface = true
			for corner in CHUNK.TRIANGLES:
				vertices.append(Vector3(cells[i]) - _center + CHUNK.CORNERS[face][corner])
				normals.append(Vector3(CHUNK.DIRECTIONS[face]))
				colors.append(_colors[i])
		if surface:
			_surface_indices.append(i)
	surface_count = _surface_indices.size()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = mesh
	add_child(_mesh)

func _process(delta: float) -> void:
	step(delta)

func step(delta: float) -> void:
	if phase == Phase.FALLING:
		elapsed += delta
		if elapsed > FALL_LIFETIME or _world.clip_box(position):
			shatter_reason = "timeout" if elapsed > FALL_LIFETIME else "collision"
			_shatter()
			return
		_last_transform = transform
		# Native matrix = matrix * rotation, then world-space translation.
		basis = basis * Basis(Vector3(1, 0, 1).normalized(), elapsed * ROTATION_RATE * delta)
		position.y -= elapsed * FALL_GRAVITY * delta
	elif phase == Phase.DEBRIS:
		_update_debris(delta)

func _shatter() -> void:
	phase = Phase.DEBRIS
	_mesh.visible = false
	var impact_position := position
	_observer = _world.get_effects_observer()
	var distance := impact_position.distance_to(_observer)
	precise_physics = distance < 16.0 and block_count < 1000
	shattered.emit(impact_position, block_count, shatter_reason)
	if distance > 170.0:
		_finish()
		return
	var fragment_count := mini(surface_count * FRAGMENTS_PER_SURFACE, fragment_limit)
	var smoke_count := mini(surface_count, smoke_limit)
	# From this point the batch uses world-axis trajectories, independent of model rotation.
	transform = Transform3D.IDENTITY
	_fragments = _create_batch(fragment_count, false, impact_position)
	_smoke = _create_batch(smoke_count, true, impact_position)
	for sample in range(smoke_count):
		var surface_index: int = _surface_indices[sample * surface_count / maxi(smoke_count, 1)]
		var point := _last_transform * (Vector3(_cells[surface_index]) + Vector3.ONE * 0.5 - _center)
		_smoke_positions.append(point)
		_smoke_velocities.append(_random_velocity(0.2))
		_smoke_colors.append(_colors[surface_index])
		_smoke_lifetimes.append(1.0 + _random.randf() * 0.5)
		_smoke_angles.append(_random.randf() * TAU)
	for particle in range(fragment_count):
		var surface_index: int = _surface_indices[particle * surface_count / maxi(fragment_count, 1)]
		var point := _last_transform * (Vector3(_cells[surface_index]) + Vector3.ONE * 0.5 - _center)
		_fragment_positions.append(point)
		_fragment_velocities.append(_random_velocity(13.0))
		_fragment_colors.append(_colors[surface_index])
		_fragment_radii.append(0.35 + _random.randf() * _random.randf() * 0.1)
		_fragment_angles.append(_random.randf() * TAU)
		_fragment_alive.append(1)
	_draw_debris()

func _create_batch(count: int, smoke: bool, origin: Vector3) -> MultiMeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Batch transforms face the camera explicitly so source random sprite angle
	# and radius survive material billboarding's basis replacement.
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if smoke:
		_smoke_material = material
		material.albedo_texture = _smoke_frame(0)
	else:
		material.albedo_texture = EXTENSIONS.texture("res://assets/openspades/images/Gfx/White.png")
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 2.0
	quad.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = count
	multimesh.custom_aabb = AABB(origin - Vector3(45, 90, 45), Vector3(90, 130, 90))
	var batch := MultiMeshInstance3D.new()
	batch.multimesh = multimesh
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(batch)
	return batch

static func clear_texture_cache() -> void:
	_smoke_frames.clear()
	_texture_generation = EXTENSIONS.get_generation()

static func _smoke_frame(frame: int) -> Texture2D:
	var index := frame % 180
	if _texture_generation != EXTENSIONS.get_generation():
		clear_texture_cache()
	if not _smoke_frames.has(index):
		_smoke_frames[index] = EXTENSIONS.texture("res://assets/openspades/images/Textures/Smoke1/%03d.png" % index)
	return _smoke_frames[index]

func _random_velocity(scale_value: float) -> Vector3:
	return Vector3(_random.randf() - _random.randf(), _random.randf() - _random.randf(), _random.randf() - _random.randf()) * scale_value

func _update_debris(delta: float) -> void:
	debris_elapsed += delta
	if debris_elapsed > FRAGMENT_LIFETIME:
		_finish()
		return
	for i in range(_fragment_positions.size()):
		if _fragment_alive[i] == 0:
			continue
		var previous := _fragment_positions[i]
		var next := previous + _fragment_velocities[i] * delta
		_fragment_velocities[i].y -= FRAGMENT_GRAVITY * delta
		if _world.clip_world(next):
			if not precise_physics:
				_fragment_alive[i] = 0
			else:
				_bounce_fragment(i, previous, next)
				next = previous
		_fragment_positions[i] = next
	for i in range(_smoke_positions.size()):
		_smoke_positions[i] += _smoke_velocities[i] * delta
	_draw_debris()

func _bounce_fragment(index: int, previous: Vector3, next: Vector3) -> void:
	var a := Vector3i(previous.floor())
	var b := Vector3i(next.floor())
	var velocity := _fragment_velocities[index]
	if b.y != a.y and ((a.x == b.x and a.z == b.z) or not _world.clip_world(Vector3(b.x, a.y, b.z))):
		velocity.y = -velocity.y
	elif b.x != a.x and ((a.y == b.y and a.z == b.z) or not _world.clip_world(Vector3(a.x, b.y, b.z))):
		velocity.x = -velocity.x
	elif b.z != a.z and ((a.x == b.x and a.y == b.y) or not _world.clip_world(Vector3(b.x, b.y, a.z))):
		velocity.z = -velocity.z
	_fragment_velocities[index] = velocity * 0.36

func _draw_debris() -> void:
	var fade := clampf(FRAGMENT_LIFETIME - debris_elapsed, 0.0, 1.0)
	var camera := get_viewport().get_camera_3d()
	var billboard_basis := camera.global_basis if camera != null else Basis.IDENTITY
	for i in range(_fragment_positions.size()):
		var radius := _fragment_radii[i] if _fragment_alive[i] else 0.0
		var sprite_basis := billboard_basis * Basis(Vector3.FORWARD, _fragment_angles[i])
		_fragments.multimesh.set_instance_transform(i, Transform3D(sprite_basis.scaled(Vector3.ONE * radius), _fragment_positions[i]))
		var color := _fragment_colors[i]
		color.a = fade
		_fragments.multimesh.set_instance_color(i, color)
	_smoke_material.albedo_texture = _smoke_frame(floori(debris_elapsed * 70.0))
	for i in range(_smoke_positions.size()):
		var remaining := _smoke_lifetimes[i] - debris_elapsed
		var radius := 1.0 + 0.5 * debris_elapsed if remaining > 0.0 else 0.0
		var sprite_basis := billboard_basis * Basis(Vector3.FORWARD, _smoke_angles[i])
		_smoke.multimesh.set_instance_transform(i, Transform3D(sprite_basis.scaled(Vector3.ONE * radius), _smoke_positions[i]))
		var color := _smoke_colors[i]
		color.a = clampf(remaining, 0.0, 1.0)
		_smoke.multimesh.set_instance_color(i, color)

func _finish() -> void:
	phase = Phase.COMPLETE
	completed.emit()
	queue_free()

func get_effect_stats() -> Dictionary:
	return {"phase": phase, "blocks": block_count, "surface_blocks": surface_count, "fragments": _fragment_positions.size(), "smoke": _smoke_positions.size(), "precise_physics": precise_physics, "reason": shatter_reason}
