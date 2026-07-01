extends Node
class_name NPCState

# Abstract class for finite state 

var actor: CharacterBody2D # NPC 
var fsm: FiniteStateMachine # The finite state machine
var planner: PathPlanner2D  # Path planner 

@onready var world_manager: Node = get_tree().current_scene


func enter(msg: Dictionary = {}) -> void: pass 
func exit() -> void: pass 
func update(_delta: float) -> void: pass

func animate(anim_name) -> void: 
	# Only trigger if not already playing 
	if actor.anim_player.current_animation != anim_name: 
		actor.anim_player.play(anim_name)
	
