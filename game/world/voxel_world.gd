class_name VoxelWorld
extends Node3D
## Packed voxel world. Coordinate axes: x east, y up, z south. One cube = 1 m.
## Empty blocks are 0; all solid colors use 0x01RRGGBB (black is 0x01000000).

signal blocks_changed(changes: Array)
signal map_transaction_committed(transaction: Dictionary)
signal map_loaded(map_name: String)
signal falling_cluster_created(cluster: Node3D)
signal falling_cluster_finished(position: Vector3, block_count: int, reason: String)

const CHUNK_SIZE := 16
const DIRECTIONS: Array[Vector3i] = [Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK, Vector3i.UP]
const VOXEL_DATA = preload("res://world/voxel_data.gd")
const VXL_JOBS = preload("res://world/vxl_reader.gd")
const CHUNK_SCRIPT = preload("res://world/voxel_chunk.gd")
const FALLING_CLUSTER = preload("res://world/falling_cluster.gd")
const WATER_SHADER = preload("res://world/water.gdshader")
const TERRAIN_SHADER = preload("res://world/terrain.gdshader")
const AO = preload("res://world/voxel_ao.gd")
const WAVE_FIELD = preload("res://world/spectral_wave.gd")
const IRRADIANCE = preload("res://world/voxel_irradiance.gd")
const REFLECTION = preload("res://world/planar_reflection.gd")

var data: VOXEL_DATA = VOXEL_DATA.new()
var dimensions: Vector3i:
	get:
		return data.dimensions
	set(value):
		data.dimensions = value
var map_name := "Blockfield Test Grounds"
var render_radius := 4
var rebuild_budget := 3
var rebuild_time_budget_ms := 4.0
var rebuild_profiling_enabled := false
var lighting_enabled := true
var ambient_occlusion_enabled := true
var irradiance_enabled := false
var _irradiance: RefCounted
var _irradiance_light := Vector3.ONE
var water_level: float:
	get:
		return data.water_level
	set(value):
		data.water_level = value
var wade_origin_level: float:
	get:
		return data.wade_origin_level
	set(value):
		data.wade_origin_level = value
var water_enabled := true
var water_waves_enabled := true
var water_refraction_enabled := true
var water_reflections_enabled := false
var water_fog_enabled := true
var _reflection_camera: Camera3D
var _reflection: Node
var _reflection_size := Vector2i(320, 240)
var _reflection_frequency := 20.0
var _reflection_geometry_budget := 768
var visual_effects_enabled := true
var max_active_clusters := 24
var fragment_limit_per_cluster := 4096
var smoke_limit_per_cluster := 1024
var _blocks: PackedInt32Array:
	# Legacy renderer/tests alias; bulk bootstrap writes go through VoxelData.
	get:
		return data.blocks
	set(value):
		data.blocks = value
var _chunks: Dictionary = {}
var _dirty: Dictionary = {}
var _collision_dirty: Dictionary = {}
var _geometry_dirty: Dictionary[Vector3i, bool] = {}
var _color_dirty: Dictionary[Vector3i, Dictionary] = {}
var _active_chunk: VoxelChunk
var _active_key := Vector3i(-1000, -1000, -1000)
var _stage_cpu_usec := PackedInt64Array([0, 0, 0, 0])
var _stage_units := PackedInt64Array([0, 0, 0, 0])
var _rebuild_stats: Dictionary = {"mesh_builds": 0, "collision_builds": 0, "color_updates": 0,
	"color_vertices": 0, "color_upload_bytes": 0, "build_cancellations": 0,
	"last_frame_usec": 0, "max_frame_usec": 0, "max_step_usec": 0,
	"last_publish_usec": 0, "max_publish_usec": 0}
var _damaged_blocks: Dictionary[Vector3i, bool] = {}
var _streaming := false
var _view_chunk := Vector3i(-1000, 0, -1000)
var _spawn := Vector3(48.5, 5.0, 70.5)
var _material: ShaderMaterial
var _falling_clusters: Array[Node3D] = []
var _effects_observer := Vector3(48.5, 5.0, 70.5)
var _water_mesh: MeshInstance3D
var _wave_field: Node
var _water_image: Image
var _water_cursor := 0
var _water_dirty: Dictionary = {}
var _water_dirty_queue: Array[int] = []
var _water_dirty_cursor := 0
var _water_fog_color := Color(0.70, 0.78, 0.80)
var _water_fog_distance := 64.0
var _topdown_image: Image
var _topdown_heights := PackedInt32Array()
var _topdown_dirty: Dictionary = {}
var _topdown_dirty_queue: Array[int] = []
var _topdown_dirty_cursor := 0
var _topdown_cursor := 0
var _topdown_revision := 0
var _topdown_progressive := false
var _preparation_turn := false
var _topdown_initial_turn := false
var _vxl_operation_token: int = 0
var _vxl_active_job: RefCounted
var _vxl_job_stats: Dictionary = {"active": false, "kind": "", "progress": 0.0, "error": OK, "cancelled": false}

func _ready() -> void:
	_ensure_material()
	if _blocks.is_empty():
		generate_lab()

func _exit_tree() -> void:
	cancel_vxl_jobs()
	_cancel_active_build()

func _process(_delta: float) -> void:
	process_rebuild_work(0, int(rebuild_time_budget_ms * 1000.0))
	if irradiance_enabled:
		_ensure_irradiance()
		_irradiance.update()
	if _water_image != null or _topdown_progressive:
		advance_visual_preparation()

static func pack_color(color: Color) -> int:
	return 0x01000000 | (clampi(roundi(color.r * 255.0), 0, 255) << 16) | (clampi(roundi(color.g * 255.0), 0, 255) << 8) | clampi(roundi(color.b * 255.0), 0, 255)

static func block_color(packed: int) -> Color:
	return Color(float((packed >> 16) & 255) / 255.0, float((packed >> 8) & 255) / 255.0, float(packed & 255) / 255.0, 1.0)

func _index(cell: Vector3i) -> int:
	return data.index(cell)

func is_in_bounds(cell: Vector3i) -> bool:
	return data.is_in_bounds(cell)

func get_block(cell: Vector3i) -> int:
	return data.get_block(cell)

