extends PathAlgorithm
class_name JPSPlusAlgorithm

const SQRT2: float = 1.41421356237

var world_manager: Node = null
var blocked_cells: Dictionary = {}
var jump_cache: Dictionary = {}
var cache_signature: String = ""
var cached_padding: int = -1
var cell_size: float = 32.0


func configure(world_manager_in: Node) -> void:
	world_manager = world_manager_in
	cell_size = _resolve_cell_size()
	_invalidate_cache()


func compute_path(_start: Vector2, _target: Vector2, _extents: Vector2) -> PackedVector2Array:
	var path := PackedVector2Array()
	if not _has_world_api():
		return path

	var start_cell: Vector2i = world_manager.world_to_cell(_start)
	var target_cell: Vector2i = world_manager.world_to_cell(_target)
	var padding: int = _padding_for_extents(_extents)

	_refresh_cache(padding)

	if _is_blocked(target_cell, start_cell):
		return path

	if start_cell == target_cell:
		path.append(_target)
		return path

	var open_list: Array = []
	var came_from: Dictionary = {}
	var g_score: Dictionary = {}
	var closed: Dictionary = {}

	g_score[_cell_key(start_cell)] = 0.0
	open_list.append({"cell": start_cell, "f": _heuristic(start_cell, target_cell)})

	while not open_list.is_empty():
		var current_index := _pop_lowest_f_index(open_list)
		var current_entry: Dictionary = open_list.pop_at(current_index)
		var current: Vector2i = current_entry["cell"]
		var current_key := _cell_key(current)

		if closed.has(current_key):
			continue
		closed[current_key] = true

		if current == target_cell:
			return _reconstruct_path(came_from, current, start_cell, _target)

		for direction in _pruned_directions(current, came_from, start_cell):
			var jump_cell := _next_jump_point(current, direction, start_cell)
			if jump_cell == Vector2i():
				continue

			if _line_reaches_goal(current, direction, target_cell, start_cell):
				jump_cell = target_cell

			var tentative_g := float(g_score[current_key]) + _movement_cost(current, jump_cell)
			var jump_key := _cell_key(jump_cell)
			if not g_score.has(jump_key) or tentative_g < float(g_score[jump_key]):
				came_from[jump_key] = current
				g_score[jump_key] = tentative_g
				open_list.append({"cell": jump_cell, "f": tentative_g + _heuristic(jump_cell, target_cell)})

	return path


func _has_world_api() -> bool:
	return world_manager != null and world_manager.has_method("world_to_cell") and world_manager.has_method("cell_to_world")


func _resolve_cell_size() -> float:
	if not _has_world_api():
		return 32.0

	var origin: Vector2 = world_manager.cell_to_world(Vector2i.ZERO)
	var adjacent: Vector2 = world_manager.cell_to_world(Vector2i(1, 0))
	var resolved: float = absf(adjacent.x - origin.x)
	if resolved <= 0.0:
		return 32.0
	return resolved


func _invalidate_cache() -> void:
	blocked_cells.clear()
	jump_cache.clear()
	cache_signature = ""
	cached_padding = -1


func _refresh_cache(padding: int) -> void:
	if not _has_world_api():
		return

	var signature := _build_map_signature(padding)
	if signature == cache_signature and padding == cached_padding:
		return

	cache_signature = signature
	cached_padding = padding
	blocked_cells = _collect_blocked_cells(padding)
	jump_cache.clear()


func _build_map_signature(padding: int) -> String:
	if not _has_world_api():
		return ""

	var keys: Array[String] = []
	for cell_key in world_manager.grid.keys():
		var cell: Vector2i = cell_key
		if _cell_contains_static_blocker(cell):
			keys.append(_cell_key(cell))

	if "solid_cells" in world_manager:
		for cell_key in world_manager.solid_cells.keys():
			keys.append(_cell_key(cell_key))

	keys.sort()
	return str(padding, "|", ",".join(keys))


func _collect_blocked_cells(padding: int) -> Dictionary:
	var result: Dictionary = {}
	if not _has_world_api():
		return result

	var raw_cells: Dictionary = {}
	for cell_key in world_manager.grid.keys():
		var cell: Vector2i = cell_key
		if _cell_contains_static_blocker(cell):
			raw_cells[cell] = true

	if "solid_cells" in world_manager:
		for cell_key in world_manager.solid_cells.keys():
			raw_cells[cell_key] = true

	for cell_key in raw_cells.keys():
		var cell: Vector2i = cell_key
		for x in range(-padding, padding + 1):
			for y in range(-padding, padding + 1):
				result[Vector2i(cell.x + x, cell.y + y)] = true

	return result


