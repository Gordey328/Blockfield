class_name VoxelIrradiance
extends RefCounted
## GLRadiosityRenderer's source palette/sun-shadow single-bounce evaluation.
## Four observer-centered 4 m coefficient volumes replace native per-voxel maps.
const STEP := 4.0
const MAX_HORIZONTAL_PROBES := 33
const MAX_VERTICAL_PROBES := 17
const ENVELOPE := 6
const MAX_SHADOW_COLUMNS := 65536
var time_budget_ms := 2.0
var probe_budget := 24
var origin := Vector3.ZERO
var size := Vector3i.ZERO
var textures: Array[ImageTexture3D] = []
var _world: Node3D
var _values: Array[PackedVector3Array] = []
var _images: Array = []
var _dirty := PackedByteArray()
var _pending: Array[int] = []
var _shadow: Dictionary = {}
var _uploads_pending := false
var _upload_frame := 0
var _computed := 0
var _last_usec := 0
var _max_usec := 0
var _uploads := 0
var _reused := 0
var _observer := Vector3.ZERO

func _init(world: Node3D) -> void:
	_world = world

func configure(observer: Vector3) -> bool:
	_observer = observer
	var dimensions: Vector3i = _world.dimensions
	var target_size := Vector3i(mini(MAX_HORIZONTAL_PROBES, ceili(dimensions.x / STEP) + 1), mini(MAX_VERTICAL_PROBES, ceili(dimensions.y / STEP) + 1), mini(MAX_HORIZONTAL_PROBES, ceili(dimensions.z / STEP) + 1))
	var span := Vector3(target_size - Vector3i.ONE) * STEP
	var target_origin := Vector3(clampf(floor(observer.x / 16.0) * 16.0 - span.x * 0.5, 0.0, maxf(0.0, dimensions.x - span.x)), 0.0, clampf(floor(observer.z / 16.0) * 16.0 - span.z * 0.5, 0.0, maxf(0.0, dimensions.z - span.z))) + Vector3.ONE * 0.5
	if target_size == size and origin.is_equal_approx(target_origin):
		return false
	var old_size := size
	var offset := Vector3i((target_origin - origin) / STEP)
	var old_values := _values.duplicate()
	var old_dirty := _dirty.duplicate()
	size = target_size
	origin = target_origin
	_values.clear()
	_images.clear()
	textures.clear()
	_pending.clear()
	if old_size != size:
		_shadow.clear()
	_computed = 0
	_reused = 0
	var count := size.x * size.y * size.z
	_dirty.resize(count)
	_dirty.fill(1)
	var reuse := PackedInt32Array()
	reuse.resize(count)
	reuse.fill(-1)
	if old_size == size and not old_values.is_empty():
		for index in range(count):
			var cell := _cell_of(index) + offset
			if cell.x >= 0 and cell.y >= 0 and cell.z >= 0 and cell.x < size.x and cell.y < size.y and cell.z < size.z:
				var previous := _index(cell)
				if old_dirty[previous] == 0:
					reuse[index] = previous
					_dirty[index] = 0
					_reused += 1
	_computed = _reused
	# Prioritize columns near the observer and the observer's height within
	# each column; users see local bounce before distant cache warming.
	var columns: Array[Vector2i] = []
	for z in range(size.z):
		for x in range(size.x):
			columns.append(Vector2i(x, z))
	var observer_grid := (observer - origin) / STEP
	var horizontal := Vector2(observer_grid.x, observer_grid.z)
	columns.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a).distance_squared_to(horizontal) > Vector2(b).distance_squared_to(horizontal))
	var heights: Array[int] = []
	for y in range(size.y):
		heights.append(y)
	heights.sort_custom(func(a: int, b: int) -> bool:
		return absf(a - observer_grid.y) > absf(b - observer_grid.y))
	for column in columns:
		for y in heights:
			var index := _index(Vector3i(column.x, y, column.y))
			if _dirty[index] != 0:
				_pending.append(index)
	for coefficient in range(4):
		var values := PackedVector3Array()
		values.resize(count)
		var slices: Array[Image] = []
		for z in range(size.z):
			var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBH)
			image.fill(Color(0, 0, 0))
			if _reused > 0:
				for y in range(size.y):
					for x in range(size.x):
						var index := _index(Vector3i(x, y, z))
						if reuse[index] >= 0:
							var value: Vector3 = old_values[coefficient][reuse[index]]
							values[index] = value
							image.set_pixel(x, y, Color(value.x, value.y, value.z))
			slices.append(image)
		_values.append(values)
		_images.append(slices)
		var texture := ImageTexture3D.new()
		var error := texture.create(Image.FORMAT_RGBH, size.x, size.y, size.z, false, slices)
		assert(error == OK, "RGB16F irradiance texture must be supported")
		textures.append(texture)
	_uploads_pending = false
	return true