func set_block_damaged(cell: Vector3i, damaged: bool) -> void:
	# Damage is a presentation state; authoritative RGB/occupancy and map history
	# remain unchanged. Health persists until an explicit edit/reset; no timer.
	if damaged and get_block(cell) == 0:
		return
	if damaged == _damaged_blocks.has(cell):
		return
	if damaged:
		_damaged_blocks[cell] = true
	else:
		_damaged_blocks.erase(cell)
	# Only this cell's colors change. Neither AO neighbors nor collision change.
	_queue_color_update(cell)

func is_block_damaged(cell: Vector3i) -> bool:
	return _damaged_blocks.has(cell)

func clear_block_damage() -> void:
	for cell: Vector3i in _damaged_blocks:
		_queue_color_update(cell)
	_damaged_blocks.clear()

func get_render_color(cell: Vector3i, packed: int) -> Color:
	# GLMapChunk halves each byte with an integer shift, including odd RGB values.
	var rgb: int = ((packed & 0xfefefe) >> 1) if _damaged_blocks.has(cell) else packed
	return block_color(rgb)

func clip_box(position: Vector3) -> bool:
	return data.clip_box(position)

func clip_world(position: Vector3) -> bool:
	return data.clip_world(position)

func is_water_floor(cell: Vector3i) -> bool:
	return water_enabled and cell.y == 0 and get_block(cell + Vector3i.UP) == 0

func set_block(cell: Vector3i, color: int) -> void:
	_present_transaction(data.set_block(cell, color))

func remove_blocks(cells: Array[Vector3i], protect_lower_layer: bool = false) -> void:
	_present_transaction(data.remove_blocks(cells, protect_lower_layer))

func apply_map_transaction(transaction: Dictionary) -> Dictionary:
	var result: Dictionary = data.apply_transaction(transaction)
	_present_transaction(result)
	return result

func _present_transaction(transaction: Dictionary) -> void:
	# Authority has already atomically committed every block, including collapse.
	# This adapter only invalidates cached presentation and creates cosmetic groups.
	if not transaction.ok or not transaction.changed:
		return
	var changes: Array = []
	for change: Dictionary in transaction.changes:
		var cell: Vector3i = change.cell
		_damaged_blocks.erase(cell)
		if _irradiance != null:
			_irradiance.invalidate(cell)
		if _topdown_image != null:
			var column := cell.x + dimensions.x * cell.z
			var top := _topdown_heights[column]
			# Unfilled columns read the newest authoritative state when reached.
			if column < _topdown_cursor and (cell.y == top or (change.after != 0 and cell.y > top)):
				if not _topdown_dirty.has(column):
					_topdown_dirty_queue.append(column)
				_topdown_dirty[column] = maxi(cell.y, int(_topdown_dirty.get(column, top)))
		if _water_image != null and cell.y == 0:
			var column := cell.x + dimensions.x * cell.z
			if column < _water_cursor:
				if not _water_dirty.has(column):
					_water_dirty_queue.append(column)
				_water_dirty[column] = true
		changes.append({"cell": cell, "before": change.before, "after": change.after, "collapsed": change.flags == 1})
		_mark_dirty(cell, (change.before == 0) != (change.after == 0))
	for group: Dictionary in transaction.collapse_groups:
		_spawn_falling_cluster(group.cells, group.colors)
	blocks_changed.emit(changes)
	map_transaction_committed.emit(transaction)

func _mark_dirty(cell: Vector3i, geometry_changed: bool = true) -> void:
	if not geometry_changed:
		_queue_color_update(cell)
		return
	# AO uses the eight neighbors on the exterior face plane. An edit at a
	# chunk edge/corner must also rebuild diagonal neighboring chunks.
	var native := dimensions == Vector3i(512, 64, 512)
	for z in range(cell.z - 1, cell.z + 2):
		for x in range(cell.x - 1, cell.x + 2):
			for y in range(cell.y - 1, cell.y + 2):
				var neighbor := Vector3i(posmod(x, dimensions.x) if native else x, y, posmod(z, dimensions.z) if native else z)
				if is_in_bounds(neighbor):
					_queue_geometry_update(_chunk_of(neighbor))
	if geometry_changed:
		_collision_dirty[_chunk_of(cell)] = true
		for direction in DIRECTIONS:
			var neighbor := cell + direction
			if is_in_bounds(neighbor):
				_collision_dirty[_chunk_of(neighbor)] = true

func _queue_color_update(cell: Vector3i) -> void:
	var key := _chunk_of(cell)
	if not _color_dirty.has(key):
		_color_dirty[key] = {}
	_color_dirty[key][cell] = true
	_dirty[key] = true

func _queue_geometry_update(key: Vector3i) -> void:
	_dirty[key] = true
	_geometry_dirty[key] = true
	# A fresh job samples current palette/damage. Discard older requests; any
	# color edit after this point is retained until the job publishes.
	_color_dirty.erase(key)
	if _active_chunk != null and _active_key == key:
		_cancel_active_build()

func _cancel_active_build() -> void:
	if _active_chunk == null:
		return
	if _active_chunk.is_rebuilding():
		_rebuild_stats.build_cancellations += 1
	_active_chunk.cancel_rebuild()
	if not _chunks.has(_active_key):
		# New chunks are detached until publication; cancelled staging owns them.
		_active_chunk.free()
	_active_chunk = null
	_active_key = Vector3i(-1000, -1000, -1000)

func _chunk_of(cell: Vector3i) -> Vector3i:
	return Vector3i(floori(float(cell.x) / CHUNK_SIZE), floori(float(cell.y) / CHUNK_SIZE), floori(float(cell.z) / CHUNK_SIZE))

func _spawn_falling_cluster(cells: Array[Vector3i], colors: PackedInt32Array) -> void:
	if not visual_effects_enabled or cells.is_empty():
		return
	if _falling_clusters.size() >= max_active_clusters:
		var oldest: Node3D = _falling_clusters.pop_front()
		oldest.queue_free()
	var cluster: Node3D = FALLING_CLUSTER.new()
	cluster.fragment_limit = fragment_limit_per_cluster
	cluster.smoke_limit = smoke_limit_per_cluster
	add_child(cluster)
	cluster.setup(self, cells, colors, _effects_observer, _material)
	cluster.shattered.connect(_on_cluster_shattered)
	cluster.completed.connect(_on_cluster_completed.bind(cluster))
	_falling_clusters.append(cluster)
	falling_cluster_created.emit(cluster)

