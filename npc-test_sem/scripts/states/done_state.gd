class_name DoneState
extends NPCState
## Resting state: no path is currently being walked, either the NPC just
## spawned, reached its goal, or was sent to an unreachable one. Stops
## movement and holds a facing appropriate idle pose, and fires npc.arrived
## every time regardless of which of those three it was, see npc.gd's own
## arrived signal doc comment for why that is main.gd's job to sort out.

func enter(msg: Dictionary = {}) -> void:
	animate(msg.get("facing", npc.facing_direction()) + "_idle")
	npc.arrived.emit()
