extends SceneTree
## Reusable presentation life/pose contract. --gpu additionally captures real pixels.
const ZOMBIE = preload("res://presentation/zombie_view.gd")
var checks: int = 0
var failures: int = 0
var gpu: bool = false
var output: String = ""


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--gpu": gpu = true
		elif argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	call_deferred("_run")


func _run() -> void:
	var view: ZombieView = ZOMBIE.new()
	var second: ZombieView = ZOMBIE.new()
	root.add_child(view)
	root.add_child(second)
	var target: Dictionary = {"id": 7, "kind": "zombie", "position": Vector3(3, 4, 5),
		"yaw": 0.4, "alive": true, "slot_alive": true, "spawn_generation": 1,
		"moving": false, "attack_phase": 0.0, "attack_kind": ""}
	view.setup(target)
	second.setup(target)
	var node_ids: Array[int] = _ids(view)
	_check(view.target_id == 7 and view.position == target.position and is_equal_approx(view.rotation.y, 0.4), "Authority ID, feet and yaw set the presentation")
	_check(view.visible and view.get_display_state().alive and view._head != null, "First occupied slot immediately displays a live zombie")
	_check(_count(view, "MeshInstance3D") == 6 and node_ids.size() == 8, "One actor has exactly six parts and one rig, with no cube nodes")
	_check(_count(view, "CollisionObject3D") == 0 and _count(view, "CollisionShape3D") == 0 and _count(view, "Label3D") == 0, "Visual adds no hit zones, physics bodies or HP labels")
	_check(view.find_child("HeldTool", true, false) == null and view.find_child("OriginalCharacterParts", true, false) == null, "Zombie does not equip a soldier weapon or reuse a soldier rig")
	_check(view._head.mesh == second._head.mesh and view._torso.mesh == second._torso.mesh and view._head.material_override == second._head.material_override, "All actors share immutable geometry and material")
	_check(view._arms[0].mesh == view._arms[1].mesh and view._legs[0].mesh == view._legs[1].mesh, "Paired limbs share their mesh")
	_check(view._arms[0].rotation.x > 0.7 and view._arms[1].rotation.x > 0.7, "Idle silhouette is unarmed with two reaching arms")
	var idle_leg: Vector3 = view._legs[0].rotation
	var idle_head: Vector3 = view._head.rotation
	target.position += Vector3(0, 0, -0.3)
	target.moving = true
	view.update_state(target)
	_check(view._legs[0].rotation != idle_leg and signf(view._legs[0].rotation.x) != signf(view._legs[1].rotation.x), "Authority movement produces opposite shuffled leg motion")
	target.attack_kind = "bite"
	target.attack_phase = 0.5
	view.update_state(target)
	_check(view._head.rotation.x < idle_head.x and view._arms[0].rotation.x > 1.0, "Confirmed attack windup visibly leans and reaches")
	_check(target.alive and target.slot_alive and target.attack_phase == 0.5, "Animating an attack does not modify authority data")
	var walker_torso: ArrayMesh = view._torso.mesh as ArrayMesh
	var walker_arm: ArrayMesh = view._arms[1].mesh as ArrayMesh
	target.zombie_type = "grenadier"
	target.throw_remaining = 3
	target.attack_kind = ""
	target.attack_phase = 0.0
	view.update_state(target)
	second.update_state(target)
	_check(view.get_display_state().zombie_type == "grenadier" and not view.get_display_state().held_grenade,
		"grenadier role is distinct while the projectile remains absent at idle")
	_check(view._torso.mesh != walker_torso and view._torso.mesh == second._torso.mesh,
		"grenadiers share a separate olive/orange torso with a baked backpack")
	_check(_contains_color(view._torso.mesh as ArrayMesh, ZOMBIE.GRENADIER_ORANGE) and _contains_color(view._torso.mesh as ArrayMesh, ZOMBIE.GRENADIER_OLIVE),
		"role mesh carries both readable vest and backpack colors")
	target.attack_kind = "throw"
	target.attack_phase = .8
	view.update_state(target)
	second.update_state(target)
	var throw_arm: Vector3 = view._arms[1].rotation
	_check(view.get_display_state().held_grenade and view._arms[1].mesh != walker_arm and view._arms[1].mesh == second._arms[1].mesh,
		"windup displays a shared grenade-bearing hand without extra nodes")
	_check(throw_arm.x < -2 and view._arms[0].rotation.x > 0,
		"throw windup raises one arm overhead instead of a two-arm bite pose")
	_check(_ids(view) == node_ids and _count(view, "MeshInstance3D") == 6,
		"backpack and grenade use mesh variants inside the original six-part pool")
	_check(target.attack_phase == .8 and target.throw_remaining == 3,
		"throw animation cannot consume stock or advance authoritative windup")
	target.attack_phase = 1.0
	view.update_state(target)
	_check(view._arms[1].rotation.x > 0 and view._arms[1].rotation != throw_arm,
		"overhand animation has a distinct forward follow-through")
	target.attack_kind = ""
	target.attack_phase = 0.0
	view.update_state(target)
	_check(not view.get_display_state().held_grenade and view._arms[1].mesh != second._arms[1].mesh,
		"confirmed release removes only the held mesh; ordinary Main owns the projectile")
	target.attack_kind = "throw"
	target.throw_remaining = 0
	view.update_state(target)
	_check(not view.get_display_state().held_grenade, "depleted grenadier cannot visually invent another grenade")
	target.zombie_type = "walker"
	target.attack_kind = "bite"
	target.attack_phase = .5
	view.update_state(target)
	_check(view._torso.mesh == walker_torso and view._arms[1].mesh == walker_arm,
		"role replacement restores walker geometry without pooled prop leakage")
	target.alive = false
	target.slot_alive = false
	view.update_state(target)
	var dead_pose: Transform3D = view._rig.transform
	_check(not view.get_display_state().alive and view.visible and absf(view._rig.rotation.x) > 1.4, "Death lays down the same zombie rig without a soldier corpse")
	view._process(0.75)
	view.update_state(target)
	view.show_death(target)
	_check(is_equal_approx(view.get_display_state().corpse_age, 0.75) and view._rig.transform == dead_pose, "Repeated dead state/event neither extends retention nor moves the corpse")
	view.set_paused(true)
	view._process(10.0)
	_check(view.visible and is_equal_approx(view.get_display_state().corpse_age, 0.75), "Pause freezes corpse retention")
	view.set_paused(false)
	view._process(1.3)
	_check(not view.visible, "Dead slot hides after two active presentation seconds")
	for generation: int in range(2, 66):
		target.spawn_generation = generation
		target.alive = true
		target.slot_alive = true
		target.position = Vector3(generation, 4, 5)
		target.attack_kind = ""
		target.attack_phase = 0.0
		target.zombie_type = "grenadier" if generation % 2 == 0 else "walker"
		target.throw_remaining = 3 if generation % 2 == 0 else 0
		view.update_state(target)
		_check(view.visible and view.get_display_state().generation == generation and is_zero_approx(view.get_display_state().walk_phase), "New generation clears corpse/attack/gait: " + str(generation))
		view.show_death()
	_check(_ids(view) == node_ids, "Many deaths and reused slots allocate no additional rig nodes")
	_check(not view.get_display_state().held_grenade, "death clears held explosive across alternating pooled roles")
	target.spawn_generation = 66
	target.slot_alive = true
	target.position = Vector3.INF
	view.update_state(target)
	_check(not view.visible, "Invalid authority position fails closed")
	view.update_state({})
	_check(not view.visible, "Cleared slot hides its presentation")
	view.free()
	second.free()
	if gpu: await _capture_stage()
	await process_frame
	print("ZOMBIE VIEW: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _capture_stage() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "GPU capture requires a visible Compatibility renderer")
		return
	if output.is_empty(): output = ProjectSettings.globalize_path("res://../.cache/previews/zombie-view")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1024, 640)
	var stage: Node3D = Node3D.new()
	root.add_child(stage)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("16232d")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.75
	stage.add_child(environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	stage.add_child(sun)
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(16, 12)
	floor_mesh.mesh = plane
	var floor_material: StandardMaterial3D = StandardMaterial3D.new()
	floor_material.albedo_color = Color("394747")
	floor_mesh.material_override = floor_material
	stage.add_child(floor_mesh)
	var camera: Camera3D = Camera3D.new()
	camera.current = true
	camera.position = Vector3(6, 4.5, -10)
	camera.fov = 43
	stage.add_child(camera)
	camera.look_at(Vector3(0, 1, 0))
	var empty: Image = await _capture("empty")
	for index: int in 4:
		var zombie: ZombieView = ZOMBIE.new()
		stage.add_child(zombie)
		var target: Dictionary = {"id": index, "kind": "zombie", "slot_alive": true, "spawn_generation": 1,
			"position": Vector3(-3.6 + index * 2.4, 0, 0), "yaw": -0.2,
			"zombie_type":"grenadier" if index >= 2 else "walker", "throw_remaining":3,
			"moving": index == 1, "attack_kind": "throw" if index == 2 else "", "attack_phase": 0.8 if index == 2 else 0.0}
		zombie.setup(target)
		if index == 1:
			target.position += Vector3(0, 0, -0.4)
			zombie.update_state(target)
		if index == 3:
			zombie.show_death()
			zombie.set_paused(true)
	var visible_zombies: Image = await _capture("walker-walk-grenadier-windup-corpse")
	_check(empty.get_data() != visible_zombies.get_data(), "Compatibility renderer displays authored zombie meshes")
	stage.free()


func _capture(file_name: String) -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var rendered: Image = root.get_texture().get_image()
	rendered.save_png(output.path_join(file_name + ".png"))
	return rendered


func _ids(node: Node) -> Array[int]:
	var result: Array[int] = [node.get_instance_id()]
	for child: Node in node.get_children(): result.append_array(_ids(child))
	return result


func _count(node: Node, type_name: String) -> int:
	var result: int = 1 if node.is_class(type_name) else 0
	for child: Node in node.get_children(): result += _count(child, type_name)
	return result


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("ZOMBIE VIEW: " + message)


static func _contains_color(mesh: ArrayMesh, color: Color) -> bool:
	var arrays: Array = mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for candidate: Color in colors:
		if absf(candidate.r - color.r) < .001 and absf(candidate.g - color.g) < .001 and absf(candidate.b - color.b) < .001:
			return true
	return false
