extends Node3D
## Two comparable planar rigs using the same mannequin dimensions and hand contacts.

const Mannequin := preload("res://game/mannequin.gd")
const SIDES := ["Left", "Right"]
const HAND_SPREAD := Vector3(0.49, 0, -0.16)

var articulated := false
var support: PhysicsBody3D
var footing: PhysicsBody3D
var model: Mannequin
var torso: RigidBody3D
var forearm: RigidBody3D
var upper_arm: RigidBody3D
var leg_bodies: Array[RigidBody3D] = []
var lengths: Dictionary[StringName, float] = {}
var phase := 0.0
var effort := 0.0
var leg_angles := [Vector2.ZERO, Vector2.ZERO]
var leg_speeds := [Vector2.ZERO, Vector2.ZERO]
var shoulder_y := 0.0
var hip_y := 0.0
var torso_rest_y := 0.0
var fore_link_span := 0.0
var previous_velocity := Vector3.ZERO
var foot_contact := false
var grip_force := Vector3.ZERO
var grip_error := 0.0


func configure(body: PhysicsBody3D, feet: PhysicsBody3D, use_links: bool, proportions: String) -> void:
	support = body
	footing = feet
	articulated = use_links
	model = Mannequin.new()
	add_child(model)
	model.decode_proportions(proportions)
	for part: StringName in model.limb_meshes:
		var mesh: CapsuleMesh = model.limb_meshes[part].mesh
		lengths[part] = mesh.height - 2.0 * mesh.radius
	shoulder_y = proximal(&"LeftUpperArm").y
	hip_y = proximal(&"LeftUpperLeg").y
	torso_rest_y = (shoulder_y + hip_y) * 0.5

	var hand := hand_center()
	# Slight compliance margin leaves room for the visible two-arm stance in 3D.
	var fore_span := average_span("LowerArm") - 0.022
	var upper_span := average_span("UpperArm") - 0.020
	fore_link_span = fore_span
	var arm_span := fore_span + upper_span
	var shoulder := hand - Vector3.UP * (arm_span - 0.025)
	torso = make_body("Torso", shoulder - Vector3.UP * (shoulder_y - torso_rest_y), 4.0 if articulated else 5.5)
	if articulated:
		forearm = make_body("ForearmPair", hand - Vector3.UP * fore_span * 0.5, 0.35)
		upper_arm = make_body("UpperArmPair", hand - Vector3.UP * (fore_span + upper_span * 0.5), 0.45)
		pin(support, forearm, hand)
		pin(forearm, upper_arm, hand - Vector3.UP * fore_span)
		pin(upper_arm, torso, hand - Vector3.UP * arm_span)
		make_legs()
	else:
		var foot := Vector3.UP * (model.floor_height - torso_rest_y + 0.12)
		add_foot_shape(torso, foot, 0.12)
	previous_velocity = torso.linear_velocity
	draw_pose()


