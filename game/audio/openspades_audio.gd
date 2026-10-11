class_name OpenSpadesAudio
extends Node
## Source layers/gains from v0.1.3 Skin/{Rifle,SMG,Shotgun} and Client_Update.
## Godot spatial panning replaces OpenAL; inverse-distance gain is shared by
## mono/stereo voices so disabling panning does not change loudness.

const MAX_VOICES := 128
const MAX_AMBIENCE_CACHE: int = 128
const ENVIRONMENT := preload("res://audio/audio_environment.gd")
const WEAPONS := ["Rifle","SMG","Shotgun"]
const LOCAL_ORIGIN := Vector3(.4,-.3,.5) # OpenAL listener-relative axes.
const AMBIENCE_DIRECTIONS := [
	Vector3(-.4806003058,-.4290962262,.7647874049),Vector3(-.3223129456,.6282069816,.7081457148),
	Vector3(.0487405825,-.6670915239,.7433796166),Vector3(.4507022412,.2196054265,.8652403981),
	Vector3(-.4272151163,-.5871645910,-.6875499891),Vector3(-.5570464881,.3832470400,-.7367638132),
	Vector3(.4379032819,-.5217172827,-.7321555795),Vector3(.5505793235,.5884516131,-.5921039669),
	Vector3(.6817141792,-.6289005125,-.3738314103),Vector3(.8824243171,.4680895178,-.0471118665),
	Vector3(.8175844571,-.5123280061,.2628225062),Vector3(.7326555077,.1693864952,.6591844373),
	Vector3(-.8833847856,-.4685933375,-.0071836406),Vector3(-.6478926244,.5325399055,-.5446433662),
	Vector3(-.7011236289,-.4179353736,.5777159168),Vector3(-.8834742898,.3226030060,.3397064611),
	Vector3(-.7012722687,.7126868113,-.0171672438),Vector3(-.4048459451,.8049148135,.4338339586),
	Vector3(.1051134448,.7400485819,-.6642885368),Vector3(.4228172537,.7759558486,.4681005138),
	Vector3(-.6416423027,-.7293326299,-.2374217142),Vector3(-.2695821559,-.9578851718,.0989012585),
	Vector3(.0927496687,-.9126579244,-.3980615680),Vector3(.4935943869,-.7218911732,.4850131084)
]

var world: VoxelWorld
var camera: Camera3D
var positional := true
var environmental := true
var efx_enabled: bool = true
var source_gain: float = 1.0
var _voices: Array[Node] = []
var _stereo: Dictionary = {}
var _random := RandomNumberGenerator.new()
var _environment := ENVIRONMENT.new()
var _owned_buses: Array[StringName] = []
var _buses: Dictionary = {}
var _output_send: StringName = &"Master"
var _early_delay: AudioEffectDelay
var _late_delay: AudioEffectDelay
var _reverb: AudioEffectReverb
var _limiter: AudioEffectHardLimiter
var _last_parameters: Dictionary = {}
var _environment_frame: int = -1
var _route_cursor: int = 0
## Skin ambience is deterministic at an exact eye and terrain version. Cache
## only versioned VoxelData; never approximate listener positions or source rays.
var ambience_cache_enabled: bool = true:
	set(value):
		if ambience_cache_enabled == value:return
		ambience_cache_enabled = value
		clear_ambience_cache()
var _ambience_cache: Dictionary[Vector3, Dictionary] = {}
var _ambience_order: Array[Vector3] = []
var _ambience_world_id: int = 0
var _ambience_data_id: int = 0
var _ambience_epoch: int = -1
var _ambience_sequence: int = -1
var _ambience_generation: int = -1
var _workload_timing: bool = false
var _ambience_calls: int = 0
var _ambience_hits: int = 0
var _ambience_misses: int = 0
var _ambience_bypasses: int = 0
var _ambience_rays: int = 0
var _ambience_usec: int = 0
var _ground_rays: int = 0
var _ground_usec: int = 0
var _dry_players_created: int = 0
var _wet_players_created: int = 0
var _spatial_players_created: int = 0
var _players_released: int = 0
var _active_players: int = 0
var _peak_active_players: int = 0
var _player_create_usec: int = 0
var _player_release_usec: int = 0
var _voice_update_calls: int = 0
var _voice_update_usec: int = 0

