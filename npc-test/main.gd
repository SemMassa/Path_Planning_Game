extends Node2D
enum PatrolMode {LIFE, RACE}

# Preload child scenes from memory
const NPC_SCENE = preload("res://npc.tscn")
const BOX_SCENE = preload("res://collision_test.tscn")

const CELL_SIZE: int = 32 # Spatial grid cell bounding layout size

@onready var mode_button: CheckButton = $PatrolMode
@onready var region: NavigationRegion2D = $NavigationRegion2D

var npcs: Array[String] = ["Green", "Blue", "Red"]
var current_mode: PatrolMode = PatrolMode.LIFE

var spawned_npcs: Array  = []
var spawned_boxes: Array = []

var grid: Dictionary = {} 		# spatial partitioning broad-phase container
var solid_cells: Dictionary = {} # cells marked solid by pathfinding radar

var spawn_positions: Array[Vector2] = [Vector2(-32, 0), Vector2(0, 0), Vector2(32, 0)]
var box_positions: Array[Vector2] = [
	Vector2(-100,50), Vector2(-250,25), Vector2(250, -25), Vector2(100,75),
	Vector2(-100,100), Vector2(-50,-100), Vector2(75,-100), Vector2(50,100), Vector2(100,-100)]


var all_life_targets: Dictionary = {
	0: [Vector2(-100,0),Vector2(0,100),Vector2(100,0),Vector2(0,-100)],
	1: [Vector2(200,200),Vector2(200,-200),Vector2(-200,-200),Vector2(-200,200)],
	2: [Vector2(-150,-150), Vector2(150,150), Vector2(150,-150), Vector2(-150,150)]}
	
var race_targets: Array[Vector2] = [Vector2(400,200)]

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if mode_button:
		mode_button.connect("toggled", _on_button_toggled)
	
	# Wait until end of frame tick to let navigation servers register map regions
	await get_tree().physics_frame
	
	spawn_npcs()
	spawn_collisions()	
	resolve_initial_spawn_overlaps() # in case initial position triggers collision
	
# Physical collision detection (collision will cause velocity change/pushback)
func _physics_process(_delta: float) -> void:
	update_spatial_grid(spawned_npcs, spawned_boxes) # Broad-phase
	narrow_phase()                                  # Narrow-phase

# Grid Mapping + Spatial Partitioning
# ------------------------
# Convert cell coordinates to center global space
func cell_to_world(cell_coords: Vector2i) -> Vector2: 
	return Vector2i(
		cell_coords.x * CELL_SIZE + (CELL_SIZE / 2.0),
		cell_coords.y * CELL_SIZE + (CELL_SIZE / 2.0))

# Convert global position properties into cell
func world_to_cell(world_pos: Vector2) -> Vector2i: 
	return Vector2i(
		floori(world_pos.x / CELL_SIZE),
		floori(world_pos.y / CELL_SIZE))
	

# Check if specific grid cell coordinate is blocked
func is_tile_solid(cell_coords: Vector2i) -> bool: 
	
	# Checked if cell coordinate was flagged by path planning radar
	if solid_cells.has(cell_coords):
		return true
	
	# Check each cell in the grid to see if it has an obstacle
	if grid.has(cell_coords):
		for item in grid[cell_coords]:
			if item.is_in_group("Statics") or item.is_in_group("Dynamics"):
				return true
				
	return false

# Mark cell grid as solid by setting value in solid_cells dict to true
func mark_cell_solid(world_pos: Vector2) -> void: 
	var cell_coords = world_to_cell(world_pos)
	solid_cells[cell_coords] = true
	
# Clear the solid cell cache when switching modes/rewriting global maps
func clear_solid_cells() -> void: 
	solid_cells.clear()

