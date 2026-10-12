class_name ArsenalView
extends Node3D
## Authored equipment and authority-owned effect geometry. No damage, clocks,
## collisions or particle emission; the ordinary effects pool remains separate.
const VIEW_LAYER: int = 1 << 18
const STATE_CAP: int = 64
const EVENT_CAP: int = 12
const DARK: Color = Color("263648")
const STEEL: Color = Color("adc0ca")
const COLORS: Array[Color] = [Color("efbc53"), Color("da8d56"), Color("76e1f3"), Color("ff704f"), Color("8ac8ff"), Color("ec9faa"), Color("edcf4f"), Color("b996fa"), Color("81dec6"), Color("be9ee9"), Color("e17666"), Color("e0be7e"), Color("bc8ef9"), Color("f37de5"), Color("eada55"), Color("fff18b"), Color("67dcff"), Color("d1a472"), Color("90dbc6"), Color("ffb078")]
static var _meshes: Dictionary[String, ArrayMesh] = {}
static var _material: StandardMaterial3D
static var _danger_material: StandardMaterial3D
var _built: bool = false
var _camera: Camera3D
var _rig: Node3D
var _held: MeshInstance3D
var _states: Array[MeshInstance3D] = []
var _events: Array[MeshInstance3D] = []
var _slot_ids: Array[String] = []
var _selected: String = "source"
var _readout: Dictionary = {}
var _pulse: float = 0.0
var _world_count: int = 0
var _event_count: int = 0

func _ready() -> void:
	_ensure_built()

func configure(camera: Camera3D) -> void:
	_ensure_built()
	_camera = camera
	if is_instance_valid(camera): camera.cull_mask |= VIEW_LAYER
	_update_pose()

func update_readout(readout: Dictionary, delta: float) -> void:
	_ensure_built()
	_readout = readout.duplicate(true)
	var selected: String = str(readout.get("selected_item", "source"))
	if selected != _selected:
		_selected = selected
		_held.mesh = _item_mesh(selected) if _valid_item(selected) else null
		_pulse = 0.0
	# Only cosmetic interpolation advances with render delta. Charge/heat/ammo
	# come from readout, and world geometry remains unchanged until present().
	_pulse = move_toward(_pulse, 0.0, maxf(delta, 0.0) * 4.0)
	_held.visible = _valid_item(_selected) and bool(readout.get("enabled", true)) and bool(readout.get("first_person", false))
	_update_pose()

func present(events: Array[Dictionary], states: Array[Dictionary]) -> void:
	_ensure_built()
	var seen: Array[String] = []
	# Sort only copied references: authority order and dictionaries stay intact.
	# Keep danger telegraphs even if a malformed/oversized batch exceeds capacity.
	var ordered_states: Array[Dictionary] = states.duplicate()
	ordered_states.sort_custom(_state_before)
	var admitted: Array[Dictionary] = []
	for record: Dictionary in ordered_states:
		if admitted.size() >= STATE_CAP: break
		if _valid_record(record) and not str(record.get("id", "")).is_empty(): admitted.append(record)
	var admitted_ids: Array[String] = []
	for record: Dictionary in admitted: admitted_ids.append(str(record.id))
	for index: int in STATE_CAP:
		if not _slot_ids[index] in admitted_ids:
			_states[index].hide()
			_slot_ids[index] = ""
	_world_count = 0
	for record: Dictionary in admitted:
		if _world_count >= STATE_CAP: break
		if not _valid_record(record): continue
		var identity: String = str(record.get("id", ""))
		if identity.is_empty() or identity in seen: continue
		seen.append(identity)
		var slot: int = _slot_ids.find(identity)
		if slot < 0:
			for index: int in STATE_CAP:
				if _slot_ids[index].is_empty():
					slot = index
					break
		if slot < 0: continue
		_slot_ids[slot] = identity
		_render_record(_states[slot], record, false)
		_world_count += 1
	for index: int in STATE_CAP:
		if not _slot_ids[index] in seen:
			_states[index].hide()
			_slot_ids[index] = ""
	for mesh: MeshInstance3D in _events: mesh.hide()
	_event_count = 0
	var ordered_events: Array[Dictionary] = events.duplicate()
	ordered_events.sort_custom(_event_before)
	for record: Dictionary in ordered_events:
		var kind: String = str(record.get("type", record.get("kind", "")))
		if kind == "fired":
			if str(record.get("item", "")) == _selected: _pulse = 1.0
			continue
		if kind not in ["beam", "chain", "impact", "explosion", "warning", "jet", "strike", "status", "shatter", "hit"]: continue
		if _event_count >= EVENT_CAP: break
		if not _valid_record(record): continue
		_render_record(_events[_event_count], record, true)
		_event_count += 1
	_update_pose()

