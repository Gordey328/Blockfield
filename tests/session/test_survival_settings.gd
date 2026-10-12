extends SceneTree
const SETTINGS = preload("res://gameplay/survival_settings.gd")
var assertions: int = 0
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error("SURVIVAL SETTINGS: " + message)


func _run() -> void:
	var checked: Dictionary = SETTINGS.validate({})
	check(checked.ok and checked.settings == SETTINGS.defaults(), "canonical default settings are accepted")
	var prior: Dictionary = SETTINGS.defaults()
	checked.settings.duration_seconds = 60
	check(prior.duration_seconds == 600, "settings getters return independent dictionaries")
	for raw: Dictionary in [{"duration_seconds": 59}, {"duration_seconds": 1801},
			{"duration_seconds": NAN}, {"duration_seconds": 60.5}, {"duration_seconds": "600"},
			{"wave_interval_seconds": 29}, {"wave_interval_seconds": 121}, {"zombies_per_wave": 0},
			{"zombies_per_wave": 25}, {"growth_per_minute": -0.1}, {"growth_per_minute": INF},
			{"growth_per_minute": 6.1}, {"growth_mode": "exponential"}, {"live_limit": 13},
			{"live_limit": 0}, {"preparation_seconds": 0}]:
		check(not SETTINGS.validate(raw).ok, "invalid production settings reject atomically: %s" % str(raw))
	check(SETTINGS.validate({"duration_seconds": 60, "wave_interval_seconds": 30,
		"zombies_per_wave": 24, "growth_per_minute": 6.0, "live_limit": 1}).ok, "production boundary values accepted")
	check(not SETTINGS.validate({"duration_seconds": 1, "wave_interval_seconds": 1, "preparation_seconds": 0}).ok,
		"short tests are never enabled by ordinary settings")
	check(SETTINGS.validate({"duration_seconds": 1, "wave_interval_seconds": 1, "preparation_seconds": 0}, true).ok,
		"short fixtures require explicit nonserialized test override")
	var with_unknown: Dictionary = SETTINGS.validate({"endless": true, "test_overrides": true, "server_url": "ignored"})
	check(with_unknown.ok and not with_unknown.settings.has("endless") and not with_unknown.settings.has("test_overrides"),
		"unknown fields cannot enable unsupported mode or test bypass")
	var settings: Dictionary = SETTINGS.defaults()
	check(SETTINGS.wave_quota(settings, 0) == 6 and SETTINGS.wave_quota(settings, 1799) == 6,
		"growth uses active time and rounds only at the chosen half-minute boundary")
	check(SETTINGS.wave_quota(settings, 1800) == 7 and SETTINGS.wave_quota(settings, 3600) == 7,
		"linear half-minute and one-minute quota match UI forecast")
	settings.growth_per_minute = 0.5
	check(SETTINGS.wave_quota(settings, 1800) == 6 and SETTINGS.wave_quota(settings, 3600) == 7,
		"fractional rate remains fractional until final quota rounding")
	settings.growth_mode = "step"
	check(SETTINGS.wave_quota(settings, 3599) == 6 and SETTINGS.wave_quota(settings, 3600) == 7,
		"step growth changes only at a whole active minute")
	settings.growth_mode = "constant"
	check(SETTINGS.wave_quota(settings, 108000) == 6, "constant mode ignores growth rate")
	settings.growth_mode = "linear"
	settings.growth_per_minute = 6.0
	check(SETTINGS.wave_quota(settings, 108000) == 24, "maximum quota remains bounded at 24")
	print("SURVIVAL SETTINGS: %d assertions, %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)
