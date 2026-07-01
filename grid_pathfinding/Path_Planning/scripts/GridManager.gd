# GridManager.gd
# Central authority for the grid:
#   - Stores the room layout (walls / floors)
#   - Owns and maintains the AStarGrid2D instance
#   - Renders the grid visually via _draw()
#   - Converts between world-space and grid-space coordinates
#   - Manages START / END markers set by the player
#
# Attach this script to a Node2D in your scene tree.
# Call setup(maze_data) once after generating the layout.

class_name GridManager
extends Node2D

# Pixel size of one grid cell
const CELL_SIZE: int = 32

# ---- Visual colors --------------------------------------------------------
const COLOR_WALL:      Color = Color(0.13, 0.13, 0.22)
const COLOR_FLOOR:     Color = Color(0.86, 0.81, 0.73)
const COLOR_GRID_LINE: Color = Color(0.68, 0.63, 0.58, 0.45)
const COLOR_START:     Color = Color(0.20, 0.75, 0.30)   # green = spawn
const COLOR_END:       Color = Color(0.85, 0.25, 0.20)   # red   = goal
# ---------------------------------------------------------------------------

var grid:        Array   # 2D array of int (MazeGenerator.EMPTY / WALL / …)
var grid_width:  int
var grid_height: int
var astar:       AStarGrid2D

# Tracks which cells are currently marked so we can clear them later
var _marked_start: Vector2i = Vector2i(-1, -1)
var _marked_end:   Vector2i = Vector2i(-1, -1)


# ---- Public API -----------------------------------------------------------

# Initialize the grid from a 2D array produced by MazeGenerator.
func setup(maze_data: Array) -> void:
	grid        = maze_data
	grid_height = grid.size()
	grid_width  = grid[0].size() if grid_height > 0 else 0
	_init_astar()
	queue_redraw()


# Returns a world-space path from one grid cell to another.
# Returns an empty array if no path exists or positions are out of bounds.
# NOTE: named find_path to avoid collision with Node.get_path()
func find_path(from_grid: Vector2i, to_grid: Vector2i) -> PackedVector2Array:
	if not astar.is_in_boundsv(from_grid) or not astar.is_in_boundsv(to_grid):
		return PackedVector2Array()
	if astar.is_point_solid(from_grid) or astar.is_point_solid(to_grid):
		return PackedVector2Array()
	return astar.get_point_path(from_grid, to_grid)


# Mark a grid cell as solid (blocked) or passable in the A* graph.
# Used by MovingObstacle to dynamically update the graph.
func set_point_solid(grid_pos: Vector2i, solid: bool) -> void:
	if astar.is_in_boundsv(grid_pos):
		astar.set_point_solid(grid_pos, solid)


# Place the START marker on a floor cell; clears the previous marker.
# Returns false if the cell is a wall or out of bounds.
func mark_start(grid_pos: Vector2i) -> bool:
	if not _is_floor(grid_pos):
		return false
	if _marked_start != Vector2i(-1, -1):
		grid[_marked_start.y][_marked_start.x] = MazeGenerator.EMPTY
	_marked_start = grid_pos
	grid[grid_pos.y][grid_pos.x] = MazeGenerator.START
	queue_redraw()
	return true


# Place the END marker on a floor cell; clears the previous marker.
# Returns false if the cell is a wall, out of bounds, or same as start.
func mark_end(grid_pos: Vector2i) -> bool:
	if not _is_floor(grid_pos):
		return false
	if grid_pos == _marked_start:
		return false
	if _marked_end != Vector2i(-1, -1):
		grid[_marked_end.y][_marked_end.x] = MazeGenerator.EMPTY
	_marked_end = grid_pos
	grid[grid_pos.y][grid_pos.x] = MazeGenerator.END
	queue_redraw()
	return true


# Remove both markers and restore their cells to EMPTY.
func clear_markers() -> void:
	if _marked_start != Vector2i(-1, -1):
		grid[_marked_start.y][_marked_start.x] = MazeGenerator.EMPTY
		_marked_start = Vector2i(-1, -1)
	if _marked_end != Vector2i(-1, -1):
		grid[_marked_end.y][_marked_end.x] = MazeGenerator.EMPTY
		_marked_end = Vector2i(-1, -1)
	queue_redraw()


# Returns true if the cell is within bounds and not a wall.
func is_walkable(grid_pos: Vector2i) -> bool:
	return _is_floor(grid_pos)


# Convert a world position to the nearest grid cell.
func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(world_pos.x / CELL_SIZE),
		int(world_pos.y / CELL_SIZE)
	)


# Convert a grid cell to its world-space center position.
func grid_to_world_center(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		grid_pos.x * CELL_SIZE + CELL_SIZE * 0.5,
		grid_pos.y * CELL_SIZE + CELL_SIZE * 0.5
	)


# Returns all walkable (EMPTY) cells as grid coordinates.
func get_empty_cells() -> Array:
	var cells: Array = []
	for y in grid_height:
		for x in grid_width:
			if grid[y][x] == MazeGenerator.EMPTY:
				cells.append(Vector2i(x, y))
	return cells


# ---- Private --------------------------------------------------------------

# True when a cell is in bounds and contains a walkable tile (not a wall).
func _is_floor(grid_pos: Vector2i) -> bool:
	if grid_pos.x < 0 or grid_pos.x >= grid_width:
		return false
	if grid_pos.y < 0 or grid_pos.y >= grid_height:
		return false
	return grid[grid_pos.y][grid_pos.x] != MazeGenerator.WALL


func _init_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region        = Rect2i(0, 0, grid_width, grid_height)
	astar.cell_size     = Vector2(CELL_SIZE, CELL_SIZE)
	# Shift returned path positions to cell centers
	astar.offset        = Vector2(CELL_SIZE * 0.5, CELL_SIZE * 0.5)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()

	# Mark all wall cells as solid in the A* graph
	for y in grid_height:
		for x in grid_width:
			if grid[y][x] == MazeGenerator.WALL:
				astar.set_point_solid(Vector2i(x, y), true)


func _draw() -> void:
	if grid.is_empty():
		return

	for y in grid_height:
		for x in grid_width:
			var rect := Rect2(x * CELL_SIZE, y * CELL_SIZE, CELL_SIZE, CELL_SIZE)
			var cell: int = grid[y][x]

			if cell == MazeGenerator.WALL:
				draw_rect(rect, COLOR_WALL)
			elif cell == MazeGenerator.START:
				draw_rect(rect, COLOR_START)
			elif cell == MazeGenerator.END:
				draw_rect(rect, COLOR_END)
			else:
				draw_rect(rect, COLOR_FLOOR)
				# Subtle grid lines on floor cells
				draw_rect(rect, COLOR_GRID_LINE, false, 0.5)
