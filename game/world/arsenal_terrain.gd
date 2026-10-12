class_name ArsenalTerrain
extends RefCounted
## Fixed-tick, canonical terrain authority for the optional arsenal.
## Receipts are already committed. Presentation must never apply them to Data again.

const MAX_JOBS: int = 8
const MAX_INPUT_CELLS: int = 512
const MAX_FOAM_CELLS: int = 36
const MAX_WORK_PER_STEP: int = 512
const MAX_CHANGES_PER_STEP: int = 256
const MAX_RECEIPTS: int = 16
const MARK_PAGE_BITS: int = 1024
const DIRECTIONS: Array[Vector3i] = [Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK, Vector3i.UP]

var _data: VoxelData
var _generation: int = -1
var _epoch: int = -1
var _tick: int = 0
var _last_step_tick: int = -1
var _next_job_id: int = 1
var _jobs: Array[Dictionary] = []
var _receipts: Array[Dictionary] = []
var _foam: Dictionary[Vector3i, Dictionary] = {}
## Sparse reference-counted guards exist only while direct cuts are queued.
var _guards: Dictionary[Vector3i, Dictionary] = {}
var _reserved_foam: int = 0
var _active: Dictionary = {}
var _phase: String = ""
var _offset: int = 0
var _seeds: PackedInt32Array = PackedInt32Array()
var _seed_marks: Dictionary[int, PackedByteArray] = {}
var _stack: PackedInt32Array = PackedInt32Array()
var _component: PackedInt32Array = PackedInt32Array()
var _visited: Dictionary[int, PackedByteArray] = {}
var _checked: Dictionary[int, PackedByteArray] = {}
var _reseed_requested: bool = false
var _own_commit: bool = false
var _last_work: int = 0
var _last_changes: int = 0
var _max_work: int = 0
var _max_changes: int = 0
var _max_step_usec: int = 0
var _completed: int = 0
var _cancelled: int = 0
var _rescans: int = 0
var _last_error: String = ""

func configure(data: VoxelData) -> void:
	if _data != null and _data.cells_committed.is_connected(_on_cells_committed):
		_data.cells_committed.disconnect(_on_cells_committed)
	clear()
	_data = data
	if _data != null:
		_generation = _data.generation
		_epoch = _data.epoch
		_tick = _data.last_tick
		_data.cells_committed.connect(_on_cells_committed)

func dispose() -> void:
	# Map reset/scene teardown releases the observer as well as queued work.
	# Selection changes and player death must preserve the live helper instead.
	if _data != null and _data.cells_committed.is_connected(_on_cells_committed):
		_data.cells_committed.disconnect(_on_cells_committed)
	clear()
	_data = null
	_generation = -1
	_epoch = -1

func clear() -> void:
	# Reset/new map only. Death/respawn must preserve canonical map edits.
	_jobs.clear()
	_receipts.clear()
	_foam.clear()
	_guards.clear()
	_reserved_foam = 0
	_last_step_tick = -1
	_finish_active(false)
	_last_error = ""

func _synchronize() -> bool:
	if _data == null or _data.read_only:
		return false
	if _generation != _data.generation or _epoch != _data.epoch:
		_cancelled += _jobs.size() + (0 if _active.is_empty() else 1)
		clear()
		_generation = _data.generation
		_epoch = _data.epoch
		_tick = _data.last_tick
	return _data.blocks.size() == _data.dimensions.x * _data.dimensions.y * _data.dimensions.z

func can_queue(job_count: int = 1) -> bool:
	return _synchronize() and job_count > 0 and _jobs.size() + (0 if _active.is_empty() else 1) + job_count <= MAX_JOBS

func _rejected(reason: String) -> Dictionary:
	return {"ok": false, "accepted": false, "error": reason, "job_id": 0}

func _admit(cells: Array[Vector3i], metadata: Dictionary, kind: String, extra: Dictionary = {}) -> Dictionary:
	if not can_queue():
		return _rejected("terrain work queue is full or map is unavailable")
	if cells.is_empty() or cells.size() > MAX_INPUT_CELLS:
		return _rejected("terrain input must contain 1..512 cells")
	var error: String = _data._metadata_error(metadata)
	if not error.is_empty():
		return _rejected(error)
	var job: Dictionary = {"id": _next_job_id, "kind": kind, "cells": cells.duplicate(), "metadata": metadata.duplicate(), "generation": _generation, "epoch": _epoch}
	job.merge(extra)
	_jobs.append(job)
	_next_job_id += 1
	return {"ok": true, "accepted": true, "error": "", "job_id": int(job.id)}

