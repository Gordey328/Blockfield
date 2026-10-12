extends RefCounted
## Exact source hit transforms borrowed only during one live multi-pellet shot.
## Eligibility/order are still read by the caller before every pellet. Synchronous
## damage listeners can change a pose or life; exact keys force fresh transforms.
const HITS = preload("res://gameplay/lab_hit_volumes.gd")

class Entry extends RefCounted:
	var feet: Vector3
	var yaw: float
	var crouch: bool
	var pitch: float
	var epoch: int
	var generation: int
	var team: int
	var pose: HITS.PreparedPose

var _entries: Dictionary[int, Entry] = {}

func prepare(id: int, feet: Vector3, yaw: float, crouch: bool, pitch: float,
		epoch: int = 0, generation: int = 0, team: int = 0) -> HITS.PreparedPose:
	var entry: Entry = _entries.get(id)
	if entry != null and entry.feet == feet and entry.yaw == yaw \
			and entry.crouch == crouch and entry.pitch == pitch \
			and entry.epoch == epoch and entry.generation == generation and entry.team == team:
		return entry.pose
	if entry == null:
		entry = Entry.new()
		_entries[id] = entry
	entry.feet = feet
	entry.yaw = yaw
	entry.crouch = crouch
	entry.pitch = pitch
	entry.epoch = epoch
	entry.generation = generation
	entry.team = team
	entry.pose = HITS.prepare_pose(feet, yaw, crouch, pitch)
	return entry.pose
