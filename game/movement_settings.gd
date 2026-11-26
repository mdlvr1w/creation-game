extends RefCounted

const LOCAL_FILE := "user://mannequin-movement.json"
# Each entry contains the minimum, maximum, and default for the control.
const LIMITS := {
	&"min_speed": Vector3(0.3, 9.0, 1.4),
	&"max_speed": Vector3(0.3, 9.0, 5.5),
	&"min_jump": Vector3(1.0, 11.0, 4.0),
	&"max_jump": Vector3(1.0, 11.0, 7.5),
	&"lean_degrees": Vector3(0.0, 35.0, 14.0),
	&"gravity": Vector3(5.0, 45.0, 22.0),
	&"air_inertia": Vector3(0.0, 100.0, 60.0),
}
const NEW_SETTINGS := [&"gravity", &"air_inertia"]
const ORDERED_PAIRS := [[&"min_speed", &"max_speed"], [&"min_jump", &"max_jump"]]

var values: Dictionary[StringName, float] = {}


func _init() -> void:
	for key: StringName in LIMITS:
		values[key] = LIMITS[key].z


func adjust(key: StringName, value: float) -> void:
	var limits: Vector3 = LIMITS[key]
	values[key] = clampf(value, limits.x, limits.y)
	for pair: Array in ORDERED_PAIRS:
		if values[pair[0]] <= values[pair[1]]:
			continue
		var other: StringName = pair[1] if key == pair[0] else pair[0]
		values[other] = values[key]


func save_to(path: String = LOCAL_FILE) -> bool:
	var temp := "%s.%s.%s.tmp" % [path, OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	var settings := {}
	for key: StringName in values:
		settings[String(key)] = snappedf(values[key], 0.1)
	var written := file.store_string(JSON.stringify({"version": 2, "movement": settings}, "\t"))
	file.close()
	if not written or DirAccess.rename_absolute(temp, path) != OK:
		DirAccess.remove_absolute(temp)
		return false
	return true


func load_from(path: String = LOCAL_FILE) -> bool:
	var contents: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not contents is Dictionary:
		return false
	var version: Variant = contents.get("version")
	if version != 1 and version != 2:
		return false
	var settings: Variant = contents.get("movement")
	if not settings is Dictionary:
		return false
	var loaded: Dictionary[StringName, float] = {}
	for key: StringName in LIMITS:
		var limits: Vector3 = LIMITS[key]
		var value: Variant = settings.get(String(key))
		if version == 1 and key in NEW_SETTINGS:
			value = float(limits.z)
		if not value is float or not is_finite(value) or value < snappedf(limits.x, 0.1) or value > limits.y:
			return false
		loaded[key] = value
	for pair: Array in ORDERED_PAIRS:
		if loaded[pair[0]] > loaded[pair[1]]:
			return false
	values = loaded
	return true
