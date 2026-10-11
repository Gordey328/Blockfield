extends SceneTree
## --baseline measures the unbounded original path before production changes.
const MODELS = preload("res://presentation/openspades_models.gd")
const EXTENSIONS = preload("res://presentation/openspades_extensions.gd")
const COLORS := 512
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _fixture(first_person: bool = false) -> MeshInstance3D:
	var original := StandardMaterial3D.new()
	original.resource_name = "TeamColor"
	original.albedo_color = Color.WHITE
	var mesh := BoxMesh.new()
	mesh.material = original
	var node := MeshInstance3D.new()
	node.mesh = mesh
	MODELS._prepare(node, first_person)
	return node

func _color(index: int) -> Color:
	var rgb := index + 1
	return Color(float((rgb >> 16) & 255) / 255.0, float((rgb >> 8) & 255) / 255.0, float(rgb & 255) / 255.0)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	if "--baseline" in OS.get_cmdline_user_args():
		await _run_baseline()
	else:
		await _run_bounds()
	print("MODEL_CACHE_CHECKS: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _run_baseline() -> void:
	MODELS.clear_cache()
	var node := _fixture()
	var baseline: Array[Dictionary] = []
	for index: int in range(COLORS):
		var requested := _color(index)
		MODELS.set_tint(node, requested)
		var colored := node.get_surface_override_material(0) as StandardMaterial3D
		_check(colored != null and colored.albedo_color == requested, "Each requested RGB remains exact")
		if index + 1 in [128, 256, 512]:
			baseline.append({"distinct_colors":index + 1, "material_entries":MODELS._material_cache.size()})
	print("MODEL_CACHE_BASELINE: ", JSON.stringify({"engine":Engine.get_version_info().string,
		"models_sha256":FileAccess.get_file_as_string("res://presentation/openspades_models.gd").sha256_text(),
		"samples":baseline, "scope":"one synthetic surface; cache references, not process peak memory"}))
	_check(baseline[0].material_entries == 129 and baseline[1].material_entries == 257 and baseline[2].material_entries == 513,
		"Original cache grows by one retained material per distinct requested RGB")
	node.free()
	MODELS.clear_cache()
	await process_frame
	await process_frame

func _run_bounds() -> void:
	MODELS.clear_cache()
	var held := _fixture()
	var changing := _fixture()
	var view := _fixture(true)
	MODELS.set_tint(held, _color(0))
	MODELS.set_tint(changing, _color(0))
	var held_material := held.get_surface_override_material(0) as StandardMaterial3D
	_check(held_material == changing.get_surface_override_material(0), "Matching exact colors share immutable materials")
	MODELS.set_tint(view, _color(0))
	var view_material := view.get_surface_override_material(0) as StandardMaterial3D
	_check(view_material != held_material and view_material.no_depth_test and view_material.render_priority == 100,
		"First-person depthHack material remains separate from world tint")
	_check(not held_material.no_depth_test, "World tint keeps normal depth tests")
	for index: int in range(COLORS):
		var requested := _color(index)
		MODELS.set_tint(changing, requested)
		MODELS.set_tint(view, requested)
		var colored := changing.get_surface_override_material(0) as StandardMaterial3D
		var fp_colored := view.get_surface_override_material(0) as StandardMaterial3D
		_check(colored != null and colored.albedo_color == requested, "Eviction never quantizes world RGB")
		_check(fp_colored != null and fp_colored.albedo_color == requested, "Eviction never quantizes view RGB")
		var stats := MODELS.get_cache_stats()
		_check(stats.world_tints <= MODELS.MAX_TINT_MATERIALS_PER_VIEW and stats.view_tints <= MODELS.MAX_TINT_MATERIALS_PER_VIEW,
			"Both tint caches remain bounded after every request")
	_check(MODELS.get_cache_stats().world_tints == 256 and MODELS.get_cache_stats().view_tints == 256,
		"Cache reaches a fixed plateau rather than retaining all colors")
	_check(MODELS.get_cache_stats().tint_evictions == 512, "Exactly the overflowing cache references are evicted")
	_check(not MODELS._world_tint_cache.has(_color(0)), "Old unused cache key is evicted")
	_check(is_instance_valid(held_material) and held.get_surface_override_material(0) == held_material and held_material.albedo_color == _color(0),
		"A live mesh retains its exact immutable material after cache eviction")
	MODELS.set_tint(changing, _color(0))
	_check(changing.get_surface_override_material(0) != held_material and held_material.albedo_color == _color(0),
		"Revisiting an evicted color creates an exact replacement without modifying the retained material")
	MODELS.set_tint(changing, _color(257))
	MODELS.set_tint(changing, _color(512))
	_check(MODELS._world_tint_cache.has(_color(257)) and not MODELS._world_tint_cache.has(_color(258)),
		"A cache hit refreshes recency before the next bounded eviction")
	# Color's string form rounds channels; these distinct float32 values need
	# distinct immutable resources even when they have the same printed form.
	var exact_a := Color(0.1234561, 0.25, 0.75, 0.5)
	var exact_b := Color(0.1234562, 0.25, 0.75, 0.5)
	MODELS.set_tint(held, exact_a)
	MODELS.set_tint(changing, exact_b)
	_check(held.get_surface_override_material(0) != changing.get_surface_override_material(0), "Close exact colors do not alias through rounded string keys")
	_check((held.get_surface_override_material(0) as StandardMaterial3D).albedo_color == exact_a and
		(changing.get_surface_override_material(0) as StandardMaterial3D).albedo_color == exact_b, "All exact RGBA channels survive cache lookup")
	for color: Color in MODELS.TEAM_COLORS:
		MODELS.set_tint(held, color)
		MODELS.set_tint(changing, color)
		_check(held.get_surface_override_material(0) == changing.get_surface_override_material(0), "Both team colors still share their immutable world material")
		_check((held.get_surface_override_material(0) as StandardMaterial3D).albedo_color == color, "Source team color stays exact")
	var team_material := held.get_surface_override_material(0) as StandardMaterial3D
	var old_generation: int = MODELS.get_cache_stats().generation
	EXTENSIONS.clear()
	var refreshed := MODELS.create("Player/Head")
	var refreshed_stats := MODELS.get_cache_stats()
	_check(refreshed_stats.generation > old_generation and refreshed_stats.generation == EXTENSIONS.get_generation(),
		"Resource generation still resets model caches before loading fresh scenes")
	_check(refreshed_stats.world_tints == 0 and refreshed_stats.view_tints == 0 and refreshed_stats.tint_evictions == 0,
		"Generation change clears tint references and counters")
	_check(held.get_surface_override_material(0) == team_material and team_material.albedo_color == MODELS.TEAM_COLORS[1],
		"Old live meshes retain valid exact resources during generation reset")
	refreshed.free()
	held.free()
	changing.free()
	view.free()
	MODELS.clear_cache()
	var cleared := MODELS.get_cache_stats()
	_check(cleared.retained_materials == 0 and cleared.scenes == 0, "Explicit teardown releases every cache reference")
	await process_frame
	await process_frame
