extends SceneTree
const Extensions = preload("res://presentation/openspades_extensions.gd")
const Models = preload("res://presentation/openspades_models.gd")
const ROOT := "res://assets/openspades/"
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	Extensions.clear()
	var data := {
		"model.glb":FileAccess.get_file_as_bytes(ROOT+"models/Player/Head.glb"),
		"icon.png":FileAccess.get_file_as_bytes(ROOT+"images/Gfx/AlertIcon.png"),
		"alert.ogg":FileAccess.get_file_as_bytes(ROOT+"sounds/Feedback/Alert.ogg")}
	var manifest := {"version":1,"id":"test-original","title":"Original fixture",
		"authors":["OpenSpades authors; see bundled licenses"],"license":"Original bundled licenses apply","assets":{}}
	for mapping in [["Models/Player/Head.kv6","model.glb","model"],
		["Gfx/AlertIcon.png","icon.png","texture"],["Sounds/Feedback/Alert.opus","alert.ogg","sound"]]:
		manifest.assets[mapping[0]] = {"file":mapping[1],"type":mapping[2],"sha256":Extensions._sha256(data[mapping[1]])}
	var bytes := _zip(manifest,data)
	var result := Extensions.load_pack_bytes(bytes)
	_check(result.ok,"Original GLB/PNG/Vorbis pack loads: " + str(result))
	_check(Extensions.get_packs().size() == 1,"Pack metadata records provenance")
	_check(Extensions.model_override("Player/Head") is PackedScene,"Original virtual model target resolves")
	var replacement := Models.create("Player/Head")
	_check(Models._scene_cache["Player/Head"] == Extensions.model_override("Player/Head"),"Model helper uses active pack instead of imported original")
	replacement.free()
	_check(Extensions.texture("Gfx/AlertIcon.png") is Texture2D,"Virtual texture resolves")
	_check(Extensions.sound(ROOT+"sounds/Feedback/Alert.ogg") is AudioStream,"Converted path aliases to original sound")
	var node := Extensions.model_override("Player/Head").instantiate()
	_check(node is Node3D and node.get_child_count() > 0,"Runtime GLB preserves mesh hierarchy")
	node.free()
	var generation := Extensions.get_generation()
	var first_scene := Extensions.model_override("Player/Head")
	var second := manifest.duplicate(true)
	second.id = "second"
	_check(Extensions.load_pack_bytes(_zip(second,data)).ok,"Second pack layers on top")
	_check(Extensions.get_generation() > generation,"Resource generation increments")
	_check(Extensions.get_packs().size() == 2,"Two packs are retained")
	_check(Extensions.model_override("Player/Head") != first_scene,"Newest resource pack wins")
	_check(Extensions.remove_pack("second"),"Pack can be removed")
	_check(Extensions.model_override("Player/Head") == first_scene,"Removing newest pack reveals previous resource")
	_check(not Extensions.remove_pack("missing"),"Missing pack removal reports false")
	var original_packs := Extensions.get_packs().size()
	for field in ["license","authors","title"]:
		var bad := manifest.duplicate(true)
		bad.erase(field)
		_check(not Extensions.load_pack_bytes(_zip(bad,data)).ok,"Missing attribution is rejected: " + field)
	for path in ["../escape.png","/absolute.png","C:/drive.png","a\\b.png","a/./b.png"]:
		var bad := manifest.duplicate(true)
		bad.assets["Gfx/AlertIcon.png"].file = path
		var unsafe := data.duplicate()
		unsafe[path] = data["icon.png"]
		_check(not Extensions.load_pack_bytes(_zip(bad,unsafe)).ok,"Unsafe ZIP path rejected: " + path)
	var wrong_hash := manifest.duplicate(true)
	wrong_hash.assets["Gfx/AlertIcon.png"].sha256 = "bad"
	_check(not Extensions.load_pack_bytes(_zip(wrong_hash,data)).ok,"Hash mismatch is rejected")
	var wrong_type := manifest.duplicate(true)
	wrong_type.assets["Gfx/AlertIcon.png"].type = "model"
	_check(not Extensions.load_pack_bytes(_zip(wrong_type,data)).ok,"Mismatched resource type rejected")
	var executable := data.duplicate()
	executable["execute.gd"] = "extends Node".to_utf8_buffer()
	_check(not Extensions.load_pack_bytes(_zip(manifest,executable)).ok,"Undeclared executable is rejected")
	var oversized := bytes.duplicate()
	# Corrupt first central-directory decoded size to 17 MiB. No extraction occurs.
	for offset in range(oversized.size()-46):
		if oversized.decode_u32(offset) == 0x02014b50:
			oversized.encode_u32(offset+24,17*1024*1024)
			break
	_check(not Extensions.load_pack_bytes(oversized).ok,"Decoded-size ZIP bomb is rejected before allocation")
	_check(not Extensions.load_pack_bytes(PackedByteArray([1,2,3])).ok,"Invalid ZIP rejected")
	_check(not Extensions._validate_glb(PackedByteArray([1,2,3])).ok,"Invalid GLB rejected")
	var glb := data["model.glb"] as PackedByteArray
	var description: Dictionary = JSON.parse_string(glb.slice(20,20+glb.decode_u32(12)).get_string_from_utf8())
	description.buffers[0].uri = "https://invalid.example/remote.bin"
	_check(not Extensions._validate_glb(_glb(description,glb)).ok,"External GLB URI rejected")
	for mutation in [{"nodes":42},{"nodes":[{"children":[0]}]},{"asset":"bad"},{"accessors":[{"count":"bad"}]},{"bufferViews":[{"buffer":0,"byteLength":"bad"}]}]:
		var malformed: Dictionary = JSON.parse_string(glb.slice(20,20+glb.decode_u32(12)).get_string_from_utf8())
		malformed.merge(mutation,true)
		_check(not Extensions._validate_glb(_glb(malformed,glb)).ok,"Malformed GLB property rejected without executing loader")
	_check(Extensions.get_packs().size() == original_packs,"Failed pack updates leave active resources unchanged")
	var first := Extensions.create_first_person_skin()
	var third := Extensions.create_third_person_skin()
	_check(first != null and third != null,"Both original skin entrypoints exist")
	for method in Extensions.FIRST_METHODS: _check(first.has_method(method),"First-person contract: " + method)
	for method in Extensions.THIRD_METHODS: _check(third.has_method(method),"Third-person contract: " + method)
	root.add_child(first)
	root.add_child(third)
	first.set_selection(2,1)
	first.set_team(1)
	first.update_pose(0.1,false,true,true,3,0.6)
	third.set_team(1)
	third.set_pose(true,false,true)
	third.set_weapon(1,3)
	third.set_intel_carrier(true)
	var sprint_state: float = first._sprint
	first.refresh_resources()
	third.refresh_resources()
	_check(first._weapon == 1 and first._tool == 2 and first._reload_progress == 0.6,"Weapon refresh retains selection and reload")
	_check(first._sprint == sprint_state and first._team_color == Models.TEAM_COLORS[1],"Weapon refresh retains sprint and team")
	_check(third._weapon == 1 and third._tool == 3 and third._crouching and third._carrying_intel,"Character refresh retains pose/weapon/intel")
	await process_frame
	first.queue_free()
	third.queue_free()
	await process_frame
	_check(Extensions.register_skin("test",_first,_third).ok,"Trusted compiled factories register")
	first = Extensions.create_first_person_skin("test",{"probe":42})
	third = Extensions.create_third_person_skin("test")
	_check(first.get_meta("probe") == 42,"Trusted factory receives copied context")
	_check(third != null,"Trusted third-person factory returns view")
	first.free()
	third.free()
	_check(not Extensions.register_skin("../bad",_first,_third).ok,"Unsafe skin id rejected")
	_check(not Extensions.register_skin("original",_first,_third).ok,"Built-in original factory cannot be overwritten")
	_check(Extensions.texture("Gfx/Ball.png") is Texture2D,"Unmodified resource falls back to original")
	Extensions.clear()
	_check(Extensions.get_packs().is_empty(),"Pack caches clear")
	_check(Extensions.model_override("Player/Head") == null,"Removed override returns to original")
	Models.clear_cache()
	await process_frame
	await process_frame
	print("EXTENSION_CHECKS: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
func _first(context: Dictionary) -> Node3D:
	var node: Node3D = load("res://presentation/weapon_view.gd").new()
	node.set_meta("probe",context.get("probe",0))
	return node
func _third(_context: Dictionary) -> Node3D:
	return load("res://presentation/character_view.gd").new()
func _zip(manifest: Dictionary,entries: Dictionary) -> PackedByteArray:
	var path := "user://extension-fixture.zip"
	var writer := ZIPPacker.new()
	writer.open(path)
	writer.start_file("blockfield-pack.json")
	writer.write_file(JSON.stringify(manifest).to_utf8_buffer())
	writer.close_file()
	for name in entries:
		writer.start_file(name)
		writer.write_file(entries[name])
		writer.close_file()
	writer.close()
	var bytes := FileAccess.get_file_as_bytes(path)
	DirAccess.remove_absolute(path)
	return bytes
func _glb(description: Dictionary, original: PackedByteArray) -> PackedByteArray:
	var json := JSON.stringify(description).to_utf8_buffer()
	while json.size() % 4: json.append(32)
	var bin_offset := 20+original.decode_u32(12)
	var binary := original.slice(bin_offset)
	var bytes := PackedByteArray()
	bytes.resize(20)
	bytes.encode_u32(0,0x46546c67)
	bytes.encode_u32(4,2)
	bytes.encode_u32(8,20+json.size()+binary.size())
	bytes.encode_u32(12,json.size())
	bytes.encode_u32(16,0x4e4f534a)
	bytes.append_array(json)
	bytes.append_array(binary)
	return bytes
func _check(value: bool,message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
