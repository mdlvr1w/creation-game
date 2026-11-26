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
	var tip_x := joint(lower, 1.0).x - mesh.radius
	check(absf(tip_x - (cube.position.x + cube.HALF_SIZE)) < 0.14, "forearm reaches the face of the cube")

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
		var surface := joint(forearm, 1.0).x - radius
		check(absf(surface - (cube.position.x + cube.HALF_SIZE)) < 0.16, "both forearms track the moving cube")

	await frames(preview, 10, 0.0, false)
	check(player.held_cube == null and player.motion.grip_cube == null, "releasing frees the cube")
	preview.reset_sandbox()
	cube.position = Vector3(1.46, cube.HALF_SIZE + 0.02, 0)
	await frames(preview, 21, 0.0, true)
	check(player.held_cube == cube and player.motion.rotation.y > 1.45, "a cube farther away can be grabbed on the right")
	preview.reset_sandbox()
	check(player.held_cube == null, "reset releases the cube")

	if failures == 0:
		print("Grab checks passed.")
	quit(int(failures > 0))


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