func setup(voxel_world: VoxelWorld,listener: Camera3D) -> void:
	stop()
	world=voxel_world
	camera=listener
	_random.randomize()
	_environment.set_query(world.data if world != null else null)
	_environment_frame = -1

static func inverse_gain(gain: float,distance: float,reference_distance: float) -> float:
	return maxf(0.0,gain)/maxf(1.0,maxf(0.0,distance)/maxf(.001,reference_distance))

static func effective_gain(gain: float, distance: float, reference: float, local: bool, stereo: bool = false, setting: float = 1.0) -> float:
	# OpenAL MIN_GAIN=0/MAX_GAIN=1 apply AFTER distance attenuation. The
	# native stereo-world UpdateObstruction assignment omits s_gain.
	var volume: float = maxf(0.0, gain) * (1.0 if stereo and not local else clampf(setting, 0.0, 4.0))
	return clampf(volume if local else inverse_gain(volume, distance, reference), 0.0, 1.0)

static func effective_wet_gain(gain: float, distance: float, reference: float, local: bool, stereo: bool, setting: float, decay_time: float) -> float:
	# EFX ROOM has roomRolloff=0. This explicit OpenAL Soft1.17.2 automatic
	# wet-gain adapter uses apparent attenuation distance, then MAX_GAIN.
	if local or stereo:
		return effective_gain(gain, distance, reference, local, stereo, setting)
	var apparent: float = maxf(distance / maxf(.001, reference), 1.0) - 1.0
	return clampf(maxf(0.0, gain) * clampf(setting, 0.0, 4.0) * pow(.001, apparent / (maxf(.1, decay_time) * 343.3)), 0.0, 1.0)

static func ambience_from_samples(distances: Array,opposite_hits: Array) -> Dictionary:
	var count:=0
	var size:=0.0
	var feedback:=0.0
	for distance in distances:
		if float(distance)<40.0:count+=1;size+=float(distance)
	for hit in opposite_hits:feedback+=1.0 if bool(hit) else 0.0
	var reflections:=.1
	if count>6:size/=count;reflections=float(count)/24.0
	else:size=100.0
	feedback=clampf((feedback/24.0-.35)/.5,0,1)
	size=clampf(size/15.0,0,1)
	return {"size":size,"room":reflections*feedback*clampf((size-.1)*4.0,0,1)*(1.0-size*.3)}

func compute_ambience(origin: Vector3) -> Dictionary:
	var started: int = Time.get_ticks_usec() if _workload_timing else 0
	_ambience_calls += 1
	if not environmental or not is_instance_valid(world):
		clear_ambience_cache()
		_ambience_bypasses += 1
		return _finish_ambience({"room":0.0,"size":0.0}, started)
	var cacheable: bool = _prepare_ambience_cache(origin)
	if cacheable and _ambience_cache.has(origin):
		_ambience_hits += 1
		# Every caller owns its scalar result, including cache hits.
		return _finish_ambience(_ambience_cache[origin].duplicate(), started)
	if cacheable:_ambience_misses += 1
	else:_ambience_bypasses += 1
	var distances: Array[float]=[]
	var feedback: Array[bool]=[]
	for source in AMBIENCE_DIRECTIONS:
		var direction:=Vector3(source.x,-source.z,source.y)
		var hit:=_acoustic_ray(origin,direction,40.0)
		# Native CastRay reports an integer corner. W maps its z corner to
		# the top of a Godot voxel, rather than the voxel's lower y corner.
		distances.append(origin.distance_to(Vector3(hit.cell)+Vector3.UP) if hit.hit else 80.0)
		feedback.append(bool(_acoustic_ray(origin,-direction,40.0).hit) if hit.hit else false)
	var result: Dictionary = ambience_from_samples(distances,feedback)
	if cacheable:
		if _ambience_order.size() >= MAX_AMBIENCE_CACHE:
			_ambience_cache.erase(_ambience_order.pop_front())
		_ambience_order.append(origin)
		_ambience_cache[origin] = result.duplicate()
	return _finish_ambience(result, started)

