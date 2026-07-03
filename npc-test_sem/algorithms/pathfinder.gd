class_name Pathfinder
extends RefCounted
## Common interface for every pathfinding strategy.
## Subclasses get swapped in at runtime so they can be compared on the same Grid.

## Every cell the algorithm expanded during the last find_path() call, in
## expansion order. Subclasses fill this in, used to visualize the search.
var explored_cells: Array[Vector2i] = []

## Returns cells from start to goal, inclusive. Empty array if unreachable.
## Base class has no algorithm; every real strategy overrides this.
func find_path(_grid: Grid, _start: Vector2i, _goal: Vector2i) -> Array[Vector2i]:
	push_error("find_path() not implemented, override in a subclass")
	return []
