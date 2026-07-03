extends PathAlgorithm
class_name DStarAlgorithm

# Runs A* search in reverse (Goal -> Start)
#	Basically creates a map of waypoints by evaluating the entire scene first
#		Knows all obstacles before choosing the path waypoints
#		
#   In A* , we search from (Start -> Goal)
# 	Basically, we choose the best waypoints until we hit a block, 
#		then we mark the block in memory and return to the beginning,
#		knowing that we will need to choose a different cell to move to
#
# Tracks two values: 
# g(s): current estimated cost from goal to a cell 
# rhs(s): one step lookahead that calculates what the cost should be based on the neighbors

# g(s) == rhs(s): the cell data is stable/open
# g(s) != rhs(s): the cell data is inconsisent: 
# g(s) > rhs(s): lookahead is cheaper (path just opened up)
# g(s) < rhs(s): lookahead is trapped (path just got blocked)

# When g(s) !== rhs(s), the cell gets placed into a priority queue
#	Priority queue is sorted based on a key-pair [k1,k2]
#		When comparing cells, checks k1 first, if k1 is the same for both cells, checks k2
#
#		k1: Total estimated distance: min(g(s),rhs(s)) + h(s_start, s) + km: 	
#			 min(g(s),rhs(s)): best cost to get from goal to a cell 
#			 h(s_start, s): estimation heuristic from cell to NPC's current position 
#			 km: key modifier tracking how far the NPC has moved 
#			
#		k2: Direct path to node: min(g(s), rhs(s))
#
# When the algorithm needs to recalculate based on blocked cell: 
# 1. Set cost of moving into and out of blocked cell to INF: 
#		- Causes rhs values of neighboring cells to increase causing (g != rhs)
#		- Since (g != rhs), neighbors placed in priority queue
#
# 2. The values in the priority queue are processed: 
#		a. From blocked cell to start, update g and rhs values
#		b. Continue until consistency is restored enough for the NPC to find a valid path 
#
# 3. Apply new repaired part to path and continue moving 

# Node structure: 
#	{"cell": Vector2i, "key": [float,float]}

# Core variables
var g: Dictionary = {} 	# Cost from goal to cell node (Key: cell -> Value: cost)
var rhs: Dictionary = {} # One-step lookahead cost	 (Key: cell -> Value: lookahead cost)
var pqueue: Array = [] # Priority Queue of inconstent nodes
var km: float = 0.0 		#Key modifier

# state positions
var s_start: Vector2i
var s_goal: Vector2i
var s_last: Vector2i

# Public methods
func compute_path(start_pos: Vector2, goal_pos: Vector2, _extents: Vector2) -> PackedVector2Array:
	# Clear current values in core variables
	clear_variables()
	
	# set states
	s_start = world_manager.world_to_cell(start_pos)
	s_goal =  world_manager.world_to_cell(goal_pos)
	s_last =  s_start  # Note that we set the last cell to the start
	
	# Search backwards, so we start looking at the goal cell
	rhs[s_goal] = 0.0
	insert_pqueue(s_goal, calculate_key(s_goal))
	
	# Find the shortest path 
	compute_shortest_path()
	return reconstruct_path()
	
func repair_path(current_pos: Vector2, blocked_cell: Vector2i) -> PackedVector2Array:
	## Repair the existing path around a blocked cell
	
	s_start = world_manager.world_to_cell(current_pos)
	km += heuristic(s_last, s_start) # calculate key modifier 
	s_last = s_start		# Set the last state to be the start (moving backwards)
	
	# Update edge costs of the blocked cell and its neighbors
	var affected_nodes = get_neighbors(blocked_cell)
	affected_nodes.append(blocked_cell)
	
	# For each affected node, update the vertex
	for node in affected_nodes: 
		update_vertex(node)
		
	# Compute the new shortest path 
	compute_shortest_path()
	return reconstruct_path()
	
	
# CALCULATION MEMBERS
	
