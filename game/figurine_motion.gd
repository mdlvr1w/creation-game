extends Node3D
## Applies a simple velocity-driven pose to the visual model. Collision is independent.
const GrabCube := preload("res://game/grabbable_cube.gd")

var model: Node3D
var rest: Dictionary[StringName, Transform3D] = {}
var phase := 0.0
var stride := 0.0
var air_pose := 0.0
var facing := 1.0
var grip_cube: GrabCube
var reach_cube: GrabCube
var grip_side := 0.0
var grip_anchor := Vector3.ZERO
var grip_normal := Vector3.RIGHT
var grip_blend := 0.0
var grip_from_above := false
var lean := 0.0
var head_look_target := Vector3.ZERO
var head_look := Vector3.ZERO
var lean_axes: Array[Vector3] = []
const BODY_LOOK_SHARE := 0.34
const AIR_STEERING_POSE_SHARE := 0.42
const UPPER_BODY := [&"Torso", &"Neck", &"Head"]


func bind_model(visual: Node3D) -> void:
	model = visual
	for limb: StringName in model.limb_meshes:
		rest[limb] = model.limb_meshes[limb].transform
	for part in UPPER_BODY:
		rest[part] = model.get_node(NodePath(String(part))).transform
	for side in ["Left", "Right"]:
		var hip := StringName(side + "UpperLeg")
		var mesh: CapsuleMesh = model.limb_meshes[hip].mesh
		lean_axes.append(rest[hip].origin - rest[hip].basis.y * (mesh.height * 0.5 - mesh.radius))


func animate(delta: float, velocity: Vector3, grounded: bool, max_speed: float, max_lean: float, direction: float) -> void:
	var speed := absf(velocity.x)
	var pace := clampf(speed / max_speed, 0.0, 1.0)
	stride = move_toward(stride, pace if grounded else 0.0, delta * 5.0)
	air_pose = move_toward(air_pose, 0.0 if grounded else 1.0, delta * 6.0)
	var grabbing := is_instance_valid(grip_cube)
	if grabbing:
		reach_cube = grip_cube
	grip_blend = move_toward(grip_blend, 1.0 if grabbing else 0.0, delta * 7.0)
	if grounded:
		var stride_speed := velocity.x * grip_side if grabbing else speed
		phase = fposmod(phase + stride_speed * delta * 2.2, TAU)
	if speed > 0.12:
		facing = signf(velocity.x)
	var turn_extent := lerpf(0.22, 1.05, maxf(pace, air_pose * 0.65))
	var turn := facing * turn_extent
	if not grounded:
		turn = lerpf(turn, signf(direction) * turn_extent, absf(direction) * AIR_STEERING_POSE_SHARE)
	head_look = head_look.lerp(head_look_target, 1.0 - exp(-delta * 12.0))
	var look_yaw := head_look.y * BODY_LOOK_SHARE
	var grab_facing := grip_side
	if grabbing and grip_from_above:
		var horizontal := grip_cube.to_global(grip_anchor).x - global_position.x
		if absf(horizontal) > 0.32:
			grab_facing = signf(horizontal)
	var yaw := grab_facing * PI * 0.5 if grabbing else turn + look_yaw
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-delta * 17.0))

	var target_lean := deg_to_rad(max_lean) * pow(pace, 0.72) if grounded else 0.0
	if grabbing and grounded:
		# Input contributes effort even before a heavy object starts to move.
		var effort := direction * grip_side
		var load := 0.82 * absf(effort) + 0.18 * pace
		target_lean = deg_to_rad(max_lean) * load * signf(effort)
	lean = lerpf(lean, target_lean, 1.0 - exp(-delta * 10.0))
	var hip_center := (lean_axes[0] + lean_axes[1]) * 0.5
	var crouch := grip_blend if grip_from_above else 0.0
	if crouch > 0.0 and is_instance_valid(reach_cube):
		var anchor_height := reach_cube.to_global(grip_anchor).y - global_position.y
		crouch *= 1.0 - smoothstep(0.16, 1.1, anchor_height)
	var crouch_depth := clampf((hip_center.y - model.floor_height) * 0.80, 0.17, 1.25)
	var body_lean := rotation_about(hip_center, lerpf(lean, 0.55, crouch))
	body_lean.origin.y -= crouch_depth * crouch
	for part in UPPER_BODY:
		model.get_node(NodePath(String(part))).transform = body_lean * rest[part]

	var head_rest := rest[&"Head"]
	var pivot := head_rest.origin - Vector3.UP * head_rest.basis.y.length() * 0.5
	var turn_head := Basis.from_euler(head_look - Vector3.UP * look_yaw)
	model.get_node("Head").transform = body_lean * Transform3D(turn_head, pivot - turn_head * pivot) * head_rest

	var swing := sin(phase) * stride
	for side in ["Left", "Right"]:
		var cycle := swing if side == "Left" else -swing
		var tuck := clampf(0.18 + velocity.y * 0.02, 0.08, 0.32) * air_pose
		pose_pair(side + "UpperLeg", side + "LowerLeg", cycle * 0.48 - tuck,
			maxf(0.0, cycle) * 0.5 + tuck * 1.5)
		if crouch > 0.0:
			bend_knee(side, body_lean, crouch)
		pose_pair(side + "UpperArm", side + "LowerArm", -cycle * 0.40 - air_pose * 0.40,
			-0.12 * stride - air_pose * 0.22, body_lean)

		if grip_blend > 0.0 and is_instance_valid(reach_cube):
			reach_for_cube(side, body_lean)


