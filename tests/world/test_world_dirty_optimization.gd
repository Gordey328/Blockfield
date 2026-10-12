extends SceneTree
## Independent old nested-neighbor oracle, complete ordered dirty state and jobs.
const WORLD = preload("res://world/voxel_world.gd")
const DATA = preload("res://world/voxel_data.gd")
const PALETTE := 0x01aabbcc
var assertions: int = 0
var failures: int = 0
var benchmark: bool = false
var report_path: String = ""

class OriginalWorld extends WORLD:
	# Preserved pre-change invalidation order and water setter.
	func _mark_dirty(cell: Vector3i, geometry_changed: bool = true) -> void:
		if not geometry_changed:
			_queue_color_update(cell)
			return
		var native := dimensions == Vector3i(512,64,512)
		for z in range(cell.z-1,cell.z+2):
			for x in range(cell.x-1,cell.x+2):
				for y in range(cell.y-1,cell.y+2):
					var neighbor := Vector3i(posmod(x,dimensions.x) if native else x,y,posmod(z,dimensions.z) if native else z)
					if is_in_bounds(neighbor):_queue_geometry_update(_chunk_of(neighbor))
		if geometry_changed:
			_collision_dirty[_chunk_of(cell)] = true
			for direction: Vector3i in DIRECTIONS:
				var neighbor: Vector3i = cell+direction
				if is_in_bounds(neighbor):_collision_dirty[_chunk_of(neighbor)] = true
	func set_water_enabled(enabled: bool) -> void:
		water_enabled = enabled
		if is_instance_valid(_water_mesh):_water_mesh.visible = enabled
		if is_instance_valid(_wave_field):_wave_field.set_enabled(enabled and water_waves_enabled)
		if is_instance_valid(_reflection):_reflection.set_enabled(enabled and water_reflections_enabled)
		_mark_all_chunks(false)

class CountedWorld extends WORLD:
	var geometry_requests: int = 0
	func _queue_geometry_update(key: Vector3i) -> void:
		geometry_requests += 1
		super._queue_geometry_update(key)

class CustomWorld extends WORLD:
	var bound_calls: int = 0
	var mapping_calls: int = 0
	func is_in_bounds(cell: Vector3i) -> bool:
		bound_calls += 1
		return super.is_in_bounds(cell) and cell.x != 15
	func _chunk_of(cell: Vector3i) -> Vector3i:
		mapping_calls += 1
		var key := super._chunk_of(cell)
		return Vector3i(key.z,key.y,key.x)

class ReferenceCustomWorld extends OriginalWorld:
	var bound_calls: int = 0
	var mapping_calls: int = 0
	func is_in_bounds(cell: Vector3i) -> bool:
		bound_calls += 1
		return super.is_in_bounds(cell) and cell.x != 15
	func _chunk_of(cell: Vector3i) -> Vector3i:
		mapping_calls += 1
		var key := super._chunk_of(cell)
		return Vector3i(key.z,key.y,key.x)

class CustomData extends DATA:
	var bound_calls: int = 0
	func is_in_bounds(cell: Vector3i) -> bool:
		bound_calls += 1
		return super.is_in_bounds(cell) and cell.z != 15

class ReflectionSpy extends Node:
	var enabled: bool = false
	func set_enabled(value: bool) -> void:
		enabled = value

class NotifyingWorld extends WORLD:
	var mark_notifications: int = 0
	func _mark_all_chunks(geometry_changed: bool = true) -> void:
		mark_notifications += 1
		super._mark_all_chunks(geometry_changed)

class ReferenceNotifyingWorld extends OriginalWorld:
	var mark_notifications: int = 0
	func _mark_all_chunks(geometry_changed: bool = true) -> void:
		mark_notifications += 1
		super._mark_all_chunks(geometry_changed)

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--benchmark":benchmark = true
		elif argument.begins_with("--report="):report_path = argument.trim_prefix("--report=")
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("WORLD DIRTY OPTIMIZATION: "+message)

