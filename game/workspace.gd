extends Node3D

const Figure := preload("res://game/figure.gd")
const INK := Color("#222827")
const ACCENT := Color("#00765e")
const BACKGROUND := Color("#faf9f5")
const FLOOR_Y := -2.8
const CAMERA_SIZE := 8.0

var figure := Figure.new()
var camera := Camera3D.new()
var drawing := MeshInstance3D.new()
var status := Label.new()
var connect_button: Button
var save_dialog: FileDialog
var open_dialog: FileDialog
var current_file := ""
var saved_figure := ""
var selected_point := -1
var drag_point := -1
enum Tool { PLACE, CONNECT, PIVOT }

var tool := Tool.PLACE
var pivot_point := -1
var pivot_radius := 0.0


func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = BACKGROUND
	add_child(environment)

	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CAMERA_SIZE
	camera.position = Vector3(0.0, 0.0, 10.0)
	add_child(camera)
	camera.make_current()

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	drawing.material_override = material
	add_child(drawing)

	build_interface()
	saved_figure = figure.encode()
	redraw()


func build_interface() -> void:
	var overlay := CanvasLayer.new()
	add_child(overlay)
	var toolbar := HBoxContainer.new()
	toolbar.position = Vector2(20, 18)
	toolbar.add_theme_constant_override("separation", 8)
	overlay.add_child(toolbar)

	add_button(toolbar, "Place & move", select_place_mode)
	connect_button = add_button(toolbar, "Connect", select_connect_mode)
	add_button(toolbar, "Swing link", select_pivot_mode)
	add_button(toolbar, "Delete point", remove_selection)
	add_button(toolbar, "Open…", request_open)
	add_button(toolbar, "Save", request_save)
	add_button(toolbar, "Save as…", show_save_dialog)

	status.position = Vector2(20, 58)
	status.add_theme_color_override("font_color", INK)
	overlay.add_child(status)
	save_dialog = make_file_dialog(overlay, FileDialog.FILE_MODE_SAVE_FILE)
	open_dialog = make_file_dialog(overlay, FileDialog.FILE_MODE_OPEN_FILE)
	save_dialog.file_selected.connect(save_figure)
	open_dialog.file_selected.connect(open_figure)
	select_place_mode()


