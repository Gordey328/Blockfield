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

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
