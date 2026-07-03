class_name LifeWaitState
extends NPCState
## Life mode only: a brief pause at spot A/B/C before continuing the cycle
## (A -> B -> C -> A -> ...). Reached only from WalkState when
## npc.is_in_life_mode() is true, mirrors WaitState's timer/idle pattern but
## hands off to npc.go_to_next_life_spot() instead of BlockState.

const WAIT_TIME: float = 1.5 # seconds

var _timer: float = 0.0

func enter(msg: Dictionary = {}) -> void:
	_timer = WAIT_TIME
	animate(msg.get("facing", npc.facing_direction()) + "_idle")

func update(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		npc.go_to_next_life_spot()
