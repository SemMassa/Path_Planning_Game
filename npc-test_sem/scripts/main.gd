extends Node2D
## Wires the Grids, NPCs, and Obstacles together. Walls come entirely from the
## maze generator now, so left click no longer edits the map, it alternates
## between placing every active NPC's spawn point and sending them all to a
## shared goal cell. Right click restarts the whole game at any time, before
## or after Start.
##
## Every active NPC gets its own dedicated Grid instance, side by side, all
## loaded with the identical maze layout (and identical Obstacle patrol
## routes), instead of racing on a single shared grid. This makes each
## algorithm's own search visible in isolation and, as a side effect, removes
## any chance of NPCs stepping on each other's occupied cells.
##
## Obstacles are no longer a single fixed scene node: StartUI asks the
## player how many to spawn (per grid) before the run actually begins, so
## they get instantiated from OBSTACLE_SCENE at runtime and parented under
## that grid's own ObstacleContainer.
##
## NPCs work the same way, one per algorithm the player ticked on StartUI,
## instantiated from NPC_SCENE and parented under its own grid's
## NPCContainer. They never collide with each other, only against their own
## grid's Obstacles, so no ordering between them matters.

const GRID_SCENE: PackedScene = preload("res://scenes/Grid.tscn")
const OBSTACLE_SCENE: PackedScene = preload("res://scenes/Obstacle.tscn")
const NPC_SCENE: PackedScene = preload("res://scenes/NPC.tscn")
const BENCHMARK_DASHBOARD_SCENE: PackedScene = preload("res://scenes/BenchmarkDashboard.tscn")
const MIN_OBSTACLE_PATH_LEN: int = 5 # cells, skip routes too short to look like real patrols
const MAX_SPAWN_ATTEMPTS_PER_OBSTACLE: int = 6 # retries before giving up on one obstacle

# Accent color per algorithm identifier (see StartUI._selected_algorithms()),
# used for each grid's title and its NPC's path/explored-cell overlay, so
# several grids stay tellable apart at a glance. The NPC sprite itself no
# longer needs a matching modulate tint, it loads one of the real
# pre-colored sheets below instead.
const ALGORITHM_COLORS: Dictionary = {
	"astar": Color(1.0, 0.15, 0.15),
	"dstar_lite": Color(0.15, 0.85, 0.15),
	"jps": Color(0.15, 0.4, 1.0),
}
const ALGORITHM_LABELS: Dictionary = {
	"astar": "A*",
	"dstar_lite": "D* Lite",
	"jps": "JPS",
}
# Which pre-colored sprite sheet each algorithm's NPC uses (see npc.gd's
# sprite_sheet_path/sprite_metadata_path), one real sheet per color instead
# of tinting a single shared sheet with sprite.modulate.
const ALGORITHM_SPRITE_SHEETS: Dictionary = {
	"astar": "red_sprites",
	"dstar_lite": "green_sprites",
	"jps": "blue_sprites",
}

const LIFE_SPOT_COUNT: int = 3 # spots A, B, C
const SIDEBAR_WIDTH: int = 380 # px, StartUI's own width, see START_WINDOW_SIZE
const GRID_GAP: int = 24 # px between side by side grids
const TITLE_HEIGHT: int = 40 # px reserved above every grid for its algorithm label
const DASHBOARD_HEIGHT: int = 220 # px, extra window height reserved below the grids for results
# Window size before Start is pressed: just StartUI, no maze/grid behind it.
const START_WINDOW_SIZE: Vector2i = Vector2i(SIDEBAR_WIDTH, 620)

var _obstacle_pathfinder: Pathfinder = AStarPathfinder.new()
var _maze: MazeGenerator
var _maze_data: Array = [] # kept around so extra grids can each get their own duplicate
var _started: bool = false # true once _on_start_pressed() has placed the NPCs
var _npcs: Array[NPC] = []
var _npc_algorithm_ids: Dictionary = {} # NPC -> algorithm_id, for the benchmark dashboard
var _grids: Array[Grid] = [] # one per active NPC, see _build_grids()
var _life_mode: bool = false # false = Race (one shared goal), true = endless A/B/C cycle

