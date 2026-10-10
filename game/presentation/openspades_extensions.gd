@static_unload
class_name OpenSpadesExtensions
extends RefCounted
## Data-only resource packs; compiled project code may register trusted skin factories.
## Uploaded ZIPs are never mounted as PCKs and never execute scripts or scenes.
const ROOT := "res://assets/openspades/"
const MAX_ARCHIVE := 32 * 1024 * 1024
const MAX_TOTAL := 64 * 1024 * 1024
const MAX_FILE := 16 * 1024 * 1024
const MAX_FILES := 512
const FIRST_METHODS := ["set_selection","is_changing_tool","update_pose","fire","reload","set_team",
	"set_block_color","set_ammo","set_grenade_cook","set_spade_action","cancel_reload","reload_completed","get_muzzle_transform","refresh_resources"]
const THIRD_METHODS := ["set_team","set_pose","set_weapon","animate_motion","set_aim","set_intel_carrier","refresh_resources"]
static var _packs: Array[Dictionary] = []
static var _catalog: Dictionary = {}
static var _aliases: Dictionary = {}
static var _factories: Dictionary = {}
static var _generation := 0

static func get_generation() -> int:
	return _generation

static func get_packs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for pack in _packs:
		result.append({"id":pack.id,"title":pack.title,"authors":pack.authors.duplicate(),
			"license":pack.license,"archive_sha256":pack.archive_sha256,"resources":pack.resources.size()})
	return result

static func clear() -> void:
	_packs.clear()
	_factories.clear()
	_generation += 1

static func remove_pack(id: String) -> bool:
	for index in range(_packs.size()):
		if _packs[index].id == id:
			_packs.remove_at(index)
			_generation += 1
			return true
	return false

static func _fail(message: String) -> Dictionary:
	return {"ok":false,"error":message}

static func _safe_path(path: String) -> bool:
	if path.is_empty() or path.length() > 180 or path.begins_with("/") or ":" in path or "\\" in path:
		return false
	for index in range(path.length()):
		if path.unicode_at(index) < 32:
			return false
	for part in path.split("/"):
		if part in ["", ".", ".."]:
			return false
	return true

static func _load_catalog() -> void:
	if not _catalog.is_empty():
		return
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "manifest.json"))
	if not manifest is Dictionary:
		return
	for entry in manifest.get("assets",[]):
		var kind := ""
		var output: String = entry.output
		if output.begins_with("models/"): kind = "model"
		elif output.begins_with("images/"): kind = "texture"
		elif output.begins_with("sounds/"): kind = "sound"
		if not kind.is_empty():
			_catalog[entry.virtual_path] = {"type":kind,"output":output}
			_aliases[ROOT + output] = entry.virtual_path

static func _canonical(path: String) -> String:
	_load_catalog()
	return _aliases.get(path,path)

static func _override(path: String, kind: String) -> Resource:
	var key := _canonical(path)
	for index in range(_packs.size()-1,-1,-1):
		var resource: Resource = _packs[index].resources.get(key)
		if resource != null and _catalog[key].type == kind:
			return resource
	return null

static func model_override(relative_path: String) -> PackedScene:
	return _override("Models/" + relative_path + ".kv6","model") as PackedScene

static func texture(path: String) -> Texture2D:
	var replacement := _override(path,"texture") as Texture2D
	if replacement != null:
		return replacement
	var canonical := _canonical(path)
	if _catalog.has(canonical) and _catalog[canonical].type == "texture":
		return load(ROOT + _catalog[canonical].output) as Texture2D
	return load(path) as Texture2D if path.begins_with(ROOT + "images/") else null

static func sound(path: String) -> AudioStream:
	var replacement := _override(path,"sound") as AudioStream
	if replacement != null:
		return replacement
	var canonical := _canonical(path)
	if _catalog.has(canonical) and _catalog[canonical].type == "sound":
		return load(ROOT + _catalog[canonical].output) as AudioStream
	return load(path) as AudioStream if path.begins_with(ROOT + "sounds/") else null

