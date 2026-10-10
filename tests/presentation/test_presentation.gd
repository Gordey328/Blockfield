extends SceneTree
## Resource/pose smoke checks. Browser screenshots remain required for visual parity.
## godot --headless --path game --script ../tests/presentation/test_presentation.gd

const CharacterScript = preload("res://presentation/character_view.gd")
const WeaponScript = preload("res://presentation/weapon_view.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var character := CharacterScript.new()
	root.add_child(character)
	var weapon := WeaponScript.new()
	root.add_child(weapon)
	var checks := 0
	for team in range(2):
		character.set_team(team)
		weapon.set_team(team)
		for gun in range(3):
			for tool in range(4):
				character.set_weapon(gun, tool)
				weapon.set_selection(tool, gun)
				weapon.set_block_color(Color(0.8, 0.25, 0.15))
				weapon.set_ammo(6, 6)
				weapon.reload()
				weapon.fire()
				for step in range(21):
					var progress := float(step) / 20.0
					character.set_pose(step % 2 == 0, false, step % 3 == 0)
					character.set_aim(lerpf(-1.4, 1.4, progress))
					character.animate_motion(6.0, progress * 3.0)
					weapon.set_grenade_cook(progress * 2)
					weapon.set_spade_action(step % 2 == 0, progress)
					weapon.update_pose(0.05, step % 2 == 0, step % 3 == 0, step % 4 == 0, 6.0, progress)
					_check_transforms(character)
					_check_transforms(weapon)
					_check(weapon.get_muzzle_transform().origin.is_finite(), "Muzzle transform is finite")
					checks += 1
				weapon.reload_completed()
				weapon.update_pose(0.1, true, false, false, 0)
				character.set_pose(false, true, false)
				_check_transforms(character)
	character.set_team(2)
	_check(not character.visible, "Original spectators do not render a soldier")
	_check(_count_meshes(character) >= 9, "Original character parts must import")
	_check(_count_meshes(weapon) >= 5, "Original arms and equipment must import")
	character.set_team(0)
	var other := CharacterScript.new()
	root.add_child(other)
	other.set_team(1)
	_check(_team_color(character).is_equal_approx(Color(0.18, 0.42, 0.86)), "Blue soldier tint remains independent")
	_check(_team_color(other).is_equal_approx(Color(0.22, 0.66, 0.26)), "Green soldier receives its own tint")
	character.set_team(1)
	other.set_team(0)
	_check(_team_color(character).is_equal_approx(Color(0.22, 0.66, 0.26)), "Blue-to-green switch works")
	_check(_team_color(other).is_equal_approx(Color(0.18, 0.42, 0.86)), "Green-to-blue switch stays independent")
	print("PRESENTATION_CHECKS: ", checks, " pose/resource combinations, ", failures, " failures")
	character.queue_free()
	other.queue_free()
	weapon.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures == 0 else 1)

func _check_transforms(node: Node) -> void:
	if node is Node3D:
		var spatial := node as Node3D
		_check(spatial.transform.origin.is_finite(), "Pose position must be finite")
		_check(spatial.transform.basis.is_finite(), "Pose basis must be finite")
		_check(absf(spatial.transform.basis.determinant()) > 0.0000001, "Pose basis must not collapse")
	for child in node.get_children():
		_check_transforms(child)

func _count_meshes(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		count += _count_meshes(child)
	return count

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error("Presentation: " + description)

func _team_color(node: Node) -> Color:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.get_surface_override_material(surface) as StandardMaterial3D
			if material != null and material.resource_name == "TeamColor":
				return material.albedo_color
	for child in node.get_children():
		var color := _team_color(child)
		if color.r >= 0:
			return color
	return Color(-1, -1, -1, 1)