func pair(size: Vector3i) -> Array[VoxelWorld]:
	var candidate: VoxelWorld = WORLD.new()
	var reference: VoxelWorld = OriginalWorld.new()
	for world: VoxelWorld in [candidate,reference]:
		world.clear_world(size)
		world.visual_effects_enabled = false
		world.set_process(false)
	return [candidate,reference]

func dirty_snapshot(world: VoxelWorld) -> Array:
	var colors: Array = []
	for key: Vector3i in world._color_dirty:
		colors.append([key,world._color_dirty[key].keys()])
	return [world._dirty.keys(),world._geometry_dirty.keys(),world._collision_dirty.keys(),colors,
		world._active_chunk != null,world._active_key,int(world._rebuild_stats.build_cancellations)]

func discard_dirty(world: VoxelWorld) -> void:
	world._dirty.clear()
	world._geometry_dirty.clear()
	world._collision_dirty.clear()
	world._color_dirty.clear()

func boundary_checks() -> void:
	for size: Vector3i in [Vector3i(1,1,1),Vector3i(1,2,1),Vector3i(16,16,16),Vector3i(17,17,17),Vector3i(32,31,31),Vector3i(171,61,165),Vector3i(512,64,512)]:
		var worlds := pair(size)
		var x_values: Array[int] = [0,1,14,15,16,17,size.x-2,size.x-1]
		var y_values: Array[int] = [0,1,14,15,16,17,size.y-2,size.y-1]
		var z_values: Array[int] = [0,1,14,15,16,17,size.z-2,size.z-1]
		for z: int in z_values:
			for x: int in x_values:
				for y: int in y_values:
					var cell := Vector3i(x,y,z)
					if not worlds[0].is_in_bounds(cell):continue
					for world: VoxelWorld in worlds:
						discard_dirty(world)
						world._mark_dirty(cell)
					check(dirty_snapshot(worlds[0]) == dirty_snapshot(worlds[1]),"full ordered geometry/collision keys at %s:%s" % [size,cell])
		for world: VoxelWorld in worlds:world.free()

func transaction_checks() -> void:
	var worlds := pair(Vector3i(48,32,48))
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x71d17e
	for ordinal: int in range(120):
		var changes: Array = []
		for index: int in range(1+ordinal%24):
			var cell := Vector3i(rng.randi_range(0,47),rng.randi_range(1,31),rng.randi_range(0,47))
			changes.append({"cell":cell,"before":PALETTE,"after":0 if index%3 else 0x01bbccdd,"flags":0})
		var transaction := {"ok":true,"changed":true,"changes":changes,"collapse_groups":[]}
		for world: VoxelWorld in worlds:world._present_transaction(transaction)
		check(dirty_snapshot(worlds[0]) == dirty_snapshot(worlds[1]),"complete ordered mixed paint/removal transaction %d" % ordinal)
		# A queued topology change must erase a later palette request even when
		# the same geometry key was already present in an earlier transaction.
		var repeated := Vector3i(15,15,15)
		for world: VoxelWorld in worlds:
			world._queue_color_update(repeated)
			world._mark_dirty(repeated)
		check(dirty_snapshot(worlds[0]) == dirty_snapshot(worlds[1]) and not worlds[0]._color_dirty.has(Vector3i.ZERO),"late geometry supersedes colors %d" % ordinal)
	for world: VoxelWorld in worlds:world.free()
	var counted := CountedWorld.new()
	counted.clear_world(Vector3i(32,32,32))
	counted._mark_dirty(Vector3i(4,4,4))
	check(counted.geometry_requests == 27,"World subclass retains every original virtual queue call")
	for repeat: int in 100:counted._mark_dirty(Vector3i(5,5,5))
	check(counted.geometry_requests == 2727,"repeated subclass edits retain original queue-call effects")
	counted.free()

