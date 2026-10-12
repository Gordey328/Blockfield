class_name ArsenalRuntime
extends RefCounted
## Twenty authored mechanisms on the host's fixed authority timeline only.
const CATALOG = preload("res://gameplay/arsenal_catalog.gd")
const MAX_PROJECTILES: int = 24
const MAX_FIELDS: int = 8
const MAX_EVENTS: int = 128
const DT: float = 1.0 / 60.0
var bridge: ArsenalBridge
var selected_item: String = "x01"
var last_deployable_hit: Vector3 = Vector3.INF
var _loadout: Dictionary = {}
var _inventory: Dictionary[String,Dictionary] = {}
var _events: Array[Dictionary] = []
var _projectiles: Array[Dictionary] = []
var _fields: Array[Dictionary] = []
var _devices: Array[Dictionary] = []
var _strikes: Array[Dictionary] = []
var _status: Dictionary[int,Dictionary] = {}
var _queue: Array[Dictionary] = []
var _tick: int = 0
var _epoch: int = 0
var _generation: int = 0
var _data_generation: int = 0
var _next_id: int = 0
var _enabled: bool = false
var _trigger: bool = false
var _release: bool = false
var _origin: Vector3 = Vector3.ZERO
var _direction: Vector3 = Vector3.FORWARD
var _charge: int = 0
var _heat: float = 0.0
var _jet_until: int = 0
var _jet_start_y: float = 0.0
var _lock: Dictionary = {}
var _last_host_tick: int = -1

func configure(authority: ArsenalBridge, loadout: Dictionary) -> void:
	clear()
	bridge = authority
	_loadout = CATALOG.canonical_loadout(loadout)
	selected_item = str(_loadout.primary)
	for item: Dictionary in CATALOG.entries():
		_inventory[str(item.id)] = {"magazine":int(item.clip),"reserve":int(item.reserve),
			"stock":int(item.stock),"deadline":0,"reload_until":0}
	_epoch = bridge.epoch()
	_generation = bridge.generation()
	_data_generation = bridge.data.generation if bridge.data != null else 0
	_last_host_tick = -1
	_enabled = true

func clear() -> void:
	if bridge != null:
		for device: Dictionary in _devices:
			if device.kind=="charge": bridge.unwatch_cell(device.cell)
	_enabled = false
	_trigger = false
	_release = false
	_charge = 0
	_heat = 0.0
	_jet_until = 0
	_lock.clear()
	_queue.clear()
	_projectiles.clear()
	_fields.clear()
	_devices.clear()
	_strikes.clear()
	_status.clear()
	_events.clear()
	_tick = 0
	if bridge != null and bridge.terrain != null:
		bridge.cancel_reservations()
		bridge.terrain.expire_owned(bridge.tick())

func equipped(item: String) -> bool:
	return bridge != null and (not bridge.session is OfflineTDMSession \
		or item == _loadout.get("primary","") or item == _loadout.get("bomb","") \
		or (_loadout.get("stratagems",[]) as Array).has(item))

func select(item: String) -> void:
	if not CATALOG.valid(item) or not equipped(item): return
	selected_item = item
	_trigger = false
	_release = false
	_charge = 0
	_lock.clear()

func set_loadout(loadout: Dictionary) -> void:
	# The lab can browse every item without restoring consumed stocks. Match
	# configuration is frozen for this life and is changed only at a new run.
	if bridge == null or bridge.session is OfflineTDMSession: return
	_loadout = CATALOG.canonical_loadout(loadout)
	select(str(_loadout.primary))

func set_trigger(held: bool, origin: Vector3, direction: Vector3) -> void:
	if not _valid_aim(origin,direction):
		_trigger = false
		return
	if _trigger and not held: _release = true
	_trigger = held
	_origin = origin
	_direction = direction.normalized()

func cancel_trigger() -> void:
	# Menu/lifecycle cancellation is separate from a combat release: vacuum must
	# never push targets because focus was lost or a settings panel was opened.
	_trigger = false
	_release = false
	_charge = 0
	_lock.clear()
	# These are uncommitted input edges, with no stock spent or world effect yet.
	# Accepted live projectiles/fields/strikes are retained outside this queue.
	_queue.clear()

func _valid_aim(origin: Vector3,direction: Vector3) -> bool:
	return bridge != null and origin.is_finite() and direction.is_finite() \
		and direction.length_squared() > .00001 and origin.distance_to(bridge.owner_position()) <= 4.0

func apply(item: String, origin: Vector3, direction: Vector3) -> Dictionary:
	if not _enabled or bridge == null or not bridge.allowed(): return _reject(item,"Action unavailable")
	if not CATALOG.valid(item) or not equipped(item): return _reject(item,"Item is not in this loadout")
	if not _valid_aim(origin,direction): return _reject(item,"Aim from the player")
	if _queue.size() >= 8: return _reject(item,"Action queue full")
	for pending: Dictionary in _queue:
		if pending.item == item: return _reject(item,"Already requested")
	var state: Dictionary = _inventory[item]
	if int(state.deadline) > _tick or int(state.reload_until) > _tick: return _reject(item,"Equipment cooling down")
	var category: String = str(CATALOG.get_item(item).category)
	if category != "primary" and int(state.stock) <= 0 and not bridge.unlimited(): return _reject(item,"No charges left")
	if category == "primary" and item != "x10" and int(state.magazine) <= 0 and not bridge.unlimited(): return _reject(item,"Reload the equipment")
	var geometry: Dictionary = _admit(item,origin,direction.normalized())
	if not bool(geometry.get("ok",false)): return _reject(item,str(geometry.get("error","Target unavailable")))
	_queue.append({"item":item,"origin":origin,"direction":direction.normalized(),"geometry":geometry,
		"requested":_tick,"ready":_tick+(72 if item=="x01" else (30 if item=="x07" else (24 if item=="x10" else 0)))})
	return {"ok":true,"error":""}

