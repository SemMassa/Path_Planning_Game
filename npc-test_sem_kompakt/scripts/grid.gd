class_name Grid
extends Node2D
## Grid of walkable/blocked cells.
## Draws itself and reports clicks so walls and the goal can be set at runtime.

signal cell_clicked(cell: Vector2i)

const LIFE_SPOT_LABELS: Array[String] = ["1", "2", "3"]
const LIFE_SPOT_COLOR: Color = Color(1.0, 0.85, 0.1) # gold, stands out from every other color
const TITLE_FONT_SIZE: int = 24 # px, drawn above the grid, e.g. the algorithm's name
const START_CELL_COLOR: Color = Color(0.15, 0.85, 0.15) # green
const START_CELL_LABEL: String = "A"
const GOAL_CELL_COLOR: Color = Color(0.9, 0.15, 0.15) # red
const GOAL_CELL_LABEL: String = "B"
const NO_CELL: Vector2i = Vector2i(-1, -1) # sentinel meaning "not set", outside every grid

@export var columns: int = 20
@export var rows: int = 15
@export var cell_size: int = 40

var _walkable: Array = [] # Array[Array[bool]], indexed [x][y], the static maze layout

# Cells a moving Obstacle currently stands on. Kept separate from _walkable
# so it can be drawn differently from a real wall instead of looking like
# the Obstacle is merging into and walking through it.
var _blocked_cells: Dictionary = {} # Vector2i -> true

# Debug overlay: one search-result entry per active NPC, keyed by that NPC
# itself. Entry: {"explored": Dictionary (Vector2i -> true), "path":
# Array[Vector2i], "color": Color}, color matches that NPC's sprite tint
# (see main.gd's ALGORITHM_COLORS). _overlay_enabled is the on/off toggle
# (key O), kept separate from the data so toggling never loses anything.
var _overlays: Dictionary = {}
var _overlay_enabled: bool = true

# Life mode's spots A, B, C, in that order (index 0 = A). Empty in Race mode.
var _life_spots: Array[Vector2i] = []

# Current shared spawn cell (green) and Race mode goal cell (red), NO_CELL
# means "not set yet, don't draw it". See set_start_cell()/set_goal_cell().
var _start_cell: Vector2i = NO_CELL
var _goal_cell: Vector2i = NO_CELL

# Label shown above this grid (e.g. the algorithm's name), see set_title().
var _title: String = ""
var _title_color: Color = Color.WHITE

# Each Grid instance owns its own Obstacles/NPCs (main.gd builds one Grid
# per active NPC so they can be compared side by side without sharing cells).
@onready var obstacle_container: Node2D = $ObstacleContainer
@onready var npc_container: Node2D = $NPCContainer

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

## Every cell that is floor in the static maze layout, in no particular
## order. Used to plan Obstacle spawn/patrol cells before spawning any of
## them: spawning first would make an Obstacle's own cell reject the very
## next Obstacle's route via is_walkable().
func get_walkable_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in columns:
		for y in rows:
			if _walkable[x][y]:
				cells.append(Vector2i(x, y))
	return cells

## Marks a single cell wall or floor, then repaints. For the permanent maze
## layout; an Obstacle's own footprint goes through set_cell_occupied()
## instead so the two can be told apart.
func set_walkable(cell: Vector2i, walkable: bool) -> void:
	if is_inside_grid(cell):
		_walkable[cell.x][cell.y] = walkable
		queue_redraw()

## Flips a cell between wall and walkable, used by left click.
func toggle_wall(cell: Vector2i) -> void:
	set_walkable(cell, not is_walkable(cell))

## Marks a cell as currently stood on by a moving Obstacle (or clears
## that), without touching the wall layout. is_walkable() treats an
## occupied cell like a wall, but _cell_color() paints it differently.
func set_cell_occupied(cell: Vector2i, occupied: bool) -> void:
	if not is_inside_grid(cell):
		return
	if occupied:
		_blocked_cells[cell] = true
	else:
		_blocked_cells.erase(cell)
	queue_redraw()

## Replaces the whole walkable map at once, e.g. with a MazeGenerator
## result. data must already be sized [columns][rows].
func load_walkable_map(data: Array) -> void:
	_walkable = data
	queue_redraw()

## Converts a pixel position (local space) to the cell it falls into.
func world_to_cell(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / cell_size), floori(world_pos.y / cell_size))

## Converts a cell to the pixel position of its center, used for movement targets.
func cell_to_world_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * cell_size + cell_size * 0.5, cell.y * cell_size + cell_size * 0.5)

## Stores/replaces one NPC's own search-result overlay entry (its explored
## cells plus its path, in its own color) and repaints. `owner` just needs
## to be a stable, distinct key per NPC, main.gd passes the NPC itself.
func set_search_result(
	owner: Object, explored: Array[Vector2i], path: Array[Vector2i], color: Color
) -> void:
	var explored_set: Dictionary = {}
	for cell in explored:
		explored_set[cell] = true
	_overlays[owner] = {"explored": explored_set, "path": path, "color": color}
	queue_redraw()

## Removes every NPC's search-result overlay, used whenever a new shared
## spawn point makes the previous results stale.
func clear_search_results() -> void:
	_overlays.clear()
	queue_redraw()

