extends SceneTree

const Preview := preload("res://game/movement_preview.tscn")
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
	var settings_file := "user://movement-test-%s.json" % OS.get_process_id()
	check(player.settings.save_to(settings_file), "movement settings save")
	var restored := Settings.new()
	check(restored.load_from(settings_file), "movement settings reload")
	for key: StringName in Settings.LIMITS:
		check(is_equal_approx(restored.values[key], player.settings.values[key]), "saved setting matches " + String(key))
	DirAccess.remove_absolute(settings_file)

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
