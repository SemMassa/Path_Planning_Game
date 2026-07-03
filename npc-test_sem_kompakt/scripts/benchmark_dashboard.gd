class_name BenchmarkDashboard
extends DashboardPanel
## Shown once every active Race mode NPC has either reached the goal or
## failed to find a path to it at all (see main.gd's _benchmarks tracking
## and _build_benchmark_results()). Displays each algorithm's own numbers
## side by side: finish time, cells the search touched, path length, and
## Cells/Path (touched cells divided by path length, lower means a more
## tightly focused search instead of fanning out over the map).
##
## No close button: the only way to dismiss this is a right click, which
## restarts the whole game (see main.gd's _unhandled_input()) rather than
## just hiding the panel.

func _ready() -> void:
	_add_header_row()

## results is an Array[Dictionary], one per NPC, each carrying at least
## "label", "color", and "status" ("done" or "failed"), plus
## "elapsed_ms"/"explored"/"path_length"/"efficiency" whenever status is
## "done". See main.gd's _build_benchmark_results().
func show_results(results: Array[Dictionary]) -> void:
	for result in results:
		_add_result_row(result)

func _add_header_row() -> void:
	_add_label("Algorithm", Color.WHITE)
	_add_label("Time (s)", Color.WHITE)
	_add_label("Cells", Color.WHITE)
	_add_label("Path Length", Color.WHITE)
	_add_label("Cells/Path", Color.WHITE)

## One row per NPC, in its own accent color so it lines up with that same
## color's grid title and overlay. A failed NPC only gets a short message
## instead of numbers that were never computed.
func _add_result_row(result: Dictionary) -> void:
	var color: Color = result["color"]
	_add_label(result["label"], color)
	if result["status"] != "done":
		_add_label("no path found", color)
		_add_label("-", color)
		_add_label("-", color)
		_add_label("-", color)
		return
	_add_label("%.2f" % (result["elapsed_ms"] / 1000.0), color)
	_add_label(str(result["explored"]), color)
	_add_label(str(result["path_length"]), color)
	_add_label("%.2f" % result["efficiency"], color)
