class_name GrenadeFeedback
extends RefCounted
## User-selected presentation range; one voxel remains one world unit.
## Applied after native audio gain caps, including environmental sends.
const HALF_GAIN_DISTANCE: float = 12.0

static func distance_gain(distance: float) -> float:
	var scaled: float = maxf(0.0, distance) / HALF_GAIN_DISTANCE
	return 1.0 / (1.0 + scaled * scaled)