func _state_before(first: Dictionary, second: Dictionary) -> bool:
	var left: int = _state_priority(first)
	var right: int = _state_priority(second)
	return left > right if left != right else str(first.get("id", "")) < str(second.get("id", ""))

func _state_priority(record: Dictionary) -> int:
	if bool(record.get("warning", false)) or str(record.get("kind", "")).contains("warning"): return 3
	if str(record.get("kind", "")) in ["fire", "blackhole", "lure", "charge", "mine", "turret", "jet"]: return 2
	return 1

func _event_before(first: Dictionary, second: Dictionary) -> bool:
	var left: int = _event_priority(first)
	var right: int = _event_priority(second)
	return left > right if left != right else str(first.get("id", "")) < str(second.get("id", ""))

func _event_priority(record: Dictionary) -> int:
	var kind: String = str(record.get("type", record.get("kind", "")))
	if kind == "warning" or bool(record.get("warning", false)): return 4
	if kind in ["explosion", "strike", "piano", "shatter", "jet"]: return 3
	if kind in ["beam", "chain"]: return 2
	return 1

func clear() -> void:
	_ensure_built()
	for mesh: MeshInstance3D in _states + _events: mesh.hide()
	_slot_ids.fill("")
	_held.hide()
	_selected = "source"
	_readout.clear()
	_pulse = 0.0
	_world_count = 0
	_event_count = 0

func get_display_state() -> Dictionary:
	return {"selected_item": _selected, "held_visible": _held.visible if _built else false,
		"state_count": _world_count, "event_count": _event_count,
		"state_cap": STATE_CAP, "event_cap": EVENT_CAP, "particle_count": 0}

func _ensure_built() -> void:
	if _built: return
	_built = true
	_rig = Node3D.new()
	_rig.name = "AuthoredArsenalRig"
	add_child(_rig)
	_rig.top_level = true
	_held = _mesh_node("HeldArsenal", _rig)
	_held.layers = VIEW_LAYER
	_held.hide()
	for index: int in STATE_CAP:
		_states.append(_mesh_node("ArsenalState%02d" % index, self))
		_slot_ids.append("")
	for index: int in EVENT_CAP: _events.append(_mesh_node("ArsenalEvent%02d" % index, self))

func _mesh_node(label: String, parent: Node3D) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	node.material_override = _shared_material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	node.hide()
	return node

func _update_pose() -> void:
	if not _built or not is_instance_valid(_camera): return
	var charge: float = clampf(float(_readout.get("charge", 0.0)), 0.0, 1.0)
	var pose: Transform3D = Transform3D(Basis.from_euler(Vector3(-_pulse * 0.10, 0.0, charge * -0.08)), Vector3(.25, -.24, -.48 + _pulse * .05))
	_rig.global_transform = _camera.global_transform * pose
	_held.scale = Vector3.ONE * (.92 + charge * .04)

func _valid_item(id: String) -> bool:
	return id.length() == 3 and id.begins_with("x") and id.substr(1).is_valid_int() and int(id.substr(1)) in range(1, 21)

func _valid_record(record: Dictionary) -> bool:
	var position_value: Variant = record.get("position", record.get("from", null))
	return position_value is Vector3 and (position_value as Vector3).is_finite() and _valid_item(str(record.get("item", "")))