func override_checks() -> void:
	var candidate := CustomWorld.new()
	var reference := ReferenceCustomWorld.new()
	for world: VoxelWorld in [candidate,reference]:world.clear_world(Vector3i(48,32,48))
	for cell: Vector3i in [Vector3i(4,4,20),Vector3i(15,15,15),Vector3i(16,16,16),Vector3i(0,1,0),Vector3i(47,31,47)]:
		candidate._mark_dirty(cell)
		reference._mark_dirty(cell)
		check(dirty_snapshot(candidate) == dirty_snapshot(reference),"custom World bounds and chunk mapping preserve complete ordered state")
		check(candidate.bound_calls == reference.bound_calls and candidate.mapping_calls == reference.mapping_calls,"custom World retains every virtual bounds/mapping call")
	candidate.free()
	reference.free()
	var worlds := pair(Vector3i(48,32,48))
	for world: VoxelWorld in worlds:
		var custom := CustomData.new()
		custom.clear(Vector3i(48,32,48),7)
		world.data = custom
	for cell: Vector3i in [Vector3i(15,15,15),Vector3i(16,16,16),Vector3i(4,4,20),Vector3i(0,1,0),Vector3i(47,31,47)]:
		for world: VoxelWorld in worlds:world._mark_dirty(cell)
		check(dirty_snapshot(worlds[0]) == dirty_snapshot(worlds[1]),"custom Data bounds preserve complete ordered geometry/collision")
		check((worlds[0].data as CustomData).bound_calls == (worlds[1].data as CustomData).bound_calls,"custom Data retains every original bounds predicate call")
	for world: VoxelWorld in worlds:world.free()
	var notification: NotifyingWorld = NotifyingWorld.new()
	var notification_reference: ReferenceNotifyingWorld = ReferenceNotifyingWorld.new()
	for world: VoxelWorld in [notification,notification_reference]:world.clear_world(Vector3i(32,32,32))
	for enabled: bool in [true,true,false,false,true,true]:
		notification.set_water_enabled(enabled)
		notification_reference.set_water_enabled(enabled)
		check(notification.mark_notifications == notification_reference.mark_notifications,"custom World receives every repeated water full-mark notification")
		check(dirty_snapshot(notification) == dirty_snapshot(notification_reference),"custom water notification preserves complete original ordered dirty state")
	notification.free()
	notification_reference.free()

func lifecycle_checks() -> void:
	var worlds := pair(Vector3i(32,32,32))
	for world: VoxelWorld in worlds:
		world._ensure_material()
		world._mark_dirty(Vector3i(4,4,4))
		world.process_rebuild_work(1,1000000)
		world._queue_color_update(Vector3i(4,4,4))
	check(worlds[0]._active_chunk != null and worlds[1]._active_chunk != null,"one unit starts unpublished sampled geometry jobs")
	var candidate_old: WeakRef = weakref(worlds[0]._active_chunk)
	var reference_old: WeakRef = weakref(worlds[1]._active_chunk)
	for world: VoxelWorld in worlds:world._mark_dirty(Vector3i(4,4,4))
	check(dirty_snapshot(worlds[0]) == dirty_snapshot(worlds[1]),"active geometry cancellation and color erasure exactly match original")
	check(candidate_old.get_ref() == null and reference_old.get_ref() == null and int(worlds[0]._rebuild_stats.build_cancellations) == 1,"cancelled detached jobs are freed exactly once")
	for world: VoxelWorld in worlds:
		world.data.seed_box(Vector3i(4,4,4),Vector3i(5,5,5),PALETTE)
		world.rebuild_now()
		world._mark_dirty(Vector3i(4,4,4))
		world.process_rebuild_work(1,1000000)
	var candidate_chunk: VoxelChunk = worlds[0]._active_chunk
	var reference_chunk: VoxelChunk = worlds[1]._active_chunk
	var candidate_mesh: Mesh = candidate_chunk.mesh_instance.mesh
	var reference_mesh: Mesh = reference_chunk.mesh_instance.mesh
	for world: VoxelWorld in worlds:world._mark_dirty(Vector3i(4,4,4))
	check(dirty_snapshot(worlds[0]) == dirty_snapshot(worlds[1]),"published chunk cancellation preserves original dirty lifecycle")
	check(is_instance_valid(candidate_chunk) and is_instance_valid(reference_chunk) and candidate_chunk.mesh_instance.mesh == candidate_mesh and reference_chunk.mesh_instance.mesh == reference_mesh,"stale job cancellation retains last published mesh and collider")
	for world: VoxelWorld in worlds:world.free()