# Race mode benchmark tracking, one entry per NPC, keyed by the NPC itself
# (see grid.gd's overlay dictionary for the same identity-key trick). Filled
# in on a goal click, read back out once every entry has stopped "running".
# Entry shape: {"status": "running"/"done"/"failed", "start_ms": int,
# "explored": int, "path_length": int, "elapsed_ms": int}. Only "status" and,
# for "running"/"done", "start_ms" are guaranteed present at every stage, see
# _on_cell_clicked()/_on_npc_arrived().
var _benchmarks: Dictionary = {}
var _dashboard: BenchmarkDashboard = null # currently shown results panel, if any

# True once a spawn point has been placed and we are waiting for the
# matching left click that sets the goal. False means the next left
# click places a new spawn point instead.
var _awaiting_goal_click: bool = false

@onready var grid: Grid = $Grid
@onready var start_ui: StartUI = $StartUI

## Keeps the grid hidden and the window sized just for StartUI, so the
## player picks Race/Life, obstacle count, and algorithms on their own
## first, without any maze or NPCs showing behind the panel. Nothing about
## the actual run (maze, grids, NPCs) is generated until Start is pressed,
## see _on_start_pressed(). Right click restart (see _unhandled_input())
## still works regardless, from the very first frame.
func _ready() -> void:
	grid.visible = false
	get_window().size = START_WINDOW_SIZE

	start_ui.start_pressed.connect(_on_start_pressed)
	grid.cell_clicked.connect(_on_cell_clicked)

## Only now, once the player has actually pressed Start, does the run
## itself begin: generates the maze, reveals the grid, then builds one Grid
## per selected algorithm (all sharing that identical maze layout), plans
## obstacle_count patrol routes once and mirrors them into every grid, and
## spawns each grid's own NPC in the maze's first room. In Life mode every
## NPC also gets the same three random spots A/B/C to cycle between
## forever, see npc.gd's life_spots/is_in_life_mode().
func _on_start_pressed(obstacle_count: int, algorithms: Array[String], mode: String) -> void:
	grid.visible = true
	grid.position = Vector2(0, TITLE_HEIGHT)
	_maze = MazeGenerator.new()
	_maze_data = _maze.generate(grid.columns, grid.rows)
	grid.load_walkable_map(_maze_data)

	_life_mode = mode == "life"
	_grids = _build_grids(algorithms.size())
	_fit_window_to_grids(_grids.size()) # StartUI has already queue_freed itself by now

	# Not "_pick_life_spots() if _life_mode else []": that ternary would type
	# as a generic Array at runtime instead of Array[Vector2i], and crash on
	# assignment, the same pitfall already hit and fixed in jps.gd.
	var life_spots: Array[Vector2i] = []
	if _life_mode:
		life_spots = _pick_life_spots()
	for grid_instance in _grids:
		grid_instance.show_life_spots(life_spots) # empty in Race mode, so this just hides them

	var planned_routes: Array[Dictionary] = _plan_obstacle_routes(obstacle_count)

	for i in algorithms.size():
		var algorithm_id: String = algorithms[i]
		var npc_grid: Grid = _grids[i]
		npc_grid.set_title(
			ALGORITHM_LABELS.get(algorithm_id, algorithm_id),
			ALGORITHM_COLORS.get(algorithm_id, Color.WHITE)
		)

		var obstacles: Array[Obstacle] = _instantiate_obstacles(planned_routes, npc_grid)

		var npc: NPC = NPC_SCENE.instantiate()
		npc.grid = npc_grid
		npc.pathfinder = _make_pathfinder(algorithm_id)
		npc.accent_color = ALGORITHM_COLORS.get(algorithm_id, Color.WHITE)
		_set_npc_sprite_sheet(npc, algorithm_id) # before add_child(), _ready() reads this right away
		npc_grid.npc_container.add_child(npc) # before place_at()/sprite access, both need _ready() run
		npc.arrived.connect(_on_npc_arrived.bind(npc))
		npc.place_at(_maze.room_center(0))
		npc.obstacles = obstacles
		npc.life_spots = life_spots
		_npcs.append(npc)
		_npc_algorithm_ids[npc] = algorithm_id
	_started = true

