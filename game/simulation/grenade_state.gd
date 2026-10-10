class_name SharedGrenadeState
extends RefCounted
## Authority projectile, independent of visual nodes and the thrower's life.
var grenade_id: int = 0
var owner_id: int = 0
var owner_generation: int = 0
var match_epoch: int = 0
var action_sequence: int = 0
var position := Vector3.ZERO
## Godot axes, metres/second; original native velocity is this / 32.
var velocity := Vector3.ZERO
var orientation := Quaternion.IDENTITY
var created_tick: int = 0
var last_tick: int = 0
var fuse_deadline_tick: float = 0.0
var finished: bool = false
var event_sequence: int = 0

func copy() -> SharedGrenadeState:
	var result := SharedGrenadeState.new()
	for property: Dictionary in get_script().get_script_property_list():
		result.set(property.name, get(property.name))
	return result
