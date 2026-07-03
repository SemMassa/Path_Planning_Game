class_name DStarLitePathfinder
extends Pathfinder
## D* Lite: like A*, but keeps its own search state (g/rhs values plus a
## priority queue) between find_path() calls instead of starting over every
## time. When only the start moved and a handful of cells changed
## walkability (an Obstacle patrolling), it repairs just the affected part
## of that state instead of recomputing the whole graph.
##
## Naming mirrors the standard D* Lite algorithm (g, rhs, pqueue, km,
## s_start, s_goal, s_last, calculate_key, update_vertex,
## compute_shortest_path, get_neighbors, reconstruct_path). One
## find_path(grid, start, goal) entry point decides internally whether to
## do a fresh search or a repair, same call shape as every other Pathfinder.

# The eight moves allowed on the grid. This grid graph is undirected (see
# Pathfinder.diagonal_move_allowed()), so a cell's neighbors double as its
# predecessors, no separate list needed.
const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)
]

var _g: Dictionary = {} # Vector2i -> float, best known cost from s to the goal
var _rhs: Dictionary = {} # Vector2i -> float, one step lookahead of _g, drives repairs
var _pqueue: Dictionary = {} # Vector2i -> Array[float], open queue, key = [priority, tiebreak]
var _km: float = 0.0 # accumulated heuristic offset from the start having moved

var _s_start: Vector2i
var _s_last: Vector2i
var _s_goal: Vector2i
var _grid: Grid # remembered only to notice find_path() being used on a different Grid
var _known_walkable: Array = [] # our own [x][y] snapshot, diffed against grid each call
var _has_run_before: bool = false

## D* Lite repairs its own plan when something blocks it, it does not
## retreat and wait like a plain A* search would.
func block_reaction() -> Pathfinder.BlockReaction:
	return Pathfinder.BlockReaction.REPLAN