func water_checks() -> void:
	var worlds := pair(Vector3i(16,16,16))
	for world: VoxelWorld in worlds:
		world._ensure_material()
		world._create_water(false)
		world.water_reflections_enabled = true
		var reflection := ReflectionSpy.new()
		world.add_child(reflection)
		world._reflection = reflection
		world.rebuild_now()
		world.set_water_enabled(false)
	check(dirty_snapshot(worlds[0]) == dirty_snapshot(worlds[1]),"changed water value retains original ordered geometry invalidation")
	check(not worlds[0]._water_mesh.visible and not worlds[1]._water_mesh.visible,"changed false value hides both water planes")
	check(not worlds[0]._wave_field.is_processing() and not worlds[1]._wave_field.is_processing(),"changed false value pauses both wave fields")
	check(not (worlds[0]._reflection as ReflectionSpy).enabled and not (worlds[1]._reflection as ReflectionSpy).enabled,"changed false value disables both reflections")
	for world: VoxelWorld in worlds:world.rebuild_now()
	var mesh: Mesh = worlds[0]._chunks[Vector3i.ZERO].mesh_instance.mesh
	worlds[0].set_water_enabled(false)
	check(worlds[0]._dirty.is_empty() and not worlds[0]._water_mesh.visible and worlds[0]._chunks[Vector3i.ZERO].mesh_instance.mesh == mesh,"same water value retains visible state and enqueues no geometry")
	# Changed values still propagate to water mesh, waves and reflection.
	for world: VoxelWorld in worlds:world.set_water_enabled(true)
	check(dirty_snapshot(worlds[0]) == dirty_snapshot(worlds[1]),"changed true value retains complete original ordered invalidation")
	check(worlds[0]._water_mesh.visible and worlds[1]._water_mesh.visible,"reenabling water restores both planes")
	check(worlds[0]._wave_field.is_processing() and worlds[1]._wave_field.is_processing(),"changed true value resumes both wave fields")
	check((worlds[0]._reflection as ReflectionSpy).enabled and (worlds[1]._reflection as ReflectionSpy).enabled,"changed true value enables both reflections")
	worlds[0].process_rebuild_work(1,1000000)
	var active: VoxelChunk = worlds[0]._active_chunk
	var retained: Array = dirty_snapshot(worlds[0])
	worlds[0].set_water_enabled(true)
	check(active != null and worlds[0]._active_chunk == active and dirty_snapshot(worlds[0]) == retained,"unchanged water keeps in-progress sampled job without cancellation")
	for world: VoxelWorld in worlds:world.free()

