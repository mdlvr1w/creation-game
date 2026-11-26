extends Node3D

const Mannequin := preload("res://game/mannequin.gd")
const Controller := preload("res://game/mannequin_controller.gd")
const Settings := preload("res://game/movement_settings.gd")
const TUNING_LABELS := {
	&"min_speed": "Min walk speed",
	&"max_speed": "Max walk speed",
	&"min_jump": "Tap jump strength",
	&"max_jump": "Hold jump strength",
	&"lean_degrees": "Forward lean (°)",
}
const Stage := preload("res://game/mannequin_stage.gd")

var player := Controller.new()
var camera := Camera3D.new()
var proportions := ""
var jump_pressed := false
var tuning_sliders: Dictionary[StringName, HSlider] = {}
var tuning_numbers: Dictionary[StringName, Label] = {}
var tuning_status := Label.new()


func _ready() -> void:
	add_child(Stage.new())
	add_platform(Vector3(0, -0.5, 0), Vector3(180, 1, 16), Color("#404b51"), false)
	add_platform(Vector3(6, 0.32, 0), Vector3(2.1, 0.64, 2.6), Color("#587e79"), true)
	for index in range(-19, 20):
		add_floor_marker(index * 2.5)

	add_child(player)
	player.reset()
	if FileAccess.file_exists(Settings.LOCAL_FILE) and not player.settings.load_from():
		tuning_status.text = "Could not load saved movement settings."
	var visual := Mannequin.new()
	# Bind after the visual is ready so the pose uses the current proportions.
	player.motion.add_child(visual)
	var tree := get_tree()
	proportions = tree.get_meta("preview_proportions", FileAccess.get_file_as_string(Mannequin.WORKING_PROPORTIONS))
	if tree.has_meta("preview_proportions"):
		tree.remove_meta("preview_proportions")
	visual.decode_proportions(proportions)
	visual.position.y = -visual.floor_height
	player.motion.bind_model(visual)

	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.6
	add_child(camera)
	update_camera(0.0)
	camera.make_current()
	add_controls()


func _input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey and event.physical_keycode == KEY_SPACE:
		jump_pressed = true
	elif event is InputEventJoypadButton and event.button_index == JOY_BUTTON_A:
		jump_pressed = true


func _physics_process(delta: float) -> void:
	var left := Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)
	var right := Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
	var direction := float(right) - float(left)
	var jump_held := Input.is_physical_key_pressed(KEY_SPACE)
	var analog := 0.0
	for device in Input.get_connected_joypads():
		var stick := Controller.stick_intent(Input.get_joy_axis(device, JOY_AXIS_LEFT_X))
		if absf(stick) > absf(analog):
			analog = stick
		jump_held = jump_held or Input.is_joy_button_pressed(device, JOY_BUTTON_A)
	if not left and not right:
		direction = analog
	player.step(delta, direction, jump_held, jump_pressed)
	jump_pressed = false
	if absf(player.position.x) > 82.0 or player.position.y < -6.0:
		player.reset()


func _process(delta: float) -> void:
	update_camera(1.0 - exp(-delta * 7.0))


func update_camera(weight: float) -> void:
	var focus_x := lerpf(camera.position.x, player.position.x, weight)
	camera.position = Vector3(focus_x, 4.2, 10.0)
	camera.look_at(Vector3(focus_x, 1.9, 0))


func add_platform(center: Vector3, dimensions: Vector3, color: Color, visible_mesh: bool) -> void:
	var body := StaticBody3D.new()
	body.position = center
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = dimensions
	collider.shape = box
	body.add_child(collider)
	if visible_mesh:
		var mesh := BoxMesh.new()
		mesh.size = dimensions
		body.add_child(colored_mesh(mesh, color))
	add_child(body)


func add_floor_marker(x: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 0.006, 1.4)
	var marker := colored_mesh(mesh, Color("#657579"))
	marker.position = Vector3(x, 0.003, 1.9)
	add_child(marker)


func colored_mesh(mesh: PrimitiveMesh, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	instance.material_override = material
	return instance


func add_controls() -> void:
	var interface := CanvasLayer.new()
	add_child(interface)
	var panel := VBoxContainer.new()
	panel.position = Vector2(20, 18)
	panel.add_theme_constant_override("separation", 8)
	interface.add_child(panel)
	var buttons := HBoxContainer.new()
	panel.add_child(buttons)
	add_button(buttons, "Back to proportions", Callable(self, "return_to_viewer"))
	add_button(buttons, "Reset position", player.reset)
	add_button(buttons, "Save movement", save_movement)
	var hint := Label.new()
	hint.text = "A / D, ← / → or left stick to move   ·   Space or south face button to jump"
	panel.add_child(hint)
	for key: StringName in TUNING_LABELS:
		add_adjustment(panel, key)
	panel.add_child(tuning_status)


func add_button(row: HBoxContainer, caption: String, action: Callable) -> void:
	var button := Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 32
	button.pressed.connect(action)
	row.add_child(button)


func add_adjustment(panel: VBoxContainer, key: StringName) -> void:
	var row := HBoxContainer.new()
	panel.add_child(row)
	var label := Label.new()
	label.custom_minimum_size.x = 152
	label.text = TUNING_LABELS[key]
	row.add_child(label)
	var slider := HSlider.new()
	slider.custom_minimum_size.x = 130
	slider.focus_mode = Control.FOCUS_NONE
	var limits: Vector3 = Settings.LIMITS[key]
	slider.min_value = snappedf(limits.x, 0.1)
	slider.max_value = limits.y
	slider.step = 0.1
	slider.value = player.settings.values[key]
	row.add_child(slider)
	tuning_sliders[key] = slider
	var value_label := Label.new()
	value_label.text = "%.1f" % slider.value
	row.add_child(value_label)
	tuning_numbers[key] = value_label
	slider.value_changed.connect(adjust_movement.bind(key))


func adjust_movement(value: float, key: StringName) -> void:
	player.settings.adjust(key, value)
	for setting: StringName in tuning_sliders:
		var current: float = player.settings.values[setting]
		tuning_sliders[setting].set_value_no_signal(current)
		tuning_numbers[setting].text = "%.1f" % current
	tuning_status.text = "Unsaved movement settings"


func save_movement() -> void:
	tuning_status.text = "Movement settings saved." if player.settings.save_to() else "Could not save movement settings."


func return_to_viewer() -> void:
	var tree := get_tree()
	tree.set_meta("preview_proportions", proportions)
	if tree.change_scene_to_file("res://game/mannequin_view.tscn") != OK:
		tree.remove_meta("preview_proportions")