func queue_remove(cells: Array[Vector3i], metadata: Dictionary) -> Dictionary:
	var admitted: Dictionary = _admit(cells, metadata, "remove")
	if not admitted.ok:
		return admitted
	var expected: Dictionary[Vector3i, Dictionary] = {}
	for cell: Vector3i in cells:
		if expected.has(cell) or not _data.is_in_bounds(cell) or cell.y <= 1:
			continue
		var guard: Dictionary = _guards.get(cell, {"refs": 0, "version": 0})
		guard.refs += 1
		_guards[cell] = guard
		expected[cell] = {"color": _data.get_block(cell), "version": int(guard.version)}
	_jobs[-1].expected = expected
	return admitted

func _release_guard(cell: Vector3i) -> void:
	if not _guards.has(cell):
		return
	_guards[cell].refs -= 1
	if int(_guards[cell].refs) <= 0:
		_guards.erase(cell)

func queue_place(cells: Array[Vector3i], color: int, expiry_tick: int, metadata: Dictionary, clearance: Callable = Callable()) -> Dictionary:
	if not _synchronize() or cells.is_empty() or cells.size() + _foam.size() + _reserved_foam > MAX_FOAM_CELLS:
		return _rejected("temporary foam limit is 36 cells")
	if color == 0 or not VoxelData.valid_color(color) or expiry_tick <= maxi(_tick, int(metadata.get("tick", _tick))):
		return _rejected("invalid temporary foam color or expiry")
	var prior: Dictionary[Vector3i, bool] = {}
	for cell: Vector3i in cells:
		if not _valid_place(cell, prior, clearance) or prior.has(cell):
			return _rejected("foam needs clear, empty, supported cells above protected ground")
		prior[cell] = true
	var admitted: Dictionary = _admit(cells, metadata, "place", {"color": color, "expiry": expiry_tick, "clearance": clearance})
	if admitted.ok:
		_reserved_foam += cells.size()
	return admitted

func _valid_place(cell: Vector3i, planned: Dictionary[Vector3i, bool], clearance: Callable) -> bool:
	if not _data.is_in_bounds(cell) or cell.y <= 1 or _data.get_block(cell) != 0:
		return false
	if clearance.is_valid() and not bool(clearance.call(cell)):
		return false
	for direction: Vector3i in DIRECTIONS:
		if _data.get_block(cell + direction) != 0 or planned.has(cell + direction):
			return true
	return false

func expire_owned(tick: int) -> void:
	if not _synchronize():
		return
	for cell: Vector3i in _foam:
		_foam[cell].expiry = tick

func has_pending() -> bool:
	return _synchronize() and (not _jobs.is_empty() or not _active.is_empty() or not _foam.is_empty())

func drain_transactions() -> Array[Dictionary]:
	var result: Array[Dictionary] = _receipts
	_receipts = []
	return result

func _cell(index: int) -> Vector3i:
	var column: int = index / _data.dimensions.y
	return Vector3i(column % _data.dimensions.x, index % _data.dimensions.y, column / _data.dimensions.x)

func _has(marks: Dictionary[int, PackedByteArray], index: int) -> bool:
	var page: int = index / MARK_PAGE_BITS
	if not marks.has(page):
		return false
	var bit: int = index % MARK_PAGE_BITS
	return (marks[page][bit / 8] & (1 << (bit % 8))) != 0

func _mark(marks: Dictionary[int, PackedByteArray], index: int, enabled: bool = true) -> void:
	var page: int = index / MARK_PAGE_BITS
	var bytes: PackedByteArray = marks.get(page, PackedByteArray())
	if bytes.is_empty():
		bytes.resize(MARK_PAGE_BITS / 8)
	var bit: int = index % MARK_PAGE_BITS
	if enabled:
		bytes[bit / 8] |= 1 << (bit % 8)
	else:
		bytes[bit / 8] &= ~(1 << (bit % 8))
	marks[page] = bytes

func _seed(cell: Vector3i) -> void:
	if not _data.is_in_bounds(cell) or cell.y <= 1 or _data.get_block(cell) == 0:
		return
	var index: int = _data.index(cell)
	if not _has(_seed_marks, index):
		_mark(_seed_marks, index)
		_seeds.append(index)

func _push(index: int) -> void:
	if not _has(_visited, index):
		_mark(_visited, index)
		_stack.append(index)

func _finish_active(completed: bool) -> void:
	if completed:
		_completed += 1
	# Normally direct processing has released every guard already. An explicit
	# cancellation/failure releases at most the512 bounded input cells.
	for cell: Vector3i in _active.get("expected", {}):
		_release_guard(cell)
	_active = {}
	_phase = ""
	_offset = 0
	_seeds = PackedInt32Array()
	_seed_marks.clear()
	_stack = PackedInt32Array()
	_component = PackedInt32Array()
	_visited.clear()
	_checked.clear()
	_reseed_requested = false

