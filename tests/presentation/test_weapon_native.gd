extends SceneTree
const Weapon = preload("res://presentation/weapon_view.gd")
const Models = preload("res://presentation/openspades_models.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var view := Weapon.new()
	root.add_child(view)
	_neutral(view,2,0)
	view._update_gun(Vector3.ZERO)
	_check(view._rig.global_position.is_equal_approx(Vector3(0.13,-0.2,-0.5)),"Source GetEyeMatrix places idle rifle on the right")
	_check(view._parts.body.global_position.is_equal_approx(Vector3(0.13825,-0.2,-0.5)),"Rifle half-resolution model keeps source half-voxel correction")
	_check(_hand(view,view._left_hand).is_equal_approx(Vector3(0.097,-0.233,-0.698)),"Literal native hip left-hand fixture")
	_check(_hand(view,view._right_hand).is_equal_approx(Vector3(0.13,-0.266,-0.236)),"Literal native hip right-hand fixture")
	view._update_view_arms()
	_check(view._upperarms[0].global_position.is_equal_approx(Vector3(-0.4,-0.25,0)),"Native LeftHand shoulder is screen left")
	_check(view._upperarms[1].global_position.is_equal_approx(Vector3(0.4,-0.25,0)),"Native RightHand shoulder is screen right")
	_check(view.get_muzzle_transform().origin.is_equal_approx(Vector3(0.13,-0.2,-1.5)),"ClientPlayer::FiredWeapon uses fixed source eye-local muzzle")
	view._aim = 1.0
	view._update_gun(Vector3.ZERO)
	_check(_hand(view,view._left_hand).is_equal_approx(Vector3(-0.033,-0.181,-0.698)),"ADS rifle resting hand retains pre-sight-alignment fixture")
	_check(not view._hand_point(Vector3(1,6,1)).is_equal_approx(view._aligned_hand_point(Vector3(1,6,1))),"Sight alignment adjusts geometry separately from native resting hands")
	var sight: Vector3 = view._rig.transform*Models.source_vector(Vector3(0,16,-4.6))
	_check(absf(sight.x)<0.000001 and absf(sight.y)<0.000001,"Full ADS centers original rifle front sight")
	_check(view.get_muzzle_transform().origin.is_equal_approx(Vector3(0.13,-0.2,-1.5)),"Native muzzle FX point is independent of sight alignment")
	for gun in range(2):
		_neutral(view,2,gun)
		view._reloading = true
		for progress in [0.02,0.2,0.4,0.6,0.8,0.95]:
			view._reload_progress = progress
			view._update_gun(Vector3.ZERO)
			_check(view._left_hand.is_finite() and view._right_hand.is_finite(),"Native magazine/bolt hand stage is finite")
		view._reload_progress = 0.5
		view._update_gun(Vector3.ZERO)
		_check(is_equal_approx(view._parts.magazine.position.y,-1.9),"Source non-smooth magazine insertion fixture")
	_neutral(view,2,2)
	view._ready_state = 0.65
	view._update_gun(Vector3.ZERO)
	_check(view._parts.pump.position.is_equal_approx(Vector3(0,0,1.5)),"Native shotgun remaining-fire-time .35 holds pump back")
	view._reloading = true
	view._reload_progress = 0.8
	view.set_ammo(4,6)
	view._update_gun(Vector3.ZERO)
	_check(view._parts.pump.position.is_equal_approx(Vector3.ZERO),"Intermediate shell reload suppresses pump")
	view.set_ammo(5,6)
	view._update_gun(Vector3.ZERO)
	_check(view._parts.pump.position.is_equal_approx(Vector3(0,0,1.5)),"Last shell reload blends original pump timing")
	view.set_ammo(6,6)
	view._ready_state = 1.5
	view._reloading = false
	view._reload_progress = 1.24
	view._update_gun(Vector3.ZERO)
	_check(view._parts.pump.position.is_equal_approx(Vector3(0,0,1.5)),"Native completed reload progress above one drives final pump")
	view.reload_completed()
	view.cancel_reload()
	view.update_pose(0.12,false,false,false,0)
	_check(is_equal_approx(view._reload_progress,1.24) and view._parts.pump.position.is_equal_approx(Vector3(0,0,1.5)),"Completed reload advances native pump even after owner cleanup")
	view.update_pose(0.3,false,false,false,0)
	_check(view._parts.pump.position.is_equal_approx(Vector3.ZERO),"Completed reload pump returns without firing a fake shot")
	_neutral(view,0,0)
	view.set_tool_action(Weapon.ToolAction.DIG_START,0.0)
	view._update_tool(Vector3.ZERO)
	_check(view._rig.global_position.is_equal_approx(Vector3(0.3,-0.3,-0.7)),"First dig begins in idle instead of repeated dig ready pose")
	view.set_tool_action(Weapon.ToolAction.DIG_START,0.25)
	view._update_tool(Vector3.ZERO)
	_check(view._rig.global_position.is_equal_approx(Vector3(0.225,-0.296,-0.68)),"Literal source first-dig quadratic position fixture")
	view.set_tool_action(Weapon.ToolAction.DIG,0.0)
	view._update_tool(Vector3.ZERO)
	_check(view._rig.global_position.is_equal_approx(Vector3(0,-0.324,-0.82)),"Repeated dig has original side/front pre-position")
	view.set_tool_action(Weapon.ToolAction.BASH,0.0)
	view._update_tool(Vector3.ZERO)
	_check(view._rig.global_position.is_equal_approx(Vector3(0.3,-0.3,-1.0)),"Literal source first-person Bash fixture")
	_neutral(view,1,0)
	view.set_tool_action(0,0,0.0)
	view._update_tool(Vector3.ZERO)
	_check(not view._rig.visible and _hand(view,view._left_hand).is_equal_approx(Vector3(-0.5,-0.6,-0.5)),"Unready block hides mesh and uses original rest hands")
	_neutral(view,3,0)
	view.set_tool_action(0,0,0.2)
	view._update_tool(Vector3.ZERO)
	_check(not view._rig.visible and _hand(view,view._right_hand).is_equal_approx(Vector3(0.2,-0.18,-0.9)),"Grenade throw uses normalized .5-second ready state")
	view.set_tool_action(0,0,1.0)
	view._update_tool(Vector3.ZERO)
	_check(view._rig.visible and view._rig.global_position.is_equal_approx(Vector3(0.3,-0.45,-0.8)),"Grenade ready threshold starts source bring-up")
	view.set_tool_action(0,0,1.5)
	view._update_tool(Vector3.ZERO)
	_check(view._rig.global_position.is_equal_approx(Vector3(0.3,-0.3,-0.7)),"Ready state above one finishes source grenade bring-up")
	view.set_grenade_cook(0.25)
	view.set_tool_action(0,0,1.0)
	view._update_tool(Vector3.ZERO)
	_check(view._rig.global_position.is_equal_approx(Vector3(1.1,-0.75,-1.0)),"Native grenade pin/side/cook fixture")
	_neutral(view,2,0)
	view.update_pose(0.1,true,true,false,0)
	_check(is_equal_approx(view._sprint_state,0.4),"Native sprint raw state rises at four per second")
	_check(is_equal_approx(view._sprint,pow(0.352,2.0)*(1.0-pow(0.001,0.1))),"Native sprint smoothstep-square and skin exponential are distinct")
	view.update_pose(0.1,true,false,false,0)
	_check(is_equal_approx(view._aim,0.8),"Native ADS rises at eight per second")
	view.update_pose(0.1,false,false,false,0)
	_check(is_equal_approx(view._aim,0.5),"Native ADS falls at three per second")
	_neutral(view,2,0)
	var tool_events: Array[Vector2i] = []
	view.tool_raised.connect(func(tool: int,gun: int) -> void: tool_events.append(Vector2i(tool,gun)))
	view._aim = 1.0
	view.set_selection(0,0)
	_check(is_equal_approx(view._aim,1.0),"Tool selection retains source ADS state for its decay")
	view.update_pose(0.125,false,false,false,0)
	_check(view._tool==2 and is_equal_approx(view._raise,0.625),"Source tool switch first lowers the previous view tool")
	_check(tool_events.is_empty() and is_equal_approx(view._aim,0.625),"Raise audio signal waits for source swap while ADS decays")
	view.update_pose(0.126,false,false,false,0)
	_check(view._tool==0 and is_zero_approx(view._raise),"Source tool switches after lowering")
	_check(tool_events==[Vector2i(0,0)],"Tool raised signal reports new source tool once")
	view.update_pose(0.125,false,false,false,0)
	_check(is_equal_approx(view._raise,0.625),"Source new tool uses squared/clamped raising curve")
	_check(tool_events.size()==1,"Continuing raise does not repeat source tool audio signal")
	view.initialize_selection(3,2)
	_check(view._tool==3 and view._weapon==2 and view._raise==1.0 and tool_events.size()==1,"Initial camera-target selection has no live tool transition or raise signal")
	_check(not view.is_changing_tool(),"Fresh initialized skin does not delay tool authority")
	view.set_selection(0,2)
	_check(view.is_changing_tool(),"Native action gate rejects the previous lowering tool")
	_check(view.get_displayed_tool()==3,"Reticle keeps displayed old tool during lowering")
	view.update_pose(0.25001,false,false,false,0)
	_check(view._tool==0 and view.is_changing_tool(),"Native action gate rejects newly selected unraised tool")
	_check(view.get_displayed_tool()==0,"Reticle changes on the actual tool swap before raise completes")
	view.update_pose(0.2497,false,false,false,0)
	_check(view._raise>0.999 and view.is_changing_tool(),"Native gate uses raw .9988 raise counter despite nearly complete eased mesh")
	view.update_pose(0.00006,false,false,false,0)
	_check(not view.is_changing_tool(),"Native .999 raw threshold releases tool-use gate")
	_neutral(view,2,0)
	view.set_animations_enabled(false)
	view.update_pose(.001,true,false,false,0)
	_check(view.get_aim_down_state()==1.0,"Disabled ADS animation reaches the aimed endpoint immediately")
	view.update_pose(.001,false,false,false,0)
	_check(view.get_aim_down_state()==0.0,"Disabled ADS animation exits immediately")
	view.set_animations_enabled(true)
	view.set_motion_state(Vector3(4,2,-6),0.25,Vector3(0.1,0.2,0))
	var swing := view._update_swing(0.1,false,0)
	_check(view._view_offset.x>0 and view._view_offset.y<0 and view._view_offset.z>0,"Native view inertia responds to camera-local movement and turn")
	_check(swing.is_finite(),"Native bob/pulse/inertia swing remains finite")
	view._view_offset = Vector3(0.08,0,0.08)
	view._local_velocity = Vector3.ZERO
	view._front_delta = Vector3.ZERO
	view._update_swing(0.01,true,0)
	_check(absf(view._view_offset.x)<=0.003001 and view._view_offset.z<=0.003001,"Native ADS soft limits keep inertia clear of ironsights")
	view.set_team(1,Color(1,0.35,0.05))
	_check(_tint_is(view._forearms[0],Color(1,0.35,0.05)),"Source arm sentinel follows authority custom team color")
	_check(_sentinel_count(view._rig)==0,"Original rifle surfaces preserve fixed voxel colors with no team sentinel")
	_check(_layers_are(view,Weapon.VIEW_LAYER),"All first-person equipment occupies the reflection-excluded view layer")
	view.refresh_resources()
	await process_frame
	await process_frame
	_check(view.get_child_count()==1 and view._source_root.get_child_count()==5,"Resource refresh retains one view-axis root without stale assemblies")
	_check(_layers_are(view,Weapon.VIEW_LAYER) and _tint_is(view._forearms[0],Color(1,0.35,0.05)),"Resource refresh preserves view layer and custom arm tint")
	view.queue_free()
	await process_frame
	await process_frame
	Models.clear_cache()
	print("WEAPON_NATIVE_CHECKS: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)

func _neutral(view: Node3D,tool: int,gun: int) -> void:
	view._tool = tool
	view._weapon = gun
	view._requested_tool = tool
	view._requested_weapon = gun
	view._raise_raw = 1.0
	view._raise = 1.0
	view._sprint_state = 0.0
	view._sprint = 0.0
	view._aim = 0.0
	view._time = 0.0
	view._vibration = 0.0
	view._view_offset = Vector3.ZERO
	view._fire_elapsed = 1000.0
	view._reloading = false
	view._reload_progress = 0.0
	view._post_reload_elapsed = -1.0
	view._source_ready = false
	view._source_action = false
	view._cook_time = 0.0
	view._ready_state = 1.0
	view.set_motion_state(Vector3.ZERO,0)
	view._rebuild_parts()
func _hand(view: Node3D,hand: Vector3) -> Vector3: return view._source_root.global_transform*hand
func _layers_are(node: Node,expected: int) -> bool:
	if (node is MeshInstance3D or node is MultiMeshInstance3D) and node.layers!=expected: return false
	for child in node.get_children():
		if not _layers_are(child,expected): return false
	return true
func _sentinel_count(node: Node) -> int:
	if node.is_queued_for_deletion(): return 0
	var count := 0
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			if node.get_surface_override_material(surface).resource_name=="TeamColor": count += 1
	for child in node.get_children(): count += _sentinel_count(child)
	return count
func _tint_is(node: Node,expected: Color) -> bool:
	if _sentinel_count(node)==0: return false
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			var material: StandardMaterial3D = node.get_surface_override_material(surface)
			if material.resource_name=="TeamColor" and material.albedo_color!=expected: return false
	for child in node.get_children():
		if _sentinel_count(child)>0 and not _tint_is(child,expected): return false
	return true
func _check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
