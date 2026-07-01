# MazeGenerator.gd
# Generates a house-like layout with distinct rectangular rooms
# connected by narrow corridors (doorways).
#
# Properties after generate():
#   start_pos : Vector2i  — center of the first room (NPC spawn)
#   end_pos   : Vector2i  — center of the last room  (NPC goal)
#
# Grid cell values:
#   EMPTY = 0  (floor)
#   WALL  = 1  (solid wall)
#   START = 2  (spawn marker, treated as floor)
#   END   = 3  (goal marker,  treated as floor)
#
# Connectivity guarantee:
#   All rooms are linked in a chain via L-shaped corridors,
#   so every floor cell is reachable from every other.

class_name MazeGenerator
extends RefCounted

const EMPTY: int = 0
const WALL:  int = 1
const START: int = 2
const END:   int = 3

# Room count range
const ROOM_COUNT_MIN: int = 5
const ROOM_COUNT_MAX: int = 9

# Room size range (in cells)
const ROOM_MIN_W: int = 4
const ROOM_MAX_W: int = 10
const ROOM_MIN_H: int = 4
const ROOM_MAX_H: int = 8

# Minimum gap between rooms (cells)
const ROOM_MARGIN: int = 2

# Max placement retries per room
const PLACE_ATTEMPTS: int = 80

# Published after generate()
var start_pos: Vector2i
var end_pos:   Vector2i

var _width:  int
var _height: int
var _grid:   Array   # Array of Array of int
var _rooms:  Array   # Array of Rect2i


func generate(width: int, height: int) -> Array:
	_width  = width
	_height = height
	_rooms  = []

	# Fill everything with walls
	_grid = []
	for y in _height:
		_grid.append([])
		for _x in _width:
			_grid[y].append(WALL)

	# Place rooms with overlap avoidance
	var target_count: int = randi_range(ROOM_COUNT_MIN, ROOM_COUNT_MAX)
	for _attempt in PLACE_ATTEMPTS * target_count:
		if _rooms.size() >= target_count:
			break
		_try_place_room()

	# Need at least 2 rooms for a start and end
	if _rooms.size() < 2:
		# Fallback: two guaranteed rooms
		_rooms.clear()
		_carve_room(Rect2i(2, 2, 8, 6))
		_carve_room(Rect2i(_width - 11, _height - 9, 8, 6))
		_rooms.append(Rect2i(2, 2, 8, 6))
		_rooms.append(Rect2i(_width - 11, _height - 9, 8, 6))

	# Connect rooms in order: 0→1→2→…→n (guarantees full connectivity)
	for i in range(_rooms.size() - 1):
		_connect_rooms(_rooms[i], _rooms[i + 1])

	# Start/end are no longer set automatically —
	# the player places them via mouse click in Main.gd.
	# We still expose room centers as suggestions if needed.
	start_pos = _room_center(_rooms[0])
	end_pos   = _room_center(_rooms[_rooms.size() - 1])

	return _grid


# ---- Private helpers -------------------------------------------------------

func _try_place_room() -> void:
	var w: int = randi_range(ROOM_MIN_W, ROOM_MAX_W)
	var h: int = randi_range(ROOM_MIN_H, ROOM_MAX_H)
	# Keep 1-cell border so walls always frame the house
	var x: int = randi_range(1, _width  - w - 1)
	var y: int = randi_range(1, _height - h - 1)

	var candidate := Rect2i(x, y, w, h)

	# Reject if it overlaps an existing room (with margin)
	for existing: Rect2i in _rooms:
		if candidate.grow(ROOM_MARGIN).intersects(existing):
			return

	_rooms.append(candidate)
	_carve_room(candidate)


func _carve_room(room: Rect2i) -> void:
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			if x >= 0 and x < _width and y >= 0 and y < _height:
				_grid[y][x] = EMPTY


func _connect_rooms(a: Rect2i, b: Rect2i) -> void:
	var ca := _room_center(a)
	var cb := _room_center(b)

	# Randomly pick horizontal-first or vertical-first L-shape
	if randi() % 2 == 0:
		_carve_h_corridor(ca.x, cb.x, ca.y)
		_carve_v_corridor(ca.y, cb.y, cb.x)
	else:
		_carve_v_corridor(ca.y, cb.y, ca.x)
		_carve_h_corridor(ca.x, cb.x, cb.y)


func _carve_h_corridor(x1: int, x2: int, y: int) -> void:
	for x in range(min(x1, x2), max(x1, x2) + 1):
		if x >= 0 and x < _width and y >= 0 and y < _height:
			_grid[y][x] = EMPTY


func _carve_v_corridor(y1: int, y2: int, x: int) -> void:
	for y in range(min(y1, y2), max(y1, y2) + 1):
		if x >= 0 and x < _width and y >= 0 and y < _height:
			_grid[y][x] = EMPTY


func _room_center(room: Rect2i) -> Vector2i:
	return Vector2i(
		room.position.x + room.size.x / 2,
		room.position.y + room.size.y / 2
	)
