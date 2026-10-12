extends "res://world/voxel_chunk.gd"
## Benchmark oracle: preserved halo completion from d5516eb2bfd22bd5d03f32ac751dce7c01086876.

func _build_halo_columns(world: Node3D, max_units: int, deadline_usec: int) -> int:
	var job := _job
	var base := job.base
	var size := job.size
	var water := job.water
	var native := job.native
	var map_blocks: PackedInt32Array = world._blocks
	var blocks := job.blocks
	var solids := job.solids
	job.blocks = PackedInt32Array()
	job.solids = PackedByteArray()
	var processed := 0
	var max_unit := 0
	var now := Time.get_ticks_usec()
	while job.cursor < AO.HALO_SIZE * AO.HALO_SIZE and (max_units <= 0 or processed < max_units) and (deadline_usec <= 0 or now < deadline_usec):
		var unit_started := now
		var x := base.x + job.cursor % AO.HALO_SIZE - 1
		var z := base.z + job.cursor / AO.HALO_SIZE - 1
		var valid := x >= 0 and x < size.x and z >= 0 and z < size.z
		var column := size.y * (x + size.x * z)
		var ao_column := size.y * (posmod(x, size.x) + size.x * posmod(z, size.z)) if native else column
		var first := job.cursor * AO.HALO_SIZE
		for hy in range(AO.HALO_SIZE):
			var y := base.y + hy - 1
			if valid and y >= 0 and y < size.y:
				blocks[first + hy] = map_blocks[column + y]
			if y < 0:
				solids[first + hy] = 1
			elif y < size.y and (valid or native):
				var sample_y := 1 if water and y == 0 and size.y > 1 else y
				solids[first + hy] = 1 if map_blocks[ao_column + sample_y] != 0 else 0
		job.cursor += 1
		processed += 1
		now = Time.get_ticks_usec()
		max_unit = maxi(max_unit, now - unit_started)
	job.blocks = blocks
	job.solids = solids
	if job.cursor == AO.HALO_SIZE * AO.HALO_SIZE:
		job.stage = 1
		job.cursor = 0
	_batch_max_unit_usec = maxi(_batch_max_unit_usec, max_unit)
	return processed

