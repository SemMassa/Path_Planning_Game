extends NPCState

var current_dir = "down"

func enter(msg: Dictionary = {}) -> void: 
	
	print("Entering WalkState")
	_update_walk_animation(actor.velocity)
	
func update(delta) -> void: 
	
	# Update the aabb for npc 
	update_aabb()
	
	var movement_frame = planner.get_next_movement_frame(delta)
	
	# Collision happened, stop moving and enter blocked state	
	if movement_frame["status"] == "BLOCKED":
		actor.velocity = Vector2.ZERO
		fsm.change_state("BlockState", {"facing": current_dir})
		return 
	
	# Update velocity and position 
	actor.velocity = movement_frame["velocity"]
	actor.global_position += actor.velocity * delta
	
	# Update directional walking animation 
	_update_walk_animation(actor.velocity)
	
	if planner.destination_reached():
		# Stop velocity (no drift)
		actor.velocity = Vector2.ZERO
		
		# switch to idle or done (depending on mode)
		if world_manager.current_mode == world_manager.PatrolMode.RACE:
			fsm.change_state("DoneState", {"facing": current_dir})
		
		else:	
			fsm.change_state("IdleState", {"facing": current_dir})
		
func _update_walk_animation(velocity: Vector2) -> void: 
	
	# If not moving, do nothing
	if velocity.length() < 0.1: 
		return 
	
	# Get the new direction 
	current_dir = actor.get_direction()
	var anim_name = current_dir + "_walk"
		
	self.animate(anim_name)
	
func update_aabb() -> void: 
	if actor.sprite.texture: 
		var frame_w = actor.sprite.texture.get_width() / actor.sprite.hframes
		var frame_h = actor.sprite.texture.get_height() / actor.sprite.vframes
		actor.current_collision_size = Vector2(frame_w, frame_h)