func _on_cluster_shattered(position: Vector3, block_count: int, reason: String) -> void:
	falling_cluster_finished.emit(position, block_count, reason)

func _on_cluster_completed(cluster: Node3D) -> void:
	_falling_clusters.erase(cluster)

func get_effect_stats() -> Dictionary:
	var falling := 0
	var fragments := 0
	var smoke := 0
	for cluster in _falling_clusters:
		var stats: Dictionary = cluster.get_effect_stats()
		if stats.phase == 0:
			falling += 1
		fragments += stats.fragments
		smoke += stats.smoke
	return {"clusters": _falling_clusters.size(), "falling": falling, "fragments": fragments, "smoke": smoke}

func explode(position: Vector3, _radius: float = 1.6) -> void:
	# Native grenade terrain damage is always a centered 3 x 3 x 3 cube.
	# Radius belongs to player damage/visuals and does not change this block set.
	_present_transaction(data.explode(position))

func explode_sphere(position: Vector3, radius: float) -> void:
	var cells: Array[Vector3i] = []
	var center := Vector3i(position.floor())
	var extent := ceili(radius)
	for z in range(center.z - extent, center.z + extent + 1):
		for x in range(center.x - extent, center.x + extent + 1):
			for y in range(center.y - extent, center.y + extent + 1):
				var cell := Vector3i(x, y, z)
				if (Vector3(cell) + Vector3.ONE * 0.5).distance_squared_to(position) <= radius * radius:
					cells.append(cell)
	remove_blocks(cells, true)

func cast_voxel(origin: Vector3, direction: Vector3, max_dist: float = 128.0) -> Dictionary:
	return data.cast_voxel(origin, direction, max_dist)

func cast_source_ray(origin: Vector3, direction: Vector3, max_steps: int = 500) -> Dictionary:
	return data.cast_source_ray(origin, direction, max_steps)

func cast_source_ray_legacy(origin: Vector3, direction: Vector3, length: float = 256.0) -> Dictionary:
	return data.cast_source_ray_legacy(origin, direction, length)

func get_spawn_position() -> Vector3:
	return _spawn

func get_topdown_image() -> Image:
	# GLFlatMapRenderer::GenerateBitmap selects the first solid in Z-down
	# order, with original RGB and opaque alpha, including underwater floor.
	# Explicit synchronous compatibility API: also completes an active fill.
	_begin_topdown_image()
	var changed := false
	for column in range(_topdown_cursor, dimensions.x * dimensions.z):
		_update_topdown_column(column, dimensions.y - 1)
		changed = true
	_topdown_cursor = dimensions.x * dimensions.z
	for column: int in _topdown_dirty:
		_update_topdown_column(column, _topdown_dirty[column])
		changed = true
	_topdown_dirty.clear()
	_topdown_dirty_queue.clear()
	_topdown_dirty_cursor = 0
	if changed:
		_topdown_revision += 1
	return _topdown_image

func _begin_topdown_image() -> void:
	if _topdown_image == null:
		var columns := dimensions.x * dimensions.z
		_topdown_heights.resize(columns)
		_topdown_heights.fill(-1)
		_topdown_image = Image.create(dimensions.x, dimensions.z, false, Image.FORMAT_RGBA8)
		_topdown_image.fill(Color.TRANSPARENT)
		_topdown_cursor = 0

func _update_topdown_column(column: int, from_y: int) -> void:
	var top := _column_top(column, from_y)
	_topdown_heights[column] = top.y
	_topdown_image.set_pixel(column % dimensions.x, column / dimensions.x, block_color(top.x) if top.x != 0 else Color.TRANSPARENT)

func get_topdown_image_progressive() -> Image:
	# This shared image is initially transparent; _process warms it without a
	# whole-map scan. Consumers upload again while pending or revision changes.
	_begin_topdown_image()
	_topdown_progressive = true
	return _topdown_image

func is_topdown_pending() -> bool:
	return _topdown_image != null and (_topdown_cursor < dimensions.x * dimensions.z or not _topdown_dirty.is_empty())

func get_visual_preparation_stats() -> Dictionary:
	var columns := dimensions.x * dimensions.z
	var topdown_pending := columns - _topdown_cursor + _topdown_dirty.size() if _topdown_image != null else 0
	var water_pending := columns - _water_cursor + _water_dirty.size() if _water_image != null else 0
	return {"epoch":data.epoch, "map_sequence":data.map_sequence, "topdown_requested":_topdown_image != null,
		"topdown_revision":_topdown_revision, "topdown_pending_columns":topdown_pending, "water_pending_columns":water_pending,
		"dirty_chunks":_dirty.size(), "ready":topdown_pending == 0 and water_pending == 0 and _dirty.is_empty()}

func advance_visual_preparation(max_columns: int = 4096, max_usec: int = 2000) -> Dictionary:
	# Count cap is hard; elapsed cap is checked between indivisible columns.
	# Alternate caches so a continuously edited map cannot starve new columns.
	var started := Time.get_ticks_usec()
	var processed := 0
	var topdown_changed := false
	var water_changed := false
	var columns := dimensions.x * dimensions.z
	while processed < maxi(0, max_columns) and max_usec > 0:
		var topdown_pending := is_topdown_pending()
		var water_pending := _water_image != null and (_water_cursor < columns or not _water_dirty.is_empty())
		if not topdown_pending and not water_pending:
			break
		_preparation_turn = not _preparation_turn
		if topdown_pending and (_preparation_turn or not water_pending):
			# Initial fill and dirty work alternate; both have bounded progress.
			_topdown_initial_turn = not _topdown_initial_turn
			if _topdown_cursor < columns and (_topdown_dirty.is_empty() or _topdown_initial_turn):
				_update_topdown_column(_topdown_cursor, dimensions.y - 1)
				_topdown_cursor += 1
			else:
				var column: int = _topdown_dirty_queue[_topdown_dirty_cursor]
				_update_topdown_column(column, _topdown_dirty[column])
				_topdown_dirty.erase(column)
				_topdown_dirty_cursor += 1
			topdown_changed = true
		else:
			if _water_cursor < columns:
				_update_water_column(_water_cursor)
				_water_cursor += 1
			else:
				var column: int = _water_dirty_queue[_water_dirty_cursor]
				_update_water_column(column)
				_water_dirty.erase(column)
				_water_dirty_cursor += 1
			water_changed = true
		processed += 1
		if Time.get_ticks_usec() - started >= max_usec:
			break
	if topdown_changed:
		_topdown_revision += 1
	# Compact once per batch, never duplicate every pending key per column.
	if _topdown_dirty_cursor > 0 and (_topdown_dirty_cursor == _topdown_dirty_queue.size() or _topdown_dirty_cursor >= 4096):
		_topdown_dirty_queue = _topdown_dirty_queue.slice(_topdown_dirty_cursor)
		_topdown_dirty_cursor = 0
	if _water_dirty_cursor > 0 and (_water_dirty_cursor == _water_dirty_queue.size() or _water_dirty_cursor >= 4096):
		_water_dirty_queue = _water_dirty_queue.slice(_water_dirty_cursor)
		_water_dirty_cursor = 0
	if water_changed and _water_cursor == columns:
		if not is_instance_valid(_water_mesh):
			_finish_water_creation()
		else:
			var texture: ImageTexture = _water_mesh.mesh.surface_get_material(0).get_shader_parameter("bottom_color")
			texture.update(_water_image)
	var stats := get_visual_preparation_stats()
	stats["processed_columns"] = processed
	stats["elapsed_usec"] = Time.get_ticks_usec() - started
	return stats