func reach_for_cube(side: String, body_pose: Transform3D) -> void:
	var upper_name := StringName(side + "UpperArm")
	var lower_name := StringName(side + "LowerArm")
	var upper: MeshInstance3D = model.limb_meshes[upper_name]
	var lower: MeshInstance3D = model.limb_meshes[lower_name]
	var upper_rest := rest[upper_name]
	var upper_mesh := upper.mesh as CapsuleMesh
	var lower_mesh := lower.mesh as CapsuleMesh
	var upper_span := upper_mesh.height - 2.0 * upper_mesh.radius
	var lower_span := lower_mesh.height - 2.0 * lower_mesh.radius
	var shoulder := body_pose * (upper_rest.origin - upper_rest.basis.y * upper_span * 0.5)

	# Both forearms track the same face in the cube's local coordinates.
	var contact_local := grip_anchor + grip_normal * lower_mesh.radius
	contact_local.z -= grip_side * clampf(upper_rest.origin.x, -0.36, 0.36)
	var contact := reach_cube.to_global(contact_local)
	var relaxed_tip := lower.position + lower.basis.y * lower_span * 0.5
	var target: Vector3 = relaxed_tip.lerp(model.to_local(contact), grip_blend)
	var outward := signf(upper_rest.origin.x)
	var bend := Vector3(outward * 0.45, -1.0, 0.0)
	if grip_from_above:
		bend = Vector3(outward * 0.6, 0.0, -1.0)
	solve_pair(upper, lower, shoulder, target, bend)


func bend_knee(side: String, body_pose: Transform3D, crouch: float) -> void:
	var upper_name := StringName(side + "UpperLeg")
	var lower_name := StringName(side + "LowerLeg")
	var upper: MeshInstance3D = model.limb_meshes[upper_name]
	var lower: MeshInstance3D = model.limb_meshes[lower_name]
	var upper_rest := rest[upper_name]
	var lower_rest := rest[lower_name]
	var hip := body_pose * (upper_rest.origin - upper_rest.basis.y * segment_span(upper) * 0.5)
	var half_span := segment_span(lower) * 0.5
	var animated_foot := lower.position + lower.basis.y * half_span
	var planted_foot := lower_rest.origin + lower_rest.basis.y * half_span
	solve_pair(upper, lower, hip, animated_foot.lerp(planted_foot, crouch), Vector3.BACK)


func solve_pair(upper: MeshInstance3D, lower: MeshInstance3D, start: Vector3, target: Vector3,
		pole: Vector3) -> void:
	var offset := target - start
	if offset.length_squared() < 0.000001:
		return
	var upper_span := segment_span(upper)
	var lower_span := segment_span(lower)
	var direction := offset.normalized()
	var distance := clampf(offset.length(), absf(upper_span - lower_span) + 0.001,
		upper_span + lower_span - 0.001)
	var along := (upper_span * upper_span - lower_span * lower_span + distance * distance) / (2.0 * distance)
	var bend_amount := sqrt(maxf(0.0, upper_span * upper_span - along * along))
	var bend := pole - direction * pole.dot(direction)
	if bend.length_squared() < 0.000001:
		bend = direction.cross(Vector3.RIGHT)
	var joint := start + direction * along + bend.normalized() * bend_amount
	point_segment(upper, start, joint)
	point_segment(lower, joint, start + direction * distance)


func segment_span(part: MeshInstance3D) -> float:
	var mesh := part.mesh as CapsuleMesh
	return mesh.height - 2.0 * mesh.radius


func point_segment(part: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	part.position = (from + to) * 0.5
	part.quaternion = Quaternion(Vector3.UP, (to - from).normalized())


func pose_pair(upper_name: StringName, lower_name: StringName, angle: float, bend: float, body_pose := Transform3D.IDENTITY) -> void:
	var upper: MeshInstance3D = model.limb_meshes[upper_name]
	var lower: MeshInstance3D = model.limb_meshes[lower_name]
	var upper_rest := rest[upper_name]
	var lower_rest := rest[lower_name]
	var mesh := upper.mesh as CapsuleMesh
	var half_span := (mesh.height - mesh.radius * 2.0) * 0.5
	var attachment := upper_rest.origin - upper_rest.basis.y * half_span
	var joint := upper_rest.origin + upper_rest.basis.y * half_span
	var swing := body_pose * rotation_about(attachment, angle)
	upper.transform = swing * upper_rest
	lower.transform = swing * rotation_about(joint, bend) * lower_rest


func rotation_about(pivot: Vector3, angle: float) -> Transform3D:
	var turn := Basis(Vector3.RIGHT, angle)
	return Transform3D(turn, pivot - turn * pivot)
