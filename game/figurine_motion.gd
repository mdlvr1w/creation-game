extends Node3D
## Applies a simple velocity-driven pose to the visual model. Collision is independent.

var model: Node3D
var rest: Dictionary[StringName, Transform3D] = {}
var phase := 0.0
var stride := 0.0
var air_pose := 0.0
var facing := 1.0
var grip_cube: RigidBody3D
var reach_cube: RigidBody3D
var grip_side := 0.0
var grip_anchor := Vector3.ZERO
var grip_normal := Vector3.RIGHT
var grip_blend := 0.0
var shared_attachment := false
var travel_speed := 0.0
var grip_start_yaw := 0.0
var grip_lateral := Vector3.BACK
var reach_lowering := 0.0
var physical_crouch := 0.0
var reach_pitch := 0.0
var lean := 0.0
var head_look_target := Vector3.ZERO
var head_look := Vector3.ZERO
var lean_axes: Array[Vector3] = []
const MAX_GRIP_STRETCH := 1.85
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


func animate(delta: float, velocity: Vector3, grounded: bool, max_speed: float, max_lean: float,
		direction: float, intent_speed := 0.0) -> void:
	var speed := absf(velocity.x)
	var pace := clampf(speed / max_speed, 0.0, 1.0)
	stride = move_toward(stride, pace if grounded else 0.0, delta * 5.0)
	air_pose = move_toward(air_pose, 0.0 if grounded else 1.0, delta * 6.0)
	var grabbing := is_instance_valid(grip_cube)
	var shared_hold := grabbing and shared_attachment
	if grabbing:
		reach_cube = grip_cube
	grip_blend = move_toward(grip_blend, 1.0 if grabbing else 0.0, delta * 7.0)
	if speed > 0.12:
		facing = signf(velocity.x)
	var turn_extent := lerpf(0.22, 1.05, maxf(pace, air_pose * 0.65))
	var turn := facing * turn_extent
	if not grounded:
		turn = lerpf(turn, signf(direction) * turn_extent, absf(direction) * AIR_STEERING_POSE_SHARE)
	head_look = head_look.lerp(head_look_target, 1.0 - exp(-delta * 12.0))
	var look_yaw := head_look.y * BODY_LOOK_SHARE
	var yaw := turn + look_yaw
	var attachment_side := grip_side
	if shared_attachment:
		var attachment := Vector3.ZERO
		if shared_hold:
			var shoulder := (rest_shoulder("Left") + rest_shoulder("Right")) * 0.5
			attachment = grip_cube.to_global(grip_anchor) - get_parent().to_global(shoulder - Vector3.UP * physical_crouch)
			attachment_side = signf(attachment.x)
		yaw = shared_facing_yaw(velocity.x, intent_speed, direction, grounded, max_speed, attachment, look_yaw)
	elif grabbing:
		var anchor_offset := grip_cube.to_global(grip_anchor) - global_position
		var lateral_weight := smoothstep(0.25, 0.55, absf(anchor_offset.x))
		yaw = lerp_angle(grip_start_yaw, signf(anchor_offset.x) * PI * 0.5, lateral_weight)
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-delta * 17.0))

	if grounded:
		var stride_speed := speed
		if grabbing:
			# Project the travel onto the visual forward axis, including when it faces against travel.
			stride_speed = velocity.x * sin(rotation.y) if shared_hold else velocity.x * grip_side
		phase = fposmod(phase + stride_speed * delta * 2.2, TAU)
	if shared_hold and not grounded:
		stride = move_toward(stride, absf(direction), delta * 6.0)
		phase = fposmod(phase + direction * delta * 8.0, TAU)

	var target_lean := deg_to_rad(max_lean) * pow(pace, 0.72) if grounded else 0.0
	if grabbing and grounded:
		# Input contributes effort even before a heavy object starts to move.
		var effort := direction * attachment_side
		var load := 0.82 * absf(effort) + 0.18 * pace
		target_lean = deg_to_rad(max_lean) * load * signf(effort)
	lean = lerpf(lean, target_lean, 1.0 - exp(-delta * 10.0))
	var hip_center := (lean_axes[0] + lean_axes[1]) * 0.5
	var body_lean := supported_reach_pose(delta, grounded, hip_center)
	var foot_plant := clampf(reach_lowering * 12.0, 0.0, 1.0)
	if shared_attachment:
		# Keep the center of the shoulders aligned with the body-side attachment.
		var shoulder := model.transform.affine_inverse() * ((rest_shoulder("Left") + rest_shoulder("Right")) * 0.5)
		var pitch := lean + minf(physical_crouch * 0.65, 0.40)
		body_lean = rotation_about(shoulder, pitch)
		body_lean.origin.y -= physical_crouch
		foot_plant = clampf(physical_crouch * 12.0, 0.0, 1.0)
	for part in UPPER_BODY:
		model.get_node(NodePath(String(part))).transform = body_lean * rest[part]

	var head_rest := rest[&"Head"]
	var pivot := head_rest.origin - Vector3.UP * head_rest.basis.y.length() * 0.5
	var turn_head := Basis.from_euler(head_look - Vector3.UP * look_yaw)
	var head_pose := body_lean * Transform3D(turn_head, pivot - turn_head * pivot) * head_rest
	if shared_attachment:
		var head_basis := turn_head * head_rest.basis
		head_pose = Transform3D(head_basis, body_lean * pivot + turn_head * (head_rest.origin - pivot))
	model.get_node("Head").transform = head_pose

	var swing := sin(phase) * stride
	for side in ["Left", "Right"]:
		var cycle := swing if side == "Left" else -swing
		var tuck := clampf(0.18 + velocity.y * 0.02, 0.08, 0.32) * air_pose
		var gait := 1.0 - foot_plant if shared_attachment else 1.0
		pose_pair(side + "UpperLeg", side + "LowerLeg", (cycle * 0.48 - tuck) * gait,
			(maxf(0.0, cycle) * 0.5 + tuck * 1.5) * gait)
		if foot_plant > 0.0:
			bend_knee(side, body_lean, foot_plant)
		pose_pair(side + "UpperArm", side + "LowerArm", (-cycle * 0.40 - air_pose * 0.40) * gait,
			(-0.12 * stride - air_pose * 0.22) * gait, body_lean)

		if grip_blend > 0.0 and is_instance_valid(reach_cube):
			reach_for_cube(side, body_lean)