func get_aabb_for_node(node: Node2D) -> Rect2: 
	
	var size = Vector2(32,32) # baseline 
	
	# If node is a Sprite2D, get size from texture
	if node.has_node("Sprite2D"):
		var sprite = node.get_node("Sprite2D") as Sprite2D
		
		# Set size to the texture size and then account for any local scale adjustments
		if sprite and sprite.texture:
			size = sprite.texture.get_size() * sprite.scale * node.scale
	
	elif node.has_node("CollisionShape2D"):
		var shape_node = node.get_node("CollisionShape2D") as CollisionShape2D
		
		if shape_node and shape_node.shape: 
			# Size depends on the shape, in our scenario we only have circles and aabbs
			if shape_node.shape is RectangleShape2D:
				# Dimensions for rectangle are distance from center to edge
				size = shape_node.shape * 2.0 * node.scale
				
			elif shape_node.shape is CircleShape2D: 
				# Dimensions will be radius * 2 for both x and y
				var radius = shape_node.shape.radius
				size = Vector2(radius * 2.0, radius * 2.0) * node.scale
	
	# Check if object declares its own dimensions
	elif "current_extents" in node and node.current_extents != Vector2.ZERO:
		size = node.current_extents
	
	elif "size" in node: 
		size = node.size
		
	# return the calculated rectangle using size
	return Rect2(node.global_position - (size / 2.0), size)
		
func update_spatial_grid(moving_obstacles: Array, static_obstacles: Array) -> void: 
	# clear the grid and repopulate (since moving obstacles will change cells)
	grid.clear()
	for obstacle in static_obstacles: 
		register_object_in_grid(obstacle, get_aabb_for_node(obstacle))
		
	for obstacle in moving_obstacles:
		register_object_in_grid(obstacle, get_aabb_for_node(obstacle))
		
# Register objects spanning across multi-cell boundary boundaries 
func register_object_in_grid(obj: Node2D, aabb: Rect2) -> void: 
	var min_cell = world_to_cell(aabb.position)
	var max_cell = world_to_cell(aabb.end)

	# Loop through each coordinate between min_cell and max_cell
	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			var cell_key = Vector2i(x, y)
			
			# If the cell is empty, populate an array and add object to it
			if not grid.has(cell_key):
				grid[cell_key] = []                
			
			grid[cell_key].append(obj)
				
# Collision Detection and Resolution
#---------------------
func aabb_vs_aabb(box_a: Rect2, box_b: Rect2) -> bool: 
	return (box_a.position.x < box_b.end.x and box_a.end.x > box_b.position.x) and \
			(box_a.position.y < box_b.end.y and box_a.end.y > box_b.position.y)


func narrow_phase() -> void: 
	var checked_pairs: Dictionary = {}
	
	# Check each cell in grid for contents	
	for cell in grid: 
		var contents = grid[cell]
		if contents.size() < 2: continue # No potential collisions in this bucket
			
		# Check each content item with all values ahead of it 
		for i in range(contents.size()):
			for j in range(i + 1, contents.size()):
				
				var obj_a = contents[i]
				var obj_b = contents[j]
					
				# Generate localized pair-keys to skip redundant inverse calculations
				var id_a = obj_a.get_instance_id()
				var id_b = obj_b.get_instance_id()
				var pair_key = str(id_a, "_", id_b) if id_a < id_b else str(id_b, "_", id_a)
				
				if checked_pairs.has(pair_key): continue
				checked_pairs[pair_key] = true
					
				# NPC vs. NPC: AABB vs. AABB
				#--------------------------------------------
				# Identify object categorization 
				var is_a_npc = obj_a.is_in_group("NPCs")
				var is_b_npc = obj_b.is_in_group("NPCs")
				var is_static = obj_a.is_in_group("Statics") or obj_b.is_in_group("Statics")
				var is_dynamic = obj_a.is_in_group("Dynamics") or obj_b.is_in_group("Dynamics")
				
				if is_a_npc or is_b_npc: 
					var collision_allowed = true
					if current_mode == PatrolMode.RACE:
						var a_done = obj_a.FSM and obj_a.FSM.current_state.name == "DoneState"
						var b_done = obj_b.FSM and obj_b.FSM.current_state.name == "DoneState"        
						if a_done or b_done:
							collision_allowed = false
							
					if collision_allowed and aabb_vs_aabb(get_aabb_for_node(obj_a), get_aabb_for_node(obj_b)):
						resolve_npc_collision(obj_a, obj_b)
							
				elif (is_a_npc or is_b_npc) and (is_static or is_dynamic):
					var npc = obj_a if is_a_npc else obj_b
					var obstacle = obj_b if is_a_npc else obj_a
					
					if aabb_vs_aabb(get_aabb_for_node(npc), get_aabb_for_node(obstacle)):
						resolve_static_collision(npc, obstacle)
				
