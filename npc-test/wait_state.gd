extends NPCState

const WAIT_TIME: float = 2.0
var timer: float = 0.0

func enter(msg: Dictionary = {}, frame_data = {}) -> void: 
	print("Entering WaitState")
	
	# Need to add this because if we were already in wait, we should recalculate 
	frame_data["from_wait"] = true
	
	actor.velocity = Vector2.ZERO
	timer = WAIT_TIME
	
	# Set animation based on NPC's current direction
	var current_dir = msg.get("facing", "down")
	var anim_name = current_dir + "_idle"
	self.animate(anim_name)
		
func update(delta: float) -> void:
	timer -= delta
	if timer <= 0.0: 
		fsm.change_state("BlockState")

func exit() -> void: 
	print("Exiting WaitState")
	
