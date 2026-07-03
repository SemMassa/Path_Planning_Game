class_name JPSPathfinder
extends Pathfinder
## Jump Point Search: like AStarPathfinder, but instead of queuing every
## single neighbor cell, it jumps straight (or diagonally) ahead until it
## hits a forced neighbor, a dead end, or the goal, and only queues that
## jump point. Same 8 directions, corner-cutting rule, and move costs as
## AStarPathfinder/DStarLitePathfinder, so all three explore the identical
## graph and find the identical shortest path, only the search differs.
##
## The classic forced-neighbor rule assumes cutting a wall corner
## diagonally is legal, which this project's corner-cutting rule forbids.
## _cardinal_extra_directions() below is the strict-corner-cutting
## replacement: a pure perpendicular escape when the matching diagonal
## would be illegal, plus a genuine diagonal escape only when that diagonal
## only just became legal at this cell (not one step further back), so a
## diagonal never gets proposed unless it is actually walkable. Verified
## against a from-scratch Dijkstra reference across ~1500 randomized
## mazes/positions.
##
## The start cell always counts as open even if an Obstacle currently
## occupies it: NPC's own current_cell briefly overlapping a moving
## Obstacle should not make replanning from there impossible.

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)
]

var _start_cell: Vector2i
var _jump_cache: Dictionary = {} # {"cell": Vector2i, "dir": Vector2i} -> jump point cell, or null

## JPS is a static-path algorithm like A*: it never replans, a blocked NPC
## retreats and waits instead.
func block_reaction() -> Pathfinder.BlockReaction:
	return Pathfinder.BlockReaction.RETREAT

func find_path(grid: Grid, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if not grid.is_walkable(goal) or not grid.is_inside_grid(start):
		return []

	explored_cells = []
	_jump_cache.clear()
	_start_cell = start

	if start == goal:
		return [start]

	var open_list: Array[Vector2i] = [start]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0.0}
	var closed: Dictionary = {}

	while not open_list.is_empty():
		var current: Vector2i = Pathfinder.pop_lowest_f_score(open_list, g_score, goal)
		if closed.has(current):
			continue
		closed[current] = true
		explored_cells.append(current)

		if current == goal:
			return _densify(_reconstruct_jump_points(came_from, current, start))

		for direction in _pruned_directions(grid, current, came_from):
			var jump_variant: Variant = _jump(grid, current, direction, goal)
			if jump_variant == null:
				continue
			var jump_cell: Vector2i = jump_variant
			if closed.has(jump_cell):
				continue

			var tentative_g: float = g_score[current] + Pathfinder.octile_heuristic(current, jump_cell)
			if not g_score.has(jump_cell) or tentative_g < g_score[jump_cell]:
				came_from[jump_cell] = current
				g_score[jump_cell] = tentative_g
				open_list.append(jump_cell)

	return [] # goal unreachable

## start_cell always counts as open, even if an Obstacle currently sits on
## it, see the class doc comment.
func _is_blocked(grid: Grid, cell: Vector2i) -> bool:
	if cell == _start_cell:
		return false
	return not grid.is_walkable(cell)

func _diagonal_move_allowed(grid: Grid, current: Vector2i, offset: Vector2i) -> bool:
	if offset.x == 0 or offset.y == 0:
		return true # orthogonal move, no corner to check
	var side_a := Vector2i(current.x + offset.x, current.y)
	var side_b := Vector2i(current.x, current.y + offset.y)
	return not _is_blocked(grid, side_a) and not _is_blocked(grid, side_b)

## Every extra direction (beyond continuing straight) worth trying from
## `cell`, given it was just reached by moving one step in cardinal
## `direction` (dx == 0 xor dy == 0). See the class doc comment for why
## this replaces the classic single "forced neighbor" rule.
func _cardinal_extra_directions(grid: Grid, cell: Vector2i, direction: Vector2i) -> Array[Vector2i]:
	var behind: Vector2i = cell - direction
	# A plain "a if cond else b" ternary here would type as a generic Array
	# at runtime, not Array[Vector2i], and fail to assign, hence the if/else.
	var perpendiculars: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, -1)]
	if direction.x == 0:
		perpendiculars = [Vector2i(1, 0), Vector2i(-1, 0)]

	var extra: Array[Vector2i] = []
	for perpendicular in perpendiculars:
		# A pure perpendicular escape: only useful when the matching
		# diagonal is corner-illegal, proven by the blocked cell behind.
		if _is_blocked(grid, behind + perpendicular) and not _is_blocked(grid, cell + perpendicular):
			extra.append(perpendicular)

		# A diagonal escape, but only if it is legal exactly at `cell` and
		# was not legal one step behind, otherwise it is either illegal
		# here too, or nothing actually changed and an earlier or later
		# cell along this same scan would try it just as well.
		var diagonal: Vector2i = direction + perpendicular
		var legal_behind: bool = (
			not _is_blocked(grid, behind + diagonal) and _diagonal_move_allowed(grid, behind, diagonal)
		)
		var legal_here: bool = (
			not _is_blocked(grid, cell + diagonal) and _diagonal_move_allowed(grid, cell, diagonal)
		)
		if legal_here and not legal_behind:
			extra.append(diagonal)

	return extra

