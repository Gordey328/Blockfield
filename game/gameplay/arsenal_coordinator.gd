class_name ArsenalCoordinator
extends Node
## Connect authored equipment to the same local session, input and presentation.
var main: Node3D
var runtime: ArsenalRuntime
var bridge: ArsenalBridge
var panel: ArsenalPanel
var view: ArsenalView
var sound: ArsenalAudio
var enabled: bool = false
var source_selected: bool = true
var _panel_trigger: bool = false
var _refresh_age: float = 0.0
var _data: VoxelData
var _loadout: Dictionary = {}
var _frozen_loadout: Dictionary = {}
var _pending_loadout: Dictionary = {}
var _epoch: int = -1
var _generation: int = -1
var _data_generation: int = -1
var _mouse_bank_held: bool = false

func configure(app: Node3D) -> void:
	main = app

func _ready() -> void:
	process_physics_priority = 10
	if main == null: return
	var configuration: Dictionary = main._launch_configuration
	enabled = configuration.get("arsenal", null) is Dictionary and (not main.offline_tdm_mode or main.offline_survival_mode)
	_loadout = ArsenalCatalog.canonical_loadout(configuration.get("arsenal", ArsenalCatalog.defaults()))
	_frozen_loadout = _loadout.duplicate(true)
	source_selected = not enabled
	panel = ArsenalPanel.new()
	add_child(panel)
	panel.configure(main.locale)
	panel.set_loadout(_loadout)
	panel.loadout_changed.connect(_loadout_changed)
	panel.item_selected.connect(_select)
	panel.apply_requested.connect(_apply)
	panel.reload_requested.connect(func() -> void:
		if _can_apply(): runtime.reload())
	panel.trigger_changed.connect(func(held: bool) -> void: _panel_trigger = held and _can_apply())
	panel.catalog_toggled.connect(_catalog_toggled)
	view = ArsenalView.new()
	main.add_child(view)
	view.configure(main.player.camera)
	sound = ArsenalAudio.new()
	add_child(sound)
	_bind()

func _bind() -> void:
	if runtime != null: runtime.clear()
	if bridge != null: bridge.dispose()
	# A catalogue edit is saved for the next attempt, never for this live run.
	if main.offline_survival_mode and not _pending_loadout.is_empty():
		_loadout = _pending_loadout.duplicate(true)
		_frozen_loadout = _loadout.duplicate(true)
		_pending_loadout.clear()
		enabled = true
		source_selected = false
		panel.set_loadout(_loadout)
	_data = main.world.data
	_epoch = _data.epoch
	_data_generation = _data.generation
	bridge = ArsenalBridge.new()
	bridge.configure(main.session, main.player, main.world)
	_generation = bridge.generation()
	runtime = ArsenalRuntime.new()
	runtime.configure(bridge, _loadout)
	main.player.arsenal_runtime = runtime
	main.player.arsenal_active = enabled and not source_selected
	main.session.arsenal = runtime if enabled else null
	if bridge.simulation() != null: bridge.simulation().arsenal = runtime if enabled else null
	if main.offline_survival_mode:
		main.session.arsenal_loadout = _frozen_loadout.duplicate(true) if enabled else {}
	view.clear()

func is_catalog_open() -> bool:
	return panel != null and panel.is_catalog_open()

func is_custom_primary() -> bool:
	return enabled and not source_selected and main.session.current_tool == LocalSession.Tool.WEAPON

func _can_apply() -> bool:
	return runtime != null and enabled and main.player.controls_enabled and not is_catalog_open() and bridge.allowed()

func prepare_trigger(held: bool) -> void:
	if runtime == null: return
	if not _can_apply():
		_panel_trigger = false
		_mouse_bank_held = false
		runtime.cancel_trigger()
		return
	runtime.set_trigger(((held and not _mouse_bank_held) or _panel_trigger) and _can_apply() and is_custom_primary(), main.player.get_aim_origin(), main.player.get_aim_direction())

func _physics_process(_delta: float) -> void:
	if main == null or runtime == null: return
	if _data != main.world.data or _epoch != main.world.data.epoch or _data_generation != main.world.data.generation:
		_bind()
	if not main.offline_tdm_mode:
		if bridge.alive() and _generation != bridge.generation():
			_generation = bridge.generation()
			runtime.configure(bridge, _loadout)
		prepare_trigger(Input.is_action_pressed("primary"))
		if enabled and main.player.controls_enabled and not is_catalog_open():
			bridge.advance_lab_tick()
			runtime.step()
			for receipt: Dictionary in bridge.drain_transactions(): main.world._present_transaction(receipt)