func alternate() -> Dictionary:
	if not _enabled or bridge == null or not bridge.allowed(): return _reject("x11","Action unavailable")
	var found: bool = false
	for device: Dictionary in _devices:
		if device.item == "x11": found = true
	if not found: return _reject("x11","Place a charge first")
	for pending: Dictionary in _queue:
		if pending.item == "detonate": return _reject("x11","Already requested")
	_queue.append({"item":"detonate","origin":_origin,"direction":_direction,"geometry":{"ok":true}})
	return {"ok":true,"error":""}

func reload() -> void:
	if not _enabled or not bridge.allowed() or not CATALOG.valid(selected_item): return
	var info: Dictionary = CATALOG.get_item(selected_item)
	var state: Dictionary = _inventory[selected_item]
	if info.category != "primary" or selected_item == "x10" or int(state.reload_until) > _tick \
			or int(state.magazine) >= int(info.clip) or (int(state.reserve) <= 0 and not bridge.unlimited()): return
	state.reload_until = _tick + (150 if selected_item in ["x01","x02"] else 90)
	_charge = 0
	_heat = 0.0
	_event("reload",selected_item,bridge.owner_position())

func refill_primary() -> void:
	var id: String = str(_loadout.get("primary",selected_item))
	if _inventory.has(id): _inventory[id].reserve = int(CATALOG.get_item(id).reserve)

func step() -> void:
	if bridge == null: return
	if bridge.epoch() != _epoch or bridge.generation() != _generation or bridge.data.generation != _data_generation or not bridge.alive():
		if _enabled: clear()
		bridge.step()
		return
	if not _enabled or not bridge.allowed(): return
	# Match integration cannot accidentally advance a fuse twice in one host step.
	var host: int = bridge.tick()
	if host == _last_host_tick: return
	_last_host_tick = host
	_tick += 1
	bridge.action_sequence += 1
	for id: String in _inventory:
		var state: Dictionary = _inventory[id]
		if int(state.reload_until) > 0 and int(state.reload_until) <= _tick:
			var needed: int = int(CATALOG.get_item(id).clip) - int(state.magazine)
			var added: int = needed if bridge.unlimited() else mini(needed,int(state.reserve))
			state.magazine += added
			if not bridge.unlimited(): state.reserve -= added
			state.reload_until = 0
			_event("reloaded",id,bridge.owner_position())
	_heat = maxf(0.0,_heat - (.001 if _trigger else .014))
	var requests: Array[Dictionary] = _queue.duplicate()
	_queue.clear()
	for request: Dictionary in requests:
		if int(request.get("ready",0)) > _tick:
			_queue.append(request)
			_charge = _tick-int(request.get("requested",_tick))
			continue
		if request.item == "detonate": _detonate_charges()
		else:
			_execute(str(request.item),request.origin,request.direction,request.geometry)
			_charge = 0
	if _trigger and str(CATALOG.get_item(selected_item).get("category","")) == "primary":
		if selected_item in ["x01","x07"]:
			_charge = mini(_charge+1,72 if selected_item == "x01" else 30)
			if selected_item == "x07": _update_lock()
			if _charge >= (72 if selected_item == "x01" else 30):
				_fire_selected()
		elif selected_item == "x10":
			_charge = mini(_charge+1,24)
			if _charge >= 24: _fire_selected()
		else: _fire_selected()
	if _release:
		if selected_item == "x08": _vacuum_push()
		_charge = 0
		_lock.clear()
		_release = false
	_step_status()
	_step_projectiles()
	_step_fields()
	_step_devices()
	_step_strikes()
	_step_jet()
	bridge.step()
	bridge.flush_events()

func _fire_selected() -> void:
	var state: Dictionary = _inventory[selected_item]
	if int(state.deadline) > _tick or int(state.reload_until) > _tick: return
	if selected_item != "x10" and int(state.magazine) <= 0 and not bridge.unlimited(): return
	if selected_item == "x04" and _heat >= .98: return
	var geometry: Dictionary = _admit(selected_item,_origin,_direction)
	if bool(geometry.get("ok",false)):
		_execute(selected_item,_origin,_direction,geometry)
		_charge = 0
	else:
		_reject(selected_item,str(geometry.get("error","Target unavailable")))
		state.deadline = _tick+15

func _admit(item: String,origin: Vector3,direction: Vector3) -> Dictionary:
	if not bridge.can_reserve(_terrain_jobs(item)): return {"ok":false,"error":"Terrain request budget exhausted"}
	var weight: int = 6 if item == "x12" else (3 if item == "x07" else (1 if item in ["x02","x06"] else 0))
	if _projectile_weight()+weight > MAX_PROJECTILES: return {"ok":false,"error":"Projectile limit reached"}
	if item in ["x04","x13","x14","x15"] and _fields.size()+_devices.size() >= MAX_FIELDS: return {"ok":false,"error":"Field limit reached"}
	if item == "x06":
		for projectile: Dictionary in _projectiles:
			if projectile.item == item: return {"ok":false,"error":"Saw is still returning"}
	if item == "x07":
		var hit: Dictionary = bridge.ray_actor(origin,direction,40.0)
		if hit.is_empty() or not bridge.line_clear(origin,hit.position): return {"ok":false,"error":"Lock onto a visible enemy"}
		return {"ok":true,"target":int(hit.id),"generation":int(hit.generation)}
	if item == "x13":
		for field: Dictionary in _fields:
			if field.item == item: return {"ok":false,"error":"A black hole is already active"}
	if item == "x19":
		for device: Dictionary in _devices:
			if device.item == item: return {"ok":false,"error":"Turret already deployed"}
	if item == "x11" and _count_devices("x11") >= 3: return {"ok":false,"error":"Detonate the three placed charges"}
	if item == "x15" and _count_devices("x15") > 0: return {"ok":false,"error":"Mines already placed"}
	if item == "x15" and int(_inventory[item].stock) < 3 and not bridge.unlimited(): return {"ok":false,"error":"Three mines are required"}
	if item in ["x01","x10"] and not bridge.terrain.can_queue(): return {"ok":false,"error":"Terrain job queue full"}
	if item in ["x09","x11","x13","x14","x15","x16","x17","x18","x19"]:
		var hit: Dictionary = bridge.ray_world(origin,direction,32.0)
		if not bool(hit.hit) or Vector3(hit.position).distance_to(origin) < .4: return {"ok":false,"error":"Aim at a visible surface"}
		if item in ["x15","x19"] and Vector3(hit.normal).y < .5: return {"ok":false,"error":"Needs a supported floor"}
		if item == "x15" and _fields.size()+_devices.size()+3 > MAX_FIELDS: return {"ok":false,"error":"Mine limit reached"}
		if item in ["x17","x18"] and _strikes.size() >= 2: return {"ok":false,"error":"Two strikes are already arriving"}
		if item in ["x09","x16","x17"] and not bridge.terrain.can_queue(): return {"ok":false,"error":"Terrain job queue full"}
		return {"ok":true,"point":hit.position,"normal":hit.normal,"cell":hit.cell}
	return {"ok":true}

