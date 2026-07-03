class_name NPC
extends CharacterBody2D
## Walks a path of grid cells, driven by a small finite state machine
## (FiniteStateMachine plus the states in scripts/states/). Must be
## parented under a Grid node so local coordinates line up.
##
## CharacterBody2D instead of plain Node2D: gives the NPC a real
## CollisionShape2D to read shape data from, on top of the existing grid
## based is_walkable() check, which still does the smart, proactive
## rerouting.
##
## Collision against Obstacles is NOT handled by Godot's physics engine,
## move_and_slide() is never called. Instead this script runs its own
## broad phase and narrow phase test (see collision_system.gd) between its
## own CircleShape2D and each Obstacle's RectangleShape2D (an AABB, since
## it never rotates), an AABB-Circle intersection test we wrote ourselves.

## Fired every time DoneState is entered, which happens on spawn placement,
## on an immediately unreachable goal, and on a genuine Race mode arrival
## alike. main.gd's benchmark tracking tells those apart itself (it only
## treats this as "arrived" while it is actively timing this NPC), rather
## than this signal trying to guess the caller's intent.
signal arrived

const FRAME_DURATION: float = 0.15 # seconds per sprite frame
const ARRIVAL_DISTANCE: float = 5.0 # px, close enough to a target cell to snap onto it

@export var speed: float = 250 # pixels per second
@export var visual_scale: float = 1.875 # sprite size multiplier, does not affect movement

# Which pre-colored sprite sheet to load, e.g. one color per algorithm, so
# several NPCs can be told apart without needing sprite.modulate to fake a
# tint on top of a single shared sheet. Must be set (see main.gd) before
# this NPC enters the tree, _ready() below reads it right away.
@export var sprite_sheet_path: String = "res://sprite_sheets/green_sprites.png"
@export var sprite_metadata_path: String = "res://sprite_sheets/green_sprites.json"

# This NPC's own accent color (see main.gd's ALGORITHM_COLORS), used only
# for its grid overlay (path + explored cells), not for the sprite itself
# anymore, that now comes from a real pre-colored sheet instead.
var accent_color: Color = Color.WHITE

var grid: Grid
var pathfinder: Pathfinder
var current_cell: Vector2i = Vector2i.ZERO
var obstacles: Array[Obstacle] = [] # patrolling obstacles to test against each step

# Life mode only: the three spots (A, B, C) to cycle between forever.
# Empty means Race mode, reaching the goal just stops at DoneState instead.
var life_spots: Array[Vector2i] = []

var _path: Array[Vector2i] = []
var _path_index: int = 0
var _goal_cell: Vector2i = Vector2i.ZERO
var _facing: String = "down" # last known movement direction, for idle poses
var _just_collided: bool = false # set by _check_obstacle_collisions() each step
var _life_spot_index: int = 0 # which life_spots entry was walked to most recently

@onready var sprite: Sprite2D = $Sprite2D
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var fsm: FiniteStateMachine = $FiniteStateMachine
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	sprite.scale = Vector2.ONE * visual_scale
	_load_sprite_animations(sprite_sheet_path, sprite_metadata_path)
	fsm.initialize(self)

## Computes a path to goal and starts walking it. Remembers goal so
## BlockState can recompute a fresh path from wherever the NPC currently
## is if the route gets blocked mid walk, only relevant for pathfinders
## whose block_reaction() is REPLAN, RetreatState never calls this.
func go_to(goal: Vector2i) -> void:
	_goal_cell = goal
	_set_path(pathfinder.find_path(grid, current_cell, goal))
	_update_grid_overlay()
	fsm.change_state("DoneState" if _path.is_empty() else "WalkState", {"facing": _facing})

## True once life_spots has been assigned (see main.gd), meaning this NPC
## should keep cycling A -> B -> C -> A ... instead of stopping at DoneState
## once it reaches a goal.
func is_in_life_mode() -> bool:
	return not life_spots.is_empty()

## Advances to the next spot in life_spots (wrapping back to A after C) and
## starts walking there. Called only by LifeWaitState, once its pause at
## the current spot elapses.
func go_to_next_life_spot() -> void:
	_life_spot_index = (_life_spot_index + 1) % life_spots.size()
	go_to(life_spots[_life_spot_index])

## Recomputes a route to the remembered goal from the current position.
## Only replaces the path data when a route is actually found, leaving
## the still-blocked path untouched on failure. Otherwise an empty path
## would satisfy path_finished() and get mistaken for "arrived" by
## whichever state calls this. The caller (BlockState) decides what FSM
## state to move to based on the returned success flag.
func recalculate_path() -> bool:
	var new_path: Array[Vector2i] = pathfinder.find_path(grid, current_cell, _goal_cell)
	if new_path.is_empty():
		return false
	_set_path(new_path)
	_update_grid_overlay()
	return true

## Keeps Grid's debug overlay (grid.gd's set_search_result()) showing this
## NPC's actual current path/explored cells. Called every time a fresh
## path is computed, not just once, so Life mode's ongoing A -> B -> C ...
## cycle and mid walk replans both stay reflected too, not just the very
## first path.
func _update_grid_overlay() -> void:
	grid.set_search_result(self, pathfinder.explored_cells, _path, accent_color)

## Teleports the NPC to cell right away and cancels any path in
## progress, used to set a new spawn point by clicking the grid.
func place_at(cell: Vector2i) -> void:
	current_cell = cell
	position = grid.cell_to_world_center(cell)
	_set_path([])
	fsm.change_state("DoneState", {"facing": _facing})

func current_path() -> Array[Vector2i]:
	return _path

## True once every cell in the path has been walked.
func path_finished() -> bool:
	return _path_index >= _path.size()