func _column_top(column: int, from_y: int) -> Vector2i:
	return data.column_top(column, from_y)

func clear_world(size: Vector3i) -> void:
	if data.clear(size, data.epoch + 1) != OK:
		push_warning("Invalid world reset dimensions/epoch")
		return
	_clear_world_visuals()

func _clear_world_visuals() -> void:
	_cancel_active_build()
	cancel_vxl_jobs()
	_damaged_blocks.clear()
	_irradiance = null
	if _material != null:
		_material.set_shader_parameter("irradiance_enabled", false)
	for cluster in _falling_clusters:
		remove_child(cluster)
		cluster.queue_free()
	_falling_clusters.clear()
	if is_instance_valid(_water_mesh):
		remove_child(_water_mesh)
		_water_mesh.queue_free()
		_water_mesh = null
	if is_instance_valid(_wave_field):
		remove_child(_wave_field)
		_wave_field.queue_free()
		_wave_field = null
	_water_image = null
	_water_cursor = 0
	_water_dirty.clear()
	_water_dirty_queue.clear()
	_water_dirty_cursor = 0
	if is_instance_valid(_reflection):
		remove_child(_reflection)
		_reflection.queue_free()
		_reflection = null
	for chunk in _chunks.values():
		remove_child(chunk)
		chunk.queue_free()
	_chunks.clear()
	_dirty.clear()
	_collision_dirty.clear()
	_geometry_dirty.clear()
	_color_dirty.clear()
	_topdown_image = null
	_topdown_heights.clear()
	_topdown_dirty.clear()
	_topdown_dirty_queue.clear()
	_topdown_dirty_cursor = 0
	_topdown_cursor = 0
	_topdown_revision = 0
	_topdown_progressive = false
	_preparation_turn = false
	_topdown_initial_turn = false
	_view_chunk = Vector3i(-1000, 0, -1000)

func generate_lab() -> void:
	if data.generate_lab(data.epoch + 1) != OK:
		push_warning("Invalid lab reset epoch")
		return
	_clear_world_visuals()
	_streaming = false
	map_name = "Blockfield Test Grounds"
	_spawn = Vector3(48.5, 5.0, 70.5)
	_create_water()
	_mark_all_chunks()
	rebuild_now()
	map_loaded.emit(map_name)

func _fill_box(start: Vector3i, end: Vector3i, color: int) -> void:
	data.seed_box(start, end, color)

func load_vxl(path: String, deferred_visuals: bool = false) -> Error:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	return load_vxl_bytes(file.get_buffer(file.get_length()), path.get_file().get_basename(), deferred_visuals)

func load_vxl_bytes(bytes: PackedByteArray, title: String = "Imported VXL", deferred_visuals: bool = false) -> Error:
	cancel_vxl_jobs()
	var error: Error = data.load_vxl_bytes(bytes, data.epoch + 1)
	if error != OK:
		push_warning("VXL import failed: %s" % data.last_error)
		return error
	_clear_world_visuals()
	_prepare_loaded_map(title, deferred_visuals)
	return OK

func set_map_data(validated: VOXEL_DATA, title: String = "Network map", deferred_visuals: bool = false) -> Error:
	# This adopts an already validated, uniquely coordinated writable model.
	# No palette scan/copy: the receiver validated colors before this handoff.
	if validated == null or validated.read_only or not VOXEL_DATA.valid_dimensions(validated.dimensions) or validated.blocks.size() != validated.dimensions.x * validated.dimensions.y * validated.dimensions.z:
		return ERR_INVALID_DATA
	if not VOXEL_DATA._u32(validated.epoch, true) or not VOXEL_DATA._u32(validated.map_sequence) or not VOXEL_DATA._u32(validated.last_tick) or not is_finite(validated.water_level) or not is_finite(validated.wade_origin_level):
		return ERR_INVALID_DATA
	data = validated
	_clear_world_visuals()
	_prepare_loaded_map(title, deferred_visuals)
	return OK

func _prepare_loaded_map(title: String, deferred_visuals: bool = false) -> void:
	map_name = title
	_streaming = true
	var center_x := dimensions.x / 2
	var center_z := dimensions.z / 2
	var surface_y := 1
	for y in range(dimensions.y - 1, 0, -1):
		if get_block(Vector3i(center_x, y, center_z)) != 0:
			surface_y = y + 1
			break
	_spawn = Vector3(center_x + 0.5, surface_y + 1.0, center_z + 0.5)
	_create_water(deferred_visuals)
	set_view_position(_spawn)
	if not deferred_visuals:
		rebuild_now()
	map_loaded.emit(map_name)

func encode_vxl() -> PackedByteArray:
	return data.encode_vxl()

## Only one local VXL load/save may run. Authority and network installation keep
## their synchronous interfaces; no private partially decoded map is published.
func cancel_vxl_jobs() -> void:
	_vxl_operation_token += 1
	if _vxl_active_job != null:
		_vxl_active_job.call("cancel")
		_vxl_job_stats["active"] = false
		_vxl_job_stats["done"] = true
		_vxl_job_stats["error"] = ERR_SKIP
		_vxl_job_stats["cancelled"] = true
		_vxl_job_stats["retained_input_bytes"] = 0
		_vxl_job_stats["retained_work_bytes"] = 0
		_vxl_job_stats["retained_snapshot_bytes"] = 0
		_vxl_job_stats["retained_output_bytes"] = 0
	_vxl_active_job = null