func _cell_of(index: int) -> Vector3i:
	return Vector3i(index % size.x, (index / size.x) % size.y, index / (size.x * size.y))

func _index(cell: Vector3i) -> int:
	return cell.x + size.x * (cell.y + size.y * cell.z)

func _shadow_pixel(x: int, source_y: int) -> int:
	var dimensions: Vector3i = _world.dimensions
	x = posmod(x, dimensions.x)
	source_y = posmod(source_y, dimensions.z)
	var key := x + dimensions.x * source_y
	if _shadow.has(key):
		return _shadow[key]
	var data: PackedInt32Array = _world._blocks
	var y := source_y
	var pixel := 0
	var found := false
	for depth in range(dimensions.y):
		var color := data[dimensions.y - 1 - depth + dimensions.y * (x + dimensions.x * y)]
		if color != 0 and depth < dimensions.y - 1:
			pixel = _encode_shadow(depth, color, false)
			found = true
			break
		y = (y + 1) % dimensions.z
		color = data[dimensions.y - 1 - depth + dimensions.y * (x + dimensions.x * y)]
		if color != 0 and depth < dimensions.y - 1:
			pixel = _encode_shadow(depth + 1, color, true)
			found = true
			break
	if not found:
		pixel = _encode_shadow(dimensions.y, data[dimensions.y * (x + dimensions.x * y)], false)
	if _shadow.size() >= MAX_SHADOW_COLUMNS:
		_shadow.clear()
	_shadow[key] = pixel
	return pixel

static func _encode_shadow(depth: int, color: int, side: bool) -> int:
	return (depth << 24) | (((color >> 18) & 63) << 16) | (((color >> 10) & 63) << 8) | ((color >> 2) & 63) | (0x00800000 if side else 0)

func evaluate(position: Vector3) -> Array[Vector3]:
	# Evaluate the same native cell center and sun projection y-z.
	var height: int = _world.dimensions.y
	var ipos := Vector3i(floori(position.x), floori(position.z), height - 1 - floori(position.y))
	var point := Vector3(ipos) + Vector3.ONE * 0.5
	var result: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	for x in range(-ENVELOPE, ENVELOPE + 1):
		for y in range(-ENVELOPE, ENVELOPE + 1):
			var pixel := _shadow_pixel(ipos.x + x, ipos.y - ipos.z + y)
			var depth := pixel >> 24
			var wx := ipos.x + x
			var wy := ipos.y - ipos.z + y + depth
			var side := (pixel & 0x00800000) != 0
			var center: Vector3
			var cosine_distance: float
			if side:
				if wy <= ipos.y:
					continue
				center = Vector3(wx + 0.5, wy, depth - 0.5)
				cosine_distance = center.y - point.y
			else:
				if depth <= ipos.z:
					continue
				center = Vector3(wx + 0.5, wy + 0.5, depth)
				cosine_distance = center.z - point.z
			var difference := point - center
			var distance := difference.length()
			var intensity := maxf(cosine_distance, 0.0) / distance / pow(distance + 0.4, 2.0)
			var incoming := -difference / distance
			var color := Vector3((pixel >> 16) & 63, (pixel >> 8) & 63, pixel & 63) * intensity * (0.1 / 64.0)
			result[0] += color
			result[1] += color * incoming.x
			result[2] -= color * incoming.z # Source Z-down -> Godot Y-up.
			result[3] += color * incoming.y
	return result

