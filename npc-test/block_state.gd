extends NPCState

func enter(msg: Dictionary = {}) -> void: 
	print("Entering BlockState")
	actor.velocity = Vector2.ZERO
	
	# Force recalculation 
	planner.recalculate_global_path()
	
	# Check if planner found a path, go back to walk state
	if planner.current_path.size() > 0:
		fsm.change_state("WalkState")
	
	# Can't find a new path, switch to wait 
	else: 
		fsm.change_state("WaitState")
		
		
	
	# Prompt nav agent to recalculate alternate route around blockage
	#actor.nav_agent.target_position = actor.get_target_pos()
	#fsm.change_state("WalkState")

func exit() -> void: 
	print("Exiting BlockState")
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
