class_name Pathfinder
extends RefCounted
## Common interface for every pathfinding strategy.
## Subclasses get swapped in at runtime so they can be compared on the same Grid.

## How an NPC using this algorithm should react to its path being blocked
## (see WalkState/RetreatState/BlockState). RETREAT: never replan, step
## backward along the already computed path until it clears, then resume
## forward on that same path, the intended demo behavior for a plain A*
## search. REPLAN: recompute a fresh route from the current position, for
## algorithms actually meant to react to a changed graph (e.g. D* Lite).
enum BlockReaction { RETREAT, REPLAN }

## Every cell the algorithm expanded during the last find_path() call, in
## expansion order. Subclasses fill this in, used to visualize the search.
var explored_cells: Array[Vector2i] = []

## Returns cells from start to goal, inclusive. Empty array if unreachable.
## Base class has no algorithm; every real strategy overrides this.
func find_path(_grid: Grid, _start: Vector2i, _goal: Vector2i) -> Array[Vector2i]:
	push_error("find_path() not implemented, override in a subclass")
	return []

## Defaults to REPLAN so a future algorithm that forgets to override this
## still gets the safer, already working behavior instead of silently
## sitting stuck forever the first time something blocks its path.
func block_reaction() -> BlockReaction:
	return BlockReaction.REPLAN
