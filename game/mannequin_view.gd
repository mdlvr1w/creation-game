extends Node3D

const Mannequin := preload("res://game/mannequin.gd")
const LimbControls := preload("res://game/limb_controls.gd")
const PROPORTIONS_FILE := Mannequin.LOCAL_PROPORTIONS
const Stage := preload("res://game/mannequin_stage.gd")
const VIEW_NAMES := ["Front", "Three-quarter", "Side"]
const VIEW_ANGLES := [0.0, 35.0, 90.0]

var figurine := Mannequin.new()
var limb_controls := LimbControls.new()
var stage := Stage.new()
var load_starting_proportions := true
var status := Label.new()
var highlight := StandardMaterial3D.new()
var selected_limb: StringName = &""
var current_view := 1
var pending_pick := Vector2.INF
var camera := Camera3D.new()
var view_buttons: Array[Button] = []


func _ready() -> void:
	add_child(stage)
	add_child(figurine)
	highlight = figurine.material.duplicate()
	highlight.albedo_color = Color("#c2f1e7")
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.65
	add_child(camera)
	camera.make_current()
	add_controls()
	if load_starting_proportions:
		figurine.decode_proportions(FileAccess.get_file_as_string(Mannequin.WORKING_PROPORTIONS))
		load_proportions()
		var tree := get_tree()
		if tree.has_meta("preview_proportions"):
			figurine.decode_proportions(tree.get_meta("preview_proportions"))
			tree.remove_meta("preview_proportions")
	set_view(1)
	get_viewport().size_changed.connect(func():
		frame_figurine()
		position_limb_controls()
	)


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

	var play := Button.new()
	play.text = "Try movement"
	play.custom_minimum_size.y = 32
	play.pressed.connect(func():
		var tree := get_tree()
		tree.set_meta("preview_proportions", figurine.encode_proportions())
		if tree.change_scene_to_file("res://game/movement_preview.tscn") != OK:
			tree.remove_meta("preview_proportions")
	)
	toolbar.add_child(play)

	status.position = Vector2(20, 58)
	status.text = "Click a part of the mannequin to adjust its proportions."
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
	var distance := INF if hit.is_empty() else origin.distance_to(hit.position)
	var part_name: StringName = &"" if hit.is_empty() else hit.collider.get_parent().name
	for part: MeshInstance3D in [figurine.torso, figurine.head]:
		var hit_distance := ellipsoid_hit_distance(part, origin, end)
		if hit_distance < distance:
			distance = hit_distance
			part_name = part.name
	select_limb(part_name)


func ellipsoid_hit_distance(part: MeshInstance3D, origin: Vector3, end: Vector3) -> float:
	# Head and torso are scaled unit-diameter spheres.
	var inverse := part.global_transform.affine_inverse()
	var hit := Geometry3D.segment_intersects_sphere(inverse * origin, inverse * end, Vector3.ZERO, 0.5)
	if hit.is_empty():
		return INF
	var point: Vector3 = part.global_transform * hit[0]
	return origin.distance_to(point)


func paired_name(limb_name: StringName) -> StringName:
	var label := String(limb_name)
	if label.begins_with("Left"):
		return StringName("Right" + label.trim_prefix("Left"))
	return StringName("Left" + label.trim_prefix("Right"))


func set_highlight(part_name: StringName, material: Material) -> void:
	if part_name == &"":
		return
	figurine.get_node(NodePath(String(part_name))).material_override = material
	if figurine.limb_meshes.has(part_name):
		figurine.limb_meshes[paired_name(part_name)].material_override = material


func select_limb(limb_name: StringName) -> void:
	set_highlight(selected_limb, figurine.material)
	selected_limb = limb_name
	if selected_limb == &"":
		limb_controls.hide()
		frame_figurine()
		return
	set_highlight(selected_limb, highlight)
	limb_controls.show_part(selected_limb, part_factors(selected_limb))
	limb_controls.reset_size()
	frame_figurine()
	position_limb_controls()


func part_factors(part_name: StringName) -> Vector4:
	match part_name:
		&"Torso": return figurine.torso_factors
		&"Head": return figurine.head_factors
		&"Neck": return figurine.neck_factors
		_: return figurine.limb_factors[part_name]


func position_limb_controls() -> void:
	if selected_limb == &"":
		return
	limb_controls.reset_size()
	var part := figurine.get_node(NodePath(String(selected_limb))) as MeshInstance3D
	var anchor := camera.unproject_position(part.global_position)
	var screen := get_viewport().get_visible_rect().size
	var size := limb_controls.size
	limb_controls.position = Vector2(
		screen.x - size.x - 24.0,
		clampf(anchor.y - size.y * 0.5, 86.0, maxf(86.0, screen.y - size.y - 16.0))
	)


func set_limb_factor(index: int, factor: float) -> void:
	if selected_limb == &"":
		return
	var factors := part_factors(selected_limb)
	factors[index] = factor
	match selected_limb:
		&"Torso":
			figurine.torso_factors = factors
		&"Head":
			figurine.head_factors = factors
		&"Neck":
			figurine.neck_factors = factors
		_:
			var opposite := paired_name(selected_limb)
			var opposite_factors: Vector4 = figurine.limb_factors[opposite]
			opposite_factors[index] = factor
			figurine.limb_factors[selected_limb] = factors
			figurine.limb_factors[opposite] = opposite_factors
	figurine.update_proportions()
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
	stage.floor_mesh.position.y = figurine.floor_height - 0.003
	var bottom := minf(0.0, figurine.floor_height)
	var top_change := maxf(0.0, figurine.head.position.y + figurine.head.scale.y * 0.5 - 2.64)
	var target := Vector3(0.0, 1.31 + (bottom + top_change) * 0.5, 0.0)
	camera.size = 3.65 + top_change - bottom
	var angle := deg_to_rad(VIEW_ANGLES[current_view])
	var vertical_offset := 0.65 if current_view == 1 else 0.0
	camera.position = target + Vector3(sin(angle) * 6.0, vertical_offset, cos(angle) * 6.0)
	camera.look_at(target)

	# Keep the right edge of the silhouette clear of the panel, even at large proportions.
	if limb_controls.visible:
		var half_width := get_viewport().get_visible_rect().size.x * 0.5
		var available := maxf(half_width - limb_controls.size.x - 48.0, 32.0)
		var bounds := projected_right_edge()
		camera.size *= maxf(1.0, (bounds - half_width) / available)


func projected_right_edge() -> float:
	var right := -INF
	for part: MeshInstance3D in figurine.get_children():
		var bounds := part.get_aabb()
		for index in 8:
			var point := part.global_transform * bounds.get_endpoint(index)
			right = maxf(right, camera.unproject_position(point).x)
	return right
