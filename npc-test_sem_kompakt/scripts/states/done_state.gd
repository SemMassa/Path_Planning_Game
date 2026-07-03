class_name DoneState
extends NPCState
## Resting state: no path is currently being walked, either the NPC just
## spawned, reached its goal, or was sent to an unreachable one. Stops
## movement and holds a facing appropriate idle pose, and fires npc.arrived
## every time regardless of which of those three it was (main.gd sorts
## that out, see npc.gd's arrived signal doc comment).

func enter(msg: Dictionary = {}) -> void:
	animate(msg.get("facing", npc.facing_direction()) + "_idle")
	npc.arrived.emit()
