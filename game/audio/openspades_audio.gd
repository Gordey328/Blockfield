class_name OpenSpadesAudio
extends Node
## Source layers/gains from v0.1.3 Skin/{Rifle,SMG,Shotgun} and Client_Update.
## Godot spatial panning replaces OpenAL; inverse-distance gain is shared by
## mono/stereo voices so disabling panning does not change loudness.

const MAX_VOICES := 128
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
var _voices: Array[Node] = []
var _stereo: Dictionary = {}
var _random := RandomNumberGenerator.new()

func setup(voxel_world: VoxelWorld,listener: Camera3D) -> void:
	world=voxel_world
	camera=listener
	_random.randomize()

static func inverse_gain(gain: float,distance: float,reference_distance: float) -> float:
	return maxf(0.0,gain)/maxf(1.0,maxf(0.0,distance)/maxf(.001,reference_distance))

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
	if not environmental or world==null:return {"room":0.0,"size":0.0}
	var distances: Array[float]=[]
	var feedback: Array[bool]=[]
	for source in AMBIENCE_DIRECTIONS:
		var direction:=Vector3(source.x,-source.z,source.y)
		var hit:=world.cast_voxel(origin,direction,40.0)
		# Native CastRay reports an integer corner. W maps its z corner to
		# the top of a Godot voxel, rather than the voxel's lower y corner.
		distances.append(origin.distance_to(Vector3(hit.cell)+Vector3.UP) if hit.hit else 80.0)
		feedback.append(bool(world.cast_voxel(origin,-direction,40.0).hit) if hit.hit else false)
	return ambience_from_samples(distances,feedback)

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
			var ground:=world.cast_voxel(point,Vector3.DOWN,8.0)
			if ground.hit:origin=Vector3(ground.cell)+Vector3(0,.8,0)
		play_spatial(layer.path,origin,layer.gain,layer.reference)

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

func _play(path: String,gain: float,point: Vector3,local: bool,reference_distance: float) -> Node:
	if gain<=0.0 or camera==null:return null
	var stream:=OpenSpadesExtensions.sound("res://assets/openspades/sounds/"+path+".ogg")
	if stream==null:return null
	var identifier:=stream.get_instance_id()
	if not _stereo.has(identifier):_stereo[identifier]=is_stereo(stream)
	var spatial: bool=not _stereo[identifier] and positional and (not local or point!=Vector3.ZERO)
	var voice: Node
	if spatial:
		var player:=AudioStreamPlayer3D.new()
		player.playback_type=AudioServer.PLAYBACK_TYPE_STREAM
		player.stream=stream
		player.attenuation_model=AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.max_distance=0.0
		player.unit_size=reference_distance
		player.max_db=linear_to_db(maxf(1.0,gain))
		player.attenuation_filter_cutoff_hz=20500.0
		if local:
			camera.add_child(player)
			player.position=Vector3(point.x,point.y,-point.z)
		else:
			add_child(player)
			player.global_position=point
		voice=player
	else:
		var player:=AudioStreamPlayer.new()
		player.playback_type=AudioServer.PLAYBACK_TYPE_STREAM
		player.stream=stream
		add_child(player)
		voice=player
	voice.set_meta("local",local)
	voice.set_meta("path",path)
	voice.set_meta("gain",gain)
	voice.set_meta("origin",point)
	voice.set_meta("reference",reference_distance)
	_update_gain(voice)
	voice.finished.connect(func():_release(voice))
	_voices.append(voice)
	while _voices.size()>MAX_VOICES:_release(_voices[0])
	voice.play()
	return voice

func _update_gain(voice: Node) -> void:
	var gain: float=voice.get_meta("gain",1.0)
	if not voice.get_meta("local",true):gain=inverse_gain(gain,camera.global_position.distance_to(voice.get_meta("origin",Vector3.ZERO)),float(voice.get_meta("reference",1.0)))
	voice.volume_db=linear_to_db(maxf(.000001,gain))

func _process(_delta: float) -> void:
	if camera==null:return
	for voice in _voices:_update_gain(voice)

func _release(voice: Node) -> void:
	_voices.erase(voice)
	voice.stop()
	voice.stream=null
	voice.queue_free()

func stop() -> void:
	for voice in _voices.duplicate():_release(voice)
	_stereo.clear()

func _exit_tree() -> void:
	stop()
