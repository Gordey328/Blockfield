class_name FallingVoxelCluster
extends Node3D
## Bounded cosmetic collapse. Authoritative cells were already removed by Data.
## One group falls for one real second; no terrain checks or secondary debris.

signal shattered(position: Vector3, block_count: int, reason: String)
signal completed

const EXTENSIONS = preload("res://presentation/openspades_extensions.gd")
const FALL_GRAVITY: float = 4.0
const ROTATION_RATE: float = 1.4
const FALL_LIFETIME: float = 1.0
const MAX_RENDERED_CELLS: int = 64
const FALL_AXIS: Vector3 = Vector3(0.7071067811865476, 0.0, 0.7071067811865476)
enum Phase { FALLING, DEBRIS, COMPLETE }

static var _cube_mesh: BoxMesh
# Compatibility for World resource reload and existing pack-cache diagnostics.
# The simplified falling effect itself never requests a smoke texture.
static var _smoke_frames: Dictionary = {}
static var _texture_generation: int = -1
var phase: int = Phase.FALLING
var elapsed: float = 0.0
var block_count: int = 0
var surface_count: int = 0
var rendered_cells: int = 0
var shatter_reason: String = ""
var precise_physics: bool = false
# Existing World setup assigns these legacy controls. Cosmetic debris is always0.
var fragment_limit: int = 0
var smoke_limit: int = 0
var _center: Vector3 = Vector3.ZERO
var _batch: MultiMeshInstance3D

func setup(_world: Node3D, cells: Array[Vector3i], packed_colors: PackedInt32Array,
		_observer: Vector3, material: Material, _seed_value: int = -1) -> void:
	block_count = cells.size()
	# Keep the exact component pivot/count without retaining/copying its cells,
	# building neighbor dictionaries or generating each cube's surface faces.
	for cell: Vector3i in cells:
		_center += Vector3(cell) + Vector3.ONE * 0.5
	_center /= float(maxi(block_count, 1))
	position = _center
	if cells.is_empty() or packed_colors.size() != block_count:
		# World connects listeners after setup, so invalid input completes later.
		call_deferred("_finish")
		return
	rendered_cells = mini(block_count, MAX_RENDERED_CELLS)
	# This key is retained for diagnostics; exact surface enumeration is removed.
	surface_count = rendered_cells
	if _cube_mesh == null:
		_cube_mesh = BoxMesh.new()
		_cube_mesh.size = Vector3.ONE
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _cube_mesh
	multimesh.instance_count = rendered_cells
	for sample: int in range(rendered_cells):
		# Even source-index sampling covers the whole supplied component order,
		# including its first/last cells. Only these64 transforms are uploaded.
		var index: int = floori(float(sample) * float(block_count - 1) / float(maxi(rendered_cells - 1, 1)))
		var point: Vector3 = Vector3(cells[index]) + Vector3.ONE * 0.5 - _center
		multimesh.set_instance_transform(sample, Transform3D(Basis.IDENTITY, point))
		var packed: int = packed_colors[index]
		multimesh.set_instance_color(sample, Color(float((packed >> 16) & 255) / 255.0,
			float((packed >> 8) & 255) / 255.0, float(packed & 255) / 255.0))
	_batch = MultiMeshInstance3D.new()
	_batch.multimesh = multimesh
	_batch.material_override = material
	_batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_batch)

func _process(delta: float) -> void:
	step(delta)

func step(delta: float) -> void:
	if phase != Phase.FALLING or not is_finite(delta) or delta <= 0.0:
		return
	elapsed = minf(FALL_LIFETIME, elapsed + delta)
	var elapsed_squared: float = elapsed * elapsed
	# Evaluate from the initial pose, so hitches and frame subdivision agree.
	transform = Transform3D(Basis(FALL_AXIS, 0.5 * ROTATION_RATE * elapsed_squared),
		_center + Vector3.DOWN * (0.5 * FALL_GRAVITY * elapsed_squared))
	if elapsed >= FALL_LIFETIME:
		_finish()

func _finish() -> void:
	if phase == Phase.COMPLETE:
		return
	phase = Phase.COMPLETE
	shatter_reason = "simplified"
	shattered.emit(position, block_count, shatter_reason)
	completed.emit()
	queue_free()

func get_effect_stats() -> Dictionary:
	return {"phase": phase, "blocks": block_count, "surface_blocks": surface_count,
		"rendered_cells": rendered_cells, "render_limit": MAX_RENDERED_CELLS,
		"fragments": 0, "smoke": 0, "precise_physics": false, "reason": shatter_reason}

static func clear_texture_cache() -> void:
	_smoke_frames.clear()
	_texture_generation = EXTENSIONS.get_generation()

static func _smoke_frame(frame: int) -> Texture2D:
	var index: int = frame % 180
	if _texture_generation != EXTENSIONS.get_generation():
		clear_texture_cache()
	if not _smoke_frames.has(index):
		_smoke_frames[index] = EXTENSIONS.texture("res://assets/openspades/images/Textures/Smoke1/%03d.png" % index)
	return _smoke_frames[index]