func get_vxl_job_stats() -> Dictionary:
	return _vxl_job_stats.duplicate()

func _vxl_operation_current(token: int, original: VOXEL_DATA, original_epoch: int) -> bool:
	return token == _vxl_operation_token and data == original and data.epoch == original_epoch and is_inside_tree()

func _finish_vxl_job(token: int, value: Error) -> void:
	if token != _vxl_operation_token:
		return
	_vxl_active_job = null
	_vxl_job_stats["active"] = false
	_vxl_job_stats["done"] = true
	_vxl_job_stats["error"] = value
	_vxl_job_stats["cancelled"] = value == ERR_SKIP

func load_vxl_bytes_incremental(bytes: PackedByteArray, title: String = "Imported VXL", max_columns: int = 1024, max_usec: int = 2000) -> Error:
	cancel_vxl_jobs()
	if not is_inside_tree():
		return ERR_UNCONFIGURED
	if max_columns <= 0 or max_usec <= 0:
		return ERR_INVALID_PARAMETER
	if data.read_only:
		return ERR_UNAUTHORIZED
	if not VOXEL_DATA._u32(data.epoch + 1, true):
		return ERR_INVALID_PARAMETER
	var token: int = _vxl_operation_token
	var original: VOXEL_DATA = data
	var original_epoch: int = data.epoch
	var tree: SceneTree = get_tree()
	var job: VXL_JOBS.DecodeJob = VXL_JOBS.begin_decode(bytes)
	_vxl_active_job = job
	_vxl_job_stats = job.advance(0, 0)
	_vxl_job_stats["active"] = true
	_vxl_job_stats["kind"] = "load"
	_vxl_job_stats["cancelled"] = false
	while not job.done:
		if not _vxl_operation_current(token, original, original_epoch):
			job.cancel()
			_finish_vxl_job(token, ERR_SKIP)
			return ERR_SKIP
		_vxl_job_stats = job.advance(max_columns, max_usec)
		_vxl_job_stats["active"] = not job.done
		_vxl_job_stats["kind"] = "load"
		_vxl_job_stats["cancelled"] = false
		if not job.done:
			await tree.process_frame
	if not _vxl_operation_current(token, original, original_epoch):
		job.cancel()
		_finish_vxl_job(token, ERR_SKIP)
		return ERR_SKIP
	if job.error != OK:
		original.last_error = job.message
		_finish_vxl_job(token, job.error)
		return job.error
	# Decoder has checked every span/color. Assignment adopts its private packed
	# array, with no second 64 MiB copy or whole-map color-validation scan.
	var installed: VOXEL_DATA = VOXEL_DATA.new()
	installed.dimensions = job.result_data.size
	installed.blocks = job.result_data.blocks
	installed.epoch = original_epoch + 1
	installed.water_level = original.water_level
	installed.wade_origin_level = original.wade_origin_level
	_finish_vxl_job(token, OK)
	return set_map_data(installed, title, true)

func encode_vxl_incremental(max_columns: int = 1024, max_usec: int = 2000) -> PackedByteArray:
	cancel_vxl_jobs()
	if not is_inside_tree() or max_columns <= 0 or max_usec <= 0:
		return PackedByteArray()
	var token: int = _vxl_operation_token
	var original: VOXEL_DATA = data
	var original_epoch: int = data.epoch
	var tree: SceneTree = get_tree()
	var job: VXL_JOBS.EncodeJob = VXL_JOBS.begin_encode(data)
	_vxl_active_job = job
	_vxl_job_stats = job.advance(0, 0)
	_vxl_job_stats["active"] = not job.done
	_vxl_job_stats["kind"] = "save"
	_vxl_job_stats["cancelled"] = false
	while not job.done:
		if not _vxl_operation_current(token, original, original_epoch):
			job.cancel()
			_finish_vxl_job(token, ERR_SKIP)
			return PackedByteArray()
		_vxl_job_stats = job.advance(max_columns, max_usec)
		_vxl_job_stats["active"] = not job.done
		_vxl_job_stats["kind"] = "save"
		_vxl_job_stats["cancelled"] = false
		if not job.done:
			await tree.process_frame
	if not _vxl_operation_current(token, original, original_epoch):
		job.cancel()
		_finish_vxl_job(token, ERR_SKIP)
		return PackedByteArray()
	_finish_vxl_job(token, job.error)
	return job.result_bytes

func save_vxl(path: String) -> Error:
	var bytes := encode_vxl()
	if bytes.is_empty():
		return ERR_INVALID_DATA
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.flush()
	return file.get_error()

func set_view_position(position: Vector3) -> void:
	_effects_observer = position
	if not _streaming:
		return
	var center := _chunk_of(Vector3i(position.floor()))
	if center.x == _view_chunk.x and center.z == _view_chunk.z:
		return
	_view_chunk = center
	if _active_chunk != null and not _is_chunk_near(_active_key):
		_cancel_active_build()
	for key in _chunks.keys():
		if not _is_chunk_near(key):
			var chunk: Node3D = _chunks[key]
			remove_child(chunk)
			chunk.queue_free()
			_chunks.erase(key)
			_dirty.erase(key)
			_geometry_dirty.erase(key)
			_color_dirty.erase(key)
			_collision_dirty.erase(key)
	for z in range(maxi(0, center.z - render_radius), mini(ceili(float(dimensions.z) / CHUNK_SIZE), center.z + render_radius + 1)):
		for x in range(maxi(0, center.x - render_radius), mini(ceili(float(dimensions.x) / CHUNK_SIZE), center.x + render_radius + 1)):
			for y in range(ceili(float(dimensions.y) / CHUNK_SIZE)):
				var key := Vector3i(x, y, z)
				if not _chunks.has(key):
					_queue_geometry_update(key)

func set_effects_observer(position: Vector3) -> void:
	_effects_observer = position
	if irradiance_enabled and _irradiance != null and _irradiance.configure(position):
		_bind_irradiance()

func get_effects_observer() -> Vector3:
	return _effects_observer

