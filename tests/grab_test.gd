extends SceneTree

const Preview := preload("res://game/movement_preview.tscn")
const Settings := preload("res://game/movement_settings.gd")

var failures := 0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var preview = Preview.instantiate()
	root.add_child(preview)
	preview.set_physics_process(false)
	var player = preview.player
	var cube = preview.cube
	player.settings = Settings.new()
	await frames(preview, 16, 0.0, true)
	check(player.held_cube == null, "holding grab at a distance does not pick up the cube")

	await frames(preview, 70, -1.0, false)
	check(cube.position.x < cube.start.x - 0.4, "walking into the cube pushes it")
	await frames(preview, 55, 0.0, true)
	check(player.held_cube == cube and player.grip_side < 0.0, "the nearby cube is grabbed on its near side")
	check(player.motion.rotation.y < -1.45, "grabbing turns the body toward the cube")

	var upper: MeshInstance3D = player.motion.model.limb_meshes[&"LeftUpperArm"]
	var lower: MeshInstance3D = player.motion.model.limb_meshes[&"LeftLowerArm"]
	check(joint(upper, 1.0).is_equal_approx(joint(lower, -1.0)), "reaching keeps the elbow connected")
	check(upper.basis.y.dot(lower.basis.y) > 0.2, "the forearm extends beyond a right-angle bend")
	var mesh := lower.mesh as CapsuleMesh
	check(face_gap(player, lower, mesh.radius) < 0.14, "forearm reaches the face of the cube")

	var initial_x: float = cube.position.x
	await frames(preview, 48, 1.0, true)
	check(cube.position.x > initial_x + 0.8, "walking backward pulls the cube")
	check(player.motion.rotation.y < -1.45, "backward movement keeps the body facing the cube")
	check(absf(player.velocity.x) < player.settings.values.max_speed - 0.5, "weight reduces held movement speed")

	var full_pull_lean: float = player.motion.lean
	check(full_pull_lean < -0.1, "the body leans back under a full pull")
	await frames(preview, 32, 0.25, true)
	check(player.motion.lean < -0.015 and player.motion.lean > full_pull_lean + 0.05,
		"a slow pull uses a lighter backward lean")
	initial_x = cube.position.x
	await frames(preview, 60, -1.0, true)
	check(player.motion.lean > 0.1, "the body leans forward while pushing")
	check(cube.position.x < initial_x - 0.4, "walking toward the held cube pushes it")

	for side in ["Left", "Right"]:
		var forearm: MeshInstance3D = player.motion.model.limb_meshes[StringName(side + "LowerArm")]
		var radius: float = forearm.mesh.radius
		check(face_gap(player, forearm, radius) < 0.16, "both forearms track the moving face")

	await frames(preview, 10, 0.0, false)
	check(player.held_cube == null and player.motion.grip_cube == null, "releasing frees the cube")
	preview.reset_sandbox()
	cube.position = Vector3(1.46, cube.HALF_SIZE + 0.02, 0)
	await frames(preview, 21, 0.0, true)
	check(player.held_cube == cube and player.motion.rotation.y > 1.45, "a cube farther away can be grabbed on the right")
	preview.reset_sandbox()
	check(player.held_cube == null, "reset releases the cube")
	await test_jump_and_roll(preview)
	await test_airborne_acquisition(preview)

	if failures == 0:
		print("Grab checks passed.")
	quit(int(failures > 0))


func test_jump_and_roll(preview) -> void:
	var player = preview.player
	var cube = preview.cube
	cube.position = Vector3(-7.25, cube.HALF_SIZE + 0.02, 0)
	player.position = Vector3(-8.53, 0.29, 0)
	await frames(preview, 25, 0.0, true)
	check(player.is_on_floor() and player.held_cube == cube, "grab the cube from the low step")
	var anchor: Vector3 = player.grip_anchor
	var start_height: float = cube.position.y
	var largest_edge_difference := 0.0
	var greatest_rotation := 0.0
	for frame in 55:
		await physics_frame
		player.update_grip(cube, true)
		player.step(1.0 / 60.0, -1.0, frame < 36)
		var near: Vector3 = cube.to_global(anchor)
		var far: Vector3 = cube.to_global(Vector3(-anchor.x, anchor.y, anchor.z))
		largest_edge_difference = maxf(largest_edge_difference, near.y - far.y)
		greatest_rotation = maxf(greatest_rotation, absf(cube.rotation.z))
		if frame == 0:
			check(player.velocity.y > 0.0 and player.velocity.y < player.settings.values.max_jump,
				"the held cube reduces takeoff speed")
	check(player.held_cube == cube and player.grip_anchor == anchor, "the grip stays on its original face")
	check(largest_edge_difference > 0.25, "the grabbed edge lifts farther than the far edge")
	check(greatest_rotation > 0.25, "the cube tips while being hauled")
	check(cube.position.x < -8.8 and cube.position.y > start_height + 0.20, "a held jump hauls the cube onto the step")
	var angle: float = cube.rotation.z
	await frames(preview, 36, 0.0, false)
	check(player.held_cube == null and absf(angle_difference(angle, cube.rotation.z)) > 0.2,
		"the cube continues rotating after release")


func test_airborne_acquisition(preview) -> void:
	var player = preview.player
	var cube = preview.cube
	preview.reset_sandbox()
	cube.position = Vector3(1.25, cube.HALF_SIZE + 0.02, 0)
	await frames(preview, 16, 0.0, false)
	for frame in 4:
		await physics_frame
		player.step(1.0 / 60.0, 0.0, true)
	check(not player.is_on_floor() and player.held_cube == null, "jump before grabbing the cube")
	var height: float = cube.position.y
	for frame in 12:
		await physics_frame
		player.update_grip(cube, true)
		player.step(1.0 / 60.0, 0.0, true)
	check(player.held_cube == cube, "a jump can catch the side of the cube")
	check(cube.position.y > height + 0.12 and absf(cube.rotation.z) > 0.1,
		"catching it on the way up lifts and tips the cube")


func face_gap(player, forearm: MeshInstance3D, radius: float) -> float:
	var cube = player.held_cube
	var normal: Vector3 = cube.global_basis * player.motion.grip_normal
	var anchor: Vector3 = cube.to_global(player.grip_anchor)
	return absf((joint(forearm, 1.0) - anchor).dot(normal) - radius)


func frames(preview, count: int, direction: float, grabbing: bool) -> void:
	for frame in count:
		await physics_frame
		preview.player.update_grip(preview.cube, grabbing)
		preview.player.step(1.0 / 60.0, direction, false)


func joint(part: MeshInstance3D, side: float) -> Vector3:
	var mesh := part.mesh as CapsuleMesh
	return part.to_global(Vector3.UP * side * (mesh.height * 0.5 - mesh.radius))


func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)