func shared_facing_yaw(relative_speed: float, intent_speed: float, direction: float, grounded: bool,
		max_speed: float, attachment: Vector3, look_yaw: float) -> float:
	var half_turn := PI * 0.5
	var travel_weight := smoothstep(0.2, max_speed, absf(travel_speed))
	var steering := direction * AIR_STEERING_POSE_SHARE
	var travel_yaw := lerpf(steering, signf(travel_speed) * half_turn, travel_weight)

	# Supported motion within the requested speed keeps its facing through reversals.
	# Platform travel and motion beyond that speed still turn the body.
	var drive_speed := absf(intent_speed)
	var driven_speed := clampf(relative_speed, -drive_speed, drive_speed) if grounded else 0.0
	var carried_weight := smoothstep(0.2, max_speed, absf(travel_speed - driven_speed))
	var attachment_width := smoothstep(0.08, 0.30, absf(attachment.x))
	var lateral_fraction := absf(attachment.x) / maxf(attachment.length(), 0.001)
	var alignment := attachment_width * smoothstep(0.15, 0.65, lateral_fraction)
	var footing_weight := 1.0 if grounded else 0.20
	var grip_weight := alignment * footing_weight * (1.0 - carried_weight)
	return lerpf(travel_yaw + look_yaw, signf(attachment.x) * half_turn, grip_weight)


func supported_reach_pose(delta: float, grounded: bool, hip_center: Vector3) -> Transform3D:
	var supported_reach := 0.0
	if grounded and not shared_attachment and grip_blend > 0.0 and is_instance_valid(reach_cube):
		var anchor := model.to_local(reach_cube.to_global(grip_anchor))
		var height: float = anchor.y - model.floor_height
		var hip_height := maxf(hip_center.y - model.floor_height, 0.1)
		supported_reach = grip_blend * (1.0 - smoothstep(hip_height * 0.22, hip_height * 0.85, height))
	var pitch_goal := supported_reach * 0.76
	var pitch_weight := 1.0 - exp(-delta * 17.0)
	reach_pitch = lerpf(reach_pitch, pitch_goal, pitch_weight)
	var body_pose := rotation_about(hip_center, lean + reach_pitch)
	var lowering := 0.0
	if supported_reach > 0.0:
		for side in ["Left", "Right"]:
			lowering = maxf(lowering, required_arm_drop(side, body_pose))
		lowering = minf(lowering, maxf(0.0, hip_center.y - model.floor_height) * 0.85)
	reach_lowering = lerpf(reach_lowering, lowering * supported_reach, pitch_weight)
	body_pose.origin.y -= reach_lowering
	return body_pose