func _terrain_jobs(item: String) -> int:
	if item in ["x12","x18"]: return 5
	if item=="x07": return 3
	return 1 if item in ["x01","x02","x10","x11","x13","x16","x17"] else 0

func _execute(item: String,origin: Vector3,direction: Vector3,geometry: Dictionary) -> void:
	# Admission is checked again against state changed by an earlier queued action.
	if not _valid_aim(origin,direction):
		_reject(item,"Player moved away from the charged aim")
		return
	var checked: Dictionary = _admit(item,origin,direction)
	if not bool(checked.ok):
		_reject(item,str(checked.error))
		return
	if item=="x07" and geometry.has("target") and (int(geometry.target)!=int(checked.target) or int(geometry.generation)!=int(checked.generation)):
		_reject(item,"The charged target life was lost")
		return
	geometry = checked
	var state: Dictionary = _inventory[item]
	var info: Dictionary = CATALOG.get_item(item)
	if int(state.deadline) > _tick or int(state.reload_until) > _tick: return
	if info.category == "primary" and item != "x10" and int(state.magazine) <= 0 and not bridge.unlimited(): return
	if info.category != "primary" and int(state.stock) <= 0 and not bridge.unlimited(): return
	if item == "x09":
		var placed: Dictionary = bridge.foam(geometry.point,geometry.normal)
		if not bool(placed.ok):
			_reject(item,str(placed.get("error","Cannot place foam")))
			return
	if not bridge.reserve(_terrain_jobs(item)):
		_reject(item,"Terrain request budget exhausted")
		return
	if not bridge.unlimited():
		if info.category == "primary" and item != "x10": state.magazine -= 1
		elif info.category != "primary": state.stock -= 3 if item == "x15" else 1
	state.deadline = _tick + maxi(1,roundi(float(info.cooldown)*60.0))
	if item not in ["x04","x08"] or _tick%6 == 0: _event("fired",item,origin,{"direction":direction})
	match item:
		"x01": _drill(origin,direction)
		"x02": _spawn_projectile(item,"brick",origin+direction*.3,direction*24.0+Vector3.UP*5,180,{"gravity":24.0,"terrain_reserved":1})
		"x03": _arc(origin,direction)
		"x04":
			_heat = minf(1.0,_heat+.005)
			if _tick % 6 == 0: _flame(origin,direction)
		"x05": _freeze_ray(origin,direction)
		"x06": _spawn_projectile(item,"saw",origin+direction*.4,direction*26.0,180,{"bounces":0,"hits":{},"gravity":0.0})
		"x07":
			for index: int in range(3):
				var side: Vector3 = direction.cross(Vector3.UP).normalized()*float(index-1)*.3
				_spawn_projectile(item,"rocket",origin+direction*.4+side,direction*16.0+side*5.0,180,{"target":geometry.target,"generation":geometry.generation,"gravity":0.0,"terrain_reserved":1})
		"x08": _vacuum(origin,direction,false)
		"x09": _event("impact",item,geometry.point,{"radius":1.5})
		"x10": _hammer(origin,direction)
		"x11": _devices.append(_record(item,"charge",geometry.point+geometry.normal*.12,900,{"cell":geometry.cell,"color":bridge.data.get_block(geometry.cell),"version":bridge.watch_cell(geometry.cell),"health":25.0,"terrain_reserved":1}))
		"x12": _spawn_projectile(item,"popcorn",origin+direction*.4,direction*14.0+Vector3.UP*5.0,60,{"gravity":24.0,"reserved":6,"terrain_reserved":5})
		"x13": _fields.append(_record(item,"blackhole",geometry.point+geometry.normal*.8,120,{"radius":5.0,"terrain_reserved":1}))
		"x14": _fields.append(_record(item,"lure",geometry.point+geometry.normal*.8,360,{"radius":14.0}))
		"x15":
			var horizontal: Vector3 = Vector3(direction.x,0,direction.z).normalized()
			for index: int in range(3):
				var point: Vector3 = Vector3(geometry.point)+horizontal*float(index-1)*1.1+Vector3.UP*.12
				var support: Dictionary = bridge.ray_world(point+Vector3.UP,Vector3.DOWN,3.0)
				if support.hit: point = support.position+Vector3.UP*.12
				_devices.append(_record(item,"mine",point,900,{"armed":_tick+60,"detonate":0,"health":10.0}))
		"x16":
			_strikes.append(_record(item,"sun",geometry.point+geometry.normal*.3,240,{"radius":6.0,"warning":true,"terrain_reserved":1}))
			_event("warning",item,geometry.point,{"radius":6.0,"seconds":4.0})
		"x17":
			_strikes.append(_record(item,"drill",Vector3(geometry.point)-Vector3(geometry.normal)*.05,120,{"radius":1.5,"warning":true,"terrain_reserved":1}))
			_event("warning",item,geometry.point,{"radius":1.5,"seconds":2.0})
		"x18":
			var horizontal: Vector3 = Vector3(direction.x,0,direction.z).normalized()
			for index: int in range(5):
				var point: Vector3 = Vector3(geometry.point)+horizontal*float(index-2)*2.5
				_strikes.append(_record(item,"piano",point,90+index*30,{"radius":2.0,"warning":true,"terrain_reserved":1}))
				_event("warning",item,point,{"radius":2.0,"seconds":1.5+float(index)*.5})
		"x19": _devices.append(_record(item,"turret",geometry.point+Vector3.UP*.1,900,{"ammo":60,"fire_tick":_tick+30,"health":75.0,"direction":direction}))
		"x20":
			_jet_until = _tick+180
			_jet_start_y = bridge.owner_position().y
			_event("jet",item,bridge.owner_position(),{"seconds":3.0})

