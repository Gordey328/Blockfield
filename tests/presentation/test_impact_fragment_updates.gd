extends SceneTree
## Accepted budget: real-time analytical motion, no terrain queries or hidden
## fragment sprites, one update per active slot per frame.
const EFFECTS = preload("res://presentation/openspades_effects.gd")
var assertions: int = 0
var failures: int = 0

class FloorWorld extends Node3D:
	var water_level: float = -100.0
	var queries: int = 0
	func get_block(cell: Vector3i) -> int:
		queries += 1
		return 0x01777777 if cell.y == 0 else 0

class CountingData extends VoxelData:
	var queries: int = 0
	func get_block(cell: Vector3i) -> int:
		queries += 1
		return super.get_block(cell)

class OverrideWorld extends VoxelWorld:
	var queries: int = 0
	func get_block(cell: Vector3i) -> int:
		queries += 1
		return 0x01777777 if cell.y == 6 else 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("IMPACT FRAGMENT UPDATES: " + message)

func count_since(effects: OpenSpadesEffects, before: Dictionary, key: String) -> int:
	return int(effects.stats()[key]) - int(before[key])

func run() -> void:
	var world := FloorWorld.new()
	root.add_child(world)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 2, 5)
	root.add_child(camera)
	var effects := EFFECTS.new()
	effects.max_particles = 16
	effects.max_casings = 0
	effects.max_tracers = 0
	effects.max_lights = 0
	root.add_child(effects)
	effects.setup(world, camera)
	effects.set_process(false)
	effects.audio_enabled = false
	effects.shake_level = 0
	var initial: Dictionary = effects.stats()
	for duration: float in [0.05, 0.1, 1.0]:
		effects.clear()
		effects._spawn(Vector3(2, 3, 4), Vector3(6, 3, -3), Color.RED, 0.2, 2.0,
			{"gravity": 0.9, "collision": EFFECTS.BOUNCE})
		var spin: float = effects.particle_snapshot(0).spin
		var before: Dictionary = effects.stats()
		effects.update_effects(duration)
		var particle: Dictionary = effects.particle_snapshot(0)
		var acceleration := Vector3(0, -28.8, 0)
		var expected := Vector3(2, 3, 4) + Vector3(6, 3, -3) * duration + acceleration * duration * duration * 0.5
		check(particle.position.distance_to(expected) < 0.0001 and particle.velocity.distance_to(Vector3(6, 3, -3) + acceleration * duration) < 0.0001, "Analytical gravity advances by real elapsed time at %ss" % duration)
		check(count_since(effects, before, "particle_updates") == 1 and count_since(effects, before, "fragment_substeps") == 1, "Each active fragment updates once in a %ss frame" % duration)
		check(count_since(effects, before, "fragment_position_writes") == 0 and count_since(effects, before, "fragment_scale_writes") == 0 and count_since(effects, before, "fragment_color_writes") == 0, "Fragments perform no hidden Sprite3D writes")
		check(not particle.has("node") and particle.batched and particle.visible, "An active fragment renders directly from its data slot")
		check(is_equal_approx(particle.age, duration) and is_equal_approx(particle.spin, spin) and is_equal_approx(particle.radius, 0.2) and particle.color == Color.RED, "Age changes while canonical spin, radius and intrinsic color remain stable")
		check(world.queries == 0 and particle.position.is_finite() and particle.velocity.is_finite(), "Collision options cannot cause terrain queries or non-finite motion")
		check(count_since(effects, before, "fragment_batch_transform_writes") == 1 and count_since(effects, before, "fragment_batch_color_writes") == 1, "Direct batch publication writes one transform and color per fragment")
	for collision: int in [EFFECTS.IGNORE, EFFECTS.DELETE, EFFECTS.BOUNCE]:
		effects.clear()
		effects._spawn(Vector3(0, 1.05, 0), Vector3(0, -6, 0), Color.WHITE, 0.2, 2.0,
			{"collision": collision})
		effects.update_effects(0.2)
		var particle: Dictionary = effects.particle_snapshot(0)
		check(effects.particle_count() == 1 and is_equal_approx(particle.position.y, -0.15) and particle.velocity == Vector3(0, -6, 0), "Legacy collision%s passes through the solid floor without deletion or bounce" % collision)
	check(world.queries == 0, "All legacy particle collision policies make zero terrain queries")
	effects.clear()
	effects._spawn(Vector3(0, 3, 0), Vector3.RIGHT, Color.WHITE, 0.1, 2.0, {"fade_out": 2.0})
	effects.update_effects(1.0)
	var hitch: Dictionary = effects.particle_snapshot(0)
	check(is_equal_approx(hitch.age, 1.0) and is_equal_approx(hitch.display_color.a, 0.5) and hitch.position.is_equal_approx(Vector3(1, 3, 0)), "A one-second hitch advances motion, age and fade by the same real elapsed time")
	var before_expiry: Dictionary = effects.stats()
	effects.update_effects(1.0)
	check(effects.particle_count() == 0 and count_since(effects, before_expiry, "fragment_batch_transform_writes") == 0, "Expired fragments release their slots without publishing stale geometry")
	effects._spawn(Vector3(2, 3, 4), Vector3.ZERO, Color.BLUE, 0.2, 2.0)
	effects.transform = Transform3D(Basis(Vector3.UP, 0.4) * Basis.from_scale(Vector3.ONE * 1.2), Vector3(3, 1, -2))
	effects.update_effects(0.0)
	var transformed: Dictionary = effects.particle_snapshot(0)
	check(transformed.position == Vector3(2, 3, 4) and is_equal_approx(transformed.radius, 0.2) and transformed.color == Color.BLUE and effects._fragment_batch.visible, "Manager transforms preserve canonical world position, radius and color")
	effects.clear()
	effects.transform = Transform3D.IDENTITY
	for options: Dictionary in [{"smoke": 1, "growth": 1.0}, {"image": "Textures/Fluid.png", "fade_out": 2.0}]:
		effects._spawn(Vector3(0, 3, 0), Vector3(2, 0, 0), Color.WHITE, 0.2, 2.0, options)
		var before: Dictionary = effects.stats()
		effects.update_effects(0.1)
		var visible: Dictionary = effects.particle_snapshot(0)
		check(visible.has("node") and visible.node.visible and not visible.batched and visible.position.is_equal_approx(Vector3(0.2, 3, 0)), "Animated smoke and fluid retain their visible individual sprites")
		check(count_since(effects, before, "particle_updates") == 1 and count_since(effects, before, "fragment_substeps") == 0, "Animated smoke and fluid update once without fragment work")
		if int(options.get("smoke", 0)) != 0:
			check(visible.node.scale.is_equal_approx(Vector3.ONE * 0.6) and visible.frame == 6 and visible.node.texture == effects._smoke_texture(1, 6), "Smoke retains elapsed-time radius growth and cached animation")
		else:
			check(is_equal_approx(visible.display_color.a, 0.95) and visible.node.texture == effects._texture("Textures/Fluid.png"), "Fluid retains its source texture and elapsed fade")
		effects.clear()
	var motion_options: Dictionary = {"damping": 0.8, "gravity": 0.9, "growth": 0.8,
		"radius_damping": 0.1, "fade_in": 0.2, "fade_out": 0.4}
	effects._spawn(Vector3(0, 3, 0), Vector3(3, 0, 0), Color(0.2, 0.4, 0.6, 0.8), 0.2, 0.2, motion_options)
	effects.update_effects(0.1)
	var damped: Dictionary = effects.particle_snapshot(0)
	var damping_integral: float = (pow(0.8, 0.1) - 1.0) / log(0.8)
	var growth_integral: float = (pow(0.1, 0.1) - 1.0) / log(0.1)
	check(absf(damped.position.x - 3.0 * damping_integral) < 0.00001 and absf(damped.velocity.x - 3.0 * pow(0.8, 0.1)) < 0.00001, "Non-identity damping uses exact elapsed-time motion and final velocity")
	check(absf(damped.radius - (0.2 + 0.8 * growth_integral)) < 0.00001 and is_equal_approx(damped.growth, 0.8 * pow(0.1, 0.1)), "Nonzero growth integrates radius damping analytically")
	check(is_equal_approx(damped.display_color.a, 0.1), "Fragment fade combines fade-in/out with its intrinsic alpha")
	effects.clear()
	effects._spawn(Vector3(0, 3, 0), Vector3(3, 0, 0), Color(0.2, 0.4, 0.6, 0.8), 0.2, 0.2, motion_options)
	for frame: int in range(6):
		effects.update_effects(0.1 / 6.0)
	var partitioned: Dictionary = effects.particle_snapshot(0)
	check(partitioned.position.distance_to(damped.position) < 0.00001 and partitioned.velocity.distance_to(damped.velocity) < 0.00001 and absf(partitioned.radius - damped.radius) < 0.00001, "One long frame and six short frames produce the same decorative motion")
	effects.clear()
	var concrete := VoxelWorld.new()
	var concrete_data := CountingData.new()
	concrete_data.clear(Vector3i(8, 8, 8))
	concrete_data.seed_box(Vector3i.ZERO, Vector3i(8, 1, 8), 0x01777777)
	concrete.data = concrete_data
	root.add_child(concrete)
	concrete.set_process(false)
	effects.world = concrete
	concrete_data.queries = 0
	effects._spawn(Vector3(2, 1.05, 2), Vector3(0, -6, 0), Color.WHITE, 0.2, 2.0, {"collision": EFFECTS.BOUNCE})
	effects.update_effects(0.2)
	check(concrete_data.queries == 0 and effects.particle_snapshot(0).position.y < 0.0, "Particles bypass concrete VoxelWorld data queries and floor collision")
	effects.clear()
	var overridden := OverrideWorld.new()
	overridden.clear_world(Vector3i(8, 8, 8))
	root.add_child(overridden)
	overridden.set_process(false)
	effects.world = overridden
	overridden.queries = 0
	effects._spawn(Vector3(2, 7.05, 2), Vector3(0, -6, 0), Color.WHITE, 0.2, 2.0, {"collision": EFFECTS.DELETE})
	effects.update_effects(0.2)
	check(overridden.queries == 0 and effects.particle_count() == 1 and effects.particle_snapshot(0).position.y < 6.0, "Particles bypass custom world collision overrides")
	effects.clear()
	effects.world = world
	world.queries = 0
	effects.grenade_explosion(Vector3(0, 2, 0))
	effects.grenade_explosion(Vector3(0, 2, 0), true)
	effects.blood(Vector3(0, 2, 0))
	effects.block_hit(Vector3(0, 2, 0), Vector3.UP, Color.WHITE)
	effects.water_hit(Vector3(0, 2, 0))
	effects.update_effects(0.1)
	check(world.queries == 0, "Public particle emitters including grenade visual bias make zero terrain queries")
	effects.clear()
	check(effects.stats().pooled_particles == effects.max_particles and effects.stats().batched_particles == 0, "Clear returns configured data slots and hides all fragments")
	check(effects.stats().particle_state_allocations == initial.particle_state_allocations and effects.stats().created_nodes == initial.created_nodes, "Motion, expiry and mixed emission reuse all preallocated records and nodes")
	concrete.queue_free()
	overridden.queue_free()
	effects.queue_free()
	world.queue_free()
	camera.queue_free()
	await process_frame
	await process_frame
	print("IMPACT FRAGMENT UPDATES: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)
