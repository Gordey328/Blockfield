extends SceneTree
## godot --headless --path game --script ../tests/presentation/test_effects.gd
const Effects = preload("res://presentation/openspades_effects.gd")

class FloorWorld extends Node3D:
	var water_level := -100.0
	var queries: int = 0
	func get_block(cell: Vector3i) -> int:
		queries += 1
		return 0x01777777 if cell.y == 0 else 0

var checks := 0
var failures := 0
var contacts := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := FloorWorld.new()
	root.add_child(world)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 2, 5)
	var effects := Effects.new()
	root.add_child(effects)
	effects.setup(world, camera)
	effects.set_process(false)
	effects.audio_enabled = false
	effects.rng.seed = 7341
	effects.casing_contact.connect(func(_position: Vector3, _water: bool, _weapon: int): contacts += 1)
	var origin := Vector3(0, 2, 0)
	_test_grenade_distance(effects, camera)
	_test_hitch_lifetimes(effects, origin)
	effects.collapse_impact(origin,100)
	_check(is_equal_approx(effects._slow_shake,.0852071006),"100-block breakup at5m applies the shorter feedback range")
	effects.clear()
	effects.collapse_impact(camera.position,1000)
	_check(effects._slow_shake==1.0,"native breakup vibration clamps at1")
	effects.clear()
	effects.collapse_impact(Vector3(0,2,200),1000)
	_check(effects._slow_shake==0.0,"native breakup beyond170m is culled")
	effects.quality = 1
	effects.blood(origin)
	_check(effects.stats().particles == 10, "Low-quality blood has original ten droplets")
	effects.clear()
	effects.quality = 2
	effects.blood(origin)
	_check(effects.stats().particles == 13, "High-quality blood adds three original animated smoke particles")
	effects.clear()
	effects.block_hit(origin, Vector3.UP, Color(0.2, 0.4, 0.6))
	_check(effects.stats().particles == 25, "Nearby high-quality impact uses original 7+16 fragments and two smoke particles")
	effects.clear()
	effects.block_destroy(origin, Color(0.2, 0.4, 0.6))
	_check(effects.stats().particles == 8, "Direct block destruction has original eight fragments")
	effects.clear()
	effects.water_hit(origin)
	_check(effects.stats().particles == 8, "Water impact uses original two splashes and six fluid sprites")
	effects.clear()
	effects.muzzle_fire(origin, Vector3.FORWARD, 0)
	_check(effects.stats().particles == 2 and effects.stats().lights == 1, "Muzzle emission has original rapid smoke and flash light")
	effects.update_effects(0.1)
	_check(effects.stats().lights == 0, "Transient flash expires")
	effects.clear()
	effects.grenade_explosion(origin)
	_check(effects.stats().particles == 50, "Above-water grenade fits the accepted fifty-particle presentation budget")
	effects.clear()
	effects.grenade_explosion(origin, true)
	_check(effects.stats().particles == 50, "Underwater grenade fits the accepted fifty-particle presentation budget")
	effects.clear()
	effects.audio_enabled = true
	effects.eject_shell(origin, Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, 0)
	effects.eject_shell(origin, Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, 1)
	effects.eject_shell(origin, Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, 2)
	_check(effects.stats().casings == 2, "Rifle/SMG original shells eject; source shotgun firing does not")
	for step in range(160):
		effects.update_effects(0.1)
	_check(contacts == 0, "Collision-free casings emit no ground-contact events")
	_check(effects.stats().casings == 0, "Decorative casings expire after their bounded flight")
	_check(effects.stats().audio == 0, "Collision-free casings create no contact sounds")
	_check(world.queries == 0, "Particle and casing emission/flight query no terrain")
	effects.stop_audio()
	_check(effects.stats().audio == 0, "Audio teardown releases owned playback and stream references")
	effects.audio_enabled = false
	effects.tracer(origin, origin + Vector3.FORWARD * 40.0, 0, true)
	_check(effects.stats().tracers == 0, "Original local first-person tracer suppression is retained")
	for weapon in range(3):
		effects.tracer(origin, origin + Vector3.FORWARD * 40.0, weapon)
	_check(effects.stats().tracers == 3, "All three original tracer velocity profiles are supported")
	for step in range(10):
		effects.update_effects(0.05)
	_check(effects.stats().tracers == 0, "Moving tracer segments terminate at the hit position")
	_test_pooling(effects, origin)
	_test_batching(effects, origin)
	_test_particle_budget(effects, origin)
	_test_casing_budget(effects, origin, world)
	effects.max_particles = 80
	for step in range(10):
		effects.grenade_explosion(origin)
	_check(effects.max_particles == 50 and effects.stats().particles == 50, "Configuration cannot raise the hard fifty-particle limit")
	_check(effects.stats().lights <= effects.max_lights, "Repeated explosions respect the flash-light budget")
	for step in range(130):
		effects.update_effects(0.1)
		_check(effects.get_camera_rotation().is_finite(), "Source camera vibration remains finite")
		for child in effects.get_children():
			if child is Node3D and not child.is_queued_for_deletion():
				_check(child.global_transform.is_finite(), "Effect transforms remain finite during gravity and animation")
		for index: int in range(effects.particle_count()):
			var particle: Dictionary = effects.particle_snapshot(index)
			_check(particle.position.is_finite() and particle.velocity.is_finite(), "Collision-free particle data stays finite through expiry")
	_check(effects.stats().particles == 0, "Every admitted particle lifetime expires")
	_check(effects.get_camera_rotation() == Vector3.ZERO, "Camera vibration decays to zero")
	effects.clear()
	_test_reload(effects, origin)
	camera.position.x = 200
	effects.blood(origin)
	effects.block_hit(origin, Vector3.UP, Color.WHITE)
	_check(effects.stats().particles == 0, "Original blood/block 150-metre distance culling is retained")
	effects.queue_free()
	world.queue_free()
	camera.queue_free()
	await process_frame
	await process_frame
	print("EFFECTS_CHECKS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _test_grenade_distance(effects: OpenSpadesEffects, camera: Camera3D) -> void:
	# Presentation range is deliberately shorter than native saturation.
	for underwater in [false, true]:
		var strength := 1.5 if underwater else 2.0
		var previous_fast := INF
		var previous_slow := INF
		for distance: float in [0.0, 5.0, 20.0, 32.0, 80.0, 170.0]:
			effects.clear()
			effects.grenade_explosion(camera.global_position + Vector3.RIGHT * distance, underwater)
			var expected := strength / (distance + 5.0) / (1.0 + distance * distance / 144.0)
			_check(is_equal_approx(effects._fast_shake, minf(expected, 0.4)), "Grenade fast vibration has shorter distance falloff at %sm (water=%s)" % [distance, underwater])
			_check(is_equal_approx(effects._slow_shake, minf(expected * 5.0, 0.4)), "Grenade slow vibration has shorter distance falloff at %sm (water=%s)" % [distance, underwater])
			_check(effects._fast_shake < previous_fast and effects._slow_shake <= previous_slow, "Increasing blast distance reduces vibration accumulators")
			previous_fast = effects._fast_shake
			previous_slow = effects._slow_shake
			if distance == 170.0:
				_check(effects.stats().particles > 0, "170m blast boundary still emits source effects")
		effects.clear()
		effects.grenade_explosion(camera.global_position + Vector3.RIGHT * 32.0, underwater)
		var sample := SourceCameraEffects.new().sample({"first_person":false,"shake_level":2,
			"grenade_fast":effects._fast_shake,"grenade_slow":effects._slow_shake,
			"random_values":[1,0,1,0,1,0,1,0],"grenade_noise":Vector3.ONE},0.0)
		_check(absf(sample.native_angles.z) < deg_to_rad(1.0), "32-unit throw has less than one degree of combined peak camera roll")
		_check(sample.grenade_fast_scaled < .07 and sample.grenade_slow_scaled < .02, "Far throw no longer reaches either camera saturation plateau")
		effects.clear()
		effects.grenade_explosion(camera.global_position + Vector3.RIGHT * 170.01, underwater)
		_check(effects._fast_shake == 0.0 and effects._slow_shake == 0.0 and effects.stats().particles == 0, "Blast beyond170m produces neither vibration nor particles")
		effects.grenade_explosion(camera.global_position, underwater)
		effects.update_effects(1.0)
		_check(effects._fast_shake == 0.0 and effects._slow_shake == 0.0 and effects.get_camera_rotation() == Vector3.ZERO, "One-second hitch drains vibration using elapsed time")
	effects.clear()
	effects.collapse_impact(camera.global_position + Vector3.RIGHT * 32.0,100000)
	_check(effects._slow_shake < .125, "A huge distant collapse cannot bypass the shorter feedback range")
	effects.clear()

func _test_pooling(effects: OpenSpadesEffects, origin: Vector3) -> void:
	effects.clear()
	var created: int = effects.stats().created_nodes
	var textures := effects._textures.size()
	_check(effects._smoke_frames[1].size() == 180 and effects._smoke_frames[2].size() == 48, "Both complete smoke animations are cached before firing")
	# More than six SMG magazines with nearby impact particles, decorative shells,
	# flashes and world tracers. Advance at60Hz to exercise animation and expiry.
	for shot in range(180):
		effects.muzzle_fire(origin, Vector3.FORWARD, 1)
		effects.block_hit(origin, Vector3.UP, Color(0.2, 0.4, 0.6))
		effects.eject_shell(origin, Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, 1)
		effects.tracer(origin, origin + Vector3.FORWARD * 40.0, 1)
		for frame in range(7):
			effects.update_effects(0.11 / 7.0)
	_check(effects.stats().created_nodes == created, "Repeated SMG fire allocates no effect/model nodes after setup")
	_check(effects._textures.size() == textures, "Firing and smoke animation perform no new texture lookups")
	effects.clear()
	_check(effects.stats().particles == 0 and effects.stats().casings == 0 and effects.stats().tracers == 0 and effects.stats().lights == 0, "Clear returns every live effect to its pool")
	_check(effects.stats().batched_particles == 0 and effects._fragment_multimesh.visible_instance_count == 0, "Clear hides every batched fragment")
	var inactive_hidden := true
	for child in effects.get_children():
		if child is Node3D and not child.is_queued_for_deletion():
			inactive_hidden = inactive_hidden and not child.visible and child.transform == Transform3D.IDENTITY and child.process_mode == Node.PROCESS_MODE_DISABLED
	_check(inactive_hidden, "Inactive pooled nodes are hidden, reset and have no process callbacks")
	for weapon in range(2):
		effects.eject_shell(origin, Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, weapon)
		var first: Node3D = effects.casing_snapshot(0).node
		var model: Node = first.get_child(0)
		effects.update_effects(0.3)
		first.scale = Vector3.ONE * 3.0
		effects.clear()
		effects.eject_shell(origin, Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, weapon)
		var entry: Dictionary = effects.casing_snapshot(0)
		_check(entry.node == first and first.get_child(0) == model, "Weapon%s reuses its original GLB casing instance" % weapon)
		_check(entry.age == 0.0 and entry.life == 2.0 and entry.opacity == 1.0 and entry.velocity.is_finite() and first.scale.is_equal_approx(Vector3.ONE), "Reused casing resets flight lifetime, fade and transform state")
		var expected_velocity := Vector3(10, 2, -5) if weapon == 0 else Vector3(10, 2, 2)
		_check(entry.velocity.is_equal_approx(expected_velocity), "Weapon%s preserves original casing ejection direction and speed" % weapon)
		effects.clear()
	effects._spawn(origin, Vector3.ONE, Color.RED, 2.0, 5.0, {"smoke": 1, "collision": Effects.IGNORE})
	var sprite: Sprite3D = effects.particle_snapshot(0).node
	effects.update_effects(0.05)
	effects.clear()
	effects._spawn(origin, Vector3.ZERO, Color.WHITE, 0.1, 2.0, {"smoke": 2})
	var particle: Dictionary = effects.particle_snapshot(0)
	_check(particle.node == sprite and sprite.texture == effects._smoke_texture(2, 0) and sprite.modulate == Color.WHITE, "Reused smoke sprite resets texture and color")
	_check(particle.age == 0.0 and particle.smoke == 2 and particle.velocity == Vector3.ZERO and particle.frame == 0, "Reused smoke state resets age, animation and velocity")
	effects.clear()
	effects._spawn(origin, Vector3.ZERO, Color.WHITE, 0.1, 2.0)
	particle = effects.particle_snapshot(0)
	_check(particle.batched and not particle.has("node") and particle.visible, "A white fragment uses an active data slot without a hidden Sprite3D")
	effects.clear()
	# Burst without advancing time exercises every active admission cap.
	for shot in range(700):
		effects.muzzle_fire(origin, Vector3.FORWARD, 1)
		effects.eject_shell(origin, Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, shot % 2)
		effects.tracer(origin, origin + Vector3.FORWARD * 40.0, 1)
	_check(effects.stats().particles == effects.max_particles and effects.stats().casings == effects.max_casings and effects.stats().tracers == effects.max_tracers and effects.stats().lights == effects.max_lights, "Unbounded emission attempts respect all active browser budgets")
	_check(effects.stats().created_nodes == created, "Budget-saturating bursts still reuse prewarmed nodes")
	effects.clear()
	_check(effects.stats().pooled_particles <= effects.max_particles and effects.stats().pooled_casings <= effects.max_casings * 2 and effects.stats().pooled_tracers <= effects.max_tracers and effects.stats().pooled_lights <= effects.max_lights, "Idle pool capacity is bounded, including separate rifle/SMG models")

func _test_hitch_lifetimes(effects: OpenSpadesEffects, origin: Vector3) -> void:
	effects.clear()
	effects.muzzle_fire(origin, Vector3.FORWARD, 1)
	effects.eject_shell(origin, Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, 1)
	effects.tracer(origin, origin + Vector3.FORWARD * 40.0, 1)
	effects._spawn(origin, Vector3.ZERO, Color.WHITE, 0.1, 2.0, {"collision": Effects.IGNORE, "fade_out": 2.0})
	effects.update_effects(1.0)
	_check(effects.stats().particles == 1 and effects.stats().lights == 0 and effects.stats().tracers == 0, "One-second hitch expires muzzle smoke, flash and world tracer in real time")
	_check(is_equal_approx(effects.particle_snapshot(0).age, 1.0) and is_equal_approx(effects.casing_snapshot(0).age, 1.0), "Particle and casing ages use real elapsed time during a hitch")
	_check(is_equal_approx(effects.particle_snapshot(0).display_color.a, 0.5), "Particle fade uses real elapsed time during a hitch")
	effects.update_effects(1.0)
	_check(effects.stats().particles == 0, "Two-second fragment lifetime expires after two one-second slow frames")
	effects.clear()

func _test_particle_budget(effects: OpenSpadesEffects, origin: Vector3) -> void:
	effects.clear()
	var before: Dictionary = effects.stats()
	_check(effects.max_particles == 50 and before.particle_hard_cap == 50 and before.particle_slot_capacity == 50, "Default and storage capacities enforce the hard fifty-particle budget")
	_check(before.particle_state_allocations == 50, "All fifty particle records are allocated during loading")
	# Fill the pool with old distant ambient smoke, then emit close combat feedback.
	for index: int in range(50):
		effects._spawn(origin + Vector3.RIGHT * 80.0, Vector3.ZERO, Color.WHITE, 0.2, 8.0, {"smoke": 1})
	effects.update_effects(0.1)
	effects.block_hit(origin, Vector3.UP, Color.BLUE)
	var close: int = 0
	for index: int in range(effects.particle_count()):
		var particle: Dictionary = effects.particle_snapshot(index)
		if particle.position.distance_to(origin) < 1.0:
			close += 1
	_check(effects.particle_count() == 50 and close == 25, "Fresh close impact fragments and dust replace distant old smoke without growing the pool")
	_check(effects.stats().particle_recycled > before.particle_recycled, "Overload recycles existing active slots")
	effects.clear()
	# Same-priority overload replaces the oldest slot; lower-priority smoke is dropped.
	effects._spawn(origin, Vector3.ZERO, Color.GREEN, 0.2, 8.0)
	for index: int in range(49):
		effects._spawn(origin, Vector3.ZERO, Color.RED, 0.2, 8.0)
	var dropped: int = effects.stats().particle_dropped
	effects._spawn(origin + Vector3.RIGHT * 80.0, Vector3.ZERO, Color.WHITE, 0.2, 8.0, {"smoke": 1})
	_check(effects.stats().particle_dropped == dropped + 1 and effects.particle_count() == 50, "Distant ambient smoke cannot evict close combat particles")
	effects._spawn(origin, Vector3.ZERO, Color.BLUE, 0.2, 8.0)
	var green: int = 0
	var blue: int = 0
	for index: int in range(effects.particle_count()):
		var particle: Dictionary = effects.particle_snapshot(index)
		green += int(particle.color == Color.GREEN)
		blue += int(particle.color == Color.BLUE)
	_check(green == 0 and blue == 1 and effects.particle_count() == 50, "A fresh equal-priority particle replaces the oldest combat particle")
	_check(effects.stats().created_nodes == before.created_nodes and effects.stats().particle_state_allocations == before.particle_state_allocations, "Overload performs no particle state or node allocation")
	effects.clear()
	effects.max_particles = -5
	effects.blood(origin)
	effects.grenade_explosion(origin)
	_check(effects.max_particles == 0 and effects.particle_count() == 0, "Negative particle configuration clamps to zero and disables emission")
	effects.max_particles = 12
	for index: int in range(40):
		effects._spawn(origin, Vector3.ZERO, Color.RED, 0.2, 2.0)
	_check(effects.particle_count() == 12 and effects.stats().particle_capacity == 12, "A lower configured budget admits only that many particles")
	effects.max_particles = 5
	_check(effects.particle_count() <= 5, "Lowering an active budget immediately restores its cap")
	effects.clear()
	effects.max_particles = 5000
	effects.prewarm()
	_check(effects.max_particles == 50 and effects.stats().particle_state_allocations == before.particle_state_allocations and effects.stats().created_nodes == before.created_nodes, "Raising the budget reuses the original fixed storage and prewarmed sprites")
	for cycle: int in range(4):
		effects.blood(origin)
		effects.water_hit(origin)
		effects.grenade_explosion(origin, cycle % 2 == 0)
		effects.clear()
		_check(effects.particle_count() == 0 and effects.stats().pooled_particles == 50 and effects._fragment_multimesh.visible_instance_count == 0, "Clear cycle returns every active slot and hides the fragment batch")
	_check(effects.stats().created_nodes == before.created_nodes and effects.stats().particle_state_allocations == before.particle_state_allocations, "Repeated mixed-effect clear cycles allocate neither records nor nodes")

func _test_casing_budget(effects: OpenSpadesEffects, origin: Vector3, world: FloorWorld) -> void:
	effects.clear()
	var before: Dictionary = effects.stats()
	_check(effects.max_casings == 16 and before.casing_hard_cap == 16 and before.casing_slot_capacity == 16 and before.casing_state_allocations == 16, "Casings have sixteen preallocated active records and a hard sixteen-casing cap")
	var before_queries: int = world.queries
	effects.eject_shell(origin, Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, 0)
	var start: Dictionary = effects.casing_snapshot(0)
	var materials: Array[BaseMaterial3D] = _casing_materials(start.node)
	var colors: Array[Color] = []
	for material: BaseMaterial3D in materials:
		colors.append(material.albedo_color)
	var updates: int = effects.stats().casing_updates
	effects.update_effects(1.75)
	var flown: Dictionary = effects.casing_snapshot(0)
	_check(effects.stats().casing_updates == updates + 1 and is_equal_approx(flown.age, 1.75), "A casing updates once per real elapsed frame")
	_check(flown.position.is_finite() and flown.velocity.is_finite() and flown.node.global_transform.is_finite() and flown.position.distance_to(start.position) > 1.0, "Decorative casing flight advances with finite position and model transform")
	_check(flown.opacity > 0.0 and flown.opacity < 1.0 and flown.node.visible, "A casing fades during the end of its two-second flight")
	var faded: bool = not materials.is_empty()
	for index: int in range(materials.size()):
		faded = faded and is_equal_approx(materials[index].albedo_color.a, colors[index].a * flown.opacity)
	_check(faded, "Compatibility casing materials publish the flight fade as actual alpha")
	var expected_position: Vector3 = start.position + start.velocity * 1.75 + Vector3.DOWN * 16.0 * 1.75 * 1.75
	_check(flown.position.distance_to(expected_position) < 0.0001, "Casing gravity advances analytically over the entire elapsed frame")
	_check(world.queries == before_queries and contacts == 0 and effects.stats().audio == 0, "Casing flight has no terrain queries, contact event or contact sound")
	effects.eject_shell(origin, Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, 0)
	var fresh_materials: Array[BaseMaterial3D] = _casing_materials(effects.casing_snapshot(1).node)
	var independent: bool = not materials.is_empty() and fresh_materials.size() == materials.size()
	for index: int in range(mini(fresh_materials.size(), colors.size())):
		independent = independent and not materials.has(fresh_materials[index]) and fresh_materials[index].albedo_color.is_equal_approx(colors[index])
	_check(independent, "A new casing stays opaque while another casing fades through independent prewarmed materials")
	effects.update_effects(0.25)
	_check(effects.casing_count() == 1 and not start.node.visible, "Casing expiry returns and hides its original model after two seconds while a newer shell survives")
	var restored: bool = not materials.is_empty()
	for index: int in range(materials.size()):
		restored = restored and materials[index].albedo_color.is_equal_approx(colors[index])
	_check(restored, "Returning a casing restores its original material colors for reuse")
	effects.max_casings = -10
	effects.eject_shell(origin, Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, 0)
	_check(effects.max_casings == 0 and effects.casing_count() == 0, "Negative casing budget clamps to zero and disables ejection")
	effects.max_casings = 4
	for index: int in range(40):
		effects.eject_shell(origin, Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, index % 2)
	_check(effects.casing_count() == 4, "Casing overload reuses only the configured active slots")
	effects.max_casings = 2
	_check(effects.casing_count() <= 2, "Lowering an active casing budget restores its cap immediately")
	effects.clear()
	effects.max_casings = 5000
	effects.prewarm()
	for index: int in range(100):
		effects.eject_shell(origin, Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, index % 2)
	_check(effects.max_casings == 16 and effects.casing_count() == 16 and effects.stats().casing_recycled > before.casing_recycled, "Oversized casing configuration clamps to sixteen and overload replaces old ejections")
	_check(effects.stats().created_nodes == before.created_nodes and effects.stats().casing_state_allocations == before.casing_state_allocations, "Raising casing budgets and repeated ejection allocate no records or GLB nodes")
	effects.clear()

func _casing_materials(node: Node3D) -> Array[BaseMaterial3D]:
	var materials: Array[BaseMaterial3D] = []
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface: int in range(mesh_instance.mesh.get_surface_count()):
			var material: BaseMaterial3D = mesh_instance.get_active_material(surface) as BaseMaterial3D
			if material != null and not materials.has(material):
				materials.append(material)
	return materials

func _test_batching(effects: OpenSpadesEffects, origin: Vector3) -> void:
	effects.clear()
	var created: int = effects.stats().created_nodes
	effects.block_destroy(origin, Color(0.2, 0.4, 0.6))
	effects.muzzle_fire(origin, Vector3.FORWARD, 1)
	effects.update_effects(0.0)
	_check(effects.stats().particles == 10 and effects.stats().batched_particles == 8 and effects._fragment_multimesh.visible_instance_count == 8, "White fragment sprites batch while both animated smoke sprites remain separate")
	var visibility_correct := true
	for index: int in range(effects.particle_count()):
		var entry: Dictionary = effects.particle_snapshot(index)
		visibility_correct = visibility_correct and entry.visible
		visibility_correct = visibility_correct and (not entry.has("node") if entry.batched else entry.node.visible)
	_check(visibility_correct and effects._fragment_batch.visible, "White fragments render through one MultiMesh without hidden sprite nodes")
	_check(effects._fragment_multimesh.instance_count == effects.stats().particle_hard_cap and effects._fragment_material.vertex_color_use_as_albedo and effects._fragment_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "Fragment batch retains fifty instances and shared transparent per-instance colors")
	effects.clear()
	var previous_transform := effects.transform
	var previous_camera_transform := effects.camera.transform
	effects.transform = Transform3D(Basis(Vector3.UP, 0.4) * Basis.from_scale(Vector3.ONE * 1.2), Vector3(3, 1, -2))
	effects.camera.rotation = Vector3(0.25, -0.3, 0.1)
	effects._spawn(origin, Vector3.ZERO, Color.RED, 0.1, 2.0, {"collision": Effects.IGNORE})
	effects.update_effects(0.0)
	if DisplayServer.get_name() == "headless":
		# Dummy RenderingServer does not store uploaded instance transforms/colors.
		# The same suite without --headless verifies these three GPU assertions.
		print("EFFECTS_GPU_SKIPPED: 3 MultiMesh transform/color assertions (headless dummy renderer)")
	else:
		var pose: Transform3D = effects._fragment_batch.global_transform * effects._fragment_multimesh.get_instance_transform(0)
		_check(pose.origin.is_equal_approx(origin) and pose.basis.get_scale().is_equal_approx(Vector3.ONE * 0.2), "Batched billboard preserves world position and radius under a transformed manager")
		_check(pose.basis.z.normalized().is_equal_approx(effects.camera.global_basis.z.normalized()), "Batched fragments face the current rotated camera after transform updates")
		_check(effects._fragment_multimesh.get_instance_color(0).is_equal_approx(effects.particle_snapshot(0).display_color), "Actual batch readback carries fragment color and fade alpha")
	_check(effects.stats().created_nodes == created, "Fragment batch never creates mesh/material nodes per emission")
	effects.clear()
	effects.transform = previous_transform
	effects.camera.transform = previous_camera_transform

func _test_reload(effects: OpenSpadesEffects, origin: Vector3) -> void:
	effects.muzzle_fire(origin, Vector3.FORWARD, 1)
	effects.eject_shell(origin, Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, 1)
	effects.tracer(origin, origin + Vector3.FORWARD * 40.0, 1)
	var old_nodes: Array[Node] = []
	for child in effects.get_children():
		if not child.is_queued_for_deletion():
			old_nodes.append(child)
	var old_material: StandardMaterial3D = effects._tracer_material
	var old_mesh: QuadMesh = effects._tracer_mesh
	var old_fragment_mesh: MultiMesh = effects._fragment_multimesh
	effects.reload_resources()
	_check(effects.stats().particles == 0 and effects.stats().casings == 0 and effects.stats().tracers == 0 and effects.stats().lights == 0, "Resource reload releases every active effect")
	var disposed := true
	for node in old_nodes:
		disposed = disposed and node.is_queued_for_deletion() and not node.is_inside_tree()
	_check(disposed, "Reload queues stale model/material nodes for deletion without retaining active nodes")
	_check(effects._smoke_frames[1].size() == 180 and effects._smoke_frames[2].size() == 48 and effects._tracer_material != old_material and effects._tracer_mesh != old_mesh, "Reload rebuilds complete frame caches and replaces stale tracer resources")
	_check(effects._fragment_multimesh != old_fragment_mesh and effects._fragment_multimesh.instance_count == effects.stats().particle_hard_cap and effects._fragment_multimesh.visible_instance_count == 0, "Reload replaces stale fragment resources with a hidden fifty-instance batch")
	_check(effects.stats().pooled_particles == effects.max_particles and effects.stats().pooled_casings == effects.max_casings * 2 and effects.stats().pooled_tracers == effects.max_tracers and effects.stats().pooled_lights == effects.max_lights, "Reload automatically repopulates pools under current budgets")
	effects.muzzle_fire(origin, Vector3.FORWARD, 1)
	effects.eject_shell(origin, Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, 1)
	effects.tracer(origin, origin + Vector3.FORWARD * 40.0, 1)
	var fresh := true
	for child in effects.get_children():
		if not child.is_queued_for_deletion():
			fresh = fresh and not old_nodes.has(child)
	_check(fresh and effects.stats().particles == 2 and effects.stats().casings == 1 and effects.stats().tracers == 1, "Post-reload effects use fresh resources and remain functional")
	effects.clear()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