## Builds exactly count Grid instances, side by side, all loaded with the
## identical maze layout (see _maze_data), so every NPC gets its own
## dedicated grid to compare algorithms on without ever competing for the
## same cells. Reuses the original preview Grid (already holding the maze
## from _ready()) as the first one instead of throwing it away. Falls back
## to that single grid if count is 0 (no algorithm selected).
func _build_grids(count: int) -> Array[Grid]:
	var built: Array[Grid] = [grid]
	for _i in range(1, count):
		var extra_grid: Grid = GRID_SCENE.instantiate()
		extra_grid.columns = grid.columns
		extra_grid.rows = grid.rows
		extra_grid.cell_size = grid.cell_size
		add_child(extra_grid)
		extra_grid.load_walkable_map(_maze_data.duplicate(true))
		extra_grid.cell_clicked.connect(_on_cell_clicked)
		built.append(extra_grid)

	var grid_width: int = grid.columns * grid.cell_size
	for i in built.size():
		built[i].position = Vector2(i * (grid_width + GRID_GAP), TITLE_HEIGHT)
	return built

## Three walkable cells for Life mode's spots A, B and C, spread across the
## maze via greedy farthest point sampling instead of plain random picks:
## the first spot is random, every next one is whichever remaining
## candidate is farthest from its own nearest already-picked spot. Falls
## back to fewer than LIFE_SPOT_COUNT only if the maze has fewer walkable
## cells than that to begin with. Every grid shares the identical maze, so
## this only needs to run once and the same spots apply everywhere.
func _pick_life_spots() -> Array[Vector2i]:
	var candidates: Array[Vector2i] = grid.get_walkable_cells()
	if candidates.is_empty():
		return []
	candidates.shuffle()

	var spots: Array[Vector2i] = [candidates.pop_back()]
	while spots.size() < LIFE_SPOT_COUNT and not candidates.is_empty():
		var farthest_index: int = _farthest_candidate_index(candidates, spots)
		spots.append(candidates.pop_at(farthest_index))
	return spots

## Index into candidates whose nearest distance to any cell already in
## spots is the largest, i.e. the candidate that would spread the spots
## out the most if picked next.
func _farthest_candidate_index(candidates: Array[Vector2i], spots: Array[Vector2i]) -> int:
	var best_index: int = 0
	var best_distance: int = -1
	for i in candidates.size():
		var distance: int = _distance_to_nearest_spot(candidates[i], spots)
		if distance > best_distance:
			best_distance = distance
			best_index = i
	return best_index

## Squared distance (no sqrt needed, only used for comparisons) from cell
## to whichever entry in spots is closest to it.
func _distance_to_nearest_spot(cell: Vector2i, spots: Array[Vector2i]) -> int:
	var nearest: int = -1
	for spot in spots:
		var distance: int = (cell - spot).length_squared()
		if nearest == -1 or distance < nearest:
			nearest = distance
	return nearest

## A fresh Pathfinder instance for the given algorithm identifier, one per
## NPC so BlockState/RetreatState on each NPC repair or retreat completely
## independently of every other NPC's search state.
func _make_pathfinder(algorithm_id: String) -> Pathfinder:
	match algorithm_id:
		"dstar_lite":
			return DStarLitePathfinder.new()
		"jps":
			return JPSPathfinder.new()
		_:
			return AStarPathfinder.new()

