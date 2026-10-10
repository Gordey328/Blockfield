class_name WeaponView
extends Node3D
## First-person original parts and skin animation stages, in camera-local space.
## Source: Resources/Scripts/Skin/*/View.as and ClientPlayer.cpp view-arm IK.

const MODELS = preload("res://presentation/openspades_models.gd")
const WEAPONS := ["Rifle", "SMG", "Shotgun"]
const VIEW_SCALE := 0.033
const RELOAD_SECONDS := [2.5, 2.5, 0.5]

var _built := false
var _tool := 2
var _weapon := 0
var _rig: Node3D
var _parts: Dictionary = {}
var _forearms: Array[Node3D] = []
var _upperarms: Array[Node3D] = []
var _team_color := Color(0.18, 0.42, 0.86)
var _block_color := Color(0.60, 0.46, 0.32)
var _aim := 0.0
var _sprint := 0.0
var _raise := 1.0
var _vibration := 0.0
var _time := 0.0
var _fire_elapsed := 1000.0
var _reloading := false
var _reload_elapsed := 0.0
var _reload_progress := 0.0
var _last_external_reload := 0.0
var _cook_time := 0.0
var _digging := false
var _dig_progress := 0.0
var _ammo := 10
var _clip_size := 10
var _left_hand := Vector3.ZERO
var _right_hand := Vector3.ZERO

func _ready() -> void:
	_ensure_built()

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_rig = Node3D.new()
	_rig.name = "OriginalViewEquipment"
	add_child(_rig)
	for side in range(2):
		var forearm: Node3D = MODELS.create("Player/Arm", true)
		var upperarm: Node3D = MODELS.create("Player/UpperArm", true)
		forearm.name = "Forearm" + str(side)
		upperarm.name = "UpperArm" + str(side)
		add_child(forearm)
		add_child(upperarm)
		_forearms.append(forearm)
		_upperarms.append(upperarm)
		MODELS.set_tint(forearm, _team_color)
		MODELS.set_tint(upperarm, _team_color)
	_rebuild_parts()
	update_pose(0.0, false, false, false, 0.0)

func set_selection(tool: int, weapon: int) -> void:
	_ensure_built()
	tool = clampi(tool, 0, 3)
	weapon = clampi(weapon, 0, 2)
	if _tool == tool and _weapon == weapon:
		return
	_tool = tool
	_weapon = weapon
	_clip_size = [10, 30, 6][_weapon]
	_ammo = _clip_size
	_raise = 0.0
	_aim = 0.0
	_cook_time = 0.0
	_fire_elapsed = 1000.0
	_vibration = 0.0
	_digging = false
	_reloading = false
	_rebuild_parts()

func set_team(index: int, color: Color = Color(-1, -1, -1, 1)) -> void:
	_ensure_built()
	var next_color: Color = MODELS.TEAM_COLORS[clampi(index, 0, 1)] if color.r < 0 else color
	if next_color == _team_color:
		return
	_team_color = next_color
	for side in range(2):
		MODELS.set_tint(_forearms[side], _team_color)
		MODELS.set_tint(_upperarms[side], _team_color)

func set_block_color(color: Color) -> void:
	_ensure_built()
	_block_color = color
	if _tool == 1:
		MODELS.set_tint(_rig, _block_color)

func set_ammo(ammo: int, clip_size: int) -> void:
	_ammo = ammo
	_clip_size = clip_size

func set_grenade_cook(seconds: float) -> void:
	_cook_time = maxf(seconds, 0.0)

func set_spade_action(digging: bool, progress: float = 0.0) -> void:
	_digging = digging
	_dig_progress = clampf(progress, 0.0, 1.0)

func fire() -> void:
	_vibration = 1.0
	_fire_elapsed = 0.0
	_cook_time = 0.0

func reload() -> void:
	_reloading = true
	_reload_elapsed = 0.0
	_reload_progress = 0.0
	_last_external_reload = 0.0

func cancel_reload() -> void:
	_reloading = false
	_reload_progress = 0.0
	_last_external_reload = 0.0

func reload_completed() -> void:
	cancel_reload()
	if _weapon == 2:
		_fire_elapsed = 0.05

