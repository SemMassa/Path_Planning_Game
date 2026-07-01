# Main.gd
# Entry point and game controller.
#
# Interaction flow:
#   1. Map loads  → player sees empty rooms
#   2. Left click on a floor cell → sets START (green)
#   3. Left click on another floor cell → sets END (red), NPCs + obstacles spawn
#   4. Left click again → full reset, back to step 2
#
# Required scene tree:
#   Node2D  (this script)
#   ├── GridManager       (Node2D + GridManager.gd)
#   ├── NPCContainer      (Node2D)
#   ├── ObstacleContainer (Node2D)
#   └── UI (CanvasLayer)
#       └── HintLabel (Label)

extends Node2D

# ---- Tunable parameters ---------------------------------------------------
const GRID_WIDTH:            int = 41
const GRID_HEIGHT:           int = 41
const NPC_COUNT:             int = 3
const MOVING_OBSTACLE_COUNT: int = 4
const MIN_OBSTACLE_PATH_LEN: int = 5
# ---------------------------------------------------------------------------

# Game phase state machine
enum Phase { PLACING_START, PLACING_END, RUNNING }

@onready var grid_manager:       GridManager = $GridManager
@onready var npc_container:      Node2D      = $NPCContainer
@onready var obstacle_container: Node2D      = $ObstacleContainer
@onready var hint_label:         Label       = $UI/HintLabel

var _npc_scene:        PackedScene = preload("res://scenes/NPC.tscn")
var _obstacle_scene:   PackedScene = preload("res://scenes/MovingObstacle.tscn")
# Preload avoids relying on class_name resolution order at parse time
const _NPCTrailScript              = preload("res://scripts/NPCTrail.gd")

var _phase:     Phase    = Phase.PLACING_START
var _start_pos: Vector2i = Vector2i(-1, -1)
var _end_pos:   Vector2i = Vector2i(-1, -1)

# One distinct color per NPC — trail and body share the same color
const NPC_COLORS: Array[Color] = [
	Color(0.20, 0.50, 0.95),   # blue
	Color(0.95, 0.60, 0.10),   # orange
	Color(0.20, 0.85, 0.45),   # green
]


# ---- Lifecycle ------------------------------------------------------------

func _ready() -> void:
	var generator := MazeGenerator.new()
	var layout     = generator.generate(GRID_WIDTH, GRID_HEIGHT)
	grid_manager.setup(layout)
	_set_phase(Phase.PLACING_START)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	if not (event as InputEventMouseButton).pressed:
		return
	if (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return

	var grid_pos := grid_manager.world_to_grid(get_global_mouse_position())

	match _phase:
		Phase.PLACING_START:
			# Any floor cell is valid as start
			if grid_manager.mark_start(grid_pos):
				_start_pos = grid_pos
				_set_phase(Phase.PLACING_END)

		Phase.PLACING_END:
			# Floor cell that is not the same as start
			if grid_pos != _start_pos and grid_manager.mark_end(grid_pos):
				_end_pos = grid_pos
				_set_phase(Phase.RUNNING)
				_spawn_moving_obstacles()
				_spawn_npcs()

		Phase.RUNNING:
			# Any click resets the whole round
			_reset()


# ---- Phase management -----------------------------------------------------

func _set_phase(phase: Phase) -> void:
	_phase = phase
	match phase:
		Phase.PLACING_START:
			hint_label.text = "Linksklick: Startpunkt setzen  (grün)"
		Phase.PLACING_END:
			hint_label.text = "Linksklick: Ziel setzen  (rot)"
		Phase.RUNNING:
			hint_label.text = "NPCs laufen — Linksklick zum Neustart"


func _reset() -> void:
	# Remove all NPCs and obstacles
	for child in npc_container.get_children():
		child.queue_free()
	for child in obstacle_container.get_children():
		child.queue_free()

	# Clear visual markers from the grid
	grid_manager.clear_markers()

	_start_pos = Vector2i(-1, -1)
	_end_pos   = Vector2i(-1, -1)

	_set_phase(Phase.PLACING_START)


# ---- Spawning helpers -----------------------------------------------------

func _spawn_npcs() -> void:
	# Spawn NPCs near the start, slightly offset so they don't stack exactly
	var offsets: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
	]

	for i in NPC_COUNT:
		var spawn_grid := _start_pos + offsets[i % offsets.size()]

		# Fall back to exact start if the offset cell is a wall
		if not grid_manager.is_walkable(spawn_grid):
			spawn_grid = _start_pos

		var color: Color = NPC_COLORS[i % NPC_COLORS.size()]

		# Spawn NPC with its unique color
		var npc: NPC = _npc_scene.instantiate()
		npc_container.add_child(npc)
		npc.global_position = grid_manager.grid_to_world_center(spawn_grid)
		npc.setup(grid_manager, _end_pos, color)

		# Spawn a matching particle trail as a sibling so it stays in world space
		# Trails are children of npc_container and get cleaned up on _reset()
		var trail = _NPCTrailScript.new()
		npc_container.add_child(trail)
		trail.setup(npc, color)


func _spawn_moving_obstacles() -> void:
	var empty_cells: Array = grid_manager.get_empty_cells()
	# Keep start and end free so obstacles can't permanently block them
	empty_cells.erase(_start_pos)
	empty_cells.erase(_end_pos)
	empty_cells.shuffle()

	var spawned:      int = 0
	var attempts:     int = 0
	var max_attempts: int = MOVING_OBSTACLE_COUNT * 6

	while spawned < MOVING_OBSTACLE_COUNT and attempts < max_attempts:
		attempts += 1

		if empty_cells.size() < 2:
			break

		var obs_start: Vector2i = empty_cells.pop_front()
		var obs_end:   Vector2i = empty_cells.pop_back()

		var path: PackedVector2Array = grid_manager.find_path(obs_start, obs_end)

		if path.size() < MIN_OBSTACLE_PATH_LEN:
			continue

		var waypoints: Array = []
		for world_pos: Vector2 in path:
			waypoints.append(grid_manager.world_to_grid(world_pos))

		var obstacle: MovingObstacle = _obstacle_scene.instantiate()
		obstacle_container.add_child(obstacle)
		obstacle.setup(grid_manager, waypoints)
		spawned += 1
