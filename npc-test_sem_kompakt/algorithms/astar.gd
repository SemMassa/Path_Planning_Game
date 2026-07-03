class_name AStarPathfinder
extends Pathfinder
## A* search: always expands the open cell with the lowest estimated total
## cost (known cost so far plus heuristic to the goal) next. Diagonal moves
## cost more than orthogonal ones, guided by an octile distance heuristic.

# The eight moves allowed on the grid: orthogonal plus diagonal.
const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)
]

## A plain A* search computes one path and sticks to it: a blocked NPC
## retreats and waits instead of replanning.
func block_reaction() -> Pathfinder.BlockReaction:
	return Pathfinder.BlockReaction.RETREAT

## A* explores fewer cells than BFS because the heuristic steers it toward
## the goal instead of expanding outward in every direction.
func find_path(grid: Grid, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if not grid.is_walkable(start) or not grid.is_walkable(goal):
		return []

	explored_cells = [] # reset from any previous find_path() call

	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0.0} # cheapest known cost from start to this cell
	var open_set: Array[Vector2i] = [start] # discovered but not fully expanded yet

	while not open_set.is_empty():
		var current: Vector2i = Pathfinder.pop_lowest_f_score(open_set, g_score, goal)
		explored_cells.append(current) # record for visualization/comparison
		if current == goal:
			break

		for offset in NEIGHBOR_OFFSETS:
			var neighbor: Vector2i = current + offset
			if not grid.is_walkable(neighbor):
				continue
			if not Pathfinder.diagonal_move_allowed(grid, current, offset):
				continue

			var tentative_g: float = g_score[current] + Pathfinder.move_cost(offset)
			if not g_score.has(neighbor) or tentative_g < g_score[neighbor]:
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				if neighbor not in open_set:
					open_set.append(neighbor)

	if start != goal and not came_from.has(goal):
		return [] # goal was never reached, no path exists

	return _reconstruct_path(came_from, start, goal)

## Walks came_from backwards from goal to start, then reverses into forward order.
func _reconstruct_path(came_from: Dictionary, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [goal]
	var step: Vector2i = goal
	while step != start:
		step = came_from[step]
		path.push_front(step)
	return path
