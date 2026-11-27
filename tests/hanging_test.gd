extends SceneTree

const Preview := preload("res://game/hanging_preview.tscn")
const DT := 1.0 / 60.0

var failures := 0
var preview: Node3D


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	preview = Preview.instantiate()
	root.add_child(preview)
	preview.set_physics_process(false)
	for articulated in [false, true]:
		for movable in [false, true]:
			await compare(articulated, movable)
	if failures == 0:
		print("Hanging checks passed.")
	quit(int(failures > 0))


func compare(articulated: bool, movable: bool) -> void:
	preview.articulated = articulated
	preview.movable = movable
	preview.restart()
	var rig = preview.rig
	await frames(80, 0.0)
	var initial_support: Vector3 = preview.support.position
	var original_angle: float = rig.leg_bodies[0].rotation.z if articulated else rig.leg_angles[0].x
	check(not rig.foot_contact, "rig starts hanging clear of the ledge")
	check(rig.grip_error < 0.04, "neutral hanging reaches both hand anchors")

	var support_travel := 0.0
	var leg_change := 0.0
	var grip_error := 0.0
	for frame in 90:
		await frames(1, 1.0)
		support_travel = maxf(support_travel, initial_support.distance_to(preview.support.position))
		var leg_angle: float = rig.leg_bodies[0].rotation.z if articulated else rig.leg_angles[0].x
		leg_change = maxf(leg_change, absf(angle_difference(original_angle, leg_angle)))
		grip_error = maxf(grip_error, rig.grip_error)
	check(leg_change > 0.25, "directional input changes the leg motion while hanging")
	check(grip_error < 0.10, "the arms retain their hand targets during active movement")
	if movable:
		check(support_travel > 0.02, "character effort moves the free support")
	else:
		check(support_travel < 0.001, "fixed support stays fixed")

	var after_input := 0.0
	for frame in 12:
		await frames(1, 0.0)
		after_input = maxf(after_input, absf(rig.torso.linear_velocity.x))
	check(after_input > 0.035, "the torso retains motion after input stops")
	await frames(50, 0.0)
	preview.nudge()
	var passive_speed := 0.0
	for frame in 45:
		await frames(1, 0.0)
		passive_speed = maxf(passive_speed, absf(rig.torso.linear_velocity.x))
	check(passive_speed > 0.10, "an external nudge moves the hanging character")

	preview.raised = true
	var contact_frames := 0
	for frame in 205:
		await physics_frame
		preview._physics_process(DT)
		if rig.foot_contact:
			contact_frames += 1
	check(contact_frames > 8, "raising the ledge gives the feet physical support")
	preview.raised = false
	for frame in 160:
		await physics_frame
		preview._physics_process(DT)
	check(not rig.foot_contact, "lowering the ledge returns the rig to hanging")
	check(rig.grip_error < 0.10, "the grip survives the footing transition")


func frames(count: int, intent: float) -> void:
	for frame in count:
		await physics_frame
		preview.rig.advance(DT, intent)


func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error("%s (articulated=%s, movable=%s)" % [description, preview.articulated, preview.movable])