func _has_identity(records: Array[Dictionary], identity: String) -> bool:
	for record: Dictionary in records:
		if str(record.get("id", "")) == identity and _valid_record(record): return true
	return false

func _render_record(node: MeshInstance3D, record: Dictionary, event: bool) -> void:
	var item: String = str(record.item)
	var kind: String = str(record.get("type", record.get("kind", "projectile"))) if event else str(record.get("kind", "projectile"))
	if bool(record.get("warning", false)): kind = "warning"
	node.material_override = _warning_material() if kind.contains("warning") else _shared_material()
	var point: Vector3 = record.get("position", record.get("from", Vector3.ZERO))
	var direction_value: Variant = record.get("direction", Vector3.FORWARD)
	var direction: Vector3 = direction_value if direction_value is Vector3 and direction_value.is_finite() else Vector3.FORWARD
	if direction.length_squared() < .0001: direction = Vector3.FORWARD
	var radius: float = float(record.get("radius", .35))
	if not is_finite(radius): radius = .35
	radius = clampf(radius, .08, 12.0)
	node.transform = Transform3D.IDENTITY
	node.position = point
	if kind in ["beam", "chain", "jet"]:
		var end_value: Variant = record.get("end_position", record.get("end", record.get("to", point + direction * 3.0)))
		var finish: Vector3 = end_value if end_value is Vector3 and end_value.is_finite() else point + direction * 3.0
		var length: float = minf(point.distance_to(finish), 64.0)
		if length < .001:
			node.hide()
			return
		node.mesh = _effect_mesh("beam", item)
		node.position = (point + finish) * .5
		node.basis = Basis.looking_at((finish - point).normalized(), Vector3.UP if absf((finish - point).normalized().y) < .99 else Vector3.RIGHT)
		node.scale = Vector3(1, 1, length)
	elif kind in ["field", "warning", "singularity", "blackhole", "fire", "lure", "strike_warning"]:
		node.mesh = _effect_mesh("warning" if kind.contains("warning") else "field", item)
		node.scale = Vector3(radius, 1, radius)
	elif kind in ["explosion", "impact", "status", "shatter", "hit"]:
		node.mesh = _effect_mesh("impact", item)
		node.scale = Vector3.ONE * minf(radius, 3.0)
	else:
		node.mesh = _projectile_mesh(item) if kind in ["brick", "saw", "rocket", "popcorn", "pop", "projectile"] else _item_mesh(item)
		node.basis = Basis.looking_at(direction.normalized(), Vector3.UP if absf(direction.normalized().y) < .99 else Vector3.RIGHT)
		node.scale = Vector3.ONE * (3.0 if item == "x18" else (2.0 if item == "x19" else .85))
		if item == "x06": node.rotate_object_local(Vector3.BACK, clampf(float(record.get("progress", 0.0)), 0, 1) * TAU * 4)
	node.show()

static func _shared_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _material

static func _warning_material() -> StandardMaterial3D:
	if _danger_material == null:
		_danger_material = _shared_material().duplicate() as StandardMaterial3D
		# Thin warning lines remain visible when a target lies inside its voxel
		# surface. This changes no collision, aim or authoritative danger radius.
		_danger_material.no_depth_test = true
	return _danger_material

