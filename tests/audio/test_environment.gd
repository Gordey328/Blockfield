extends SceneTree
## Source numeric/behavioral fixtures, independent of DSP and preferences.
const ENV = preload("res://audio/audio_environment.gd")
const AUDIO = preload("res://audio/openspades_audio.gd")
var checks: int=0
var failures: int=0

class Rays extends RefCounted:
	var blocked: bool=true
	var clear_at: int=-1
	var calls: int=0
	var legacy_calls: int=0
	var endpoints: Array[Vector3]=[]
	func cast_source_ray_legacy(origin: Vector3,direction: Vector3,distance: float) -> Dictionary:
		legacy_calls+=1
		return cast_voxel(origin,direction,distance)
	func cast_voxel(origin: Vector3,direction: Vector3,distance: float) -> Dictionary:
		calls+=1
		endpoints.append(origin+direction*distance)
		return {"hit":blocked and calls!=clear_at,"cell":Vector3i(3,3,3)}

func _initialize() -> void:call_deferred("_run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures+=1;push_error("AUDIO_ENV: "+label)
func near(a: float,b: float,label: String) -> void:check(absf(a-b)<.000001,label)

func _run() -> void:
	var env=ENV.new()
	check(env.distances.size()==128 and env.feedback_history.size()==128,"native128 sample ring")
	check(env.distances[0]==20000 and env.feedback_history[0]==0,"startup histories")
	var distances:=PackedFloat64Array()
	distances.resize(128);distances.fill(80)
	var feedback:=PackedFloat64Array()
	feedback.resize(128);feedback.fill(0)
	var room: Dictionary=ENV.room_parameters(distances,feedback)
	near(room.gain,.16,"map fallback overall.16")
	near(room.early_gain,.05,"fallback reflections.05")
	near(room.early_delay,.3,"early maximum.3")
	near(room.late_delay,.1,"late relativemaximum.1")
	near(room.late_onset,.4,"late begins afterearly+.1")
	near(room.decay_time,.1,"fallback decay minimum.1")
	for i: int in range(32):distances[i]=7.5;feedback[i]=1
	room=ENV.room_parameters(distances,feedback)
	check(room.hits==32 and room.room_size==100,"strict32 is stillfallback")
	distances[32]=7.5;feedback[32]=1
	room=ENV.room_parameters(distances,feedback)
	near(room.reflections,33.0/128.0,"33samples use measuredroom")
	near(room.room_size,7.5,"measuredmean")
	distances.fill(7.5);feedback.fill(1)
	room=ENV.room_parameters(distances,feedback)
	near(room.volume,4*PI*56.25/3,"nativevolume")
	near(room.area,4*PI*7.5,"nativearea")
	near(room.decay_time,1.00625,"nativeSabineT60")
	near(room.gain,.8,"fullroomoverallgain")
	near(room.early_gain,.25,"fullroomreflections")
	near(room.late_gain,.34,"fullfeedbacklategain")
	near(room.early_delay,7.5/324,"earlydelay roomsize/speed324")
	near(room.late_onset,15.0/324,"late delayrelativeearly")
	near(room.gain_hf,.5929,"ROOM staticHFgain")
	near(room.decay_hf_ratio,.83,"ROOM staticHFratio")
	distances.fill(40)
	check(ENV.room_parameters(distances,feedback).hits==0,"distance40 strictmiss")
	near(ENV.room_parameters(distances,feedback,false).gain,0,"no map hasnowetgain")
	for i: int in range(128):env.commit_room_sample(4,true)
	check(env.history_position==0,"128 commitswrap")
	env.commit_room_sample(80)
	check(env.distances[0]==80 and env.feedback_history[0]==1,"nativeforwardmissretainsoldfeedback")
	var rays:=Rays.new()
	env.set_query(rays);env.begin_turn(0,128,0)
	var answer: Dictionary=env.trace_obstruction(Vector3.ZERO,Vector3(4,3,2))
	check(answer.blocked and answer.rays==27,"all27 blocked required")
	check(rays.legacy_calls==27,"nativeCastRay selected overmetric")
	var unique: Dictionary={}
	for endpoint: Vector3 in rays.endpoints:unique[endpoint.snapped(Vector3(.01,.01,.01))]=true
	check(unique.size()==27,"all27 unique .2 endpoints")
	check(rays.endpoints.any(func(point: Vector3):return point.distance_to(Vector3(3.8,2.8,1.8))<.000001) and rays.endpoints.any(func(point: Vector3):return point.distance_to(Vector3(4.2,3.2,2.2))<.000001),"native.2m gridcorners")
	rays.calls=0;rays.clear_at=17
	answer=env.trace_obstruction(Vector3.ZERO,Vector3(4,3,2))
	check(not answer.blocked and answer.rays==17,"single clear provesfalse earlyout")
	rays.calls=0;rays.clear_at=-1
	env.reset();env.begin_turn(0,128,0)
	answer=env.obstruction(Vector3.ZERO,Vector3.ONE)
	check(answer.known and answer.blocked and answer.rays==27,"fresh fullquery")
	check(env.obstruction(Vector3.ZERO,Vector3.ONE).rays==0,"exactorigin sharesall layers")
	env.begin_turn(.11,2,0)
	answer=env.obstruction(Vector3.ZERO,Vector3.ONE)
	check(answer.known and answer.blocked and answer.rays==2,"budget holds knownstale within.25sec")
	env.begin_turn(.3,2,0)
	answer=env.obstruction(Vector3.ZERO,Vector3.ONE)
	check(not answer.known and not answer.blocked,"expired partialcannotinvent blocked")
	check(env.last_turn_rays==2 and env.budget_exhausted,"hard raybudget")
	env.begin_turn(.31,27,0)
	check(env.obstruction(Vector3.ZERO,Vector3.ONE).blocked,"refresh recoversafterbudget")
	var debug: Dictionary=env.debug_state();debug.parameters.gain=100
	check(env.parameters.gain!=100,"debug copiescannotmutate state")
	rays.blocked=false;rays.calls=0
	env.reset();env.begin_turn(1,1000,0)
	for i: int in range(129):env.obstruction(Vector3.ZERO,Vector3(i+1,0,0))
	check(env.debug_state().cache_entries==128,"cache bounded128origins")
	env.reset();env.begin_turn(2,8,0);rays.blocked=true;rays.calls=0
	env.sample_room(Vector3.ZERO)
	check(env.history_position==4 and env.last_turn_rays==8,"four forward/opposite pairs")
	env.begin_turn(2.001,8,0);env.sample_room(Vector3.ZERO)
	check(env.history_position==4 and env.last_turn_rays==0,"wallclock avoidsfixedfps over-sampling")
	env.begin_turn(20,8,0);env.sample_room(Vector3.ZERO)
	check(env.history_position==8,"longstall no unboundedcatchup")
	env.begin_turn(21,128,1)
	var waited: int=Time.get_ticks_usec()
	while Time.get_ticks_usec()-waited<10:pass
	answer=env.trace_obstruction(Vector3.ZERO,Vector3.ONE,true)
	check(not answer.known and answer.rays==0 and env.budget_exhausted,"wallclockbudget preventsnewquery")
	var data:=VoxelData.new();data.clear(Vector3i(12,12,12))
	data.seed_box(Vector3i(4,0,0),Vector3i(5,12,12),0x01ffffff)
	env.set_query(data);env.begin_turn(22,128,0)
	check(env.obstruction(Vector3(1,3,3),Vector3(8,3,3)).blocked,"actualnative mapwall all27blocked")
	data.set_block(Vector3i(4,3,3),0)
	env.begin_turn(22.01,128,0)
	answer=env.obstruction(Vector3(1,3,3),Vector3(8,3,3))
	check(answer.known and not answer.blocked and answer.rays>0,"blocktransaction invalidatesfresh cachedwall")
	near(AUDIO.effective_gain(8,.5,1,true),1,"ALMAX_GAIN local8 caps1")
	near(AUDIO.effective_gain(20,10,1,false),1,"ALMAX_GAIN clampAFTER inverse")
	near(AUDIO.effective_gain(20,80,1,false),.25,"raw20 extendsrange")
	near(AUDIO.effective_gain(8,80,1,false,false,.5),.05,"s_gain precedesdistance/cap")
	near(AUDIO.effective_gain(8,.5,1,true,false,.05),.4,"localnative s_gain")
	near(AUDIO.effective_gain(1,20,4,false,true,0),.2,"nativeworldstereo s_gain omission preserved")
	near(AUDIO.effective_gain(1,20,4,false,false,0),0,"worldmono s_gain0")
	near(AUDIO.effective_wet_gain(1,344.3,1,false,false,1,1),.001,"explicithistoricalWetGainAuto golden")
	var baseline: int=AudioServer.get_bus_count()
	var host:=Node3D.new();root.add_child(host)
	var camera:=Camera3D.new();host.add_child(camera)
	var audio=AUDIO.new();host.add_child(audio);audio.setup(null,camera)
	var mono: Node=audio.play_local("Weapons/DryFire",8,Vector3(.4,-.3,.5))
	near(float(mono.get_meta("gain")),8,"metadata unchanged")
	near(db_to_linear(mono.volume_db),1,"effective mixer voice cap")
	check(mono.get_meta("copies").size()==2,"eligiblelocal3D createsearly+latecopies")
	check(audio.debug_environment().owned_buses.size()==9,"bounded9DSPbuses")
	var ui: Node=audio.play_local("Feedback/Chat")
	check(ui.get_meta("copies").is_empty(),"UI2D alwaysdryonly")
	# Ricochet pitch and moving 3D sources must still reach both room branches,
	# including an externally moved branch whose dry source has not changed.
	mono.pitch_scale=0.95
	mono.global_transform=Transform3D(Basis(Vector3.UP,0.2),Vector3(1,2,3))
	audio._update_gain(mono)
	for copy: Node in mono.get_meta("copies"):
		near(copy.pitch_scale,0.95,"wet branch follows changed ricochet pitch")
		check(copy.global_transform==mono.global_transform,"wet branch follows exact changed source transform")
		copy.global_position+=Vector3.RIGHT
	mono.pitch_scale=1.05
	audio._update_gain(mono)
	for copy: Node in mono.get_meta("copies"):
		check(is_equal_approx(copy.pitch_scale,1.05) and copy.global_transform==mono.global_transform,"next update restores changed branch and follows new pitch")
	var other=AUDIO.new();host.add_child(other);other.setup(null,camera);other.get_output_bus()
	check(other.get_output_bus()!=audio.get_output_bus(),"separateinstancesuniqueownedbuses")
	other.stop();check(AudioServer.get_bus_count()==baseline+9,"stopremovesonlyownbuses")
	audio.efx_enabled=false;audio._process(0)
	check(mono.get_meta("copies").is_empty(),"EFXoff removeswetcopies")
	check(str(mono.bus).ends_with("dry_clear"),"EFXoff clearsobstruction")
	for i: int in range(129):audio.play_local("Weapons/DryFire")
	check(audio._voices.size()==128,"logicalpolyphony bounded128")
	await create_timer(.2).timeout
	audio.stop();check(AudioServer.get_bus_count()==baseline,"stopremovesDSP andtails")
	check(audio.debug_environment().history_position==0,"stop resetsroomhistory")
	audio.get_output_bus();check(AudioServer.get_bus_count()==baseline+9,"lazyrecreatesownedDSP")
	audio.stop();audio.stop();check(AudioServer.get_bus_count()==baseline,"stopidempotent")
	var acoustic_world:=VoxelWorld.new();acoustic_world.data.clear(Vector3i(12,12,12),7)
	var old_data: VoxelData=acoustic_world.data
	var old_reference: WeakRef=weakref(old_data)
	audio.setup(acoustic_world,camera);audio.set_process(false)
	check(audio._environment.query==old_data,"setup adoptscurrent puredataquery")
	acoustic_world.data=VoxelData.new();acoustic_world.data.clear(Vector3i(12,12,12),8)
	old_data=null
	audio._environment_frame=-1;audio._begin_environment_turn()
	check(audio._environment.query==acoustic_world.data and old_reference.get_ref()==null,"Data replacement releasesold strongquery reference")
	audio._environment.commit_room_sample(6,true)
	acoustic_world.data.clear(Vector3i(12,12,12),9)
	audio._environment_frame=-1;audio._begin_environment_turn()
	check(audio._environment.history_position<=4 and audio._environment.feedback_history[0]==0,"new epoch resetsold acoustic history")
	audio.stop();check(audio._environment.query==null,"stop releasesowned puredatareference")
	acoustic_world.free();audio.world=null
	host.queue_free();await process_frame;await process_frame;await create_timer(.2).timeout
	print("AUDIO ENVIRONMENT: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
