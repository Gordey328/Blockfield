extends SceneTree
## Independently specified native sound-layer fixtures and real voice routing.
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("_run")
func check(condition: bool,label: String) -> void:
	checks+=1
	if not condition:failures+=1;push_error("FAIL: "+label)
func layer(actual: Dictionary,path: String,gain: float,reference: float) -> void:
	check(actual.path==path,"source sound path "+path)
	check(is_equal_approx(float(actual.gain),gain),"source gain "+path)
	check(is_equal_approx(float(actual.reference),reference),"source reference distance "+path)
func _run() -> void:
	var rifle:=OpenSpadesAudio.weapon_layers(0,true,.25,.2)
	check(rifle.size()==4,"FP rifle has four source layers")
	layer(rifle[0],"Weapons/Rifle/FireLocal",8,1)
	layer(rifle[1],"Weapons/Rifle/V2AmbienceSmall",2,1)
	layer(rifle[2],"Weapons/Rifle/FireFar",1,4)
	layer(rifle[3],"Weapons/Rifle/FireStereo",1,1)
	var third:=OpenSpadesAudio.weapon_layers(0,false,.5,.7,3)
	layer(third[0],"Weapons/Rifle/Fire3",20,1)
	layer(third[1],"Weapons/Rifle/V2AmbienceLarge",10,1)
	layer(third[2],"Weapons/Rifle/FireFar",1,26)
	layer(third[3],"Weapons/Rifle/FireStereo",1,4)
	var smg:=OpenSpadesAudio.weapon_layers(1,true,.5,.5,4,2)
	check(smg.size()==2,"FP SMG has two layers and no FireStereo fallback")
	layer(smg[0],"Weapons/SMG/V2Local4",8,1)
	layer(smg[1],"Weapons/SMG/V2AmbienceLarge2",4,1)
	smg=OpenSpadesAudio.weapon_layers(1,false,.25,.2,1,3)
	layer(smg[0],"Weapons/SMG/V2Third1",9,1)
	layer(smg[1],"Weapons/SMG/V2AmbienceSmall3",2,10)
	layer(smg[2],"Weapons/SMG/FireFar",.4,10)
	layer(smg[3],"Weapons/SMG/FireStereo",.4,1)
	var shotgun:=OpenSpadesAudio.weapon_layers(2,false,0,0)
	layer(shotgun[0],"Weapons/Shotgun/Fire",8,1)
	layer(shotgun[2],"Weapons/Shotgun/FireFar",2,4)
	layer(OpenSpadesAudio.weapon_layers(2,true,0,0)[2],"Weapons/Shotgun/FireFar",2,1)
	var land:=OpenSpadesAudio.explosion_layers(false,2)
	check(land.size()==5,"land explosion has five source layers")
	layer(land[0],"Weapons/Grenade/Explode2",30,5)
	layer(land[1],"Weapons/Grenade/ExplodeStereo2",30,1)
	layer(land[2],"Weapons/Grenade/ExplodeFar",6,40)
	layer(land[3],"Weapons/Grenade/ExplodeFarStereo",6,10)
	layer(land[4],"Weapons/Grenade/Debris",5,3)
	var water:=OpenSpadesAudio.explosion_layers(true)
	check(water.size()==3,"underwater explosion has three layers")
	layer(water[0],"Weapons/Grenade/WaterExplode",10,1)
	layer(water[1],"Weapons/Grenade/WaterExplodeFar",6,10)
	layer(water[2],"Weapons/Grenade/WaterExplodeStereo",2,10)
	check(is_equal_approx(OpenSpadesAudio.inverse_gain(6,80,40),3),"world stereo/mono use inverse reference distance")
	var solid_impact:=OpenSpadesAudio.impact_layers(false,4)
	check(solid_impact.size()==2,"solid bullet hit plays block and ricochet source layers")
	layer(solid_impact[0],"Weapons/Impacts/Block",2,1)
	layer(solid_impact[1],"Weapons/Impacts/Ricochet4",2,1)
	var water_impact:=OpenSpadesAudio.impact_layers(true,3)
	check(water_impact.size()==1,"water hit plays a single impact layer")
	layer(water_impact[0],"Weapons/Impacts/Water3",2,1)
	check(is_equal_approx(OpenSpadesAudio.inverse_gain(8,.5,1),8),"near distance clamps at reference, not source volume")
	var distances: Array[float]=[]
	var feedback: Array[bool]=[]
	for index in range(24):distances.append(7.5);feedback.append(true)
	var ambience:=OpenSpadesAudio.ambience_from_samples(distances,feedback)
	check(is_equal_approx(ambience.size,.5) and is_equal_approx(ambience.room,.85),"enclosed 7.5m room golden ambience .85")
	for index in range(24):distances[index]=80;feedback[index]=false
	ambience=OpenSpadesAudio.ambience_from_samples(distances,feedback)
	check(ambience.size==1.0 and ambience.room==0.0,"open air has no ambience layer")
	for index in range(6):distances[index]=7.5;feedback[index]=true
	check(OpenSpadesAudio.ambience_from_samples(distances,feedback).room==0,"six rays below strict seven-hit room threshold")
	var host:=Node3D.new()
	root.add_child(host)
	var camera:=Camera3D.new()
	host.add_child(camera)
	var audio:=OpenSpadesAudio.new()
	host.add_child(audio)
	audio.setup(null,camera)
	var mono:=audio.play_local("Weapons/DryFire",1,Vector3(.4,-.3,.5))
	check(mono is AudioStreamPlayer3D,"local mono offset retains spatial pan")
	if mono!=null:
		check(mono.position.is_equal_approx(Vector3(.4,-.3,-.5)),"OpenAL listener-relative forward maps to -GodotZ")
		check(mono.attenuation_model==AudioStreamPlayer3D.ATTENUATION_DISABLED,"local mono has no distance falloff")
	var stereo:=audio.play_spatial("Weapons/Rifle/FireStereo",Vector3(0,0,-20),1,4)
	check(stereo is AudioStreamPlayer,"stereo world layer preserves two channels and avoids panning")
	if stereo!=null:check(is_equal_approx(db_to_linear(stereo.volume_db),.2),"stereo world layer distance gain")
	var world_mono:=audio.play_spatial("Weapons/DryFire",Vector3(0,0,-20),1,4)
	check(world_mono is AudioStreamPlayer3D,"world mono remains spatial")
	if world_mono!=null:
		check(is_equal_approx(db_to_linear(world_mono.volume_db),.2),"mono/stereo world volume agrees")
		check(world_mono.max_distance==0.0 and world_mono.unit_size==4.0,"no extra 150m linear fade")
	for weapon in range(3):
		for first_person in [false,true]:
			for entry in OpenSpadesAudio.weapon_layers(weapon,first_person,.5,.5,4,4):
				check(OpenSpadesExtensions.sound("res://assets/openspades/sounds/"+str(entry.path)+".ogg")!=null,"original layer resource exists "+entry.path)
	# Let the audio server consume queued play commands before stopping them.
	await create_timer(.1).timeout
	audio.stop()
	check(audio._voices.is_empty(),"voice teardown clears active streams")
	host.queue_free()
	await process_frame
	await process_frame
	await create_timer(.1).timeout
	print("AUDIO TESTS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
