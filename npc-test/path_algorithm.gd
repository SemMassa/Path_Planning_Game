extends RefCounted
class_name PathAlgorithm

# RefCounted keeps internal counter, do not need to be freed manually
var world_manager: Node

func set_world_manager(p_world_manager: Node) -> void: 
	world_manager = p_world_manager


# generic find path function
func compute_path(start: Vector2, target: Vector2, extents: Vector2) -> PackedVector2Array:
	push_error("Not implemented")
	return PackedVector2Array()