func spawn_collisions() -> void: 
	
	# Spawn static collisions
	for i in range(box_positions.size()):
		var new_box = BOX_SCENE.instantiate()
		new_box.global_position = box_positions[i]
		new_box.name = str("box_", i)
		
		# Add box to scene and add to group 
		add_child(new_box)
		new_box.add_to_group("Statics")
		spawned_boxes.append(new_box)


func resolve_npc_collision(npc_a: Node2D, npc_b: Node2D) -> void: 
	var aabb_a: Rect2 = get_aabb_for_node(npc_a)
	var aabb_b: Rect2 = get_aabb_for_node(npc_b)
	
	# Calculate overlap depth on both axes
	var overlap_x: float = min(aabb_a.end.x, aabb_b.end.x) - max(aabb_a.position.x, aabb_b.position.x)
	var overlap_y: float = min(aabb_a.end.y, aabb_b.end.y) - max(aabb_a.position.y, aabb_b.position.y)
	
	# If no real overlap, exit
	if overlap_x <= 0 or overlap_y <= 0: 
		return
		
	# Apply minimum translation vector to determine how to push
	if overlap_x < overlap_y: 
		# X-axis is the shallowest overlap, we need to resolve horizontally
		# Determine direction via normal 
		var normal_x: float = 1.0 if aabb_a.get_center().x > aabb_b.get_center().x else -1.0
		
		# Split push 50/50 across the axes with amall buffer of 0.5
		var push_amount = (overlap_y * 0.5) + 0.5
		npc_a.global_position.x += normal_x * push_amount
		npc_b.global_position.x -= normal_x * push_amount
	
	else: 
		# Y-axis is the shallowest overlap, need to resolve vertically
		# Determine direction via normal
		var normal_y: float = 1.0 if aabb_a.get_center().y > aabb_b.get_center().y else -1.0
		var push_amount = (overlap_x * 0.5) + 0.5
		
		npc_a.global_position.y += normal_y * push_amount
		npc_b.global_position.y -= normal_y * push_amount
		
	# Stop characters to stop walking and handle pathfinding
	if npc_a.FSM and npc_a.FSM.current_state.name == "WalkState":
		npc_a.FSM.change_state("BlockState")
		
	if npc_b.FSM and npc_b.FSM.current_state.name == "WalkState":
		npc_b.FSM.change_state("BlockState")
		
	
func resolve_static_collision(npc: Node2D, obstacle: Node2D) -> void: 
	# 1. Fetch current global AABB rectangles
	var aabb_npc: Rect2 = get_aabb_for_node(npc)
	var aabb_obs: Rect2 = get_aabb_for_node(obstacle)
	
	# 2. Calculate the overlap depth on both axes
	var overlap_x: float = min(aabb_npc.end.x, aabb_obs.end.x) - max(aabb_npc.position.x, aabb_obs.position.x)
	var overlap_y: float = min(aabb_npc.end.y, aabb_obs.end.y) - max(aabb_npc.position.y, aabb_obs.position.y)
		
	# exit if no overlap
	if overlap_x <= 0 or overlap_y <= 0:
		return

	if overlap_x < overlap_y:
		# X-axis is the shallowest overlap, so resolve horizontally
		# If the NPC's center is to the right of the box center, push right. Otherwise, push left.
		var dir_x: float = 1.0 if aabb_npc.get_center().x > aabb_obs.get_center().x else -1.0
		
		# Push the NPC by the full overlap amount, plus a tiny 0.1 pixel buffer to break contact
		npc.global_position.x += dir_x * (overlap_x + 0.1)
	else:
		# Y-axis is the shallowest overlap, so resolve vertically
		var dir_y: float = 1.0 if aabb_npc.get_center().y > aabb_obs.get_center().y else -1.0
		
		# Push the NPC vertically out of the box
		npc.global_position.y += dir_y * (overlap_y + 0.1)

	# Dynamically mark obstacles's cell position as solid so the path planner radar can read it
	mark_cell_solid(obstacle.global_position)
	
	# Stop the NPC from walking and force them into their pathfinding block state
	if npc.FSM and npc.FSM.current_state.name == "WalkState":
		npc.FSM.change_state("BlockState")


