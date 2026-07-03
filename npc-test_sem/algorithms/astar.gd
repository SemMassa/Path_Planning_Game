class_name AStarPathfinder
extends Pathfinder
## A* search: always expands the open cell with the lowest estimated
## total cost (known cost so far plus heuristic to the goal) next.
## Diagonal moves cost more than orthogonal ones, guided by an octile
## distance heuristic so the estimate never overshoots the true cost.

const ORTHOGONAL_COST: float = 1.0
const DIAGONAL_COST: float = 1.41421356 # sqrt(2)

# The eight moves allowed on the grid: orthogonal plus diagonal.
const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)
]

## A* explores fewer cells than BFS because the heuristic steers it
## toward the goal instead of expanding outward in every direction.
func find_path(grid: Grid, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if not grid.is_walkable(start) or not grid.is_walkable(goal):
		return []

	explored_cells = [] # reset from any previous find_path() call

	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0.0} # cheapest known cost from start to this cell
	var open_set: Array[Vector2i] = [start] # cells discovered but not fully expanded yet

	while not open_set.is_empty():
		var current: Vector2i = _pop_lowest_f_score(open_set, g_score, goal)
		explored_cells.append(current) # record for visualization/comparison
		if current == goal:
			break

		for offset in NEIGHBOR_OFFSETS:
			var neighbor: Vector2i = current + offset
			if not grid.is_walkable(neighbor):
				continue
			if not _diagonal_move_allowed(grid, current, offset):
				continue

			var tentative_g: float = g_score[current] + _move_cost(offset)
			if not g_score.has(neighbor) or tentative_g < g_score[neighbor]:
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				if neighbor not in open_set:
					open_set.append(neighbor)

	if start != goal and not came_from.has(goal):
		return [] # goal was never reached, no path exists

	return _reconstruct_path(came_from, start, goal)

## Cost of a single step: more for diagonal moves than orthogonal ones.
func _move_cost(offset: Vector2i) -> float:
	return DIAGONAL_COST if offset.x != 0 and offset.y != 0 else ORTHOGONAL_COST

## Octile distance: the true cheapest possible cost between two cells
## on an 8 directional grid, so it never overestimates (admissible heuristic).
func _heuristic(a: Vector2i, b: Vector2i) -> float:
	var dx: int = absi(a.x - b.x)
	var dy: int = absi(a.y - b.y)
	return ORTHOGONAL_COST * maxi(dx, dy) + (DIAGONAL_COST - ORTHOGONAL_COST) * mini(dx, dy)

## Removes and returns the open cell with the lowest f_score (g_score + heuristic).
## Linear scan is fine for the grid sizes used here; a binary heap would be
## the next optimization step for much larger grids.
func _pop_lowest_f_score(
	open_set: Array[Vector2i], g_score: Dictionary, goal: Vector2i
) -> Vector2i:
	var best_index: int = 0
	var best_f: float = g_score[open_set[0]] + _heuristic(open_set[0], goal)
	for i in range(1, open_set.size()):
		var f: float = g_score[open_set[i]] + _heuristic(open_set[i], goal)
		if f < best_f:
			best_f = f
			best_index = i
	return open_set.pop_at(best_index)

## Blocks diagonal moves that would cut through a wall corner.
func _diagonal_move_allowed(grid: Grid, current: Vector2i, offset: Vector2i) -> bool:
	if offset.x == 0 or offset.y == 0:
		return true # orthogonal move, no corner to check
	var side_a := Vector2i(current.x + offset.x, current.y)
	var side_b := Vector2i(current.x, current.y + offset.y)
	return grid.is_walkable(side_a) and grid.is_walkable(side_b)

## Walks came_from backwards from goal to start, then reverses into forward order.
func _reconstruct_path(came_from: Dictionary, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [goal]
	var step: Vector2i = goal
	while step != start:
		step = came_from[step]
		path.push_front(step)
	return path
