class_name MazeGenerator
extends RefCounted
## Generates a house like layout: rectangular rooms connected by single
## cell wide corridors. On top of a guaranteed room chain (which alone
## makes every floor cell reachable), a few redundant connections are
## added so loops exist too, a blocked corridor should not mean a fully
## blocked map, which matters once Obstacle can wall one off.
## Produces a plain walkable grid in the same [x][y] layout Grid uses
## internally, load it via Grid.load_walkable_map().

const ROOM_COUNT_MIN: int = 5
const ROOM_COUNT_MAX: int = 9

const ROOM_MIN_SIZE: int = 4
const ROOM_MAX_W: int = 10
const ROOM_MAX_H: int = 8

const ROOM_MARGIN: int = 2 # minimum gap kept between rooms, in cells
const PLACE_ATTEMPTS: int = 80 # max placement retries per room

# Beyond the guaranteed chain, each room also connects to its N nearest
# rooms it is not already linked to. This is what creates loops instead
# of one single dead end hallway.
const EXTRA_CONNECTIONS_PER_ROOM: int = 3

# Used only to detect corridors running directly alongside one another.
const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]

var _width: int
var _height: int
var _walkable: Array = [] # Array[Array[bool]], indexed [x][y]
var _rooms: Array[Rect2i] = []

# Non room cells carved by a corridor so far, steers new corridors away
# from running directly beside an existing one instead of crossing it.
var _corridor_cells: Dictionary = {} # Vector2i -> true

## Builds a maze of the given size and returns it as walkable data,
## ready for Grid.load_walkable_map(). Call room_center() / room_count()
## afterwards to get sensible NPC or obstacle spawn points.
func generate(width: int, height: int) -> Array:
	_width = width
	_height = height
	_rooms = []
	_corridor_cells = {}
	_fill_with_walls()

	var target_count: int = randi_range(ROOM_COUNT_MIN, ROOM_COUNT_MAX)
	for _attempt in PLACE_ATTEMPTS * target_count:
		if _rooms.size() >= target_count:
			break
		_try_place_room()

	if _rooms.size() < 2:
		_place_fallback_rooms() # placement got unlucky, guarantee at least 2 rooms

	# Chain 0 -> 1 -> ... -> n first, this alone guarantees full connectivity.
	var linked_pairs: Dictionary = {} # "i_j" keys, avoids connecting the same pair twice
	for i in range(_rooms.size() - 1):
		_connect_rooms(_rooms[i], _rooms[i + 1])
		linked_pairs[_pair_key(i, i + 1)] = true

	_add_extra_connections(linked_pairs)
	return _walkable

## Center cell of room number index, a safe spot to place an NPC or
## obstacle since rooms are always fully carved out floor.
func room_center(index: int) -> Vector2i:
	return _center_of(_rooms[index])

func room_count() -> int:
	return _rooms.size()

func _fill_with_walls() -> void:
	_walkable.resize(_width)
	for x in _width:
		var column: Array = []
		column.resize(_height)
		column.fill(false)
		_walkable[x] = column

func _set_floor(cell: Vector2i) -> void:
	if cell.x >= 0 and cell.x < _width and cell.y >= 0 and cell.y < _height:
		_walkable[cell.x][cell.y] = true

## Tries one random room placement, keeps it only if it does not overlap
## an existing room (with margin). Simply does nothing on failure, the
## caller just retries with the next attempt.
func _try_place_room() -> void:
	var w: int = randi_range(ROOM_MIN_SIZE, ROOM_MAX_W)
	var h: int = randi_range(ROOM_MIN_SIZE, ROOM_MAX_H)
	var x: int = randi_range(1, _width - w - 1)
	var y: int = randi_range(1, _height - h - 1)
	var candidate := Rect2i(x, y, w, h)

	for existing in _rooms:
		if candidate.grow(ROOM_MARGIN).intersects(existing):
			return

	_rooms.append(candidate)
	_carve_room(candidate)

## Two guaranteed, non overlapping rooms, used only if random placement
## could not fit ROOM_COUNT_MIN rooms after every retry.
func _place_fallback_rooms() -> void:
	_rooms.clear()
	var first := Rect2i(2, 2, 6, 5)
	var second := Rect2i(_width - 8, _height - 7, 6, 5)
	_carve_room(first)
	_carve_room(second)
	_rooms.append(first)
	_rooms.append(second)

