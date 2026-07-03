class_name WaitState
extends NPCState
## Brief pause after hitting a blocked cell. Every block in this project
## is caused by the one patrolling Obstacle (maze walls never change
## after generation), so this just gives it a moment to wander off on
## its own before BlockState tries to repair or recompute the route.

const WAIT_TIME: float = 1.0 # seconds

var _timer: float = 0.0

func enter(msg: Dictionary = {}) -> void:
	_timer = WAIT_TIME
	animate(msg.get("facing", npc.facing_direction()) + "_idle")

func update(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		fsm.change_state("BlockState")
