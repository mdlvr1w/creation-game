extends Node3D

const PlaytestRecorder := preload("res://game/playtest_recorder.gd")
const Mannequin := preload("res://game/mannequin.gd")
const GrabCube := preload("res://game/grabbable_cube.gd")
const HeadLook := preload("res://game/controller_head_look.gd")
const Controller := preload("res://game/mannequin_controller.gd")
const Settings := preload("res://game/movement_settings.gd")
const TUNING_LABELS := {
	&"min_speed": "Min walk speed",
	&"max_speed": "Max walk speed",
	&"min_jump": "Tap jump strength",
	&"max_jump": "Hold jump strength",
	&"lean_degrees": "Forward lean (°)",
	&"gravity": "Gravity strength",
	&"air_inertia": "Air inertia (%)",
}
const TUNING_HELP := {
	&"gravity": "Higher gravity pulls the mannequin down faster.",
	&"air_inertia": "Higher inertia carries more momentum and makes midair turns slower.",
}
const Stage := preload("res://game/mannequin_stage.gd")

var player := Controller.new()
var cube := GrabCube.new()
var camera := Camera3D.new()
var proportions := ""
var jump_pressed := false
var tuning_sliders: Dictionary[StringName, HSlider] = {}
var tuning_fields: Dictionary[StringName, SpinBox] = {}
var head_look := HeadLook.new()
var motion_status := Label.new()
var tuning_status := Label.new()
var recorder := PlaytestRecorder.new()
var capture_status := Label.new()
var record_button: Button
var stop_record_button: Button


func _ready() -> void:
	add_child(Stage.new())
	add_platform(Vector3(0, -0.5, 0), Vector3(180, 1, 16), Color("#404b51"), false)
	add_platform(Vector3(-9.5, 0.14, 0), Vector3(2.25, 0.28, 2.6), Color("#587e79"), true)
	for index in 4:
		var height: float = [0.38, 0.82, 1.40, 2.15][index]
		var color := Color("#587e79").lightened(index * 0.045)
		add_platform(Vector3(5.4 + index * 2.05, height * 0.5, 0), Vector3(1.9, height, 2.6), color, true)
	for index in range(-19, 20):
		add_floor_marker(index * 2.5)

	add_child(cube)
	add_child(player)
	add_child(head_look)
	add_child(recorder)
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
	add_head_direction_line(visual.head)

	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.size = 7.6
	add_child(camera)
	update_camera()
	camera.make_current()
	add_controls()


func add_head_direction_line(head: MeshInstance3D) -> void:
	var indicator := MeshInstance3D.new()
	indicator.name = "HeadDirectionDebug"
	var line := CylinderMesh.new()
	line.top_radius = 0.012
	line.bottom_radius = 0.012
	line.height = 0.92
	indicator.mesh = line
	indicator.position.z = line.height * 0.5
	indicator.rotation.x = PI * 0.5
	indicator.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = Color("#ffcf4a")
	indicator.material_override = material
	head.add_child(indicator)


func _input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey and event.physical_keycode == KEY_SPACE and not typing_number():
		jump_pressed = true
	elif event is InputEventJoypadButton and event.button_index == JOY_BUTTON_A:
		jump_pressed = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and typing_number():
		get_viewport().gui_get_focus_owner().release_focus()