static func load_pack_file(path: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null:
		return _fail("Cannot open resource pack")
	if file.get_length() > MAX_ARCHIVE:
		return _fail("Resource pack exceeds 32 MiB")
	return load_pack_bytes(file.get_buffer(file.get_length()))

static func load_pack_bytes(bytes: PackedByteArray) -> Dictionary:
	var preflight := _zip_directory(bytes)
	if not preflight.ok:
		return preflight
	_load_catalog()
	if _catalog.is_empty():
		return _fail("Original asset manifest is missing")
	var digest := _sha256(bytes)
	var temp_path := "user://blockfield-pack-" + digest + ".zip"
	var file := FileAccess.open(temp_path,FileAccess.WRITE)
	if file == null:
		return _fail("Cannot stage uploaded pack")
	file.store_buffer(bytes)
	file.close()
	var reader := ZIPReader.new()
	if reader.open(temp_path) != OK:
		DirAccess.remove_absolute(temp_path)
		return _fail("Invalid ZIP archive")
	var result := _read_pack(reader,preflight.files,digest)
	reader.close()
	DirAccess.remove_absolute(temp_path)
	return result

static func _sha256(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

static func _zip_directory(bytes: PackedByteArray) -> Dictionary:
	# Inspect decoded sizes before ZIPReader allocates any entry. No ZIP64/multidisk.
	if bytes.size() < 22 or bytes.size() > MAX_ARCHIVE:
		return _fail("Invalid archive size")
	var end := -1
	for offset in range(bytes.size()-22,maxi(bytes.size()-65558,-1),-1):
		if bytes.decode_u32(offset) == 0x06054b50 and offset+22+bytes.decode_u16(offset+20) == bytes.size():
			end = offset
			break
	if end < 0 or bytes.decode_u16(end+4) != 0 or bytes.decode_u16(end+6) != 0:
		return _fail("ZIP end directory or disk number is invalid")
	var count := bytes.decode_u16(end+10)
	if count < 1 or count > MAX_FILES or bytes.decode_u16(end+8) != count:
		return _fail("Unsupported ZIP entry count")
	var offset := bytes.decode_u32(end+16)
	if offset + bytes.decode_u32(end+12) != end:
		return _fail("ZIP central directory bounds are invalid")
	var total := 0
	var files: Dictionary = {}
	for index in range(count):
		if offset+46 > end or bytes.decode_u32(offset) != 0x02014b50:
			return _fail("Invalid ZIP entry")
		var flags := bytes.decode_u16(offset+8)
		var method := bytes.decode_u16(offset+10)
		var compressed := bytes.decode_u32(offset+20)
		var decoded := bytes.decode_u32(offset+24)
		var name_length := bytes.decode_u16(offset+28)
		var next := offset+46+name_length+bytes.decode_u16(offset+30)+bytes.decode_u16(offset+32)
		var local := bytes.decode_u32(offset+42)
		if next > end or flags & 1 or method not in [0,8] or decoded > MAX_FILE or compressed > MAX_FILE or bytes.decode_u16(offset+34) != 0:
			return _fail("Unsupported ZIP compression, encryption or entry size")
		var name := bytes.slice(offset+46,offset+46+name_length).get_string_from_utf8()
		if not _safe_path(name) or files.has(name):
			return _fail("Unsafe or duplicate ZIP path")
		if local+30 > offset or bytes.decode_u32(local) != 0x04034b50:
			return _fail("Invalid ZIP local entry")
		var local_name_length := bytes.decode_u16(local+26)
		var data_start := local+30+local_name_length+bytes.decode_u16(local+28)
		if data_start+compressed > offset or bytes.slice(local+30,local+30+local_name_length).get_string_from_utf8() != name:
			return _fail("ZIP local and central entries disagree")
		total += decoded
		if total > MAX_TOTAL:
			return _fail("Decoded pack exceeds 64 MiB")
		files[name] = decoded
		offset = next
	if offset != end or not files.has("blockfield-pack.json") or files["blockfield-pack.json"] > 262144:
		return _fail("Missing or oversized blockfield-pack.json")
	return {"ok":true,"files":files}

static func _read_pack(reader: ZIPReader, files: Dictionary, digest: String) -> Dictionary:
	var manifest = JSON.parse_string(reader.read_file("blockfield-pack.json").get_string_from_utf8())
	if not manifest is Dictionary or manifest.get("version") != 1:
		return _fail("Pack manifest version must be 1")
	for field in ["id","title","license"]:
		if not manifest.get(field) is String or manifest[field].is_empty() or manifest[field].length() > 2000:
			return _fail("Missing pack attribution: " + field)
	if not _safe_path(manifest.id) or "/" in manifest.id or not manifest.get("authors") is Array or manifest.authors.is_empty():
		return _fail("Pack id/authors are invalid")
	for author in manifest.authors:
		if not author is String or author.is_empty() or author.length() > 200:
			return _fail("Invalid pack author")
	if not manifest.get("assets") is Dictionary or manifest.assets.is_empty():
		return _fail("Pack has no resource overrides")
	if manifest.assets.size() > 128 or _packs.size() >= 4 and not _packs.any(func(pack): return pack.id == manifest.id):
		return _fail("At most 128 overrides per pack and four active packs are supported")
	var resources: Dictionary = {}
	var claimed := {"blockfield-pack.json":true}
	var runtime_budget := 0
	for key in manifest.assets:
		if not key is String or not _catalog.has(key):
			return _fail("Unknown original resource target")
		var entry = manifest.assets[key]
		if not entry is Dictionary or not entry.get("file") is String or not entry.get("sha256") is String:
			return _fail("Resource entry requires file and sha256")
		var path: String = entry.file
		var kind: String = _catalog[key].type
		var extension: String = {"model":"glb","texture":"png","sound":"ogg"}[kind]
		if entry.get("type") != kind or not _safe_path(path) or not files.has(path) or path.get_extension().to_lower() != extension:
			return _fail("Resource path/type is invalid: " + key)
		var payload := reader.read_file(path)
		if payload.size() != files[path] or _sha256(payload) != entry.sha256.to_lower():
			return _fail("Resource checksum/size mismatch: " + key)
		var decoded := _decode_resource(payload,kind)
		if not decoded.ok:
			return _fail(key + ": " + decoded.error)
		runtime_budget += decoded.budget
		if runtime_budget > MAX_TOTAL:
			return _fail("Decoded resource memory budget exceeds 64 MiB")
		resources[key] = decoded.resource
		claimed[path] = true
	# Only declared resources and attribution text are accepted, no executable extras.
	for path: String in files:
		if not claimed.has(path) and path.get_extension().to_lower() not in ["txt","md"]:
			return _fail("Undeclared resource or executable entry: " + path)
	var pack := {"id":manifest.id,"title":manifest.title,"authors":manifest.authors,
		"license":manifest.license,"resources":resources,"archive_sha256":digest}
	remove_pack(pack.id)
	_packs.append(pack)
	_generation += 1
	return {"ok":true,"id":pack.id,"resources":resources.size(),"archive_sha256":digest}

static func _decode_resource(bytes: PackedByteArray, kind: String) -> Dictionary:
	if kind == "texture":
		if bytes.size() < 33 or bytes.slice(0,8).hex_encode() != "89504e470d0a1a0a" or bytes.slice(12,16).get_string_from_ascii() != "IHDR":
			return _fail("Expected PNG image")
		var width := _big_endian_u32(bytes,16)
		var height := _big_endian_u32(bytes,20)
		if width < 1 or height < 1 or width > 4096 or height > 4096 or width*height > 4194304:
			return _fail("PNG dimensions exceed 4 megapixels or 4096 per side")
		var image := Image.new()
		if image.load_png_from_buffer(bytes) != OK:
			return _fail("PNG decode failed")
		return {"ok":true,"resource":ImageTexture.create_from_image(image),"budget":width*height*4}
	if kind == "sound":
		if bytes.size() < 32 or bytes.slice(0,4).get_string_from_ascii() != "OggS":
			return _fail("Expected Ogg Vorbis audio")
		var packet := 27 + int(bytes[26])
		if packet+7 > bytes.size() or bytes[packet] != 1 or bytes.slice(packet+1,packet+7).get_string_from_ascii() != "vorbis":
			return _fail("Expected Ogg Vorbis identification packet")
		var audio := AudioStreamOggVorbis.load_from_buffer(bytes)
		if audio == null or audio.get_length() > 60:
			return _fail("Invalid or longer than 60 seconds Ogg Vorbis audio")
		return {"ok":true,"resource":audio,"budget":bytes.size()}
	var valid := _validate_glb(bytes)
	if not valid.ok:
		return valid
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_buffer(bytes,"",state) != OK:
		return _fail("GLB decode failed")
	var node := document.generate_scene(state)
	if node == null or not node is Node3D:
		if node != null: node.free()
		return _fail("GLB did not produce a model")
	var packed := PackedScene.new()
	var result := packed.pack(node)
	node.free()
	return {"ok":true,"resource":packed,"budget":valid.budget} if result == OK else _fail("Cannot store imported model")

static func _big_endian_u32(bytes: PackedByteArray, offset: int) -> int:
	return int(bytes[offset]) << 24 | int(bytes[offset+1]) << 16 | int(bytes[offset+2]) << 8 | int(bytes[offset+3])

static func _integer(value: Variant, maximum: int = MAX_FILE) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0 and float(value) <= maximum and float(value) == floorf(float(value))

static func _validate_glb(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 28 or bytes.decode_u32(0) != 0x46546c67 or bytes.decode_u32(4) != 2 or bytes.decode_u32(8) != bytes.size() or bytes.decode_u32(16) != 0x4e4f534a:
		return _fail("Expected binary GLTF 2 model")
	var json_size := bytes.decode_u32(12)
	if json_size > 1048576 or json_size+28 > bytes.size():
		return _fail("GLB JSON bounds are invalid")
	var description = JSON.parse_string(bytes.slice(20,20+json_size).get_string_from_utf8())
	if not description is Dictionary or not description.get("asset") is Dictionary or description.asset.get("version") != "2.0":
		return _fail("Invalid GLTF description")
	for section in ["buffers","images","nodes","meshes","accessors","bufferViews"]:
		if not description.get(section,[]) is Array:
			return _fail("Invalid GLTF collection: " + section)
	if description.get("buffers",[]).size() != 1:
		return _fail("GLB must have one embedded buffer")
	var bin_offset := 20+json_size
	if bytes.decode_u32(bin_offset+4) != 0x004e4942 or bin_offset+8+bytes.decode_u32(bin_offset) != bytes.size():
		return _fail("GLB must contain one embedded binary chunk")
	var buffer = description.buffers[0]
	if not buffer is Dictionary or not _integer(buffer.get("byteLength")) or buffer.byteLength > bytes.decode_u32(bin_offset):
		return _fail("Invalid GLB buffer byte length")
	if description.has("extensionsRequired") or description.has("animations") or description.has("skins") or description.has("cameras"):
		return _fail("Only static mesh GLBs without required extensions are supported")
	if description.get("nodes",[]).size() > 256 or description.get("meshes",[]).size() > 128 or description.get("accessors",[]).size() > 2048 or description.get("images",[]).size() > 16:
		return _fail("GLB object budget exceeded")
	for section in ["buffers","images"]:
		for item in description.get(section,[]):
			if not item is Dictionary or item.has("uri"):
				return _fail("External GLB resources are forbidden")
	for node in description.get("nodes",[]):
		if not node is Dictionary or node.has("extensions") or node.has("camera") or node.has("skin"):
			return _fail("GLB nodes must contain mesh transforms only")
		for field in ["translation","rotation","scale","matrix"]:
			if node.has(field):
				var length: int = {"translation":3,"rotation":4,"scale":3,"matrix":16}[field]
				if not node[field] is Array or node[field].size() != length:
					return _fail("Invalid GLB transform")
				for value in node[field]:
					if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or absf(float(value)) > 100000:
						return _fail("Non-finite or oversized GLB transform")
	var nodes: Array = description.get("nodes",[])
	var parents := PackedInt32Array()
	parents.resize(nodes.size())
	for node in nodes:
		if not node.get("children",[]) is Array:
			return _fail("Invalid GLB child list")
		if node.has("mesh") and (not _integer(node.mesh,127) or int(node.mesh) >= description.get("meshes",[]).size()):
			return _fail("Invalid GLB mesh index")
		for child in node.get("children",[]):
			if not _integer(child,255) or int(child) >= nodes.size():
				return _fail("Invalid GLB child index")
			parents[int(child)] += 1
			if parents[int(child)] > 1:
				return _fail("GLB node has multiple parents")
	var queue: Array[int] = []
	for index in range(nodes.size()):
		if parents[index] == 0: queue.append(index)
	var cursor := 0
	while cursor < queue.size():
		for child in nodes[queue[cursor]].get("children",[]):
			parents[int(child)] -= 1
			if parents[int(child)] == 0: queue.append(int(child))
		cursor += 1
	if cursor != nodes.size():
		return _fail("GLB node graph contains a cycle")
	var count := 0
	for accessor in description.get("accessors",[]):
		if not accessor is Dictionary or not _integer(accessor.get("count"),750000):
			return _fail("GLB accessor count is invalid")
		count += int(accessor.count)
	if count > 2000000:
		return _fail("GLB geometry budget exceeded")
	for view in description.get("bufferViews",[]):
		if not view is Dictionary or view.get("buffer",-1) != 0 or not _integer(view.get("byteOffset",0)) or not _integer(view.get("byteLength")) or view.get("byteOffset",0)+view.byteLength > bytes.decode_u32(bin_offset):
			return _fail("GLB buffer view is outside embedded data")
	var budget := bytes.size()+count*16
	for image in description.get("images",[]):
		if image.get("mimeType") != "image/png" or not _integer(image.get("bufferView"),2048):
			return _fail("GLB images must be embedded PNGs")
		var index := int(image.bufferView)
		var views: Array = description.get("bufferViews",[])
		if index < 0 or index >= views.size():
			return _fail("GLB image view is invalid")
		var view: Dictionary = views[index]
		var start := bin_offset+8+int(view.get("byteOffset",0))
		var decoded := _decode_resource(bytes.slice(start,start+int(view.byteLength)),"texture")
		if not decoded.ok:
			return _fail("GLB embedded image exceeds texture limits")
		budget += decoded.budget
	return {"ok":true,"budget":budget}

static func register_skin(id: String, first_person: Callable, third_person: Callable) -> Dictionary:
	# This API is available only to code already compiled into the trusted project.
	if not _safe_path(id) or "/" in id or id == "original" or not first_person.is_valid() or not third_person.is_valid():
		return _fail("Invalid trusted skin factory")
	_factories[id] = {"first":first_person,"third":third_person}
	return {"ok":true}

static func get_skins() -> PackedStringArray:
	var result := PackedStringArray(["original"])
	for id in _factories: result.append(id)
	return result

static func create_first_person_skin(id: String = "original", context: Dictionary = {}) -> Node3D:
	return _create_skin(id,"first",context)

static func create_third_person_skin(id: String = "original", context: Dictionary = {}) -> Node3D:
	return _create_skin(id,"third",context)

static func _create_skin(id: String, view: String, context: Dictionary) -> Node3D:
	var node: Node3D
	if id == "original":
		var script: Script = load("res://presentation/" + ("weapon_view.gd" if view == "first" else "character_view.gd"))
		node = script.new() as Node3D
	elif _factories.has(id):
		var result = _factories[id][view].call(context.duplicate(true))
		if not result is Node3D:
			if result is Node: result.free()
			push_error("Skin factory must return a Node3D")
			return null
		node = result
	else:
		push_error("Unknown skin factory: " + id)
		return null
	for method in (FIRST_METHODS if view == "first" else THIRD_METHODS):
		if not node.has_method(method):
			node.free()
			push_error("Skin is missing method: " + method)
			return null
	if node.get_parent() != null:
		push_error("Skin factory must return an unattached node")
		return null
	return node
