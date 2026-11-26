extends SceneTree

const Preview := preload("res://game/movement_preview.tscn")

var failures := 0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var preview = Preview.instantiate()
	root.add_child(preview)
	var recorder = preview.recorder
	var path := "user://capture-test-%s" % OS.get_process_id()
	var folder := ProjectSettings.globalize_path(path)
	var has_display := DisplayServer.get_name() != "headless"

	check(recorder.start({"test": "first"}, path), "start the first recording")
	await create_timer(0.55).timeout
	check(preview.record_button.disabled and not preview.stop_record_button.disabled, "recording controls reflect active capture")
	recorder.stop()
	await wait_for_writer(recorder)
	var trace := FileAccess.get_file_as_string(folder.path_join("trace.jsonl"))
	check(trace.contains('"first"') and trace.contains('"kind":"physics"') and trace.contains('"kind":"stop"'),
		"the first trace contains start, physics, and stop")
	if has_display:
		check_frame_index(folder)

	check(recorder.start({"test": "replacement"}, path), "start a replacement recording")
	await create_timer(0.24).timeout
	recorder.stop()
	await wait_for_writer(recorder)
	trace = FileAccess.get_file_as_string(folder.path_join("trace.jsonl"))
	check(trace.contains('"replacement"') and not trace.contains('"first"'), "the previous trace is replaced")
	if has_display:
		check_frame_index(folder)
	check(not preview.record_button.disabled and preview.stop_record_button.disabled, "recording controls reset")
	var capture_folder := DirAccess.open(folder)
	for filename in capture_folder.get_files():
		capture_folder.remove(filename)
	DirAccess.remove_absolute(folder)
	if failures == 0:
		print("Recording checks passed.")
	quit(int(failures > 0))


func wait_for_writer(recorder) -> void:
	while recorder.writer != null:
		await process_frame


func check_frame_index(folder: String) -> void:
	var rows := FileAccess.get_file_as_string(folder.path_join("frames.jsonl")).split("\n", false)
	check(rows.size() >= 2, "the graphical preview writes gameplay frames")
	var previous := -1
	for row in rows:
		var frame: Dictionary = JSON.parse_string(row)
		check(frame.t_usec > previous and frame.has("physics_frame"), "frames share the trace clock")
		check(FileAccess.file_exists(folder.path_join(frame.file)), "indexed frame exists")
		previous = int(frame.t_usec)
	var files := DirAccess.get_files_at(folder)
	var image_count := 0
	for filename in files:
		if filename.begins_with("frame_") and filename.ends_with(".jpg"):
			image_count += 1
	check(image_count == rows.size(), "older frames do not survive a new capture")


func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)
