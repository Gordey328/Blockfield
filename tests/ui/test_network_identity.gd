extends SceneTree
## Isolated real HUD controls/character views. No main or preference writes.
const SESSION = preload("res://gameplay/local_session.gd")
const SOLDIER = preload("res://gameplay/lab_soldier.gd")
const HUD = preload("res://ui/lab_hud.gd")
const SCOREBOARD = preload("res://ui/lab_scoreboard.gd")
const PLAYER = preload("res://gameplay/player_controller.gd")
const OBSERVER = preload("res://presentation/spectator_view.gd")
const MODELS = preload("res://presentation/openspades_models.gd")
const EXTENSIONS = preload("res://presentation/openspades_extensions.gd")
var assertions := 0
var failures := 0

class RemoteSession extends LocalSession:
	func local_player_id() -> int: return 43

class AppDouble extends Node3D:
	var player_name := "Local actor43"

func _initialize() -> void: call_deferred("_run")
func check(value: bool,message: String) -> void:
	assertions += 1
	if not value: failures += 1;push_error("NETWORK PRESENTATION IDENTITY: " + message)
func _run() -> void:
	var existed := FileAccess.file_exists("user://settings.cfg")
	var settings_before := FileAccess.get_file_as_bytes("user://settings.cfg") if existed else PackedByteArray()
	var session := RemoteSession.new()
	root.add_child(session)
	session.mode="ctf"
	var target := {"id":14,"name":"Remote soldier","position":Vector3(12,4,20),"health":-1,"health_known":false,"alive":true,"team":1,"weapon":0,"tool":2,"state":"walking","moving":false,"yaw":0.0,"pitch":0.0,"carries_intel":true}
	session.targets.assign([target])
	var soldier := SOLDIER.new()
	root.add_child(soldier)
	soldier.setup(session,14,target.position)
	soldier.set_process(false)
	soldier._process(0.1)
	check(not soldier.character._dead,"unknown negative remote HP does not create false death pose")
	check(soldier._label.text == "Remote soldier" and "HP" not in soldier._label.text,"public remote name rendered without invented numeric HP")
	check(soldier.character._carrying_intel,"network carries_intel independent of walking pose attaches intel")
	check(_collision_layers(soldier,2),"live remote hit areas remain selectable with unknown HP")
	target.alive=false;target.health=100
	soldier._process(0.1)
	check(soldier.character._dead and _collision_layers(soldier,0),"canonical dead remote state drives corpse pose and disables hit areas")
	check(not soldier.character._carrying_intel,"dead remote view cannot retain carried intel")
	check("HP" not in soldier._label.text,"dead public state still does not reveal numeric HP")
	target.alive=true;target.health=-1
	soldier._process(0.1)
	check(not soldier.character._dead and _collision_layers(soldier,2),"confirmed remote respawn restores model and selectable volumes")
	target.health_known=true;target.health=0
	soldier._process(0.1)
	check(soldier.character._dead and "0 HP" in soldier._label.text,"offline known HP0 still drives death and numeric lab label")
	target.health=100;target.carries_intel=false;target.state="standing"
	soldier._process(0.1)
	check(not soldier.character._dead and "100 HP" in soldier._label.text,"offline HP label and living pose retained")
	target.erase("carries_intel");target.state="intel"
	soldier._process(0.1)
	check(soldier.character._carrying_intel,"legacy offline intel pose remains supported")
	target.state="standing";target.health_known=false;target.health=-1
	var hud := HUD.new()
	root.add_child(hud)
	hud.set_process(false)
	hud.session=session
	hud._cross=TextureRect.new();hud.add_child(hud._cross)
	hud._hit=TextureRect.new();hud.add_child(hud._hit)
	hud._intel_icon=TextureRect.new();hud.add_child(hud._intel_icon)
	# Player stays outside the tree: no scene setup, inputs, audio or authority.
	var player := PLAYER.new()
	player.session=session
	player.followed_target_id=14
	player.camera_mode=BlockfieldPlayer.CameraMode.FOLLOW_FIRST_PERSON
	hud.player=player
	session.team=2;session.health=0
	hud._hit_time=1
	hud._update_reticle(0)
	check(hud._cross.visible and hud._hit.visible,"spectator follows live unknown-HP actor with native reticle and confirmation")
	target.alive=false;target.health=100
	hud._update_reticle(0)
	check(not hud._cross.visible and not hud._hit.visible,"unknown-HP dead actor hides followed reticle despite numeric placeholder")
	target.alive=true;target.health_known=true;target.health=0
	hud._update_reticle(0)
	check(not hud._cross.visible,"known HP0 follow remains invalid with stale alive flag")
	target.health_known=false;target.health=-1;target.team=2
	hud._update_reticle(0)
	check(not hud._cross.visible,"spectator target is never a followed combat actor")
	target.team=1
	player.followed_target_id=999
	hud._update_reticle(0)
	check(not hud._cross.visible,"missing remote actor safely hides reticle")
	player.followed_target_id=14
	player.camera_mode=BlockfieldPlayer.CameraMode.FIRST_PERSON
	session.team=0;session.health=100
	hud._update_reticle(0)
	check(hud._cross.visible,"offline/local own known HP first-person reticle retained")
	session.health=0;hud._update_reticle(0)
	check(not hud._cross.visible,"own death still hides first-person reticle")
	session.ctf_flags.assign([{"team":1,"carrier":43,"position":Vector3.ZERO}])
	hud._update_intel_indicator(true)
	check(session.local_player_id() == 43 and session.is_local_intel_carrier() and hud._intel_icon.visible,"positive authenticated actor ID drives local intel HUD")
	session.ctf_flags[0].carrier=0
	hud._update_intel_indicator(true)
	check(not session.is_local_intel_carrier() and not hud._intel_icon.visible,"legacy actor0 cannot impersonate network owner carrier")
	session.ctf_flags[0].carrier=14
	hud._update_intel_indicator(true)
	check(not hud._intel_icon.visible,"another remote carrier does not show local intel icon")
	session.ctf_flags[0].carrier=43
	hud._update_intel_indicator(false)
	check(not hud._intel_icon.visible,"dead/inactive local carrier icon hidden")
	hud._update_intel_indicator(true);session.mode="sandbox";hud._update_intel_indicator(true)
	check(not hud._intel_icon.visible,"stale CTF carrier does not show in sandbox")
	var offline := SESSION.new()
	root.add_child(offline)
	offline.mode="ctf";offline.ctf_flags[1].carrier=0
	check(offline.local_player_id() == 0 and offline.is_local_intel_carrier(),"offline session preserves actor0 intel helper")
	offline.ctf_flags[1].carrier=1
	check(not offline.is_local_intel_carrier(),"offline remote lab carrier does not count as local")
	var app := AppDouble.new()
	var scoreboard := SCOREBOARD.new()
	scoreboard.main=app;scoreboard.session=session
	session.score=5;session.player_deaths=2;session.health=100;session.team=0
	var rows := scoreboard.get_rows()
	check(rows.size() == 2 and rows[0].id == 43 and rows[0].local and rows[1].id == 14 and not rows[1].local,"scoreboard shows canonical positive local ID and untouched remote ID")
	check(rows[0].score == 5 and rows[0].deaths == 2 and rows[1].alive,"scoreboard local highlight/score and remote alive use same session contract")
	check(not rows[1].has("health"),"remote scoreboard never invents HP")
	scoreboard.session=offline
	check(scoreboard.get_rows()[0].id == 0,"offline scoreboard local ID0 compatibility")
	var camera := Camera3D.new();root.add_child(camera)
	var observer := OBSERVER.new();camera.add_child(observer)
	observer.set_process(false);observer.setup(camera,session)
	target.health_known=false;target.health=-1;target.alive=true;target.team=1
	observer.show_target(14,true)
	check(observer.visible and observer._skin != null,"actual first-person followed equipment renders unknown-HP living actor")
	target.alive=false;target.health=100;observer.update_view(.1)
	check(not observer.visible,"canonical unknown-HP death hides followed equipment")
	target.alive=true;target.health=-1;observer.update_view(.1)
	check(observer.visible,"unknown-HP respawn restores followed first-person equipment")
	target.health_known=true;target.health=0;observer.update_view(.1)
	check(not observer.visible,"known HP0 still suppresses followed equipment")
	check(FileAccess.file_exists("user://settings.cfg") == existed and (not existed or FileAccess.get_file_as_bytes("user://settings.cfg") == settings_before),"isolated presentation checks leave settings byte-for-byte unchanged")
	player.free();scoreboard.free();app.free()
	soldier.queue_free();hud.queue_free();camera.queue_free();session.queue_free();offline.queue_free()
	await process_frame
	await process_frame
	EXTENSIONS.clear()
	MODELS.clear_cache()
	print("NETWORK PRESENTATION IDENTITY: %d assertions, %d failures" % [assertions,failures])
	quit(0 if failures == 0 else 1)

func _collision_layers(soldier: LabSoldier,expected: int) -> bool:
	if soldier._zones.is_empty(): return false
	for area: Area3D in soldier._zones:
		if area.collision_layer != expected: return false
	return true