func _drill(origin: Vector3,direction: Vector3) -> void:
	var removals: Array[Vector3i] = []
	var cursor: Vector3 = origin
	var end: Vector3 = origin+direction*48.0
	for index: int in range(9):
		var hit: Dictionary = bridge.ray_world(cursor,direction,48.0-origin.distance_to(cursor))
		if not hit.hit: break
		end = hit.position
		if Vector3i(hit.cell).y <= 1 or removals.size() >= 8: break
		if not removals.has(hit.cell): removals.append(hit.cell)
		cursor = _exit_cell(hit.position,hit.cell,direction)
		end = origin+direction*48.0
	bridge.remove(removals,true)
	var excluded: Array[int] = []
	for index: int in range(2):
		var hit: Dictionary = bridge.ray_actor(origin,direction,origin.distance_to(end),excluded)
		if hit.is_empty(): break
		# Only the eight queued cells can be pierced; unlisted walls still stop it.
		if not _clear_except(origin,hit.position,removals): break
		_hit(int(hit.id),90.0,"x01",true,str(hit.part))
		excluded.append(int(hit.id))
	_event("beam","x01",origin,{"end_position":end,"radius":.06})

func _clear_except(origin: Vector3,end: Vector3,cells: Array[Vector3i]) -> bool:
	var direction: Vector3 = (end-origin).normalized()
	var cursor: Vector3 = origin
	for index: int in range(mini(130,cells.size()+2)):
		var hit: Dictionary = bridge.ray_world(cursor,direction,maxf(0.0,cursor.distance_to(end)-.02))
		if not hit.hit: return true
		if not cells.has(hit.cell): return false
		cursor = _exit_cell(hit.position,hit.cell,direction)
	return false

func _exit_cell(point: Vector3,cell: Vector3i,direction: Vector3) -> Vector3:
	var distance: float = INF
	for axis: int in range(3):
		if absf(direction[axis]) < .000001: continue
		var edge: float = float(cell[axis])+(1.0 if direction[axis]>0.0 else 0.0)
		var candidate: float = (edge-point[axis])/direction[axis]
		if candidate > .000001: distance = minf(distance,candidate)
	return point+direction*((distance if is_finite(distance) else .001)+.003)

func _arc(origin: Vector3,direction: Vector3) -> void:
	var hit: Dictionary = bridge.ray_actor(origin,direction,30.0)
	if hit.is_empty() or not bridge.line_clear(origin,hit.position): return
	var ids: Array[int] = []
	var from: Vector3 = origin
	var current: Dictionary = bridge.actor(int(hit.id))
	for link: int in range(4):
		if current.is_empty(): break
		var id: int = int(current.id)
		_hit(id,40.0*pow(.72,link),"x03")
		_slow(id,90,.55)
		_event("chain","x03",from,{"end_position":current.position,"radius":.06})
		ids.append(id)
		from = current.position
		current = _nearest(from,6.0,ids,true)

func _flame(origin: Vector3,direction: Vector3) -> void:
	var wall: Dictionary = bridge.ray_world(origin,direction,9.0)
	var length: float = origin.distance_to(wall.position) if wall.hit else 9.0
	for actor: Dictionary in _cone(origin,direction,length,.85,12):
		_warm(int(actor.id))
		_hit(int(actor.id),7.0,"x04")
	if wall.hit:
		bridge.damage_cell(wall.cell,5.0)
		var point: Vector3 = Vector3(wall.position)+Vector3(wall.normal)*.25
		var found: bool = false
		for field: Dictionary in _fields:
			if field.item == "x04" and Vector3(field.position).distance_to(point) < 1.0:
				field.until = _tick+180
				found = true
		if not found and _fields.size()+_devices.size() < MAX_FIELDS:
			_fields.append(_record("x04","fire",point,180,{"radius":1.6,"cell":wall.cell}))
	_event("beam","x04",origin,{"end_position":origin+direction*length,"radius":.2})

func _freeze_ray(origin: Vector3,direction: Vector3) -> void:
	var hit: Dictionary = bridge.ray_actor(origin,direction,9.0)
	var wall: Dictionary = bridge.ray_world(origin,direction,9.0)
	var end: Vector3 = wall.position if wall.hit else origin+direction*9.0
	if not hit.is_empty() and bridge.line_clear(origin,hit.position):
		var id: int = int(hit.id)
		_hit(id,4.0,"x05")
		var status: Dictionary = _status_for(id)
		status.cold = mini(4,int(status.get("cold",0))+1)
		status.cold_until = _tick+120
		_slow(id,120,.6)
		if int(status.cold) >= 4 and _tick >= int(status.get("immune_until",0)):
			status.frozen_until = _tick+90
			status.immune_until = _tick+270
			status.cold = 0
			_event("status","x05",hit.position,{"seconds":1.5,"radius":.8})
		end = hit.position
	_event("beam","x05",origin,{"end_position":end,"radius":.15})