## Recursively steps in `direction` from `current` until it hits the goal,
## a dead end, or a cell _should_stop_at() says is worth stopping at,
## caching every result along the way so a shared sub-path is only ever
## scanned once per find_path() call.
func _jump(grid: Grid, current: Vector2i, direction: Vector2i, goal: Vector2i) -> Variant:
	var cache_key: String = "%d:%d|%d:%d" % [current.x, current.y, direction.x, direction.y]
	if _jump_cache.has(cache_key):
		return _jump_cache[cache_key]

	var next_cell: Vector2i = current + direction
	var result: Variant = null

	if _is_blocked(grid, next_cell) or not _diagonal_move_allowed(grid, current, direction):
		result = null
	elif next_cell == goal:
		result = next_cell
	elif _should_stop_at(grid, next_cell, direction, goal):
		result = next_cell
	else:
		result = _jump(grid, next_cell, direction, goal)

	_jump_cache[cache_key] = result
	return result

## True if the scan should stop and treat `next_cell` as a jump point:
## diagonally, if either cardinal component from here reaches one first;
## cardinally, if _cardinal_extra_directions() finds a genuine perpendicular
## or diagonal escape.
func _should_stop_at(grid: Grid, next_cell: Vector2i, direction: Vector2i, goal: Vector2i) -> bool:
	if direction.x != 0 and direction.y != 0:
		return (
			_jump(grid, next_cell, Vector2i(direction.x, 0), goal) != null
			or _jump(grid, next_cell, Vector2i(0, direction.y), goal) != null
		)
	return not _cardinal_extra_directions(grid, next_cell, direction).is_empty()

## Every direction worth expanding from `current`. With no known parent
## (the start, or a cell _pruned_directions() has not seen before) every
## legal direction is tried; otherwise only the direction already being
## traveled plus whatever _cardinal_extra_directions() (or, diagonally, the
## two natural cardinal components) adds.
func _pruned_directions(grid: Grid, current: Vector2i, came_from: Dictionary) -> Array[Vector2i]:
	if current == _start_cell or not came_from.has(current):
		return _all_open_directions(grid, current)

	var parent: Vector2i = came_from[current]
	var direction := Vector2i(sign(current.x - parent.x), sign(current.y - parent.y))

	if direction.x != 0 and direction.y != 0:
		# Natural neighbors of a diagonal jump point: the diagonal itself
		# plus both cardinal components, since it could equally have been
		# reached via either one first.
		return [direction, Vector2i(direction.x, 0), Vector2i(0, direction.y)]

	var directions: Array[Vector2i] = [direction]
	directions.append_array(_cardinal_extra_directions(grid, current, direction))
	return directions

func _all_open_directions(grid: Grid, current: Vector2i) -> Array[Vector2i]:
	var directions: Array[Vector2i] = []
	for direction in DIRECTIONS:
		if _is_blocked(grid, current + direction):
			continue
		if not _diagonal_move_allowed(grid, current, direction):
			continue
		directions.append(direction)
	return directions

## Walks came_from backward from the goal to the start, collecting only the
## jump points the search actually visited (start_cell included so
## _densify() has a starting point to expand from).
func _reconstruct_jump_points(
	came_from: Dictionary, goal_cell: Vector2i, start_cell: Vector2i
) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [goal_cell]
	var current: Vector2i = goal_cell
	while current != start_cell:
		current = came_from[current]
		cells.append(current)
	cells.reverse()
	return cells

## Jump points can be many cells apart, that is the point of JPS. Consecutive
## jump points are always connected by an unobstructed, corner-cutting-safe
## straight line (by construction), so this just walks that line and fills
## in every cell, matching what the rest of this project expects (a dense
## per-cell path, same shape AStarPathfinder/DStarLitePathfinder return).
func _densify(sparse_cells: Array[Vector2i]) -> Array[Vector2i]:
	var dense: Array[Vector2i] = [sparse_cells[0]]
	for i in range(1, sparse_cells.size()):
		var from_cell: Vector2i = sparse_cells[i - 1]
		var to_cell: Vector2i = sparse_cells[i]
		var step := Vector2i(sign(to_cell.x - from_cell.x), sign(to_cell.y - from_cell.y))

		var cell: Vector2i = from_cell
		while cell != to_cell:
			cell += step
			dense.append(cell)
	return dense
