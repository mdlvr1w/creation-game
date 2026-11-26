extends SceneTree

const Viewer := preload("res://game/mannequin_view.tscn")

var failures := 0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var viewer = Viewer.instantiate()
	viewer.load_starting_proportions = false
	root.add_child(viewer)
	await physics_frame
	await physics_frame
	await process_frame
	viewer.set_view(0)

	var model = viewer.figurine
	var upper: MeshInstance3D = model.limb_meshes[&"RightUpperArm"]
	var lower: MeshInstance3D = model.limb_meshes[&"RightLowerArm"]
	var initial_radius: float = upper.mesh.radius
	var initial_length := capsule_span(upper)
	var shoulder := joint_center(upper, -1.0)

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = viewer.camera.unproject_position(upper.global_position)
	root.push_input(click, true)
	await physics_frame
	await process_frame
	check(viewer.selected_limb == &"RightUpperArm" and viewer.limb_controls.visible,
		"clicking the arm opens its controls")

	viewer.limb_controls.sliders[1].value = 135
	check(is_equal_approx(capsule_span(upper), initial_length * 1.35), "length slider stretches the segment")
	check(is_equal_approx(upper.mesh.radius, initial_radius), "length preserves the radius")
	check(shoulder.is_equal_approx(joint_center(upper, -1.0)), "upper segment stays attached to torso")
	check(joint_center(upper, 1.0).is_equal_approx(joint_center(lower, -1.0)),
		"the lower segment follows the elbow")

	viewer.limb_controls.fields[2].value = 130
	check(is_equal_approx(upper.mesh.radius, initial_radius * 1.3), "thickness changes radius only")
	check(is_equal_approx(capsule_span(upper), initial_length * 1.35), "thickness preserves joint spacing")
	viewer.limb_controls.fields[0].value = 120
	check(is_equal_approx(upper.mesh.radius, initial_radius * 1.3 * 1.2), "size scales thickness")
	check(is_equal_approx(capsule_span(upper), initial_length * 1.35 * 1.2), "size scales length")

	var left_upper: MeshInstance3D = model.limb_meshes[&"LeftUpperArm"]
	check(left_upper.material_override == upper.material_override, "both sides are highlighted")
	check(is_equal_approx(capsule_span(left_upper), capsule_span(upper)), "left and right length edit together")
	check(is_equal_approx(left_upper.mesh.radius, upper.mesh.radius), "left and right thickness edit together")
	var before_offset := joint_center(upper, -1.0)
	viewer.limb_controls.fields[3].value = 25
	check(joint_center(upper, -1.0).y > before_offset.y, "height offset raises both attachments")
	check(joint_center(upper, 1.0).is_equal_approx(joint_center(lower, -1.0)), "offset keeps the elbow connected")
	viewer.select_limb(&"RightLowerArm")
	var elbow_before := joint_center(lower, -1.0)
	viewer.limb_controls.fields[3].value = 35
	check(joint_center(lower, -1.0).y > elbow_before.y, "lower offset raises the shared joint")
	check(joint_center(upper, 1.0).is_equal_approx(joint_center(lower, -1.0)), "lower offset keeps the elbow connected")

	var release := click.duplicate() as InputEventMouseButton
	release.pressed = false
	root.push_input(release, true)
	click.position = viewer.camera.unproject_position(model.torso.global_position)
	root.push_input(click, true)
	await physics_frame
	await process_frame
	check(viewer.selected_limb == &"Torso", "clicking the visible torso selects it")
	check(not viewer.limb_controls.fields[3].visible, "torso has a height dimension instead of a joint offset")
	viewer.limb_controls.fields[1].value = 155
	check(is_equal_approx(model.torso.scale.y, 0.78 * 1.55), "torso height can be edited")
	check(is_equal_approx(model.head.position.y - model.neck.position.y, 0.55), "the neck and head follow the torso")
	check(joint_center(upper, 1.0).is_equal_approx(joint_center(lower, -1.0)), "torso edits preserve limb connections")


	root.push_input(release, true)
	click.position = viewer.camera.unproject_position(model.head.global_position)
	root.push_input(click, true)
	await physics_frame
	await process_frame
	check(viewer.selected_limb == &"Head", "clicking the head selects it")
	var head_bottom: float = model.head.position.y - model.head.scale.y * 0.5
	viewer.limb_controls.fields[1].value = 150
	viewer.limb_controls.fields[2].value = 145
	check(is_equal_approx(model.head.scale.y, 1.06 * 1.5), "head height can be edited")
	check(is_equal_approx(model.head.scale.x, 1.06 * 1.45), "head thickness can be edited")
	check(is_equal_approx(model.head.position.y - model.head.scale.y * 0.5, head_bottom),
		"head dimensions keep it attached to the neck")

	root.push_input(release, true)
	click.position = viewer.camera.unproject_position(model.neck.global_position)
	root.push_input(click, true)
	await physics_frame
	await process_frame
	check(viewer.selected_limb == &"Neck", "clicking the neck selects it")
	var head_before_neck_edit: float = model.head.position.y
	viewer.limb_controls.fields[1].value = 145
	check(is_equal_approx(capsule_span(model.neck), 0.16 * 1.45), "neck height can be edited")
	check(model.head.position.y > head_before_neck_edit, "the head follows the neck")
	await process_frame
	check(viewer.limb_controls.position.x > viewer.projected_right_edge(),
		"the controls sit outside the projected silhouette")


	var file := "user://mannequin-test-%s.json" % OS.get_process_id()
	check(viewer.save_proportions(file), "proportions save to JSON")
	var expected: String = model.encode_proportions()
	viewer.set_limb_factor(1, 1.0)
	check(viewer.load_proportions(file) and model.encode_proportions() == expected, "saved proportions reload")
	check(not model.decode_proportions('{"version":1,"limbs":{}}'), "reject incomplete presets")
	check(model.encode_proportions() == expected, "invalid presets preserve current values")
	var legacy: Dictionary = JSON.parse_string(expected)
	legacy.version = 2
	legacy.erase("head")
	legacy.erase("neck")
	check(model.decode_proportions(JSON.stringify(legacy)), "torso and limb presets still load")
	check(is_equal_approx(model.head_factors.y, 1.0) and is_equal_approx(model.neck_factors.y, 1.0),
		"older presets get the original head and neck")
	legacy.version = 1
	legacy.erase("torso")
	for values in legacy.limbs.values():
		values.erase("height_offset")
	check(model.decode_proportions(JSON.stringify(legacy)), "original limb presets still load")
	check(is_equal_approx(model.limb_factors[&"RightUpperArm"].y, 1.35), "legacy dimensions are retained")
	check(is_equal_approx(model.torso_factors.y, 1.0), "legacy presets get the original torso")
	DirAccess.remove_absolute(file)
	if failures == 0:
		print("Mannequin checks passed.")
	quit(int(failures > 0))


func capsule_span(part: MeshInstance3D) -> float:
	var capsule := part.mesh as CapsuleMesh
	return capsule.height - 2.0 * capsule.radius


func joint_center(part: MeshInstance3D, side: float) -> Vector3:
	return part.position + part.basis.y * capsule_span(part) * side * 0.5


func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)