## Flips whether the overlay is currently drawn. The underlying data is
## untouched, so toggling back on immediately shows the last set result.
func toggle_overlay() -> void:
	_overlay_enabled = not _overlay_enabled
	queue_redraw()

## Stores Life mode's spots A/B/C (in that order) for the overlay markers
## and repaints. Pass an empty array to hide them again (Race mode).
func show_life_spots(spots: Array[Vector2i]) -> void:
	_life_spots = spots
	queue_redraw()

## Sets the label drawn above this grid, e.g. the algorithm name in its own
## NPC's color. Pass an empty string to hide it again.
func set_title(text: String, color: Color) -> void:
	_title = text
	_title_color = color
	queue_redraw()

## Marks cell as the current shared spawn point (green marker, "A").
## Pass NO_CELL to hide it again.
func set_start_cell(cell: Vector2i) -> void:
	_start_cell = cell
	queue_redraw()

## Marks cell as the current Race mode goal (red marker, "B"). Pass
## NO_CELL to hide it again, e.g. once a new spawn point has no goal yet.
func set_goal_cell(cell: Vector2i) -> void:
	_goal_cell = cell
	queue_redraw()

## Picks the fill color for one cell: explored cells get a soft tint in
## whichever NPC's own color explored them first, everything else is plain
## walkable/wall. An Obstacle's own cell is not tinted here, Obstacle draws
## its own square (see obstacle.gd), so the cell underneath stays plain floor.
func _cell_color(cell: Vector2i) -> Color:
	if _overlay_enabled:
		for overlay in _overlays.values():
			if overlay["explored"].has(cell):
				return (overlay["color"] as Color).lightened(0.6)
	return Color.WHITE if _walkable[cell.x][cell.y] else Color.BLACK

## Draws every active NPC's own path as a connected line, in its own color.
func _draw_paths() -> void:
	if not _overlay_enabled:
		return
	for overlay in _overlays.values():
		var path: Array = overlay["path"]
		if path.size() < 2:
			continue
		var points: PackedVector2Array = []
		for cell in path:
			points.append(cell_to_world_center(cell))
		draw_polyline(points, overlay["color"], 4.0)

## Draws a small gold marker plus its letter (A/B/C) on top of each Life
## mode spot, so it is visible where the NPCs are headed, not just once
## they arrive.
func _draw_life_spots() -> void:
	for i in _life_spots.size():
		var center: Vector2 = cell_to_world_center(_life_spots[i])
		draw_circle(center, cell_size * 0.35, LIFE_SPOT_COLOR)
		if i < LIFE_SPOT_LABELS.size():
			_draw_spot_label(center, LIFE_SPOT_LABELS[i])

## Centers `label` roughly on `center`. draw_string() positions by
## baseline, not a bounding box, so this is an approximation, good enough
## for a single short letter on a small marker.
func _draw_spot_label(center: Vector2, label: String) -> void:
	var font: Font = ThemeDB.fallback_font
	var font_size: int = ThemeDB.fallback_font_size
	var text_width: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var text_pos := Vector2(center.x - text_width / 2.0, center.y + font_size * 0.35)
	draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)

## Draws a small colored marker plus its letter on the start cell (green,
## "A") and/or the goal cell (red, "B"), same look as the Life mode markers.
func _draw_start_goal_markers() -> void:
	if is_inside_grid(_start_cell):
		var start_center: Vector2 = cell_to_world_center(_start_cell)
		draw_circle(start_center, cell_size * 0.35, START_CELL_COLOR)
		_draw_spot_label(start_center, START_CELL_LABEL)
	if is_inside_grid(_goal_cell):
		var goal_center: Vector2 = cell_to_world_center(_goal_cell)
		draw_circle(goal_center, cell_size * 0.35, GOAL_CELL_COLOR)
		_draw_spot_label(goal_center, GOAL_CELL_LABEL)

## Draws _title (if set) centered above the grid, in its own color.
func _draw_title() -> void:
	if _title.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var text_width: float = font.get_string_size(
		_title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT_SIZE
	).x
	var center_x: float = columns * cell_size / 2.0
	var text_pos := Vector2(center_x - text_width / 2.0, -10.0)
	draw_string(font, text_pos, _title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_FONT_SIZE, _title_color)

## Paints every cell using _cell_color(), then the start/goal markers,
## every NPC's path, the Life mode spot markers, and the title on top.
func _draw() -> void:
	for x in columns:
		for y in rows:
			var cell := Vector2i(x, y)
			var rect := Rect2(x * cell_size, y * cell_size, cell_size, cell_size)
			draw_rect(rect, _cell_color(cell), true)
	_draw_start_goal_markers()
	_draw_paths()
	_draw_life_spots()
	_draw_title()

## Translates a left click into a grid cell and forwards it as a signal,
## and the O key into the overlay on/off toggle, at any time. Right click
## (restart) is handled globally by main.gd instead, see its own
## _unhandled_input().
func _unhandled_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		var cell := world_to_cell(get_local_mouse_position())
		if is_inside_grid(cell):
			cell_clicked.emit(cell)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_O:
		toggle_overlay()
