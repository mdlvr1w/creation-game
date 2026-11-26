extends PanelContainer

signal factor_changed(index: int, factor: float)

const Mannequin := preload("res://game/mannequin.gd")
const LABELS := ["Size", "Length", "Thickness"]
const HELP := [
	"Scales the length and thickness together.",
	"Changes the distance between the joints.",
	"Changes the width without moving the joints.",
]

var title := Label.new()
var sliders: Array[HSlider] = []
var fields: Array[SpinBox] = []


func _ready() -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color("#20292e")
	background.border_color = Color("#51656b")
	background.set_border_width_all(1)
	background.set_corner_radius_all(8)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		background.set_content_margin(side, 12)
	add_theme_stylebox_override("panel", background)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	add_child(column)
	title.add_theme_font_size_override("font_size", 18)
	column.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 9)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)

	for index in LABELS.size():
		var label := Label.new()
		label.text = LABELS[index]
		label.tooltip_text = HELP[index]
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(label)

		var slider := HSlider.new()
		slider.tooltip_text = HELP[index]
		slider.custom_minimum_size.x = 105
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(slider)
		sliders.append(slider)

		var field := SpinBox.new()
		field.suffix = "%"
		field.custom_minimum_size.x = 80
		grid.add_child(field)
		fields.append(field)

		for control: Range in [slider, field]:
			control.min_value = Mannequin.MIN_FACTOR * 100
			control.max_value = Mannequin.MAX_FACTOR * 100
			control.step = 1
			control.value = 100
			control.value_changed.connect(change_factor.bind(index))
	hide()


func show_limb(limb_name: StringName, factors: Vector3) -> void:
	title.text = String(limb_name).capitalize()
	for index in LABELS.size():
		sliders[index].set_value_no_signal(factors[index] * 100)
		fields[index].set_value_no_signal(factors[index] * 100)
	show()


func change_factor(percent: float, index: int) -> void:
	sliders[index].set_value_no_signal(percent)
	fields[index].set_value_no_signal(percent)
	factor_changed.emit(index, percent / 100.0)
