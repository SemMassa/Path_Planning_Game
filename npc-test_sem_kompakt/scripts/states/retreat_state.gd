class_name RetreatState
extends NPCState
## Reacts to a blocked path for pathfinders whose block_reaction() is
## RETREAT (plain A*, JPS): never recomputes a route. Instead steps
## backward through the cells already walked, as if physically pushed back
## by whatever is blocking the next forward cell, until that cell is
## walkable again, then hands control back to WalkState to continue
## forward on the exact same, original path.

var _blocked_cell: Vector2i # the cell we failed to enter, fixed for this whole retreat

## Remembers which cell is actually blocked once, on entry. Checking
## npc.current_target_cell() every tick instead would be wrong: it moves
## one cell closer with every retreat_step(), so it would eventually point
## at a cell behind us that was never blocked, making this think the way
## is clear after a single step back.
func enter(_msg: Dictionary = {}) -> void:
	_blocked_cell = npc.current_target_cell()
	_update_retreat_animation()

func update(_delta: float) -> void:
	if npc.grid.is_walkable(_blocked_cell):
		fsm.change_state("WalkState")
		return

	if npc.retreat_step():
		_update_retreat_animation()
	else:
		# Already back at the very first path cell, nowhere left to
		# retreat to, just wait here facing the blockage.
		animate(npc.facing_direction() + "_idle")

func _update_retreat_animation() -> void:
	animate(npc.facing_direction() + "_walk")
