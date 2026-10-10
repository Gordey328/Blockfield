extends SceneTree
const Observer = preload("res://presentation/spectator_view.gd")
const Models = preload("res://presentation/openspades_models.gd")
const Extensions = preload("res://presentation/openspades_extensions.gd")
const Weapon = preload("res://presentation/weapon_view.gd")
const Character = preload("res://presentation/character_view.gd")
var checks := 0
var failures := 0
var _factory_context: Dictionary = {}

class SessionDouble extends Node:
	var profile_version := "0.75"
	var current_weapon := 2
	var magazine := 1
	var authority_calls := 0
	var targets: Dictionary = {
		1:{"id":1,"position":Vector3(4,0,2),"alive":true,"health":100,"team":1,"weapon":0,"tool":2},
		2:{"id":2,"position":Vector3(-2,0,1),"alive":true,"health":100,"team":0,"weapon":2,"tool":3}}
	func get_target(id: int) -> Dictionary: return targets.get(id,{})
	func get_team_info(team: int) -> Dictionary:
		return {"color":Color(0.9,0.3,0.1) if team==1 else Color(0.2,0.6,0.8)}
	func try_fire() -> void: authority_calls += 1
	func reload_weapon() -> void: authority_calls += 1
	func damage_player(_amount: float) -> void: authority_calls += 1
	func damage_target(_id: int,_part: String,_distance: float) -> void: authority_calls += 1
	func get_weapon_info() -> Dictionary:
		authority_calls += 1 # The local weapon is deliberately unrelated to the observed one.
		return {"clip_size":6}

