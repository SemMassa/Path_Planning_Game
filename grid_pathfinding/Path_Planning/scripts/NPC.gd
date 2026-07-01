# NPC.gd
# A NavigationAgent that moves through the grid using A* pathfinding.
#
# Behavior:
#   - Follows a computed path toward a target grid cell
#   - Recalculates the path every PATH_RECALC_INTERVAL seconds
#     to react to moving obstacles blocking the way
#   - Stops at the target and waits (does not loop back)
#
# Scene setup:
#   CharacterBody2D
#   ├── CollisionShape2D  (RectangleShape2D, size 24x24)
#   └── visual drawn via _draw()

class_name NPC
extends CharacterBody2D

# Movement speed in pixels per second
const MOVE_SPEED: float = 90.0

# How often the path is recalculated (seconds)
const PATH_RECALC_INTERVAL: float = 1.2

# How close (px) the NPC must be to a waypoint before advancing
const WAYPOINT_REACH_DISTANCE: float = 3.0

# Visual radius (color is set per-instance via setup())
const VISUAL_RADIUS:    float = 10.0
const PATH_LINE_WIDTH:  float = 1.5   # px width of the planned-path line

# Toggle path visualization on/off at runtime
var show_path: bool = true

# Instance color — set by Main.gd so each NPC has a distinct color
# that matches its particle trail
var body_color:    Color = Color(0.20, 0.45, 0.85)
var outline_color: Color = Color(0.10, 0.20, 0.50)

var grid_manager:    GridManager
var target_grid_pos: Vector2i

var _path:         PackedVector2Array = []
var _path_index:   int   = 0
var _recalc_timer: float = 0.0
var _arrived:      bool  = false   # true once the NPC has reached the target


# ---- Public API -----------------------------------------------------------

# Call once after adding to the scene tree.
# color: body color (should match the NPCTrail color assigned in Main.gd)
func setup(gm: GridManager, target: Vector2i, color: Color = Color(0.20, 0.45, 0.85)) -> void:
	grid_manager    = gm
	target_grid_pos = target
	_arrived        = false
	body_color      = color
	# Derive a darker outline from the body color
	outline_color   = Color(color.r * 0.5, color.g * 0.5, color.b * 0.5)
	_calculate_path()


# Change the NPC's destination at runtime and resume movement.
func set_target(new_target: Vector2i) -> void:
	target_grid_pos = new_target
	_arrived        = false
	_calculate_path()


# ---- Godot callbacks ------------------------------------------------------

func _process(delta: float) -> void:
	if _arrived:
		return

	_recalc_timer += delta
	if _recalc_timer >= PATH_RECALC_INTERVAL:
		_recalc_timer = 0.0
		_calculate_path()

	_follow_path(delta)


func _draw() -> void:
	draw_circle(Vector2.ZERO, VISUAL_RADIUS, body_color)
	draw_arc(Vector2.ZERO, VISUAL_RADIUS, 0.0, TAU, 16, outline_color, 1.5)


# ---- Private --------------------------------------------------------------

func _calculate_path() -> void:
	var my_grid := grid_manager.world_to_grid(global_position)

	# Already at the target — no path needed
	if my_grid == target_grid_pos:
		_path       = PackedVector2Array()
		_path_index = 0
		_arrived    = true
		return

	var new_path := grid_manager.find_path(my_grid, target_grid_pos)
	_path = new_path

	# Start from the nearest waypoint among the first few entries.
	# This prevents the NPC from snapping back to an earlier position
	# when the path is recalculated while already past the first waypoint.
	_path_index = 0
	if _path.size() > 1:
		var min_dist := global_position.distance_squared_to(_path[0])
		for i in range(1, min(_path.size(), 3)):
			var d := global_position.distance_squared_to(_path[i])
			if d < min_dist:
				min_dist    = d
				_path_index = i


func _follow_path(delta: float) -> void:
	if _path_index >= _path.size():
		# Path exhausted — check if we actually arrived
		var my_grid := grid_manager.world_to_grid(global_position)
		if my_grid == target_grid_pos:
			_arrived = true
		return

	var waypoint := _path[_path_index]
	var distance  := global_position.distance_to(waypoint)

	if distance < WAYPOINT_REACH_DISTANCE:
		global_position = waypoint
		_path_index    += 1
	else:
		var direction := (waypoint - global_position).normalized()
		global_position += direction * MOVE_SPEED * delta

	queue_redraw()