## The cell the NPC is currently walking toward.
func current_target_cell() -> Vector2i:
	return _path[_path_index]

## Last cardinal direction the NPC moved in, used to pick a matching
## walk/idle animation. Keeps its value while standing still.
func facing_direction() -> String:
	return _facing

## Moves one physics step toward the current target cell by hand (no
## engine physics involved), snaps to it once close enough, advances to
## the next cell, then runs our own collision check against every
## obstacle. Called by WalkState from _physics_process, the FSM decides
## when walking happens, not NPC itself.
func advance_step() -> void:
	var target_cell: Vector2i = _path[_path_index]
	var target_pos: Vector2 = grid.cell_to_world_center(target_cell)
	var to_target: Vector2 = target_pos - position

	if to_target.length() <= ARRIVAL_DISTANCE:
		position = target_pos
		current_cell = target_cell
		_path_index += 1
	else:
		_update_facing(to_target)
		var step: Vector2 = to_target.normalized() * speed * get_physics_process_delta_time()
		position += step

	_check_obstacle_collisions()

## True if this physics step's _check_obstacle_collisions() found an
## overlap (the Obstacle, in practice, maze walls have no shape at all).
func just_collided() -> bool:
	return _just_collided

## Moves one physics step backward toward the previous path cell, the
## mirror image of advance_step(). Used only by RetreatState, for
## algorithms whose Pathfinder.block_reaction() is RETREAT: the NPC never
## replans, it just steps back along the path it already computed until
## the way forward clears, then resumes on that same path. Returns false
## without moving once path_index is already 0, nowhere left to retreat to.
func retreat_step() -> bool:
	if _path_index <= 0:
		return false

	var previous_cell: Vector2i = _path[_path_index - 1]
	var target_pos: Vector2 = grid.cell_to_world_center(previous_cell)
	var to_target: Vector2 = target_pos - position

	if to_target.length() <= ARRIVAL_DISTANCE:
		position = target_pos
		current_cell = previous_cell
		_path_index -= 1
	else:
		_update_facing(to_target)
		var step: Vector2 = to_target.normalized() * speed * get_physics_process_delta_time()
		position += step

	_check_obstacle_collisions()
	return true

## Our own narrow phase test against every obstacle in obstacles, using
## CollisionSystem's hand written AABB-Circle check, no engine call
## involved. Pushes the NPC back out of any obstacle it now overlaps.
func _check_obstacle_collisions() -> void:
	_just_collided = false
	var radius: float = (_collision_shape.shape as CircleShape2D).radius
	for obstacle in obstacles:
		var box: Rect2 = obstacle.collision_box()
		if CollisionSystem.circle_vs_box_collides(global_position, radius, box):
			global_position = CollisionSystem.push_circle_out_of_box(global_position, radius, box)
			_just_collided = true

func _set_path(path: Array[Vector2i]) -> void:
	_path = path
	_path_index = 0

func _update_facing(movement: Vector2) -> void:
	if movement.length_squared() < 1.0:
		return # barely moving, keep the last facing instead of flickering
	if absf(movement.x) > absf(movement.y):
		_facing = "right" if movement.x > 0 else "left"
	else:
		_facing = "down" if movement.y > 0 else "up"

## Loads a sprite sheet plus its LibreSprite JSON metadata, slices the
## sheet into frames, and builds one Animation per named tag (e.g.
## "down_walk") so states can just call animate("down_walk").
func _load_sprite_animations(texture_path: String, json_path: String) -> void:
	var texture: Texture2D = load(texture_path)
	if texture == null:
		push_error("Could not load sprite sheet: " + texture_path)
		return
	sprite.texture = texture

	if not FileAccess.file_exists(json_path):
		push_error("Could not find sprite metadata: " + json_path)
		return

	var file: FileAccess = FileAccess.open(json_path, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("Failed to parse sprite metadata: " + json_path)
		return

	var data: Dictionary = json.get_data()
	_configure_frame_grid(data)
	_build_animations(data)

## Works out how many columns/rows of frames the sheet has, from the
## pixel size of its first frame.
func _configure_frame_grid(data: Dictionary) -> void:
	var frames: Dictionary = data["frames"]
	var first_frame: Dictionary = frames[frames.keys()[0]]["frame"]
	var frame_width: float = first_frame["w"]
	var frame_height: float = first_frame["h"]

	sprite.hframes = clampi(roundi(sprite.texture.get_width() / frame_width), 1, 999)
	sprite.vframes = clampi(roundi(sprite.texture.get_height() / frame_height), 1, 999)

## Turns every named tag into a real Animation that steps the Sprite2D
## frame index over time, then hands them all to anim_player as one library.
func _build_animations(data: Dictionary) -> void:
	var library := AnimationLibrary.new()
	for tag in data["meta"]["frameTags"]:
		var start_frame: int = int(tag["from"])
		var end_frame: int = int(tag["to"])
		library.add_animation(tag["name"], _build_single_animation(start_frame, end_frame))
	anim_player.add_animation_library("", library)

## One Animation resource that steps Sprite2D's frame property through
## start_frame..end_frame, looping, with hard cuts (no blending) between
## frames, appropriate for pixel art.
func _build_single_animation(start_frame: int, end_frame: int) -> Animation:
	var animation := Animation.new()
	var track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, "Sprite2D:frame")
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_NEAREST)
	animation.loop_mode = Animation.LOOP_LINEAR

	var frame_count: int = end_frame - start_frame + 1
	animation.length = frame_count * FRAME_DURATION

	var time: float = 0.0
	for frame in range(start_frame, end_frame + 1):
		animation.track_insert_key(track, time, frame)
		time += FRAME_DURATION

	return animation
