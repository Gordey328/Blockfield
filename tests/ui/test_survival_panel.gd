extends SceneTree
## State/formatting and actual container bounds at desktop/mobile sizes.
const PANEL = preload("res://ui/survival_panel.gd")
var checks: int = 0
var failures: int = 0
var actions: Array[String] = []

class FakeSession extends RefCounted:
	var paused: bool = true
	var reads: int = 0
	var state: Dictionary = {"phase": "active", "outcome": "", "finished": false, "paused": true,
		"elapsed_seconds": 60.1, "time_remaining": 539.9, "wave": 2, "wave_planned": 7,
		"wave_spawned": 3, "wave_skipped": 2, "live": 5, "live_limit": 12,
		"window_remaining": 0.0, "next_wave_seconds": 59.9, "supply_status": "progress", "supply_progress": 0.5,
		"settings": {"duration_seconds": 600, "wave_interval_seconds": 60, "zombies_per_wave": 6, "growth_per_minute": 1.0, "growth_mode": "linear"}}
	func get_survival_state() -> Dictionary:
		reads += 1
		return state.duplicate(true)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_size: Vector2i = root.size
	var original_scale: Vector2i = root.content_scale_size
	var original_mode: Window.ContentScaleMode = root.content_scale_mode
	var original_aspect: Window.ContentScaleAspect = root.content_scale_aspect
	var panel: SurvivalPanel = PANEL.new()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var session: FakeSession = FakeSession.new()
	var original_state: Dictionary = session.state.duplicate(true)
	var original_mouse: Input.MouseMode = Input.mouse_mode
	panel.configure(session, "ru")
	panel.resume_requested.connect(func() -> void: actions.append("resume"))
	panel.restart_requested.connect(func() -> void: actions.append("restart"))
	panel.home_requested.connect(func() -> void: actions.append("home"))
	await _frames(4)
	var display: Dictionary = panel.get_display_state()
	_check(display.timer == "Осталось: 09:00" and display.phase.contains("Пауза"), "Countdown rounds up and pause is clearly shown")
	_check(display.wave == "Волна 2 · Живых 5 / 12" and display.quota.contains("Появилось 3 из 7 · Пропущено 2"), "Readout reports actual appearances, planned quota and honest skips separately")
	_check(display.supply.contains("Пополнение") and is_equal_approx(display.supply_progress, 0.5), "Supply text and progress follow authority state")
	_check(display.settings.contains("До 6") and display.settings.contains("Плавный рост"), "Settings retain up-to semantics and selected growth type")
	panel._resume.pressed.emit()
	panel._restart.pressed.emit()
	panel._home.pressed.emit()
	_check(actions == ["resume", "restart", "home"], "Each button emits exactly its intended integration signal")
	_check(session.state == original_state and session.paused and Input.mouse_mode == original_mouse, "Display and action signals do not change session rules, pause or mouse capture")
	session.state.phase = "preparation"
	session.state.preparation_remaining = 19.2
	session.state.paused = false
	panel.refresh()
	_check(panel.get_display_state().timer == "До первой волны: 00:20", "Preparation has its own timer")
	session.state.phase = "cleanup"
	panel.refresh()
	_check(panel.get_display_state().timer == "Зачистка: осталось 5" and panel.get_display_state().phase.contains("новых волн нет"), "Cleanup advertises remaining actual enemies and end of waves")
	session.state.phase = "finished"
	session.state.finished = true
	session.state.outcome = "win"
	session.state.kills = 17
	session.state.headshots = 8
	session.state.damage_taken = 40
	panel.refresh()
	display = panel.get_display_state()
	_check(display.title == "Вы выжили" and not display.resume_visible and display.resume_disabled, "Winning result cannot resume finished gameplay")
	_check(display.detail.contains("Убийства: 17") and display.detail.contains("Попаданий в голову: 8") and display.detail.contains("40"), "Result exposes actual combat statistics")
	session.state.outcome = "interrupted"
	session.state.finish_reason = "spawn_unavailable"
	panel.configure(session, "en")
	display = panel.get_display_state()
	_check(display.title == "Arena unavailable" and display.phase.contains("no result") and display.detail.contains("No available zombie spawn"), "Technical spawn failure never presents a win or recorded result")
	session.state.finish_reason = "route_unavailable"
	panel.refresh()
	_check(panel.get_display_state().detail.contains("cannot reach"), "Unreachable enemy route has its own reason")
	session.state.outcome = "defeat"
	panel.refresh()
	_check(panel.get_display_state().title == "Run ended" and panel.get_display_state().phase == "Player defeated", "Death outcome is localized independently of interruption")
	for dimensions: Vector2i in [Vector2i(375, 812), Vector2i(812, 375), Vector2i(568, 320), Vector2i(1280, 720)]:
		for scaled: bool in [false, true]:
			root.size = dimensions
			root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS if scaled else Window.CONTENT_SCALE_MODE_DISABLED
			root.content_scale_size = Vector2i(1280, 720) if scaled else Vector2i.ZERO
			root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
			for finished: bool in [false, true]:
				session.state.finished = finished
				session.state.phase = "finished" if finished else "active"
				session.state.outcome = "win" if finished else ""
				panel.configure(session, "ru")
				await _frames(5)
				_check_bounds(panel, dimensions, scaled, finished)
	panel.free()
	await _frames(3)
	root.size = original_size
	root.content_scale_size = original_scale
	root.content_scale_mode = original_mode
	root.content_scale_aspect = original_aspect
	_check(session.reads > 0, "Configured panel reads the connected survival state")
	print("SURVIVAL PANEL: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check_bounds(panel: SurvivalPanel, dimensions: Vector2i, scaled: bool, finished: bool) -> void:
	var viewport: Rect2 = root.get_visible_rect()
	var css_per_logical: Vector2 = Vector2(dimensions) / viewport.size
	var rectangles: Array[Rect2] = []
	for button: Button in [panel._resume, panel._restart, panel._home]:
		if not button.is_visible_in_tree(): continue
		var rect: Rect2 = button.get_global_rect()
		var context: String = "%s scaled=%s finished=%s %s" % [str(dimensions), scaled, finished, button.name]
		_check(viewport.grow(0.5).encloses(rect), "Footer button stays within actual viewport: " + context)
		_check(rect.size.x * css_per_logical.x >= 47.5 and rect.size.y * css_per_logical.y >= 47.5, "Touch target retains48CSS px: " + context)
		for previous: Rect2 in rectangles:
			_check(not previous.grow(-0.5).intersects(rect.grow(-0.5)), "Footer actions do not overlap: " + context)
		rectangles.append(rect)
	_check(panel._scroll.size.y > 20 and viewport.grow(0.5).encloses(panel._scroll.get_global_rect()), "Long detail stays in an accessible scroll area: " + str(dimensions))
	_check(panel._scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "Portrait layout does not require horizontal scrolling")


func _frames(count: int) -> void:
	for frame: int in count:
		await process_frame
		await create_timer(0.0).timeout


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SURVIVAL PANEL: " + message)
