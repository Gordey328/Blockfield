extends SceneTree
## godot --headless --path game --script ../tests/presentation/test_effects.gd
const Effects = preload("res://presentation/openspades_effects.gd")

class FloorWorld extends Node3D:
	var water_level := -100.0
	func get_block(cell: Vector3i) -> int:
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
	_check(is_equal_approx(effects._slow_shake,.1),"native100-block breakup at5m contributes .1 vibration")
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
	_check(effects.stats().particles == 58, "Above-water grenade uses original 4+8+42+4 particle groups")
	effects.clear()
	effects.grenade_explosion(origin, true)
	_check(effects.stats().particles == 73, "Underwater grenade uses original 7+16+8+42 particle groups")
	effects.clear()
	effects.audio_enabled = true
	effects.eject_shell(origin, Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, 0)
	effects.eject_shell(origin, Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, 1)
	effects.eject_shell(origin, Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, 2)
	_check(effects.stats().casings == 2, "Rifle/SMG original shells eject; source shotgun firing does not")
	for step in range(160):
		effects.update_effects(0.1)
	_check(contacts == 2, "Each original casing emits one first ground-contact event")
	_check(effects.stats().casings == 0, "Original shell ground lifetime expires")
	_check(effects.stats().audio <= 2, "Casing contact audio has bounded one-shot lifetime")
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
	effects.max_particles = 80
	for step in range(10):
		effects.grenade_explosion(origin)
	_check(effects.stats().particles == 80, "Repeated explosions respect the browser particle budget")
	_check(effects.stats().lights <= effects.max_lights, "Repeated explosions respect the flash-light budget")
	for step in range(130):
		effects.update_effects(0.1)
		_check(effects.get_camera_rotation().is_finite(), "Source camera vibration remains finite")
		for child in effects.get_children():
			if child is Node3D and not child.is_queued_for_deletion():
				_check(child.global_transform.is_finite(), "Particle transforms remain finite during gravity/collision/animation")
	_check(effects.stats().particles == 0, "All original particle lifetimes expire")
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
	# Source accumulators are tested directly, without stochastic camera samples.
	for underwater in [false, true]:
		var strength := 1.5 if underwater else 2.0
		var previous_fast := INF
		var previous_slow := INF
		for distance: float in [0.0, 20.0, 80.0, 170.0]:
			effects.clear()
			effects.grenade_explosion(camera.global_position + Vector3.RIGHT * distance, underwater)
			var expected := strength / (distance + 5.0)
			_check(is_equal_approx(effects._fast_shake, minf(expected, 0.4)), "Grenade fast vibration uses source distance falloff at %sm (water=%s)" % [distance, underwater])
			_check(is_equal_approx(effects._slow_shake, minf(expected * 5.0, 0.4)), "Grenade slow vibration uses source distance falloff at %sm (water=%s)" % [distance, underwater])
			_check(effects._fast_shake < previous_fast and effects._slow_shake <= previous_slow, "Increasing blast distance reduces source vibration accumulators")
			previous_fast = effects._fast_shake
			previous_slow = effects._slow_shake
			if distance == 170.0:
				_check(effects.stats().particles > 0, "170m blast boundary still emits source effects")
		var fast_boundary := 10.0 if underwater else 15.0
		var slow_boundary := 25.0 if underwater else 35.0
		effects.clear()
		effects.grenade_explosion(camera.global_position + Vector3.RIGHT * fast_boundary, underwater)
		_check(is_equal_approx(effects._fast_shake * 10.0, 1.0), "Original near fast-shake saturation boundary is retained")
		effects.clear()
		effects.grenade_explosion(camera.global_position + Vector3.RIGHT * slow_boundary, underwater)
		_check(is_equal_approx(effects._slow_shake * 4.0, 1.0), "Original near slow-shake saturation boundary is retained")
		effects.clear()
		effects.grenade_explosion(camera.global_position + Vector3.RIGHT * 170.01, underwater)
		_check(effects._fast_shake == 0.0 and effects._slow_shake == 0.0 and effects.stats().particles == 0, "Blast beyond170m produces neither vibration nor particles")
		effects.grenade_explosion(camera.global_position, underwater)
		effects.update_effects(1.0)
		_check(effects._fast_shake == 0.0 and effects._slow_shake == 0.0 and effects.get_camera_rotation() == Vector3.ZERO, "One-second hitch drains vibration using elapsed time")
	effects.clear()

