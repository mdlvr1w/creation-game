extends Node3D
## Places playtest cubes on the same depth plane as the mannequin.

signal cube_placed(at: Vector3)

const Cube := preload("res://game/grabbable_cube.gd")
const VALID_EDGE := Color("#ffd989")
const BLOCKED_EDGE := Color("#ff555b")
const EDGE_WIDTH := 0.014

var camera: Camera3D
var menu := PanelContainer.new()
var ghost := Node3D.new()
var edges := StandardMaterial3D.new()
var halo := StandardMaterial3D.new()
var overlap := PhysicsShapeQueryParameters3D.new()
var pending_position := Vector3.INF
var cursor_position := Vector2.ZERO


func configure(view_camera: Camera3D, interface: CanvasLayer) -> void:
	camera = view_camera
	interface.add_child(menu)
	menu.hide()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#20292e")
	style.border_color = Color("#9c683e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 5.0
	style.content_margin_right = 5.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	menu.add_theme_stylebox_override("panel", style)
	var item := Button.new()
	item.text = "Orange cube"
	item.modulate = Color("#ffd4aa")
	item.custom_minimum_size = Vector2(118, 34)
	item.focus_mode = Control.FOCUS_NONE
	item.pressed.connect(begin_placement)
	menu.add_child(item)

	var box := BoxShape3D.new()
	box.size = Vector3.ONE * Cube.SIZE
	overlap.shape = box

	add_child(ghost)
	ghost.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	ghost.hide()
	var fill := StandardMaterial3D.new()
	fill.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill.albedo_color = Color(Cube.COLOR, 0.5)
	add_box(Vector3.ONE * Cube.SIZE, Vector3.ZERO, fill)
	edges.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for first in [-Cube.HALF_SIZE, Cube.HALF_SIZE]:
		for second in [-Cube.HALF_SIZE, Cube.HALF_SIZE]:
			add_edge(Vector3(Cube.SIZE, EDGE_WIDTH, EDGE_WIDTH), Vector3(0.0, first, second))
			add_edge(Vector3(EDGE_WIDTH, Cube.SIZE, EDGE_WIDTH), Vector3(first, 0.0, second))
			add_edge(Vector3(EDGE_WIDTH, EDGE_WIDTH, Cube.SIZE), Vector3(first, second, 0.0))


func add_edge(size: Vector3, center: Vector3) -> void:
	add_box(size, center, edges)
	add_box(size + Vector3.ONE * EDGE_WIDTH * 2.0, center, halo)


func add_box(size: Vector3, center: Vector3, material: StandardMaterial3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = center
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.add_child(part)


func show_menu(at: Vector2) -> void:
	menu.show()
	menu.reset_size()
	menu.position = at.clamp(Vector2.ZERO, (get_viewport().get_visible_rect().size - menu.size).max(Vector2.ZERO))


func begin_placement() -> void:
	menu.hide()
	ghost.global_position = cursor_world_position(cursor_position)
	set_preview_valid(false)
	ghost.show()


func cancel_placement() -> bool:
	if ghost.visible:
		pending_position = Vector3.INF
		ghost.hide()
		show_menu(cursor_position)
		return true
	if menu.visible:
		menu.hide()
		return true
	return false


func handle_mouse(event: InputEventMouseButton) -> bool:
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if not ghost.visible:
			show_menu(event.position)
		return true
	if event.button_index != MOUSE_BUTTON_LEFT:
		return false
	if ghost.visible:
		pending_position = cursor_world_position(event.position)
		return true
	menu.hide()
	return false


func cursor_world_position(cursor: Vector2) -> Vector3:
	var origin := camera.project_position(cursor, camera.near)
	var direction := camera.project_ray_normal(cursor)
	return Plane(Vector3.BACK, 0.0).intersects_ray(origin, direction)


func follow_cursor() -> void:
	if ghost.visible:
		ghost.global_position = cursor_world_position(cursor_position)


func set_preview_valid(allowed: bool) -> void:
	var color := VALID_EDGE if allowed else BLOCKED_EDGE
	edges.albedo_color = color
	halo.albedo_color = Color(color, 0.24)


func can_place(at: Vector3) -> bool:
	overlap.transform = Transform3D(Basis.IDENTITY, at)
	return get_world_3d().direct_space_state.intersect_shape(overlap, 1).is_empty()


func check_placement() -> void:
	if not ghost.visible:
		return
	if pending_position.is_finite():
		var at := pending_position
		pending_position = Vector3.INF
		if can_place(at):
			cube_placed.emit(at)
	set_preview_valid(can_place(ghost.global_position))