func update_vertex(u: Vector2i) -> void: 
	## Update the vertex of a node 
	
	if u != s_goal: 
		var min_rhs = INF
		for s_next in get_neighbors(u):
			var edge_cost = get_edge_cost(u, s_next)	    # Find edge cost between u and next state
			var new_rhs = g.get(s_next, INF) + edge_cost # Determine new lookahead cost
			min_rhs = min(min_rhs, new_rhs)			    # Find min between two lookaheads
	
			# Update rhs[u] to be new min rhs
			rhs[u] = min_rhs
		
	# Remove the current cell from the priority queue
	remove_pqueue(u)
	
	# If there is an inconsisency (g(s) != rhs(s)
	# Add node back into priority queue
	if g.get(u, INF) != rhs.get(u, INF):
		insert_pqueue(u, calculate_key(u))


func calculate_key(s: Vector2i) -> Array: 
	##
	## Calculates the key pair for a passed state [k1,k2]
	## 
	## k1: Total estimated distance: min(g(s),rhs(s)) + h(s_start, s) + km: 	
	##			 min(g(s),rhs(s)): best cost to get from goal to a cell 
	##			 h(s_start, s): estimation heuristic from cell to NPC's current position 
	##			 km: key modifier tracking how far the NPC has moved 
	##
	##  k2: min(g(s),rhs(s)): best cost to get from goal to a cell 
	##
	##
	## Returns key pair [k1, k2]
	
	var g_val = g.get(s, INF) 		# get the goal cost otherwise set to INF
	var rhs_val = rhs.get(s, INF)	# get lookahead cost otherwise set to INF

	var best_cost = min(g_val, rhs_val)
		
	return [best_cost + heuristic(s_start, s) + km, best_cost]

	
func compute_shortest_path() -> void: 
	
	# if the node at the top of the queue has a smaller than s_start key, or 
	# if there is an inconsistency, stop 
	while not pqueue.is_empty() and continue_compute_shortest_path():
		
			# Grab top cell and associated key 
			var old_key  = pqueue_top_key()
			var old_node = pop_pqueue()
			
			# Calculate a key for the old cell, will compare with stored value
			var new_key = calculate_key(old_node)
				
			# If the old key is smaller than the new key, add new cell and key into priority queue
			# Create new cell with recalculted key
			if key_less_than(old_key,new_key):
				insert_pqueue(old_node, new_key)
			
			# Cost is overconsistent (Shortcut is blocked)
			elif g.get(old_node, INF) > rhs.get(old_node, INF):
				g[old_node] = rhs[old_node]
					
				# update vertex for each neighbor
				for s in get_neighbors(old_node):
					update_vertex(s)
				
			# Cost is underconsistent (Shortcut is cleared)	
			else: 
				g[old_node] = INF # Don't want to use old path again
				
				# Get affected node + old node and add them to priority queue
				var affected = get_neighbors(old_node)
				affected.append(old_node)
				
				for s in affected: 
					update_vertex(s)
			
func continue_compute_shortest_path() -> bool: 
	
	# If top key is less than the start node's key, continue reparing 
	if pq_top_key_less_than(calculate_key(s_start)):
		return true
		
	# If the start node is still inconsistent, keep repairing 
	if rhs.get(s_start, INF) != g.get(s_start, INF):
		return true
			
	return false
						

# GRID HELPERS
# ---------------------------
func heuristic(a: Vector2i, b: Vector2i) -> float:
	# Use octile distance to match 8-way movement grid systems
	# h = D * (dx + dy) + (D2 - 2 * D) * min(dx,dy)
	#	dx = |x1 - x2|: absolute horizontal distance between two nodes
	#	dy = |y1 - y2|: absolute vertical distance between two nodes
	# 
	#   D: Cost of moving straight, we set it to 1.0
	#   D2: Cost of moving diagonally, set to sqrt(2)
	
	var dx = abs(a.x - b.x)
	var dy = abs(a.y - b.y)
		
	return max(dx,dy) + (sqrt(2) - 1) * min(dx,dy)
	
	
func get_edge_cost(u: Vector2i, v: Vector2i) -> float: 
## Get the edge cost between two cells 

	# If passed cells are currently blocked, do not want to go 
	if world_manager.is_tile_solid(u) or world_manager.is_tile_solid(v):
		return INF

	# Orthogonal movement will have cost of 1
	# Diagonal movement will have cost of sqrt(2): (sqrt( 1^2 + 1^2))
	
	# If movement is diagonal
	if u.x != v.x and u.y != v.y:
		return sqrt(2)
		
	else:
		return 1.0
		