func _physics_process(delta: float) -> void:
	var use_keyboard := not typing_number()
	var left := use_keyboard and (Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	var right := use_keyboard and (Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
	var direction := float(right) - float(left)
	var jump_held := use_keyboard and Input.is_physical_key_pressed(KEY_SPACE)
	var analog := 0.0
	var raw_stick := 0.0
	var grab_held := use_keyboard and Input.is_physical_key_pressed(KEY_E)
	for device in Input.get_connected_joypads():
		var axis := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
		if absf(axis) > absf(raw_stick):
			raw_stick = axis
		analog = Controller.stick_intent(raw_stick)
		jump_held = jump_held or Input.is_joy_button_pressed(device, JOY_BUTTON_A)
		grab_held = grab_held or Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER)
	if not left and not right:
		direction = analog
	player.motion.head_look_target = head_look.sample()
	player.update_grip(cube, grab_held)
	player.step(delta, direction, jump_held, jump_pressed)
	if recorder.recording:
		record_physics(delta, direction, raw_stick, jump_held, grab_held)
	jump_pressed = false
	if absf(player.position.x) > 82.0 or player.position.y < -6.0 or cube.position.y < -6.0:
		reset_sandbox()


func reset_sandbox() -> void:
	recorder.log_event("reset_positions", {})
	player.reset()
	cube.reset()


func start_on_cube() -> void:
	reset_sandbox()
	player.position = cube.position + Vector3.UP * (GrabCube.HALF_SIZE + 0.03)
	player.reset_physics_interpolation()
	recorder.log_event("start_on_cube", {})


func typing_number() -> bool:
	return get_viewport().gui_get_focus_owner() is LineEdit


func _process(_delta: float) -> void:
	update_camera()
	if head_look.device < 0:
		motion_status.text = "Controller tilt unavailable"
	elif head_look.recenter_pending:
		motion_status.text = "Hold the controller comfortably to center the head"
	else:
		motion_status.text = "Tilt the controller to look around"


func update_camera() -> void:
	# Follow the same rendered position as the mannequin to keep it steady in the frame.
	var focus_x := player.get_global_transform_interpolated().origin.x
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
	add_button(buttons, "Reset positions", reset_sandbox)
	add_button(buttons, "Start on cube", start_on_cube)
	add_button(buttons, "Save movement", save_movement)
	add_button(buttons, "Center head", head_look.recenter)
	var hint := Label.new()
	hint.text = "A / D, ← / → or left stick to move   ·   Space or south face button to jump"
	panel.add_child(hint)
	var grab_hint := Label.new()
	grab_hint.text = "Hold R1 or E beside or on the orange cube · Jump to lift the face you grabbed"
	panel.add_child(grab_hint)
	for key: StringName in TUNING_LABELS:
		add_adjustment(panel, key)
	panel.add_child(tuning_status)
	panel.add_child(motion_status)
	var capture_buttons := HBoxContainer.new()
	panel.add_child(capture_buttons)
	record_button = add_button(capture_buttons, "Record", start_recording)
	stop_record_button = add_button(capture_buttons, "Stop recording", recorder.stop)
	stop_record_button.disabled = true
	capture_buttons.add_child(capture_status)
	recorder.status_changed.connect(update_recording_status)


func start_recording() -> void:
	var build_revision := "source checkout"
	if FileAccess.file_exists("res://game/build_revision.txt"):
		build_revision = FileAccess.get_file_as_string("res://game/build_revision.txt").strip_edges()
	recorder.start({
		"schema": 1,
		"build": build_revision,
		"engine": Engine.get_version_info().string,
		"physics_hz": Engine.physics_ticks_per_second,
		"movement": player.settings.values,
		"proportions": JSON.parse_string(proportions),
		"cube_mass": cube.mass,
	})


func update_recording_status(message: String) -> void:
	record_button.disabled = recorder.recording
	stop_record_button.disabled = not recorder.recording
	capture_status.text = message


func record_physics(delta: float, direction: float, raw_stick: float, jump_held: bool, grab_held: bool) -> void:
	var motion := player.motion
	var head: MeshInstance3D = motion.model.head
	recorder.log_event("physics", {
		"dt": delta,
		"input": {
			"move": direction, "stick_x": raw_stick, "jump": jump_held,
			"jump_pressed": jump_pressed, "grab": grab_held, "tilt": vector_values(motion.head_look_target),
		},
		"player": {
			"position": vector_values(player.global_position), "velocity": vector_values(player.velocity),
			"world_velocity": vector_values(player.get_real_velocity()), "drive_speed": player.last_drive_speed,
			"grounded": player.is_on_floor(), "floor_normal": vector_values(player.get_floor_normal()),
			"support_velocity": vector_values(player.get_platform_velocity()),
			"body_yaw": motion.rotation.y, "head_forward": vector_values(head.global_basis.z.normalized()),
			"reach_lowering": motion.reach_lowering, "reach_pitch": motion.reach_pitch,
		},
		"cube": {
			"position": vector_values(cube.global_position), "velocity": vector_values(cube.linear_velocity),
			"rotation_z": cube.rotation.z, "angular_velocity_z": cube.angular_velocity.z,
		},
		"grip": {
			"held": player.held_cube != null, "from_above": player.grip_from_above,
			"shared_support": player.last_shared_support, "force_on_cube": vector_values(player.last_grip_force),
			"anchor_local": vector_values(player.grip_anchor) if player.held_cube != null else null,
			"anchor_world": vector_values(cube.to_global(player.grip_anchor)) if player.held_cube != null else null,
		},
	})


func vector_values(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func add_button(row: HBoxContainer, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 32
	button.pressed.connect(action)
	row.add_child(button)
	return button


func add_adjustment(panel: VBoxContainer, key: StringName) -> void:
	var row := HBoxContainer.new()
	panel.add_child(row)
	var label := Label.new()
	label.custom_minimum_size.x = 152
	label.text = TUNING_LABELS[key]
	var help: String = TUNING_HELP.get(key, "")
	label.tooltip_text = help
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)
	var slider := HSlider.new()
	slider.custom_minimum_size.x = 130
	slider.focus_mode = Control.FOCUS_NONE
	slider.tooltip_text = help
	var limits: Vector3 = Settings.LIMITS[key]
	slider.min_value = snappedf(limits.x, 0.1)
	slider.max_value = limits.y
	slider.step = 0.1
	slider.value = player.settings.values[key]
	row.add_child(slider)
	tuning_sliders[key] = slider
	var field := SpinBox.new()
	field.custom_minimum_size.x = 78
	field.min_value = slider.min_value
	field.max_value = slider.max_value
	field.step = slider.step
	field.value = slider.value
	field.get_line_edit().text_submitted.connect(func(_value: String):
		field.get_line_edit().release_focus()
	)
	row.add_child(field)
	tuning_fields[key] = field
	slider.value_changed.connect(adjust_movement.bind(key))
	field.value_changed.connect(adjust_movement.bind(key))


func adjust_movement(value: float, key: StringName) -> void:
	player.settings.adjust(key, value)
	for setting: StringName in tuning_sliders:
		var current: float = player.settings.values[setting]
		tuning_sliders[setting].set_value_no_signal(current)
		tuning_fields[setting].set_value_no_signal(current)
	tuning_status.text = "Unsaved movement settings"
	recorder.log_event("movement_tuning", {"values": player.settings.values})


func save_movement() -> void:
	tuning_status.text = "Movement settings saved." if player.settings.save_to() else "Could not save movement settings."


func return_to_viewer() -> void:
	var tree := get_tree()
	tree.set_meta("preview_proportions", proportions)
	if tree.change_scene_to_file("res://game/mannequin_view.tscn") != OK:
		tree.remove_meta("preview_proportions")
