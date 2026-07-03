class_name DashboardPanel
extends CanvasLayer
## Shared base for BenchmarkDashboard/LifeDashboard: both are a CanvasLayer
## wrapping the same PanelContainer/VBoxContainer/GridContainer layout and
## fill it with the same colored Label pattern, only what goes in the rows
## differs between the two.

@onready var _grid_container: GridContainer = $PanelContainer/VBoxContainer/GridContainer

## Adds one Label with text in color to the grid and returns it, so callers
## that need to keep updating it (see LifeDashboard) can hold onto the reference.
func _add_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	_grid_container.add_child(label)
	return label
