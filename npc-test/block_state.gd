extends NPCState

var structure # Simple value to allow structure without errors

func enter(msg: Dictionary = {}) -> void: 
	print("Entering BlockState")

	# Check if we came from wait state
	var from_wait = msg.get("from_wait", false)    # Did we come from wait state
	var sensor_data = planner.check_sensor_radar() # Grab most recent sensor data
	var path_found: bool = true					  # Did we find a path after repair 
	
	if sensor_data["collided"]:
		var obstacle = sensor_data.get("obstacle")
		
		# No obstacle, go back to walk 
		if not obstacle: 
			fsm.change_state("WalkState")
			return
			
		# If we run into NPC/dynamic obstacle wait to see if obstacle moves out of the way 
		# Allows use of best path (recalculation will only be next-best)
		if obstacle and is_obstacle_dynamic(obstacle) and not from_wait: 	
			actor.velocity = Vector2.ZERO
			fsm.change_state("WaitState")
			return 
			
		else: 
			
			# Obstacle static/didn't move after wait 
			# Recalculate the path based on planner algorithm
			
			var blocked_cell = planner.world_manager.world_to_cell(sensor_data["position"])
			
			match planner.current_algorithm: 
				planner.AlgorithmType.ASTAR: 
					planner.recalculate_global_path()
					
					# If calculated path empty, goal unreachable 
					if planner.current_path.is_empty():
						path_found = false
				
				planner.AlgorithmType.DSTAR_LITE:
					
					# Repair the local path from npc position 
					var repaired_path = planner.current_algorithm.repair_path(
						actor.global_position, blocked_cell)
						
					# If current path empty, goal is unreachable
					if repaired_path.is_empty(): 
						path_found = false
					
					else: 
						planner.current_path = repaired_path
						planner.current_waypoint_idx = 0 # Reset waypoint idx so we start at beginning of calculated path
					 
				planner.AlgorithmType.JPS_PLUS:
					
					# recalculate the global path 
					planner.recalculate_global_path()
					if planner.current_path.is_empty():
						path_found = false
				
	else:
		# Obstacle has moved, path is now clear
		if not planner.current_algorithm is DStarAlgorithm:
			
			# Rebuild positions for ASTAR and JPS_PLUS	
			planner.recalculate_global_path()	
			if planner.current_path.is_empty():
						path_found = false

	# If path wasn't found, we need to move back into the wait state
	if path_found == false: 
		actor.velocity = Vector2.ZERO
		fsm.change_state("WaitState", {"from_wait" : false})
	
	# Path fixing successful, return to walk state	
	else: 
		fsm.change_state("WalkState")

func exit() -> void: 
	print("Exiting BlockState")
	
# Helper Functions 

func is_obstacle_dynamic(obstacle: Node2D) -> bool:
	return obstacle.is_in_group("NPCs") or obstacle.is_in_group("Dynamics")
	
#extends NPCState
#
##var nav_agent: NavigationAgent2D
#var last_dir: String = "down"
#var wait_time: float = 0.0
#
#const WAIT_DURATION: float = 0.25
#
## inherits from our NPCState basic class 
#func enter() -> void: 
	## set actor animation through actor reference
	#print("Switching to BLOCK state")
	#actor.velocity = Vector2.ZERO
	#
	#var target_world_pos: Vector2 = actor.cell_to_world(actor.current_target_cell)
	#var to_target: Vector2 = target_world_pos - actor.global_position
	#var move_dir = actor.calculate_direction_to(target_world_pos)
	#
	#actor.anim_player.play(move_dir + "_idle")	
	#
	#
	##var current_dir = actor.get_direction()
	##actor.anim_player.play(current_dir + "_idle")
	#
#func update(delta: float) -> void: 
	## let velocity push slide npcs apart
	#actor.velocity = actor.velocity.lerp(Vector2.ZERO, 0.1)
	#actor.global_position += actor.velocity * delta
	#
	## Count down to wait time
	#wait_time +=	 delta
	#if wait_time >= WAIT_DURATION:
		#evaluate_dstar_path()
		#
#
#func evaluate_dstar_path() -> void: 
	#var current_cell: Vector2i = actor.world_to_cell(actor.global_position)
	#var next_cell: Vector2i = actor.dstar.get_next_move_step(current_cell)
	#
	## Check cost before moving to next position
	#var path_cost = actor.dstar.get_cost(current_cell, next_cell)
	#
	## If current cost if INF, blocked, switch to wait
	#if path_cost == INF:
		#fsm.change_state("WaitState")
	#
	#else:
		#fsm.change_state("WalkState")
#
#
	#
	##var nav_agent = get_node_or_null("NavigationAgent2D")
	##if nav_agent: 
		## snap npc to mesh
	##	var map_rid = nav_agent.get_navigation_map()
	##	var closest_point = NavigationServer2D.map_get_closest_point(map_rid, actor.global_position)
	##	actor.global_position = closest_point
		#
		## Force agent to refresh setup towards the current target
	##	nav_agent.target_position = actor.get_target_pos()
	#
		## Wait to process new path 
	##	await actor.get_tree().physics_frame
		#
		## Check if grid can find route 
	##	if nav_agent.is_target_reachable():
	##		print(actor.name, " found a clean route - returning to WalkState")
	##		fsm.change_state("WalkState")
	##		return
		#
	## no nav agent, path layout is closed off, switch to wait
	##print(actor.name, " cannot find clean route, moving to waiting state")
	##fsm.change_state("WaitState")	
	#
#func exit() -> void: 
	#print("Exiting BLOCK")		
