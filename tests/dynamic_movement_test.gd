extends SceneTree

const Preview := preload("res://game/movement_preview.tscn")
const Settings := preload("res://game/movement_settings.gd")
const DT := 1.0 / 60.0

var failures := 0
var preview: Node3D


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	preview = Preview.instantiate()
	preview.use_dynamic_controller = true
	root.add_child(preview)
	preview.set_physics_process(false)
	var player = preview.player
	var cube = preview.cube
	player.settings = Settings.new()
	await frames(20)
	check(player.is_on_floor(), "dynamic body finds static ground")
	await frames(35, 0.5)
	check(player.position.x > 1.2 and player.velocity.x > 2.4, "partial stick moves the dynamic body")
	check(player.last_drive_impulse.length() <= player.drive_strength * DT + 0.001, "drive respects its impulse budget")
	await frames(16)
	check(absf(player.velocity.x) < 0.3, "the released stick brakes on the ground")

	var short_jump := await measure_jump(1)
	var full_jump := await measure_jump(35)
	check(full_jump > short_jump + 0.55 and full_jump > 1.15, "tap and hold keep distinct jumps")

	preview.reset_sandbox()
	cube.position = Vector3(-1.23, cube.HALF_SIZE + 0.02, 0)
	await frames(20, 0.0, false, true)
	check(player.held_cube == cube, "the reachable side can be grabbed")
	var anchor: Vector3 = player.grip_anchor
	var cube_height: float = cube.position.y
	await frames(16, 0.0, true, true)
	check(cube.position.y > cube_height + 0.18 and absf(cube.rotation.z) > 0.15, "a side jump lifts and tips the cube")
	check(player.grip_anchor == anchor, "the grip stays at the same local surface point")
	await frames(1)
	check(player.held_cube == null, "releasing removes the relationship")

	var light_progress := await push_for_distance(2.0)
	var heavy_progress := await push_for_distance(14.0)
	check(light_progress > heavy_progress + 0.12, "the same drive moves a lighter cube farther")

	cube.mass = 3.0
	preview.start_on_cube()
	await frames(36, 0.0, false, true)
	check(player.support_body == cube and player.grip_from_above, "top grab identifies the supporting cube")
	var top_start: float = center_height()
	var maximum := top_start
	var takeoffs := 0
	for attempt in 17:
		for frame in 24:
			await frames(1, 0.0, frame < 12, true)
			maximum = maxf(maximum, center_height())
			if player.last_takeoff_impulse.y > 0.0:
				takeoffs += 1
	check(takeoffs >= 10, "the repeated-jump regression actually attempts takeoffs from the cube")
	check(maximum < top_start + 0.5 and center_height() < top_start + 0.15,
		"repeated top-grab jumps do not ratchet the pair upward")

	preview.start_on_cube()
	await frames(36, 0.0, false, true)
	var start_x: float = player.position.x
	for frame in 18:
		cube.apply_central_force(Vector3.LEFT * 105.0)
		await frames(1, 0.0, false, true)
	check(player.position.x < start_x - 0.12, "a moving cube can still carry the figurine")
	await check_off_center_ride()

	if failures == 0:
		print("Dynamic movement checks passed.")
	quit(int(failures > 0))


func check_off_center_ride() -> void:
	preview.reset_sandbox()
	var player = preview.player
	var cube = preview.cube
	cube.position = Vector3(-22, cube.HALF_SIZE + 0.02, 0)
	player.position = Vector3(-21.65, cube.HALF_SIZE * 2.0 + 0.08, 0)
	await frames(16)
	await frames(36, 0.0, false, true)
	check(player.grip_from_above, "off-center stance can grab the top")
	check(absf(cube.linear_velocity.x) < 0.8, "neutral stance does not drive the cube")
	check(is_zero_approx(player.last_drive_speed), "the neutral stick requests no drive speed")
	var peak_speed := 0.0
	for frame in 120:
		await frames(1, -0.20, false, true)
		peak_speed = maxf(peak_speed, absf(cube.linear_velocity.x))
	check(peak_speed < 7.0, "a small stick tilt does not produce runaway lateral motion")
	await frames(60, 0.0, false, true)
	check(absf(cube.linear_velocity.x) < 0.8, "the cube settles after steering stops")


func frames(count: int, direction := 0.0, jump := false, grab := false) -> void:
	for frame in count:
		await physics_frame
		preview.player.update_grip(preview.cube, grab)
		preview.player.step(DT, direction, jump)


func measure_jump(hold_frames: int) -> float:
	preview.reset_sandbox()
	await frames(20)
	var apex := 0.0
	for frame in 65:
		await frames(1, 0.0, frame < hold_frames)
		apex = maxf(apex, preview.player.position.y)
	return apex


func push_for_distance(cube_mass: float) -> float:
	preview.reset_sandbox()
	preview.cube.mass = cube_mass
	preview.cube.position.x = -1.23
	await frames(20, 0.0, false, true)
	check(preview.player.held_cube == preview.cube, "each mass comparison starts with a grip")
	var initial_x: float = preview.cube.position.x
	await frames(50, -1.0, false, true)
	check(is_equal_approx(preview.player.last_drive_speed, -5.5), "grabbing preserves movement intent")
	return initial_x - preview.cube.position.x


func center_height() -> float:
	var player = preview.player
	var cube = preview.cube
	return (player.position.y * player.mass + cube.position.y * cube.mass) / (player.mass + cube.mass)


func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)
