extends SceneTree
## Snapshot identity, authored geometry, finite pools and presentation isolation.
const VIEW = preload("res://presentation/arsenal_view.gd")
const AUDIO = preload("res://presentation/arsenal_audio.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var world: Node3D = Node3D.new()
	root.add_child(world)
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(3, 4, 5)
	var view: ArsenalView = VIEW.new()
	world.add_child(view)
	view.configure(camera)
	var identity: Array[int] = _node_ids(view)
	_check(identity.size() == VIEW.STATE_CAP + VIEW.EVENT_CAP + 3 and _count_physics(view) == 0, "Cap-relative fixed allocation has no physics nodes or per-voxel allocation")
	_check(not view.get_display_state().held_visible, "New view does not replace source weapon implicitly")
	var shapes: Array[int] = []
	for index: int in range(1, 21):
		var id: String = "x%02d" % index
		var readout: Dictionary = {"selected_item": id, "enabled": true, "first_person": true, "charge": .4, "heat": .2, "magazine": 3}
		var before: Dictionary = readout.duplicate(true)
		view.update_readout(readout, .1)
		var mesh: ArrayMesh = view._held.mesh as ArrayMesh
		_check(view.get_display_state().held_visible and mesh != null and mesh.get_surface_count() == 1, "Every item has authored baked equipment geometry: " + id)
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var signature: int = hash(vertices)
		_check(not signature in shapes, "Item differs in silhouette geometry, beyond color: " + id)
		shapes.append(signature)
		_check(readout == before, "Rendering equipment never changes its authority readout: " + id)
	_check(view._held.layers == VIEW.VIEW_LAYER and camera.cull_mask & VIEW.VIEW_LAYER != 0, "First-person models use the existing reflection-excluded view layer")
	view.update_readout({"selected_item": "source", "enabled": true}, 0)
	_check(not view._held.visible, "Returning to source hides only authored equipment")
	var states: Array[Dictionary] = []
	for index: int in VIEW.STATE_CAP + 16:
		states.append({"id": index + 1, "item": "x%02d" % (index % 20 + 1), "kind": "projectile", "position": Vector3(index, 0, -3), "direction": Vector3.FORWARD, "remaining": .5})
	var events: Array[Dictionary] = []
	for index: int in 30:
		events.append({"id": index, "item": "x03", "type": "beam", "position": Vector3(index, 2, 0), "end_position": Vector3(index, 2, -4), "radius": .1})
	var originals: Array[Dictionary] = states.duplicate(true)
	view.present(events, states)
	_check(view.get_display_state().state_count == VIEW.STATE_CAP and view.get_display_state().event_count == VIEW.EVENT_CAP, "Overflow cannot grow state or event geometry pools")
	_check(_node_ids(view) == identity and states == originals, "Present consumes snapshots without allocation or authority mutation")
	states.append({"id": 900, "item": "x16", "kind": "sun", "warning": true, "position": Vector3(1,0,1), "radius":6.0})
	events.append({"id": 901, "item": "x17", "type": "warning", "position": Vector3(2,0,1), "radius":1.5})
	view.present(events, states)
	_check(view._slot_ids.has("900") and view._states[view._slot_ids.find("900")].visible, "A late danger telegraph displaces ordinary projectile geometry at saturation")
	_check((view._states[view._slot_ids.find("900")].material_override as StandardMaterial3D).no_depth_test, "Thin danger lines remain readable at a voxel target surface")
	_check(view._events[0].mesh == VIEW._effect_mesh("warning", "x17"), "Critical warning event is presented ahead of an oversized ordinary effect batch")
	var slot: MeshInstance3D = view._states[view._slot_ids.find("1")]
	var at: Transform3D = slot.transform
	view.update_readout({"selected_item": "x01", "enabled": true, "charge": 1.0}, 1000.0)
	_check(slot.transform == at and view.get_display_state().state_count == VIEW.STATE_CAP, "Render delta cannot move a projectile or expire simulation state")
	states = [{"id": 1, "item": "x02", "kind": "projectile", "position": Vector3(7, 8, 9), "direction": Vector3.RIGHT, "remaining": .1}]
	view.present([], states)
	_check(slot.position == Vector3(7, 8, 9) and view._states[view._slot_ids.find("1")] == slot, "Stable authority ID reuses its mesh slot and committed position")
	_check(view.get_display_state().state_count == 1 and view.get_display_state().event_count == 0, "Omitted snapshot records and old event geometry hide immediately")
	var variants: Array[Dictionary] = [
		{"id": 2, "item": "x13", "kind": "field", "position": Vector3.ONE, "radius": 5.0},
		{"id": 3, "item": "x18", "kind": "warning", "position": Vector3(2, 0, 3), "radius": 2.0},
		{"id": 4, "item": "x19", "kind": "turret", "position": Vector3(3, 0, 4), "direction": Vector3.LEFT},
		{"id": 5, "item": "x20", "kind": "jet", "position": Vector3(0, 2, 0), "end_position": Vector3(0, 0, 0)}]
	view.present([], variants)
	_check(view.get_display_state().state_count == 4, "Fields, warnings, finite turret and jetpack all have snapshot-driven geometry")
	view.update_readout({"selected_item":"x01", "enabled":true, "first_person":false}, 0)
	_check(not view._held.visible and view.get_display_state().state_count == 4, "Third-person camera hides held equipment while preserving committed world geometry")
	view.update_readout({"selected_item":"x01", "enabled":true, "first_person":true}, 0)
	_check(view._held.visible, "Returning to first person restores the selected authored silhouette")
	view.present([], [{"id": 7, "item": "x02", "position": Vector3.INF}, {"id": 8, "item": "unknown", "position": Vector3.ZERO}])
	_check(view.get_display_state().state_count == 0, "Nonfinite geometry and unknown IDs fail closed")
	view.clear()
	_check(not view.get_display_state().held_visible and view.get_display_state().state_count == 0 and view.get_display_state().event_count == 0, "Lifecycle clear removes every held/world/event visual")
	_check(_node_ids(view) == identity and view.get_display_state().particle_count == 0, "Many selections/reset reuse nodes and never add a decorative particle pool")
	await _check_audio()
	world.free()
	print("ARSENAL VIEW: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _check_audio() -> void:
	var audio: ArsenalAudio = AUDIO.new()
	root.add_child(audio)
	var audio_ids: Array[int] = _node_ids(audio)
	var signatures: Array[int] = []
	for index: int in range(1, 21):
		var key: String = "x%02d:fire" % index
		var wav: AudioStreamWAV = AUDIO._clip(key)
		_check(wav != null and not wav.stereo and wav.mix_rate == 22050 and wav.get_length() <= 1.0 and wav.data.size() > 100, "Each invented item has a short mono procedural sound: " + key)
		var signature: int = hash(wav.data)
		_check(not signature in signatures and wav == AUDIO._clip(key), "Item PCM is distinct and cached rather than resynthesized: " + key)
		signatures.append(signature)
	_check(AUDIO._clip("x16:warning").data != AUDIO._clip("x16:boom").data, "Fuse siren and explosion are separate original clips")
	var notes: Array[int] = []
	for index: int in 5: notes.append(hash(AUDIO._clip("x18:note%d" % index).data))
	_check(notes.size() == 5 and notes[0] != notes[1] and notes[1] != notes[2] and notes[2] != notes[3] and notes[3] != notes[4], "The piano sequence uses five different notes")
	var volume: float = AudioServer.get_bus_volume_db(0)
	var mute: bool = AudioServer.is_bus_mute(0)
	var effects: Array[Dictionary] = []
	for index: int in range(1, 21): effects.append({"type": "fired", "item": "x%02d" % index})
	var original: Array[Dictionary] = effects.duplicate(true)
	audio.play(effects)
	_check(audio.get_display_state().voices == 4 and audio.get_display_state().active <= 4 and _node_ids(audio) == audio_ids, "A burst of twenty sounds cannot create more than four reusable voices")
	_check(effects == original and AudioServer.get_bus_volume_db(0) == volume and AudioServer.is_bus_mute(0) == mute, "Playback does not alter events or global volume/mute")
	for voice: AudioStreamPlayer in audio._voices: _check(voice.bus == &"Master", "Every voice passes through user-controlled Master output")
	audio.clear()
	audio.play([{"type":"warning", "item":"x16"}, {"type":"warning", "item":"x17"}, {"type":"warning", "item":"x18"}, {"type":"warning", "item":"x19"}])
	var warnings: Array[AudioStream] = []
	for voice: AudioStreamPlayer in audio._voices: warnings.append(voice.stream)
	audio.play(effects)
	var retained: bool = true
	for index: int in AUDIO.VOICE_CAP: retained = retained and audio._voices[index].stream == warnings[index]
	_check(retained, "Ordinary gunfire cannot steal four active warning voices")
	audio.clear()
	for index: int in 5: audio.play([{"type":"piano", "item":"x18"}])
	_check(audio.get_display_state().last_key == "x18:note4", "Five confirmed piano falls advance the five-note sequence")
	var playbacks: Array[WeakRef] = _playback_refs(audio)
	_check(playbacks.size() == AUDIO.VOICE_CAP, "Four real engine playbacks are captured for lifecycle release verification")
	audio.clear()
	_check(audio.get_display_state().active == 0 and _node_ids(audio) == audio_ids, "Reset stops all playback without reallocating the pool")
	audio.free()
	# AudioServer asynchronously retires stopped/replaced WAV playbacks. Allow
	# every <=.85s clip to finish its engine retention before ending this fixture;
	# .15s was shorter than the clip lifetime and produced shutdown ref warnings.
	await create_timer(1.25).timeout
	var released: bool = true
	for playback: WeakRef in playbacks: released = released and playback.get_ref() == null
	_check(released, "Stopped/free voices release actual playback references after bounded engine completion")

func _playback_refs(audio: ArsenalAudio) -> Array[WeakRef]:
	var result: Array[WeakRef] = []
	for voice: AudioStreamPlayer in audio._voices:
		var playback: AudioStreamPlayback = voice.get_stream_playback()
		if playback != null: result.append(weakref(playback))
	return result

func _node_ids(node: Node) -> Array[int]:
	var result: Array[int] = [node.get_instance_id()]
	for child: Node in node.get_children(): result.append_array(_node_ids(child))
	return result

func _count_physics(node: Node) -> int:
	var count: int = 1 if node is CollisionObject3D or node is CollisionShape3D or node is GPUParticles3D or node is CPUParticles3D or node is Timer else 0
	for child: Node in node.get_children(): count += _count_physics(child)
	return count

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("ARSENAL VIEW: " + message)