func _finish_ambience(result: Dictionary, started: int) -> Dictionary:
	if _workload_timing:_ambience_usec += Time.get_ticks_usec() - started
	return result

func _prepare_ambience_cache(origin: Vector3) -> bool:
	if not ambience_cache_enabled or not origin.is_finite() or not (world.data is VoxelData):
		clear_ambience_cache()
		return false
	var data: VoxelData = world.data
	var world_id: int = world.get_instance_id()
	var data_id: int = data.get_instance_id()
	var generation: int = OpenSpadesExtensions.get_generation()
	if world_id != _ambience_world_id or data_id != _ambience_data_id or data.epoch != _ambience_epoch or data.map_sequence != _ambience_sequence or generation != _ambience_generation:
		clear_ambience_cache()
		_ambience_world_id = world_id
		_ambience_data_id = data_id
		_ambience_epoch = data.epoch
		_ambience_sequence = data.map_sequence
		_ambience_generation = generation
	return true

func clear_ambience_cache() -> void:
	_ambience_cache.clear()
	_ambience_order.clear()
	_ambience_world_id = 0
	_ambience_data_id = 0
	_ambience_epoch = -1
	_ambience_sequence = -1
	_ambience_generation = -1

func reload_resources() -> void:
	# Main can call this explicitly; generation checks also catch pack reloads.
	clear_ambience_cache()
	_stereo.clear()

func _acoustic_ray(origin: Vector3,direction: Vector3,distance: float) -> Dictionary:
	_ambience_rays += 1
	if world.data != null and world.data.has_method("cast_source_ray_legacy"):
		return world.data.cast_source_ray_legacy(origin,direction,distance)
	return world.cast_voxel(origin,direction,distance)

static func weapon_layers(weapon: int,first_person: bool,room: float,size: float,variant: int=1,ambience_variant: int=1) -> Array[Dictionary]:
	var layers: Array[Dictionary]=[]
	if weapon<0 or weapon>2:return layers
	var prefix: String="Weapons/"+WEAPONS[weapon]+"/"
	var ambience:="V2Ambience"+("Small" if size<.5 else "Large")
	if weapon==1:
		layers.append({"path":prefix+("V2Local" if first_person else "V2Third")+str(clampi(variant,1,4)),"gain":8.0 if first_person else 9.0,"reference":1.0})
		layers.append({"path":prefix+ambience+str(clampi(ambience_variant,1,4)),"gain":8.0*room,"reference":1.0 if first_person else 10.0})
		if not first_person:
			layers.append({"path":prefix+"FireFar","gain":.4,"reference":10.0})
			layers.append({"path":prefix+"FireStereo","gain":.4,"reference":1.0})
	elif weapon==0:
		layers.append({"path":prefix+("FireLocal" if first_person else "Fire"+str(clampi(variant,1,3))),"gain":8.0 if first_person else 20.0,"reference":1.0})
		layers.append({"path":prefix+ambience,"gain":(8.0 if first_person else 20.0)*room,"reference":1.0})
		layers.append({"path":prefix+"FireFar","gain":1.0,"reference":4.0 if first_person else 26.0})
		layers.append({"path":prefix+"FireStereo","gain":1.0,"reference":1.0 if first_person else 4.0})
	else:
		layers.append({"path":prefix+("FireLocal" if first_person else "Fire"),"gain":8.0,"reference":1.0})
		layers.append({"path":prefix+ambience,"gain":8.0*room,"reference":1.0})
		layers.append({"path":prefix+"FireFar","gain":2.0,"reference":1.0 if first_person else 4.0})
		layers.append({"path":prefix+"FireStereo","gain":2.0,"reference":1.0})
	return layers

func weapon_fire(weapon: int,first_person: bool,eye: Vector3,origin: Vector3) -> void:
	var ambience:=compute_ambience(eye)
	var variant:=_random.randi_range(1,3 if weapon==0 else 4)
	var layers:=weapon_layers(weapon,first_person,ambience.room,ambience.size,variant,_random.randi_range(1,4))
	for layer in layers:
		if first_person:play_local(layer.path,layer.gain,LOCAL_ORIGIN)
		else:play_spatial(layer.path,origin,layer.gain,layer.reference)

