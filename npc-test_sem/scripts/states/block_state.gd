class_name BlockState
extends NPCState
## Reacts to a blocked path. If the blocking cell already cleared, just
## resume walking. Otherwise try to recompute a route around it, if that
## fails entirely (fully boxed in), wait a bit and try again later.

func enter(_msg: Dictionary = {}) -> void:
	if npc.path_finished() or npc.grid.is_walkable(npc.current_target_cell()):
		fsm.change_state("WalkState")
	elif npc.recalculate_path():
		fsm.change_state("WalkState")
	else:
		fsm.change_state("WaitState", {"facing": npc.facing_direction()})
