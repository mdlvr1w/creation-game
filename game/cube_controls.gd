extends PanelContainer

const CONTROLS := {
	&"mass": ["Weight (kg)", 0.25, 30.0, 0.05],
	&"bounce": ["Bounciness", 0.0, 1.0, 0.01],
	&"friction": ["Surface friction", 0.0, 1.0, 0.01],
}

signal property_changed(key: StringName, value: float)
var fields: Dictionary[StringName, SpinBox] = {}


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#20292e")
	style.border_color = Color("#9c683e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, 12)
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	var heading := HBoxContainer.new()
	column.add_child(heading)
	var title := Label.new()
	title.text = "Orange cube"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(hide)
	heading.add_child(close)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	column.add_child(grid)
	for key: StringName in CONTROLS:
		add_control(grid, key)
	hide()


func add_control(grid: GridContainer, key: StringName) -> void:
	var config: Array = CONTROLS[key]
	var label := Label.new()
	label.text = config[0]
	grid.add_child(label)
	var slider := HSlider.new()
	slider.custom_minimum_size.x = 86
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	grid.add_child(slider)
	var field := SpinBox.new()
	field.custom_minimum_size.x = 78
	grid.add_child(field)
	fields[key] = field
	for control: Range in [slider, field]:
		control.min_value = config[1]
		control.max_value = config[2]
		control.step = config[3]
	slider.share(field)
	field.value_changed.connect(func(value: float): property_changed.emit(key, value))
	field.get_line_edit().text_submitted.connect(func(_value: String):
		field.get_line_edit().release_focus()
	)


func open_at(cursor: Vector2, values: Dictionary) -> void:
	for key: StringName in fields:
		fields[key].set_value_no_signal(values[key])
	show()
	reset_size()
	var viewport := get_viewport_rect().size
	var x := cursor.x + 24.0
	if x + size.x > viewport.x - 12.0:
		x = cursor.x - size.x - 24.0
	position = Vector2(
		clampf(x, 12.0, maxf(12.0, viewport.x - size.x - 12.0)),
		clampf(cursor.y - size.y * 0.5, 12.0, maxf(12.0, viewport.y - size.y - 12.0))
	)