static func _item_mesh(item: String) -> ArrayMesh:
	if _meshes.has(item): return _meshes[item]
	var number: int = clampi(int(item.substr(1)), 1, 20)
	var accent: Color = COLORS[number - 1]
	var pieces: Array[Dictionary] = []
	# Each item is a single baked mesh. Shared grips do not erase its silhouette.
	if number <= 9:
		pieces.append(_box(Vector3(0, -.11, .04), Vector3(.075, .18, .085), DARK, Vector3(-.18, 0, 0)))
	match number:
		1:
			pieces.append(_box(Vector3.ZERO, Vector3(.15, .12, .48), DARK))
			for index: int in 5: pieces.append(_box(Vector3(0, 0, -.09 - index * .065), Vector3(.21, .035, .025), accent))
			pieces.append(_box(Vector3(0, .085, -.04), Vector3(.055, .05, .15), STEEL))
		2:
			pieces.append(_box(Vector3.ZERO, Vector3(.25, .20, .27), accent))
			pieces.append(_box(Vector3(0, .12, -.08), Vector3(.23, .12, .19), STEEL))
			pieces.append(_box(Vector3(0, 0, -.27), Vector3(.21, .16, .16), DARK))
		3:
			pieces.append(_box(Vector3.ZERO, Vector3(.16, .09, .32), DARK))
			for side: float in [-1.0, 1.0]:
				pieces.append(_box(Vector3(side * .10, .08, -.13), Vector3(.025, .13, .23), accent))
			pieces.append(_box(Vector3(0, 0, -.27), Vector3(.06, .06, .16), STEEL))
		4:
			pieces.append(_box(Vector3.ZERO, Vector3(.15, .14, .34), DARK))
			pieces.append(_box(Vector3(0, -.13, -.08), Vector3(.18, .17, .16), accent))
			pieces.append(_box(Vector3(0, 0, -.31), Vector3(.22, .09, .16), STEEL))
		5:
			pieces.append(_box(Vector3.ZERO, Vector3(.12, .17, .29), STEEL))
			for side: float in [-1.0, 1.0]: pieces.append(_box(Vector3(side * .10, 0, .04), Vector3(.09, .19, .18), accent))
			pieces.append(_box(Vector3(0, 0, -.25), Vector3(.12, .12, .19), DARK))
		6:
			for index: int in 12:
				var angle: float = TAU * float(index) / 12.0
				pieces.append(_box(Vector3(cos(angle) * .14, sin(angle) * .14, -.12), Vector3(.085, .045, .035), STEEL, Vector3(0, 0, angle)))
			pieces.append(_box(Vector3(0, 0, -.12), Vector3(.17, .17, .045), accent))
			pieces.append(_box(Vector3(0, -.06, .05), Vector3(.12, .09, .27), DARK))
		7:
			pieces.append(_box(Vector3.ZERO, Vector3(.18, .11, .27), DARK))
			for side: float in [-1.0, 0.0, 1.0]: pieces.append(_box(Vector3(side * .10, .04, -.19), Vector3(.075, .075, .30), accent))
			pieces.append(_box(Vector3(.11, .14, .01), Vector3(.025, .16, .025), STEEL))
		8:
			pieces.append(_box(Vector3.ZERO, Vector3(.25, .20, .26), accent))
			pieces.append(_box(Vector3(0, 0, -.23), Vector3(.31, .25, .15), DARK))
			pieces.append(_box(Vector3(.17, .01, .10), Vector3(.025, .025, .30), STEEL, Vector3(0, -.55, 0)))
		9:
			pieces.append(_box(Vector3.ZERO, Vector3(.14, .12, .30), STEEL))
			for side: float in [-1.0, 1.0]: pieces.append(_box(Vector3(side * .09, .035, .06), Vector3(.08, .20, .13), accent))
			pieces.append(_box(Vector3(0, 0, -.21), Vector3(.10, .08, .14), accent))
		10:
			pieces.append(_box(Vector3(0, -.16, .02), Vector3(.055, .40, .055), STEEL))
			pieces.append(_box(Vector3(0, .09, -.02), Vector3(.33, .17, .18), DARK))
			for side: float in [-1.0, 1.0]: pieces.append(_box(Vector3(side * .18, .09, -.02), Vector3(.055, .20, .20), accent))
		11:
			pieces.append(_box(Vector3.ZERO, Vector3(.25, .07, .19), accent))
			pieces.append(_box(Vector3(0, .06, 0), Vector3(.10, .05, .11), DARK))
		12:
			pieces.append(_box(Vector3.ZERO, Vector3(.15, .20, .15), accent))
			for index: int in 3: pieces.append(_box(Vector3((index - 1) * .065, .14, -.01), Vector3(.07, .07, .07), Color("fff0be")))
		13:
			pieces.append(_box(Vector3.ZERO, Vector3(.13, .13, .13), Color("683ba6")))
			for index: int in 4: pieces.append(_box(Vector3.ZERO, Vector3(.23, .025, .025), accent, Vector3(0, index * PI / 4, index * PI / 4)))
		14:
			for column: int in 3:
				for row: int in 3: pieces.append(_box(Vector3((column - 1) * .055, (row - 1) * .055, 0), Vector3(.048, .048, .15), COLORS[(column * 3 + row) % 20]))
		15:
			for index: int in 5: pieces.append(_box(Vector3((index - 2) * .055, pow(float(index - 2), 2) * .015, 0), Vector3(.065, .06, .065), accent, Vector3(0, 0, (index - 2) * .2)))
		16:
			pieces.append(_box(Vector3.ZERO, Vector3(.15, .15, .26), accent))
			pieces.append(_box(Vector3(0, .11, 0), Vector3(.10, .065, .07), DARK))
			for side: float in [-1.0, 1.0]: pieces.append(_box(Vector3(side * .12, 0, .11), Vector3(.10, .03, .11), STEEL))
		17:
			pieces.append(_box(Vector3.ZERO, Vector3(.15, .065, .21), DARK))
			pieces.append(_box(Vector3(0, .065, -.035), Vector3(.09, .05, .11), accent))
			pieces.append(_box(Vector3(.085, .13, .05), Vector3(.025, .20, .025), STEEL))
		18:
			pieces.append(_box(Vector3.ZERO, Vector3(.40, .23, .22), Color("473127")))
			pieces.append(_box(Vector3(0, .13, -.03), Vector3(.41, .025, .24), accent))
			for index: int in 8: pieces.append(_box(Vector3((index - 3.5) * .045, .005, -.14), Vector3(.039, .025, .08), Color.WHITE if index % 3 else DARK))
		19:
			pieces.append(_box(Vector3(0, -.05, .01), Vector3(.28, .12, .19), DARK))
			pieces.append(_box(Vector3(0, .10, -.05), Vector3(.15, .11, .18), accent))
			pieces.append(_box(Vector3(0, .10, -.20), Vector3(.06, .06, .20), STEEL))
			for side: float in [-1.0, 1.0]: pieces.append(_box(Vector3(side * .13, -.13, .02), Vector3(.025, .12, .16), STEEL))
		20:
			pieces.append(_box(Vector3.ZERO, Vector3(.09, .25, .20), DARK))
			for side: float in [-1.0, 1.0]:
				pieces.append(_box(Vector3(side * .11, 0, .02), Vector3(.10, .26, .14), STEEL))
				pieces.append(_box(Vector3(side * .11, -.17, .02), Vector3(.065, .09, .065), accent))
		_:
			pieces.append(_box(Vector3.ZERO, Vector3(.15, .15, .15), accent))
	_meshes[item] = _bake(pieces)
	return _meshes[item]