func weapon_reload(weapon: int,first_person: bool,origin: Vector3) -> void:
	var path: String="Weapons/"+WEAPONS[clampi(weapon,0,2)]+("/ReloadLocal" if first_person else "/Reload")
	if first_person:play_local(path,.2,LOCAL_ORIGIN)
	else:play_spatial(path,origin,.2)

func weapon_reloaded(weapon: int,first_person: bool,origin: Vector3) -> void:
	if weapon!=2:return
	if first_person:play_local("Weapons/Shotgun/CockLocal",.2,LOCAL_ORIGIN)
	else:play_spatial("Weapons/Shotgun/Cock",origin,.2)

static func explosion_layers(underwater: bool,variant: int=1) -> Array[Dictionary]:
	var prefix:="Weapons/Grenade/"
	if underwater:return [{"path":prefix+"WaterExplode","gain":10.0,"reference":1.0},{"path":prefix+"WaterExplodeFar","gain":6.0,"reference":10.0},{"path":prefix+"WaterExplodeStereo","gain":2.0,"reference":10.0}]
	return [{"path":prefix+"Explode"+str(clampi(variant,1,2)),"gain":30.0,"reference":5.0},{"path":prefix+"ExplodeStereo"+str(clampi(variant,1,2)),"gain":30.0,"reference":1.0},{"path":prefix+"ExplodeFar","gain":6.0,"reference":40.0},{"path":prefix+"ExplodeFarStereo","gain":6.0,"reference":10.0},{"path":prefix+"Debris","gain":5.0,"reference":3.0}]

func explosion(point: Vector3,underwater: bool) -> void:
	for layer in explosion_layers(underwater,_random.randi_range(1,2)):
		var origin:=point
		if str(layer.path).ends_with("Debris") and world!=null:
			var started: int = Time.get_ticks_usec() if _workload_timing else 0
			_ground_rays += 1
			var ground:=world.cast_voxel(point,Vector3.DOWN,8.0)
			if _workload_timing:_ground_usec += Time.get_ticks_usec() - started
			if ground.hit:origin=Vector3(ground.cell)+Vector3(0,.8,0)
		_play(layer.path,layer.gain,origin,false,layer.reference,true)

func play_local(path: String,gain: float=1.0,offset: Vector3=Vector3.ZERO) -> Node:
	return _play(path,gain,offset,true,1.0)

func play_spatial(path: String,point: Vector3,gain: float=1.0,reference_distance: float=1.0) -> Node:
	return _play(path,gain,point,false,reference_distance)

func flesh_hit(point: Vector3,local: bool=false) -> void:
	var variant:=_random.randi_range(1,4 if local else 3)
	if local:play_local("Weapons/Impacts/FleshLocal"+str(variant))
	else:play_spatial("Weapons/Impacts/Flesh"+str(variant),point,4.0)

static func impact_layers(water: bool,variant: int=1) -> Array[Dictionary]:
	var numbered:="Weapons/Impacts/"+("Water" if water else "Ricochet")+str(clampi(variant,1,4))
	if water:return [{"path":numbered,"gain":2.0,"reference":1.0}]
	return [{"path":"Weapons/Impacts/Block","gain":2.0,"reference":1.0},{"path":numbered,"gain":2.0,"reference":1.0}]

func bullet_impact(point: Vector3,normal: Vector3,water: bool) -> void:
	var shifted:=point+normal*.05
	for entry in impact_layers(water,_random.randi_range(1,4)):
		var voice:=play_spatial(entry.path,shifted,entry.gain,entry.reference)
		if voice!=null and not str(entry.path).ends_with("/Block"):voice.pitch_scale=.9+_random.randf()*.2

static func is_stereo(stream: AudioStream) -> bool:
	if stream is AudioStreamOggVorbis and stream.packet_sequence!=null:
		var pages: Array=stream.packet_sequence.packet_data
		if not pages.is_empty() and not pages[0].is_empty():
			var packet: PackedByteArray=pages[0][0]
			if packet.size()>11 and packet[0]==1 and packet.slice(1,7).get_string_from_ascii()=="vorbis":return packet[11]>1
	if stream is AudioStreamWAV:return stream.stereo
	return false