func _start_active() -> void:
	_active = _jobs.pop_front()
	_offset = 0
	_phase = "direct"

func _metadata() -> Dictionary:
	var metadata: Dictionary = _active.metadata.duplicate()
	metadata.tick = maxi(_tick, _data.last_tick)
	return metadata

func _commit(changes: Array[Dictionary]) -> bool:
	if changes.is_empty():
		return true
	_own_commit = true
	var result: Dictionary = _data.commit_without_collapse(changes, _metadata())
	_own_commit = false
	if not result.ok:
		_last_error = String(result.error)
		return false
	_receipts.append(result)
	_last_changes += changes.size()
	return true

func _admit_expiry() -> void:
	if not can_queue():
		return
	var due: Array[Vector3i] = []
	var tokens: Dictionary[Vector3i, int] = {}
	for cell: Vector3i in _foam:
		var state: Dictionary = _foam[cell]
		if int(state.expiry) <= _tick and not bool(state.get("queued", false)):
			due.append(cell)
			tokens[cell] = int(state.token)
	if due.is_empty():
		return
	var result: Dictionary = _admit(due, {"tick": maxi(_tick, _data.last_tick), "actor_id": 0}, "expire", {"tokens": tokens})
	if result.ok:
		for cell: Vector3i in due:
			_foam[cell].queued = true

func step(tick: int) -> void:
	_last_work = 0
	_last_changes = 0
	if not _synchronize() or tick < _tick or tick < _data.last_tick or tick == _last_step_tick:
		return
	_tick = tick
	_last_step_tick = tick
	var started: int = Time.get_ticks_usec()
	_admit_expiry()
	while _last_work < MAX_WORK_PER_STEP and _last_changes < MAX_CHANGES_PER_STEP and _receipts.size() < MAX_RECEIPTS:
		if _active.is_empty():
			if _jobs.is_empty():
				break
			_start_active()
		if _reseed_requested:
			_phase = "reseed"
			_offset = 0
			_checked.clear()
			_reseed_requested = false
			_rescans += 1
		match _phase:
			"direct":
				_direct_step()
			"seed":
				_seed_step()
			"scan":
				_scan_step()
			"collapse":
				_collapse_step()
			"mark":
				_mark_step()
			"reseed":
				_reseed_step()
			_:
				_last_error = "invalid cooperative phase"
				_finish_active(false)
	_max_work = maxi(_max_work, _last_work)
	_max_changes = maxi(_max_changes, _last_changes)
	_max_step_usec = maxi(_max_step_usec, Time.get_ticks_usec() - started)

func _direct_step() -> void:
	var cells: Array[Vector3i] = _active.cells
	var changes: Array[Dictionary] = []
	var placed: Array[Vector3i] = []
	var planned: Dictionary[Vector3i, bool] = {}
	while _offset < cells.size() and _last_work < MAX_WORK_PER_STEP and _last_changes + changes.size() < MAX_CHANGES_PER_STEP:
		var cell: Vector3i = cells[_offset]
		_offset += 1
		_last_work += 1
		if not _data.is_in_bounds(cell) or cell.y <= 1:
			continue
		var before: int = _data.get_block(cell)
		if String(_active.kind) == "remove":
			var expected: Dictionary = _active.expected.get(cell, {})
			if expected.is_empty():
				continue
			var guard: Dictionary = _guards.get(cell, {})
			var unchanged: bool = not guard.is_empty() and before == int(expected.color) and int(guard.version) == int(expected.version)
			_active.expected.erase(cell)
			_release_guard(cell)
			if not unchanged:
				continue
		if String(_active.kind) == "place":
			_reserved_foam -= 1
			if _tick >= int(_active.expiry) or not _valid_place(cell, planned, _active.clearance):
				continue
			changes.append({"cell": cell, "before": 0, "after": int(_active.color), "flags": 0})
			planned[cell] = true
			placed.append(cell)
		elif before != 0 and not planned.has(cell):
			if String(_active.kind) == "expire":
				var owner: Dictionary = _foam.get(cell, {})
				if owner.is_empty() or int(owner.token) != int(_active.tokens.get(cell, -1)):
					continue
			changes.append({"cell": cell, "before": before, "after": 0, "flags": 0})
			planned[cell] = true
	if not _commit(changes):
		_finish_active(false)
		return
	for cell: Vector3i in placed:
		_foam[cell] = {"token": int(_active.id), "color": int(_active.color), "expiry": int(_active.expiry), "queued": false}
	for change: Dictionary in changes:
		if int(change.after) == 0:
			for direction: Vector3i in DIRECTIONS:
				_seed(Vector3i(change.cell) + direction)
	if _offset >= cells.size():
		if String(_active.kind) == "place":
			_finish_active(true)
		else:
			_phase = "seed"
			_offset = 0