static func _effect_mesh(kind: String, item: String) -> ArrayMesh:
	var key: String = kind + item
	if _meshes.has(key): return _meshes[key]
	var accent: Color = COLORS[clampi(int(item.substr(1)) - 1, 0, 19)]
	var pieces: Array[Dictionary] = []
	if kind == "beam":
		pieces.append(_box(Vector3.ZERO, Vector3(.035, .035, 1.0), accent))
	else:
		for index: int in 20:
			var angle: float = TAU * float(index) / 20.0
			pieces.append(_box(Vector3(cos(angle), .04, sin(angle)), Vector3(.055, .045, .30), accent, Vector3(0, -angle, 0)))
		if kind == "warning": pieces.append(_box(Vector3(0, .45, 0), Vector3(.055, .90, .055), accent))
		if kind == "field" and item == "x04":
			for index: int in 5: pieces.append(_box(Vector3((index - 2) * .23, .18, 0), Vector3(.08, .32, .08), accent, Vector3(0, 0, (index - 2) * .15)))
		if kind == "field" and item == "x13":
			pieces.append(_box(Vector3(0, .3, 0), Vector3(.18, .18, .18), Color("683ba6")))
			for index: int in 8:
				var angle: float = TAU * float(index) / 8.0
				pieces.append(_box(Vector3(cos(angle) * .4, .3, sin(angle) * .4), Vector3(.1, .045, .24), accent, Vector3(0, -angle, 0)))
		if kind == "field" and item == "x14":
			for index: int in 6: pieces.append(_box(Vector3(cos(index * TAU / 6) * .15, .28, sin(index * TAU / 6) * .15), Vector3(.11, .16, .11), COLORS[index]))
		if kind == "impact":
			for axis: Vector3 in [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]: pieces.append(_box(Vector3.ZERO, Vector3.ONE * .065 + axis * 1.3, accent))
	_meshes[key] = _bake(pieces)
	return _meshes[key]

