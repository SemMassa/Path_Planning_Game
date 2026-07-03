class_name DoneState
extends NPCState
## Resting state: no path is currently being walked, either the NPC just
## spawned, reached its goal, or was sent to an unreachable one. Stops
## movement and holds a facing appropriate idle pose.

func enter(msg: Dictionary = {}) -> void:
	animate(msg.get("facing", npc.facing_direction()) + "_idle")
