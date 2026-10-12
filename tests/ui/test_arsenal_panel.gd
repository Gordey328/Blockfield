extends SceneTree
## Real touch dispatch, catalogue admission and bounded CSS layout.
const PANEL = preload("res://ui/arsenal_panel.gd")
const CATALOG = preload("res://gameplay/arsenal_catalog.gd")
const MOBILE = preload("res://ui/mobile_controls.gd")

class WebCssPanel extends ArsenalPanel:
	var raw_css: Variant = "[1280,720]"
	var css_reads: int = 0

	func _uses_css_layout() -> bool:
		return true

	func _read_css_rect() -> Variant:
		css_reads += 1
		return raw_css

var checks: int = 0
var failures: int = 0
var selections: Array[String] = []
var changes: Array[Dictionary] = []
var applications: Array[String] = []
var triggers: Array[bool] = []
var toggles: Array[bool] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var saved: Dictionary = {"size": root.size, "scale_size": root.content_scale_size,
		"scale_mode": root.content_scale_mode, "scale_aspect": root.content_scale_aspect,
		"mouse_mode": Input.mouse_mode}
	root.size = Vector2i(812, 375)
	var panel: ArsenalPanel = PANEL.new()
	root.add_child(panel)
	panel.item_selected.connect(func(id: String) -> void: selections.append(id))
	panel.loadout_changed.connect(func(value: Dictionary) -> void: changes.append(value))
	panel.apply_requested.connect(func(id: String) -> void: applications.append(id))
	panel.trigger_changed.connect(func(value: bool) -> void: triggers.append(value))
	panel.catalog_toggled.connect(func(value: bool) -> void: toggles.append(value))
	await _frames(4)
	_check(panel.get_display_state().selected_item == "source" and selections.is_empty(), "Constructing the panel does not enable the new arsenal")
	panel.set_enabled(true)
	panel.show_catalog(true)
	_check(toggles == [true] and panel.get_safe_zones().size() == 1, "Opening catalogue publishes one input/capture gate and safe region")
	var identities: Array[int] = _node_ids(panel)
	var discovered: Array[String] = []
	for category: String in ["primary", "bomb", "stratagem"]:
		await _tap(panel._tabs[category])
		var display: Dictionary = panel.get_display_state()
		_check(display.visible_ids.size() == (10 if category == "primary" else (6 if category == "bomb" else 4)), "Each category exposes its full roster: " + category)
		for entry: Dictionary in CATALOG.entries():
			if entry.category != category: continue
			var id: String = str(entry.id)
			var card: Button = panel._cards[id]
			panel._scroll.ensure_control_visible(card)
			await _frames(3)
			_check(panel._scroll.get_global_rect().intersects(card.get_global_rect()), "Every item is reachable by scrolling: " + id)
			_check(panel._card_details[id].text.contains(entry.description_ru), "Card carries catalogue action copy: " + id)
			await _tap(card, panel._scroll.get_global_rect())
			_check(not selections.is_empty() and selections.back() == id and panel.get_display_state().selected_item == id, "A real touch equips the intended ID exactly once: " + id)
			discovered.append(id)
	_check(discovered.size() == 20 and changes.size() == 20, "All twenty actions are discoverable without tiny combat buttons")
	_check(_node_ids(panel) == identities, "Browsing and equipping reuse the original UI nodes")
	panel._choose_category("primary")
	await _frames(4)
	var swipe_start: Vector2 = panel._scroll.get_global_rect().get_center()
	var selections_before_swipe: int = selections.size()
	_touch(swipe_start, true)
	var drag: InputEventScreenDrag = InputEventScreenDrag.new()
	drag.index = 7
	drag.position = swipe_start - Vector2(0, 45) * panel._logical_per_css
	drag.relative = drag.position - swipe_start
	root.push_input(drag, true)
	_touch(drag.position, false)
	await _frames(3)
	_check(panel._scroll.scroll_vertical > 0 and selections.size() == selections_before_swipe, "Actual swipe scrolls catalogue without accidentally equipping its card")
	panel.set_combat_visible(false)
	_check(panel.is_catalog_open() and panel._overlay.visible, "Combat pause gate leaves the already-open catalogue accessible")
	panel.close()
	_check(not panel._bank.visible, "Combat lifecycle gate hides the compact bank independently of global enable")
	panel.set_combat_visible(true)
	panel.show_catalog(true)
	panel._choose_category("stratagem")
	panel._choose_strat_slot(1)
	panel._equip("x17")
	panel._choose_strat_slot(0)
	panel._equip("x17")
	var supports: Array = panel.get_display_state().loadout.stratagems
	_check(supports.size() == 2 and supports[0] != supports[1], "Choosing an already equipped support swaps slots without duplicates")
	panel.close()
	_check(not panel.is_catalog_open() and toggles.back() == false, "Closing releases the root catalogue gate")
	var readout: Dictionary = {"selected_item": "x17", "loadout": CATALOG.defaults(),
		"stock": {"x17": 2, "x12": 2}, "cooldowns": {"x17": 0.0},
		"magazine": 3, "reserve": 12, "charge": .5, "heat": .25, "enabled": true}
	var original: Dictionary = readout.duplicate(true)
	panel.set_readout(readout)
	await _frames(3)
	await _tap(panel._more)
	await _tap(panel._apply)
	_check(applications.is_empty() and panel.get_display_state().targeting, "First support tap enters explicit targeting without firing")
	await _tap(panel._more)
	panel._apply.pressed.emit()
	_check(applications == ["x17"], "Confirm sends one support request and rejects duplicate submission")
	panel.set_readout(original)
	panel.request_application("x18")
	_check(applications.size() == 1 and panel.get_display_state().targeting and selections.back() == "x18", "Keyboard support helper selects and aims without immediate activation")
	panel.request_application("x18")
	_check(applications == ["x17", "x18"], "Second keyboard shortcut confirms through the same support path")
	panel.set_readout(original)
	panel.request_application("x12")
	_check(applications == ["x17", "x18", "x12"], "Bomb shortcut performs exactly one application after its stock gate")
	panel.set_readout(original)
	panel.request_application("x01")
	_check(applications.size() == 3 and selections.back() == "x01", "Primary helper only selects; it never manufactures a fire intent")
	applications.clear()
	applications.append("x17")
	panel.set_readout(original)
	readout.targeting = true
	readout.target_valid = false
	readout.target_reason = "Target behind wall"
	panel.set_readout(readout)
	_check(panel.get_display_state().apply_disabled and panel.get_display_state().hint == "Target behind wall", "Root aim rejection disables confirmation and exposes the reason")
	readout.erase("targeting")
	readout.erase("target_valid")
	readout.erase("target_reason")
	readout.selected_item = "x12"
	readout.stock.x12 = 0
	panel.set_readout(readout)
	panel._apply.pressed.emit()
	_check(applications.size() == 1 and panel._apply.disabled, "Depleted bombs cannot issue application intents")
	readout.selected_item = "x17"
	readout.cooldowns.x17 = 4.5
	panel.set_readout(readout)
	_check(panel._apply.disabled and panel.get_display_state().stock_text.contains("4.5"), "Cooldown uses authority seconds and disables support")
	panel.set_readout(original)
	_check(original.selected_item == "x17" and original.stock.x12 == 2, "The UI never mutates input readout dictionaries")
	readout = original.duplicate(true)
	readout.selected_item = "x01"
	panel.set_readout(readout)
	await _frames(3)
	await _tap(panel._more)
	var point: Vector2 = panel._apply.get_global_rect().get_center()
	_touch(point, true)
	await _frames(2)
	_check(triggers == [true], "Actual touch-down holds the primary trigger for charge and continuous tools")
	_touch(point, false, true)
	await _frames(2)
	_check(triggers == [true, false], "Canceled touch releases fire and never confirms an action")
	_touch(point, true)
	panel.show_catalog(true)
	_check(triggers == [true, false, true, false], "Opening catalogue cancels held fire before root pauses input")
	_touch(point, false)
	panel.close()
	await _tap(panel._more)
	await _tap(panel._source)
	_check(selections.back() == "source" and panel.get_display_state().selected_item == "source", "Classic action restores original equipment through an explicit intent")
	panel.set_home_mode(true)
	_check(not panel._bank.visible, "Home mode contains no compact combat bank")
	panel.show_catalog(true)
	_check(panel._overlay.visible, "Home still provides the full catalogue when explicitly opened")
	var retained_kit: Dictionary = panel.get_display_state().loadout.duplicate(true)
	var source_before: int = selections.size()
	var applications_before: int = applications.size()
	await _frames(3)
	_check(panel._home_source.is_visible_in_tree() and panel._home_source.text.contains("Обычный набор"), "Home catalogue exposes an explicit Classic kit action")
	await _tap(panel._home_source)
	_check(selections.size() == source_before + 1 and selections.back() == "source" and not panel.is_catalog_open(), "Actual Home Classic touch emits one source intent and closes the catalogue")
	_check(panel.get_display_state().loadout == retained_kit and applications.size() == applications_before, "Home Classic preserves the custom kit without issuing an application request")
	panel.show_catalog(true)
	for dimensions: Vector2i in [Vector2i(375, 812), Vector2i(566, 320)]:
		root.size = dimensions
		panel.configure("en")
		await _frames(5)
		var viewport: Rect2 = root.get_visible_rect()
		var css_per_logical: Vector2 = Vector2(dimensions) / viewport.size
		for button: Button in [panel._home_source, panel._close_button]:
			var rectangle: Rect2 = button.get_global_rect()
			_check(viewport.grow(.5).encloses(rectangle) and rectangle.size.x * css_per_logical.x >= 55.5 and rectangle.size.y * css_per_logical.y >= 55.5, "Home header action fits narrow/short screens with a56CSS target: " + str(dimensions))
		_check(not panel._home_source.get_global_rect().grow(-.5).intersects(panel._close_button.get_global_rect().grow(-.5)), "Home header actions never overlap: " + str(dimensions))
	panel.set_home_mode(false)
	_check(not panel._home_source.visible, "Home Classic header action is hidden in combat mode")
	for dimensions: Vector2i in [Vector2i(375, 812), Vector2i(812, 375), Vector2i(568, 320), Vector2i(1280, 720)]:
		for scaled: bool in [false, true]:
			root.size = dimensions
			root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS if scaled else Window.CONTENT_SCALE_MODE_DISABLED
			root.content_scale_size = Vector2i(1280, 720) if scaled else Vector2i.ZERO
			root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
			panel.configure("en")
			panel.show_catalog(true)
			await _frames(5)
			_check_layout(panel, dimensions, scaled)
			panel.close()
			await _frames(3)
			var viewport: Rect2 = root.get_visible_rect()
			_check(viewport.grow(.5).encloses(panel._bank.get_global_rect()), "Compact equipped bank fits viewport: " + str(dimensions))
	await _check_home_card_resize()
	await _check_compact_bank()
	await _check_web_css_cache()
	panel.set_enabled(false)
	panel.show_catalog(true)
	_check(not panel._overlay.visible and not panel._bank.visible, "Disabled lifecycle hides and gates both surfaces")
	_check(Input.mouse_mode == saved.mouse_mode, "Panel leaves mouse capture to the root")
	panel.free()
	root.size = saved.size
	root.content_scale_size = saved.scale_size
	root.content_scale_mode = saved.scale_mode
	root.content_scale_aspect = saved.scale_aspect
	print("ARSENAL PANEL: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _check_home_card_resize() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var sample: ArsenalPanel = PANEL.new()
	root.add_child(sample)
	sample.set_home_mode(true)
	sample.set_enabled(true)
	sample.configure("ru")
	await _frames(3)
	for dimensions: Vector2i in [Vector2i(390, 844), Vector2i(1280, 720), Vector2i(390, 844)]:
		sample.close()
		root.size = dimensions
		sample.show_catalog(true)
		var css_per_logical: Vector2 = Vector2(dimensions) / root.get_visible_rect().size
		var heights: Array[float] = []
		_check(sample._cards.x01.custom_minimum_size.y >= 142 and sample._cards.x01.custom_minimum_size.y <= 240, "Opening/resizing never stores a viewport-sized minimum for the first card: " + str(dimensions))
		for frame: int in 4:
			await _frames(1)
			var height: float = sample._cards.x01.get_global_rect().size.y * css_per_logical.y
			heights.append(height)
			_check(height >= 141.5 and height <= 240.5, "First rendered Home card stays bounded before settling: " + str(dimensions) + " frame=" + str(frame))
			if frame > 0:
				var card_rectangle: Rect2 = sample._cards.x01.get_global_rect()
				_check(card_rectangle.grow(.5).encloses(sample._card_titles.x01.get_global_rect()) and card_rectangle.grow(.5).encloses(sample._card_details.x01.get_global_rect()), "Early card text stays inside its bounds before the CSS poll: " + str(dimensions) + " frame=" + str(frame))
		await create_timer(.30).timeout
		heights.append(sample._cards.x01.get_global_rect().size.y * css_per_logical.y)
		_check(absf(heights.back() - heights[0]) < 1.0, "Home card avoids quarter-second height jitter after opening: " + str(dimensions))
		print("ARSENAL CARD RESIZE %s: %s" % [dimensions, heights])
	var reached: Array[String] = []
	for category: String in ["primary", "bomb", "stratagem"]:
		sample._choose_category(category)
		await _frames(2)
		for entry: Dictionary in CATALOG.entries():
			if entry.category != category: continue
			var id: String = str(entry.id)
			var card: Button = sample._cards[id]
			sample._scroll.ensure_control_visible(card)
			await _frames(2)
			var rectangle: Rect2 = card.get_global_rect()
			var detail: Label = sample._card_details[id]
			_check(rectangle.size.y >= 141.5 and rectangle.size.y <= 240.5 and sample._scroll.get_global_rect().intersects(rectangle), "Every mobile Home card has bounded reachable content: " + id)
			_check(rectangle.grow(.5).encloses(sample._card_titles[id].get_global_rect()) and rectangle.grow(.5).encloses(detail.get_global_rect()) and detail.get_visible_line_count() == detail.get_line_count(), "Card title and complete wrapped action text remain unclipped: " + id)
			reached.append(id)
	_check(reached.size() == 20, "All twenty Home cards remain reachable after desktop/mobile transitions")
	sample.free()

func _check_compact_bank() -> void:
	root.size = Vector2i(844, 390)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var sample: ArsenalPanel = PANEL.new()
	root.add_child(sample)
	sample.set_enabled(true)
	var state: Dictionary = {"selected_item":"x17", "loadout":CATALOG.defaults(), "stock":{"x17":2, "x12":2}, "cooldowns":{}, "magazine":3, "reserve":12, "enabled":true, "target_valid":true}
	var applied: Array[String] = []
	var held: Array[bool] = []
	var selected: Array[String] = []
	sample.apply_requested.connect(func(id: String) -> void:
		applied.append(id)
		state.stock[id] = int(state.stock.get(id, 0)) - 1
		sample.set_readout(state))
	sample.trigger_changed.connect(func(value: bool) -> void: held.append(value))
	sample.item_selected.connect(func(id: String) -> void: selected.append(id))
	sample.set_readout(state)
	await _frames(4)
	var center: Vector2 = Vector2(844, 390) * .5
	var aim_area: Rect2 = Rect2(center - Vector2.ONE * 12, Vector2.ONE * 24)
	_check(sample._compact_bank and not sample._actions_row.visible and sample._more.visible, "Short landscape starts with one equipped row and a More action")
	_check(not sample._bank.get_global_rect().intersects(aim_area), "Closed844×390 bank leaves the actual crosshair and surrounding aim area clear")
	for button: Button in sample._slots + [sample._more]:
		_check(button.is_visible_in_tree() and button.get_global_rect().size.x >= 55.5 and button.get_global_rect().size.y >= 55.5, "Every closed bank action retains a56CSS touch target")
	var mobile: BlockfieldMobileControls = MOBILE.new()
	root.add_child(mobile)
	mobile.setup(null, null)
	mobile.set_process_input(false)
	mobile.set_anchors_preset(Control.PRESET_TOP_LEFT)
	mobile.size = Vector2(844, 390)
	mobile.set_touch_preferences(false, 1.0, false)
	var mobile_rects: Dictionary = mobile.get_action_rects()
	_check(not sample._bank.get_global_rect().intersects(mobile_rects.primary) and not sample._bank.get_global_rect().intersects(mobile.get_hit_regions().move), "Closed bank avoids real primary-fire and fixed joystick regions")
	_check(sample._bank.position.y >= mobile.get_layout_height(), "Closed bank remains below the original tool row")
	mobile.free()
	await _tap(sample._more)
	_check(sample._actions_row.visible and sample._actions_open and sample.get_safe_zones() == [sample._bank.get_global_rect()], "More opens the existing action drawer and exposes its exact safe bounds")
	await _tap(sample._apply)
	_check(sample._targeting and not sample._actions_row.visible and not sample._actions_open and applied.is_empty(), "Touch Aim collapses the drawer without spending support stock")
	_check(sample._more.text.contains("Подтвердить") and not sample._bank.get_global_rect().intersects(aim_area), "Direct confirmation stays reachable while the aim area is clear")
	state.target_valid = false
	sample.set_readout(state)
	await _tap(sample._more)
	_check(applied.is_empty() and sample._more.disabled and state.stock.x17 == 2, "Invalid target disables compact confirmation without spending stock")
	state.target_valid = true
	sample.set_readout(state)
	await _tap(sample._more)
	_check(applied == ["x17"] and state.stock.x17 == 1 and not sample._actions_open, "Touch Confirm spends support stock exactly once through the shared intent path")
	state.selected_item = "x12"
	sample.set_readout(state)
	await _tap(sample._more)
	await _tap(sample._apply)
	_check(applied == ["x17", "x12"] and state.stock.x12 == 1 and not sample._actions_row.visible, "Bomb application folds the drawer after one request")
	state.selected_item = "x01"
	sample.set_readout(state)
	await _tap(sample._more)
	var fire_point: Vector2 = sample._apply.get_global_rect().get_center()
	_touch(fire_point, true, false, 8)
	await _frames(1)
	await _tap(sample._more)
	_check(held == [true, false] and sample._touches.is_empty() and sample._canceled_touches.has(8), "Collapsing with another finger cancels every owned index and releases held fire")
	_touch(fire_point, false, false, 8)
	_check(sample._canceled_touches.is_empty() and applied.size() == 2, "Canceled release cannot activate a hidden action or leak a pointer claim")
	await _tap(sample._more)
	await _tap(sample._source)
	_check(selected == ["source"] and not sample._actions_open, "The compact drawer keeps Classic backup accessible through a real touch")
	await _tap(sample._more)
	root.size = Vector2i(390,844)
	await _frames(4)
	_check(not sample._actions_open and sample._actions_row.visible and not sample._more.visible, "Rotating an open drawer to portrait clears fold state and restores direct actions")
	root.size = Vector2i(844,390)
	await _frames(4)
	_check(not sample._actions_open and not sample._actions_row.visible and not sample._bank.get_global_rect().intersects(aim_area), "Returning from portrait restores a closed bank with a clear crosshair")
	for dimensions: Vector2i in [Vector2i(390,844), Vector2i(844,390), Vector2i(1280,720), Vector2i(844,390)]:
		root.size = dimensions
		await _frames(4)
		_check(root.get_visible_rect().encloses(sample._bank.get_global_rect()), "Resized combat bank stays inside the viewport: " + str(dimensions))
		if dimensions.y < 500:
			_check(not sample._actions_row.visible and sample._more.visible, "Rotation returns to a closed compact bank: " + str(dimensions))
			await _tap(sample._more)
			_check(sample._actions_row.visible, "Action drawer remains reachable after rotation: " + str(dimensions))
			await _tap(sample._more)
		else:
			_check(sample._actions_row.visible and not sample._more.visible, "Portrait/desktop retain the existing directly visible actions: " + str(dimensions))
	sample.free()

func _check_web_css_cache() -> void:
	# Keep the native window unchanged: only the browser's late canvas rectangle
	# changes. This runs the production cache gate, not the native OS fallback.
	root.size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var sample: WebCssPanel = WebCssPanel.new()
	root.add_child(sample)
	sample.set_process(false)
	var state: Dictionary = {"selected_item":"x17", "loadout":CATALOG.defaults(), "stock":{"x17":2}, "cooldowns":{}, "enabled":true, "target_valid":true}
	_coordinator_update(sample, state)
	await _frames(4)
	_check(sample._css_extent == Vector2(1280, 720) and not sample._compact_bank, "Web cache starts with the pre-ready desktop canvas rectangle")
	var readers: int = sample.css_reads
	sample.raw_css = "[844,390]"
	for tick: int in 30:
		sample._process(.01)
		if tick % 10 == 0: _coordinator_update(sample, state)
	await _frames(4)
	_check(root.size == Vector2i(1280, 720) and sample._css_extent == Vector2(844, 390), "Late Web canvas adopts landscape dimensions without a native viewport resize")
	_check(sample._compact_bank and sample._more.visible and not sample._actions_row.visible, "10Hz coordinator renders cannot starve the compact Web layout")
	var aim_area: Rect2 = Rect2(root.get_visible_rect().get_center() - Vector2.ONE * 12, Vector2.ONE * 24)
	_check(not sample._bank.get_global_rect().intersects(aim_area), "Late Web landscape adoption keeps the crosshair clear")
	for button: Button in sample._slots + [sample._more]:
		var css_target: Vector2 = button.get_global_rect().size / sample._logical_per_css
		_check(css_target.x >= 55.5 and css_target.y >= 55.5, "Late Web layout keeps each compact target at56CSS pixels")
	for tick: int in 70:
		sample._process(.01)
		if tick % 10 == 0: _coordinator_update(sample, state)
	var first_second_reads: int = sample.css_reads - readers
	_check(first_second_reads >= 3 and first_second_reads <= 5, "Web canvas reads stay bounded at3–5/s despite three10Hz render calls")
	for dimensions: Vector2i in [Vector2i(390, 844), Vector2i(844, 390), Vector2i(1280, 720)]:
		sample.raw_css = JSON.stringify([dimensions.x, dimensions.y])
		for tick: int in 30:
			sample._process(.01)
			if tick % 10 == 0: _coordinator_update(sample, state)
		await _frames(4)
		_check(sample._css_extent == Vector2(dimensions) and sample._compact_bank == (dimensions.y < 500), "Web cache follows late CSS portrait/landscape/desktop changes: " + str(dimensions))
		_check(root.get_visible_rect().grow(.5).encloses(sample._bank.get_global_rect()), "Late CSS combat bank fits the logical viewport: " + str(dimensions))
	print("ARSENAL WEB CSS: %d reads in the first simulated second; final %s" % [first_second_reads, sample._css_extent])
	sample.free()

func _coordinator_update(panel: ArsenalPanel, state: Dictionary) -> void:
	panel.set_enabled(true)
	panel.set_combat_visible(true)
	panel.set_readout(state)

func _check_layout(panel: ArsenalPanel, dimensions: Vector2i, scaled: bool) -> void:
	var viewport: Rect2 = root.get_visible_rect()
	var css_per_logical: Vector2 = Vector2(dimensions) / viewport.size
	var context: String = "%s scaled=%s" % [dimensions, scaled]
	_check(viewport.grow(.5).encloses(panel._overlay.get_global_rect()), "Catalogue stays within logical viewport: " + context)
	_check(viewport.grow(.5).encloses(panel._scroll.get_global_rect()) and panel._scroll.get_global_rect().size.y * css_per_logical.y > 56, "Short screens retain a usable scrolling catalogue: " + context)
	for button: Button in [panel._close_button, panel._tabs.primary, panel._tabs.bomb, panel._tabs.stratagem]:
		_check(viewport.grow(.5).encloses(button.get_global_rect()), "Header controls remain reachable: " + context)
		_check(button.get_global_rect().size.x * css_per_logical.x >= 55.5 and button.get_global_rect().size.y * css_per_logical.y >= 55.5, "Header has a56CSS touch target: " + context)

func _tap(button: Button, clip: Rect2 = Rect2()) -> void:
	var rectangle: Rect2 = button.get_global_rect()
	if clip.has_area(): rectangle = rectangle.intersection(clip)
	_touch(rectangle.get_center(), true)
	await _frames(1)
	_touch(rectangle.get_center(), false)
	await _frames(2)

func _touch(point: Vector2, down: bool, canceled: bool = false, index: int = 7) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = down
	event.canceled = canceled
	root.push_input(event, true)

func _frames(count: int) -> void:
	for frame: int in count: await process_frame

func _node_ids(node: Node) -> Array[int]:
	var result: Array[int] = [node.get_instance_id()]
	for child: Node in node.get_children(): result.append_array(_node_ids(child))
	return result

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("ARSENAL PANEL: " + message)
