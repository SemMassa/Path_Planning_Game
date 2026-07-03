class_name NPCState
extends Node
## Base class for every finite state machine state. Concrete states
## override enter()/update()/exit(); this class only wires up the shared
## references every state needs and a shared animation helper.

var npc: NPC
var fsm: FiniteStateMachine

func enter(_msg: Dictionary = {}) -> void:
	pass

func exit() -> void:
	pass

func update(_delta: float) -> void:
	pass

## Plays anim_name only if it is not already playing, so a looping
## animation does not restart from frame 0 every single frame.
func animate(anim_name: String) -> void:
	if npc.anim_player.current_animation != anim_name:
		npc.anim_player.play(anim_name)