func _cell_contains_static_blocker(cell: Vector2i) -> bool:
	if not world_manager.grid.has(cell):
		return false

	for item in world_manager.grid[cell]:
		if item == null:
			continue
		if item.is_in_group("Statics"):
			return true

	return false


func _padding_for_extents(extents: Vector2) -> int:
	var largest_extent := maxf(extents.x, extents.y)
	if largest_extent <= 0.0:
		return 0

	return maxi(0, ceili(largest_extent / cell_size) - 1)


func _cell_key(cell: Vector2i) -> String:
	return str(cell.x, ":", cell.y)


func _is_blocked(cell: Vector2i, start_cell: Vector2i) -> bool:
	if cell == start_cell:
		return false

	if blocked_cells.is_empty():
		blocked_cells = _collect_blocked_cells(cached_padding if cached_padding >= 0 else 0)

	return blocked_cells.has(cell)


func _is_step_valid(current: Vector2i, direction: Vector2i, start_cell: Vector2i) -> bool:
	var next_cell := current + direction
	if _is_blocked(next_cell, start_cell):
		return false

	if direction.x != 0 and direction.y != 0:
		if _is_blocked(current + Vector2i(direction.x, 0), start_cell):
			return false
		if _is_blocked(current + Vector2i(0, direction.y), start_cell):
			return false

	return true


func _line_reaches_goal(current: Vector2i, direction: Vector2i, goal: Vector2i, start_cell: Vector2i) -> bool:
	var delta := goal - current
	if direction.x == 0 and delta.x != 0:
		return false
	if direction.y == 0 and delta.y != 0:
		return false

	if direction.x != 0 and direction.y != 0:
		if abs(delta.x) != abs(delta.y):
			return false
		if sign(delta.x) != direction.x or sign(delta.y) != direction.y:
			return false

		for step in range(1, abs(delta.x) + 1):
			var step_cell := current + Vector2i(direction.x * step, direction.y * step)
			if _is_blocked(step_cell, start_cell):
				return false
			if _is_blocked(current + Vector2i(direction.x * step, 0), start_cell):
				return false
			if _is_blocked(current + Vector2i(0, direction.y * step), start_cell):
				return false
	else:
		if direction.x != 0:
			if delta.y != 0 or sign(delta.x) != direction.x:
				return false
			for step in range(1, abs(delta.x) + 1):
				if _is_blocked(current + Vector2i(direction.x * step, 0), start_cell):
					return false
		else:
			if delta.x != 0 or sign(delta.y) != direction.y:
				return false
			for step in range(1, abs(delta.y) + 1):
				if _is_blocked(current + Vector2i(0, direction.y * step), start_cell):
					return false

	return true


func _next_jump_point(current: Vector2i, direction: Vector2i, start_cell: Vector2i) -> Vector2i:
	var cache_key := str(_cell_key(current), "|", direction.x, ":", direction.y)
	if jump_cache.has(cache_key):
		return jump_cache[cache_key]

	if not _is_step_valid(current, direction, start_cell):
		jump_cache[cache_key] = Vector2i()
		return Vector2i()

	var next_cell := current + direction
	if _has_forced_neighbor(next_cell, direction, start_cell):
		jump_cache[cache_key] = next_cell
		return next_cell

	if direction.x != 0 and direction.y != 0:
		if _next_jump_point(next_cell, Vector2i(direction.x, 0), start_cell) != Vector2i():
			jump_cache[cache_key] = next_cell
			return next_cell
		if _next_jump_point(next_cell, Vector2i(0, direction.y), start_cell) != Vector2i():
			jump_cache[cache_key] = next_cell
			return next_cell

	var further := _next_jump_point(next_cell, direction, start_cell)
	jump_cache[cache_key] = further
	return further


