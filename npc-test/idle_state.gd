extends NPCState

const WAIT_TIME  = 2.0 # arbitrary wait time 
var timer: float = 0.0

# inherits from our NPCState basic class 
func enter(msg: Dictionary = {}) -> void: 
	# set actor animation through actor reference
	print("Switching to IDLE state")
			
	# Kill movement
	actor.velocity = Vector2.ZERO # Stop movement
	timer = 2.0 # arbitrary value
	
	# Animation only has one direction, so don't worry about finding direction
	self.animate("clean")

	# advance the target
	actor.advance_to_next_target()

func update(delta: float) -> void: 
	timer -= delta
	
	# wait_time is at 0, begin walking again 
	if timer <= 0.0:
		fsm.change_state("WalkState")	
		
func exit() -> void: 
	print("Exiting IDLE")		
