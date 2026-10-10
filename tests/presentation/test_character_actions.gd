extends SceneTree
const Character = preload("res://presentation/character_view.gd")
const Models = preload("res://presentation/openspades_models.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var view := Character.new()
	root.add_child(view)
	view.set_weapon(0,0)
	view.set_aim(0.3)
	view.set_tool_action(Character.ToolAction.IDLE)
	var original_head := view._head.transform
	var idle_arms := view._arms.transform
	_check(_forward(view._arms.transform.basis).is_equal_approx(Vector3(0,sin(0.3),-cos(0.3))),"Native positive pitch points upward")
	_check(view._equipment.position.x > 0,"Third-person held equipment is in source right hand")
	_check(_has_native_tool_color(view._equipment),"Native spade has no team tint, including customColor defaults")
	view.set_tool_action(Character.ToolAction.BASH,0)
	_check(_forward(view._arms.transform.basis).is_equal_approx(Vector3(0,sin(-0.36),-cos(-0.36))),"Source Bash bias .7 and negative pitch .9 are applied")
	_check(view._head.transform == original_head,"Spade Bash changes arms without moving head")
	view.set_tool_action(Character.ToolAction.BASH,1)
	_check(view._arms.transform.is_equal_approx(idle_arms),"Bash completion returns to native idle pitch")
	view.set_tool_action(Character.ToolAction.DIG,0.4)
	_check(view._arms.transform.is_equal_approx(idle_arms),"Native third-person digging has no invented pitch bias")
	view.set_pose(false,false,true)
	_check(_forward(view._arms.transform.basis).is_equal_approx(Vector3(0,sin(-0.18),-cos(-0.18))),"Sprint subtracts .5 before negative-pitch attenuation")
	view.set_pose(false,false,false)
	view.set_weapon(0,3)
	_check(_has_native_tool_color(view._equipment),"Native grenade has no team tint")
	view.set_tool_action(0,0,0,1,1)
	var grenade_idle := view._equipment.transform
	view.set_tool_action(0,0,3.0,0.1,0)
	_check(view._equipment.transform.is_equal_approx(grenade_idle),"Source third-person grenade stores cook/ready/raise without fake animation")
	_check(view._cook_time == 3.0 and view._ready_state == 0.1 and view._raise_state == 0.0,"Action state is supplied to skin contract")
	for gun in range(3):
		view.set_weapon(gun,2)
		_check(_has_native_tool_color(view._equipment),"Native gun retains original fixed colors")
		view.set_team(1-gun%2)
		_check(_has_native_tool_color(view._equipment),"Team switch preserves original fixed gun colors")
	view.set_weapon(0,1)
	view.set_block_color(Color(0.9,0.2,0.1))
	_check(_tint(view._equipment).is_equal_approx(Color(0.9,0.2,0.1)),"Held block uses block color rather than team color")
	view.set_team(1)
	_check(_tint(view._equipment).is_equal_approx(Color(0.9,0.2,0.1)),"Team switch does not replace held block color")
	view.set_aim(0)
	view.set_motion_state(6,0,0.25)
	var left_tip := view._legs[0].transform * (Models.SOURCE_AXES*Vector3(0,0,10))
	var right_tip := view._legs[1].transform * (Models.SOURCE_AXES*Vector3(0,0,10))
	_check(is_equal_approx(left_tip.z,-sin(0.45)) and is_equal_approx(right_tip.z,sin(0.45)),"Native forward gait converts m/s to /32 velocity and alternates legs")
	view.set_motion_state(-6,0,0.25)
	_check((view._legs[0].transform*(Models.SOURCE_AXES*Vector3(0,0,10))).z > 0,"Walking backward reverses leg swing")
	view.set_motion_state(0,8,0.25)
	left_tip = view._legs[0].transform*(Models.SOURCE_AXES*Vector3(0,0,10))
	_check(is_equal_approx(left_tip.x,-0.25+sin(0.45)),"Native sideways gait uses independent source-Y rotation")
	view.set_motion_state(6,8,0)
	_check((view._legs[0].transform*(Models.SOURCE_AXES*Vector3(0,0,10))).is_equal_approx(Vector3(-0.25,-0.9,0)),"Zero walk phase has no leg rotation")
	view.set_pose(true,false,false)
	_check(is_equal_approx(view._rig.position.y,0.7) and view._torso.position.is_equal_approx(Vector3(0,0.55,0)),"Crouch retains source feet/origin offsets")
	view.set_pose(false,true,false)
	_check(view._corpse.visible,"Static source Dead model remains available when ragdoll disabled")
	var dead_basis := view._corpse.global_basis
	view.rotation.y = PI*0.5
	view.set_pose(false,true,false)
	_check(view._corpse.global_basis.is_equal_approx(dead_basis),"Native static dead fallback ignores player yaw")
	view.set_pose(true,true,false)
	_check(view._corpse.global_position.is_equal_approx(view.global_position+Vector3.DOWN*0.3),"Static dead fallback retains crouching GetOrigin height")
	view.set_ragdoll_enabled(true)
	_check(not view._corpse.visible and not view._head.visible,"Ragdoll mode hides duplicate Character dead body")
	view.set_pose(false,false,false)
	view.set_intel_carrier(true,Color(0.8,0.25,0.7))
	_check(_tint(view._intel).is_equal_approx(Color(0.8,0.25,0.7)),"Enemy intel uses authority-supplied custom team color")
	view.refresh_resources()
	_check(_tint(view._intel).is_equal_approx(Color(0.8,0.25,0.7)),"Resource refresh preserves authority intel color")
	view.queue_free()
	await process_frame
	await process_frame
	Models.clear_cache()
	print("CHARACTER_ACTION_CHECKS: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
func _forward(basis: Basis) -> Vector3:
	return (basis*Models.SOURCE_AXES*Vector3(0,1,0)).normalized()
func _has_native_tool_color(node: Node) -> bool:
	var color := _tint(node)
	# Original default weapon/spade/grenade meshes have no black sentinel faces;
	# a replacement that does have them must receive the native black default.
	return color.r < 0 or color.is_equal_approx(Color.BLACK)
func _tint(node: Node) -> Color:
	if node is MeshInstance3D:
		for index in range(node.mesh.get_surface_count()):
			var material = node.get_surface_override_material(index)
			if material is StandardMaterial3D and material.resource_name == "TeamColor": return material.albedo_color
	for child in node.get_children():
		var color := _tint(child)
		if color.r >= 0: return color
	return Color(-1,-1,-1,1)
func _check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
