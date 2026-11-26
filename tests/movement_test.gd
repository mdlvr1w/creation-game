extends SceneTree

const Preview := preload("res://game/movement_preview.tscn")
const Viewer := preload("res://game/mannequin_view.tscn")

var failures := 0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var preview = Preview.instantiate()
	root.add_child(preview)
	preview.set_physics_process(false)
	var player = preview.player
	var visual = player.motion.model
	check(is_equal_approx(visual.torso_factors.y, 1.21), "preview loads the chosen torso")
	check(is_equal_approx(visual.neck_factors.z, 0.80), "preview loads the chosen neck")
	check(is_equal_approx(visual.limb_factors[&"LeftLowerArm"].y, 1.20), "preview loads the chosen forearms")
	for frame in 12:
		await physics_frame
		player.step(1.0 / 60.0, 0.0, false)
	check(player.is_on_floor(), "character lands on the floor")

	for frame in 18:
		await physics_frame
		player.step(1.0 / 60.0, 1.0, false)
	check(player.position.x > 0.5, "horizontal intent moves the character")
	check(player.motion.stride > 0.25, "moving on the floor blends in a stride")
	var upper: MeshInstance3D = visual.limb_meshes[&"LeftUpperLeg"]
	var lower: MeshInstance3D = visual.limb_meshes[&"LeftLowerLeg"]
	check(joint(upper, 1.0).is_equal_approx(joint(lower, -1.0)), "animation preserves the knee connection")

	await physics_frame
	player.step(1.0 / 60.0, 0.0, true)
	check(player.velocity.y > 0.0 and not player.is_on_floor(), "jump leaves the floor")
	for frame in 8:
		await physics_frame
		player.step(1.0 / 60.0, 0.0, false)
	check(player.motion.air_pose > 0.5, "airborne state blends in a jump pose")

	for frame in 60:
		await physics_frame
		player.step(1.0 / 60.0, 0.0, false)
	check(player.is_on_floor() and is_zero_approx(player.velocity.x), "character lands and stops")

	preview.queue_free()
	await process_frame
	var viewer = Viewer.instantiate()
	# Preview round trips should preserve a displayed edit even before it is saved.
	var state: Dictionary = JSON.parse_string(preview_preset())
	state.head.length = 1.4
	set_meta("preview_proportions", JSON.stringify(state))
	root.add_child(viewer)
	check(is_equal_approx(viewer.figurine.head_factors.y, 1.4), "viewer restores preview proportions")
	if failures == 0:
		print("Movement checks passed.")
	quit(int(failures > 0))


func preview_preset() -> String:
	return FileAccess.get_file_as_string("res://game/default_proportions.json")


func joint(part: MeshInstance3D, side: float) -> Vector3:
	var mesh := part.mesh as CapsuleMesh
	return part.position + part.basis.y * side * (mesh.height * 0.5 - mesh.radius)


func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)
