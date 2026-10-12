extends SceneTree
## Real map authority, ownership and cooperative-completion fixtures.

const DATA = preload("res://world/voxel_data.gd")
const TERRAIN = preload("res://world/arsenal_terrain.gd")
const RED: int = 0x01cc3311
const FOAM: int = 0x0144ddff
var assertions: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("ARSENAL TERRAIN: " + message)

func fresh(size: Vector3i = Vector3i(16, 16, 16)) -> VoxelData:
	var data: VoxelData = DATA.new()
	check(data.clear(size, 17) == OK, "fixture map initializes")
	data.seed_box(Vector3i.ZERO, Vector3i(size.x, 2, size.z), RED)
	return data

func helper(data: VoxelData) -> TERRAIN:
	var terrain: TERRAIN = TERRAIN.new()
	terrain.configure(data)
	return terrain

func meta(tick: int = 0) -> Dictionary:
	return {"tick": tick, "actor_id": 2, "action_id": 37}

func settle(terrain: TERRAIN, start_tick: int = 1, limit: int = 400, replica: VoxelData = null) -> int:
	var tick: int = start_tick
	while terrain.has_pending() and tick < start_tick + limit:
		terrain.step(tick)
		var diagnostics: Dictionary = terrain.get_diagnostics()
		check(int(diagnostics.last_work) <= TERRAIN.MAX_WORK_PER_STEP, "each fixed tick bounds all scan/seed/reseed/removal cell work")
		check(int(diagnostics.last_changes) <= TERRAIN.MAX_CHANGES_PER_STEP, "each fixed tick bounds canonical changed cells")
		for transaction: Dictionary in terrain.drain_transactions():
			check(transaction.ok and transaction.changed and transaction.changes.size() <= 256, "bounded canonical receipt")
			if replica != null:
				check(replica.apply_transaction(transaction).ok, "independent presentation replica accepts every receipt exactly once")
				if int(transaction.map_sequence) == 1:
					check(not replica.apply_transaction(transaction).ok, "duplicate canonical receipt is rejected instead of applying terrain twice")
		tick += 1
	check(not terrain.has_pending(), "all accepted terrain work and finite foam complete")
	check(String(terrain.get_diagnostics().error).is_empty(), "completion has no silently rejected canonical transaction")
	return tick

func seam_checks() -> void:
	var data: VoxelData = fresh()
	var before: PackedInt32Array = data.blocks.duplicate()
	var invalid: Array[Dictionary] = [{"cell": Vector3i(2, 0, 2), "before": RED, "after": 0, "flags": 0}]
	check(not data.commit_without_collapse(invalid, meta()).ok and data.blocks == before, "bounded seam atomically rejects bedrock edits")
	invalid = [{"cell": Vector3i(2, 2, 2), "before": RED, "after": 0, "flags": 0}]
	check(not data.commit_without_collapse(invalid, meta()).ok and data.blocks == before, "bounded seam rejects before-color conflicts without writes")
	var too_many: Array[Dictionary] = []
	for ordinal: int in 257:
		too_many.append({"cell": Vector3i(2, 2, 2), "before": 0, "after": RED, "flags": 0})
	check(not data.commit_without_collapse(too_many, meta()).ok, "bounded seam rejects a257cell transaction")
	var terrain: TERRAIN = helper(data)
	var huge: Array[Vector3i] = []
	huge.resize(513)
	check(not terrain.queue_remove(huge, meta()).accepted, "input over512 rejected before admission")
	for ordinal: int in 8:
		check(terrain.queue_remove([Vector3i(ordinal, 1, 0)], meta()).accepted, "bounded eight-job admission")
	check(not terrain.can_queue() and not terrain.queue_remove([Vector3i(8, 1, 0)], meta()).accepted, "queue saturation keeps existing work and rejects additional job")
	settle(terrain)
	check(data.blocks == before and data.map_sequence == 0, "protected two bottom layers never change or create fake receipts")
	var readonly: VoxelData = data.frozen_copy() as VoxelData
	terrain.configure(readonly)
	check(not terrain.can_queue(), "immutable snapshot cannot become arsenal authority")

func supported_checks() -> void:
	var data: VoxelData = fresh()
	data.seed_box(Vector3i(3, 2, 5), Vector3i(4, 7, 6), RED)
	data.seed_box(Vector3i(11, 2, 5), Vector3i(12, 7, 6), RED)
	data.seed_box(Vector3i(3, 6, 5), Vector3i(12, 7, 6), FOAM)
	var terrain: TERRAIN = helper(data)
	check(terrain.queue_remove([Vector3i(3, 4, 5)], meta()).accepted, "first support cut accepted")
	var next: int = settle(terrain)
	check(data.get_block(Vector3i(7, 6, 5)) == FOAM, "roof remains with second connected support")
	check(terrain.queue_remove([Vector3i(11, 4, 5)], meta(next)).accepted, "last support cut accepted")
	settle(terrain, next)
	check(data.get_block(Vector3i(7, 6, 5)) == 0 and data.get_block(Vector3i(3, 2, 5)) == RED, "only disconnected roof and upper pillars collapse; rooted lower pillars remain")

