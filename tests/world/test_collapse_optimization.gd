extends SceneTree
## Ordered differential authority checks against the retained original algorithm.
const DATA = preload("res://world/voxel_data.gd")
const REFERENCE = preload("res://../tests/world/collapse_reference.gd")
var assertions := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("COLLAPSE OPTIMIZATION: " + message)

func compare(reference: RefCounted, candidate: RefCounted, cuts: Array[Vector3i], protected: bool, tick: int, label: String) -> void:
	var metadata := {"tick":tick,"actor_id":5,"action_id":tick + 1}
	var expected: Dictionary = reference.remove_blocks(cuts, protected, metadata)
	var actual: Dictionary = candidate.remove_blocks(cuts, protected, metadata)
	check(actual == expected, label + " preserves complete transaction, DFS changes and ordered component/color groups")
	check(candidate.blocks == reference.blocks, label + " preserves exact intrinsic occupancy/color")
	check(candidate.get_journal_stats() == reference.get_journal_stats(), label + " preserves bounded history identity/counts")
	check(candidate.transactions_since(maxi(0,candidate.map_sequence-1)) == reference.transactions_since(maxi(0,reference.map_sequence-1)), label + " preserves independent retained transaction")

func copy_pair(size: Vector3i, values: PackedInt32Array) -> Array[RefCounted]:
	var reference: RefCounted = REFERENCE.new()
	var candidate: RefCounted = DATA.new()
	check(reference.clear(size,7) == OK and candidate.clear(size,7) == OK, "valid independent fixture dimensions")
	reference.blocks = values.duplicate()
	candidate.blocks = values.duplicate()
	return [reference,candidate]

func boundary_checks() -> void:
	for size: Vector3i in [Vector3i(1,1,1),Vector3i(1,2,1),Vector3i(1,8,1),Vector3i(8,8,1),Vector3i(1,8,8),Vector3i(9,8,11)]:
		var values := PackedInt32Array()
		values.resize(size.x*size.y*size.z)
		values.fill(0x01000000)
		var pair := copy_pair(size,values)
		var corners: Array[Vector3i] = [Vector3i(0,2,0),Vector3i(size.x-1,2,size.z-1),Vector3i(size.x-1,size.y-1,0),Vector3i(0,size.y-1,size.z-1),Vector3i(-1,2,0),Vector3i(size.x,2,0)]
		for ordinal: int in corners.size():
			compare(pair[0],pair[1],[corners[ordinal],corners[ordinal]],ordinal%2 == 1,ordinal,"boundary %s cut%d" % [size,ordinal])
	# Neighbors separated only by a packed-array edge must never join. The
	# isolated top corner and distant bottom support are adjacent in storage.
	var values := PackedInt32Array()
	values.resize(4*8*4)
	values[7] = 0x01000000
	values[8] = 0x01ee7711
	values[6] = 0x014488ee
	values[4*8-1] = 0x01ff0088
	values[4*8] = 0x01ffffff
	var pair := copy_pair(Vector3i(4,8,4),values)
	compare(pair[0],pair[1],[Vector3i(0,6,0)],false,1,"column and plane wrap guard")
	# Multiple unsupported groups and a supported component share the removal.
	var seed: RefCounted = DATA.new()
	seed.clear(Vector3i(20,12,20),7)
	seed.seed_box(Vector3i.ZERO,Vector3i(20,2,20),0x01000000)
	seed.seed_box(Vector3i(9,2,9),Vector3i(10,8,10),0x01eeeeee)
	seed.seed_box(Vector3i(2,7,9),Vector3i(18,8,10),0x01123456)
	seed.seed_box(Vector3i(9,7,2),Vector3i(10,8,18),0x01654321)
	pair = copy_pair(seed.dimensions,seed.blocks)
	compare(pair[0],pair[1],[Vector3i(9,7,9)],false,1,"four split roof arms and surviving support")
	check(pair[1].get_block(Vector3i(9,2,9)) != 0,"supported pillar remains after arms collapse")

func seeded_checks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5147c011
	for fixture: int in 120:
		var size := Vector3i(rng.randi_range(1,14),rng.randi_range(3,12),rng.randi_range(1,14))
		var values := PackedInt32Array()
		values.resize(size.x*size.y*size.z)
		for index: int in values.size():
			if rng.randf() < (0.2 + float(fixture%5)*0.16):
				values[index] = 0x01000000 | (rng.randi() & 0xffffff)
		var pair := copy_pair(size,values)
		for action: int in 16:
			var cuts: Array[Vector3i] = []
			for ordinal: int in rng.randi_range(1,9):
				cuts.append(Vector3i(rng.randi_range(-1,size.x),rng.randi_range(0,size.y),rng.randi_range(-1,size.z)))
			compare(pair[0],pair[1],cuts,action%3 == 0,action,"seeded map%d action%d" % [fixture,action])

func run() -> void:
	boundary_checks()
	seeded_checks()
	print("COLLAPSE OPTIMIZATION TESTS: %d assertions, %d failures" % [assertions,failures])
	quit(1 if failures else 0)
