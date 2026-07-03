class_name Obstacle
extends AnimatableBody2D
## Patrols back and forth along a fixed list of cells (ping pong). Blocks the
## cell it is currently in and frees the one it just left, exactly when its
## visible position crosses into a new cell, so the map always matches what
## is actually on screen. Must be parented under a Grid node, same as NPC.
##
## Drawn as its own orange square (see _draw() below) rather than only
## showing up as a blocked grid cell: an occupied cell used to be painted
## the same black as a real wall, which made the Obstacle look like it was
## merging into and walking through walls whenever it passed one.
##
## AnimatableBody2D instead of plain Node2D: it is Godot's node meant for a
## solid that a script moves directly (not through physics forces). Plain
## Node2D has no CollisionShape2D at all, so there would be nothing for
## NPC's hand written collision check (see collision_system.gd) to read.
##
## Godot's physics engine itself is not used to detect collisions against
## this obstacle. collision_box() below only hands the raw shape data to
## NPC, which runs its own narrow phase test with it.

@export var speed: float = 100.0 # pixels per second
@export var waypoint_reach_distance: float = 2.0 # px, when to snap onto a waypoint

var grid: Grid
var waypoints: Array[Vector2i] = []

var _waypoint_index: int = 0 # waypoint we are currently heading toward
var _committed_index: int = 0 # waypoint we most recently fully reached
var _direction: int = 1 # 1 = forward, -1 = backward through waypoints
var _last_cell: Vector2i = Vector2i(-1, -1)

@onready var _collision_shape: CollisionShape2D = $CollisionShape2D

## Places the Obstacle at spawn_cell, always, then starts patrolling path
## if it actually has one. spawn_cell must already be walkable (the caller
## picks it, e.g. a room center). Placement no longer depends on path
## being usable: if pathfinding fails and returns an empty (or single
## cell) route, the Obstacle still ends up sitting at a real floor cell
## instead of wherever its Node2D happened to start out in the scene,
## which could just as easily have been an actual wall cell.
func start_path(spawn_cell: Vector2i, path: Array[Vector2i]) -> void:
	waypoints = path
	position = grid.cell_to_world_center(spawn_cell)
	_last_cell = spawn_cell
	grid.set_cell_occupied(_last_cell, true)

	_committed_index = 0
	_waypoint_index = _next_valid_index(0, 1) if waypoints.size() > 1 else 0

## Slides toward the next waypoint, then updates which cell is blocked.
## Checks every frame whether the target is still walkable, so a wall
## placed on the route mid patrol turns the obstacle back instead of
## letting it walk straight through. Runs in _physics_process, same tick
## NPC's own hand written collision check reads this obstacle's position.
func _physics_process(delta: float) -> void:
	if waypoints.size() < 2:
		return

	# Ignore our own footprint: _update_blocked_cell() may have already
	# marked the target as "not walkable" simply because we just stepped
	# into it, that is not an external wall and must not trigger a bounce.
	var target_is_walled: bool = (
		waypoints[_waypoint_index] != _last_cell
		and not grid.is_walkable(waypoints[_waypoint_index])
	)
	if target_is_walled:
		_waypoint_index = _next_valid_index(_committed_index, -_direction)

	var target_pos: Vector2 = grid.cell_to_world_center(waypoints[_waypoint_index])
	var to_target: Vector2 = target_pos - position
	if to_target.length() < waypoint_reach_distance:
		position = target_pos
		_committed_index = _waypoint_index
		_waypoint_index = _next_valid_index(_committed_index, _direction)
	else:
		position += to_target.normalized() * speed * delta

	_update_blocked_cell()
	queue_redraw()

## Picks the next waypoint index from from_index, preferring direction and
## bouncing to the opposite one if that side is out of range or walled off.
## Updates _direction to whichever way it actually decided to go.
func _next_valid_index(from_index: int, direction: int) -> int:
	var forward: int = from_index + direction
	if _is_valid_waypoint(forward):
		_direction = direction
		return forward

	var backward: int = from_index - direction
	if _is_valid_waypoint(backward):
		_direction = -direction
		return backward

	return from_index # walled in on both sides, stay put and retry next frame

## True if index is a real waypoint and its cell is currently walkable.
## A user placed wall could have appeared on the route since it was planned.
func _is_valid_waypoint(index: int) -> bool:
	return index >= 0 and index < waypoints.size() and grid.is_walkable(waypoints[index])

## Frees the cell left behind and blocks the cell just entered, only when
## the current position actually falls into a different cell than before.
func _update_blocked_cell() -> void:
	var current_cell: Vector2i = grid.world_to_cell(position)
	if current_cell == _last_cell:
		return
	grid.set_cell_occupied(_last_cell, false)
	_last_cell = current_cell
	grid.set_cell_occupied(current_cell, true)

## Current world space bounding box, read straight from the RectangleShape2D
## assigned in Obstacle.tscn. This never rotates, so shape.size centered on
## global_position is exactly its AABB, no further math needed.
func collision_box() -> Rect2:
	var shape: RectangleShape2D = _collision_shape.shape
	return Rect2(global_position - shape.size / 2.0, shape.size)

## Draws the obstacle itself as a solid orange square matching its
## CollisionShape2D, so it stays visible as a distinct shape moving at its
## real, continuous position, not just as a discolored grid cell.
func _draw() -> void:
	var half_size: Vector2 = (_collision_shape.shape as RectangleShape2D).size / 2.0
	draw_rect(Rect2(-half_size, half_size * 2.0), Color(1.0, 0.55, 0.1))