func update_pose(delta: float, aiming: bool, sprinting: bool, crouching: bool,
		speed: float, reload_progress: float = 0.0) -> void:
	_ensure_built()
	_time += delta
	_fire_elapsed += delta
	_vibration = maxf(_vibration - delta * 10.0, 0.0)
	_raise = minf(_raise + delta * 4.0, 1.0)
	_aim = move_toward(_aim, 1.0 if aiming and _tool == 2 and not sprinting else 0.0, delta * 5.0)
	var sprint_target := 1.0 if sprinting else 0.0
	if sprint_target > _sprint:
		_sprint += (sprint_target - _sprint) * (1.0 - pow(0.001, delta))
	else:
		_sprint = sprint_target
	_update_reload(delta, reload_progress)
	var motion := clampf(absf(speed) / 6.0, 0.0, 1.0) * (0.8 if crouching else 1.0)
	var swing := Vector3(sin(_time * TAU * 1.6) * 0.02 * motion,
		0, absf(cos(_time * TAU * 1.6)) * 0.015 * motion)
	if _tool == 2:
		_update_gun(swing)
	else:
		_update_tool(swing)
	_update_view_arms()

func _update_reload(delta: float, external_progress: float) -> void:
	if external_progress > 0.0:
		_reloading = external_progress < 1.0
		_reload_progress = clampf(external_progress, 0.0, 1.0)
		_reload_elapsed = _reload_progress * float(RELOAD_SECONDS[_weapon])
		_last_external_reload = external_progress
	elif _last_external_reload > 0.9:
		reload_completed()
	elif _reloading:
		_reload_elapsed += delta
		_reload_progress = clampf(_reload_elapsed / float(RELOAD_SECONDS[_weapon]), 0.0, 1.0)
		if _reload_progress >= 1.0:
			reload_completed()

func _rebuild_parts() -> void:
	for child in _rig.get_children():
		if child is Node3D:
			(child as Node3D).hide()
		child.queue_free()
	_parts.clear()
	if _tool == 2:
		var group: String = "Weapons/" + WEAPONS[_weapon] + "/"
		if _weapon == 0:
			_add_part("body", group + "WeaponNoMagazine", 0.5, Vector3(-0.25, 0, 0))
			_add_part("rear_sight", group + "Sight1", 0.025, Vector3(0.0125, -8, -4.5))
			_add_part("front_sight", group + "Sight2", 0.05, Vector3(0.025, 16, -4.575))
			_add_part("magazine", group + "Magazine", 1, Vector3(0, 1, 1))
		elif _weapon == 1:
			_add_part("body", group + "WeaponNoMagazine")
			_add_part("front_sight", group + "Sight1", 0.1, Vector3(0.05, 5, -4.85))
			_add_part("front_pin", group + "Sight3", 0.05, Vector3(0.025, 5, -4.875))
			_add_part("rear_sight", group + "Sight2", 0.08, Vector3(0.04, -9, -4.9))
			_add_part("magazine", group + "Magazine", 1, Vector3(0, 3, 1))
		else:
			_add_part("body", group + "WeaponNoPump")
			_add_part("rear_sight", group + "Sight2", 0.05, Vector3(0.025, -9, -4.4))
			_add_part("front_sight", group + "Sight1", 0.05, Vector3(0.025, 8.5, -4.4))
			_add_part("pump", group + "Pump")
	else:
		var path: String = "Weapons/Spade/Spade"
		if _tool == 1:
			path = "Weapons/Block/Block2"
		elif _tool == 3:
			path = "Weapons/Grenade/Grenade"
		_add_part("body", path)
		if _tool == 1:
			MODELS.set_tint(_rig, _block_color)

func _add_part(key: String, path: String, scalar: float = 1.0, source_offset: Vector3 = Vector3.ZERO) -> void:
	var model: Node3D = MODELS.create(path, true)
	model.name = key
	model.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scalar), MODELS.source_vector(source_offset))
	_rig.add_child(model)
	_parts[key] = model

func _rotate_before(matrix: Transform3D, axis: Vector3, angle: float) -> Transform3D:
	return Transform3D(MODELS.source_rotation(axis, angle), Vector3.ZERO) * matrix