func add_button(parent: Control, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(0, 32)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func make_file_dialog(parent: Node, mode: FileDialog.FileMode) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode
	dialog.filters = PackedStringArray(["*.figure.json ; Figure"])
	dialog.use_native_dialog = false
	parent.add_child(dialog)
	return dialog


func select_place_mode() -> void:
	tool = Tool.PLACE
	pivot_point = -1
	set_status("Click empty space to add a point. Drag a point to move it.")
	update_tools()


func select_connect_mode() -> void:
	tool = Tool.CONNECT
	pivot_point = -1
	selected_point = -1
	set_status("Click two points to connect them. Right-click to cancel a selection.")
	update_tools()


func select_pivot_mode() -> void:
	tool = Tool.PIVOT
	selected_point = -1
	pivot_point = -1
	set_status("Click a pivot point, then drag a connected point around it.")
	update_tools()


func update_tools() -> void:
	drag_point = -1
	connect_button.disabled = tool == Tool.CONNECT
	redraw()


func set_status(message: String) -> void:
	status.text = message


func _input(event: InputEvent) -> void:
	# Release even when the pointer moves over the toolbar during a drag.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		drag_point = -1


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and drag_point >= 0:
		var destination := point_on_plane(event.position)
		if tool == Tool.PIVOT:
			var pivot := figure.points[pivot_point]
			var offset := Vector2(destination.x - pivot.x, destination.y - pivot.y)
			if offset.is_zero_approx():
				return
			offset = offset.normalized() * pivot_radius
			destination = pivot + Vector3(offset.x, offset.y, 0.0)
		destination.z = figure.points[drag_point].z
		figure.points[drag_point] = destination
		redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			handle_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			selected_point = -1
			pivot_point = -1
			redraw()
	elif event.is_action_pressed("ui_cancel"):
		select_place_mode()


func handle_click(screen_position: Vector2) -> void:
	var hit := pick_point(screen_position)
	if tool == Tool.CONNECT:
		if hit < 0:
			return
		if selected_point < 0:
			selected_point = hit
		elif figure.connect_points(selected_point, hit):
			selected_point = -1
			set_status("Connected. Click two points to make another link.")
		else:
			selected_point = hit
			set_status("Choose a different point to make a new link.")
	elif tool == Tool.PIVOT:
		if hit < 0:
			return
		if pivot_point < 0:
			pivot_point = hit
			selected_point = hit
		else:
			var link := Vector2i(mini(pivot_point, hit), maxi(pivot_point, hit))
			if not figure.links.has(link):
				set_status("Choose a point connected to the pivot, or right-click to choose another pivot.")
				return
			var offset := figure.points[hit] - figure.points[pivot_point]
			pivot_radius = Vector2(offset.x, offset.y).length()
			drag_point = hit
			set_status("Drag to swing the link. Right-click to choose another pivot.")
	else:
		if hit < 0:
			hit = figure.points.size()
			figure.points.append(point_on_plane(screen_position))
		selected_point = hit
		drag_point = hit
	redraw()


func remove_selection() -> void:
	if selected_point < 0:
		set_status("Select a point before deleting it.")
		return
	figure.remove_point(selected_point)
	pivot_point = -1
	selected_point = -1
	drag_point = -1
	redraw()


func point_on_plane(screen_position: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen_position)
	return Vector3(origin.x, origin.y, 0.0)


func pick_point(screen_position: Vector2) -> int:
	var closest := -1
	var distance := 13.0
	for index in figure.points.size():
		var candidate := camera.unproject_position(figure.points[index]).distance_to(screen_position)
		if candidate < distance:
			closest = index
			distance = candidate
	return closest


func redraw() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	draw_line(mesh, Vector3(-100, FLOOR_Y, 0), Vector3(100, FLOOR_Y, 0), 0.023, INK)
	for link in figure.links:
		draw_line(mesh, figure.points[link.x], figure.points[link.y], 0.032, INK)
	for index in figure.points.size():
		var center := figure.points[index] + Vector3(0, 0, 0.01)
		var color := ACCENT if index == selected_point else INK
		for segment in 16:
			var start := Vector2.from_angle(TAU * segment / 16.0) * 0.09
			var finish := Vector2.from_angle(TAU * (segment + 1) / 16.0) * 0.09
			draw_triangle(mesh, center, center + Vector3(start.x, start.y, 0), center + Vector3(finish.x, finish.y, 0), color)
	mesh.surface_end()
	drawing.mesh = mesh


func draw_line(mesh: ImmediateMesh, start: Vector3, finish: Vector3, width: float, color: Color) -> void:
	var direction := Vector2(finish.x - start.x, finish.y - start.y)
	if direction.is_zero_approx():
		return
	var offset := direction.orthogonal().normalized() * width * 0.5
	var side := Vector3(offset.x, offset.y, 0)
	draw_triangle(mesh, start + side, finish + side, finish - side, color)
	draw_triangle(mesh, start + side, finish - side, start - side, color)


func draw_triangle(mesh: ImmediateMesh, first: Vector3, second: Vector3, third: Vector3, color: Color) -> void:
	for vertex in [first, second, third]:
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(vertex)


func request_open() -> void:
	if figure.encode() == saved_figure:
		open_dialog.popup_centered_ratio(0.7)
		return
	var confirmation := ConfirmationDialog.new()
	confirmation.dialog_text = "Open another figure? Unsaved changes will be lost if it loads successfully."
	confirmation.confirmed.connect(func(): open_dialog.popup_centered_ratio(0.7))
	confirmation.visibility_changed.connect(func():
		if not confirmation.visible:
			confirmation.queue_free()
	)
	get_node("CanvasLayer").add_child(confirmation)
	confirmation.popup_centered()


func request_save() -> void:
	if current_file.is_empty():
		show_save_dialog()
	else:
		save_figure(current_file)


func show_save_dialog() -> void:
	save_dialog.current_file = "figure.figure.json"
	save_dialog.popup_centered_ratio(0.7)


func save_figure(path: String) -> void:
	var encoded := figure.encode()
	var temporary_path := "%s.%s.%s.tmp" % [path, OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		set_status("Could not save the figure.")
		return
	var written := file.store_string(encoded)
	file.close()
	if not written or DirAccess.rename_absolute(temporary_path, path) != OK:
		DirAccess.remove_absolute(temporary_path)
		set_status("Could not finish saving the figure.")
		return
	current_file = path
	saved_figure = encoded
	set_status("Saved " + path.get_file())


func open_figure(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or not figure.decode(file.get_as_text()):
		set_status("Could not open that figure. Your current figure is still here.")
		return
	current_file = path
	saved_figure = figure.encode()
	pivot_point = -1
	selected_point = -1
	drag_point = -1
	redraw()
	set_status("Opened " + path.get_file())
