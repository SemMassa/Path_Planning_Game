class_name BlockState
extends NPCState
## Reacts to a blocked path, or to go_to() finding no path to the goal at
## all (current_path() empty here means that, since WalkState only ever
## hands off here mid walk with a non-empty path). If the way is already
## clear, just resume, otherwise try to recompute a route around it; if
## that fails too (fully boxed in, or the goal is unreachable this
## instant), wait a bit and try again. Repeats indefinitely, since
## patrolling Obstacles keep moving, so the way tends to open up eventually.

func enter(_msg: Dictionary = {}) -> void:
	if not npc.current_path().is_empty() and npc.grid.is_walkable(npc.current_target_cell()):
		fsm.change_state("WalkState")
	elif npc.recalculate_path():
		fsm.change_state("WalkState")
	else:
		fsm.change_state("WaitState", {"facing": npc.facing_direction()})
