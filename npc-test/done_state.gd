extends NPCState

# inherits from our NPCState basic class 
func enter(msg: Dictionary = {}) -> void: 
	# set actor animation through actor reference
	print("Switching to DONE state")

	# Kill movement + animation
	actor.velocity = Vector2.ZERO # Stop movement
	actor.anim_player.stop()      # Stop animation
	
	# Set animation based on direction passed from last state
	var current_dir = msg.get("facing", "down")
	var anim_name = current_dir + "_idle"

	if actor.animation_bounds.has(anim_name):
		var target_frame = actor.animation_bounds[anim_name]["start"]
		actor.sprite.frame = target_frame
	
func update(_delta: float) -> void: 
	actor.velocity = Vector2.ZERO
	
func exit() -> void: 
	print("Exiting DONE")		