func _carve_room(room: Rect2i) -> void:
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			_set_floor(Vector2i(x, y))

## For every room, adds a corridor to its EXTRA_CONNECTIONS_PER_ROOM
## nearest rooms it is not already linked to. linked_pairs is shared and
## updated in place so a pair never gets connected twice.
func _add_extra_connections(linked_pairs: Dictionary) -> void:
	for i in range(_rooms.size()):
		var by_distance: Array = []
		for j in range(_rooms.size()):
			if j == i:
				continue
			by_distance.append({"index": j, "distance": _room_distance(_rooms[i], _rooms[j])})
		by_distance.sort_custom(func(a, b): return a["distance"] < b["distance"])

		var added := 0
		for entry in by_distance:
			if added >= EXTRA_CONNECTIONS_PER_ROOM:
				break
			var j: int = entry["index"]
			var key := _pair_key(i, j)
			if linked_pairs.has(key):
				continue
			linked_pairs[key] = true
			_connect_rooms(_rooms[i], _rooms[j])
			added += 1

## Order independent identity for a room pair, so (i, j) and (j, i)
## count as the same connection.
func _pair_key(a: int, b: int) -> String:
	return str(mini(a, b), "_", maxi(a, b))

func _room_distance(a: Rect2i, b: Rect2i) -> int:
	var center_a := _center_of(a)
	var center_b := _center_of(b)
	return absi(center_a.x - center_b.x) + absi(center_a.y - center_b.y)

## Carves an L shaped, single cell wide corridor between two room centers.
func _connect_rooms(a: Rect2i, b: Rect2i) -> void:
	var center_a := _center_of(a)
	var center_b := _center_of(b)

	# Either L shape (horizontal first or vertical first) connects the
	# same two rooms equally well, pick whichever runs beside fewer
	# already carved corridor cells, that keeps corridors from ending up
	# parallel and adjacent, which would read as one wide corridor.
	var path_h := _l_path_cells(center_a, center_b, true)
	var path_v := _l_path_cells(center_a, center_b, false)
	var conflicts_h := _adjacency_conflicts(path_h)
	var conflicts_v := _adjacency_conflicts(path_v)

	var chosen: Array[Vector2i]
	if conflicts_h == conflicts_v:
		chosen = path_h if randi() % 2 == 0 else path_v
	else:
		chosen = path_h if conflicts_h < conflicts_v else path_v

	_carve_path(chosen)

## All cells of one L shaped route between two points, either
## horizontal first (sideways, then up/down) or vertical first.
func _l_path_cells(
	from_cell: Vector2i, to_cell: Vector2i, horizontal_first: bool
) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if horizontal_first:
		for x in range(mini(from_cell.x, to_cell.x), maxi(from_cell.x, to_cell.x) + 1):
			cells.append(Vector2i(x, from_cell.y))
		for y in range(mini(from_cell.y, to_cell.y), maxi(from_cell.y, to_cell.y) + 1):
			cells.append(Vector2i(to_cell.x, y))
	else:
		for y in range(mini(from_cell.y, to_cell.y), maxi(from_cell.y, to_cell.y) + 1):
			cells.append(Vector2i(from_cell.x, y))
		for x in range(mini(from_cell.x, to_cell.x), maxi(from_cell.x, to_cell.x) + 1):
			cells.append(Vector2i(x, to_cell.y))
	return cells

## Counts cells on this route that would run directly beside an existing
## corridor cell (room interiors do not count, they are meant to be wide
## open). Crossing another corridor at a single point is fine, only
## running alongside one for a stretch counts as a conflict.
func _adjacency_conflicts(cells: Array[Vector2i]) -> int:
	var conflicts := 0
	for cell in cells:
		if _corridor_cells.has(cell) or _room_cell_at(cell):
			continue
		for offset in NEIGHBOR_OFFSETS:
			if _corridor_cells.has(cell + offset):
				conflicts += 1
				break
	return conflicts

func _room_cell_at(cell: Vector2i) -> bool:
	for room in _rooms:
		if room.has_point(cell):
			return true
	return false

func _carve_path(cells: Array[Vector2i]) -> void:
	for cell in cells:
		_set_floor(cell)
		if not _room_cell_at(cell):
			_corridor_cells[cell] = true

func _center_of(room: Rect2i) -> Vector2i:
	return Vector2i(room.position.x + room.size.x / 2, room.position.y + room.size.y / 2)
