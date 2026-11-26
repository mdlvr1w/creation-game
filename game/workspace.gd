extends Node3D

const Figure := preload("res://game/figure.gd")
const ExtrusionHandles := preload("res://game/extrusion_handles.gd")
const MIRROR_TOLERANCE := 0.001
const CENTER_SNAP := 0.065
const MIN_DRAG := 6.0
const PREVIEW := Color("#469486")
const INK := Color("#222827")
const ACCENT := Color("#00765e")
const BACKGROUND := Color("#faf9f5")
const FLOOR_Y := -2.8
const CAMERA_SIZE := 8.0

var figure := Figure.new()
var camera := Camera3D.new()
var drawing := MeshInstance3D.new()
var handles := ExtrusionHandles.new()
var toolbar := HBoxContainer.new()
var mirror_button := CheckButton.new()
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
var hovered_point := -1
var extrusion_handle := -1
var extrusion_start := Vector2.ZERO
var extrusion_target := Vector3.ZERO
var mirror_source := -1
var preview_visible := false


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
	overlay.add_child(handles)
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
	mirror_button.text = "Mirror extrusion"
	mirror_button.tooltip_text = "Reflect new links across the vertical centerline."
	mirror_button.toggled.connect(func(_enabled: bool): redraw())
	toolbar.add_child(mirror_button)
	get_viewport().size_changed.connect(redraw)

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
	set_status("Click to place. Drag a point to move it, an arrow to extend straight, or the ring to extend freely.")
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
	clear_extrusion()
	hovered_point = -1
	drag_point = -1
	connect_button.disabled = tool == Tool.CONNECT
	redraw()


func set_status(message: String) -> void:
	status.text = message


func _input(event: InputEvent) -> void:
	if extrusion_handle >= 0:
		if event is InputEventMouseMotion:
			update_extrusion(event.position)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if not event.pressed:
				finish_extrusion(event.position)
		elif event.is_action_pressed("ui_cancel") or (
			event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed
		):
			cancel_extrusion()
		else:
			return
		get_viewport().set_input_as_handled()
		return

	# Release even when the pointer moves over the toolbar during a drag.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		drag_point = -1
		redraw()


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
	elif event is InputEventMouseMotion and tool == Tool.PLACE:
		var point := pick_point(event.position)
		var handle := -1 if point >= 0 else handles.hit_test(event.position)
		if point != hovered_point or handle != handles.hovered:
			hovered_point = point
			handles.hovered = handle
			redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			handle_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			selected_point = -1
			pivot_point = -1
			handles.hovered = -1
			redraw()
	elif event.is_action_pressed("ui_cancel"):
		select_place_mode()


func handle_click(screen_position: Vector2) -> void:
	var hit := pick_point(screen_position)
	if tool == Tool.PLACE and hit < 0:
		var handle := handles.hit_test(screen_position)
		if handle >= 0:
			begin_extrusion(handle, screen_position)
			return
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
			var position := point_on_plane(screen_position)
			if mirror_button.button_pressed and absf(position.x) <= CENTER_SNAP:
				position.x = 0.0
			figure.points.append(position)
		selected_point = hit
		drag_point = hit
	redraw()


func begin_extrusion(handle: int, cursor: Vector2) -> void:
	var source := figure.points[selected_point]
	if mirror_button.button_pressed:
		mirror_source = find_point(reflect_point(source))
		if mirror_source < 0:
			set_status("Mirror extrusion needs a source on the centerline or a matching point across it.")
			return

	extrusion_handle = handle
	extrusion_start = cursor
	drag_point = -1
	set_status("Drag to preview the new link. Escape cancels.")
	redraw()


func update_extrusion(cursor: Vector2) -> void:
	var source := figure.points[selected_point]
	var on_plane := point_on_plane(cursor)
	var displacement := Vector2(on_plane.x - source.x, on_plane.y - source.y)
	if extrusion_handle != ExtrusionHandles.FREE_HANDLE:
		var direction: Vector2 = ExtrusionHandles.DIRECTIONS[extrusion_handle]
		direction.y = -direction.y
		displacement = direction * maxf(0.0, displacement.dot(direction))
	extrusion_target = source + Vector3(displacement.x, displacement.y, 0.0)
	if mirror_source >= 0 and absf(extrusion_target.x) <= CENTER_SNAP:
		extrusion_target.x = 0.0
	preview_visible = (cursor.distance_to(extrusion_start) >= MIN_DRAG
		and source.distance_to(extrusion_target) > CENTER_SNAP
		and get_viewport().get_visible_rect().has_point(cursor)
		and not toolbar.get_global_rect().has_point(cursor))
	if preview_visible:
		var description := "Mirrored link" if mirror_source >= 0 else "Link"
		set_status("%s length %.2f   ·   Escape cancels" % [description, source.distance_to(extrusion_target)])
	redraw()