func _create_water(deferred: bool = false) -> void:
	_water_image = Image.create(dimensions.x, dimensions.z, false, Image.FORMAT_RGBA8)
	_water_cursor = 0
	_water_dirty.clear()
	_water_dirty_queue.clear()
	_water_dirty_cursor = 0
	if not deferred:
		for column in range(dimensions.x * dimensions.z):
			_update_water_column(column)
		_water_cursor = dimensions.x * dimensions.z
		_finish_water_creation()

func _update_water_column(column: int) -> void:
	_water_image.set_pixel(column % dimensions.x, column / dimensions.x, block_color(data.blocks[column * dimensions.y]))

func _finish_water_creation() -> void:
	_wave_field = WAVE_FIELD.new()
	_wave_field.name = "SpectralWaterWaves"
	add_child(_wave_field)
	_wave_field.setup()
	_wave_field.set_enabled(water_enabled and water_waves_enabled)
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	material.set_shader_parameter("bottom_color", ImageTexture.create_from_image(_water_image))
	material.set_shader_parameter("map_size", Vector2(dimensions.x, dimensions.z))
	material.set_shader_parameter("fog_color", Vector3(_water_fog_color.r, _water_fog_color.g, _water_fog_color.b))
	material.set_shader_parameter("fog_distance", _water_fog_distance)
	material.set_shader_parameter("fog_enabled", water_fog_enabled)
	material.set_shader_parameter("wave_texture", _wave_field.get_texture())
	material.set_shader_parameter("lighting_enabled", lighting_enabled)
	material.set_shader_parameter("waves_enabled", water_waves_enabled)
	material.set_shader_parameter("refraction_enabled", water_refraction_enabled)
	var plane := PlaneMesh.new()
	plane.size = Vector2(dimensions.x, dimensions.z)
	plane.material = material
	_water_mesh = MeshInstance3D.new()
	_water_mesh.name = "WaterSurface"
	_water_mesh.mesh = plane
	_water_mesh.position = Vector3(dimensions.x * 0.5, water_level + 0.002, dimensions.z * 0.5)
	_water_mesh.visible = water_enabled
	_water_mesh.layers = REFLECTION.WATER_LAYER
	_water_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water_mesh)
	_setup_reflection()

func _setup_reflection() -> void:
	if not is_instance_valid(_water_mesh) or not is_instance_valid(_reflection_camera):
		return
	if not is_instance_valid(_reflection):
		_reflection = REFLECTION.new()
		_reflection.name = "PlanarWaterReflection"
		add_child(_reflection)
	_reflection.setup(_reflection_camera, _water_mesh.mesh.surface_get_material(0), _water_mesh.global_position.y, get_draw_distance())
	_reflection.set_budget(_reflection_size, _reflection_frequency, _reflection_geometry_budget)
	_reflection.set_enabled(water_enabled and water_reflections_enabled)

func set_reflection_camera(camera: Camera3D) -> void:
	_reflection_camera = camera
	_setup_reflection()

func set_water_reflections_enabled(enabled: bool) -> void:
	water_reflections_enabled = enabled
	if is_instance_valid(_reflection):
		_reflection.set_enabled(enabled and water_enabled)
	elif enabled:
		_setup_reflection()

func set_water_reflection_budget(size: Vector2i, frequency: float, instances: int) -> void:
	_reflection_size = size
	_reflection_frequency = frequency
	_reflection_geometry_budget = instances
	if is_instance_valid(_reflection):
		_reflection.set_budget(size, frequency, instances)

func get_reflection_stats() -> Dictionary:
	return _reflection.get_stats() if is_instance_valid(_reflection) else {"enabled": false, "requested": water_reflections_enabled, "geometry": 0}

func set_water_waves_enabled(enabled: bool) -> void:
	water_waves_enabled = enabled
	if is_instance_valid(_water_mesh):
		_water_mesh.mesh.surface_get_material(0).set_shader_parameter("waves_enabled", enabled)
	if is_instance_valid(_wave_field):
		_wave_field.set_enabled(water_enabled and enabled)

func set_water_refraction_enabled(enabled: bool) -> void:
	water_refraction_enabled = enabled
	if is_instance_valid(_water_mesh):
		_water_mesh.mesh.surface_get_material(0).set_shader_parameter("refraction_enabled", enabled)

func get_water_stats() -> Dictionary:
	return _wave_field.get_stats() if is_instance_valid(_wave_field) else {}

func set_water_enabled(enabled: bool) -> void:
	water_enabled = enabled
	if is_instance_valid(_water_mesh):
		_water_mesh.visible = enabled
	if is_instance_valid(_wave_field):
		_wave_field.set_enabled(enabled and water_waves_enabled)
	if is_instance_valid(_reflection):
		_reflection.set_enabled(enabled and water_reflections_enabled)
	_mark_all_chunks(false)

func set_water_fog(color: Color, distance: float) -> void:
	_water_fog_color = color
	_water_fog_distance = maxf(distance, 1.0)
	if is_instance_valid(_water_mesh):
		var material: ShaderMaterial = _water_mesh.mesh.surface_get_material(0)
		material.set_shader_parameter("fog_color", Vector3(color.r, color.g, color.b))
		material.set_shader_parameter("fog_distance", maxf(distance, 1.0))

func set_water_fog_enabled(enabled: bool) -> void:
	# Water implements native channel-dependent fog itself, so Environment's
	# fog_enabled does not control this material's fog_disabled shader.
	water_fog_enabled = enabled
	if is_instance_valid(_water_mesh):
		_water_mesh.mesh.surface_get_material(0).set_shader_parameter("fog_enabled", enabled)

func _is_chunk_near(key: Vector3i) -> bool:
	return abs(key.x - _view_chunk.x) <= render_radius and abs(key.z - _view_chunk.z) <= render_radius

func _mark_all_chunks(geometry_changed: bool = true) -> void:
	for z in range(ceili(float(dimensions.z) / CHUNK_SIZE)):
		for x in range(ceili(float(dimensions.x) / CHUNK_SIZE)):
			for y in range(ceili(float(dimensions.y) / CHUNK_SIZE)):
				_queue_geometry_update(Vector3i(x, y, z))
				if geometry_changed:
					_collision_dirty[Vector3i(x, y, z)] = true