func _on_button_toggled(race_on: bool) -> void:
	if race_on: 
		current_mode = PatrolMode.RACE
	else:
		current_mode = PatrolMode.LIFE
		
		var npcs_list = get_tree().get_nodes_in_group("NPCs")
		if npcs_list.size() > 0: 
			# Aggressively resolve clustered groups over a few iterations
			for k in range(6):
				for i in range(npcs_list.size()):
					for j in range(i + 1, npcs_list.size()):
						var npc_a = npcs_list[i]
						var npc_b = npcs_list[j]
						
						var box_a = get_aabb_for_node(npc_a)
						var box_b = get_aabb_for_node(npc_b)
						
						# Check if their rectangular boundaries are overlapping
						if aabb_vs_aabb(box_a, box_b):
							var overlap_x = min(box_a.end.x, box_b.end.x) - max(box_a.position.x, box_b.position.x)
							var overlap_y = min(box_a.end.y, box_b.end.y) - max(box_a.position.y, box_b.position.y)
							
							# Fallback if they are perfectly overlapping (prevent zeroes)
							if overlap_x <= 0: overlap_x = 0.1
							if overlap_y <= 0: overlap_y = 0.1
							
							# Push out along the shallowest penetration axis (MTV)
							if overlap_x < overlap_y:
								var dir_x = 1.0 if box_a.get_center().x > box_b.get_center().x else -1.0
								# Split 50/50 and add a small safety cushion (2.0 pixels like your original code)
								var push_amount = (overlap_x * 0.5) + 2.0
								npc_a.global_position.x += dir_x * push_amount
								npc_b.global_position.x -= dir_x * push_amount
							else:
								var dir_y = 1.0 if box_a.get_center().y > box_b.get_center().y else -1.0
								var push_amount = (overlap_y * 0.5) + 2.0
								npc_a.global_position.y += dir_y * push_amount
								npc_b.global_position.y -= dir_y * push_amount
	
	# Wipe solid cell layout caches so algorithms reconstruct clean maps on strategy changes
	clear_solid_cells()
	get_tree().call_group("NPCs", "on_global_mode_changed")

func spawn_npcs() -> void:
	for i in range(npcs.size()): 
		var new_npc = NPC_SCENE.instantiate()
		
		# Populate npc properties
		new_npc.npc_color = i
		new_npc.name = str("NPCs_", i)
		new_npc.global_position = spawn_positions[i]
		new_npc.world = self
		
		# Populate targets for npcs 
		var raw_life_targets = all_life_targets.get(i, [])
		var typed_life: Array[Vector2] = []
		typed_life.assign(raw_life_targets)
		
		new_npc.life_targets = typed_life
		new_npc.race_targets = race_targets
		
		# Add npc to scene and add to NPC group
		add_child(new_npc)
		new_npc.add_to_group("NPCs")
		spawned_npcs.append(new_npc)

		
func resolve_initial_spawn_overlaps() -> void: 
	if(spawned_npcs.is_empty()):
		return
	
	# Compare one npc with all those after it
	for i in range(spawned_npcs.size()):
		for j in range(i + 1, spawned_npcs.size()):
			var npc_a = spawned_npcs[i]
			var npc_b = spawned_npcs[j]

			var aabb_a = get_aabb_for_node(npc_a)
			var aabb_b = get_aabb_for_node(npc_b)
			
			if aabb_vs_aabb(npc_a, npc_b):
				# Calculate overlap on both axes
				var overlap_x = min(aabb_a.end.x, aabb_b.end.x) - max(aabb_a.position.x, aabb_b.position.x)
				var overlap_y = min(aabb_a.end.y, aabb_b.end.y) - max(aabb_a.position.y, aabb_b.position.y)
			
				# Push out along shallowest penetration axis
				if overlap_x < overlap_y:
					var dir = 1.0 if aabb_a.get_center().x < aabb_b.get_center().x else -1.0
					npc_a.global_position.x -= overlap_x * 0.5 * dir	
					npc_b.global_position.x -= overlap_x * 0.5 * dir	
		
				else	:
					var dir = 1.0 if aabb_a.get_center().y < aabb_b.get_center().y else -1.0
					npc_a.global_position.y -= overlap_y * 0.5 * dir	
					npc_b.global_position.y -= overlap_y * 0.5 * dir	
	
