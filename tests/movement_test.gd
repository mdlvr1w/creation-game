extends SceneTree

const Preview := preload("res://game/movement_preview.tscn")
const HeadLook := preload("res://game/controller_head_look.gd")
const Settings := preload("res://game/movement_settings.gd")
const Controller := preload("res://game/mannequin_controller.gd")
const Viewer := preload("res://game/mannequin_view.tscn")

var failures := 0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var preview = Preview.instantiate()
	root.add_child(preview)
	preview.set_physics_process(false)
	preview.cube.position.x = -50.0
	var player = preview.player
	player.settings = Settings.new()
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

	check(is_zero_approx(Controller.stick_intent(0.10)), "small stick drift is ignored")
	check(is_equal_approx(Controller.stick_intent(-1.0), -1.0), "full stick deflection maps to full speed intent")
	var half_stick := Controller.stick_intent(0.59)
	check(is_equal_approx(half_stick, 0.5), "stick movement scales after the dead zone")
	for frame in 45:
		await physics_frame
		player.step(1.0 / 60.0, -half_stick, false)
	check(is_equal_approx(absf(player.velocity.x), lerpf(1.4, 5.5, half_stick)), "partial stick uses an intermediate speed")
	var walk_lean: float = player.motion.lean
	for frame in 45:
		await physics_frame
		player.step(1.0 / 60.0, -1.0, false)
	check(player.motion.lean > walk_lean and walk_lean > 0.0, "the torso leans further at higher speeds")
	check(player.motion.model.torso.basis.y.z > 0.0, "the torso actually tilts forward")
	preview.tuning_sliders[&"lean_degrees"].value = 0.0
	for frame in 45:
		await physics_frame
		player.step(1.0 / 60.0, -1.0, false)
	check(absf(player.motion.lean) < 0.001, "setting lean to zero returns the torso upright")

	player.reset()
	var tap_height := await measure_jump(player, false)
	var hold_height := await measure_jump(player, true)
	check(hold_height > tap_height + 0.5, "holding jump reaches a higher apex than tapping")

	preview.tuning_sliders[&"min_speed"].value = 6.0
	check(is_equal_approx(preview.tuning_sliders[&"max_speed"].value, 6.0),
		"speed sliders keep the minimum and maximum ordered")
	preview.tuning_sliders[&"max_jump"].value = 3.0
	check(is_equal_approx(preview.tuning_sliders[&"min_jump"].value, 3.0),
		"jump sliders keep the minimum and maximum ordered")
	preview.tuning_fields[&"gravity"].value = 19.7
	check(is_equal_approx(preview.tuning_sliders[&"gravity"].value, 19.7)
		and is_equal_approx(player.settings.values.gravity, 19.7), "numeric input updates the slider and controller")
	var neutral := Vector3(0, -1, 0)
	check(HeadLook.tilt_pose(neutral, neutral).is_zero_approx(), "neutral grip centers the head")
	var tilt := HeadLook.tilt_pose(neutral, Vector3(0.4, -0.9, 0.2).normalized())
	check(tilt.x < 0.0 and tilt.y > 0.0 and tilt.z < 0.0, "controller tilt produces a head rotation")

	await check_air_tuning(preview)

	var settings_file := "user://movement-test-%s.json" % OS.get_process_id()
	check(player.settings.save_to(settings_file), "movement settings save")
	var restored := Settings.new()
	check(restored.load_from(settings_file), "movement settings reload")
	for key: StringName in Settings.LIMITS:
		check(is_equal_approx(restored.values[key], player.settings.values[key]), "saved setting matches " + String(key))
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(settings_file))
	legacy.version = 1
	legacy.movement.erase("gravity")
	legacy.movement.erase("air_inertia")
	var legacy_file := FileAccess.open(settings_file, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy))
	legacy_file.close()
	check(restored.load_from(settings_file), "older movement saves still load")
	check(is_equal_approx(restored.values.gravity, 22.0) and is_equal_approx(restored.values.air_inertia, 60.0),
		"older saves inherit defaults for the two new settings")
	check(is_equal_approx(restored.values.min_speed, 6.0), "older saves preserve existing tuning")
	DirAccess.remove_absolute(settings_file)

	check_pose_response(player.motion)
	preview.update_camera()
	check(is_equal_approx(preview.camera.position.x, player.get_global_transform_interpolated().origin.x),
		"camera follows the rendered horizontal position")

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


