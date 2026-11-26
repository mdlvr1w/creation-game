extends Node3D

const Mannequin := preload("res://game/mannequin.gd")
const FIGURINE_TARGET := Vector3(0.0, 1.31, 0.0)
const VIEW_NAMES := ["Front", "Three-quarter", "Side"]
const VIEW_ANGLES := [0.0, 35.0, 90.0]

var camera := Camera3D.new()
var view_buttons: Array[Button] = []


func _ready() -> void:
	add_stage()
	add_child(Mannequin.new())
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.65
	add_child(camera)
	camera.make_current()
	add_controls()
	set_view(1)


func add_stage() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("#283338")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("#e2eaf0")
	world.environment.ambient_light_energy = 0.26
	add_child(world)

	var stage := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(300.0, 300.0)
	stage.mesh = mesh
	var surface := StandardMaterial3D.new()
	surface.albedo_color = Color("#404b51")
	surface.roughness = 1.0
	stage.material_override = surface
	stage.position.y = -0.003
	add_child(stage)

	add_light(Vector3(-48, -32, 0), Color("#fff3e4"), 0.22, true)
	add_light(Vector3(-26, 145, 0), Color("#d9ebff"), 0.12, false)


func add_light(angle: Vector3, color: Color, energy: float, casts_shadow: bool) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = angle
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = casts_shadow
	light.directional_shadow_max_distance = 12.0
	add_child(light)


func add_controls() -> void:
	var interface := CanvasLayer.new()
	add_child(interface)
	var toolbar := HBoxContainer.new()
	toolbar.position = Vector2(20.0, 18.0)
	toolbar.add_theme_constant_override("separation", 8)
	interface.add_child(toolbar)

	for index in VIEW_NAMES.size():
		var button := Button.new()
		button.text = VIEW_NAMES[index]
		button.custom_minimum_size.y = 32
		button.toggle_mode = true
		button.pressed.connect(set_view.bind(index))
		toolbar.add_child(button)
		view_buttons.append(button)

	var editor := Button.new()
	editor.text = "Point editor"
	editor.custom_minimum_size.y = 32
	editor.pressed.connect(func(): get_tree().change_scene_to_file("res://game/workspace.tscn"))
	toolbar.add_child(editor)


func set_view(index: int) -> void:
	var angle := deg_to_rad(VIEW_ANGLES[index])
	var vertical_offset := 0.65 if index == 1 else 0.0
	camera.position = FIGURINE_TARGET + Vector3(sin(angle) * 6.0, vertical_offset, cos(angle) * 6.0)
	camera.look_at(FIGURINE_TARGET)
	for button_index in view_buttons.size():
		view_buttons[button_index].set_pressed_no_signal(button_index == index)