func _play(path: String,gain: float,point: Vector3,local: bool,reference_distance: float,blast_falloff: bool = false) -> Node:
	# A button's later signal listener can outlive immediate scene replacement.
	if gain<=0.0 or not is_instance_valid(camera) or not is_inside_tree() or not camera.is_inside_tree():return null
	var stream:=OpenSpadesExtensions.sound("res://assets/openspades/sounds/"+path+".ogg")
	if stream==null:return null
	return _start_voice(stream,path,gain,point,local,reference_distance,blast_falloff)

func _start_voice(stream: AudioStream, path: String, gain: float, point: Vector3, local: bool, reference_distance: float, blast_falloff: bool = false) -> Node:
	var identifier:=stream.get_instance_id()
	if not _stereo.has(identifier):_stereo[identifier]=is_stereo(stream)
	var spatial: bool=not _stereo[identifier] and positional and (not local or point!=Vector3.ZERO)
	_ensure_buses()
	_begin_environment_turn()
	var voice: Node = _new_player(stream, spatial, local, point, reference_distance)
	voice.set_meta("local",local)
	voice.set_meta("path",path)
	voice.set_meta("gain",gain)
	voice.set_meta("origin",point)
	voice.set_meta("reference",reference_distance)
	voice.set_meta("stereo",bool(_stereo[identifier]))
	voice.set_meta("blast_falloff",blast_falloff)
	voice.set_meta("efx_eligible",not local or point!=Vector3.ZERO)
	voice.set_meta("copies",[])
	_update_routes(voice)
	_update_gain(voice)
	voice.finished.connect(func():_release(voice))
	_voices.append(voice)
	while _voices.size()>MAX_VOICES:_release(_voices[0])
	# Plain stream players register immediately. 3D players queue their start
	# for the same physics turn; see measured mix-block scheduling limits.
	AudioServer.lock()
	voice.play()
	for copy: Node in voice.get_meta("copies",[]):copy.play()
	AudioServer.unlock()
	return voice

func _new_player(stream: AudioStream, spatial: bool, local: bool, point: Vector3, reference_distance: float, wet: bool = false) -> Node:
	var started: int = Time.get_ticks_usec() if _workload_timing else 0
	if spatial:
		var player:=AudioStreamPlayer3D.new()
		player.playback_type=AudioServer.PLAYBACK_TYPE_STREAM
		player.stream=stream
		player.attenuation_model=AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.max_distance=0.0
		player.unit_size=reference_distance
		player.max_db=3.0103 if wet else 0.0
		player.attenuation_filter_cutoff_hz=20500.0
		if wet:player.panning_strength=0.0
		if local:
			camera.add_child(player)
			player.position=Vector3(point.x,point.y,-point.z)
		else:
			add_child(player)
			player.global_position=point
		_record_player_created(wet, spatial, started)
		return player
	else:
		var player:=AudioStreamPlayer.new()
		player.playback_type=AudioServer.PLAYBACK_TYPE_STREAM
		player.stream=stream
		add_child(player)
		_record_player_created(wet, spatial, started)
		return player

func _record_player_created(wet: bool, spatial: bool, started: int) -> void:
	if wet:_wet_players_created += 1
	else:_dry_players_created += 1
	if spatial:_spatial_players_created += 1
	_active_players += 1
	_peak_active_players = maxi(_peak_active_players, _active_players)
	if _workload_timing:_player_create_usec += Time.get_ticks_usec() - started

func _update_gain(voice: Node) -> void:
	var raw: float=voice.get_meta("gain",1.0)
	var local: bool=voice.get_meta("local",true)
	var stereo: bool=voice.get_meta("stereo",false)
	var distance: float=0.0 if local else camera.global_position.distance_to(voice.get_meta("origin",Vector3.ZERO))
	var reference: float=voice.get_meta("reference",1.0)
	var gain: float=effective_gain(raw,distance,reference,local,stereo,source_gain)
	var blast_gain: float=GrenadeFeedback.distance_gain(distance) if voice.get_meta("blast_falloff",false) else 1.0
	gain*=blast_gain
	voice.volume_db=linear_to_db(maxf(.000001,gain))
	var wet_gain: float=effective_wet_gain(raw,distance,reference,local,stereo,source_gain,float(_environment.parameters.decay_time))
	wet_gain*=blast_gain
	var target_pitch: float=voice.pitch_scale
	var target_transform: Transform3D=voice.global_transform if voice is AudioStreamPlayer3D else Transform3D.IDENTITY
	for copy: Node in voice.get_meta("copies",[]):
		copy.volume_db=linear_to_db(maxf(.000001,wet_gain))+(3.0103 if copy is AudioStreamPlayer3D else 0.0)
		# The native pitch setter visits AudioServer playbacks even for an equal
		# value. Preserve every actual change without repeating that work.
		if copy.pitch_scale != target_pitch:copy.pitch_scale=target_pitch
		if copy is AudioStreamPlayer3D and copy.global_transform != target_transform:
			copy.global_transform=target_transform