## Points npc at the real, pre-colored sprite sheet for algorithm_id (see
## ALGORITHM_SPRITE_SHEETS), falling back to green for an unknown id. Must
## run before npc enters the tree, npc.gd's _ready() reads these paths once
## and never again.
func _set_npc_sprite_sheet(npc: NPC, algorithm_id: String) -> void:
	var sheet_name: String = ALGORITHM_SPRITE_SHEETS.get(algorithm_id, "green_sprites")
	npc.sprite_sheet_path = "res://sprite_sheets/%s.png" % sheet_name
	npc.sprite_metadata_path = "res://sprite_sheets/%s.json" % sheet_name

## Plans obstacle_count patrol routes on the (shared) maze layout, without
## spawning anything yet. Every grid uses the identical maze, so this one
## planning pass is reused to instantiate matching Obstacles into every grid
## further down (see _instantiate_obstacles()), meaning every comparison
## grid sees the exact same obstacle behaviour, not just the same maze.
## Planning has to happen before any spawning: start_path() immediately
## blocks an Obstacle's own spawn cell, and is_walkable() checks that same
## occupancy, so planning route 2 after already spawning Obstacle 1 could
## reject route 2 outright if it happened to start or end on Obstacle 1's
## spawn cell. Since nothing is occupied yet while every route is still
## just being planned, that cannot happen here.
func _plan_obstacle_routes(count: int) -> Array[Dictionary]:
	var candidate_cells: Array[Vector2i] = grid.get_walkable_cells()
	candidate_cells.erase(_maze.room_center(0)) # keep every NPC's own spawn cell free
	candidate_cells.shuffle()

	var planned_routes: Array[Dictionary] = []
	var attempts: int = 0
	var max_attempts: int = count * MAX_SPAWN_ATTEMPTS_PER_OBSTACLE

	while planned_routes.size() < count and attempts < max_attempts:
		attempts += 1
		if candidate_cells.size() < 2:
			break

		var patrol_from: Vector2i = candidate_cells.pop_front()
		var patrol_to: Vector2i = candidate_cells.pop_back()
		var patrol_route: Array[Vector2i] = _obstacle_pathfinder.find_path(
			grid, patrol_from, patrol_to
		)
		if patrol_route.size() < MIN_OBSTACLE_PATH_LEN:
			continue

		planned_routes.append({"spawn_cell": patrol_from, "route": patrol_route})
	return planned_routes

## Spawns one Obstacle per planned route into target_grid's own
## ObstacleContainer, so occupancy tracking (grid.set_cell_occupied()) stays
## fully independent per grid even though the routes themselves are shared,
## keeping every grid's patrol behaviour in lockstep.
func _instantiate_obstacles(
	planned_routes: Array[Dictionary], target_grid: Grid
) -> Array[Obstacle]:
	var obstacles: Array[Obstacle] = []
	for planned in planned_routes:
		var obstacle: Obstacle = OBSTACLE_SCENE.instantiate()
		obstacle.grid = target_grid
		obstacle.start_path(planned["spawn_cell"], planned["route"])
		target_grid.obstacle_container.add_child(obstacle)
		obstacles.append(obstacle)
	return obstacles

## Right click reloads the whole scene, a full restart: fresh maze, no
## leftover NPC/Obstacle/Grid/dashboard state, back to StartUI. Simpler and
## safer than manually clearing every piece of spawned state by hand, which
## is exactly the kind of bookkeeping that caused bugs earlier in this
## project. Handled here globally (Main receives every unhandled input,
## unscoped to any position) rather than per Grid instance: a Grid only
## ever emits cell_clicked for a click that actually lands within its own
## columns x rows area, so it used to miss a right click anywhere else on
## screen, e.g. once the benchmark dashboard grew the window and added
## space below the grids, restart there silently did nothing.
func _unhandled_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_RIGHT
	):
		get_tree().reload_current_scene()