func _basic_matrix(swing: Vector3) -> Transform3D:
	var matrix := Transform3D.IDENTITY
	if _sprint > 0:
		matrix = _rotate_before(matrix, Vector3(0, 1, 0), _sprint * -0.1)
		matrix = _rotate_before(matrix, Vector3.RIGHT, _sprint * 0.3)
		matrix = _rotate_before(matrix, Vector3(0, 0, 1), _sprint * -0.55)
		matrix = MODELS.source_translation(Vector3(0.23, -0.05, 0.15) * _sprint) * matrix
	var put_down := 1.0 - _raise
	matrix = _rotate_before(matrix, Vector3(0, 0, 1), put_down * -1.3)
	matrix = _rotate_before(matrix, Vector3(0, 1, 0), put_down * 0.2)
	matrix = MODELS.source_translation(Vector3(0.1, -0.3, 0.1) * put_down) * matrix
	var aim_amount := smoothstep(0.0, 1.0, _aim)
	var gain := 1.0 - aim_amount * 0.4
	var offsets := [0.052, 0.038, 0.0535]
	var z_position: float = 0.2 - aim_amount * float(offsets[_weapon])
	var vib := _vibration
	var hip := Vector3(sin(vib * TAU) * 0.008, vib * (vib - 1.0) * 0.14, vib * (1.0 - vib) * 0.03) * gain
	var ads := Vector3(0, vib * (vib - 1.0) * vib * 0.3, 0) * gain
	var offset := Vector3(-0.13 * (1.0 - aim_amount), 0.5, z_position)
	offset += swing * gain + hip.lerp(ads, aim_amount)
	matrix = MODELS.source_translation(offset) * matrix
	return matrix.scaled_local(Vector3.ONE * VIEW_SCALE)

func _align_sight(matrix: Transform3D, source_point: Vector3) -> Transform3D:
	var fade := clampf((smoothstep(0.0, 1.0, _aim) - 0.8) / 0.2, 0, 1)
	if fade <= 0:
		return matrix
	var point: Vector3 = MODELS.SOURCE_AXES.inverse() * (matrix * MODELS.source_vector(source_point))
	if absf(point.y) > 0.0001:
		matrix = _rotate_before(matrix, Vector3(0, 0, 1), atan(point.x / point.y) * fade)
		matrix = _rotate_before(matrix, Vector3(-1, 0, 0), atan(point.z / point.y) * fade)
	return matrix

func _update_gun(swing: Vector3) -> void:
	var matrix := _basic_matrix(swing)
	var points := [Vector3(0, 16, -4.6), Vector3(0, 5, -4.9), Vector3(0, 8.5, -4.4)]
	_rig.transform = _align_sight(matrix, points[_weapon])
	_rig.visible = true
	_left_hand = _hand_point(Vector3(1, 6, 1))
	_right_hand = _hand_point(Vector3(0, -8, 4 if _weapon == 1 else 2))
	match _weapon:
		0: _rifle_reload_hands()
		1: _smg_reload_hands()
		2: _shotgun_hands()

func _hand_point(value: Vector3) -> Vector3:
	return _rig.transform * MODELS.source_vector(value)

func _magazine_point(offset: Vector3) -> Vector3:
	var magazine := _parts["magazine"] as Node3D
	return _rig.transform * (magazine.transform * MODELS.source_vector(offset))

func _smooth(value: float) -> float:
	return smoothstep(0.0, 1.0, clampf(value, 0, 1))

func _rifle_reload_hands() -> void:
	var magazine := _parts["magazine"] as Node3D
	magazine.position = MODELS.source_vector(Vector3(0, 1, 1))
	if not _reloading:
		return
	var stage := _reload_progress * 2.5
	var left_rest := _left_hand
	var right_rest := _right_hand
	var discard := _hand_point(Vector3(5, -10, 4))
	var right_bolt := _hand_point(Vector3(-2, -7, -4))
	var right_pull := _hand_point(Vector3(-3, -4, -6))
	if stage < 0.1:
		_left_hand = _left_hand.lerp(_magazine_point(Vector3(0, 0, 4)), _smooth(stage / 0.1))
	elif stage < 0.7:
		var per := (stage - 0.1) / 0.6
		if per < 0.2:
			per = clampf(per * 4.0 - 0.4, 0, 0.2)
		if per > 0.5:
			per += per - 0.5
		magazine.position = MODELS.source_vector(Vector3(0, 1, 1 + per * per * 10))
		_left_hand = _magazine_point(Vector3(0, 0, 4))
		if per > 0.5:
			_left_hand = _left_hand.lerp(discard, _smooth(per - 0.5))
	elif stage < 1.4:
		var per := (1.4 - stage) / 0.7
		if per < 0.3:
			per = clampf(per * 4.0 - 0.4, 0, 0.3)
		magazine.position = MODELS.source_vector(Vector3(0, 1, 1 + per * per * 10))
		_left_hand = _magazine_point(Vector3(0, 0, 4))
	elif stage < 1.9:
		var per := _smooth((stage - 1.4) / 0.5)
		_left_hand = _magazine_point(Vector3(0, 0, 4)).lerp(left_rest, per)
		_right_hand = right_rest.lerp(right_bolt, per)
	elif stage < 2.2:
		_right_hand = right_bolt.lerp(right_pull, _smooth((stage - 1.9) / 0.3))
	else:
		_right_hand = right_pull.lerp(right_rest, _smooth((stage - 2.2) / 0.3))

