class_name WalkState
extends NPCState
## Moves the NPC toward its next path cell and keeps the walk animation in
## sync with its facing direction. If the next cell is no longer walkable
## (the patrolling Obstacle moved onto it), or a real physical collision
## happens anyway (a safety net alongside that proactive grid check), hands
## off to whichever state matches the current pathfinder's block_reaction():
## RetreatState for algorithms meant to stick to their original path (plain
## A*, JPS), BlockState for ones meant to replan (D* Lite).

func enter(_msg: Dictionary = {}) -> void:
	_update_walk_animation()

func update(_delta: float) -> void:
	if npc.path_finished():
		fsm.change_state(_arrival_state_name(), {"facing": npc.facing_direction()})
		return

	if not npc.grid.is_walkable(npc.current_target_cell()):
		fsm.change_state(_block_state_name())
		return

	npc.advance_step()
	_update_walk_animation()

	if npc.just_collided():
		fsm.change_state(_block_state_name())

func _update_walk_animation() -> void:
	animate(npc.facing_direction() + "_walk")

## Which state handles a blocked path, decided by the pathfinder currently
## driving this NPC, so different algorithms can react completely
## differently to the exact same blockage.
func _block_state_name() -> String:
	if npc.pathfinder.block_reaction() == Pathfinder.BlockReaction.RETREAT:
		return "RetreatState"
	return "BlockState"

## Race mode just stops at DoneState. Life mode (npc.is_in_life_mode())
## instead pauses briefly at the spot it just reached, then moves on to the
## next one in the A -> B -> C -> A ... cycle.
func _arrival_state_name() -> String:
	if npc.is_in_life_mode():
		return "LifeWaitState"
	return "DoneState"