func _seed_step() -> void:
	if _seeds.is_empty():
		_finish_active(true)
		return
	var index: int = _seeds[-1]
	_seeds.resize(_seeds.size() - 1)
	_mark(_seed_marks, index, false)
	_last_work += 1
	if _data.blocks[index] == 0 or _has(_checked, index):
		return
	_stack = PackedInt32Array()
	_component = PackedInt32Array()
	_visited.clear()
	_push(index)
	_phase = "scan"

func _scan_step() -> void:
	if _stack.is_empty():
		_phase = "collapse"
		_offset = 0
		return
	var index: int = _stack[-1]
	_stack.resize(_stack.size() - 1)
	_last_work += 1
	if _data.blocks[index] == 0:
		return
	_component.append(index)
	var cell: Vector3i = _cell(index)
	if cell.y <= 1 or _has(_checked, index):
		_phase = "mark"
		_offset = 0
		return
	# Reverse pushes retain source downward-priority traversal without index wrap.
	for ordinal: int in range(DIRECTIONS.size() - 1, -1, -1):
		var neighbor: Vector3i = cell + DIRECTIONS[ordinal]
		if _data.is_in_bounds(neighbor) and _data.get_block(neighbor) != 0:
			_push(_data.index(neighbor))

func _mark_step() -> void:
	if _offset >= _component.size():
		_component = PackedInt32Array()
		_stack = PackedInt32Array()
		_visited.clear()
		_phase = "seed"
		return
	_mark(_checked, _component[_offset])
	_offset += 1
	_last_work += 1

func _collapse_step() -> void:
	var changes: Array[Dictionary] = []
	while _offset < _component.size() and _last_work < MAX_WORK_PER_STEP and _last_changes + changes.size() < MAX_CHANGES_PER_STEP:
		var index: int = _component[_offset]
		_offset += 1
		_last_work += 1
		var cell: Vector3i = _cell(index)
		var before: int = _data.get_block(cell)
		if before != 0 and cell.y > 1:
			changes.append({"cell": cell, "before": before, "after": 0, "flags": 1})
	if not _commit(changes):
		_finish_active(false)
		return
	if _offset >= _component.size():
		_component = PackedInt32Array()
		_visited.clear()
		_phase = "seed"

func _reseed_step() -> void:
	# Preserve not-yet-visited frontier roots too: a concurrent cut may separate
	# them from the already visited members. Each requeue consumes one work unit.
	if not _stack.is_empty():
		var index: int = _stack[-1]
		_stack.resize(_stack.size() - 1)
		_seed(_cell(index))
		_last_work += 1
		return
	if _offset >= _component.size():
		_component = PackedInt32Array()
		_visited.clear()
		_phase = "seed"
		_offset = 0
		return
	_seed(_cell(_component[_offset]))
	_offset += 1
	_last_work += 1

func _on_cells_committed(changes: Array) -> void:
	for change: Dictionary in changes:
		if _guards.has(change.cell):
			_guards[change.cell].version += 1
		# A remove/build of the same RGB destroys the ownership token immediately.
		_foam.erase(change.cell)
	if _own_commit or _active.is_empty():
		return
	_checked.clear()
	if _phase not in ["scan", "collapse", "mark"]:
		return
	for change: Dictionary in changes:
		var cell: Vector3i = change.cell
		if _has(_visited, _data.index(cell)):
			_reseed_requested = true
			return
		if int(change.before) == 0 and int(change.after) != 0:
			for direction: Vector3i in DIRECTIONS:
				var neighbor: Vector3i = cell + direction
				if _data.is_in_bounds(neighbor) and _has(_visited, _data.index(neighbor)):
					_reseed_requested = true
					return

func get_diagnostics() -> Dictionary:
	return {"jobs": _jobs.size() + (0 if _active.is_empty() else 1), "foam_cells": _foam.size(), "reserved_foam": _reserved_foam, "guard_cells": _guards.size(), "retained_receipts": _receipts.size(), "phase": _phase, "component_cells": _component.size(), "frontier_cells": _stack.size(), "seed_cells": _seeds.size(), "mark_pages": _visited.size() + _checked.size() + _seed_marks.size(), "last_work": _last_work, "last_changes": _last_changes, "max_work": _max_work, "max_changes": _max_changes, "max_step_usec": _max_step_usec, "completed": _completed, "cancelled": _cancelled, "rescans": _rescans, "error": _last_error, "epoch": _epoch, "generation": _generation, "tick": _tick}
