extends RefCounted
class_name PathAlgorithm

# RefCounted keeps internal counter, do not need to be freed manually

func configure(_world_manager: Node) -> void:
	pass

# generic find path function
func compute_path(_start: Vector2, _target: Vector2, _extents: Vector2) -> PackedVector2Array:
	push_error("Not implemented")
	return PackedVector2Array()