func _process(delta: float) -> void:
	if main == null or runtime == null: return
	if _data != main.world.data or _epoch != main.world.data.epoch or _data_generation != main.world.data.generation: _bind()
	var readout: Dictionary = runtime.readout()
	readout.selected_item = str(readout.get("selected_item", _loadout.primary)) if is_custom_primary() else "source"
	readout.enabled = enabled and main.session.health > 0 and not is_catalog_open()
	readout.first_person = main.player.camera_mode == BlockfieldPlayer.CameraMode.FIRST_PERSON
	if main.offline_survival_mode: readout.loadout = _frozen_loadout.duplicate(true)
	var aim: Dictionary = bridge.ray_world(main.player.get_aim_origin(), main.player.get_aim_direction(), 96.0)
	readout.target_valid = str(readout.selected_item) == "x20" or bool(aim.get("hit", false))
	readout.target_reason = ("Наведи прицел и подтверди вызов" if bool(readout.target_valid) else "Нужна видимая точка на карте")
	view.update_readout(readout, delta)
	var events: Array[Dictionary] = runtime.drain_events()
	var states: Array[Dictionary] = runtime.visuals()
	if panel.get_display_state().targeting and bool(readout.target_valid) and str(readout.selected_item) != "x20":
		states.append({"id":-900,"item":str(readout.selected_item),"kind":"warning","position":aim.position,"direction":main.player.get_aim_direction(),"radius":1.0,"remaining":2.0,"seconds":2.0,"warning":true,"progress":0.0})
	view.present(events, states)
	sound.play(events)
	for event: Dictionary in events:
		if str(event.get("type", "")) == "rejected": main.hud.show_notice(str(event.get("error", "Недоступно")))
	_refresh_age += delta
	if _refresh_age >= 0.1:
		_refresh_age = 0.0
		var blocked: bool = main._launch_in_progress or (not main._launch_configuration.is_empty() and main._launch_status != "ready")
		var choice: bool = main.offline_survival_mode and bool(main.session.get_rush_state().get("pending", false))
		panel.set_enabled(not blocked and not choice and main.session.health > 0 and (not main.offline_tdm_mode or main.offline_survival_mode))
		panel.set_combat_visible(main.hud._focused and not blocked and not choice and not main.hud.is_menu_open() and main.session.health > 0)
		panel.set_readout(readout)
	main.hud._combat_readout.arsenal_state = readout if is_custom_primary() else {}
	if is_custom_primary(): main.hud._ammo.visible = false
	if main.player._weapon_view != null:
		main.player._weapon_view.visible = not is_custom_primary() and main.player.camera_mode == BlockfieldPlayer.CameraMode.FIRST_PERSON
	if main.hud.mobile_controls != null:
		main.hud.mobile_controls.set_external_safe_zones(panel.get_safe_zones())

func _loadout_changed(loadout: Dictionary) -> void:
	var canonical: Dictionary = ArsenalCatalog.canonical_loadout(loadout)
	ArsenalLoadout.save(canonical, true)
	if main.offline_tdm_mode:
		_pending_loadout = canonical.duplicate(true)
		main.hud.show_notice("Снаряжение сохранено для следующей попытки")
		return
	_loadout = canonical
	_frozen_loadout = canonical.duplicate(true)
	# Runtime retains the stock of other items; catalogue changes never refill it.
	runtime.set_loadout(canonical)
	enabled = true
	source_selected = false
	main.player.arsenal_active = true
	main.session.arsenal = runtime
	runtime.select(str(canonical.primary))
	main.session.select_tool(LocalSession.Tool.WEAPON)

func _select(id: String) -> void:
	if id == "source":
		source_selected = true
		main.player.arsenal_active = false
		if not main.offline_tdm_mode: ArsenalLoadout.save(_loadout, false)
		return
	if main.offline_tdm_mode:
		if not enabled or not runtime.equipped(id):
			main.hud.show_notice("Выберите арсенал в главном меню перед попыткой")
			return
	if not main.offline_tdm_mode:
		enabled = true
		main.session.arsenal = runtime
	source_selected = false
	main.player.arsenal_active = true
	runtime.select(id)
	main.session.select_tool(LocalSession.Tool.WEAPON)

func _apply(id: String) -> void:
	if not _can_apply(): return
	var result: Dictionary = runtime.apply(id, main.player.get_aim_origin(), main.player.get_aim_direction())
	if not bool(result.get("ok", false)): main.hud.show_notice(str(result.get("error", "Недоступно")))

func _catalog_toggled(_open: bool) -> void:
	_panel_trigger = false
	_mouse_bank_held = false
	prepare_trigger(false)
	LabInputBindings.release_actions()
	main.hud._sync_controls()

func _input(event: InputEvent) -> void:
	if panel == null: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed: _mouse_bank_held = false
		else:
			for rectangle: Rect2 in panel.get_safe_zones():
				if rectangle.has_point(event.position): _mouse_bank_held = true

func _unhandled_input(event: InputEvent) -> void:
	if main == null or panel == null: return
	if event.is_action_pressed("arsenal") and not event.is_echo():
		panel.show_catalog(not is_catalog_open())
		get_viewport().set_input_as_handled()
		return
	if is_catalog_open() and event.is_action_pressed("pause"):
		panel.close()
		get_viewport().set_input_as_handled()
		return
	if not _can_apply(): return
	if event.is_echo(): return
	var item: String = ""
	if event.is_action_pressed("arsenal_bomb"): item = str(_loadout.bomb)
	elif event.is_action_pressed("arsenal_strat_one"): item = str(_loadout.stratagems[0])
	elif event.is_action_pressed("arsenal_strat_two"): item = str(_loadout.stratagems[1])
	if not item.is_empty():
		panel.request_application(item)
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if runtime != null: runtime.clear()
	if bridge != null: bridge.dispose()
	if sound != null: sound.clear()
