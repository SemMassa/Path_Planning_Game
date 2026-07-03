class_name LifeWaitState
extends NPCState
## Life mode only: a brief pause at spot 1/2/3 before continuing the cycle
## (1 -> 2 -> 3 -> 1 -> ...). Reached only from WalkState when
## npc.is_in_life_mode() is true, mirrors WaitState's timer/idle pattern but
## hands off to npc.go_to_next_life_spot() instead of BlockState. Also
## fires npc.life_spot_reached, for main.gd's live Life mode benchmark
## dashboard, since this is always a genuine arrival at a hotspot.

const WAIT_TIME: float = 1.5 # seconds

var _timer: float = 0.0

func enter(msg: Dictionary = {}) -> void:
	_timer = WAIT_TIME
	animate(msg.get("facing", npc.facing_direction()) + "_idle")
	npc.life_spot_reached.emit()

func update(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		npc.go_to_next_life_spot()
