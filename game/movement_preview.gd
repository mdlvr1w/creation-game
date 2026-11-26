extends Node3D

const Mannequin := preload("res://game/mannequin.gd")
const Controller := preload("res://game/mannequin_controller.gd")
const Stage := preload("res://game/mannequin_stage.gd")

var player := Controller.new()
var camera := Camera3D.new()
var proportions := ""
var jump_was_down := false


func _ready() -> void:
	add_child(Stage.new())
	add_platform(Vector3(0, -0.5, 0), Vector3(180, 1, 16), Color("#404b51"), false)
	add_platform(Vector3(6, 0.32, 0), Vector3(2.1, 0.64, 2.6), Color("#587e79"), true)
	for index in range(-19, 20):
		add_floor_marker(index * 2.5)

	add_child(player)
	player.reset()
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


func _physics_process(delta: float) -> void:
	var left := Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)
	var right := Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
	var jump := Input.is_physical_key_pressed(KEY_SPACE)
	player.step(delta, float(right) - float(left), jump and not jump_was_down)
	jump_was_down = jump
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
	var hint := Label.new()
	hint.text = "A / D or ← / → to move   ·   Space to jump"
	panel.add_child(hint)
	add_adjustment(panel, "Move speed", 2.5, 9.0, player.speed,
		func(value: float): player.speed = value)
	add_adjustment(panel, "Jump strength", 4.0, 11.0, player.jump_speed,
		func(value: float): player.jump_speed = value)


func add_button(row: HBoxContainer, caption: String, action: Callable) -> void:
	var button := Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 32
	button.pressed.connect(action)
	row.add_child(button)


func add_adjustment(panel: VBoxContainer, caption: String, minimum: float, maximum: float,
		initial: float, action: Callable) -> void:
	var row := HBoxContainer.new()
	panel.add_child(row)
	var label := Label.new()
	label.custom_minimum_size.x = 108
	label.text = caption
	row.add_child(label)
	var slider := HSlider.new()
	slider.custom_minimum_size.x = 105
	slider.focus_mode = Control.FOCUS_NONE
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 0.1
	slider.value = initial
	row.add_child(slider)
	var value_label := Label.new()
	value_label.text = "%.1f" % initial
	row.add_child(value_label)
	slider.value_changed.connect(func(value: float):
		value_label.text = "%.1f" % value
		action.call(value)
	)


func return_to_viewer() -> void:
	var tree := get_tree()
	tree.set_meta("preview_proportions", proportions)
	if tree.change_scene_to_file("res://game/mannequin_view.tscn") != OK:
		tree.remove_meta("preview_proportions")