func _has_forced_neighbor(cell: Vector2i, direction: Vector2i, start_cell: Vector2i) -> bool:
	if direction.x != 0 and direction.y != 0:
		if _is_blocked(cell + Vector2i(-direction.x, 0), start_cell) and not _is_blocked(cell + Vector2i(-direction.x, direction.y), start_cell):
			return true
		if _is_blocked(cell + Vector2i(0, -direction.y), start_cell) and not _is_blocked(cell + Vector2i(direction.x, -direction.y), start_cell):
			return true
	else:
		if direction.x != 0:
			if _is_blocked(cell + Vector2i(0, 1), start_cell) and not _is_blocked(cell + Vector2i(direction.x, 1), start_cell):
				return true
			if _is_blocked(cell + Vector2i(0, -1), start_cell) and not _is_blocked(cell + Vector2i(direction.x, -1), start_cell):
				return true
		else:
			if _is_blocked(cell + Vector2i(1, 0), start_cell) and not _is_blocked(cell + Vector2i(1, direction.y), start_cell):
				return true
			if _is_blocked(cell + Vector2i(-1, 0), start_cell) and not _is_blocked(cell + Vector2i(-1, direction.y), start_cell):
				return true

	return false


func _pruned_directions(current: Vector2i, came_from: Dictionary, start_cell: Vector2i) -> Array:
	if current == start_cell or not came_from.has(_cell_key(current)):
		return _all_open_directions(current, start_cell)

	var parent: Vector2i = came_from[_cell_key(current)]
	var direction := Vector2i(sign(current.x - parent.x), sign(current.y - parent.y))
	var directions: Array = []

	if direction.x != 0 and direction.y != 0:
		directions.append(direction)
		directions.append(Vector2i(direction.x, 0))
		directions.append(Vector2i(0, direction.y))

		if _is_blocked(current + Vector2i(-direction.x, 0), start_cell) and not _is_blocked(current + Vector2i(-direction.x, direction.y), start_cell):
			directions.append(Vector2i(-direction.x, direction.y))
		if _is_blocked(current + Vector2i(0, -direction.y), start_cell) and not _is_blocked(current + Vector2i(direction.x, -direction.y), start_cell):
			directions.append(Vector2i(direction.x, -direction.y))
	else:
		directions.append(direction)
		if direction.x != 0:
			if _is_blocked(current + Vector2i(0, 1), start_cell) and not _is_blocked(current + Vector2i(direction.x, 1), start_cell):
				directions.append(Vector2i(direction.x, 1))
			if _is_blocked(current + Vector2i(0, -1), start_cell) and not _is_blocked(current + Vector2i(direction.x, -1), start_cell):
				directions.append(Vector2i(direction.x, -1))
		else:
			if _is_blocked(current + Vector2i(1, 0), start_cell) and not _is_blocked(current + Vector2i(1, direction.y), start_cell):
				directions.append(Vector2i(1, direction.y))
			if _is_blocked(current + Vector2i(-1, 0), start_cell) and not _is_blocked(current + Vector2i(-1, direction.y), start_cell):
				directions.append(Vector2i(-1, direction.y))

	return _unique_directions(directions)


func _all_open_directions(current: Vector2i, start_cell: Vector2i) -> Array:
	var directions: Array = []
	for direction in [
		Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)
	]:
		if _is_step_valid(current, direction, start_cell):
			directions.append(direction)

	return directions


func _unique_directions(directions: Array) -> Array:
	var unique: Array = []
	var seen: Dictionary = {}
	for direction in directions:
		var key := str(direction.x, ":", direction.y)
		if seen.has(key):
			continue
		seen[key] = true
		unique.append(direction)

	return unique


func _heuristic(a: Vector2i, b: Vector2i) -> float:
	var dx: int = abs(a.x - b.x)
	var dy: int = abs(a.y - b.y)
	return float(max(dx, dy)) + float(min(dx, dy)) * (SQRT2 - 1.0)


func _movement_cost(a: Vector2i, b: Vector2i) -> float:
	var dx: int = abs(a.x - b.x)
	var dy: int = abs(a.y - b.y)
	if dx == 0 or dy == 0:
		return float(dx + dy)
	return float(min(dx, dy)) * SQRT2 + float(abs(dx - dy))


func _pop_lowest_f_index(open_list: Array) -> int:
	var best_index := 0
	var best_score := float(open_list[0]["f"])
	for i in range(1, open_list.size()):
		var score := float(open_list[i]["f"])
		if score < best_score:
			best_score = score
			best_index = i

	return best_index


func _reconstruct_path(came_from: Dictionary, current: Vector2i, start_cell: Vector2i, target: Vector2) -> PackedVector2Array:
	var cells: Array = [current]
	var current_key := _cell_key(current)
	while came_from.has(current_key):
		current = came_from[current_key]
		current_key = _cell_key(current)
		if current == start_cell:
			break
		cells.append(current)

	cells.reverse()

	var path := PackedVector2Array()
	for cell in cells:
		path.append(world_manager.cell_to_world(cell))

	path.append(target)
	return path
