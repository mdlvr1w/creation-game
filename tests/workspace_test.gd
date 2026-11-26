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
	if failures == 0:
		print("Workspace checks passed.")
	quit(int(failures > 0))


func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)
