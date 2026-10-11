extends SceneTree
## Actual PCM after the production DSP. No Main, renderer fixtures or settings.
const AUDIO = preload("res://audio/openspades_audio.gd")
const ENV = preload("res://audio/audio_environment.gd")
const WORLD = preload("res://world/voxel_world.gd")
const BUS: StringName=&"OpenSpadesEnvironmentPCM"
var checks: int=0
var failures: int=0
var host: Node3D
var camera: Camera3D
var world: VoxelWorld
var audio: OpenSpadesAudio
var capture: AudioEffectCapture
var bus_index: int=-1
var old_mute: bool=false
var output: String
var results: Array[Dictionary]=[]

func _initialize() -> void:call_deferred("_run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures+=1;push_error("ENVIRONMENT_PCM: "+label)

func _run() -> void:
	output=ProjectSettings.globalize_path("res://../.cache/previews/audio-environment").path_join(AudioServer.get_driver_name().to_lower())
	DirAccess.make_dir_recursive_absolute(output)
	old_mute=AudioServer.is_bus_mute(0);AudioServer.set_bus_mute(0,true)
	AudioServer.add_bus();bus_index=AudioServer.get_bus_count()-1
	AudioServer.set_bus_name(bus_index,BUS);AudioServer.set_bus_send(bus_index,&"Master")
	capture=AudioEffectCapture.new();capture.buffer_length=5
	AudioServer.add_bus_effect(bus_index,capture);AudioServer.set_bus_mute(bus_index,true)
	host=Node3D.new();root.add_child(host)
	camera=Camera3D.new();host.add_child(camera);camera.position=Vector3(8,8,8);camera.current=true
	root.audio_listener_enable_3d=true
	# Query-only world: no tree entry, meshes, GPU work or map presentation.
	world=WORLD.new();world.data.clear(Vector3i(32,32,32))
	audio=AUDIO.new();host.add_child(audio);audio.setup(world,camera);audio.set_process(false);audio.set_output_bus(BUS)
	var low: AudioStreamWAV=wave(400,.25,.15)
	var high: AudioStreamWAV=wave(10000,.25,.15)
	var origin:=Vector3(16,8,8)
	audio.positional=false
	var clear_low: Dictionary=await record("clear_400hz",func():audio._start_voice(low,"fixture",1,origin,false,16),.5)
	var clear_high: Dictionary=await record("clear_10000hz",func():audio._start_voice(high,"fixture",1,origin,false,16),.5)
	world.data.seed_box(Vector3i(12,0,0),Vector3i(13,32,32),0x01ffffff)
	var blocked_low: Dictionary=await record("blocked_400hz",func():audio._start_voice(low,"fixture",1,origin,false,16),.5)
	var blocked_high: Dictionary=await record("blocked_10000hz",func():audio._start_voice(high,"fixture",1,origin,false,16),.5)
	var low_ratio: float=sqrt(float(blocked_low.early_energy)/float(clear_low.early_energy))
	var high_ratio: float=sqrt(float(blocked_high.early_energy)/float(clear_high.early_energy))
	check(low_ratio>.9 and low_ratio<1.05,"obstruction retains lowfrequency unity")
	check(high_ratio>.06 and high_ratio<.25,"obstruction attenuates actual10kHz PCM")
	audio.efx_enabled=false
	var disabled: Dictionary=await record("efx_off_10000hz",func():audio._start_voice(high,"fixture",1,origin,false,16),.5)
	check(absf(sqrt(float(disabled.early_energy)/float(clear_high.early_energy))-1)<.04,"EFXoff reallybypasses obstruction")
	audio.efx_enabled=true
	var ui: Dictionary=await record("ui_dry_inside_room",func():audio._start_voice(high,"fixture_ui",1,Vector3.ZERO,true,1),.6,7.5)
	check(absf(sqrt(float(ui.early_energy)/float(clear_high.early_energy))-1)<.04,"UI dry unaffectedbywall/room")
	check(float(ui.tail_energy)<.00000001,"UI has no early/reverb tail")
	world.data.clear(Vector3i(32,32,32))
	audio.positional=true
	var input: AudioStreamWAV=impulse()
	var early: Dictionary=await record("early_only_20m",func():audio._start_voice(input,"fixture_impulse",1,Vector3(.4,-.3,.5),true,1),.7,20,false)
	check(absf(float(early.echo_peak_delay)-20.0/324.0)<.03,"actualearlydelay matches20/324 withinmixblock")
	check(float(early.tail_energy)<.00000001,"earlyonly has no longfeedbacktail")
	var room: Dictionary=await record("reverb_7_5m",func():audio._start_voice(input,"fixture_impulse",1,Vector3(.4,-.3,.5),true,1),3,7.5,true)
	var tiny: Dictionary=await record("reverb_tiny_0_5m",func():audio._start_voice(input,"fixture_impulse",1,Vector3(.4,-.3,.5),true,1),2,.5,true)
	check(float(room.tail_energy)>.00000001 and float(tiny.tail_energy)>.00000001,"actualsharedreverb leaves finitepost-input tail")
	check(float(room.measured_t60)>float(tiny.measured_t60)*1.1,"roomdecayparameter meaningfullychangesPCMtail")
	check(float(tiny.measured_t60)>.15,"shortnative.1s measuredbackendadaptation exposed")
	audio.efx_enabled=false
	var dry: Dictionary=await record("dry_impulse",func():audio._start_voice(input,"fixture_impulse",1,Vector3(.4,-.3,.5),true,1),.6,7.5,true)
	check(float(dry.tail_energy)<.00000001,"EFXoff removes actual roomtail")
	var cap_one: Dictionary=await record("source_gain_1",func():audio._start_voice(low,"fixture",1,Vector3.ZERO,true,1),.5)
	var cap_eight: Dictionary=await record("source_gain_8",func():audio._start_voice(low,"fixture",8,Vector3.ZERO,true,1),.5)
	check(absf(sqrt(float(cap_eight.early_energy)/float(cap_one.early_energy))-1)<.02,"rawsource8 PCM equalssource1 afternativecap")
	audio.source_gain=.05
	var adjusted: Dictionary=await record("source_gain_setting_005",func():audio._start_voice(low,"fixture",8,Vector3.ZERO,true,1),.5)
	check(absf(sqrt(float(adjusted.early_energy)/float(cap_one.early_energy))-.4)<.015,"native s_gain appliesbeforepervoicecap")
	audio.source_gain=1
	var loud: AudioStreamWAV=wave(800,.3,.8)
	var polyphony: Callable=func():
		for i: int in range(12):audio._start_voice(loud,"fixture",8,Vector3.ZERO,true,1)
	var limited: Dictionary=await record("limited_polyphony",polyphony,.6)
	var unlimited: Dictionary=await record("unlimited_negative_control",polyphony,.6,0,false,false)
	check(float(limited.peak)<=.968,"fullDSPpolyphonicoutput staysbelow-.3dBceiling")
	check(float(unlimited.peak)>2,"disabledlimiter negativecontrol proves actualoverload")
	var master_volume: float=AudioServer.get_bus_volume_db(0)
	AudioServer.set_bus_volume_db(0,linear_to_db(4))
	var master_limited: Dictionary=await record("master_gain4_headroom",polyphony,.6)
	AudioServer.set_bus_volume_db(0,master_volume)
	check(float(master_limited.peak)*4<=.968,"limiter reservesheadroom forpostDSPMastergain4")
	var report: Dictionary={"driver":AudioServer.get_driver_name(),"engine":Engine.get_version_info().string,"mix_rate":AudioServer.get_mix_rate(),"checks":checks,"failures":failures,"low_frequency_ratio":low_ratio,"high_frequency_ratio":high_ratio,"short_tail_source_seconds":.1,"short_tail_measured_seconds":tiny.measured_t60,"room_source_seconds":1.00625,"room_measured_seconds":room.measured_t60,"results":results,"browser_listening_verified":false}
	var file:=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	check(file!=null,"report saves")
	if file!=null:report.checks=checks;report.failures=failures;file.store_string(JSON.stringify(report,"\t"));file.close()
	audio.stop();world.free();world=null;host.queue_free()
	await process_frame;await process_frame;await create_timer(.2).timeout
	AudioServer.remove_bus_effect(bus_index,0);AudioServer.remove_bus(bus_index);capture=null
	AudioServer.set_bus_mute(0,old_mute)
	print("AUDIO ENVIRONMENT PCM: %d checks, %d failures; %s"%[checks,failures,output])
	quit(1 if failures else 0)

func record(name: String,play: Callable,seconds: float,room_size: float=0,feedback: bool=false,limiter: bool=true) -> Dictionary:
	audio.stop();await create_timer(.12).timeout
	audio._environment.set_query(world.data)
	var distances:=PackedFloat64Array();distances.resize(128);distances.fill(room_size if room_size>0 else 80.0)
	var opposite:=PackedFloat64Array();opposite.resize(128);opposite.fill(1.0 if feedback else 0.0)
	audio._environment.parameters=ENV.room_parameters(distances,opposite,true)
	# Install source-approved room history; freeze stochastic updates so the
	# measured DSP difference has one known source parameter set.
	audio._environment._last_room_time=float(Time.get_ticks_usec())/1000000.0+1000.0
	var out: int=AudioServer.get_bus_index(audio.get_output_bus())
	AudioServer.set_bus_effect_enabled(out,0,limiter)
	capture.clear_buffer();var discarded: int=capture.get_discarded_frames()
	# This isolated DSP fixture freezes service updates. Complete the actual
	# 27-ray obstruction predicate before playback instead of retaining an
	# unknown/clear route when a slow Web query exceeds the production time cap.
	# Production still uses128 rays/1.5ms; its budget behavior is tested separately.
	audio._begin_environment_turn()
	audio._environment.begin_turn(float(Time.get_ticks_usec())/1000000.0,ENV.MAX_RAYS_PER_TURN,0)
	play.call()
	var query_rays: int=audio._environment.last_turn_rays
	var query_exhausted: bool=audio._environment.budget_exhausted
	var blocked_voices: Array[bool]=[]
	for voice: Node in audio._voices:blocked_voices.append(bool(voice.get_meta("blocked",false)))
	var frames:=PackedVector2Array()
	var target_frames: int=ceili(AudioServer.get_mix_rate()*seconds)
	# Use the same complete audio-duration window for every compared signal.
	# A bounded3x guard for long captures allows the observed slow Web mixer
	# cadence without changing PCM or obstruction acceptance thresholds.
	var wall_limit: float=seconds+maxf(2.0,2.0*seconds)
	var capture_started: int=Time.get_ticks_usec()
	var end: int=capture_started+ceili(wall_limit*1000000.0)
	while Time.get_ticks_usec()<end and frames.size()<target_frames:
		await create_timer(.01).timeout
		var count: int=capture.get_frames_available()
		if count>0:frames.append_array(capture.get_buffer(count))
	var remaining: int=capture.get_frames_available()
	if remaining>0:frames.append_array(capture.get_buffer(remaining))
	var capture_wall_seconds: float=float(Time.get_ticks_usec()-capture_started)/1000000.0
	var captured_frames: int=frames.size()
	if frames.size()>target_frames:frames.resize(target_frames)
	var metrics: Dictionary=measure(frames)
	metrics.name=name
	metrics.window_seconds=seconds
	metrics.capture_clock="audio_frames"
	metrics.target_frames=target_frames
	metrics.captured_frames=captured_frames
	metrics.capture_wall_seconds=capture_wall_seconds
	metrics.capture_wall_limit_seconds=wall_limit
	metrics.capture_timed_out=captured_frames<target_frames or capture_wall_seconds>wall_limit
	metrics.captured_audio_seconds=float(frames.size())/AudioServer.get_mix_rate()
	metrics.fixture_query_ray_limit=ENV.MAX_RAYS_PER_TURN
	metrics.fixture_query_time_cap_usec=0
	metrics.query_rays=query_rays
	metrics.query_budget_exhausted=query_exhausted
	metrics.blocked_voices=blocked_voices
	metrics.discarded_frames=capture.get_discarded_frames()-discarded
	metrics.first_frame=first_signal(frames)
	metrics.early_energy=energy_window(frames,.02,.14,int(metrics.first_frame))
	metrics.tail_energy=energy_window(frames,.45,seconds,int(metrics.first_frame))
	metrics.echo_peak_delay=echo_delay(frames,int(metrics.first_frame))
	metrics.measured_t60=schroeder_t60(frames,int(metrics.first_frame)+int(.12*AudioServer.get_mix_rate()))
	metrics.source_parameters=audio._environment.parameters.duplicate(true)
	check(frames.size()>=target_frames and not bool(metrics.capture_timed_out),name+" requested realcapturedframes before wall deadline")
	check(metrics.finite and metrics.nonzero_frames>0,name+" finite nonzerosignal")
	check(capture.get_discarded_frames()==discarded,name+" boundedcapture nooverflow")
	check(write_wav(output.path_join(name+".wav"),frames,.95/maxf(1,float(metrics.peak))),name+" WAVsaved")
	results.append(metrics)
	print("ENV PCM %s: rms=%.7f peak=%.5f tail=%.8f T60=%.5f echo=%.5f"%[name,metrics.rms,metrics.peak,metrics.tail_energy,metrics.measured_t60,metrics.echo_peak_delay])
	return metrics

func first_signal(frames: PackedVector2Array) -> int:
	for i: int in range(frames.size()):
		if maxf(absf(frames[i].x),absf(frames[i].y))>.000001:return i
	return 0
func energy_window(frames: PackedVector2Array,from: float,to: float,start: int) -> float:
	var energy: float=0
	for i: int in range(maxi(0,start+int(from*AudioServer.get_mix_rate())),mini(frames.size(),start+int(to*AudioServer.get_mix_rate()))):energy+=frames[i].length_squared()
	return energy
func echo_delay(frames: PackedVector2Array,start: int) -> float:
	var peak: float=0;var index: int=start
	for i: int in range(start+int(.04*AudioServer.get_mix_rate()),mini(frames.size(),start+int(.11*AudioServer.get_mix_rate()))):
		if frames[i].length_squared()>peak:peak=frames[i].length_squared();index=i
	return float(index-start)/AudioServer.get_mix_rate()
func schroeder_t60(frames: PackedVector2Array,start: int) -> float:
	var accumulated: float=0
	var energy:=PackedFloat64Array();energy.resize(frames.size())
	for i: int in range(frames.size()-1,start-1,-1):accumulated+=frames[i].length_squared();energy[i]=accumulated
	if accumulated<.000000001:return 0
	var minus5: int=-1;var minus25: int=-1
	for i: int in range(start,frames.size()):
		var relative: float=energy[i]/accumulated
		if minus5<0 and relative<=pow(10,-.5):minus5=i
		if relative<=pow(10,-2.5):minus25=i;break
	return 3.0*float(minus25-minus5)/AudioServer.get_mix_rate() if minus5>=0 and minus25>minus5 else 0
func wave(frequency: float,seconds: float,amplitude: float) -> AudioStreamWAV:
	var stream:=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=int(AudioServer.get_mix_rate());stream.stereo=false
	var samples: int=int(seconds*stream.mix_rate);var bytes:=PackedByteArray();bytes.resize(samples*2)
	for i: int in range(samples):bytes.encode_s16(i*2,int(sin(TAU*frequency*i/stream.mix_rate)*amplitude*32767))
	stream.data=bytes;return stream
func impulse() -> AudioStreamWAV:
	var stream:=wave(400,.03,0)
	var bytes: PackedByteArray=stream.data
	bytes.encode_s16(20,16384)
	stream.data=bytes;return stream

func measure(frames: PackedVector2Array) -> Dictionary:
	var energy: float=0
	var peak: float=0
	var nonzero: int=0
	var finite: bool=true
	for sample: Vector2 in frames:
		if not is_finite(sample.x) or not is_finite(sample.y):finite=false;continue
		energy+=sample.length_squared()
		peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)))
		if maxf(absf(sample.x),absf(sample.y))>.0000001:nonzero+=1
	return {"frames":frames.size(),"energy":energy,"peak":peak,"rms":sqrt(energy/(2*maxi(1,frames.size()))),"nonzero_frames":nonzero,"finite":finite}

func write_wav(path: String,frames: PackedVector2Array,scale: float) -> bool:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null:return false
	var rate: int=int(AudioServer.get_mix_rate())
	file.store_buffer("RIFF".to_ascii_buffer());file.store_32(36+frames.size()*4)
	file.store_buffer("WAVEfmt ".to_ascii_buffer());file.store_32(16);file.store_16(1);file.store_16(2)
	file.store_32(rate);file.store_32(rate*4);file.store_16(4);file.store_16(16)
	file.store_buffer("data".to_ascii_buffer());file.store_32(frames.size()*4)
	for sample: Vector2 in frames:
		file.store_16(int(round(clampf(sample.x*scale,-1,1)*32767))&0xffff)
		file.store_16(int(round(clampf(sample.y*scale,-1,1)*32767))&0xffff)
	file.close();return true