func raw_water_checks() -> void:
	var worlds := pair(Vector3i(16,16,16))
	for world: VoxelWorld in worlds:
		world._ensure_material()
		world._create_water(false)
		var reflection := ReflectionSpy.new()
		world.add_child(reflection)
		world._reflection = reflection
		world.water_reflections_enabled = true
		world.data.seed_box(Vector3i.ZERO,Vector3i(16,1,16),PALETTE)
		world._mark_all_chunks()
		world.rebuild_now()
		world.set_water_enabled(true)
		world.rebuild_now()
	for enabled: bool in [false,true,false,true]:
		for world: VoxelWorld in worlds:
			world._mark_dirty(Vector3i(4,4,4))
			world.process_rebuild_work(1,1000000)
			world.water_enabled = enabled
			world.set_water_enabled(enabled)
		check(dirty_snapshot(worlds[0]) == dirty_snapshot(worlds[1]),"raw property assignment reconciles ordered geometry and active cancellation")
		check(worlds[0]._water_mesh.visible == enabled and worlds[0]._wave_field.is_processing() == enabled and (worlds[0]._reflection as ReflectionSpy).enabled == enabled,"raw property assignment reconciles water mesh/waves/reflection")
		check(worlds[0]._active_chunk == null and worlds[1]._active_chunk == null,"raw changed state cancels previously sampled active geometry")
		for world: VoxelWorld in worlds:world.rebuild_now()
		var candidate_chunk: VoxelChunk = worlds[0]._chunks[Vector3i.ZERO]
		var reference_chunk: VoxelChunk = worlds[1]._chunks[Vector3i.ZERO]
		check(candidate_chunk.face_count == reference_chunk.face_count and candidate_chunk.collision_face_count == reference_chunk.collision_face_count,"raw assignment rebuild preserves original water-floor face behavior")
	# Reconcile resource fields even when the applied geometry state is current.
	worlds[0]._water_mesh.hide()
	worlds[0]._wave_field.set_enabled(false)
	(worlds[0]._reflection as ReflectionSpy).enabled = false
	worlds[0].set_water_enabled(true)
	check(worlds[0]._dirty.is_empty() and worlds[0]._water_mesh.visible and worlds[0]._wave_field.is_processing() and (worlds[0]._reflection as ReflectionSpy).enabled,"same applied state repairs resource visibility without rebuilding faces")
	# If a raw intermediate value was sampled, changing it back cannot retain
	# that mixed job merely because it matches the last requested global state.
	for world: VoxelWorld in worlds:
		world._mark_dirty(Vector3i(4,4,4))
		world.water_enabled = false
		world.process_rebuild_work(1,1000000)
		world.water_enabled = true
		world.set_water_enabled(true)
	check(dirty_snapshot(worlds[0]) == dirty_snapshot(worlds[1]) and worlds[0]._active_chunk == null,"raw value sampled then restored forces complete geometry reconciliation")
	for world: VoxelWorld in worlds:world.free()
	# Direct assignment before any resources exist establishes the first requested
	# geometry state; resource creation subsequently reads that same raw property.
	var fresh := WORLD.new()
	fresh.clear_world(Vector3i(16,16,16))
	fresh.water_enabled = false
	fresh.set_water_enabled(false)
	check(fresh._water_geometry_state == 0 and not fresh._dirty.is_empty(),"raw pre-creation assignment establishes requested geometry state")
	fresh._create_water(false)
	check(not fresh._water_mesh.visible and not fresh._wave_field.is_processing(),"new resources respect pre-creation raw water value")
	fresh.free()

func benchmark_dirty() -> void:
	var rows: Array[Dictionary] = []
	for side: int in [20,80]:
		var worlds := pair(Vector3i(96,48,96))
		var transaction := {"ok":true,"changed":true,"changes":[],"collapse_groups":[]}
		for z: int in range(8,8+side):
			for x: int in range(8,8+side):
				for y: int in range(30,34):
					transaction.changes.append({"cell":Vector3i(x,y,z),"before":PALETTE,"after":0,"flags":1})
		var samples: Array[Dictionary] = []
		for repeat: int in range(7):
			for world: VoxelWorld in worlds:discard_dirty(world)
			var candidate_usec: int = 0
			var reference_usec: int = 0
			for index: int in ([1,0] if repeat%2 == 0 else [0,1]):
				var started: int = Time.get_ticks_usec()
				worlds[index]._present_transaction(transaction)
				var elapsed: int = Time.get_ticks_usec()-started
				if index == 0:candidate_usec = elapsed
				else:reference_usec = elapsed
			var exact: bool = dirty_snapshot(worlds[0]) == dirty_snapshot(worlds[1])
			check(exact,"measured batch preserves complete ordered invalidation")
			samples.append({"candidate_usec":candidate_usec,"reference_usec":reference_usec,"exact":exact})
		rows.append({"changes":transaction.changes.size(),"samples":samples})
		for world: VoxelWorld in worlds:world.free()
	var report := {"engine":Engine.get_version_info().string,"method":"paired native World invalidation CPU, same changes and ordered queues; excludes collapse, meshing, GPU and rendered FPS","rows":rows,"failures":failures}
	if not report_path.is_empty():
		var file := FileAccess.open(report_path,FileAccess.WRITE)
		if file != null:file.store_string(JSON.stringify(report,"\t"))
	print("WORLD DIRTY BENCHMARK: "+JSON.stringify(report))

func run() -> void:
	boundary_checks()
	transaction_checks()
	override_checks()
	lifecycle_checks()
	water_checks()
	raw_water_checks()
	if benchmark:benchmark_dirty()
	await process_frame
	print("WORLD DIRTY OPTIMIZATION: %d assertions, %d failures" % [assertions,failures])
	quit(1 if failures else 0)