func required_arm_drop(side: String, body_pose: Transform3D) -> float:
	var upper_name := StringName(side + "UpperArm")
	var upper: MeshInstance3D = model.limb_meshes[upper_name]
	var lower: MeshInstance3D = model.limb_meshes[StringName(side + "LowerArm")]
	var upper_rest := rest[upper_name]
	var start := body_pose * (upper_rest.origin - upper_rest.basis.y * segment_span(upper) * 0.5)
	var target := model.to_local(hand_contact(upper_rest.origin.x, lower.mesh.radius))
	var offset := target - start
	var reach := (segment_span(upper) + segment_span(lower)) * 0.98
	var vertical_reach := sqrt(maxf(0.0, reach * reach - offset.x * offset.x - offset.z * offset.z))
	return maxf(0.0, -offset.y - vertical_reach)


func hand_contact(shoulder_x: float, radius: float) -> Vector3:
	var contact_local := grip_anchor + grip_normal * radius
	if shared_attachment:
		contact_local += grip_lateral * clampf(shoulder_x, -0.08, 0.08)
	else:
		contact_local += grip_lateral * clampf(shoulder_x, -0.33, 0.33)
	return reach_cube.to_global(contact_local)


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

	var contact := hand_contact(upper_rest.origin.x, lower_mesh.radius)
	var relaxed_tip := lower.position + lower.basis.y * lower_span * 0.5
	var attached := shared_attachment and is_instance_valid(grip_cube)
	var target: Vector3 = relaxed_tip.lerp(model.to_local(contact), 1.0 if attached else grip_blend)
	var outward := signf(upper_rest.origin.x)
	var bend := Vector3(outward * 0.45, -1.0, 0.0)
	var downward := smoothstep(0.15, 0.55, shoulder.y - target.y)
	bend = bend.lerp(Vector3(outward * 0.6, 0.0, -1.0), downward)
	solve_pair(upper, lower, shoulder, target, bend, MAX_GRIP_STRETCH if shared_attachment else 1.0)


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
		pole: Vector3, max_stretch := 1.0) -> void:
	var offset := target - start
	if offset.length_squared() < 0.000001:
		return
	var upper_span := segment_span(upper)
	var lower_span := segment_span(lower)
	var stretch := clampf((offset.length() + 0.001) / (upper_span + lower_span), 1.0, max_stretch)
	upper_span *= stretch
	lower_span *= stretch
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
	if stretch > 1.0:
		upper.scale.y = stretch
		lower.scale.y = stretch


func rest_shoulder(side: String) -> Vector3:
	var name := StringName(side + "UpperArm")
	var upper: MeshInstance3D = model.limb_meshes[name]
	var pose := rest[name]
	return model.transform * (pose.origin - pose.basis.y * segment_span(upper) * 0.5)


func hand_radius(side: String) -> float:
	var forearm: MeshInstance3D = model.limb_meshes[StringName(side + "LowerArm")]
	return forearm.mesh.radius


func hand_error() -> float:
	var error := 0.0
	for side in ["Left", "Right"]:
		var forearm: MeshInstance3D = model.limb_meshes[StringName(side + "LowerArm")]
		var hand := forearm.to_global(Vector3.UP * segment_span(forearm) * 0.5)
		var shoulder: Transform3D = rest[StringName(side + "UpperArm")]
		error = maxf(error, hand.distance_to(hand_contact(shoulder.origin.x, forearm.mesh.radius)))
	return error


func arm_reach(side: String) -> float:
	return segment_span(model.limb_meshes[StringName(side + "UpperArm")]) + segment_span(
		model.limb_meshes[StringName(side + "LowerArm")])


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
