class_name LabBuildCursor
extends Node3D
## Source: Client::DrawBlockCursor. Outline cells use the real placement validator.
var player: BlockfieldPlayer
var enabled:=true
var preview: Dictionary={"cells":[],"valid":false,"reason":"","pending":false}
var _mesh: ImmediateMesh
var _material: StandardMaterial3D
var _cells: Array[MeshInstance3D]=[]

func setup(local_player: BlockfieldPlayer) -> void:
	player=local_player
	_material=StandardMaterial3D.new()
	_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test=false
	_mesh=ImmediateMesh.new()
	var corners: Array[Vector3]=[]
	for index in 8:corners.append(Vector3(index&1,(index>>1)&1,(index>>2)&1))
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for index in 8:
		for axis in [1,2,4]:
			if (index&axis)==0:
				_mesh.surface_add_vertex(corners[index])
				_mesh.surface_add_vertex(corners[index|axis])
	_mesh.surface_end()

func _process(_delta: float) -> void:
	if player==null:return
	preview=player.get_build_preview()
	var positions: Array=preview.get("cells",[])
	while _cells.size()<mini(positions.size(),50):
		var cell:=MeshInstance3D.new()
		cell.mesh=_mesh
		cell.material_override=_material
		cell.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cell)
		_cells.append(cell)
	_material.albedo_color=Color(1,.7,.2,.8) if bool(preview.get("pending",false)) else (Color(.6,1,.65,.85) if bool(preview.get("valid",false)) else Color(1,.3,.25,.85))
	for index in _cells.size():
		_cells[index].visible=enabled and index<positions.size()
		if index<positions.size():_cells[index].global_position=Vector3(positions[index])
