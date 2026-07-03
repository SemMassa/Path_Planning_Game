class_name Grid
extends Node2D
## Grid of walkable/blocked cells.
## Draws itself and reports clicks so walls and the goal can be set at runtime.

signal cell_clicked(cell: Vector2i, mouse_button: int)

@export var columns: int = 20
@export var rows: int = 15
@export var cell_size: int = 32

var _walkable: Array = [] # Array[Array[bool]], indexed [x][y], the static maze layout

# Cells a moving Obstacle currently stands on. Kept separate from _walkable
# so a temporarily occupied cell can be drawn differently from an actual
# permanent wall. The two used to share one array and one color (black),
# which made a patrolling Obstacle look like it was merging into and
# walking through real walls whenever it passed one.
var _blocked_cells: Dictionary = {} # Vector2i -> true

# Debug overlay data from the last pathfinding run.
# _explored_cells is an unordered set (keys matter, values are unused),
# _path keeps its order since it gets drawn as a connected line.
var _explored_cells: Dictionary = {}
var _path: Array[Vector2i] = []

## Builds the [columns][rows] table and marks every cell walkable at start.
func _ready() -> void:
	_walkable.resize(columns)
	for x in columns:
		var walkable_column: Array = []
		walkable_column.resize(rows)
		walkable_column.fill(true)
		_walkable[x] = walkable_column

## True if the cell lies within the grid bounds (ignores wall state).
func is_inside_grid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < columns and cell.y >= 0 and cell.y < rows

## True if the cell exists, is not a wall, and no Obstacle is currently on it.
func is_walkable(cell: Vector2i) -> bool:
	return is_inside_grid(cell) and _walkable[cell.x][cell.y] and not _blocked_cells.has(cell)

## Marks a single cell wall or floor, then repaints the grid. For the
## permanent maze layout, not for an Obstacle's own footprint, that goes
## through set_cell_occupied() instead so the two can be told apart.
func set_walkable(cell: Vector2i, walkable: bool) -> void:
	if is_inside_grid(cell):
		_walkable[cell.x][cell.y] = walkable
		queue_redraw()

## Flips a cell between wall and walkable, used by left click.
func toggle_wall(cell: Vector2i) -> void:
	set_walkable(cell, not is_walkable(cell))

## Marks a cell as currently stood on by a moving Obstacle (or clears that),
## without touching the underlying wall layout. is_walkable() treats an
## occupied cell the same as a wall, but _cell_color() paints it differently.
func set_cell_occupied(cell: Vector2i, occupied: bool) -> void:
	if not is_inside_grid(cell):
		return
	if occupied:
		_blocked_cells[cell] = true
	else:
		_blocked_cells.erase(cell)
	queue_redraw()

## Replaces the whole walkable map at once, e.g. with a MazeGenerator
## result. data must already be sized [columns][rows], same layout as
## the internal table.
func load_walkable_map(data: Array) -> void:
	_walkable = data
	queue_redraw()

## Converts a pixel position (local space) to the cell it falls into.
func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / cell_size), floori(world_pos.y / cell_size))

## Converts a cell to the pixel position of its center, used for movement targets.
func cell_to_world_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * cell_size + cell_size * 0.5, cell.y * cell_size + cell_size * 0.5)

## Stores the last search result for the debug overlay and repaints.
func show_search_result(explored: Array[Vector2i], path: Array[Vector2i]) -> void:
	_explored_cells.clear()
	for cell in explored:
		_explored_cells[cell] = true
	_path = path
	queue_redraw()

## Removes the debug overlay, used whenever the map changes and the
## previous search result no longer reflects reality.
func clear_search_result() -> void:
	_explored_cells.clear()
	_path = []
	queue_redraw()

## Picks the fill color for one cell: explored cells get a tint, a cell an
## Obstacle currently stands on gets its own tint (so it never reads as a
## real wall), everything else is plain walkable/wall.
func _cell_color(cell: Vector2i) -> Color:
	if _explored_cells.has(cell):
		return Color(0.55, 0.75, 0.95) # considered by the algorithm: light blue
	if _blocked_cells.has(cell):
		return Color(1.0, 0.55, 0.1) # Obstacle footprint: orange, not a real wall
	return Color.WHITE if _walkable[cell.x][cell.y] else Color.BLACK

## Draws the final path as a connected line through each cell's center.
func _draw_path() -> void:
	if _path.size() < 2:
		return
	var points: PackedVector2Array = []
	for cell in _path:
		points.append(cell_to_world_center(cell))
	draw_polyline(points, Color(1.0, 0.3, 0.1), 4.0)

## Paints every cell using _cell_color(), a thin grid outline, then the path on top.
func _draw() -> void:
	for x in columns:
		for y in rows:
			var cell := Vector2i(x, y)
			var rect := Rect2(x * cell_size, y * cell_size, cell_size, cell_size)
			draw_rect(rect, _cell_color(cell), true)
			draw_rect(rect, Color(0.6, 0.6, 0.6), false)
	_draw_path()

## Translates raw mouse clicks into a grid cell and forwards them as a signal.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var cell := world_to_cell(get_local_mouse_position())
		if is_inside_grid(cell):
			cell_clicked.emit(cell, event.button_index)
