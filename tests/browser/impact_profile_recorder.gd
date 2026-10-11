extends RefCounted
## Diagnostic-only shared nested CPU recorder; copied into isolated __probe.
const SAMPLE_CAP := 8192
static var enabled := false
static var records: Dictionary = {}
static var stack: Array[Dictionary] = []

static func reset() -> void:
	records.clear()
	stack.clear()
	enabled = true

static func enter(key: String) -> int:
	if not enabled:
		return -1
	stack.append({"key":key,"start":Time.get_ticks_usec(),"child":0})
	return stack.size()-1

static func leave(ticket: int) -> void:
	if ticket<0:
		return
	var now := Time.get_ticks_usec()
	var entry: Dictionary = stack.pop_back()
	var inclusive: int = now-int(entry.start)
	var exclusive: int = maxi(0,inclusive-int(entry.child))
	if not stack.is_empty():
		stack[-1].child = int(stack[-1].child)+inclusive
	var key: String = entry.key
	if not records.has(key):
		records[key] = {"calls":0,"inclusive_usec":0,"exclusive_usec":0,"max_inclusive_usec":0,"max_exclusive_usec":0,"samples":[]}
	var row: Dictionary = records[key]
	row.calls = int(row.calls)+1
	row.inclusive_usec = int(row.inclusive_usec)+inclusive
	row.exclusive_usec = int(row.exclusive_usec)+exclusive
	row.max_inclusive_usec = maxi(int(row.max_inclusive_usec),inclusive)
	row.max_exclusive_usec = maxi(int(row.max_exclusive_usec),exclusive)
	if row.samples.size()<SAMPLE_CAP:
		row.samples.append(inclusive)

static func snapshot() -> Dictionary:
	var result: Dictionary = {}
	for key: String in records:
		var row: Dictionary = records[key]
		var samples: Array = row.samples.duplicate()
		samples.sort()
		result[key] = {"calls":row.calls,"inclusive_usec":row.inclusive_usec,"exclusive_usec":row.exclusive_usec,
			"max_inclusive_usec":row.max_inclusive_usec,"max_exclusive_usec":row.max_exclusive_usec,
			"p50_inclusive_usec":samples[int((samples.size()-1)*0.5)] if not samples.is_empty() else 0,
			"p95_inclusive_usec":samples[int((samples.size()-1)*0.95)] if not samples.is_empty() else 0,
			"retained_samples":samples.size(),"sample_policy":"first8192 per function; total/count/max include all calls"}
	return result