## Every left click places a new spawn point for every active NPC, in its
## own grid, but only once the game has actually started, _started guards
## against a left click reaching place_at() before _on_start_pressed() ever
## gave the NPCs a grid. Since every grid shares the identical maze layout,
## the same cell coordinate (wherever it was actually clicked, in whichever
## grid) is valid and meaningful in all of them at once, so one click really
## does set every grid's spawn point together. In Race mode, the next left
## click after that sets the shared goal. In Life mode there is no second
## click at all: as soon as the spawn point is placed, every NPC heads
## straight for spot A on its own, then keeps cycling A -> B -> C -> A ...
## without further input. Every npc.go_to() call (here and, in Life mode,
## every later leg triggered internally by LifeWaitState) refreshes its own
## grid's overlay entry on its own, see npc.gd's _update_grid_overlay(), so
## nothing here needs to touch any Grid's overlay itself beyond clearing
## stale entries below.
func _on_cell_clicked(cell: Vector2i) -> void:
	if not _started:
		return

	if not _awaiting_goal_click:
		if not grid.is_walkable(cell):
			return # ignore clicks on walls, keep waiting for a valid spawn
		if is_instance_valid(_dashboard):
			_dashboard.queue_free() # from a previous race, its numbers no longer apply
		for npc in _npcs:
			npc.place_at(cell)
			_benchmarks.erase(npc) # abort any still-running benchmark from a previous attempt
		for grid_instance in _grids:
			grid_instance.clear_search_results() # old paths started from the old spawn point
			grid_instance.set_start_cell(cell)
			grid_instance.set_goal_cell(Grid.NO_CELL) # no goal chosen yet for this new spawn point

		if _life_mode:
			for npc in _npcs:
				npc.go_to(npc.life_spots[0]) # spot A, LifeWaitState takes it from there
		else:
			_awaiting_goal_click = true
	else:
		for npc in _npcs:
			_start_benchmark(npc, cell)
		for grid_instance in _grids:
			grid_instance.set_goal_cell(cell)
		_awaiting_goal_click = false
		if _all_benchmarks_finished():
			_show_benchmark_dashboard() # every NPC failed to find a path at all, nothing to time

## Sends npc toward goal and immediately records its benchmark entry: the
## search itself already ran synchronously inside go_to(), so explored
## cells and path length are already known right away, only the elapsed
## walking time still needs _on_npc_arrived() later. A goal pathfinding
## could not reach at all leaves current_path() empty, marked "failed"
## right here instead of waiting for an arrival that will never come.
func _start_benchmark(npc: NPC, goal: Vector2i) -> void:
	npc.go_to(goal)
	var path_length: int = npc.current_path().size()
	if path_length == 0:
		_benchmarks[npc] = {"status": "failed"}
		return
	_benchmarks[npc] = {
		"status": "running",
		"start_ms": Time.get_ticks_msec(),
		"explored": npc.pathfinder.explored_cells.size(),
		"path_length": path_length,
	}

## Fired by every NPC's own arrived signal, which also fires on plain spawn
## placement and on an immediately unreachable goal, neither of which is a
## real arrival. Only a benchmark entry still marked "running" (see
## _start_benchmark()) means this really is one, everything else is ignored.
func _on_npc_arrived(npc: NPC) -> void:
	if not _benchmarks.has(npc) or _benchmarks[npc]["status"] != "running":
		return
	var entry: Dictionary = _benchmarks[npc]
	entry["status"] = "done"
	entry["elapsed_ms"] = Time.get_ticks_msec() - entry["start_ms"]
	_benchmarks[npc] = entry
	if _all_benchmarks_finished():
		_show_benchmark_dashboard()

## True once every active NPC has a benchmark entry and none of them are
## still "running", i.e. every NPC has either arrived or failed to find a
## path at all.
func _all_benchmarks_finished() -> bool:
	if _benchmarks.size() < _npcs.size():
		return false
	for entry in _benchmarks.values():
		if entry["status"] == "running":
			return false
	return true

