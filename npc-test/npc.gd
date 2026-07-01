
extends CharacterBody2D
class_name GameNPC

enum NPCColor {GREEN, BLUE, RED}

const FRAME_DURATION: float = 0.15 # Timing loop for custom row updates

# Configuration exports
@export var speed: float = 120.0

var life_targets: Array[Vector2] = []
var race_targets: Array[Vector2] = []

# Assets
var texture_paths: Array[String] = [
	"res://sprite_sheets/green_sprites.png",
	"res://sprite_sheets/blue_sprites.png",
	"res://sprite_sheets/red_sprites.png"]
#
var json_paths: Array[String] = 	[
	"res://sprite_sheets/green_sprites.json",
	"res://sprite_sheets/blue_sprites.json",
	"res://sprite_sheets/red_sprites.json"] 

# Component References
@onready var path_planner: PathPlanner2D = $PathPlanner2D
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var sprite: Sprite2D             = $Sprite2D
@onready var FSM: FiniteStateMachine      = $FiniteStateMachine

#@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

@onready var world: Node = get_tree().current_scene

# Values passed from main
var npc_color: NPCColor = NPCColor.GREEN
var algorithm: PathPlanner2D.AlgorithmType = PathPlanner2D.AlgorithmType.ASTAR

var current_target_idx: int = 0
var animation_bounds: Dictionary = {}

var current_collision_size = Vector2(24,28)

func _ready() -> void:
	# Configure standard navigation agent defaults

	# Read textures and animations for associated color enum value passed from main
	if npc_color < texture_paths.size() and npc_color < json_paths.size():
		var loaded_texture = load(texture_paths[npc_color])
		if loaded_texture: 
			sprite.texture = loaded_texture
		
		# Parse corresponding json file
		parse_libresprite_json(json_paths[npc_color])
	
		# configure path planner
		path_planner.speed = speed
		path_planner.set_current_extents(current_collision_size)
		path_planner.set_algorithm_by_type(algorithm)
		
		# Initialize the finite state machine
		FSM.initialize_fsm() 

func _physics_process(delta: float) -> void:
	
	# Keep state tick moving forward every single physical frame
	if FSM: FSM.process_states(delta)	


# Advance to the next target in the target array 
func advance_to_next_target() -> void:
	
	var target_array = get_active_targets()
	if target_array.is_empty(): 
		return
	
	# Loop through targets, circle back once we reached the end
	current_target_idx = (current_target_idx + 1) % target_array.size()

	# Set new target in path planning algorithm
	path_planner.set_target(get_target_pos())

func get_target_pos() -> Vector2:
	var target_array = get_active_targets()
	
	# Return current target if in range
	if current_target_idx < target_array.size():
		return target_array[current_target_idx]
	
	# Already at our target, return global position 
	return global_position		
	
func get_active_targets() -> Array[Vector2]:
	
	# Return life targets by default
	if not world or not "current_mode" in world: 
		return life_targets
	
	if world.current_mode == world.PatrolMode.LIFE:
		return life_targets
	
	else:
		return race_targets

func get_direction() -> String: 
	# If NPC is standing still/barely moving, don't change direction (looks bad)
	# Can do check velocity.length < 20.0 for this
	
	# Since velocity.length involves some square roots, and that is expensive, we can use 
	# length_squared, as long as we square the other side 20^2 = 400
	
	if velocity.length_squared() < 400.0:
		return ""
		
	
	# Compare horizontal and vertical magnitude:
	#	 If horizontal magnitude larger, moving left/right, else up/down
	if abs(velocity.x) > abs(velocity.y):
		return "right" if velocity.x > 0 else "left"
	else:
		## Note that in Godot down = positive y
		return "down" if velocity.y > 0 else "up"

# Signal after switching between race and life
func on_global_mode_changed() -> void:
	current_target_idx = 0 # clear current target (starting over)
	
	# Force custon path planner to shift target destinations
	path_planner.set_target(get_target_pos())
	
	# force into walk cycle if not already in it
	if FSM.current_state.name != "WalkState":
		FSM.change_state("WalkState")
		
func file_accessible(file_path) -> bool: 
	if not FileAccess.file_exists(file_path):
		push_error("File at path %s not found" % file_path)
		return false
	return true 

func parse_libresprite_json(json_file: String) -> void: 
	if not file_accessible(json_file): 
		return
	
	# Load and parse the JSON file
	var file = FileAccess.open(json_file, FileAccess.READ)
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("Failed to parse file %s " % json_file)
		return 
		
	var data = json.get_data()
	
	# Dynamic spritesheet layout calculation, 
	#	so we show only one sprite instead of entire spritesheet
	
	if sprite.texture: 
		# LibreSprite json script is structured like a dictionary: 
		#	Each frame is keyed by the cell name 
		#	Each cell will have the same width and height
		var frames_data = data["frames"]
		var first_frame_key = frames_data.keys()[0]
		
		if first_frame_key:
			var first_frame_meta = frames_data[first_frame_key]["frame"]
			
			# Grab dimensions from the first frame
			if first_frame_meta:
				var cell_w = float(first_frame_meta["w"])
				var cell_h = float(first_frame_meta["h"])
		
				# Get total size of the loaded image 
				var total_w = sprite.texture.get_width()
				var total_h = sprite.texture.get_height()
				
				# Calculate and apply grid slots (Total size / cell size)
				sprite.hframes = clampi(roundi(total_w / cell_w), 1, 999)
				sprite.vframes = clampi(roundi(total_h / cell_h), 1, 999)

	# Create animation library object and start reading frame tags
	var library = AnimationLibrary.new()	
	var tags = data["meta"]["frameTags"]
	
	for tag in tags: 
		var anim_name = tag["name"]
		var start_frame = int(tag["from"])
		var end_frame = int(tag["to"])
		
		# Create animation object, and index that points to the Sprite2D frame property
		var anim = Animation.new()
		var track_idx = anim.add_track(Animation.TYPE_VALUE)
		
		# Set the node path to point animation player to the character
		# Set interpolation to Nearest/Constant so key frames change instanty
		#  instead of calculating in between frame (since pixel art)
		anim.track_set_path(track_idx, "Sprite2D:frame")
		anim.track_set_interpolation_type(track_idx, Animation.INTERPOLATION_NEAREST)
		
		# Set loop mode to linear since on going animation 
		anim.loop_mode = Animation.LOOP_LINEAR 
		
		# Calculate timeline pacing based on frames and total animation duration 
		var frame_count = (end_frame - start_frame) + 1
		anim.length =  frame_count * FRAME_DURATION
		
		# Inject keyframes onto the timeline
		var current_time = 0.0
		for frame in range(start_frame, end_frame + 1):
			anim.track_insert_key(track_idx, current_time, frame)
			current_time += FRAME_DURATION
					
		library.add_animation(anim_name, anim)
		
		#Save metadata
		animation_bounds[tag["name"]] = {
			"start": int(tag["from"]),
			"end": int(tag["to"])}
	
	# Add created library to character
	anim_player.add_animation_library("",library)
