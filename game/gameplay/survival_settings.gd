class_name SurvivalSettings
extends RefCounted
## Canonical authored mode settings. Test bounds are explicit and never serialized.
const MAX_LIVE: int = 12
const SPAWN_WINDOW_SECONDS: int = 12


static func defaults() -> Dictionary:
	return {"duration_seconds": 600, "wave_interval_seconds": 60,
		"zombies_per_wave": 6, "growth_per_minute": 1.0, "growth_mode": "linear",
		"live_limit": MAX_LIVE, "preparation_seconds": 20}


static func validate(raw: Dictionary, test_overrides: bool = false) -> Dictionary:
	var settings: Dictionary = defaults()
	for key: String in settings:
		if raw.has(key):
			settings[key] = raw[key]
	var minimum_duration: int = 1 if test_overrides else 60
	var minimum_interval: int = 1 if test_overrides else 30
	for key: String in ["duration_seconds", "wave_interval_seconds", "zombies_per_wave", "live_limit", "preparation_seconds"]:
		var value: Variant = settings[key]
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) != floorf(float(value)):
			return {"ok": false, "error": "Survival setting %s must be an integer" % key, "settings": {}}
		settings[key] = int(value)
	if settings.duration_seconds < minimum_duration or settings.duration_seconds > 1800:
		return {"ok": false, "error": "Survival duration is outside supported bounds", "settings": {}}
	if settings.wave_interval_seconds < minimum_interval or settings.wave_interval_seconds > 120:
		return {"ok": false, "error": "Survival wave interval is outside supported bounds", "settings": {}}
	if settings.zombies_per_wave < 1 or settings.zombies_per_wave > 24 or settings.live_limit < 1 or settings.live_limit > MAX_LIVE:
		return {"ok": false, "error": "Survival population is outside supported bounds", "settings": {}}
	if (not test_overrides and settings.preparation_seconds != 20) or settings.preparation_seconds < 0 or settings.preparation_seconds > 20:
		return {"ok": false, "error": "Survival preparation must be 20 seconds", "settings": {}}
	if typeof(settings.growth_per_minute) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(settings.growth_per_minute)) \
			or float(settings.growth_per_minute) < 0.0 or float(settings.growth_per_minute) > 6.0:
		return {"ok": false, "error": "Survival growth is outside supported bounds", "settings": {}}
	settings.growth_per_minute = float(settings.growth_per_minute)
	if typeof(settings.growth_mode) != TYPE_STRING or settings.growth_mode not in ["constant", "linear", "step"]:
		return {"ok": false, "error": "Unknown survival growth mode", "settings": {}}
	return {"ok": true, "error": "", "settings": settings}


static func wave_quota(settings: Dictionary, active_tick: int) -> int:
	var minutes: float = float(maxi(0, active_tick)) / 3600.0
	var growth: float = 0.0
	if settings.growth_mode == "linear":
		growth = minutes * float(settings.growth_per_minute)
	elif settings.growth_mode == "step":
		growth = floorf(minutes) * float(settings.growth_per_minute)
	return clampi(roundi(float(settings.zombies_per_wave) + growth), 1, 24)
