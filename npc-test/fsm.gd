extends Node
class_name FiniteStateMachine

@export var current_state: Node 
var actor: CharacterBody2D # character ref

# Basic finite state machine control. All states have their own script. 
# This control is used to direct our current_state to the correct script

# Called to initialize the fsm
func initialize_fsm() -> void:
	# Get parent NPC body
	actor = get_parent()
		
	# Inject actor and the finite state references into each state
	for child in get_children():
		if child is NPCState:
			child.actor = actor
			child.fsm = self
		
	# If we don't have a selected current state in inspector and we have available states, 
	# set current state to first available state
	if not current_state and get_child_count() > 0: 
		current_state = get_child(0)
			
	# Enter the current state if we have one 
	if current_state: 
		current_state.enter() 	
		
# process the state 
func process_states(delta: float) -> void: 
	if current_state: 
		current_state.update(delta)

# Change the current state		
func change_state(state_name: String, msg: Dictionary = {}) -> void:	
	var new_state = get_node_or_null(state_name)
	
	# Let user know if they changed to a wrong state (learned from experience)
	if not new_state: 
		push_error("State not found: " + new_state)
		return 
	
	# If new state is the current state, do nothing
	if new_state == current_state: 
		return 
		
	# Exit out of current state and enter new one 
	if current_state:
		current_state.exit()
	
	current_state = new_state
	current_state.enter(msg)
