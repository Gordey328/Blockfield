extends SceneTree
## Source-shaped numerical motion/bounce/fade plus actual hidden-node write
## counts for the 3/6 substeps seen during sustained 50/100ms impact frames.
const EFFECTS = preload("res://presentation/openspades_effects.gd")
var assertions: int = 0
var failures: int = 0

class FloorWorld extends Node3D:
	var water_level: float = -100.0
	func get_block(cell: Vector3i) -> int:
		return 0x01777777 if cell.y == 0 else 0

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
	for duration: float in [0.05, 0.1]:
		effects.clear()
		effects._spawn(Vector3(2, 3, 4), Vector3(6, 3, -3), Color.RED, 0.2, 2.0,
			{"gravity": 0.9, "collision": EFFECTS.IGNORE})
		var before: Dictionary = effects.stats()
		effects.update_effects(duration)
		var particle: Dictionary = effects._particles[0]
		var expected_steps: int = 3 if duration == 0.05 else 6
		check(count_since(effects, before, "fragment_substeps") == expected_steps, "50/100ms frame retains every bounded physics substep")
		check(count_since(effects, before, "fragment_position_writes") == 1, "3/6 fragment substeps mirror hidden position only once")
		check(count_since(effects, before, "fragment_scale_writes") == 0 and count_since(effects, before, "fragment_color_writes") == 0, "constant-radius opaque fragment causes no redundant scale/color setters")
		# Source explicit Euler: gravity follows each position integration.
		var expected := Vector3(2.3, 3.126, 3.85) if duration == 0.05 else Vector3(2.6, 3.18, 3.7)
		check(particle.node.global_position.distance_to(expected) < 0.00001, "source Euler trajectory survives consolidated hidden-node updates")
		check(absf(particle.velocity.y - (1.56 if duration == 0.05 else 0.12)) < 0.00001, "gravity applies to every retained substep")
		check(is_equal_approx(particle.age, duration) and not particle.node.visible, "real age and hidden fragment visibility are retained")
		check(particle.node.scale.is_equal_approx(Vector3.ONE * 0.4) and particle.node.modulate == Color.RED, "post-update node inspection retains exact radius and color")
	effects.clear()
	effects._spawn(Vector3(0, 1.05, 0), Vector3(0, -6, 0), Color.WHITE, 0.2, 2.0,
		{"collision": EFFECTS.BOUNCE})
	var before: Dictionary = effects.stats()
	effects.update_effects(0.05)
	var bounced: Dictionary = effects._particles[0]
	check(absf(bounced.node.global_position.y - 1.122) < 0.00001 and absf(bounced.velocity.y - 2.16) < 0.00001, "source floor bounce retains old position then applies0.36 damping before remaining substeps")
	check(count_since(effects, before, "fragment_position_writes") == 1 and count_since(effects, before, "fragment_substeps") == 3, "bounce changes dictionary trajectory without extra hidden-node setters")
	effects.clear()
	effects._spawn(Vector3(0, 3, 0), Vector3.ZERO, Color.WHITE, 0.1, 2.0,
		{"collision": EFFECTS.IGNORE, "fade_out": 2.0})
	before = effects.stats()
	effects.update_effects(1.0)
	check(is_equal_approx(effects._particles[0].age, 1.0) and is_equal_approx(effects._particles[0].node.modulate.a, 0.5), "one-second hitch keeps real elapsed lifetime/fade with bounded integration")
	check(count_since(effects, before, "fragment_substeps") == 6 and count_since(effects, before, "fragment_position_writes") == 1 and count_since(effects, before, "fragment_color_writes") == 1, "hitch mirrors final faded color once after six substeps")
	before = effects.stats()
	effects.update_effects(1.0)
	check(effects.stats().particles == 0 and count_since(effects, before, "fragment_position_writes") == 0, "expired fragment releases without mirroring stale state")
	effects._spawn(Vector3(0, 3, 0), Vector3.RIGHT, Color.RED, 0.2, 2.0,
		{"collision": EFFECTS.IGNORE})
	var moved: Sprite3D = effects._particles[0].node
	moved.global_position = Vector3(10, 8, 5)
	effects.update_effects(0.02)
	check(moved.global_position.distance_to(Vector3(10.02, 8, 5)) < 0.00001, "external hidden-node movement becomes the next frame's canonical position")
	effects.clear()
	effects._spawn(Vector3(2, 3, 4), Vector3.ZERO, Color.BLUE, 0.2, 2.0,
		{"collision": EFFECTS.IGNORE})
	effects.transform = Transform3D(Basis(Vector3.UP, 0.4) * Basis.from_scale(Vector3.ONE * 1.2), Vector3(3, 1, -2))
	var inherited: Sprite3D = effects._particles[0].node
	var inherited_position: Vector3 = inherited.global_position
	effects.update_effects(0.0)
	check(inherited.global_position.distance_to(inherited_position) < 0.00001 and inherited.global_basis.get_scale().is_equal_approx(Vector3.ONE * 0.48), "external manager transform and inherited radius remain inspectable after final mirror")
	check(inherited.modulate == Color.BLUE and effects._fragment_batch.visible, "transformed fragment retains batch color and visibility")
	effects.clear()
	effects.transform = Transform3D.IDENTITY
	for options: Dictionary in [{"smoke": 1, "growth": 1.0, "collision": EFFECTS.IGNORE},
		{"image": "Textures/Fluid.png", "fade_out": 2.0, "collision": EFFECTS.IGNORE}]:
		effects._spawn(Vector3(0, 3, 0), Vector3(2, 0, 0), Color.WHITE, 0.2, 2.0, options)
		before = effects.stats()
		effects.update_effects(0.1)
		var visible: Dictionary = effects._particles[0]
		check(visible.node.visible and not visible.batched and visible.node.global_position.distance_to(Vector3(0.2, 3, 0)) < 0.00001, "visible animated smoke/fluid retains its individual sprite path")
		check(count_since(effects, before, "fragment_substeps") == 0 and count_since(effects, before, "fragment_position_writes") == 0, "visible sprites do not enter hidden-fragment mirroring")
		if int(options.get("smoke", 0)) != 0:
			check(visible.node.scale.is_equal_approx(Vector3.ONE * 0.6) and visible.frame == 6, "visible smoke keeps source radius growth and animation")
		else:
			check(is_equal_approx(visible.node.modulate.a, 0.95), "visible fluid keeps source elapsed fade")
		effects.clear()
	check(effects.stats().pooled_particles == effects.max_particles and effects.stats().batched_particles == 0, "clear returns all fragment/smoke/fluid nodes to the unchanged bounded pool")
	effects.queue_free()
	world.queue_free()
	camera.queue_free()
	await process_frame
	await process_frame
	print("IMPACT FRAGMENT UPDATES: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)