func _test_pooling(effects: OpenSpadesEffects, origin: Vector3) -> void:
	effects.clear()
	var created: int = effects.stats().created_nodes
	var textures := effects._textures.size()
	_check(effects._smoke_frames[1].size() == 180 and effects._smoke_frames[2].size() == 48, "Both complete smoke animations are cached before firing")
	# More than six SMG magazines, with nearby impact particles, shell collisions,
	# flashes and world tracers. Advance at60Hz so lifetimes/collisions are exercised.
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
		var first: Node3D = effects._casings[0].node
		var model: Node = first.get_child(0)
		effects._casings[0].played = true
		effects._casings[0].ground_time = 1.5
		first.scale = Vector3.ONE * 3.0
		effects.clear()
		effects.eject_shell(origin, Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, weapon)
		var entry: Dictionary = effects._casings[0]
		_check(entry.node == first and first.get_child(0) == model, "Weapon%s reuses its original GLB casing instance" % weapon)
		_check(not entry.played and entry.ground_time == -1.0 and entry.age == 0.0 and first.scale.is_equal_approx(Vector3.ONE), "Reused casing resets collision/contact/lifetime/transform state")
		effects.clear()
	effects._spawn(origin, Vector3.ONE, Color.RED, 2.0, 5.0, {"smoke": 1, "collision": Effects.IGNORE})
	var sprite: Sprite3D = effects._particles[0].node
	effects.update_effects(0.05)
	effects.clear()
	effects._spawn(origin, Vector3.ZERO, Color.WHITE, 0.1, 2.0)
	var particle: Dictionary = effects._particles[0]
	_check(particle.node == sprite and sprite.texture == effects._texture("Gfx/White.png") and sprite.modulate == Color.WHITE, "Reused sprite resets previous smoke texture and color")
	_check(particle.age == 0.0 and particle.smoke == 0 and particle.velocity == Vector3.ZERO and particle.collision == Effects.DELETE, "Reused sprite resets lifetime, velocity and collision policy")
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
	_check(is_equal_approx(effects._particles[0].age, 1.0) and is_equal_approx(effects._casings[0].age, 1.0), "Particle and casing ages use real elapsed time during a hitch")
	_check(is_equal_approx(effects._particles[0].node.modulate.a, 0.5), "Particle fade uses real elapsed time during a hitch")
	effects.update_effects(1.0)
	_check(effects.stats().particles == 0, "Two-second fragment lifetime expires after two one-second slow frames")
	effects.clear()

func _test_batching(effects: OpenSpadesEffects, origin: Vector3) -> void:
	effects.clear()
	var created: int = effects.stats().created_nodes
	effects.block_destroy(origin, Color(0.2, 0.4, 0.6))
	effects.muzzle_fire(origin, Vector3.FORWARD, 1)
	effects.update_effects(0.0)
	_check(effects.stats().particles == 10 and effects.stats().batched_particles == 8 and effects._fragment_multimesh.visible_instance_count == 8, "White fragment sprites batch while both animated smoke sprites remain separate")
	var visibility_correct := true
	for entry: Dictionary in effects._particles:
		visibility_correct = visibility_correct and entry.node.visible == (not entry.batched)
	_check(visibility_correct and effects._fragment_batch.visible, "Batched fragment sprites stay hidden and emit one visible MultiMesh")
	_check(effects._fragment_multimesh.instance_count == effects.max_particles and effects._fragment_material.vertex_color_use_as_albedo and effects._fragment_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "Fragment batch has fixed capacity and shared transparent per-instance colors")
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
		_check(pose.origin.is_equal_approx(origin) and pose.basis.get_scale().is_equal_approx(Vector3.ONE * 0.24), "Batched billboard preserves global position and inherited radius under a transformed manager")
		_check(pose.basis.z.normalized().is_equal_approx(effects.camera.global_basis.z.normalized()), "Batched fragments face the current rotated camera after transform updates")
		_check(effects._fragment_multimesh.get_instance_color(0).is_equal_approx(effects._particles[0].node.modulate), "Batch carries original fragment color and fade alpha")
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
	_check(effects._fragment_multimesh != old_fragment_mesh and effects._fragment_multimesh.instance_count == effects.max_particles and effects._fragment_multimesh.visible_instance_count == 0, "Reload replaces stale fragment batch resources under the current budget")
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
