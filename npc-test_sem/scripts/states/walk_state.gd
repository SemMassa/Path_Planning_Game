class_name WalkState
extends NPCState
## Moves the NPC toward its next path cell and keeps the walk animation
## in sync with its facing direction. If the next cell is no longer
## walkable (the patrolling Obstacle moved onto it), hands off to
## BlockState instead of walking straight into it. Also reacts if a
## real physical collision happens anyway, a safety net alongside the
## proactive grid check, e.g. if position and grid state ever briefly
## disagree.

func enter(_msg: Dictionary = {}) -> void:
	_update_walk_animation()

func update(_delta: float) -> void:
	# Only Race mode exists right now, reaching the goal always means
	# DoneState. A future Life mode (endless patrol) would branch here
	# into an IdleState instead, picking the next waypoint on its own.
	if npc.path_finished():
		fsm.change_state("DoneState", {"facing": npc.facing_direction()})
		return

	if not npc.grid.is_walkable(npc.current_target_cell()):
		fsm.change_state("BlockState")
		return

	npc.advance_step()
	_update_walk_animation()

	if npc.just_collided():
		fsm.change_state("BlockState")

func _update_walk_animation() -> void:
	animate(npc.facing_direction() + "_walk")