func check_pose_response(motion) -> void:
	var lower: MeshInstance3D = motion.model.limb_meshes[&"LeftLowerLeg"]
	motion.head_look_target = Vector3.ZERO
	for frame in 45:
		motion.animate(1.0 / 60.0, Vector3.ZERO, true, 5.5, 0.0, 0.0)
	var neutral_turn: float = motion.rotation.y
	var foot_height: float = lower.global_position.y
	motion.head_look_target = Vector3(0, -0.55, 0)
	for frame in 45:
		motion.animate(1.0 / 60.0, Vector3.ZERO, true, 5.5, 0.0, 0.0)
	check(motion.rotation.y < neutral_turn - 0.1, "body follows the direction of head tilt")
	check(is_equal_approx(lower.global_position.y, foot_height), "head-driven body turn does not lift the feet")

	motion.head_look_target = Vector3.ZERO
	var airborne_velocity := Vector3(4, -2, 0)
	for frame in 45:
		motion.animate(1.0 / 60.0, airborne_velocity, false, 5.5, 0.0, 0.0)
	var momentum_turn: float = motion.rotation.y
	motion.animate(1.0 / 60.0, airborne_velocity, false, 5.5, 0.0, -1.0)
	check(motion.rotation.y < momentum_turn - 0.05,
		"opposite input moves the pose toward the new direction while momentum is unchanged")


func check_air_tuning(preview) -> void:
	var player = preview.player
	player.position = Vector3(-12, 12, 0)
	await physics_frame
	player.step(1.0 / 60.0, 0.0, false)
	check(not player.is_on_floor(), "air tuning test starts airborne")

	preview.tuning_sliders[&"gravity"].value = 10.0
	player.velocity = Vector3.ZERO
	await physics_frame
	player.step(1.0 / 60.0, 0.0, false)
	var light_fall: float = player.velocity.y
	preview.tuning_sliders[&"gravity"].value = 35.0
	player.velocity = Vector3.ZERO
	await physics_frame
	player.step(1.0 / 60.0, 0.0, false)
	check(player.velocity.y < light_fall, "higher gravity accelerates the fall")

	preview.tuning_sliders[&"air_inertia"].value = 0.0
	player.velocity = Vector3(2, 0, 0)
	await physics_frame
	player.step(1.0 / 60.0, -1.0, false)
	var quick_turn: float = player.velocity.x
	preview.tuning_sliders[&"air_inertia"].value = 100.0
	player.velocity = Vector3(2, 0, 0)
	await physics_frame
	player.step(1.0 / 60.0, 0.0, false)
	check(is_equal_approx(player.velocity.x, 2.0), "full inertia preserves coasting momentum")
	await physics_frame
	player.step(1.0 / 60.0, -1.0, false)
	check(player.velocity.x > quick_turn and player.velocity.x < 2.0,
		"full inertia slows reversal while still allowing steering")
	for frame in 42:
		await physics_frame
		player.step(1.0 / 60.0, -1.0, false)
	check(player.velocity.x < 0 and not player.is_on_floor(), "steering can reverse the character in the air")


func measure_jump(player, held: bool) -> float:
	for frame in 12:
		await physics_frame
		player.step(1.0 / 60.0, 0.0, false)
	await physics_frame
	player.step(1.0 / 60.0, 0.0, true)
	var apex: float = player.position.y
	for frame in 65:
		await physics_frame
		player.step(1.0 / 60.0, 0.0, held)
		apex = maxf(apex, player.position.y)
	return apex


func preview_preset() -> String:
	return FileAccess.get_file_as_string("res://game/default_proportions.json")


func joint(part: MeshInstance3D, side: float) -> Vector3:
	var mesh := part.mesh as CapsuleMesh
	return part.position + part.basis.y * side * (mesh.height * 0.5 - mesh.radius)


func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)
