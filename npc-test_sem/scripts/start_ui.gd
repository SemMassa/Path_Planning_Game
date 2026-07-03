class_name StartUI
extends CanvasLayer
## Shown once at launch: lets the player pick Race or Life mode, how many
## Obstacles to spawn, and which pathfinding algorithm(s) should run,
## before the actual run starts. Fires start_pressed and then removes
## itself, main.gd does the actual spawning once it hears that signal.
##
## Obstacle count and algorithm selection are shared by both modes (same
## fields either way), the two mode buttons only decide what main.gd does
## once the NPCs reach their first goal: stop (Race) or keep cycling
## through three spots A/B/C forever (Life).
##
## Algorithm identifiers ("astar", "dstar_lite", "jps") and the mode string
## ("race"/"life") are plain strings rather than enums: main.gd is the only
## place that needs to turn them into actual objects/behavior, an enum
## shared between two files for a single match statement would not pull
## its weight.

signal start_pressed(obstacle_count: int, algorithms: Array[String], mode: String)

@onready var _race_mode_button: Button = $PanelContainer/VBoxContainer/ModeContainer/RaceModeButton
@onready var _life_mode_button: Button = $PanelContainer/VBoxContainer/ModeContainer/LifeModeButton
@onready var _obstacle_count_box: SpinBox = $PanelContainer/VBoxContainer/ObstacleCountBox
@onready var _astar_check: CheckBox = $PanelContainer/VBoxContainer/AStarCheck
@onready var _dstar_lite_check: CheckBox = $PanelContainer/VBoxContainer/DStarLiteCheck
@onready var _jps_check: CheckBox = $PanelContainer/VBoxContainer/JPSCheck
@onready var _start_button: Button = $PanelContainer/VBoxContainer/StartButton

func _ready() -> void:
	_start_button.pressed.connect(_on_start_button_pressed)

func _on_start_button_pressed() -> void:
	start_pressed.emit(int(_obstacle_count_box.value), _selected_algorithms(), _selected_mode())
	queue_free()

func _selected_mode() -> String:
	return "life" if _life_mode_button.button_pressed else "race"

## Every algorithm whose checkbox is currently ticked. Can be empty, main.gd
## simply spawns no NPC at all in that case rather than guessing one.
func _selected_algorithms() -> Array[String]:
	var algorithms: Array[String] = []
	if _astar_check.button_pressed:
		algorithms.append("astar")
	if _dstar_lite_check.button_pressed:
		algorithms.append("dstar_lite")
	if _jps_check.button_pressed:
		algorithms.append("jps")
	return algorithms