func _vacuum(origin: Vector3,direction: Vector3,push: bool) -> void:
	for actor: Dictionary in _cone(origin,direction,6.0,.6,3):
		var impulse: Vector3 = (Vector3(actor.position)-origin).normalized()* (9.0 if push else -1.5)
		if push: bridge.push(int(actor.id),impulse,9.0)
		elif Vector3(actor.position).distance_to(origin)<1.5: bridge.push(int(actor.id),impulse,0.0)
		else: bridge.impulse(int(actor.id),impulse)
	_event("beam","x08",origin,{"end_position":origin+direction*6.0,"radius":.2})

func _vacuum_push() -> void:
	_vacuum(_origin,_direction,true)

func _hammer(origin: Vector3,direction: Vector3) -> void:
	for actor: Dictionary in _cone(origin,direction,3.5,.15,12):
		_hit(int(actor.id),65.0,"x10",true)
		bridge.impulse(int(actor.id),(Vector3(actor.position)-origin).normalized()*12.0+Vector3.UP*4.0)
	var cells: Array[Vector3i] = []
	for side: float in [-.3,0.0,.3]:
		var ray: Vector3 = (direction+direction.cross(Vector3.UP)*side).normalized()
		var hit: Dictionary = bridge.ray_world(origin,ray,3.5)
		if hit.hit and not cells.has(hit.cell): cells.append(hit.cell)
	bridge.remove(cells,true)
	_event("impact","x10",origin+direction*2.0,{"radius":3.0})

func _hit(id: int,amount: float,item: String,heavy: bool = false,part: String = "torso") -> void:
	var position: Vector3 = bridge.actor(id).get("position",Vector3.ZERO)
	var status: Dictionary = _status.get(id,{})
	if heavy and int(status.get("frozen_until",0)) > _tick:
		amount += 40.0
		status.frozen_until = 0
		_event("shatter",item,position,{"radius":1.0})
	var actual: float = bridge.damage(id,amount*bridge.power_multiplier(item),item,part)
	if actual > 0.0:
		_event("hit",item,position,{"amount":actual,"radius":.2})

func _status_for(id: int) -> Dictionary:
	var actor: Dictionary = bridge.actor(id)
	if actor.is_empty(): return {}
	var status: Dictionary = _status.get(id,{})
	if status.is_empty() or int(status.generation) != int(actor.generation):
		status = {"generation":int(actor.generation),"slow_until":0,"scale":1.0,"cold":0,"cold_until":0,"frozen_until":0,"immune_until":0}
		_status[id] = status
	return status

func _slow(id: int,ticks: int,scale: float) -> void:
	var status: Dictionary = _status_for(id)
	if status.is_empty(): return
	status.slow_until = _tick+ticks
	status.scale = scale

func _warm(id: int) -> void:
	var status: Dictionary = _status.get(id,{})
	if not status.is_empty():
		status.cold = 0
		status.frozen_until = 0
		status.slow_until = 0

func movement_scale(id: int) -> float:
	var status: Dictionary = _status.get(id,{})
	if status.is_empty(): return 1.0
	var actor: Dictionary = bridge.actor(id)
	if actor.is_empty() or int(actor.generation) != int(status.generation): return 1.0
	if int(status.get("frozen_until",0)) > _tick: return 0.0
	return float(status.scale) if int(status.slow_until) > _tick else 1.0

func _step_status() -> void:
	for id: int in _status.keys():
		var actor: Dictionary = bridge.actor(id)
		if actor.is_empty() or int(actor.generation) != int(_status[id].generation):
			_status.erase(id)
		elif int(_status[id].cold_until) <= _tick: _status[id].cold = 0

func _update_lock() -> void:
	var hit: Dictionary = bridge.ray_actor(_origin,_direction,40.0)
	if hit.is_empty() or not bridge.line_clear(_origin,hit.position):
		_lock.clear()
		_charge = 0
		return
	if not _lock.is_empty() and (int(_lock.id) != int(hit.id) or int(_lock.generation) != int(hit.generation)): _charge = 1
	_lock = {"id":int(hit.id),"generation":int(hit.generation)}

func _nearest(origin: Vector3,radius: float,excluded: Array[int] = [],visible: bool = true) -> Dictionary:
	var selected: Dictionary = {}
	var best: float = radius*radius
	for actor: Dictionary in bridge.actors():
		var distance: float = origin.distance_squared_to(actor.position)
		if excluded.has(int(actor.id)) or distance >= best: continue
		if visible and not bridge.line_clear(origin,actor.position): continue
		selected = actor
		best = distance
	return selected

func _cone(origin: Vector3,direction: Vector3,radius: float,cosine: float,limit: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for actor: Dictionary in bridge.actors():
		var offset: Vector3 = Vector3(actor.position)-origin
		if offset.length() > radius or offset.normalized().dot(direction) < cosine or not bridge.line_clear(origin,actor.position): continue
		result.append(actor)
	result.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return origin.distance_squared_to(a.position) < origin.distance_squared_to(b.position))
	if result.size() > limit: result.resize(limit)
	return result

func _record(item: String,kind: String,position: Vector3,ticks: int,detail: Dictionary = {}) -> Dictionary:
	_next_id += 1
	var result: Dictionary = {"id":_next_id,"item":item,"kind":kind,"position":position,"direction":Vector3.FORWARD,
		"created":_tick,"until":_tick+ticks,"color":CATALOG.get_item(item).color}
	result.merge(detail,true)
	return result