func rebuild_now() -> void:
	_ensure_material()
	# Complete an in-flight build using its current halo and final color queue.
	# Geometry invalidation always cancels stale jobs before reaching this API.
	if _active_chunk != null:
		_finish_active_build()
	for key: Vector3i in _dirty.keys():
		if not _streaming or _is_chunk_near(key):
			_rebuild_chunk(key)
	_dirty.clear()
	_geometry_dirty.clear()
	_color_dirty.clear()
	_collision_dirty.clear()

func _rebuild_chunk(key: Vector3i) -> void:
	if _color_dirty.has(key) and not _geometry_dirty.has(key) and _chunks.has(key):
		for cell: Vector3i in _color_dirty[key]:
			_update_chunk_color(_chunks[key], cell)
		_color_dirty.erase(key)
		return
	_start_chunk_build(key)
	_finish_active_build()

func _start_chunk_build(key: Vector3i) -> void:
	var rebuild_collision := _collision_dirty.has(key) or not _chunks.has(key)
	_active_key = key
	if _chunks.has(key):
		_active_chunk = _chunks[key]
	else:
		_active_chunk = CHUNK_SCRIPT.new()
		_active_chunk.coordinate = key
		_active_chunk.position = Vector3(key * CHUNK_SIZE)
		_active_chunk.name = "Chunk_%d_%d_%d" % [key.x, key.y, key.z]
	_active_chunk.begin_rebuild(self, rebuild_collision)

func _finish_active_build() -> void:
	var advanced := _active_chunk.advance_rebuild_slice(self, _material, _color_dirty.get(_active_key, {}), 0, 0, rebuild_profiling_enabled)
	if rebuild_profiling_enabled:
		_record_rebuild_profile(advanced)
	_publish_chunk_build()

func _record_rebuild_profile(advanced: Dictionary) -> void:
	# Record each slice immediately so cancelled work remains represented.
	for stage in range(4):
		_stage_cpu_usec[stage] += advanced.stage_cpu_usec[stage]
		_stage_units[stage] += advanced.stage_units[stage]

func _publish_chunk_build() -> void:
	_rebuild_stats.mesh_builds += 1
	if _collision_dirty.has(_active_key) or not _chunks.has(_active_key):
		_rebuild_stats.collision_builds += 1
	_rebuild_stats.last_publish_usec = _active_chunk.publish_usec
	_rebuild_stats.max_publish_usec = maxi(_rebuild_stats.max_publish_usec, _active_chunk.publish_usec)
	if not _chunks.has(_active_key):
		add_child(_active_chunk)
		_chunks[_active_key] = _active_chunk
	_active_chunk.mesh_instance.visibility_range_end = get_draw_distance() + CHUNK_SIZE * 0.8660254
	_dirty.erase(_active_key)
	_geometry_dirty.erase(_active_key)
	_color_dirty.erase(_active_key)
	_collision_dirty.erase(_active_key)
	_active_chunk = null
	_active_key = Vector3i(-1000, -1000, -1000)

func _update_chunk_color(chunk: VoxelChunk, cell: Vector3i) -> void:
	var bytes := chunk.update_color(self, cell)
	if bytes > 0:
		_rebuild_stats.color_updates += 1
		_rebuild_stats.color_upload_bytes += bytes
		_rebuild_stats.color_vertices += bytes / chunk._attribute_stride

func _nearest_dirty_key(colors_only: bool = false) -> Vector3i:
	var result := Vector3i(-1000, -1000, -1000)
	var distance := INF
	var observer := _chunk_of(Vector3i(_effects_observer.floor()))
	var candidates: Dictionary = _color_dirty if colors_only else _dirty
	for key: Vector3i in candidates:
		if colors_only and (_geometry_dirty.has(key) or not _chunks.has(key)):
			continue
		var score := Vector3(key - observer).length_squared()
		if score < distance:
			result = key
			distance = score
	return result

func process_rebuild_work(max_units: int = 0, time_budget_usec: int = 4000) -> Dictionary:
	# Unit count zero means no count limit; nonpositive time means no work.
	# One active job bounds staging memory. Cheap color uploads take priority,
	# then the nearest dirty chunk advances without replacing partial meshes.
	var started := Time.get_ticks_usec()
	var units := 0
	var completed := 0
	var max_step: int = _rebuild_stats.max_step_usec
	if time_budget_usec > 0 and rebuild_budget > 0:
		_ensure_material()
		# No input callback can interleave within this synchronous work slice.
		# Select colors once per completed color chunk, and retain the active
		# job's final-color queue until publication, rather than per column.
		var color_key := _nearest_dirty_key(true)
		var pending_colors: Dictionary = _color_dirty.get(_active_key, {})
		var now := Time.get_ticks_usec()
		while (max_units <= 0 or units < max_units) and completed < rebuild_budget and now - started < time_budget_usec:
			var step_started := now
			var processed := 1
			var unit_max := 0
			if color_key.x != -1000:
				var cell: Vector3i = _color_dirty[color_key].keys()[0]
				if not _streaming or _is_chunk_near(color_key):
					_update_chunk_color(_chunks[color_key], cell)
				_color_dirty[color_key].erase(cell)
				if _color_dirty[color_key].is_empty():
					_color_dirty.erase(color_key)
					_dirty.erase(color_key)
					completed += 1
					color_key = _nearest_dirty_key(true)
			else:
				if _active_chunk == null:
					var key := _nearest_dirty_key()
					if key.x == -1000:
						break
					if _streaming and not _is_chunk_near(key):
						_dirty.erase(key)
						_geometry_dirty.erase(key)
						_color_dirty.erase(key)
						_collision_dirty.erase(key)
						now = Time.get_ticks_usec()
						continue
					_start_chunk_build(key)
					pending_colors = _color_dirty.get(key, {})
				var setup_usec := Time.get_ticks_usec() - step_started
				var remaining := maxi(0, max_units - units) if max_units > 0 else 0
				var advanced := _active_chunk.advance_rebuild_slice(self, _material, pending_colors, remaining, started + time_budget_usec, rebuild_profiling_enabled)
				if rebuild_profiling_enabled:
					_record_rebuild_profile(advanced)
				processed = advanced.processed_units
				unit_max = setup_usec + int(advanced.max_unit_usec)
				if advanced.completed:
					_publish_chunk_build()
					completed += 1
			units += processed
			now = Time.get_ticks_usec()
			max_step = maxi(max_step, unit_max if unit_max > 0 else now - step_started)
			if processed == 0:
				break
	var elapsed := Time.get_ticks_usec() - started
	_rebuild_stats.max_step_usec = max_step
	_rebuild_stats.last_frame_usec = elapsed
	_rebuild_stats.max_frame_usec = maxi(_rebuild_stats.max_frame_usec, elapsed)
	return {"processed_units": units, "completed_chunks": completed, "pending_chunks": _dirty.size(), "elapsed_usec": elapsed, "active_build": _active_chunk != null}