func _process(_delta: float) -> void:
	if camera==null:return
	if _owned_buses.is_empty():return
	_begin_environment_turn()
	_apply_room_parameters()
	var started: int = Time.get_ticks_usec() if _workload_timing else 0
	# Rotate obstruction refresh priority so a full voice pool cannot starve
	# newer origins indefinitely when the ray/time budget is exhausted.
	for offset: int in range(_voices.size()):
		var voice: Node=_voices[(_route_cursor+offset)%_voices.size()]
		_update_routes(voice)
		_update_gain(voice)
		_voice_update_calls += 1
	if _workload_timing:_voice_update_usec += Time.get_ticks_usec() - started
	_route_cursor=(_route_cursor+1)%maxi(1,_voices.size())
	_environment.finish_turn()
	# Master is a separate user output setting, applied after this owned bus.
	# Reserve extra headroom if it amplifies, without mutating a shared bus.
	_limiter.ceiling_db=-.3-maxf(0.0,AudioServer.get_bus_volume_db(0))

func _release(voice: Node) -> void:
	var started: int = Time.get_ticks_usec() if _workload_timing else 0
	_voices.erase(voice)
	for copy: Node in voice.get_meta("copies",[]):
		copy.stop()
		copy.stream=null
		copy.queue_free()
		_record_player_released()
	voice.set_meta("copies",[])
	voice.stop()
	voice.stream=null
	voice.queue_free()
	_record_player_released()
	if _workload_timing:_player_release_usec += Time.get_ticks_usec() - started

func _record_player_released() -> void:
	_players_released += 1
	_active_players -= 1

func stop() -> void:
	clear_ambience_cache()
	AudioServer.lock()
	for voice in _voices.duplicate():_release(voice)
	_stereo.clear()
	for name: StringName in _owned_buses:
		var index: int=AudioServer.get_bus_index(name)
		if index>=0:AudioServer.remove_bus(index)
	_owned_buses.clear()
	_buses.clear()
	_early_delay=null
	_late_delay=null
	_reverb=null
	_limiter=null
	_last_parameters.clear()
	_environment.set_query(null)
	_environment_frame=-1
	_route_cursor=0
	AudioServer.unlock()

func get_output_bus() -> StringName:
	_ensure_buses()
	return _buses.output

func reset_environment() -> void:
	## Explicit lifecycle hook for an in-place map replacement with the same
	## epoch/sequence. Ordinary block edits only invalidate obstruction answers.
	clear_ambience_cache()
	_environment.set_query(world.data if is_instance_valid(world) else null)
	_environment_frame=-1
	_last_parameters.clear()

func set_output_bus(name: StringName) -> void:
	_output_send=name if AudioServer.get_bus_index(name)>=0 else &"Master"
	if not _owned_buses.is_empty():AudioServer.set_bus_send(AudioServer.get_bus_index(_buses.output),_output_send)

func debug_environment() -> Dictionary:
	var state: Dictionary=_environment.debug_state()
	state.owned_buses=_owned_buses.duplicate()
	state.logical_voices=_voices.size()
	var copies: int=0
	for voice: Node in _voices:copies+=voice.get_meta("copies",[]).size()
	state.wet_copies=copies
	state.efx_enabled=efx_enabled
	state.source_gain=source_gain
	state.output_send=_output_send
	state.backend="Godot stream; Freeverb + separate early/late delays + high shelves + hard limiter"
	state.workload = debug_workload()
	return state

