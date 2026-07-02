extends Node2D
class_name PathPlanner2D

enum AlgorithmType {ASTAR, DSTAR_LITE, JPS_PLUS}

@export var speed: float = 150
@export var lookahead_dist = 32.0 # set to 1 tile by default

@onready var world_manager: Node = get_tree().current_scene


var current_algorithm: PathAlgorithm
var current_path: PackedVector2Array = PackedVector2Array()
var current_waypoint_idx: int = 0

var target_position: Vector2 = Vector2.ZERO
var current_extents: Vector2 = Vector2.ZERO # npc dimensions 

# Choose the algorithm
func set_algorithm_by_type(algorithm: AlgorithmType) -> void: 
	match algorithm: 
		AlgorithmType.ASTAR:
			set_algorithm(AStarAlgorithm.new())
			
		AlgorithmType.DSTAR_LITE:
			set_algorithm(DStarAlgorithm.new())
		
		AlgorithmType.JPS_PLUS:
			set_algorithm(JPSPlusAlgorithm.new())
	
func set_algorithm(algorithm: PathAlgorithm) -> void: 
	current_algorithm = algorithm
	if current_algorithm:
		current_algorithm.configure(world_manager)
	
func set_target(target: Vector2) -> void: 
	
	# Set the new target and clear current path
	target_position = target
	current_path.clear()
	current_waypoint_idx = 0

func set_current_extents(extents: Vector2) -> void: 
	current_extents = extents


		
		## Algorithm strategies
		## -------------------------
		## Standard A*: cannot handle local changes dynamically
		## Actions: 
		##	- Wipe current path 
		##	- call recalculate path to search map from scratch, but avoiding the marked cell
		##	- return velocity of zero to hold position during calculation 
		#
		## D*: Fixes paths dynamically without full recalculation 	
		## Actions: 
		##	- Repair segment of the path 
		##   - Add new segment to waypoints
		##   - Reset waypoint to 0 to target the new waypoint
		#
		## JPS+: 

		
func get_next_movement_frame(_delta: float) -> Dictionary: 
	var result = {"velocity": Vector2.ZERO, "status": "OK"}
	
	if current_waypoint_idx >= current_path.size(): 
		return result
		
	var target_waypoint = current_path[current_waypoint_idx]
		
	# Check if we are close enough to the waypoint, if so, advance
	if global_position.distance_to(target_waypoint) < 10.0:
		current_waypoint_idx += 1
		
		# If we've reached the end, stop
		if current_waypoint_idx >= current_path.size(): 
			return result
			
		target_waypoint = current_path[current_waypoint_idx]
		
	# Check if collision
	var sensor = check_sensor_radar()
	if sensor["collided"]:
		world_manager.mark_cell_solid(sensor["position"])
		
			
		# If collided, need to move to block state
		result["status"] = "BLOCKED"
		return result

	# If no collision, move waypoint 
	var waypoint_dir = global_position.direction_to(target_waypoint)
	result["velocity"] = waypoint_dir * speed
	
	return result 
	
	
func check_sensor_radar() -> Dictionary:
	var results = {
		"collided": false, 
		"obstacle_node" : null, 
		"position": Vector2.ZERO}
	
	# If at the end of paths
	if current_waypoint_idx >= current_path.size():
		return results
		
	var waypoint = current_path[current_waypoint_idx]
	var waypoint_dir = global_position.direction_to(waypoint)
	
	# Perform a lookahead and determine what's one tile in front
	var local_lookahead_dist = 32.0 # one tile
	var lookahead_pos  = global_position + (waypoint_dir * local_lookahead_dist)
	
	# Check for collisions 
	# Locate the cell for lookahead_pos
	var cell_key = world_manager.world_to_cell(lookahead_pos)
	if world_manager.grid.has(cell_key):
		
		var potential_obstacles = world_manager.grid[cell_key]
		var npc_aabb =  Rect2(lookahead_pos - (current_extents / 2.0), current_extents)
	
		for obstacle in potential_obstacles:
			# Skip checking for collision against itself
			if obstacle == get_parent():
				continue
				
			# If collision, mark it as such in sensor 
			if aabb_vs_aabb(npc_aabb, obstacle):
				# set values in sensor 
				results["collided"] = true
				results["obstacle_node"] = obstacle
				results["position"] = lookahead_pos
				return results
				
	return results
		

# AABB vs AABB collision detection 
func aabb_vs_aabb(npc_aabb: Rect2, obstacle: Node) -> bool:

		# Since we don't know what size obstacles are, and we know NPC is mostly rectangular, 
		# all objects shoudl have AABBs
		var obs_aabb = world_manager.get_aabb_for_node(obstacle)
			
		#Find the min coordinates (bottom-left corner) of both boxes
		# Find max coordinates (upper-right corner) of both boxes
		# Using Rect2, min = position, max = end
			
		var min_npc = npc_aabb.position
		var max_npc = npc_aabb.end
			
		var min_obs = obs_aabb.position
		var max_obs = obs_aabb.end
		
		return ((min_npc.x < max_obs.x and max_npc.x > min_obs.x) and 
			(min_npc.y < max_obs.y and max_npc.y > min_obs.y))
	
# invoke full path recalculation 
func recalculate_global_path() -> void: 
	if current_algorithm:
		current_path = current_algorithm.compute_path(global_position, target_position, current_extents)
		current_waypoint_idx = 0 # reset waypoint index so we start from the beginning of the path
	
func destination_reached() -> bool: 
	
	# If we nave waypoints to travel, not done 
	# If the index exceeds bounds, WalkState will rely on target distance
	if current_waypoint_idx < current_path.size(): 
		return false
		
	# check distance to absolute final target, 
	# if we're within 3 pixels, call it good enough
	var distance_to_target = global_position.distance_to(target_position)
	return distance_to_target  < 3.0	