func get_neighbors(cell: Vector2i) -> Array[Vector2i]:
	## Return all neighbors of passed cell 
	
	var neighbors: Array[Vector2i] = []
	
	# Set directions
	var directions = [
		Vector2i(-1,0), Vector2i(1,0), Vector2i(0,-1), Vector2i(0,1),
		Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]
	
	# Find the neighbor by adding direction to passed cell
	for dir in directions: 
		neighbors.append(cell + dir)
		
	return neighbors
	
# PATH GENERATION METHODS
# --------------------------------------

func reconstruct_path() -> PackedVector2Array:
	## Reconstruct the path 
	
	var path = PackedVector2Array()
	var curr = s_start # set current cell to be start
	
	# If start is inaccessible, return empty array
	if g.get(curr, INF) == INF:
		return path
	
	# Add the current cell position waypoints to hit in the path
	path.append(world_manager.cell_to_world(curr))
	
	# Walk forwards down local gradient values to find goal 
	var safety_break = 0 # Add this to make sure we stop after 500 runs
	
	while curr != s_goal and safety_break < 500:
		safety_break += 1
		var min_cost = INF
		var next_cell = curr
		
		# Determine the step cost for each neighbor of next cell 
		# If the current step to the neighbor is less costly than current min cost, update 
		
		for neighbor in get_neighbors(curr):
			var step_cost = get_edge_cost(curr, neighbor) + g.get(neighbor, INF)
			if step_cost < min_cost: 
				min_cost = step_cost
				next_cell = neighbor
		
		if next_cell == curr: # Weren't able to move, trapped
			return PackedVector2Array()
			
		# Otherwise we were able to find a cell to move to, add it to path
		curr = next_cell
		path.append(world_manager.cell_to_world(curr))
	
	return path
	
# PQUEUE Handlers

func insert_pqueue(cell: Vector2i, key: Array) -> void: 
	pqueue.append({"cell": cell, "key": key})

func pop_pqueue() -> Vector2i:
	## Finds best value in priority queue and pops it
	
	# Loop through each cell in the queue
	var best_idx = 0
	for i in range(1, pqueue.size()):

		var cell_key = pqueue[i]["key"]
		var best_key = pqueue[best_idx]["key"]
		
		if key_less_than(cell_key,best_key):
			best_idx = i
				
	# Remove the node located at best_idx ad return the cell 	
	var node = pqueue[best_idx]
	pqueue.remove_at(best_idx)
	return node["cell"]
	
func pqueue_top_key() -> Array: 
	## Obtain key from node at top of queue
	
	if pqueue.is_empty(): return [INF, INF]
	
	var best_key = pqueue[0]["key"]
	
	# loop through each item in pqueue
	for node in pqueue: 
		if(key_less_than(node["key"], best_key)):
			best_key = node["key"]
			
	return best_key
	
func remove_pqueue(cell: Vector2i) -> void: 			
	## Remove a certain cell from the priority queue
	
	# Move through queue in reverse to prevent shifting out of bounds when 
	# removing the element whose cell equals the target
	for i in range(pqueue.size() - 1, -1, -1):
		if pqueue[i]["cell"] == cell:
			pqueue.remove_at(i)
			
func key_less_than(key_a: Array, key_b: Array) -> bool:
	## Find the best index based on value of key-pair
	##  Checks key-pair (k1 first, then k2)
	## Returns index determined to be the best

	# If cell k1 is less than best k1, best index is cell index
	if key_a[0] < key_b[0]: return true
	if key_a[0] == key_b[0] and key_a[1] < key_b[1]: return true
	return false
		
func pq_top_key_less_than(target_key: Array) -> bool: 
	return key_less_than(pqueue_top_key(), target_key)
	
# Helpers
func clear_variables() -> void: 
	g.clear()
	rhs.clear()
	pqueue.clear()
	km = 0.0
	
	# Clear nodes
	s_start = Vector2.ZERO
	s_goal = Vector2.ZERO
	s_last = Vector2.ZERO
	
	
