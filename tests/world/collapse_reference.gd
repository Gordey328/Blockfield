extends "res://world/voxel_data.gd"
## Differential oracle: preserved traversal from d5516eb2bfd22bd5d03f32ac751dce7c01086876.

func _collapse_neighbors(removed: Array[Vector3i], changes: Array, groups: Array) -> void:
	# Existing source-adapted downward-priority traversal; stop as soon as a
	# path to either bottom layer is proven. Only authority computes support.
	var checked: Dictionary = {}
	for cell: Vector3i in removed:
		for direction: Vector3i in DIRECTIONS:
			var start: Vector3i = cell+direction
			if get_block(start) == 0 or checked.has(start):
				continue
			var stack: Array[Vector3i] = [start]
			var component: Array[Vector3i] = []
			var visited: Dictionary = {start:true}
			var supported: bool = false
			while not stack.is_empty():
				var current: Vector3i = stack.pop_back()
				component.append(current)
				if current.y <= 1:
					supported = true
					break
				for i: int in range(DIRECTIONS.size()-1,-1,-1):
					var neighbor: Vector3i = current+DIRECTIONS[i]
					if get_block(neighbor) != 0 and not visited.has(neighbor):
						if neighbor.y <= 1 or checked.has(neighbor):
							supported = true
							break
						visited[neighbor] = true
						stack.append(neighbor)
				if supported:
					break
			if supported:
				for member: Vector3i in component:
					checked[member] = true
			else:
				var colors: PackedInt32Array = PackedInt32Array()
				for member: Vector3i in component:
					colors.append(get_block(member))
				for member: Vector3i in component:
					checked[member] = true
					_record(member,0,changes,true)
				groups.append({"cells":component,"colors":colors})