func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var session := SessionDouble.new()
	root.add_child(session)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(10,2,3)
	camera.rotation = Vector3(0.2,0.4,0)
	var camera_pose := camera.transform
	var observer := Observer.new()
	camera.add_child(observer)
	observer.setup(camera,session)
	_check(not observer.visible and observer._skin==null,"Setup starts without visible observed equipment")
	var original := session.targets.duplicate(true)
	observer.show_target(1,true)
	_check(observer.visible and observer._skin!=null,"Live followed soldier creates visible first-person equipment")
	_check(observer._skin._tool==2 and observer._skin._weapon==0,"Observed weapon selection comes from target rather than local player")
	_check(observer._skin._ammo==10 and observer._skin._clip_size==10,"Absent ammo snapshot uses observed profile clip")
	_check(observer._skin._team_color==session.get_team_info(1).color,"Observed uniform uses target team metadata")
	_check(observer._skin._action_type==0 and not observer._skin._reloading and is_zero_approx(observer._skin._aim),"Missing action fields produce idle non-aiming presentation")
	_check(session.targets==original and session.authority_calls==0,"Showing target leaves authority snapshots and local weapon state untouched")
	_check(camera.transform==camera_pose,"Presentation never modifies follow-camera transform")
	var first_skin := observer._skin
	observer.show_target(1,true)
	_check(observer._skin==first_skin,"Repeated follow selection does not recreate observed skin")
	session.targets[1].position += Vector3(0,0,-0.3)
	observer.show_target(1,true)
	observer.update_view(0.1)
	_check(observer._skin._local_velocity.is_equal_approx(Vector3(0,0,-3)),"Previous position supplies world motion in observed camera-local axes")
	_check(is_equal_approx(observer._skin._walk_progress,0.045),"Missing walk phase uses source half-distance .15 factor")
	session.targets[1].merge({"yaw":PI/2,"pitch":0.2,"velocity":Vector3(3,0,0),"walk_progress":0.25,"aiming":true,"state":"crouching","ammo":4,"clip_size":12,"team_color":Color(0.8,0.2,0.6)},true)
	observer.update_view(0.1)
	var axes := Basis.from_euler(Vector3(0.2,PI/2,0))
	_check(observer._skin._local_velocity.is_equal_approx(axes.inverse()*Vector3(3,0,0)),"Pitch/yaw convert explicit target velocity without relying on local camera orientation")
	_check(is_equal_approx(observer._skin._aim,0.8) and is_equal_approx(observer._skin._walk_progress,0.25),"Optional ADS and walk phase reach original skin state")
	_check(observer._skin._ammo==4 and observer._skin._clip_size==12 and observer._skin._team_color==Color(0.8,0.2,0.6),"Target ammo/clip/custom team color override defaults")
	session.targets[1].aiming = false
	session.targets[1].state = "sprinting"
	observer.update_view(0.1)
	_check(is_equal_approx(observer._skin._sprint_state,0.4),"Observed sprint feeds original view easing")
	session.targets[1].merge({"is_reloading":true,"reload_progress":0.3},true)
	observer.update_view(0.05)
	_check(observer._skin._reloading and is_equal_approx(observer._skin._reload_progress,0.3),"Optional remote reload snapshot animates magazine stage")
	session.targets[1].reload_progress = 0.05
	observer.update_view(0.05)
	_check(observer._skin._reloading and is_equal_approx(observer._skin._reload_progress,0.05),"Restarted remote shell cycle resets inherited reload state")
	session.targets[1].merge({"is_reloading":false,"reload_cancelled":true},true)
	observer.update_view(0.01)
	_check(not observer._skin._reloading and observer._skin._post_reload_elapsed<0,"Cancelled remote reload does not invent a completed pump")
	session.targets[1].shot_sequence = 10
	observer.update_view(0.01)
	_check(is_equal_approx(observer._skin._fire_elapsed,.01),"First preview shot after an absent sequence uses the zero baseline")
	_check(observer.get_camera_motion_state().fire_age==0.0,"Observed shot updates camera vibration without touching authority")
	session.targets[1].shot_sequence = 11
	observer.update_view(0.01)
	_check(is_equal_approx(observer._skin._fire_elapsed,0.01) and session.authority_calls==0,"Sequence change invokes only view recoil and never session fire")
	observer.update_view(.05)
	_check(is_equal_approx(observer.get_camera_motion_state().fire_age,.05),"Follow camera vibration decays from observed shot age")
	observer.animations_enabled=false
	session.targets[1].state="standing"
	session.targets[1].aiming=true
	observer.update_view(.001)
	_check(observer.get_aim_down_state()==1.0,"Disabled animation uses instant target ADS, including follow zoom")
	observer.animations_enabled=true
	session.targets[2].merge({"cook_time":0.125,"ready_state":1.5,"action":{"type":0,"progress":0,"ready":1.5},"shot_sequence":30},true)
	observer.show_target(2,true)
	_check(observer._skin!=first_skin and observer._skin._tool==3,"Changing observed player initializes its tool without showing old player's gun")
	_check(observer.get_displayed_tool()==3 and observer._skin._fire_elapsed>1.0,"Joining observed nonzero sequence establishes baseline without phantom fire")
	_check(is_equal_approx(observer._skin._cook_time,0.125) and observer._skin._ammo==6,"Observed grenade cook and selected shotgun profile remain target-owned")
	_check(observer._skin._raise==1.0 and is_zero_approx(observer._skin._sprint_state) and is_zero_approx(observer._skin._aim),"New observed soldier does not inherit prior sprint/ADS/tool lowering")
	session.profile_version = "0.76"
	observer.update_view(0.0)
	_check(observer._skin._ammo==8 and observer._skin._clip_size==8,"Missing ammo follows live active profile changes")
	session.targets[2].profile = "0.75"
	observer.update_view(0.0)
	_check(observer._skin._ammo==6 and observer._skin._clip_size==6,"Explicit target profile overrides local profile choice")
	_check(_layers_are(observer._skin,Observer.VIEW_LAYER),"Observed equipment excludes world-reflection render layers")
	observer.refresh_resources()
	await process_frame
	await process_frame
	_check(observer.visible and observer._skin._tool==3 and observer.get_child_count()==1,"Resource refresh retains observed selection without orphaned skins")
	_check(_layers_are(observer._skin,Observer.VIEW_LAYER),"Resource refresh preserves reflection exclusion")
	session.targets[2].alive = false
	observer.update_view(0.1)
	_check(not observer.visible,"Dead observed soldier has no first-person equipment")
	var dead_skin := observer._skin
	session.targets[2].alive = true
	observer.update_view(0.1)
	_check(observer.visible and observer._skin!=dead_skin,"Respawn rebuilds observed view without stale death pose state")
	session.targets[2].health = 0
	observer.update_view(0.1)
	_check(not observer.visible,"Zero-health snapshot hides even with stale alive flag")
	session.targets[2].health = 100
	session.targets[2].team = 2
	observer.update_view(0.1)
	_check(not observer.visible,"Spectator team cannot render live soldier equipment")
	session.targets[2].team = 0
	observer.show_target(99,true)
	_check(not observer.visible,"Missing followed soldier safely hides view")
	observer.show_target(2,true)
	observer.show_target(2,false)
	_check(not observer.visible,"Leaving first-person-follow hides observed equipment")
	var result := Extensions.register_skin("observer-test",_first_factory,func(_context: Dictionary) -> Node3D: return Character.new())
	_check(result.ok,"Trusted spectator skin factory registers")
	observer.set_skin("observer-test")
	observer.show_target(1,true)
	_check(_factory_context.get("spectator",false) and not _factory_context.get("local_audio",true),"Trusted skin receives spectator and disabled local-audio context")
	_check(not _factory_context.has("session") and _factory_context.snapshot==session.targets[1],"Factory receives copied snapshot without live session authority")
	_factory_context.snapshot.health = 1
	_check(session.targets[1].health==100,"Factory snapshot mutation cannot edit authority target")
	_check(not observer.set_skin("missing") and observer._skin_id=="observer-test","Unknown skin cannot replace active spectator view")
	observer.clear()
	await process_frame
	await process_frame
	_check(not observer.visible and observer._skin==null and observer.get_child_count()==0,"Clear releases camera equipment and follow state")
	_check(session.authority_calls==0 and session.current_weapon==2 and session.magazine==1,"No spectator update calls authority or changes local weapon/ammo")
	_check(not _has_audio(observer),"Adapter never creates or connects own-local sound players")
	observer.show_target(1,true)
	_check(observer.visible,"Clear retains setup references for the next valid follow target")
	camera.queue_free()
	session.queue_free()
	await process_frame
	await process_frame
	Extensions.clear()
	Models.clear_cache()
	print("SPECTATOR_VIEW_CHECKS: %d assertions, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)

func _first_factory(context: Dictionary) -> Node3D:
	_factory_context = context
	return Weapon.new()
func _layers_are(node: Node,layer: int) -> bool:
	if (node is MeshInstance3D or node is MultiMeshInstance3D) and node.layers!=layer: return false
	for child in node.get_children():
		if not _layers_are(child,layer): return false
	return true
func _has_audio(node: Node) -> bool:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D or node is AudioStreamPlayer2D: return true
	for child in node.get_children():
		if _has_audio(child): return true
	return false
func _check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
