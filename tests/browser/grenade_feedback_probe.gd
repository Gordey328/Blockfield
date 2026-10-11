extends Node
## Actual Main and Web mixer, separate user directory and production entry.
const MAIN = preload("res://scenes/main.tscn")
var app: Node3D
var capture: AudioEffectCapture
var bus_index: int = -1
var callback: JavaScriptObject
var busy: bool = false
var near_rms: float = 0.0

func _ready() -> void:
	app = MAIN.instantiate()
	add_child(app)
	app.set_locale("en")
	app.hud.set_menu_visible(false)
	app.player.set_process(false)
	app.player.set_physics_process(false)
	app.player._has_entered = true
	app.player.camera_mode = BlockfieldPlayer.CameraMode.FIRST_PERSON
	app.session.invulnerable = true
	app.session.select_tool(LocalSession.Tool.GRENADE)
	app.player._update_view(0.0)
	AudioServer.add_bus()
	bus_index = AudioServer.get_bus_count()-1
	AudioServer.set_bus_name(bus_index,"GrenadeWebProof")
	capture = AudioEffectCapture.new()
	capture.buffer_length = 4.0
	AudioServer.add_bus_effect(bus_index,capture)
	app.audio.set_output_bus("GrenadeWebProof")
	callback = JavaScriptBridge.create_callback(_fire_js)
	JavaScriptBridge.get_interface("window").grenadeProbeFire = callback
	JavaScriptBridge.eval("var p=document.createElement('div');p.id='grenade-probe';p.style='position:absolute;top:8px;left:8px;background:#111d;color:white;padding:12px;z-index:10000';p.innerHTML='<b>Actual Main: grenade distance</b><div><button id=blast5>Blast at 5</button><button id=blast32>Blast at 32</button><button id=blast80>Blast at 80</button></div><pre id=blast-result>Ready: click 5, then 32, then 80. Real mixer capture.</pre>';document.body.appendChild(p);[5,32,80].forEach(d=>document.getElementById('blast'+d).onclick=()=>window.grenadeProbeFire(d));",true)

func _process(delta: float) -> void:
	if app!=null:app.player._update_view(delta)

func _fire_js(arguments: Array) -> void:
	if not busy:_blast(float(arguments[0]))

func _blast(distance: float) -> void:
	busy = true
	app.audio.stop()
	app.audio.set_output_bus("GrenadeWebProof")
	app.effects.clear()
	await get_tree().create_timer(.15).timeout
	capture.clear_buffer()
	var discarded: int = capture.get_discarded_frames()
	app.audio._random.seed = 328
	app._explosion(app.player.camera.global_position+Vector3.FORWARD*distance)
	var result: Dictionary = {"distance":distance,"fast":app.effects._fast_shake,"slow":app.effects._slow_shake,"layers":app.audio._voices.size(),"particles":app.effects.stats().particles}
	var frames: int = 0
	var energy: float = 0.0
	var finite: bool = true
	var target_frames: int = ceili(AudioServer.get_mix_rate()*3.0)
	var deadline: int = Time.get_ticks_msec()+12000
	while frames<target_frames and Time.get_ticks_msec()<deadline:
		await get_tree().create_timer(.02).timeout
		var count: int = capture.get_frames_available()
		if count==0:continue
		var samples: PackedVector2Array = capture.get_buffer(count)
		for sample: Vector2 in samples:
			if frames>=target_frames:break
			finite = finite and sample.is_finite()
			energy += sample.length_squared()
			frames += 1
	result.frames = frames
	result.target_frames = target_frames
	result.rms = sqrt(energy/maxf(1.0,frames*2.0))
	result.finite = finite
	result.overflow = capture.get_discarded_frames()-discarded
	if distance==5.0:near_rms = result.rms
	result.ratio_to_5 = result.rms/near_rms if near_rms>0.0 else -1.0
	result.pass = frames==target_frames and finite and result.overflow==0 and result.rms>.00001 and (distance==5.0 or result.ratio_to_5<(.4 if distance==32.0 else .1))
	print("GRENADE_WEB_FEEDBACK: "+JSON.stringify(result))
	JavaScriptBridge.eval("document.getElementById('blast-result').textContent="+JSON.stringify(JSON.stringify(result,"  "))+";",true)
	busy = false

func _exit_tree() -> void:
	if is_instance_valid(app):app.audio.stop()
	if bus_index>=0:
		AudioServer.remove_bus_effect(bus_index,0)
		AudioServer.remove_bus(bus_index)
