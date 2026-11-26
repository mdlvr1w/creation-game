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

	check(recorder.start({"test": "first"}, path), "start the first recording")
	await create_timer(0.55).timeout
	check(preview.record_button.disabled and not preview.stop_record_button.disabled, "recording controls reflect active capture")
	recorder.stop()
	var trace := FileAccess.get_file_as_string(folder.path_join("trace.jsonl"))
	check(trace.contains('"first"') and trace.contains('"kind":"physics"') and trace.contains('"kind":"stop"'),
		"the first trace contains start, physics, and stop")

	var legacy_frame := FileAccess.open(folder.path_join("frame_000000.jpg"), FileAccess.WRITE)
	legacy_frame.close()
	check(recorder.start({"test": "replacement"}, path), "start a replacement recording")
	await create_timer(0.24).timeout
	recorder.stop()
	trace = FileAccess.get_file_as_string(folder.path_join("trace.jsonl"))
	check(trace.contains('"replacement"') and not trace.contains('"first"'), "the previous trace is replaced")
	check(DirAccess.get_files_at(folder) == PackedStringArray(["trace.jsonl"]),
		"recording writes only the trace and replaces legacy capture files")
	check(not preview.record_button.disabled and preview.stop_record_button.disabled, "recording controls reset")
	var capture_folder := DirAccess.open(folder)
	for filename in capture_folder.get_files():
		capture_folder.remove(filename)
	DirAccess.remove_absolute(folder)
	if failures == 0:
		print("Recording checks passed.")
	quit(int(failures > 0))


func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)