func finish_extrusion(cursor: Vector2) -> void:
	update_extrusion(cursor)
	if not preview_visible:
		cancel_extrusion()
		return
	var endpoint := append_link(selected_point, extrusion_target)
	if mirror_source >= 0:
		var reflected := reflect_point(extrusion_target)
		if not reflected.is_equal_approx(figure.points[mirror_source]):
			append_link(mirror_source, reflected)
	selected_point = endpoint
	hovered_point = -1
	clear_extrusion()
	set_status("Link added. Pull another handle to continue.")
	redraw()


func append_link(source: int, position: Vector3) -> int:
	var endpoint := find_point(position)
	if endpoint < 0:
		endpoint = figure.points.size()
		figure.points.append(position)
	figure.connect_points(source, endpoint)
	return endpoint


func reflect_point(point: Vector3) -> Vector3:
	return Vector3(-point.x, point.y, point.z)


func find_point(position: Vector3) -> int:
	for index in figure.points.size():
		if position.distance_to(figure.points[index]) <= MIRROR_TOLERANCE:
			return index
	return -1


func clear_extrusion() -> void:
	extrusion_handle = -1
	mirror_source = -1
	preview_visible = false
	handles.hovered = -1


func cancel_extrusion() -> void:
	clear_extrusion()
	set_status("Extrusion canceled. Pull a handle to try again.")
	redraw()


func remove_selection() -> void:
	if selected_point < 0:
		set_status("Select a point before deleting it.")
		return
	clear_extrusion()
	hovered_point = -1
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
	if mirror_button.button_pressed:
		draw_line(mesh, Vector3(0, -20, 0), Vector3(0, 20, 0), 0.014, Color("#a5c2b8"))
	if preview_visible:
		draw_preview(mesh, figure.points[selected_point], extrusion_target)
		if mirror_source >= 0:
			draw_preview(mesh, figure.points[mirror_source], reflect_point(extrusion_target))
	for link in figure.links:
		draw_line(mesh, figure.points[link.x], figure.points[link.y], 0.032, INK)
	for index in figure.points.size():
		var color := ACCENT if index == selected_point or index == hovered_point else INK
		draw_point(mesh, figure.points[index], color)
	mesh.surface_end()
	drawing.mesh = mesh
	update_handles()


func update_handles() -> void:
	handles.visible_handles.clear()
	if tool == Tool.PLACE and selected_point >= 0 and extrusion_handle < 0:
		handles.center = camera.unproject_position(figure.points[selected_point])
		for index in ExtrusionHandles.DIRECTIONS.size():
			# A nearby point always remains available for selection.
			if pick_point(handles.position_for(index)) < 0:
				handles.visible_handles.append(index)
	handles.queue_redraw()


func draw_preview(mesh: ImmediateMesh, source: Vector3, target: Vector3) -> void:
	draw_line(mesh, source, target, 0.032, PREVIEW)
	draw_point(mesh, target, PREVIEW)


func draw_point(mesh: ImmediateMesh, point: Vector3, color: Color) -> void:
	var center := point + Vector3(0, 0, 0.01)
	for segment in 16:
		var start := Vector2.from_angle(TAU * segment / 16.0) * 0.09
		var finish := Vector2.from_angle(TAU * (segment + 1) / 16.0) * 0.09
		draw_triangle(mesh, center, center + Vector3(start.x, start.y, 0), center + Vector3(finish.x, finish.y, 0), color)


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
	clear_extrusion()
	hovered_point = -1
	current_file = path
	saved_figure = figure.encode()
	pivot_point = -1
	selected_point = -1
	drag_point = -1
	redraw()
	set_status("Opened " + path.get_file())