func _spawn_projectile(item: String,kind: String,position: Vector3,velocity: Vector3,ticks: int,detail: Dictionary = {}) -> void:
	var state: Dictionary = _record(item,kind,position,ticks,detail)
	state.velocity = velocity
	state.direction = velocity.normalized()
	state.finished = false
	_projectiles.append(state)

func _projectile_weight() -> int:
	var result: int = 0
	for projectile: Dictionary in _projectiles: result += int(projectile.get("reserved",1))
	return result

func _step_projectiles() -> void:
	var added: Array[Dictionary] = []
	for projectile: Dictionary in _projectiles:
		if bool(projectile.finished): continue
		if _tick >= int(projectile.until):
			if projectile.kind == "popcorn":
				for index: int in range(5):
					var angle: float = float(index)*TAU/5.0
					var child: Dictionary = _record("x12","pop",projectile.position,30+index*15,{"velocity":Vector3(cos(angle)*6,7,sin(angle)*6),"gravity":24.0,"finished":false,"terrain_reserved":1})
					added.append(child)
				projectile.terrain_reserved=0
			elif projectile.kind == "pop":
				_blast(projectile.position,3.0,65.0,"x12",1.5,0.0,true)
				projectile.terrain_reserved=0
			projectile.finished = true
			continue
		var previous: Vector3 = projectile.position
		var velocity: Vector3 = projectile.velocity
		if projectile.kind == "rocket":
			var target: Dictionary = bridge.actor(int(projectile.target))
			if not target.is_empty() and int(target.generation) == int(projectile.generation):
				var desired: Vector3 = (Vector3(target.position)-previous).normalized()*20.0
				velocity = velocity.lerp(desired,.1).normalized()*20.0
		if projectile.kind == "saw" and _tick-int(projectile.created) > 75:
			velocity = velocity.lerp((bridge.owner_position()+Vector3.UP*1.5-previous).normalized()*26.0,.09).normalized()*26.0
		velocity.y -= float(projectile.get("gravity",0.0))*DT
		var next: Vector3 = previous+velocity*DT
		var segment: Vector3 = next-previous
		var wall: Dictionary = bridge.ray_world(previous,segment,segment.length())
		var excluded: Array[int] = []
		if _tick-int(projectile.created) < 15 or projectile.kind in ["rocket","brick"]: excluded.append(bridge.owner_id())
		var hit: Dictionary = bridge.ray_actor(previous,segment.normalized(),segment.length(),excluded,projectile.kind == "saw")
		if not hit.is_empty() and (not wall.hit or previous.distance_to(hit.position) < previous.distance_to(wall.position)):
			match str(projectile.kind):
				"brick":
					_hit(int(hit.id),70.0,"x02",true)
					bridge.impulse(int(hit.id),velocity.normalized()*10+Vector3.UP*3)
					projectile.finished = true
				"rocket":
					_blast(hit.position,2.5,55.0,"x07",1.0,0.0,true)
					projectile.terrain_reserved=0
					projectile.finished = true
				"saw":
					var key: String = "%d:%d" % [hit.id,hit.generation]
					if _tick >= int(projectile.hits.get(key,0)):
						_hit(int(hit.id),55.0*pow(.8,int(projectile.bounces)),"x06",true)
						projectile.hits[key] = _tick+20
		if bool(wall.hit) and not bool(projectile.finished):
			match str(projectile.kind):
				"brick":
					bridge.damage_cell(wall.cell,100.0,true)
					projectile.terrain_reserved=0
					_event("impact","x02",wall.position,{"radius":.8})
					projectile.finished = true
				"rocket":
					_blast(Vector3(wall.position)+Vector3(wall.normal)*.03,2.5,55.0,"x07",1.0,0.0,true)
					projectile.terrain_reserved=0
					projectile.finished = true
				"saw":
					projectile.bounces += 1
					if int(projectile.bounces) > 3: projectile.finished = true
					velocity = velocity.bounce(wall.normal)
					next = Vector3(wall.position)+Vector3(wall.normal)*.12
					_event("impact","x06",wall.position,{"radius":.5})
				_:
					velocity = velocity.bounce(wall.normal)*.55
					next = Vector3(wall.position)+Vector3(wall.normal)*.15
		projectile.position = next
		projectile.velocity = velocity
		projectile.direction = velocity.normalized()
		if not bridge.data.is_in_bounds(Vector3i(next.floor())) and next.y < 0: projectile.finished = true
	for index: int in range(_projectiles.size()-1,-1,-1):
		if bool(_projectiles[index].finished):
			bridge.release_reservation(int(_projectiles[index].get("terrain_reserved",0)))
			_projectiles.remove_at(index)
	_projectiles.append_array(added)

func _blast(position: Vector3,radius: float,damage: float,item: String,terrain_radius: float = 0.0,impulse: float = 0.0,reserved: bool = false) -> void:
	# Actor visibility snapshots precede the committed crater/collapse queue.
	for actor: Dictionary in bridge.actors(true):
		var offset: Vector3 = Vector3(actor.position)-position
		if offset.length() >= radius or not bridge.line_clear(position,actor.position): continue
		var factor: float = 1.0-offset.length()/radius
		_hit(int(actor.id),damage*factor*factor,item,true)
		if impulse > 0.0: bridge.impulse(int(actor.id),offset.normalized()*impulse+Vector3.UP*impulse*.35)
	if item != "x15": damage_deployables_at(position,radius,damage)
	if terrain_radius > 0.0: bridge.sphere(position,terrain_radius,512,reserved)
	elif reserved: bridge.release_reservation(1)
	_event("explosion",item,position,{"radius":radius})