static func _projectile_mesh(item: String) -> ArrayMesh:
	if item not in ["x02", "x06", "x07", "x12"]: return _item_mesh(item)
	var key: String = "projectile" + item
	if _meshes.has(key): return _meshes[key]
	var accent: Color = COLORS[int(item.substr(1)) - 1]
	var pieces: Array[Dictionary] = []
	match item:
		"x02":
			pieces.append(_box(Vector3.ZERO, Vector3(.22, .20, .24), accent))
			pieces.append(_box(Vector3(0, .105, 0), Vector3(.08, .015, .25), STEEL))
		"x06":
			pieces.append(_box(Vector3.ZERO, Vector3(.16, .16, .03), accent))
			for index: int in 12:
				var angle: float = TAU * index / 12.0
				pieces.append(_box(Vector3(cos(angle) * .13, sin(angle) * .13, 0), Vector3(.075, .04, .03), STEEL, Vector3(0, 0, angle)))
		"x07":
			pieces.append(_box(Vector3.ZERO, Vector3(.055, .045, .16), accent))
			pieces.append(_box(Vector3(0, 0, .03), Vector3(.058, .048, .028), DARK))
			for side: float in [-1.0, 1.0]:
				pieces.append(_box(Vector3(side * .07, .025, 0), Vector3(.095, .018, .055), STEEL, Vector3(0, side * .2, 0)))
				pieces.append(_box(Vector3(side * .025, .035, -.09), Vector3(.008, .045, .008), DARK))
		"x12":
			pieces.append(_box(Vector3.ZERO, Vector3(.075, .075, .075), accent))
			pieces.append(_box(Vector3(.02, .04, .01), Vector3(.06, .05, .06), Color("fff0be")))
	_meshes[key] = _bake(pieces)
	return _meshes[key]

static func _box(point: Vector3, dimensions: Vector3, color: Color, angles: Vector3 = Vector3.ZERO) -> Dictionary:
	return {"position": point, "size": dimensions, "color": color, "rotation": angles}

static func _bake(pieces: Array[Dictionary]) -> ArrayMesh:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var normals: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	var corners: Array[Vector3] = [Vector3(-1,-1,-1), Vector3(1,-1,-1), Vector3(1,1,-1), Vector3(-1,1,-1), Vector3(-1,-1,1), Vector3(1,-1,1), Vector3(1,1,1), Vector3(-1,1,1)]
	var faces: Array[PackedInt32Array] = [PackedInt32Array([1,5,6,2]), PackedInt32Array([4,0,3,7]), PackedInt32Array([3,2,6,7]), PackedInt32Array([4,5,1,0]), PackedInt32Array([5,4,7,6]), PackedInt32Array([0,1,2,3])]
	for piece: Dictionary in pieces:
		var basis: Basis = Basis.from_euler(piece.rotation)
		for face: int in 6:
			for index: int in [0,1,2,0,2,3]:
				tool.set_color(piece.color)
				tool.set_normal(basis * normals[face])
				tool.add_vertex(piece.position + basis * (corners[faces[face][index]] * piece.size * .5))
	return tool.commit()
