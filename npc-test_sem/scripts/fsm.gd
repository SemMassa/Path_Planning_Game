class_name FiniteStateMachine
extends Node
## Owns exactly one active NPCState at a time and forwards update() to it
## every frame. States are looked up by their node name (e.g. "WalkState"),
## so change_state("WalkState") finds the sibling node with that name.

@export var current_state: NPCState

var npc: NPC

## Injects shared references into every state and enters the first one.
## Call once, after npc's own @onready state is set up.
func initialize(owning_npc: NPC) -> void:
	npc = owning_npc
	for child in get_children():
		if child is NPCState:
			child.npc = npc
			child.fsm = self

	if not current_state and get_child_count() > 0:
		current_state = get_child(0)
	if current_state:
		current_state.enter()

## Runs in _physics_process rather than _process: WalkState's movement
## calls move_and_slide(), which must happen on the physics tick.
func _physics_process(delta: float) -> void:
	if current_state:
		current_state.update(delta)

## Switches to the sibling state named state_name, calling exit() on the
## old state and enter(msg) on the new one. msg carries small bits of
## context between states, e.g. which direction the NPC was last facing.
func change_state(state_name: String, msg: Dictionary = {}) -> void:
	var new_state: NPCState = get_node_or_null(state_name)
	if not new_state:
		push_error("State not found: " + state_name)
		return
	if new_state == current_state:
		return

	if current_state:
		current_state.exit()
	current_state = new_state
	current_state.enter(msg)