## Builds one result row per NPC from _benchmarks + _npc_algorithm_ids and
## hands them all to a fresh BenchmarkDashboard, replacing any still-open
## one from an earlier race. Grows the window first (_reserve_dashboard_
## space()) so the panel gets its own strip below the grids instead of
## covering them.
func _show_benchmark_dashboard() -> void:
	if is_instance_valid(_dashboard):
		_dashboard.queue_free()
	_reserve_dashboard_space()
	_dashboard = BENCHMARK_DASHBOARD_SCENE.instantiate()
	add_child(_dashboard)
	_dashboard.show_results(_build_benchmark_results())

## One result Dictionary per NPC: label/color for display, and either the
## finished numbers (elapsed_ms/explored/path_length/efficiency) or just a
## "failed" status if that NPC's goal was never reachable at all.
## Efficiency is explored cells divided by path length, lower means the
## search stayed more tightly focused on the actual route instead of
## fanning out over the whole map.
func _build_benchmark_results() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for npc in _npcs:
		var algorithm_id: String = _npc_algorithm_ids.get(npc, "")
		var entry: Dictionary = _benchmarks.get(npc, {"status": "failed"})
		var result: Dictionary = {
			"label": ALGORITHM_LABELS.get(algorithm_id, algorithm_id),
			"color": ALGORITHM_COLORS.get(algorithm_id, Color.WHITE),
			"status": entry["status"],
		}
		if entry["status"] == "done":
			var explored: int = entry["explored"]
			var path_length: int = entry["path_length"]
			result["elapsed_ms"] = entry["elapsed_ms"]
			result["explored"] = explored
			result["path_length"] = path_length
			result["efficiency"] = float(explored) / path_length
		results.append(result)
	return results

## Works out how wide/tall grid_count grids side by side (plus their gaps
## and title strip) are, in logical pixels, and hands that off to
## _configure_window() to actually display it, maximized and as large as
## the screen allows. Only ever called once Start has been pressed and
## StartUI has already queue_freed itself (see _ready(), which sizes the
## window for StartUI alone instead), so there is no sidebar to account for
## here anymore.
func _fit_window_to_grids(grid_count: int) -> void:
	var content_width: int = (
		grid_count * grid.columns * grid.cell_size + maxi(0, grid_count - 1) * GRID_GAP
	)
	var content_height: int = grid.rows * grid.cell_size + TITLE_HEIGHT
	_configure_window(Vector2i(content_width, content_height))

## Tells Godot's own window content scaling to stretch content_size worth of
## logical game pixels to fill the actual window, then maximizes that
## window, always ending up as large as the current screen allows.
##
## This replaces an earlier approach that manually queried
## DisplayServer.screen_get_usable_rect() once, computed a fit_scale from
## it, and resized the window in raw pixels. That resize depended on
## wherever the window already happened to be (position, current size,
## which monitor it was considered "on"), so restarting mid Godot editor
## test run, or growing the window again later for the benchmark dashboard,
## could each shift that calculation slightly differently every time,
## something this project's own testing bore out as genuinely unreliable.
## content_scale_size + MODE_MAXIMIZED is the same trick every ordinary
## resolution independent Godot game uses instead: Godot's own rendering
## pipeline does the stretching every frame, and maximizing is a plain
## OS level window state, neither one depends on any value left over from
## a previous run.
func _configure_window(content_size: Vector2i) -> void:
	var window: Window = get_window()
	window.content_scale_size = content_size
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.mode = Window.MODE_MAXIMIZED

## Re-tells Godot's window content scaling to include DASHBOARD_HEIGHT worth
## of extra logical height below the grids, so the results panel gets its
## own space instead of covering them. Purely a content_scale_size change
## (not a raw pixel window resize), recomputed fresh from
## grid.rows/grid.cell_size every time, so it never depends on whatever the
## window happened to already be sized at.
func _reserve_dashboard_space() -> void:
	var window: Window = get_window()
	var content_size: Vector2i = window.content_scale_size
	content_size.y = grid.rows * grid.cell_size + TITLE_HEIGHT + DASHBOARD_HEIGHT
	window.content_scale_size = content_size
