class_name LifeDashboard
extends DashboardPanel
## Shown continuously once Life mode's spawn point is placed (see main.gd's
## _show_life_dashboard()). Unlike BenchmarkDashboard this is never a one
## shot result screen: it keeps refreshing for as long as the run goes on,
## until a new spawn point replaces it or a right click restarts the game.
## Displays each algorithm's own live numbers: elapsed time, hotspots
## reached so far, and its hotspot rate (reached count / elapsed minutes).

# One entry per NPC/row, in the same order show_entries() received them, so
# main.gd's update_entry(index, ...) can address a row by that same index.
# "start_ms" and "reached_count" are read every frame in _process() (the
# rate depends on both, so it must be recomputed continuously), the label
# references let it update text in place without rebuilding the row.
var _rows: Array[Dictionary] = []

func _ready() -> void:
	_add_header_row()

## entries is an Array[Dictionary], one per NPC, each with "label", "color"
## (see main.gd's ALGORITHM_LABELS/ALGORITHM_COLORS), and "start_ms" (when
## this NPC's current Life mode run began). Builds one row per entry.
func show_entries(entries: Array[Dictionary]) -> void:
	_rows.clear()
	for entry in entries:
		_add_entry_row(entry)

## Refreshes row index's hotspot count, called by main.gd every time that
## NPC completes a leg (reaches its next hotspot). Elapsed time and the
## rate that depends on it refresh on their own every frame, see _process().
func update_entry(index: int, reached_count: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	_rows[index]["reached_count"] = reached_count
	(_rows[index]["reached_label"] as Label).text = str(reached_count)

## Keeps every row's elapsed-time and hotspot-rate labels live, independent
## of whatever triggers update_entry(), so both keep ticking even while an
## NPC is still walking toward its next hotspot.
func _process(_delta: float) -> void:
	for row in _rows:
		var elapsed_s: float = (Time.get_ticks_msec() - (row["start_ms"] as int)) / 1000.0
		(row["time_label"] as Label).text = "%.1f" % elapsed_s

		var reached_count: int = row["reached_count"]
		var rate_text: String = "-"
		if elapsed_s > 0.0:
			rate_text = "%.1f" % (reached_count / (elapsed_s / 60.0))
		(row["rate_label"] as Label).text = rate_text

func _add_header_row() -> void:
	_add_label("Algorithm", Color.WHITE)
	_add_label("Time (s)", Color.WHITE)
	_add_label("Hotspots Reached", Color.WHITE)
	_add_label("Hotspots/Min", Color.WHITE)

func _add_entry_row(entry: Dictionary) -> void:
	var color: Color = entry["color"]
	_add_label(entry["label"], color)
	var time_label: Label = _add_label("0.0", color)
	var reached_label: Label = _add_label("0", color)
	var rate_label: Label = _add_label("-", color)
	_rows.append({
		"start_ms": entry["start_ms"],
		"reached_count": 0,
		"time_label": time_label,
		"reached_label": reached_label,
		"rate_label": rate_label,
	})