func get_rebuild_stats() -> Dictionary:
	var stats := _rebuild_stats.duplicate()
	# Ordered halo/mesh/collision/publish CPU and logical units. Only opt-in
	# profiling measures stage dispatch/buffer ownership overhead; max_step is
	# the longest logical unit plus scheduler setup, max_frame the whole slice.
	stats.profiling_enabled = rebuild_profiling_enabled
	stats.stage_cpu_usec = _stage_cpu_usec.duplicate()
	stats.stage_units = _stage_units.duplicate()
	stats.color_backend = "dummy_surface" if DisplayServer.get_name() == "headless" else "attribute_region"
	stats.pending_chunks = _dirty.size()
	stats.pending_color_chunks = _color_dirty.size()
	stats.active_build = _active_chunk != null
	var cache_bytes := 0
	for chunk: VoxelChunk in _chunks.values():
		cache_bytes += chunk.get_cached_color_bytes()
	stats.cached_color_bytes = cache_bytes
	return stats

func _ensure_material() -> void:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = TERRAIN_SHADER
		_material.set_shader_parameter("lighting_enabled", lighting_enabled)
		_material.set_shader_parameter("ambient_occlusion_strength", 1.0 if ambient_occlusion_enabled else 0.0)
		_material.set_shader_parameter("ambient_occlusion_atlas", AO.get_texture())

func set_ambient_occlusion_atlas_enabled(enabled: bool) -> void:
	# Explicit quality/diagnostic fallback; native atlas sampling is the default.
	_ensure_material()
	_material.set_shader_parameter("ambient_occlusion_atlas_enabled", enabled)

func reload_resources() -> void:
	if is_instance_valid(_reflection):
		_reflection.clear_cache()
	for cluster in _falling_clusters:
		if is_instance_valid(cluster):
			cluster.queue_free()
	_falling_clusters.clear()
	FALLING_CLUSTER.clear_texture_cache()
	AO.initialize()
	_ensure_material()
	_material.set_shader_parameter("ambient_occlusion_atlas", AO.get_texture())
	_mark_all_chunks(false)

func set_lighting_enabled(enabled: bool) -> void:
	lighting_enabled = enabled
	_ensure_material()
	_material.set_shader_parameter("lighting_enabled", enabled)
	if is_instance_valid(_water_mesh):
		_water_mesh.mesh.surface_get_material(0).set_shader_parameter("lighting_enabled", enabled)

func set_ambient_occlusion_enabled(enabled: bool) -> void:
	ambient_occlusion_enabled = enabled
	_ensure_material()
	_material.set_shader_parameter("ambient_occlusion_strength", 1.0 if enabled else 0.0)

func _ensure_irradiance() -> void:
	_ensure_material()
	if _irradiance == null:
		_irradiance = IRRADIANCE.new(self)
		_irradiance.configure(_effects_observer)
		_bind_irradiance()
	elif _irradiance.configure(_effects_observer):
		_bind_irradiance()

func _bind_irradiance() -> void:
	_material.set_shader_parameter("irradiance_origin", _irradiance.origin)
	_material.set_shader_parameter("irradiance_size", Vector3(_irradiance.size))
	_material.set_shader_parameter("irradiance_spacing", IRRADIANCE.STEP)
	for index in range(4):
		_material.set_shader_parameter(["irradiance_base", "irradiance_x", "irradiance_y", "irradiance_z"][index], _irradiance.textures[index])
	_material.set_shader_parameter("irradiance_enabled", irradiance_enabled)
	_material.set_shader_parameter("irradiance_light", _irradiance_light)

func set_irradiance_enabled(enabled: bool) -> void:
	irradiance_enabled = enabled
	_ensure_material()
	if enabled:
		_ensure_irradiance()
	_material.set_shader_parameter("irradiance_enabled", enabled)

func set_irradiance_light(color: Color, energy: float = 1.0) -> void:
	_irradiance_light = Vector3(color.r, color.g, color.b) * maxf(0.0, energy)
	_ensure_material()
	_material.set_shader_parameter("irradiance_light", _irradiance_light)

func get_irradiance_at(position: Vector3, normal: Vector3) -> Color:
	if not irradiance_enabled or _irradiance == null:
		return Color(0, 0, 0)
	var radiance: Vector3 = _irradiance.sample(position, normal.normalized()) * _irradiance_light
	return Color(radiance.x, radiance.y, radiance.z)

func get_irradiance_stats() -> Dictionary:
	var stats: Dictionary = _irradiance.get_stats() if _irradiance != null else {"dirty_probes":0,"probes":0}
	stats["enabled"] = irradiance_enabled
	return stats

func get_draw_distance() -> float:
	return float(render_radius * CHUNK_SIZE)

func set_draw_distance(meters: float) -> float:
	render_radius = clampi(ceili(meters / CHUNK_SIZE), 1, 10)
	_view_chunk = Vector3i(-1000, 0, -1000)
	set_view_position(_effects_observer)
	for chunk in _chunks.values():
		chunk.mesh_instance.visibility_range_end = get_draw_distance() + CHUNK_SIZE * 0.8660254
	_water_fog_distance = get_draw_distance()
	if is_instance_valid(_water_mesh):
		var material: ShaderMaterial = _water_mesh.mesh.surface_get_material(0)
		material.set_shader_parameter("fog_distance", get_draw_distance())
	if is_instance_valid(_reflection):
		_reflection.distance_limit = get_draw_distance()
	return get_draw_distance()

func get_stats() -> Dictionary:
	var faces := 0
	for chunk in _chunks.values():
		faces += chunk.face_count
	return {"dimensions": dimensions, "chunks": _chunks.size(), "faces": faces, "dirty_chunks": _dirty.size(), "data_bytes": _blocks.size() * 4}
