class_name TouchAimAssist
extends RefCounted
## Mild touch friction over a visible opponent. Never generates aim motion.
const MIN_GAIN: float = 0.82
const MAX_DISTANCE: float = 64.0
const FULL_FRICTION_ANGLE: float = PI / 180.0
const ESCAPE_ANGLE: float = 4.0 * PI / 180.0

static func gain(origin: Vector3, direction: Vector3, targets: Array[Dictionary], own_team: int, exclude_id: int, world: VoxelWorld, angular_motion: Vector2) -> float:
	if world == null or own_team not in [0, 1] or not origin.is_finite() or not direction.is_finite() or not angular_motion.is_finite():
		return 1.0
	var angle: float = angular_motion.length()
	if angle == 0.0 or angle >= ESCAPE_ANGLE or direction.length_squared() < 0.000001:
		return 1.0
	var ray: Vector3 = direction.normalized()
	var closest: float = MAX_DISTANCE
	var nearest_team: int = -1
	for target: Dictionary in targets:
		if int(target.get("id", -1)) == exclude_id or not bool(target.get("alive", false)) or int(target.get("team", 2)) not in [0, 1]:
			continue
		if bool(target.get("health_known", true)) and int(target.get("health", 100)) <= 0:
			continue
		var feet: Vector3 = target.position
		# Cheap range rejection precedes the original five-volume OBB test.
		if origin.distance_squared_to(feet) > pow(MAX_DISTANCE + 3.0, 2.0):
			continue
		var offset: Vector3 = feet + Vector3.UP * 1.25 - origin
		var along: float = offset.dot(ray)
		if along < -3.0 or along > MAX_DISTANCE + 3.0 or offset.length_squared() - along * along > 9.0:
			continue
		var hit: Dictionary = LabHitVolumes.cast_ray(origin, ray, feet, float(target.get("yaw", 0.0)), bool(target.get("crouching", target.get("crouch", str(target.get("state", "")) == "crouching"))), float(target.get("pitch", 0.0)), closest)
		if bool(hit.hit) and float(hit.distance) < closest:
			closest = float(hit.distance)
			nearest_team = int(target.team)
	if nearest_team < 0 or nearest_team == own_team:
		return 1.0
	var terrain: Dictionary = world.cast_source_ray(origin, ray, MAX_DISTANCE)
	if bool(terrain.hit) and origin.distance_to(terrain.position) < closest:
		return 1.0
	# Deliberate fast swipes smoothly escape the slowdown; no persistent lock.
	return lerpf(MIN_GAIN, 1.0, smoothstep(FULL_FRICTION_ANGLE, ESCAPE_ANGLE, angle))
