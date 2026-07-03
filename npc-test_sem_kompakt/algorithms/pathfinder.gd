class_name Pathfinder
extends RefCounted
## Common interface for every pathfinding strategy. Subclasses get swapped
## in at runtime so they can be compared on the same Grid. Also holds the
## octile distance math shared by every subclass (all use the same 8
## direction, diagonal cost, grid).

## How an NPC should react when its path gets blocked (see WalkState /
## BlockState / RetreatState). RETREAT: step back along the already found
## path until it clears, then resume it (plain A*, JPS). REPLAN: recompute a
## fresh route from the current position (D* Lite).
enum BlockReaction { RETREAT, REPLAN }

const ORTHOGONAL_COST: float = 1.0
const DIAGONAL_COST: float = 1.41421356 # sqrt(2)

## Every cell expanded during the last find_path() call, in expansion
## order. Filled in by subclasses, used to visualize the search.
var explored_cells: Array[Vector2i] = []

## Cells from start to goal, inclusive. Empty if unreachable.
func find_path(_grid: Grid, _start: Vector2i, _goal: Vector2i) -> Array[Vector2i]:
	push_error("find_path() not implemented, override in a subclass")
	return []

## Defaults to REPLAN, the safer choice for an algorithm that forgets to
## override this.
func block_reaction() -> BlockReaction:
	return BlockReaction.REPLAN

## Cost of one step: more for diagonal moves than orthogonal ones.
static func move_cost(offset: Vector2i) -> float:
	return DIAGONAL_COST if offset.x != 0 and offset.y != 0 else ORTHOGONAL_COST

## Octile distance: the true cheapest cost between two cells on an 8
## directional grid, so it never overestimates (admissible heuristic).
static func octile_heuristic(a: Vector2i, b: Vector2i) -> float:
	var dx: int = absi(a.x - b.x)
	var dy: int = absi(a.y - b.y)
	return ORTHOGONAL_COST * maxi(dx, dy) + (DIAGONAL_COST - ORTHOGONAL_COST) * mini(dx, dy)

## Removes and returns the cell in open_list with the lowest f_score
## (g_score + heuristic to goal). Linear scan, fine for this project's grid
## sizes; a binary heap would be the next optimization step for much
## larger grids.
static func pop_lowest_f_score(
	open_list: Array[Vector2i], g_score: Dictionary, goal: Vector2i
) -> Vector2i:
	var best_index: int = 0
	var best_f: float = g_score[open_list[0]] + octile_heuristic(open_list[0], goal)
	for i in range(1, open_list.size()):
		var f: float = g_score[open_list[i]] + octile_heuristic(open_list[i], goal)
		if f < best_f:
			best_f = f
			best_index = i
	return open_list.pop_at(best_index)

## Blocks diagonal moves that would cut through a wall corner.
static func diagonal_move_allowed(grid: Grid, current: Vector2i, offset: Vector2i) -> bool:
	if offset.x == 0 or offset.y == 0:
		return true # orthogonal move, no corner to check
	var side_a := Vector2i(current.x + offset.x, current.y)
	var side_b := Vector2i(current.x, current.y + offset.y)
	return grid.is_walkable(side_a) and grid.is_walkable(side_b)
