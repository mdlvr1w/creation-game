extends Node3D

const Mannequin := preload("res://game/mannequin.gd")
const LimbControls := preload("res://game/limb_controls.gd")
const PROPORTIONS_FILE := "user://mannequin-proportions.json"
const VIEW_NAMES := ["Front", "Three-quarter", "Side"]
const VIEW_ANGLES := [0.0, 35.0, 90.0]

var figurine := Mannequin.new()
var limb_controls := LimbControls.new()
var stage := MeshInstance3D.new()
var status := Label.new()
var highlight := StandardMaterial3D.new()
var selected_limb: StringName = &""
var current_view := 1
var pending_pick := Vector2.INF
var camera := Camera3D.new()
var view_buttons: Array[Button] = []


func _ready() -> void:
	add_stage()
	add_child(figurine)
	highlight = figurine.material.duplicate()
	highlight.albedo_color = Color("#c2f1e7")
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.65
	add_child(camera)
	camera.make_current()
	add_controls()
	load_proportions()
	set_view(1)
	get_viewport().size_changed.connect(position_limb_controls)


func add_stage() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("#283338")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("#e2eaf0")
	world.environment.ambient_light_energy = 0.26
	add_child(world)

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

	var save := Button.new()
	save.text = "Save proportions"
	save.custom_minimum_size.y = 32
	save.pressed.connect(func(): save_proportions())
	toolbar.add_child(save)

	status.position = Vector2(20, 58)
	status.text = "Click the torso or a limb segment to adjust proportions."
	status.add_theme_color_override("font_shadow_color", Color("#20292e"))
	status.add_theme_constant_override("shadow_offset_y", 1)
	interface.add_child(status)
	interface.add_child(limb_controls)
	limb_controls.factor_changed.connect(set_limb_factor)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pending_pick = event.position


func _physics_process(_delta: float) -> void:
	if not pending_pick.is_finite():
		return
	var origin := camera.project_ray_origin(pending_pick)
	var end := origin + camera.project_ray_normal(pending_pick) * 30.0
	pending_pick = Vector2.INF
	var query := PhysicsRayQueryParameters3D.create(origin, end, 1)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var torso_distance := ray_torso_distance(origin, end)
	if torso_distance < INF and (hit.is_empty() or torso_distance < origin.distance_to(hit.position)):
		select_limb(&"Torso")
	elif hit.is_empty():
		select_limb(&"")
	else:
		select_limb(hit.collider.get_parent().name)


func ray_torso_distance(origin: Vector3, end: Vector3) -> float:
	# In torso-local space the mesh is a sphere with radius 0.5.
	var inverse: Transform3D = figurine.torso.global_transform.affine_inverse()
	var start: Vector3 = inverse * origin
	var direction: Vector3 = inverse * end - start
	var nearest := -start.dot(direction) / direction.length_squared()
	var midpoint := start + nearest * direction
	var gap := 0.25 - midpoint.length_squared()
	if gap < 0.0:
		return INF
	var fraction := nearest - sqrt(gap / direction.length_squared())
	return origin.distance_to(end) * fraction if fraction >= 0.0 and fraction <= 1.0 else INF


func paired_name(limb_name: StringName) -> StringName:
	var label := String(limb_name)
	if label.begins_with("Left"):
		return StringName("Right" + label.trim_prefix("Left"))
	return StringName("Left" + label.trim_prefix("Right"))


func set_highlight(part_name: StringName, material: Material) -> void:
	if part_name == &"Torso":
		figurine.torso.material_override = material
	elif part_name != &"":
		figurine.limb_meshes[part_name].material_override = material
		figurine.limb_meshes[paired_name(part_name)].material_override = material


func select_limb(limb_name: StringName) -> void:
	set_highlight(selected_limb, figurine.material)
	selected_limb = limb_name
	if selected_limb == &"":
		limb_controls.hide()
		return
	set_highlight(selected_limb, highlight)
	var factors: Vector4 = figurine.torso_factors if selected_limb == &"Torso" else figurine.limb_factors[selected_limb]
	limb_controls.show_part(selected_limb, factors)
	position_limb_controls()


func position_limb_controls() -> void:
	if selected_limb == &"":
		return
	limb_controls.reset_size()
	var part: MeshInstance3D = figurine.torso if selected_limb == &"Torso" else figurine.limb_meshes[selected_limb]
	var anchor := camera.unproject_position(part.global_position)
	var screen := get_viewport().get_visible_rect().size
	var size := limb_controls.size
	var x := anchor.x + 58.0
	if x + size.x > screen.x - 16.0:
		x = anchor.x - size.x - 58.0
	limb_controls.position = Vector2(
		clampf(x, 16.0, maxf(16.0, screen.x - size.x - 16.0)),
		clampf(anchor.y - size.y * 0.5, 86.0, maxf(86.0, screen.y - size.y - 16.0))
	)


func set_limb_factor(index: int, factor: float) -> void:
	if selected_limb == &"":
		return
	if selected_limb == &"Torso":
		figurine.torso_factors[index] = factor
	else:
		var opposite := paired_name(selected_limb)
		var factors: Vector4 = figurine.limb_factors[selected_limb]
		var opposite_factors: Vector4 = figurine.limb_factors[opposite]
		factors[index] = factor
		opposite_factors[index] = factor
		figurine.limb_factors[selected_limb] = factors
		figurine.limb_factors[opposite] = opposite_factors
	figurine.update_limbs()
	frame_figurine()
	status.text = "Unsaved proportions"


func save_proportions(path: String = PROPORTIONS_FILE) -> bool:
	var temp := "%s.%s.%s.tmp" % [path, OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		status.text = "Could not save proportions."
		return false
	var written := file.store_string(figurine.encode_proportions())
	file.close()
	if not written or DirAccess.rename_absolute(temp, path) != OK:
		DirAccess.remove_absolute(temp)
		status.text = "Could not save proportions."
		return false
	status.text = "Proportions saved. They will load the next time you open the viewer."
	return true


func load_proportions(path: String = PROPORTIONS_FILE) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or not figurine.decode_proportions(file.get_as_text()):
		status.text = "Could not read saved proportions."
		return false
	return true


func set_view(index: int) -> void:
	current_view = index
	frame_figurine()
	for button_index in view_buttons.size():
		view_buttons[button_index].set_pressed_no_signal(button_index == index)
	position_limb_controls()


func frame_figurine() -> void:
	stage.position.y = figurine.floor_height - 0.003
	var bottom := minf(0.0, figurine.floor_height)
	var top_change := maxf(0.0, figurine.head.position.y - 2.11)
	var target := Vector3(0.0, 1.31 + (bottom + top_change) * 0.5, 0.0)
	camera.size = 3.65 + top_change - bottom
	var angle := deg_to_rad(VIEW_ANGLES[current_view])
	var vertical_offset := 0.65 if current_view == 1 else 0.0
	camera.position = target + Vector3(sin(angle) * 6.0, vertical_offset, cos(angle) * 6.0)
	camera.look_at(target)