func large_checks() -> void:
	var data: VoxelData = fresh(Vector3i(80, 20, 80))
	data.seed_box(Vector3i(40, 2, 40), Vector3i(41, 8, 41), RED)
	data.seed_box(Vector3i(8, 8, 8), Vector3i(72, 14, 72), FOAM)
	var replica: VoxelData = DATA.new()
	check(replica.load_snapshot_bytes(data.snapshot_bytes(), data.dimensions, data.epoch, 0) == OK, "large independent replica initializes")
	var terrain: TERRAIN = helper(data)
	check(terrain.queue_remove([Vector3i(40, 4, 40)], meta()).accepted, "one-cell cut detaches24576cell construction")
	var started: int = Time.get_ticks_usec()
	var next: int = settle(terrain, 1, 400, replica)
	var elapsed: int = Time.get_ticks_usec() - started
	check(data.blocks == replica.blocks and data.map_sequence == replica.map_sequence, "large canonical chunks converge without applying authority twice")
	check(data.get_block(Vector3i(60, 12, 60)) == 0 and data.get_block(Vector3i(40, 3, 40)) == RED, "whole large unsupported component completes; lower support remains")
	check(next > 2 and int(terrain.get_diagnostics().max_changes) <= 256, "large collapse is cooperative authority work, not one unbounded DFS")
	print("ARSENAL LARGE COLLAPSE: 24576 roof cells, %d fixed ticks, %d usec fixture total, %d usec max authority step, %d pages at completion" % [next - 1, elapsed, int(terrain.get_diagnostics().max_step_usec), int(terrain.get_diagnostics().mark_pages)])

func place_support(data: VoxelData, cell: Vector3i, tick: int) -> void:
	for y: int in range(2, cell.y):
		check(data.set_block(Vector3i(cell.x, y, cell.z), RED, meta(tick)).ok, "concurrent source building creates actual supported pillar")

func concurrent_checks() -> void:
	for during_removal: bool in [false, true]:
		var data: VoxelData = fresh(Vector3i(48, 16, 48))
		data.seed_box(Vector3i(24, 2, 24), Vector3i(25, 8, 25), RED)
		data.seed_box(Vector3i(4, 8, 4), Vector3i(44, 9, 44), FOAM)
		var terrain: TERRAIN = helper(data)
		check(terrain.queue_remove([Vector3i(24, 4, 24)], meta()).accepted, "concurrent fixture support cut admitted")
		var tick: int = 1
		while tick < 30:
			terrain.step(tick)
			terrain.drain_transactions()
			var phase: String = String(terrain.get_diagnostics().phase)
			if (during_removal and phase == "collapse") or (not during_removal and phase == "scan"):
				break
			tick += 1
		var safe: Vector3i = Vector3i(43, 8, 43)
		check(data.get_block(safe) == FOAM, "rescue target survives until concurrent building")
		place_support(data, safe, tick)
		settle(terrain, tick + 1)
		check(data.get_block(safe) == FOAM and data.get_block(safe + Vector3i.DOWN) == RED, "new supported structure is rescued during scan/removal")
		if during_removal:
			check(int(terrain.get_diagnostics().rescans) > 0, "touching topology changes during removal cause bounded revalidation")
	# Unrelated source building must not restart a large pending scan every tick.
	var data: VoxelData = fresh(Vector3i(48, 16, 48))
	data.seed_box(Vector3i(24, 2, 24), Vector3i(25, 8, 25), RED)
	data.seed_box(Vector3i(4, 8, 4), Vector3i(44, 9, 44), FOAM)
	var terrain: TERRAIN = helper(data)
	terrain.queue_remove([Vector3i(24, 4, 24)], meta())
	var tick: int = 1
	while terrain.has_pending() and tick < 100:
		data.set_block(Vector3i(tick % 40 + 4, 2, 1), FOAM, meta(tick))
		terrain.step(tick)
		terrain.drain_transactions()
		tick += 1
	check(not terrain.has_pending() and data.get_block(Vector3i(30, 8, 30)) == 0, "continuous unrelated source edits cannot postpone cleanup indefinitely")
	check(int(terrain.get_diagnostics().rescans) == 0, "unrelated construction does not restart component traversals")

