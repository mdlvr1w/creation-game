extends SceneTree

const Workspace := preload("res://game/workspace.tscn")

var failures := 0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var workspace = Workspace.instantiate()
	root.add_child(workspace)
	await process_frame

	var pivot := Vector2(300, 300)
	var endpoint := Vector2(400, 300)
	workspace.handle_click(pivot)
	workspace.handle_click(endpoint)
	workspace.select_connect_mode()
	workspace.handle_click(pivot)
	workspace.handle_click(endpoint)
	check(workspace.figure.links.size() == 1, "connect points from the workspace")

	workspace.select_pivot_mode()
	workspace.handle_click(pivot)
	workspace.handle_click(endpoint)
	var length_before: float = workspace.figure.points[0].distance_to(workspace.figure.points[1])
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(300, 400)
	workspace._unhandled_input(motion)
	var length_after: float = workspace.figure.points[0].distance_to(workspace.figure.points[1])
	check(is_equal_approx(length_after, length_before), "swing preserves link length")
	var center: Vector3 = workspace.figure.points[0]
	var actual: Vector3 = workspace.figure.points[1] - center
	var expected_direction: Vector3 = workspace.point_on_plane(motion.position) - center
	check(actual.normalized().is_equal_approx(expected_direction.normalized()), "swing follows the cursor")

	var path := "user://workspace-test-%s.figure.json" % OS.get_process_id()
	var expected: String = workspace.figure.encode()
	workspace.save_figure(path)
	workspace.figure.remove_point(0)
	workspace.open_figure(path)
	check(workspace.figure.encode() == expected, "save and reopen through the workspace")
	workspace.save_figure(path)
	check(workspace.status.text.begins_with("Saved"), "overwrite an existing save")
	DirAccess.remove_absolute(path)
	test_extrusion(workspace)
	if failures == 0:
		print("Workspace checks passed.")
	quit(int(failures > 0))


func test_extrusion(workspace) -> void:
	workspace.figure.points.clear()
	workspace.figure.links.clear()
	workspace.select_place_mode()
	var center := root.get_visible_rect().get_center()
	click_at(center)
	check(workspace.figure.points.size() == 1, "place a point from mouse input")
	if workspace.figure.points.is_empty():
		return

	var arrow: Vector2 = workspace.handles.position_for(1)
	var end := center + Vector2(50, 95)
	mouse_button(arrow, true)
	move_mouse(end)
	check(workspace.preview_visible, "drag shows an extrusion preview")
	check(workspace.figure.points.size() == 1, "preview leaves the figure intact")
	var cancel := InputEventKey.new()
	cancel.keycode = KEY_ESCAPE
	cancel.pressed = true
	root.push_input(cancel, true)
	mouse_button(end, false)
	check(workspace.figure.points.size() == 1, "Escape cancels extrusion")

	mouse_button(arrow, true)
	move_mouse(end)
	mouse_button(end, false)
	check(workspace.figure.points.size() == 2, "release adds one point")
	if workspace.figure.points.size() != 2:
		return
	check(workspace.figure.links.size() == 1, "extrusion connects the new point")
	check(workspace.selected_point == 1, "selection follows the new point")
	check(is_equal_approx(workspace.figure.points[0].x, workspace.figure.points[1].x),
		"directional extrusion keeps horizontal alignment")

	# Use an off-center source with no opposite point.
	click_at(center + Vector2(160, 90))
	var source: Vector3 = workspace.figure.points[2]
	var mirror_handle: Vector2 = workspace.handles.position_for(5)
	move_mouse(mirror_handle)
	check(workspace.handles.hint.visible and workspace.handles.hint.text.contains("mirror"),
		"mirror handle explains its action on hover")
	click_at(mirror_handle)
	check(workspace.mirror_next, "selected point arms mirroring")

	var right_arrow: Vector2 = workspace.handles.position_for(0)
	move_mouse(right_arrow)
	check(workspace.handles.hint.visible and workspace.handles.hint.text.contains("right"),
		"directional handle explains its action on hover")
	var right_end := right_arrow + Vector2(65, 10)
	mouse_button(right_arrow, true)
	move_mouse(right_end)
	check(workspace.preview_visible and not workspace.handles.hint.visible,
		"mirrored arrow stays usable and hides hover help during the drag")
	mouse_button(right_end, false)
	check(workspace.figure.points.size() == 5, "mirrored arrow adds two points from an off-center source")
	if workspace.figure.points.size() != 5:
		return
	var primary: Vector3 = workspace.figure.points[3]
	var mirrored: Vector3 = workspace.figure.points[4]
	check((primary - source).is_equal_approx(source - mirrored), "both links extend from the selected point")
	check(workspace.figure.links.has(Vector2i(2, 3)) and workspace.figure.links.has(Vector2i(2, 4)),
		"both new endpoints are linked to the source")
	check(not workspace.mirror_next and workspace.selected_point == 3,
		"mirroring is consumed and selection follows the primary endpoint")

	var free_handle: Vector2 = workspace.handles.position_for(4)
	move_mouse(free_handle)
	check(workspace.handles.hint.visible and workspace.handles.hint.text.contains("any direction"),
		"free handle explains its action on hover")
	var free_target := free_handle + Vector2(55, -50)
	mouse_button(free_handle, true)
	move_mouse(free_target)
	mouse_button(free_target, false)
	check(workspace.figure.points.size() == 6, "the next pull is free and unmirrored")

	click_at(center)
	click_at(workspace.handles.position_for(5))
	var up_arrow: Vector2 = workspace.handles.position_for(3)
	var up_end := up_arrow + Vector2(0, -75)
	mouse_button(up_arrow, true)
	move_mouse(up_end)
	mouse_button(up_end, false)
	check(workspace.figure.points.size() == 7 and workspace.figure.links.size() == 5,
		"a pull along the mirror axis creates a single link")


func click_at(position: Vector2) -> void:
	mouse_button(position, true)
	mouse_button(position, false)


func mouse_button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)


func move_mouse(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)


func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)
