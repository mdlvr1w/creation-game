extends Node
## Records the rendered viewport and game telemetry on the same monotonic clock.

signal status_changed(message: String)

const DIRECTORY := "user://playtest-capture"
const FRAME_INTERVAL_USEC := 66667
const QUEUE_LIMIT := 4

var recording := false
var directory := ""
var started_usec := 0
var next_frame_usec := 0
var frame_index := 0
var dropped := 0
var trace_failed := false
var trace: FileAccess
var writer: Thread
var queue: Array[Dictionary] = []
var queue_lock := Mutex.new()
var work_ready := Semaphore.new()
var stopping := false


func _ready() -> void:
	RenderingServer.frame_post_draw.connect(capture_viewport)


func _process(_delta: float) -> void:
	if writer != null and not writer.is_alive():
		finish_writer()


func _exit_tree() -> void:
	if recording:
		stop()
	if writer != null:
		finish_writer()


func start(context: Dictionary, path: String = DIRECTORY) -> bool:
	if recording or writer != null:
		return false
	directory = ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		status_changed.emit("Could not create the capture folder.")
		return false
	if not clear_previous():
		status_changed.emit("Could not replace the previous capture.")
		return false
	trace = FileAccess.open(directory.path_join("trace.jsonl"), FileAccess.WRITE)
	if trace == null:
		status_changed.emit("Could not open the capture trace.")
		return false

	started_usec = Time.get_ticks_usec()
	next_frame_usec = 0
	frame_index = 0
	dropped = 0
	trace_failed = false
	stopping = false
	work_ready = Semaphore.new()
	writer = Thread.new()
	if writer.start(write_frames.bind(directory)) != OK:
		writer = null
		trace = null
		status_changed.emit("Could not start the capture writer.")
		return false

	recording = true
	log_event("start", context)
	status_changed.emit("● Recording playtest")
	return true


func clear_previous() -> bool:
	var folder := DirAccess.open(directory)
	if folder == null:
		return false
	for name in folder.get_files():
		if name in ["trace.jsonl", "frames.jsonl", "frames.ffconcat", "playtest.mp4", "summary.json"] or (
			name.begins_with("frame_") and name.ends_with(".jpg")
		):
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


func capture_viewport() -> void:
	if not recording or DisplayServer.get_name() == "headless":
		return
	var timestamp := Time.get_ticks_usec() - started_usec
	if timestamp < next_frame_usec:
		return
	next_frame_usec += (floori(float(timestamp - next_frame_usec) / FRAME_INTERVAL_USEC) + 1) * FRAME_INTERVAL_USEC
	queue_lock.lock()
	var has_room := queue.size() < QUEUE_LIMIT
	queue_lock.unlock()
	if not has_room:
		dropped += 1
		return
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		dropped += 1
		return
	queue_lock.lock()
	queue.append({
		"image": image, "t_usec": timestamp, "index": frame_index,
		"physics_frame": Engine.get_physics_frames(),
	})
	queue_lock.unlock()
	frame_index += 1
	work_ready.post()


func stop() -> void:
	if not recording:
		return
	log_event("stop", {"queued_frames": frame_index, "dropped_frames": dropped})
	recording = false
	trace.close()
	trace = null
	queue_lock.lock()
	stopping = true
	queue_lock.unlock()
	work_ready.post()
	status_changed.emit("Saving playtest capture…")


func finish_writer() -> void:
	var result: Dictionary = writer.wait_to_finish()
	writer = null
	var frames: int = result.frames
	var summary := FileAccess.open(directory.path_join("summary.json"), FileAccess.WRITE)
	if summary != null:
		summary.store_string(JSON.stringify({
			"frames": frames, "dropped_frames": dropped + frame_index - frames,
			"video": result.video, "write_error": result.write_error or trace_failed,
		}, "\t"))
	if result.write_error or trace_failed:
		status_changed.emit("Capture saved with missing data.")
	elif result.video:
		status_changed.emit("Playtest captured · video and trace saved locally")
	elif frames > 0:
		status_changed.emit("Playtest captured · frames and trace saved locally")
	else:
		status_changed.emit("Playtest trace saved · no gameplay frames captured")


func write_frames(path: String) -> Dictionary:
	var index := FileAccess.open(path.path_join("frames.jsonl"), FileAccess.WRITE)
	var captured: Array[Dictionary] = []
	var write_error := index == null
	while true:
		work_ready.wait()
		queue_lock.lock()
		var frame: Dictionary = queue.pop_front() if not queue.is_empty() else {}
		var done := frame.is_empty() and stopping
		queue_lock.unlock()
		if done:
			break
		if frame.is_empty() or index == null:
			continue

		var image: Image = frame.image
		if image.get_width() > 960:
			var height := roundi(float(image.get_height()) * 960.0 / image.get_width())
			image.resize(960, height, Image.INTERPOLATE_BILINEAR)
		var name := "frame_%06d.jpg" % frame.index
		if image.save_jpg(path.path_join(name), 0.82) != OK:
			write_error = true
			continue
		frame.erase("image")
		frame["file"] = name
		index.store_line(JSON.stringify(frame))
		captured.append(frame)
	if index != null:
		index.close()
	var has_video := encode_video(path, captured)
	return {"frames": captured.size(), "video": has_video, "write_error": write_error}


func encode_video(path: String, captured: Array[Dictionary]) -> bool:
	var ffmpeg := find_ffmpeg()
	if captured.size() < 2 or ffmpeg.is_empty():
		return false
	var manifest_path := path.path_join("frames.ffconcat")
	var manifest := FileAccess.open(manifest_path, FileAccess.WRITE)
	if manifest == null:
		return false
	manifest.store_line("ffconcat version 1.0")
	for index in captured.size():
		var frame := captured[index]
		var length := FRAME_INTERVAL_USEC
		if index + 1 < captured.size():
			length = int(captured[index + 1].t_usec) - int(frame.t_usec)
		manifest.store_line("file " + frame.file)
		manifest.store_line("duration %.6f" % (float(length) / 1000000.0))
	manifest.store_line("file " + captured.back().file)
	manifest.close()

	var output := path.path_join("playtest.mp4")
	var messages: Array = []
	var status := OS.execute(ffmpeg, [
		"-nostdin", "-v", "error", "-y", "-f", "concat", "-safe", "1", "-i", manifest_path,
		"-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p",
		"-fps_mode", "vfr", "-c:v", "libx264", "-preset", "veryfast", output,
	], messages, true)
	if status != 0:
		if FileAccess.file_exists(output):
			DirAccess.remove_absolute(output)
		return false
	return true


func find_ffmpeg() -> String:
	var windows := OS.get_name() == "Windows"
	var binary := "ffmpeg.exe" if windows else "ffmpeg"
	var separator := ";" if windows else ":"
	for folder in OS.get_environment("PATH").split(separator, false):
		var path := folder.strip_edges().trim_prefix('"').trim_suffix('"').path_join(binary)
		if FileAccess.file_exists(path):
			return path
	return ""