func foam_checks() -> void:
	var data: VoxelData = fresh()
	var terrain: TERRAIN = helper(data)
	var wall: Array[Vector3i] = [Vector3i(4, 2, 4), Vector3i(4, 3, 4), Vector3i(4, 4, 4)]
	check(terrain.queue_place(wall, FOAM, 10, meta()).accepted, "supported finite real foam wall admitted")
	terrain.step(1)
	var receipts: Array[Dictionary] = terrain.drain_transactions()
	check(receipts.size() == 1 and data.get_block(wall[2]) == FOAM and int(terrain.get_diagnostics().foam_cells) == 3, "foam is one canonical solid placement, with ownership per actual cell")
	data.remove_blocks([wall[0]], true, meta(2))
	data.set_block(wall[0], FOAM, meta(2))
	check(int(terrain.get_diagnostics().foam_cells) == 0, "source removal including collapsedfoam invalidates every old ownership token")
	settle(terrain, 3, 20)
	check(data.get_block(wall[0]) == FOAM, "same-RGB source replacement survives old foam expiry")
	var other: Array[Vector3i] = [Vector3i(6, 2, 6), Vector3i(6, 3, 6)]
	check(terrain.queue_place(other, FOAM, 20, meta(4)).accepted, "second temporary wall admitted")
	terrain.step(5)
	terrain.drain_transactions()
	var sequence: int = data.map_sequence
	for ordinal: int in 20:
		check(data.map_sequence == sequence and data.get_block(other[0]) == FOAM, "without advanced fixed steps paused foam never expires")
	settle(terrain, 6, 30)
	check(data.get_block(other[0]) == 0 and data.get_block(other[1]) == 0, "expiry deletes exactly still-owned foam through cooperative canonical removal")
	check(not terrain.queue_place([Vector3i(8, 7, 8)], FOAM, 50, meta(30)).accepted, "airborne unsupported foam rejected")
	check(not terrain.queue_place([Vector3i(8, 2, 8)], FOAM, 50, meta(30), func(_cell_value: Vector3i) -> bool: return false).accepted, "actor-clearance veto rejects foam before admission")
	var gate: Array[bool] = [true]
	var clearance: Callable = func(_cell_value: Vector3i) -> bool: return gate[0]
	check(terrain.queue_place([Vector3i(8, 2, 8)], FOAM, 50, meta(30), clearance).accepted, "clearance checked at admission")
	gate[0] = false
	terrain.step(31)
	terrain.drain_transactions()
	check(data.get_block(Vector3i(8, 2, 8)) == 0 and int(terrain.get_diagnostics().reserved_foam) == 0, "live actor-clearance rechecked at canonical placement and reservation released")
	var many: Array[Vector3i] = []
	for x: int in range(9):
		for z: int in range(4):
			many.append(Vector3i(x + 1, 2, z + 10))
	check(terrain.queue_place(many, FOAM, 90, meta(32)).accepted, "all36foam cells can be reserved")
	check(not terrain.queue_place([Vector3i(12, 2, 12)], FOAM, 90, meta(32)).accepted, "pending reservations count against global36cell cap")
	terrain.step(33)
	terrain.drain_transactions()
	terrain.expire_owned(34)
	settle(terrain, 34)
	check(int(terrain.get_diagnostics().foam_cells) == 0, "explicit session cleanup expires owned foam in bounded jobs")

func map_checks() -> void:
	var data: VoxelData = fresh()
	data.seed_box(Vector3i(4, 2, 4), Vector3i(5, 6, 5), RED)
	var terrain: TERRAIN = helper(data)
	check(terrain.queue_remove([Vector3i(4, 2, 4)], meta()).accepted, "old-map delayed terrain job queued")
	var generation: int = data.generation
	data.clear(data.dimensions, data.epoch)
	data.seed_box(Vector3i.ZERO, Vector3i(16, 2, 16), RED)
	data.seed_box(Vector3i(4, 2, 4), Vector3i(5, 6, 5), RED)
	terrain.step(1)
	check(data.generation != generation and not terrain.has_pending() and data.get_block(Vector3i(4, 2, 4)) == RED and terrain.drain_transactions().is_empty(), "same-epoch replacement cancels old jobs without touching new map")
	terrain.queue_remove([Vector3i(4, 2, 4)], meta(1))
	terrain.step(2)
	var sequence: int = data.map_sequence
	terrain.step(2)
	check(data.map_sequence == sequence and int(terrain.get_diagnostics().last_work) == 0, "duplicate fixed tick cannot advance work or clocks")
	terrain.clear()
	check(data.get_block(Vector3i(4, 2, 4)) == 0, "clear cancels helper work and does not restore death/respawn terrain")
	check(data.cells_committed.is_connected(Callable(terrain, "_on_cells_committed")), "live helper retains mutation observer through non-adoption clear")
	terrain.dispose()
	check(not data.cells_committed.is_connected(Callable(terrain, "_on_cells_committed")) and not terrain.can_queue(), "teardown disconnects observer and releases authority data")
	check(data.get_block(Vector3i(4, 2, 4)) == 0, "disposing helper never restores canonical terrain")