func _step_fields() -> void:
	for index: int in range(_fields.size()-1,-1,-1):
		var field: Dictionary = _fields[index]
		if _tick >= int(field.until):
			if field.kind == "blackhole": _blast(field.position,5.0,70.0,"x13",1.5,12.0,true)
			elif field.kind == "lure": _blast(field.position,2.5,20.0,"x14")
			_fields.remove_at(index)
			continue
		if field.kind == "blackhole":
			for actor: Dictionary in bridge.actors():
				var offset: Vector3 = Vector3(field.position)-Vector3(actor.position)
				if offset.length() < 5.0 and bridge.line_clear(field.position,actor.position): bridge.impulse(int(actor.id),offset.normalized()*1.0)
		elif field.kind == "fire" and _tick%15 == 0:
			for actor: Dictionary in bridge.actors(true):
				if Vector3(actor.position).distance_to(field.position) < 1.6 and bridge.line_clear(field.position,actor.position):
					_warm(int(actor.id))
					_hit(int(actor.id),5.0,"x04")
			bridge.damage_cell(field.cell,3.0)

func lure_target(origin: Vector3) -> Vector3:
	if not _enabled: return Vector3.INF
	for field: Dictionary in _fields:
		if field.kind == "lure" and origin.distance_to(field.position) < 14.0 and bridge.line_clear(origin,field.position): return field.position
	return Vector3.INF

func _count_devices(item: String) -> int:
	var count: int = 0
	for device: Dictionary in _devices:
		if device.item == item: count += 1
	return count

func _detonate_charges() -> void:
	var charges: Array[Dictionary] = []
	for index: int in range(_devices.size()-1,-1,-1):
		if _devices[index].item == "x11":
			var charge: Dictionary = _devices[index]
			if float(charge.health)>0.0 and bridge.cell_version(charge.cell)==int(charge.version) and bridge.data.get_block(charge.cell)==int(charge.color): charges.append(charge)
			else:
				bridge.release_reservation(1)
				bridge.unwatch_cell(charge.cell)
			_devices.remove_at(index)
	for charge: Dictionary in charges:
		_blast(charge.position,4.0,110.0,"x11",2.0,0.0,true)
		bridge.unwatch_cell(charge.cell)

func _step_devices() -> void:
	for index: int in range(_devices.size()-1,-1,-1):
		var device: Dictionary = _devices[index]
		if device.kind == "charge" and (bridge.data.get_block(device.cell) != int(device.color) or bridge.cell_version(device.cell) != int(device.version)):
			bridge.release_reservation(int(device.get("terrain_reserved",0)))
			bridge.unwatch_cell(device.cell)
			_devices.remove_at(index)
			continue
		if float(device.health) <= 0.0 or (int(device.until) > int(device.created) and _tick >= int(device.until)):
			bridge.release_reservation(int(device.get("terrain_reserved",0)))
			if device.kind=="charge": bridge.unwatch_cell(device.cell)
			_devices.remove_at(index)
			continue
		if device.kind == "mine":
			if int(device.detonate) > 0 and _tick >= int(device.detonate):
				_blast(device.position,2.7,25.0,"x15",0.0,14.0)
				for other: Dictionary in _devices:
					if other.kind == "mine" and int(other.detonate) == 0 and Vector3(other.position).distance_to(device.position) <= 3.0: other.detonate = _tick+12
				_devices.remove_at(index)
			elif _tick >= int(device.armed) and int(device.detonate) == 0:
				for actor: Dictionary in bridge.actors(true):
					if Vector3(actor.feet).distance_to(device.position) < 1.0:
						device.detonate = _tick+1
						break
		elif device.kind == "turret" and _tick >= int(device.fire_tick):
			var target: Dictionary = _nearest(Vector3(device.position)+Vector3.UP,24.0)
			if not target.is_empty():
				_hit(int(target.id),15.0,"x19")
				device.ammo -= 1
				device.fire_tick = _tick+9
				device.direction = (Vector3(target.position)-Vector3(device.position)).normalized()
				_event("beam","x19",Vector3(device.position)+Vector3.UP,{"end_position":target.position,"radius":.03})
			if int(device.ammo) <= 0: _devices.remove_at(index)

func damage_deployable(origin: Vector3,direction: Vector3,amount: float = 35.0) -> bool:
	# Coordinator routes ordinary hostile/source shots through this ray seam.
	last_deployable_hit = Vector3.INF
	if not origin.is_finite() or not direction.is_finite() or direction.length_squared()<.00001 or not is_finite(amount) or amount <= 0.0: return false
	var ray: Vector3 = direction.normalized()
	var wall: Dictionary = bridge.ray_world(origin,ray,48.0)
	var actor: Dictionary = bridge.ray_actor(origin,ray,48.0)
	var nearest: float = origin.distance_to(wall.position) if wall.hit else 48.0
	if not actor.is_empty(): nearest = minf(nearest,float(actor.distance))
	var selected: Dictionary = {}
	for device: Dictionary in _devices:
		if float(device.health)<=0: continue
		var height: float = 1.3 if device.kind=="turret" else .45
		var box: AABB = AABB(Vector3(device.position)-Vector3(.55,0,.55),Vector3(1.1,height,1.1))
		var distance: float = ArsenalBridge.HITS.ray_box(origin,ray,box,48.0)
		if distance>=0.0 and distance<nearest:
			nearest=distance
			selected=device
	if selected.is_empty(): return false
	last_deployable_hit = origin+ray*nearest
	selected.health -= amount
	_event("impact",str(selected.item),selected.position,{"radius":.5})
	return true

func damage_deployables_at(position: Vector3,radius: float,amount: float) -> void:
	if not position.is_finite() or not is_finite(radius) or not is_finite(amount) or radius <= 0.0 or amount <= 0.0: return
	for device: Dictionary in _devices:
		var distance: float = position.distance_to(device.position)
		if distance < radius and bridge.line_clear(position,device.position):
			device.health -= amount*pow(1.0-distance/radius,2)

