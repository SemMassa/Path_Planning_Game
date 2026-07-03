class_name BenchmarkDashboard
extends CanvasLayer
## Shown once every active Race mode NPC has either reached the goal or
## failed to find a path to it at all (see main.gd's _benchmarks tracking
## and _build_benchmark_results()). Displays each algorithm's own numbers
## side by side in a table: finish time, cells the search touched, path
## length, and search efficiency (touched cells / path length, lower means
## a more tightly focused search instead of fanning out over the map).

## No close button: the only way to dismiss this is a right click, which
## restarts the whole game (see main.gd's _unhandled_input()) rather than
## just hiding the panel, so there is nothing partial to leave open here.
@onready var _grid_container: GridContainer = $PanelContainer/VBoxContainer/GridContainer

func _ready() -> void:
	_add_header_row()

## results is an Array[Dictionary], one per NPC, each carrying at least
## "label", "color", and "status" ("done" or "failed"), plus
## "elapsed_ms"/"explored"/"path_length"/"efficiency" whenever status is
## "done". See main.gd's _build_benchmark_results().
func show_results(results: Array[Dictionary]) -> void:
	for result in results:
		_add_result_row(result)

## Column headers, plain white so they read as labels, not another result row.
func _add_header_row() -> void:
	_add_label("Algorithmus", Color.WHITE)
	_add_label("Zeit (s)", Color.WHITE)
	_add_label("Zellen", Color.WHITE)
	_add_label("Pfadlänge", Color.WHITE)
	_add_label("Effizienz", Color.WHITE)

## One row per NPC, in its own accent color so it lines up with that same
## color's grid title and overlay. A failed NPC only gets a short message
## instead of numbers that were never computed.
func _add_result_row(result: Dictionary) -> void:
	var color: Color = result["color"]
	_add_label(result["label"], color)
	if result["status"] != "done":
		_add_label("kein Pfad gefunden", color)
		_add_label("-", color)
		_add_label("-", color)
		_add_label("-", color)
		return
	_add_label("%.2f" % (result["elapsed_ms"] / 1000.0), color)
	_add_label(str(result["explored"]), color)
	_add_label(str(result["path_length"]), color)
	_add_label("%.2f" % result["efficiency"], color)

func _add_label(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	_grid_container.add_child(label)