func receipt_backpressure_checks() -> void:
	var data: VoxelData = fresh(Vector3i(32, 8, 8))
	data.seed_box(Vector3i(0, 2, 1), Vector3i(24, 3, 2), RED)
	var terrain: TERRAIN = helper(data)
	for tick: int in range(1, 17):
		check(terrain.queue_remove([Vector3i(tick - 1, 2, 1)], meta(tick)).accepted, "undrained presentation fixture admits bounded work")
		terrain.step(tick)
	check(int(terrain.get_diagnostics().retained_receipts) == 16, "canonical receipt retention is capped at16")
	check(terrain.queue_remove([Vector3i(16, 2, 1)], meta(17)).accepted, "additional authority job remains queued under presentation backpressure")
	terrain.step(17)
	check(data.get_block(Vector3i(16, 2, 1)) == RED and int(terrain.get_diagnostics().retained_receipts) == 16, "full receipts pause mutation without losing an accepted job")
	check(terrain.drain_transactions().size() == 16, "receipt drain transfers bounded canonical ownership once")
	settle(terrain, 18)
	check(data.get_block(Vector3i(16, 2, 1)) == 0, "presentation drain allows pending authority to complete")

func queued_replacement_checks() -> void:
	var data: VoxelData = fresh(Vector3i(32, 12, 32))
	data.seed_box(Vector3i(0, 2, 0), Vector3i(32, 3, 16), RED)
	var terrain: TERRAIN = helper(data)
	var cells: Array[Vector3i] = []
	for index: int in 512:
		cells.append(Vector3i(index % 32, 2, index / 32))
	check(terrain.queue_remove(cells, meta()).accepted and int(terrain.get_diagnostics().guard_cells) == 512, "bounded direct request captures all original cell identities")
	# Replace before any direct batch, then replace another cell in the delayed
	# second batch. Same RGB is deliberately used in both replacements.
	data.remove_blocks([cells[10]], true, meta(1))
	data.set_block(cells[10], RED, meta(1))
	terrain.step(1)
	terrain.drain_transactions()
	check(data.get_block(cells[10]) == RED and data.get_block(cells[400]) == RED, "first batch preserves new supported replacement and leaves later cut pending")
	data.remove_blocks([cells[400]], true, meta(2))
	data.set_block(cells[400], RED, meta(2))
	settle(terrain, 2)
	check(data.get_block(cells[400]) == RED and data.get_block(cells[10]) == RED and data.get_block(cells[401]) == 0, "second batch protects same-RGB source replacement while unchanged original cut still applies")
	check(int(terrain.get_diagnostics().guard_cells) == 0, "completed direct guard references are released")
	var empty: Vector3i = Vector3i(5, 2, 25)
	check(terrain.queue_remove([empty], meta(10)).accepted, "old air coordinate can be admitted without a fake edit")
	data.set_block(empty, RED, meta(10))
	settle(terrain, 10)
	check(data.get_block(empty) == RED, "a new block built into originally queued air is never damaged by an old blast")
	terrain.queue_remove([empty], meta(20))
	terrain.dispose()
	check(int(terrain.get_diagnostics().guard_cells) == 0, "teardown drops queued cell watches without terrain edits")

func differential_checks() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 0x7a3a71
	for ordinal: int in 12:
		var data: VoxelData = fresh(Vector3i(12, 12, 12))
		for z: int in range(2, 10):
			for x: int in range(2, 10):
				if rng.randf() < 0.6:
					data.seed_box(Vector3i(x, 2, z), Vector3i(x + 1, rng.randi_range(3, 10), z + 1), FOAM)
		var reference: VoxelData = DATA.new()
		reference.load_snapshot_bytes(data.snapshot_bytes(), data.dimensions, data.epoch, 0)
		var cuts: Array[Vector3i] = []
		for cut: int in 12:
			cuts.append(Vector3i(rng.randi_range(1, 10), rng.randi_range(0, 10), rng.randi_range(1, 10)))
		reference.remove_blocks(cuts, true, meta())
		var terrain: TERRAIN = helper(data)
		terrain.queue_remove(cuts, meta())
		settle(terrain)
		check(data.blocks == reference.blocks, "cooperative final occupancy/color matches source connected support semantics fixture%d" % ordinal)

func run() -> void:
	seam_checks()
	supported_checks()
	large_checks()
	concurrent_checks()
	foam_checks()
	map_checks()
	receipt_backpressure_checks()
	queued_replacement_checks()
	differential_checks()
	print("ARSENAL TERRAIN TESTS: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
