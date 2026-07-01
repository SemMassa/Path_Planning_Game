# MovingObstacle.gd
# A dynamic obstacle that moves along a precomputed path (ping-pong).
#
# Integration with A*:
#   - Marks its current grid cell as solid when it enters it
#   - Clears the previous cell when leaving
#   This forces NPCs to recalculate around the obstacle.
#
# Scene setup:
#   Node2D  (this script)
#   └── (optional) collision — add StaticBody2D child if physics collisions needed

class_name MovingObstacle
extends Node2D

# Movement speed in pixels per second
const MOVE_SPEED: float = 55.0

# How close (px) to a waypoint before advancing to the next
const WAYPOINT_REACH_DISTANCE: float = 2.0

# Visual appearance (drawn via _draw)
const VISUAL_HALF_SIZE: float = 11.0
const COLOR_FILL:       Color = Color(0.754, 0.137, 0.842, 1.0)
const COLOR_OUTLINE:    Color = Color(0.45, 0.10, 0.08)

var grid_manager: GridManager
var waypoints:    Array  # Array of Vector2i — grid positions along the path

var _waypoint_index: int     = 0
var _direction:      int     = 1      # 1 = forward, -1 = backward (ping-pong)
var _last_grid_pos:  Vector2i = Vector2i(-1, -1)


# ---- Public API -----------------------------------------------------------

# Call once after adding to the scene tree.
# wps: Array[Vector2i] — a sequence of connected empty grid cells
func setup(gm: GridManager, wps: Array) -> void:
	grid_manager = gm
	waypoints    = wps

	if waypoints.is_empty():
		return

	global_position = grid_manager.grid_to_world_center(waypoints[0])
	_block_current_cell()


# ---- Godot callbacks ------------------------------------------------------

func _process(delta: float) -> void:
	if waypoints.size() < 2:
		return

	var target_world := grid_manager.grid_to_world_center(waypoints[_waypoint_index])
	var distance      := global_position.distance_to(target_world)

	if distance < WAYPOINT_REACH_DISTANCE:
		global_position = target_world
		_advance_waypoint()
	else:
		var dir := (target_world - global_position).normalized()
		global_position += dir * MOVE_SPEED * delta

	# Update A* whenever the obstacle crosses into a new cell
	var current_grid := grid_manager.world_to_grid(global_position)
	if current_grid != _last_grid_pos:
		grid_manager.set_point_solid(_last_grid_pos, false)
		_last_grid_pos = current_grid
		grid_manager.set_point_solid(current_grid, true)

	queue_redraw()


func _draw() -> void:
	var hs := VISUAL_HALF_SIZE
	draw_rect(Rect2(-hs, -hs, hs * 2.0, hs * 2.0), COLOR_FILL)
	draw_rect(Rect2(-hs, -hs, hs * 2.0, hs * 2.0), COLOR_OUTLINE, false, 1.5)


# ---- Private --------------------------------------------------------------

func _advance_waypoint() -> void:
	_waypoint_index += _direction

	# Reverse direction at the ends (ping-pong)
	if _waypoint_index >= waypoints.size():
		_direction      = -1
		_waypoint_index = waypoints.size() - 2
	elif _waypoint_index < 0:
		_direction      = 1
		_waypoint_index = 1


func _block_current_cell() -> void:
	var grid_pos := grid_manager.world_to_grid(global_position)
	grid_manager.set_point_solid(grid_pos, true)
	_last_grid_pos = grid_pos