## Same interface as every other Pathfinder, but internally either runs a
## full first time search, or repairs its existing state if the start moved
## and/or some cells' walkability changed since the last call with this
## same goal.
func find_path(grid: Grid, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if not grid.is_walkable(start) or not grid.is_walkable(goal):
		return []

	explored_cells = [] # reset from any previous find_path() call

	var needs_fresh_start: bool = not _has_run_before or goal != _s_goal or grid != _grid
	if needs_fresh_start:
		_grid = grid
		_initialize(start, goal)
		_snapshot_walkable(grid)
		_compute_shortest_path(grid)
		_has_run_before = true
	else:
		var changed_cells: Array[Vector2i] = _diff_and_resync_walkable(grid)
		_km += Pathfinder.octile_heuristic(_s_last, start)
		_s_last = start
		_s_start = start
		for cell in changed_cells:
			_update_vertex(grid, cell)
			for neighbor_info in _get_neighbors(grid, cell):
				_update_vertex(grid, neighbor_info["cell"])
		_compute_shortest_path(grid)

	return _reconstruct_path(grid)

## Resets D* Lite's internal state and seeds the goal, the one cell whose
## rhs is defined to be 0 rather than derived from neighbors.
func _initialize(start: Vector2i, goal: Vector2i) -> void:
	_g = {}
	_rhs = {}
	_pqueue = {}
	_km = 0.0
	_s_start = start
	_s_last = start
	_s_goal = goal
	_rhs[goal] = 0.0
	_insert_pqueue(goal, _calculate_key(goal))

## The priority a cell is queued at: its best known cost estimate plus the
## heuristic distance back to the start, plus km. Ties break on that cost
## estimate alone, without the heuristic.
func _calculate_key(s: Vector2i) -> Array:
	var g_rhs: float = minf(_g.get(s, INF), _rhs.get(s, INF))
	return [g_rhs + Pathfinder.octile_heuristic(_s_start, s) + _km, g_rhs]

## True if key_a sorts before key_b: primary value first, tiebreak second.
static func _key_less_than(key_a: Array, key_b: Array) -> bool:
	if key_a[0] != key_b[0]:
		return key_a[0] < key_b[0]
	return key_a[1] < key_b[1]

## Recomputes rhs(u) from its neighbors' current g values, then keeps the
## open queue consistent: u is only queued while locally inconsistent
## (g != rhs), exactly the vertices _compute_shortest_path() still needs to
## look at.
func _update_vertex(grid: Grid, u: Vector2i) -> void:
	if u != _s_goal:
		var best: float = INF
		for neighbor_info in _get_neighbors(grid, u):
			var candidate: float = neighbor_info["cost"] + _g.get(neighbor_info["cell"], INF)
			if candidate < best:
				best = candidate
		_rhs[u] = best

	_pqueue.erase(u)
	if _g.get(u, INF) != _rhs.get(u, INF):
		_insert_pqueue(u, _calculate_key(u))

## Repairs the open queue until the start is locally consistent and nothing
## queued could still improve it, the actual search step. After a small
## local change this only touches a handful of cells, after a fresh
## _initialize() it behaves like a full search, same total cost as A*.
func _compute_shortest_path(grid: Grid) -> void:
	while not _pqueue.is_empty():
		var start_key: Array = _calculate_key(_s_start)
		var top_key: Array = _pqueue_top_key()
		var start_consistent: bool = _rhs.get(_s_start, INF) == _g.get(_s_start, INF)
		if not _key_less_than(top_key, start_key) and start_consistent:
			break

		var popped: Dictionary = _pop_pqueue()
		var u: Vector2i = popped["cell"]
		var k_old: Array = popped["key"]
		explored_cells.append(u) # record for visualization/comparison

		var k_new: Array = _calculate_key(u)
		if _key_less_than(k_old, k_new):
			_insert_pqueue(u, k_new)
		elif _g.get(u, INF) > _rhs.get(u, INF):
			_g[u] = _rhs[u]
			for neighbor_info in _get_neighbors(grid, u):
				_update_vertex(grid, neighbor_info["cell"])
		else:
			_g[u] = INF
			for neighbor_info in _get_neighbors(grid, u):
				_update_vertex(grid, neighbor_info["cell"])
			_update_vertex(grid, u)

func _insert_pqueue(cell: Vector2i, key: Array) -> void:
	_pqueue[cell] = key

## Removes and returns the queued cell with the smallest key, linear scan,
## only called while _pqueue is known to be non-empty.
func _pop_pqueue() -> Dictionary:
	var best_cell: Vector2i
	var best_key: Array = []
	var is_first: bool = true
	for cell in _pqueue:
		var key: Array = _pqueue[cell]
		if is_first or _key_less_than(key, best_key):
			best_key = key
			best_cell = cell
			is_first = false
	_pqueue.erase(best_cell)
	return {"cell": best_cell, "key": best_key}

## Smallest key currently queued, only called while _pqueue is known non-empty.
func _pqueue_top_key() -> Array:
	var best_key: Array = []
	var is_first: bool = true
	for cell in _pqueue:
		var key: Array = _pqueue[cell]
		if is_first or _key_less_than(key, best_key):
			best_key = key
			is_first = false
	return best_key

## Greedily follows the smallest g-value neighbor from start to goal. D*
## Lite never builds a came_from map like AStarPathfinder does, g itself
## already encodes the whole route once _compute_shortest_path() is done.
func _reconstruct_path(grid: Grid) -> Array[Vector2i]:
	if _g.get(_s_start, INF) == INF:
		return [] # start never reached the goal, unreachable

	var path: Array[Vector2i] = [_s_start]
	var current: Vector2i = _s_start
	while current != _s_goal:
		var best_neighbor: Vector2i = current
		var best_cost: float = INF
		var found_any: bool = false
		for neighbor_info in _get_neighbors(grid, current):
			var total: float = neighbor_info["cost"] + _g.get(neighbor_info["cell"], INF)
			if total < best_cost:
				best_cost = total
				best_neighbor = neighbor_info["cell"]
				found_any = true
		if not found_any:
			return []
		path.append(best_neighbor)
		current = best_neighbor
	return path

## Copies grid's current walkable layout so the next call can tell which
## cells actually changed since this one, instead of assuming everything
## needs rechecking.
func _snapshot_walkable(grid: Grid) -> void:
	_known_walkable.resize(grid.columns)
	for x in grid.columns:
		var column: Array = []
		column.resize(grid.rows)
		for y in grid.rows:
			column[y] = grid.is_walkable(Vector2i(x, y))
		_known_walkable[x] = column

## Compares grid's current walkable state against the last snapshot, cell
## by cell. The saving D* Lite makes is in how few of these changed cells'
## surroundings _compute_shortest_path() then has to reprocess, not in
## detecting them.
func _diff_and_resync_walkable(grid: Grid) -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	for x in grid.columns:
		for y in grid.rows:
			var cell := Vector2i(x, y)
			var now: bool = grid.is_walkable(cell)
			if now != _known_walkable[x][y]:
				changed.append(cell)
				_known_walkable[x][y] = now
	return changed

## Every walkable neighbor of cell (8 directions, corner-cutting blocked
## the same way as AStarPathfinder), paired with its move cost.
func _get_neighbors(grid: Grid, cell: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for offset in NEIGHBOR_OFFSETS:
		var neighbor: Vector2i = cell + offset
		if not grid.is_walkable(neighbor):
			continue
		if not Pathfinder.diagonal_move_allowed(grid, cell, offset):
			continue
		result.append({"cell": neighbor, "cost": Pathfinder.move_cost(offset)})
	return result
