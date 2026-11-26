extends Node
## Maps controller tilt relative to the player's neutral grip onto a head pose.

var device := -1
var reference := Vector3.ZERO
var recenter_pending := true


func _ready() -> void:
	Input.joy_connection_changed.connect(on_connection_changed)
	choose_device()


func _exit_tree() -> void:
	if device >= 0 and Input.get_connected_joypads().has(device):
		Input.set_joy_motion_sensors_enabled(device, false)


func on_connection_changed(changed_device: int, connected: bool) -> void:
	if changed_device == device and not connected:
		device = -1
	if device < 0:
		choose_device()


func choose_device() -> void:
	for candidate in Input.get_connected_joypads():
		if Input.has_joy_motion_sensors(candidate):
			Input.set_joy_motion_sensors_enabled(candidate, true)
			device = candidate
			recenter()
			return


func recenter() -> void:
	recenter_pending = true


func sample() -> Vector3:
	if device < 0:
		return Vector3.ZERO
	var gravity := Input.get_joy_gravity(device)
	if gravity.length_squared() < 1.0:
		return Vector3.ZERO
	if recenter_pending:
		reference = gravity.normalized()
		recenter_pending = false
	return tilt_pose(reference, gravity.normalized())


static func tilt_pose(neutral: Vector3, gravity: Vector3) -> Vector3:
	var side := clampf((gravity.x - neutral.x) * 1.3, -1.0, 1.0)
	var neutral_pitch := atan2(neutral.z, -neutral.y)
	var current_pitch := atan2(gravity.z, -gravity.y)
	var pitch := clampf(angle_difference(neutral_pitch, current_pitch), -0.65, 0.65)
	return Vector3(-pitch * 0.65, side * 0.65, -side * 0.22)