func invalidate(cell: Vector3i) -> void:
	var dimensions: Vector3i = _world.dimensions
	var source_z := dimensions.y - 1 - cell.y
	for shift in range(2):
		_shadow.erase(posmod(cell.x, dimensions.x) + dimensions.x * posmod(cell.z - source_z - shift, dimensions.z))
	var minimum := Vector3i(((Vector3(cell) - Vector3.ONE * ENVELOPE - origin) / STEP).floor())
	var maximum := Vector3i(((Vector3(cell) + Vector3.ONE * ENVELOPE - origin) / STEP).ceil())
	for z in range(maxi(0, minimum.z), mini(size.z - 1, maximum.z) + 1):
		for y in range(maxi(0, minimum.y), mini(size.y - 1, maximum.y) + 1):
			for x in range(maxi(0, minimum.x), mini(size.x - 1, maximum.x) + 1):
				var index := _index(Vector3i(x, y, z))
				if _dirty[index] == 0:
					_dirty[index] = 1
					_pending.append(index)

func update() -> void:
	var started := Time.get_ticks_usec()
	var processed := 0
	while not _pending.is_empty() and processed < probe_budget:
		var index: int = _pending.pop_back()
		var cell := _cell_of(index)
		var value := evaluate(origin + Vector3(cell) * STEP)
		for coefficient in range(4):
			_values[coefficient][index] = value[coefficient]
			_images[coefficient][cell.z].set_pixel(cell.x, cell.y, Color(value[coefficient].x, value[coefficient].y, value[coefficient].z))
		_dirty[index] = 0
		_computed += 1
		processed += 1
		_uploads_pending = true
		if Time.get_ticks_usec() - started >= time_budget_ms * 1000.0:
			break
	_upload_frame += 1
	if _uploads_pending and (_pending.is_empty() or _upload_frame >= 6):
		_upload()
	_last_usec = Time.get_ticks_usec() - started
	_max_usec = maxi(_max_usec, _last_usec)

func _upload() -> void:
	for coefficient in range(4):
		textures[coefficient].update(_images[coefficient])
	_uploads_pending = false
	_upload_frame = 0
	_uploads += 1

func flush() -> void:
	while not _pending.is_empty():
		update()
	if _uploads_pending:
		_upload()

func sample(position: Vector3, normal: Vector3) -> Vector3:
	var grid := (position - origin) / STEP
	if grid.x < 0 or grid.y < 0 or grid.z < 0 or grid.x > size.x - 1 or grid.y > size.y - 1 or grid.z > size.z - 1:
		return Vector3.ZERO
	var base := Vector3i(grid.floor())
	var weight := grid - Vector3(base)
	var result := Vector3.ZERO
	for z in range(2):
		for y in range(2):
			for x in range(2):
				var cell := (base + Vector3i(x, y, z)).min(size - Vector3i.ONE)
				var index := _index(cell)
				var value := _values[0][index] + _values[1][index] * normal.x + _values[2][index] * normal.y + _values[3][index] * normal.z
				result += value * (weight.x if x else 1.0 - weight.x) * (weight.y if y else 1.0 - weight.y) * (weight.z if z else 1.0 - weight.z)
	return result.max(Vector3.ZERO) * 1.5

func get_stats() -> Dictionary:
	var count := size.x * size.y * size.z
	return {"spacing": STEP, "size":size, "origin":origin, "probes":count, "dirty_probes":_pending.size(), "computed_probes":_computed, "reused_probes":_reused, "shadow_columns":_shadow.size(), "max_shadow_columns":MAX_SHADOW_COLUMNS, "texture_bytes":count * 4 * 3 * 2, "coefficient_bytes":count * 4 * 3 * 4, "last_update_usec":_last_usec, "max_update_usec":_max_usec, "time_budget_ms":time_budget_ms, "probe_budget":probe_budget, "uploads":_uploads, "native_per_voxel_volumes":false}