func set_workload_timing_enabled(enabled: bool) -> void:
	_workload_timing = enabled
	_environment.workload_timing_enabled = enabled

func reset_workload_counters() -> void:
	_ambience_calls = 0
	_ambience_hits = 0
	_ambience_misses = 0
	_ambience_bypasses = 0
	_ambience_rays = 0
	_ambience_usec = 0
	_ground_rays = 0
	_ground_usec = 0
	_dry_players_created = 0
	_wet_players_created = 0
	_spatial_players_created = 0
	_players_released = 0
	_peak_active_players = _active_players
	_player_create_usec = 0
	_player_release_usec = 0
	_voice_update_calls = 0
	_voice_update_usec = 0
	_environment.reset_workload_counters()

func debug_workload() -> Dictionary:
	# Scalar snapshot: callers cannot mutate counters or cache values.
	return {"timing_enabled": _workload_timing, "ambience_cache_enabled": ambience_cache_enabled,
		"ambience_cache_capacity": MAX_AMBIENCE_CACHE, "ambience_cache_entries": _ambience_cache.size(),
		"ambience_calls": _ambience_calls, "ambience_cache_hits": _ambience_hits, "ambience_cache_misses": _ambience_misses,
		"ambience_bypasses": _ambience_bypasses, "ambience_rays": _ambience_rays, "ambience_usec": _ambience_usec,
		"ground_rays": _ground_rays, "ground_usec": _ground_usec, "environment_rays": _environment.total_rays,
		"room_rays": _environment.total_room_rays, "obstruction_rays": _environment.total_obstruction_rays,
		"environment_trace_usec": _environment.total_trace_usec, "audio_rays_total": _ambience_rays + _ground_rays + _environment.total_rays,
		"dry_players_created": _dry_players_created, "wet_players_created": _wet_players_created,
		"spatial_players_created": _spatial_players_created, "players_released": _players_released,
		"active_players": _active_players, "peak_active_players": _peak_active_players,
		"player_create_usec": _player_create_usec, "player_release_usec": _player_release_usec,
		"voice_update_calls": _voice_update_calls, "voice_update_usec": _voice_update_usec}

func _bus(key: String, send: StringName) -> void:
	var name: StringName=StringName("OpenSpades_%d_%s"%[get_instance_id(),key])
	AudioServer.add_bus()
	var index: int=AudioServer.get_bus_count()-1
	AudioServer.set_bus_name(index,name)
	AudioServer.set_bus_send(index,send)
	_owned_buses.append(name)
	_buses[key]=name

func _shelf(gain_hf: float) -> AudioEffectHighShelfFilter:
	var effect:=AudioEffectHighShelfFilter.new()
	# Godot's biquad uses A=gain and asymptotic HF=A². The reference is5kHz.
	effect.gain=sqrt(gain_hf)
	effect.cutoff_hz=5000.0
	effect.resonance=.5
	effect.db=AudioEffectFilter.FILTER_6DB
	return effect

func _delay() -> AudioEffectDelay:
	var effect:=AudioEffectDelay.new()
	effect.dry=0.0
	effect.tap1_active=true
	effect.tap1_level_db=0.0
	effect.tap2_active=false
	effect.feedback_active=false
	return effect

func _ensure_buses() -> void:
	if not _owned_buses.is_empty():return
	_bus("output",_output_send)
	_limiter=AudioEffectHardLimiter.new()
	_limiter.ceiling_db=-.3-maxf(0.0,AudioServer.get_bus_volume_db(0))
	_limiter.pre_gain_db=0.0
	_limiter.release=.1
	AudioServer.add_bus_effect(AudioServer.get_bus_index(_buses.output),_limiter)
	_bus("early",_buses.output)
	_early_delay=_delay()
	AudioServer.add_bus_effect(AudioServer.get_bus_index(_buses.early),_shelf(.5929))
	AudioServer.add_bus_effect(AudioServer.get_bus_index(_buses.early),_early_delay)
	_bus("late",_buses.output)
	_late_delay=_delay()
	_reverb=AudioEffectReverb.new()
	_reverb.dry=0.0
	_reverb.predelay_msec=0.0
	_reverb.predelay_feedback=0.0
	_reverb.spread=1.0
	_reverb.hipass=0.0
	_reverb.damping=.2
	AudioServer.add_bus_effect(AudioServer.get_bus_index(_buses.late),_late_delay)
	AudioServer.add_bus_effect(AudioServer.get_bus_index(_buses.late),_shelf(.5929))
	AudioServer.add_bus_effect(AudioServer.get_bus_index(_buses.late),_reverb)
	for path: String in ["dry","early","late"]:
		for blocked: bool in [false,true]:
			var key: String=path+("_blocked" if blocked else "_clear")
			_bus(key,_buses.output if path=="dry" else _buses[path])
			if blocked:AudioServer.add_bus_effect(AudioServer.get_bus_index(_buses[key]),_shelf(.1))
	_apply_room_parameters()

