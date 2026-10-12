extends SceneTree
const MAIN = preload("res://scenes/main.tscn")
var checks: int = 0
var failures: int = 0

class RaySpy extends VoxelWorld:
	var rays: int = 0
	func cast_voxel(_origin: Vector3, _direction: Vector3, _max_dist: float = 500.0) -> Dictionary:
		rays += 1
		return {"hit":false}

class CorpseSpy extends OpenSpadesCorpse:
	var step_calls: int = 0
	func step(_delta: float) -> void:
		step_calls += 1

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var app: Node3D = MAIN.instantiate()
	root.add_child(app)
	app.set_process(false)
	app.hud.set_menu_visible(true)
	var original: VoxelWorld = app.world
	var spy: RaySpy = RaySpy.new()
	var graphics: Dictionary = app.get_graphics_options()
	app.graphics_options.manual_focus = false
	app.graphics_options.lens_flare = false
	app.world = spy
	for frame: int in 60: app._update_graphics(1.0/60.0)
	check(spy.rays==0,"disabled flare produces no solar terrain rays")
	app.graphics_options.lens_flare = true
	for frame: int in 5: app._update_graphics(1.0/60.0)
	check(spy.rays==5,"enabled flare retains every-frame visibility sampling")
	check(app.post_effects._flare_sources.size()==1,"enabled flare publishes the original sun source")
	app.world = original
	app.graphics_options.lens_flare = false
	app._apply_graphics()
	check(app.post_effects._flare_sources.is_empty(),"disabling flare clears stale source immediately")
	app.world = spy
	app._update_graphics(1.0/60.0)
	check(spy.rays==5,"disabled flare remains query-free after option transition")
	app.graphics_options.lens_flare = true
	app._update_graphics(1.0/60.0)
	check(spy.rays==6 and app.post_effects._flare_sources.size()==1,"reenabling flare immediately refreshes visibility and source")
	app.world = original
	app.graphics_options = graphics
	app._apply_graphics()
	check(app.get_graphics_options()==graphics,"all original quality options survive optimization checks")
	check(app.network_client==null,"offline lab never creates a multiplayer client")
	var body: OpenSpadesCorpse = app.spawn_corpse({"feet_position":app.player.global_position,"yaw":0.5,"team":1})
	check(body.is_static(),"actual Main death presentation selects static body mode")
	var frozen_center: Vector3 = body.get_center()
	var corpse_spy: CorpseSpy = CorpseSpy.new()
	app.add_child(corpse_spy)
	app._corpses.append(corpse_spy)
	for frame: int in 60: app._process(1.0/60.0)
	check(corpse_spy.step_calls==0,"actual rendered Main never dispatches a corpse solver")
	check(body.get_center()==frozen_center,"body remains fixed through sixty actual Main callbacks")
	app.clear_corpses()
	check(app._corpses.is_empty() and app._last_player_corpse==null,"static body teardown clears owner camera references")
	spy.free()
	app.queue_free()
	await process_frame
	await process_frame
	print("MAIN_OPTIMIZATION_CHECKS: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