func _smg_reload_hands() -> void:
	var magazine := _parts["magazine"] as Node3D
	magazine.position = MODELS.source_vector(Vector3(0, 3, 1))
	if not _reloading:
		return
	var stage := _reload_progress * 2.5
	var left_rest := _left_hand
	var discard := _hand_point(Vector3(5, -10, 4))
	var charge := _hand_point(Vector3(1, 6, -4))
	var pull := _hand_point(Vector3(1, 9, -6))
	if stage < 0.7:
		var per := stage / 0.7
		magazine.position = MODELS.source_vector(Vector3(0, 3, 1 + per * per * 50))
		_left_hand = _left_hand.lerp(discard, _smooth(per))
	elif stage < 1.4:
		var per := (1.4 - stage) / 0.7
		if per < 0.3:
			per = clampf(per * 4.0 - 0.4, 0, 0.3)
		magazine.position = MODELS.source_vector(Vector3(0, 3, 1 + per * per * 10))
		_left_hand = _magazine_point(Vector3(0, 0, 4))
	elif stage < 1.9:
		_left_hand = _magazine_point(Vector3(0, 0, 4)).lerp(charge, _smooth((stage - 1.4) / 0.5))
	elif stage < 2.2:
		_left_hand = charge.lerp(pull, _smooth((stage - 1.9) / 0.3))
	else:
		_left_hand = pull.lerp(left_rest, _smooth((stage - 2.2) / 0.3))

func _shotgun_hands() -> void:
	_left_hand = _hand_point(Vector3(0, 4, 2))
	if _reloading:
		var stage := _reload_progress * 0.5
		var left_rest := _left_hand
		var reach := _hand_point(Vector3(5, -10, 4))
		var insert := _hand_point(Vector3(1, 1, 2))
		if stage < 0.2:
			_left_hand = left_rest.lerp(reach, _smooth(stage / 0.2))
		elif stage < 0.35:
			_left_hand = reach.lerp(insert, _smooth((stage - 0.2) / 0.15))
		else:
			_left_hand = insert.lerp(left_rest, _smooth((stage - 0.35) / 0.15))
	var cock := 0.0
	if _fire_elapsed >= 0.2 and _fire_elapsed < 0.3:
		cock = (_fire_elapsed - 0.2) / 0.1
	elif _fire_elapsed >= 0.3 and _fire_elapsed < 0.42:
		cock = 1.0
	elif _fire_elapsed >= 0.42 and _fire_elapsed < 0.52:
		cock = 1.0 - (_fire_elapsed - 0.42) / 0.1
	var cock_fade := 1.0
	if _reloading:
		cock_fade = 0.0 if _reload_progress < 0.5 or _ammo < _clip_size - 1 else clampf((_reload_progress * 0.5 - 0.25) * 10, 0, 1)
	cock *= cock_fade
	var pump := _parts["pump"] as Node3D
	pump.position = MODELS.source_vector(Vector3(0, cock * -1.5, 0))
	if cock_fade > 0:
		_left_hand = _left_hand.lerp(_rig.transform * (pump.transform * MODELS.source_vector(Vector3(0, 4, 2))), cock_fade)