func _apply_room_parameters() -> void:
	var parameters: Dictionary=_environment.parameters
	if parameters==_last_parameters:return
	_last_parameters=parameters.duplicate(true)
	_early_delay.tap1_delay_ms=float(parameters.early_delay)*1000.0
	_late_delay.tap1_delay_ms=float(parameters.late_onset)*1000.0
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(_buses.early),linear_to_db(maxf(.000001,float(parameters.gain)*float(parameters.early_gain))))
	AudioServer.set_bus_mute(AudioServer.get_bus_index(_buses.early),not efx_enabled or float(parameters.gain)==0.0)
	_reverb.wet=clampf(float(parameters.gain)*float(parameters.late_gain)/.6,0.0,1.0)
	AudioServer.set_bus_mute(AudioServer.get_bus_index(_buses.late),not efx_enabled or _reverb.wet==0.0)
	# Match low-frequency T60 through the longest36.667ms Freeverb comb.
	# Its feedback floor.7 bounds the short-room adaptation (~.71sec).
	var feedback: float=exp(log(.001)*.0366666667/maxf(.1,float(parameters.decay_time)))
	_reverb.room_size=clampf((feedback-.7)/.28,0.0,1.0)

func _begin_environment_turn() -> void:
	var frame: int=Engine.get_process_frames()
	if frame==_environment_frame:return
	_environment_frame=frame
	var query: Variant=world.data if is_instance_valid(world) else null
	if query!=_environment.query:_environment.set_query(query)
	_environment.begin_turn(float(Time.get_ticks_usec())/1000000.0)
	if efx_enabled:_environment.sample_room(camera.global_position)
	# A changed flag must update bus mute even if the room parameters did not.
	if not _owned_buses.is_empty():
		AudioServer.set_bus_mute(AudioServer.get_bus_index(_buses.early),not efx_enabled or float(_environment.parameters.gain)==0.0)
		AudioServer.set_bus_mute(AudioServer.get_bus_index(_buses.late),not efx_enabled or _reverb.wet==0.0)

func _update_routes(voice: Node) -> void:
	var eligible: bool=efx_enabled and bool(voice.get_meta("efx_eligible",false))
	var copies: Array=voice.get_meta("copies",[])
	var added: bool=false
	if not eligible and not copies.is_empty():
		for copy: Node in copies:
			copy.stop()
			copy.stream=null
			copy.queue_free()
			_record_player_released()
		copies.clear()
	elif eligible and copies.is_empty():
		added=true
		for _branch: int in range(2):
			var copy: Node=_new_player(voice.stream,voice is AudioStreamPlayer3D,bool(voice.get_meta("local")),voice.get_meta("origin"),float(voice.get_meta("reference")),true)
			copies.append(copy)
	voice.set_meta("copies",copies)
	var blocked: bool=false
	if eligible and not bool(voice.get_meta("local",false)):
		blocked=bool(_environment.obstruction(camera.global_position,voice.get_meta("origin")).blocked)
	var suffix: String="_blocked" if blocked else "_clear"
	voice.bus=_buses["dry"+suffix]
	voice.set_meta("blocked",blocked)
	for index: int in range(copies.size()):copies[index].bus=_buses[("early" if index==0 else "late")+suffix]
	if added and voice.playing:
		_update_gain(voice)
		AudioServer.lock()
		for copy: Node in copies:copy.play(voice.get_playback_position())
		AudioServer.unlock()

func _exit_tree() -> void:
	stop()