func _step_strikes() -> void:
	for index: int in range(_strikes.size()-1,-1,-1):
		var strike: Dictionary = _strikes[index]
		if _tick < int(strike.until): continue
		match str(strike.kind):
			"sun": _blast(strike.position,10.0,300.0,"x16",6.0,16.0,true)
			"piano":
				_blast(Vector3(strike.position)+Vector3.UP*.2,3.5,120.0,"x18",1.5,8.0,true)
				_event("piano","x18",strike.position,{"radius":2.0,"seconds":.35})
			"drill":
				var top: Vector3 = Vector3(strike.position)
				top.y = float(bridge.data.dimensions.y)+.5
				var hit: Dictionary = bridge.ray_world(top,Vector3.DOWN,float(bridge.data.dimensions.y)+1.0)
				var cells: Array[Vector3i] = []
				var first_y: int = -1
				var lowest_y: int = -1
				if hit.hit:
					var first: Vector3i = hit.cell
					first_y = first.y
					lowest_y = maxi(2,first.y-11)
					for depth: int in range(12):
						if first.y-depth <= 1: break
						for x: int in range(-1,2):
							for z: int in range(-1,2): cells.append(first+Vector3i(x,-depth,z))
					bridge.remove(cells,true)
				else: bridge.release_reservation(1)
				for actor: Dictionary in bridge.actors(true):
					var delta: Vector3 = Vector3(actor.position)-Vector3(strike.position)
					var actor_top: Vector3 = Vector3(actor.position)
					actor_top.y = top.y
					if first_y>=0 and Vector2(delta.x,delta.z).length() < 1.6 and Vector3(actor.position).y>=lowest_y \
							and Vector3(actor.position).y<=first_y+1.0 and _clear_except(actor_top,actor.position,cells):
						_hit(int(actor.id),180.0,"x17",true)
				_event("beam","x17",top,{"end_position":strike.position,"radius":.8})
		_strikes.remove_at(index)

func _step_jet() -> void:
	if _jet_until <= _tick: return
	var feet: Vector3 = bridge.owner_position()
	var ceiling: Dictionary = bridge.ray_world(feet+Vector3.UP*2.25,Vector3.UP,1.0)
	if feet.y >= _jet_start_y+8.0:
		if bridge.velocity_mps(bridge.owner_id()).y>0.0: bridge.push(bridge.owner_id(),Vector3.UP,0.0)
	elif not bool(ceiling.hit): bridge.impulse(bridge.owner_id(),Vector3.UP*.85)

func _event(type: String,item: String,position: Vector3,detail: Dictionary = {}) -> void:
	_next_id += 1
	var event: Dictionary = {"id":_next_id,"type":type,"kind":type,"item":item,"position":position,
		"direction":_direction,"color":CATALOG.get_item(item).get("color",Color.WHITE),"radius":.3,"remaining":.15,"seconds":.15,"tick":_tick}
	event.merge(detail,true)
	if event.has("end_position"):
		event.from = position
		event.to = event.end_position
	if event.has("seconds"): event.remaining = event.seconds
	if _events.size() >= MAX_EVENTS: _events.pop_front()
	_events.append(event)

func _reject(item: String,error: String) -> Dictionary:
	_event("rejected",item,bridge.owner_position() if bridge != null else Vector3.ZERO,{"error":error})
	return {"ok":false,"error":error}

func drain_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = _events.duplicate(true)
	_events.clear()
	return result

func visuals() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for group: Array[Dictionary] in [_projectiles,_fields,_devices,_strikes]:
		for state: Dictionary in group:
			var visual: Dictionary = state.duplicate(true)
			visual.remaining = maxf(0.0,float(int(state.until)-_tick)/60.0)
			visual.seconds = visual.remaining
			visual.progress = clampf(float(_tick-int(state.created))/maxf(1.0,float(int(state.until)-int(state.created))),0.0,1.0)
			result.append(visual)
	if _jet_until > _tick:
		result.append({"id":-1,"item":"x20","kind":"jet","position":bridge.owner_position(),"direction":Vector3.UP,"color":CATALOG.get_item("x20").color,"remaining":float(_jet_until-_tick)/60.0,"seconds":float(_jet_until-_tick)/60.0,"progress":0.0})
	return result

func readout() -> Dictionary:
	var stock: Dictionary = {}
	var cooldowns: Dictionary = {}
	for id: String in _inventory:
		stock[id] = int(_inventory[id].stock)
		cooldowns[id] = maxf(0.0,float(int(_inventory[id].deadline)-_tick)/60.0)
	var state: Dictionary = _inventory.get(selected_item,{"magazine":0,"reserve":0,"reload_until":0})
	return {"selected_item":selected_item,"selected_name":str(CATALOG.get_item(selected_item).get("name","")),
		"loadout":_loadout.duplicate(true),"stock":stock,"cooldowns":cooldowns,"magazine":int(state.magazine),
		"reserve":int(state.reserve),"charge":clampf(float(_charge)/(72.0 if selected_item=="x01" else (24.0 if selected_item=="x10" else 30.0)),0.0,1.0),
		"heat":_heat,"enabled":_enabled,"reloading":int(state.reload_until)>_tick,"jet_remaining":maxf(0.0,float(_jet_until-_tick)/60.0),"tick":_tick,
		"projectiles":_projectile_weight(),"fields":_fields.size(),"devices":_devices.size(),"statuses":_status.size(),"pending":has_pending()}

func has_pending() -> bool:
	return not _projectiles.is_empty() or not _fields.is_empty() or not _devices.is_empty() \
		or not _strikes.is_empty() or not _queue.is_empty() or _jet_until > _tick or (bridge != null and bridge.has_pending())