func make_body(label: String, center: Vector3, weight: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = label
	body.position = center
	body.mass = weight
	body.inertia = Vector3.ONE * maxf(weight * 0.045, 0.025)
	body.collision_layer = 0
	body.collision_mask = 0
	body.axis_lock_linear_z = true
	body.axis_lock_angular_x = true
	body.axis_lock_angular_y = true
	body.can_sleep = false
	body.linear_damp = 0.22
	body.angular_damp = 1.1
	add_child(body)
	return body


func add_foot_shape(body: RigidBody3D, offset: Vector3, radius: float) -> void:
	var collider := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	collider.shape = shape
	collider.position = offset
	body.add_child(collider)
	body.collision_layer = 4
	body.collision_mask = 1
	body.contact_monitor = true
	body.max_contacts_reported = 4
	body.physics_material_override = PhysicsMaterial.new()
	body.physics_material_override.friction = 0.8


func make_legs() -> void:
	for index in SIDES.size():
		var side: String = SIDES[index]
		var upper_name := StringName(side + "UpperLeg")
		var lower_name := StringName(side + "LowerLeg")
		var side_sign := float(index * 2 - 1)
		var hip := torso.position + Vector3(0.15 * side_sign, hip_y - torso_rest_y, -0.15 * side_sign)
		var upper := make_body(side + "Thigh", hip - Vector3.UP * lengths[upper_name] * 0.5, 0.42)
		var knee := hip - Vector3.UP * lengths[upper_name]
		var lower := make_body(side + "Shin", knee - Vector3.UP * lengths[lower_name] * 0.5, 0.32)
		pin(torso, upper, hip)
		pin(upper, lower, knee)
		add_foot_shape(lower, Vector3.DOWN * lengths[lower_name] * 0.5, model.limb_meshes[lower_name].mesh.radius)
		leg_bodies.append(upper)
		leg_bodies.append(lower)


func pin(first: PhysicsBody3D, second: PhysicsBody3D, at: Vector3) -> void:
	var joint := PinJoint3D.new()
	joint.position = at
	add_child(joint)
	joint.node_a = joint.get_path_to(first)
	joint.node_b = joint.get_path_to(second)


func advance(delta: float, intention: float) -> void:
	foot_contact = has_foot_contact()
	effort = move_toward(effort, intention, delta * 5.0)
	phase = fposmod(phase + delta * (2.0 + 8.0 * absf(effort)), TAU)
	var acceleration := (torso.linear_velocity.x - previous_velocity.x) / delta
	previous_velocity = torso.linear_velocity
	if articulated:
		drive_links()
		grip_force = Vector3.ZERO
	else:
		drive_procedural(delta, acceleration)
	draw_pose()


func has_foot_contact() -> bool:
	if not articulated:
		return torso.get_colliding_bodies().has(footing)
	for index in [1, 3]:
		if leg_bodies[index].get_colliding_bodies().has(footing):
			return true
	return false


func drive_links() -> void:
	# The same hip and knee drive applies in the air and while finding footing.
	var activity := absf(effort)
	var hip_strength := lerpf(1.25, 14.0, activity)
	var knee_strength := lerpf(1.0, 10.0, activity)
	if foot_contact:
		hip_strength = maxf(hip_strength, 7.0)
		knee_strength = maxf(knee_strength, 8.0)
	for index in SIDES.size():
		var upper := leg_bodies[index * 2]
		var lower := leg_bodies[index * 2 + 1]
		var target := leg_target(index)
		servo(torso, upper, target.x, hip_strength, 0.95, 12.0)
		servo(upper, lower, target.y, knee_strength, 0.65, 10.0, Vector2(-1.65, 0.17))

	var elbow := angle_difference(forearm.rotation.z, upper_arm.rotation.z)
	servo(forearm, upper_arm, elbow, 0.0, 0.42, 14.0, Vector2(-1.55, 0.32))
	var shoulder := angle_difference(upper_arm.rotation.z, torso.rotation.z)
	var stroke := (leg_bodies[0].angular_velocity.z + leg_bodies[2].angular_velocity.z) * 0.035
	var intent_pose := -0.62 * effort - clampf(stroke, -0.3, 0.3)
	var brace := maxf(activity, 0.32 if foot_contact else 0.0)
	servo(upper_arm, torso, lerpf(shoulder, intent_pose, brace), 30.0, 1.05, 24.0, Vector2(-1.2, 1.2))


func servo(parent: RigidBody3D, child: RigidBody3D, target: float, stiffness: float,
		damping: float, limit: float,
		angles := Vector2(-PI, PI)) -> void:
	var relative := angle_difference(parent.rotation.z, child.rotation.z)
	var speed := child.angular_velocity.z - parent.angular_velocity.z
	var correction := clampf(relative, angles.x, angles.y) - relative
	var torque := clampf(stiffness * angle_difference(relative, target) - damping * speed + correction * 50.0,
		-limit, limit)
	child.apply_torque(Vector3.BACK * torque)
	parent.apply_torque(Vector3.BACK * -torque)


func drive_procedural(delta: float, acceleration: float) -> void:
	var shoulder := torso.to_global(Vector3.UP * (shoulder_y - torso_rest_y))
	var anchor := hand_center()
	var gap := shoulder - anchor
	var reach := average_span("LowerArm") + average_span("UpperArm") - 0.09
	var direction := gap.normalized()
	var velocity := torso.linear_velocity + torso.angular_velocity.cross(shoulder - torso.global_position)
	if support is RigidBody3D:
		velocity -= support.linear_velocity + support.angular_velocity.cross(anchor - support.global_position)
	var tension := 0.0
	if gap.length() > reach:
		tension = clampf((gap.length() - reach) * 1450.0 + velocity.dot(direction) * 48.0, 0.0, 260.0)
	grip_force = direction * tension
	torso.apply_force(-grip_force, shoulder - torso.global_position)
	if support is RigidBody3D:
		support.apply_force(grip_force, anchor - support.global_position)
	# The simplified physical body has one bounded drive at hip height.
	torso.apply_force(Vector3.RIGHT * effort * 14.0, Vector3.UP * (hip_y - torso_rest_y))
	for index in SIDES.size():
		var target := leg_target(index)
		var angle: Vector2 = leg_angles[index]
		var speed: Vector2 = leg_speeds[index]
		var inertial_lag := clampf(-acceleration * 0.018, -0.42, 0.42)
		speed += ((target + Vector2(inertial_lag, 0) - angle) * 44.0 - speed * 7.0) * delta
		leg_angles[index] = angle + speed * delta
		leg_speeds[index] = speed


func leg_target(index: int) -> Vector2:
	var wave := phase + PI * index
	var amplitude := absf(effort) * (0.38 if foot_contact else 1.0)
	var hip := effort * 0.19 + sin(wave) * amplitude * 0.66
	var knee := -0.12 - maxf(0.0, cos(wave)) * amplitude * 0.72
	return Vector2(hip, knee)


func draw_pose() -> void:
	var roll := Basis(Vector3.BACK, torso.rotation.z)
	var look := Basis(Vector3.UP, 0.38)
	var body_basis := roll * look
	var body_pose := Transform3D(body_basis, torso.position - body_basis * Vector3.UP * torso_rest_y)
	model.position = Vector3.ZERO
	for part: MeshInstance3D in [model.torso, model.neck, model.head]:
		if not part.has_meta("hang_rest"):
			part.set_meta("hang_rest", part.transform)
		part.transform = body_pose * part.get_meta("hang_rest")

	grip_error = 0.0
	for index in SIDES.size():
		var side: String = SIDES[index]
		var upper_name := StringName(side + "UpperArm")
		var lower_name := StringName(side + "LowerArm")
		var shoulder := body_pose * proximal(upper_name)
		var hand := hand_point(index)
		var pole := Vector3(0.08, -0.2, float(index * 2 - 1))
		if articulated:
			var guide := forearm.to_global(Vector3.DOWN * fore_link_span * 0.5)
			pole = guide + (hand - hand_center()) * 0.6 - shoulder
		var wrist := solve_arm(upper_name, lower_name, shoulder, hand, pole)
		grip_error = maxf(grip_error, hand.distance_to(wrist))
		draw_leg(index, body_pose)


func draw_leg(index: int, body_pose: Transform3D) -> void:
	var side: String = SIDES[index]
	var upper_name := StringName(side + "UpperLeg")
	var lower_name := StringName(side + "LowerLeg")
	var hip := body_pose * proximal(upper_name)
	var knee: Vector3
	var foot: Vector3
	if articulated:
		var upper := leg_bodies[index * 2]
		var lower := leg_bodies[index * 2 + 1]
		# The leg links and their visible counterparts share the same contact end.
		hip = upper.to_global(Vector3.UP * lengths[upper_name] * 0.5)
		knee = lower.to_global(Vector3.UP * lengths[lower_name] * 0.5)
		foot = lower.to_global(Vector3.DOWN * lengths[lower_name] * 0.5)
	else:
		var angles: Vector2 = leg_angles[index]
		knee = hip + Basis(Vector3.BACK, torso.rotation.z + angles.x) * Vector3.DOWN * lengths[upper_name]
		foot = knee + Basis(Vector3.BACK, torso.rotation.z + angles.x + angles.y) * Vector3.DOWN * lengths[lower_name]
	segment(upper_name, hip, knee)
	segment(lower_name, knee, foot)


func solve_arm(upper: StringName, lower: StringName, shoulder: Vector3, target: Vector3, pole: Vector3) -> Vector3:
	var offset := target - shoulder
	var direction := offset.normalized() if offset.length_squared() > 0.000001 else Vector3.UP
	var a := lengths[upper]
	var b := lengths[lower]
	var distance := clampf(offset.length(), absf(a - b) + 0.001, a + b)
	var along := (a * a - b * b + distance * distance) / (2.0 * distance)
	var bend := pole - direction * pole.dot(direction)
	if bend.length_squared() < 0.001:
		bend = direction.cross(Vector3.BACK)
	var elbow := shoulder + direction * along + bend.normalized() * sqrt(maxf(0.0, a * a - along * along))
	var wrist := shoulder + direction * distance
	segment(upper, shoulder, elbow)
	segment(lower, elbow, wrist)
	return wrist


func segment(part_name: StringName, start: Vector3, end: Vector3) -> void:
	var part: MeshInstance3D = model.limb_meshes[part_name]
	part.position = (start + end) * 0.5
	part.quaternion = Quaternion(Vector3.UP, (end - start).normalized())


func proximal(part_name: StringName) -> Vector3:
	var part: MeshInstance3D = model.limb_meshes[part_name]
	if not part.has_meta("hang_proximal"):
		part.set_meta("hang_proximal", part.position - part.basis.y * lengths[part_name] * 0.5)
	return part.get_meta("hang_proximal")


func average_span(suffix: String) -> float:
	return (lengths[StringName("Left" + suffix)] + lengths[StringName("Right" + suffix)]) * 0.5


func hand_center() -> Vector3:
	return support.to_global(Vector3.ZERO)


func hand_point(index: int) -> Vector3:
	return support.to_global(HAND_SPREAD * float(index * 2 - 1))