func _update_tool(swing: Vector3) -> void:
	var matrix := Transform3D.IDENTITY.scaled_local(Vector3.ONE * VIEW_SCALE)
	var put_down := 1.0 - _raise
	_rig.visible = true
	if _tool == 0:
		var bash := maxf(1.0 - _fire_elapsed / 0.25, 0.0)
		if _digging:
			var progress := _dig_progress
			var angle := 0.6
			var front := -0.8
			if progress < 0.5:
				var per := pow((0.5 - progress) / 0.5, 4)
				angle += per * 0.6
				front += per * 2.0
			else:
				var per := 1.0 - pow(1.0 - (progress - 0.5) / 0.5, 2)
				angle += per * 0.6
				front += per * 2.0
			matrix = _rotate_before(matrix, Vector3.RIGHT, angle)
			matrix = _rotate_before(matrix, Vector3(0, 0, 1), front * 0.15)
			matrix = MODELS.source_translation(Vector3(0.3, front * 0.1, front * 0.02)) * matrix
		elif bash > 0:
			matrix = _rotate_before(matrix, Vector3.RIGHT, bash * 1.7)
			matrix = MODELS.source_translation(Vector3(0, bash * 0.3, 0)) * matrix
		var per := maxf(_sprint, put_down)
		matrix = _rotate_before(matrix, Vector3(0, 1, 0), per * 1.3)
		matrix = MODELS.source_translation(Vector3(0.3, -0.4, -0.1) * per) * matrix
		matrix = MODELS.source_translation(Vector3(-0.3, 0.7 - put_down * 0.3, 0.3) + swing) * matrix
		_rig.transform = matrix
		_left_hand = _hand_point(Vector3(0, 0, 7))
		_right_hand = _hand_point(Vector3(0, 0, -2))
	elif _tool == 1:
		matrix = _rotate_before(matrix, Vector3(0, 0, 1), _sprint * -0.3)
		matrix = MODELS.source_translation(Vector3(0.1, -0.4, -0.05) * _sprint) * matrix
		matrix = MODELS.source_translation(Vector3(-0.3, 0.7, 0.3) + swing + Vector3(-0.1, -0.3, 0.2) * put_down) * matrix
		_rig.transform = matrix
		_rig.visible = _fire_elapsed >= 0.15
		_left_hand = _hand_point(Vector3(5, -1, 4))
		_right_hand = _hand_point(Vector3(-5.5, 3, -5))
	else:
		var pin := minf(_cook_time * 8.0, 2.0)
		var side := maxf(pin - 1.0, 0.0)
		var bring := -side * 2.0
		matrix = _rotate_before(matrix, Vector3(0, 0, 1), _sprint * -0.3)
		matrix = MODELS.source_translation(Vector3(0.1, -0.2, -0.05) * _sprint) * matrix
		matrix = MODELS.source_translation(Vector3(-0.3 - side * 0.8, 0.8 - bring * 0.1, 0.45 - bring * 0.15)
			+ swing + Vector3(-0.1, -0.3, 0.1) * put_down) * matrix
		_rig.transform = matrix
		_rig.visible = _fire_elapsed > 0.33
		_left_hand = _hand_point(Vector3(10, -1, 10))
		_right_hand = _hand_point(Vector3(-3, 1, 5))
		var pull := _hand_point(Vector3(2, 1, -2))
		if pin < 1:
			_left_hand = _left_hand.lerp(pull, pin)
		else:
			_left_hand = pull.lerp(_hand_point(Vector3(8, -1, 10)), pin - 1)
		if not _rig.visible:
			var per := minf(_fire_elapsed * 3.0, 1.0)
			var arc := 0.9 - pow(per - 0.6, 2) * 2.5
			_left_hand = MODELS.source_vector(Vector3(0.5, 0.5, 0.6))
			_right_hand = MODELS.source_vector(Vector3(-0.2, arc, -0.9 + per * 1.8))

func _update_view_arms() -> void:
	# Solve the original equal-length two-segment arms, preserving original bend side.
	var shoulders := [Vector3(0.4, 0, 0.25), Vector3(-0.4, 0, 0.25)]
	var bend_directions := [Vector3(0.5, 0.2, 0), Vector3(-0.5, 0.2, 0)]
	var hands := [_left_hand, _right_hand]
	for side in range(2):
		var shoulder: Vector3 = shoulders[side]
		var hand: Vector3 = MODELS.SOURCE_AXES.inverse() * hands[side]
		var difference := hand - shoulder
		var bend_length := sqrt(maxf(0.25 - difference.length_squared() * 0.25, 0.0))
		var bend: Vector3 = bend_directions[side].cross(difference).normalized()
		if bend.z < 0:
			bend.z = -bend.z
		var elbow := (hand + shoulder) * 0.5 + bend * bend_length
		_arm_segment(_forearms[side], elbow, hand)
		_arm_segment(_upperarms[side], shoulder, elbow)

func _arm_segment(part: Node3D, start: Vector3, end: Vector3) -> void:
	var axis_z := (end - start).normalized()
	if axis_z.length_squared() < 0.0001:
		part.visible = false
		return
	part.visible = true
	var axis_x := Vector3(0, 0, 1)
	var axis_y := axis_z.cross(axis_x).normalized()
	if axis_y.length_squared() < 0.0001:
		axis_y = Vector3(0, 1, 0)
	axis_x = axis_y.cross(axis_z).normalized()
	var axes := Basis(axis_x, axis_y, axis_z)
	part.transform = Transform3D(MODELS.source_basis(axes).scaled(Vector3.ONE * 0.05), MODELS.source_vector(start))

func get_muzzle_transform() -> Transform3D:
	_ensure_built()
	var lengths := [17.0, 9.0, 11.0]
	return _rig.global_transform * MODELS.source_translation(Vector3(0, lengths[_weapon], -3))
