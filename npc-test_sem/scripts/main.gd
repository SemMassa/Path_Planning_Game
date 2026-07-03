extends Node2D
## Wires the Grid and NPC together. Walls come entirely from the maze
## generator now, so left click no longer edits the map, it alternates
## between placing the NPC's spawn point and sending it to a goal.
## Right click is currently unused.

var _obstacle_pathfinder: Pathfinder = AStarPathfinder.new()

# True once a spawn point has been placed and we are waiting for the
# matching left click that sets the goal. False means the next left
# click places a new spawn point instead.
var _awaiting_goal_click: bool = false

@onready var grid: Grid = $Grid
@onready var npc: NPC = $Grid/NPC
@onready var obstacle: Obstacle = $Grid/Obstacle

## Generates a maze layout, places the NPC in its first room, sends the
## obstacle patrolling between two other rooms through the real corridors,
## resizes the window to fit, and starts listening for grid clicks.
func _ready() -> void:
	_fit_window_to_grid()

	var maze := MazeGenerator.new()
	var maze_data: Array = maze.generate(grid.columns, grid.rows)
	grid.load_walkable_map(maze_data)

	npc.grid = grid
	npc.pathfinder = AStarPathfinder.new() # its own instance, BlockState uses it independently
	npc.obstacles = [obstacle] # what NPC's own collision check tests against each step
	npc.place_at(maze.room_center(0))

	obstacle.grid = grid
	var patrol_from: Vector2i = maze.room_center(1)
	var patrol_to: Vector2i = maze.room_center(maze.room_count() - 1)
	var patrol_route: Array[Vector2i] = _obstacle_pathfinder.find_path(grid, patrol_from, patrol_to)
	obstacle.start_path(patrol_from, patrol_route) # patrol_from: room center, always walkable

	grid.cell_clicked.connect(_on_cell_clicked)

## Every other left click places a new spawn point, the ones in between
## set the goal and send the NPC there. Right click currently does nothing.
func _on_cell_clicked(cell: Vector2i, mouse_button: int) -> void:
	if mouse_button != MOUSE_BUTTON_LEFT:
		return

	if not _awaiting_goal_click:
		if not grid.is_walkable(cell):
			return # ignore clicks on walls, keep waiting for a valid spawn
		npc.place_at(cell)
		grid.clear_search_result() # old path started from the old spawn point
		_awaiting_goal_click = true
	else:
		npc.go_to(cell)
		grid.show_search_result(npc.pathfinder.explored_cells, npc.current_path())
		_awaiting_goal_click = false

## Sets the window to exactly grid.columns x grid.rows cells, in pixels,
## so the whole grid is always visible, no matter how large it is set to.
func _fit_window_to_grid() -> void:
	get_window().size = Vector2i(grid.columns * grid.cell_size, grid.rows * grid.cell_size)
