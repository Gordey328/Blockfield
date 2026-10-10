extends SceneTree
## Actual source skin over fixed owner state; no Main, authority or preferences.
const WEAPON=preload("res://presentation/weapon_view.gd")
const MODELS=preload("res://presentation/openspades_models.gd")
var assertions:=0
var failures:=0
func _initialize() -> void:call_deferred("_run")
func check(value: bool,message: String) -> void:
	assertions+=1
	if not value:failures+=1;push_error("WEAPON SIMULATION MIRROR: "+message)
func _state(tool: int=2,displayed: int=2,gun: int=0,displayed_gun: int=0,raise_value: float=1,sprint: float=0,ads: float=0) -> Dictionary:
	return {"desired_tool":tool,"displayed_tool":displayed,"weapon":gun,"displayed_weapon":displayed_gun,"tool_raise":raise_value,"sprint_state":sprint,"aim_down_state":ads}
func _run() -> void:
	var view:=WEAPON.new();root.add_child(view)
	var raises: Array[Vector2i]=[]
	view.tool_raised.connect(func(tool: int,weapon: int):raises.append(Vector2i(tool,weapon)))
	var owner:=_state(0,2,1,0,.5,.25,.4)
	check(view.set_simulation_state(owner),"valid complete owner mirror accepted")
	check(view.get_displayed_tool()==2 and view._requested_tool==0 and view._weapon==0 and view._requested_weapon==1,"desired and displayed equipment remain distinct while old gun lowers")
	check(is_equal_approx(view._raise,.625),"source quadratic raise transform from raw0.5 equals0.625")
	check(view.is_changing_tool() and is_equal_approx(view.get_sprint_state(),.25) and is_equal_approx(view.get_aim_down_state(),.4),"native gate and camera getters retain exact approved raw values")
	owner.tool_raise=1;owner.displayed_tool=3
	check(is_equal_approx(view._raise_raw,.5) and view._tool==2,"caller mutation cannot change retained owner mirror")
	for delta in [0.0,.0001,.0166667,.1,2.0,100.0]:
		view.update_pose(delta,true,true,false,6)
		check(view._tool==2 and view._weapon==0 and is_equal_approx(view._raise_raw,.5),"variable render delta cannot switch or raise the mirrored tool")
		check(is_equal_approx(view.get_sprint_state(),.25) and is_equal_approx(view.get_aim_down_state(),.4),"variable render delta cannot integrate shared sprint/ADS twice")
		check(view._rig.transform.is_finite() and view._left_hand.is_finite() and view._right_hand.is_finite(),"source pose remains finite for supported render intervals")
	check(raises.is_empty(),"mirrored lowering never synthesizes a local tool raise signal")
	view.set_selection(3,2)
	check(view._requested_tool==0 and view._requested_weapon==1 and view._tool==2 and raises.is_empty(),"compatibility selection calls cannot overwrite mirrored authority or emit raise audio")
	view.set_animations_enabled(false);view.update_pose(.5,false,false,true,0)
	check(is_equal_approx(view.get_aim_down_state(),.4) and is_equal_approx(view.get_sprint_state(),.25) and is_equal_approx(view._raise_raw,.5),"animations preference cannot overwrite network raw state or native gates")
	var before:=view._simulation_state.duplicate(true)
	var invalid: Array[Dictionary]=[]
	var missing:=_state();missing.erase("tool_raise");invalid.append(missing)
	var extra:=_state();extra.unsafe=true;invalid.append(extra)
	for field in ["desired_tool","displayed_tool","weapon","displayed_weapon"]:
		for bad in [-1,4,0.5,true,"1"]:
			var value:=_state();value[field]=bad;invalid.append(value)
	for field in ["tool_raise","sprint_state","aim_down_state"]:
		for bad in [-.01,1.01,NAN,INF,true,"0.5"]:
			var value:=_state();value[field]=bad;invalid.append(value)
	for value in invalid:
		check(not view.set_simulation_state(value) and view._simulation_state==before,"invalid mirror fails atomically without changing retained state")
	check(view.set_simulation_state(_state(3,3,2,2,.998999,0,0)) and view.is_changing_tool(),"mirrored raw raise below native0.999 threshold remains gated")
	check(view.set_simulation_state(_state(3,3,2,2,.999,0,0)) and not view.is_changing_tool(),"mirrored raw raise at source threshold permits use despite eased value")
	check(raises.is_empty() and view._tool==3 and view._weapon==2,"confirmed displayed swap rebuilds silently rather than repeating predicted raise")
	check(view.set_simulation_state(_state(2,2,1,1,1,.7,1)) and view._parts.has("body"),"confirmed gun class selects actual original SMG assembly")
	view.update_pose(0,true,false,false,0)
	check(view.get_aim_down_state()==1 and view._raise==1,"confirmed fully aimed and raised pose reaches exact source values")
	view.refresh_resources();await process_frame;await process_frame
	check(view._tool==2 and view._weapon==1 and view.get_aim_down_state()==1 and is_equal_approx(view.get_sprint_state(),.7),"resource reload preserves and reapplies the shared owner mirror")
	view.set_animations_enabled(true)
	view.clear_simulation_state();view.update_pose(.1,false,false,false,0)
	check(is_equal_approx(view.get_aim_down_state(),.7) and is_equal_approx(view.get_sprint_state(),.4),"clear restores source offline ADS−3/s and sprint−3/s integration")
	view.set_selection(0,1);view.update_pose(.3,false,false,false,0)
	check(view._tool==0 and raises==[Vector2i(0,1)],"offline lower/swap resumes its original tool raised signal")
	view.queue_free();await process_frame;await process_frame;MODELS.clear_cache()
	print("WEAPON SIMULATION MIRROR: %d assertions, %d failures"%[assertions,failures])
	quit(0 if failures==0 else 1)
