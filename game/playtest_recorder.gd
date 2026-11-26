extends Node
## Writes a local, timestamped trace of gameplay input and physics.

signal status_changed(message: String)

const DIRECTORY := "user://playtest-capture"

var recording := false
var started_usec := 0
var trace_failed := false
var trace: FileAccess


func _exit_tree() -> void:
	stop()


func start(context: Dictionary, path: String = DIRECTORY) -> bool:
	if recording:
		return false
	var directory := ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		status_changed.emit("Could not create the capture folder.")
		return false
	if not clear_legacy_capture(directory):
		status_changed.emit("Could not replace the previous capture.")
		return false
	trace = FileAccess.open(directory.path_join("trace.jsonl"), FileAccess.WRITE)
	if trace == null:
		status_changed.emit("Could not open the capture trace.")
		return false

	started_usec = Time.get_ticks_usec()
	trace_failed = false
	recording = true
	log_event("start", context)
	status_changed.emit("● Recording playtest data")
	return true


func clear_legacy_capture(directory: String) -> bool:
	var folder := DirAccess.open(directory)
	if folder == null:
		return false
	for name in folder.get_files():
		var is_old_image := name.begins_with("frame_") and name.ends_with(".jpg") and name.substr(6, name.length() - 10).is_valid_int()
		if is_old_image or name in ["frames.jsonl", "frames.ffconcat", "playtest.mp4", "summary.json"]:
			if folder.remove(name) != OK:
				return false
	return true


func log_event(kind: String, data: Dictionary) -> void:
	if not recording:
		return
	if not trace.store_line(JSON.stringify({
		"t_usec": Time.get_ticks_usec() - started_usec,
		"physics_frame": Engine.get_physics_frames(),
		"kind": kind,
		"data": data,
	})):
		trace_failed = true


func stop() -> void:
	if not recording:
		return
	log_event("stop", {})
	recording = false
	trace.close()
	trace = null
	status_changed.emit("Trace saved with missing data." if trace_failed else "Playtest trace saved locally")
