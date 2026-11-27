extends RigidBody3D
## The experimental body drives toward an intention with finite strength.
## Contacts and the temporary two-body grip determine the resulting motion.

const Motion := preload("res://game/figurine_motion.gd")
const Settings := preload("res://game/movement_settings.gd")

const CATCH_REACH := 1.35
const GRIP_STIFFNESS := 1700.0
const GRIP_DAMPING := 100.0
const GRIP_FORCE := 550.0
const GRIP_ENGAGEMENT_TIME := 0.06
const CAPSULE_HEIGHT := 1.75

@export var drive_strength := 145.0
@export var drive_response := 0.12
@export var braking_response := 0.09

var motion := Motion.new()
var settings := Settings.new()

var direction := 0.0
var jump_held := false
var jump_requested := false
var jump_was_held := false
var can_cut_jump := false
var floor_normal := Vector3.ZERO
var support_velocity := Vector3.ZERO
var support_body: PhysicsBody3D
var support_position := Vector3.ZERO
var support_relative_y := 0.0

var held_cube: RigidBody3D
var grip_anchor := Vector3.ZERO
var grip_normal := Vector3.ZERO
var grip_clearance := 0.0
var grip_from_above := false
var grip_shoulder := Vector3.ZERO
var grip_reach := 0.0
var grip_rest_length := 0.0
var grip_age := 0.0
var grip_launch := false
var near_grip_footing := false
var physical_crouch := 0.0
var crouch_clearance := CapsuleShape3D.new()
var last_support_impulse := 0.0
var last_grip_sample: Dictionary = {}
var last_upright_torque := 0.0
var body_collider := CollisionShape3D.new()
var last_drive_speed := 0.0
var last_grip_force := Vector3.ZERO
var last_shared_support := false
var last_drive_impulse := Vector3.ZERO
var last_takeoff_impulse := Vector3.ZERO
var last_simulated_input := Vector2.ZERO

var velocity: Vector3:
	get:
		return linear_velocity


func _ready() -> void:
	mass = 6.0
	axis_lock_linear_z = true
	axis_lock_angular_x = true
	axis_lock_angular_y = true
	can_sleep = false
	continuous_cd = true
	collision_mask = 3
	max_contacts_reported = 12
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0

	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.12
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	# Leave room for the overhead reach before the movement capsule meets the tread.
	capsule.height = CAPSULE_HEIGHT
	crouch_clearance.radius = capsule.radius
	body_collider.shape = capsule
	body_collider.position.y = capsule.height * 0.5
	add_child(body_collider)
	add_child(motion)
	motion.shared_attachment = true


func step(delta: float, move_intent: float, jump_down: bool, jump_pressed := false) -> void:
	direction = move_intent
	jump_requested = jump_requested or jump_pressed or (jump_down and not jump_was_held)
	jump_was_held = jump_down
	jump_held = jump_down
	var world_gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	gravity_scale = settings.values.gravity / world_gravity
	update_physical_crouch(delta)
	motion.travel_speed = linear_velocity.x
	var visual_velocity := linear_velocity
	if is_on_floor():
		visual_velocity.x -= support_velocity.x
	motion.animate(delta, visual_velocity, is_on_floor(), settings.values.max_speed, settings.values.lean_degrees,
		direction, target_speed())


func update_physical_crouch(delta: float) -> void:
	var target := 0.0
	if held_cube != null:
		var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.65,
			global_position - Vector3.UP * 0.25, collision_mask, [get_rid()])
		var foot := get_world_3d().direct_space_state.intersect_ray(query)
		if near_grip_footing or support_body == held_cube or (
				not foot.is_empty() and foot.collider == held_cube and foot.normal.y > 0.45):
			target = clampf(grip_shoulder.y - grip_reach * 0.94, 0.50,
				CAPSULE_HEIGHT - crouch_clearance.radius * 2.0)
	var lowering := move_toward(physical_crouch, target, delta * 4.0)
	if is_equal_approx(lowering, physical_crouch):
		return
	if lowering < physical_crouch:
		# Check the space at the growing end without re-testing the planted end.
		var upper := (body_collider.shape as CapsuleShape3D).height - crouch_clearance.radius
		crouch_clearance.height = crouch_clearance.radius * 2.0 + physical_crouch - lowering
		var clearance := PhysicsShapeQueryParameters3D.new()
		clearance.shape = crouch_clearance
		clearance.transform = global_transform.translated(global_basis.y * (
			upper + (physical_crouch - lowering) * 0.5))
		clearance.collision_mask = collision_mask
		clearance.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_shape(clearance, 1).is_empty():
			return
	set_physical_crouch(lowering)


func set_physical_crouch(lowering: float) -> void:
	physical_crouch = lowering
	var capsule := body_collider.shape as CapsuleShape3D
	capsule.height = CAPSULE_HEIGHT - lowering
	body_collider.position.y = capsule.height * 0.5
	motion.physical_crouch = lowering


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	read_support(state)
	if is_on_floor():
		grip_launch = false
	update_balance(state)
	last_simulated_input = Vector2(direction, float(jump_requested))
	last_takeoff_impulse = Vector3.ZERO
	apply_drive(state)
	if jump_requested and support_body != null and support_relative_y < 0.8:
		takeoff(state)
		can_cut_jump = jump_held
	elif can_cut_jump and not jump_held and state.linear_velocity.y > settings.values.min_jump:
		var cut: float = settings.values.min_jump - state.linear_velocity.y
		state.apply_central_impulse(Vector3.UP * cut * mass)
		can_cut_jump = false
	elif not jump_held or state.linear_velocity.y <= 0.0:
		can_cut_jump = false
	jump_requested = false

	last_grip_force = Vector3.ZERO
	last_grip_sample = {}
	last_shared_support = held_cube != null and held_cube == support_body
	if held_cube != null:
		apply_attachment(state)


func read_support(state: PhysicsDirectBodyState3D) -> void:
	support_body = null
	floor_normal = Vector3.ZERO
	support_velocity = Vector3.ZERO
	support_relative_y = 0.0
	var best_normal := 0.70
	near_grip_footing = false
	last_support_impulse = 0.0
	for index in state.get_contact_count():
		var normal := state.get_contact_local_normal(index)
		var foot_offset := state.get_contact_local_position(index) - state.transform.origin
		var collider := state.get_contact_collider_object(index) as PhysicsBody3D
		if held_cube != null and collider == held_cube and normal.y > 0.45 and foot_offset.y < 0.75:
			near_grip_footing = true
		if collider == null or normal.y <= best_normal or foot_offset.dot(state.transform.basis.y) > 0.4:
			continue
		last_support_impulse = state.get_contact_impulse(index).dot(normal)
		best_normal = normal.y
		support_body = collider
		floor_normal = normal
		support_position = state.get_contact_collider_position(index)
		support_velocity = state.get_contact_collider_velocity_at_position(index)
		support_relative_y = state.linear_velocity.y - support_velocity.y


func target_speed() -> float:
	return signf(direction) * lerpf(settings.values.min_speed, settings.values.max_speed, absf(direction))


func apply_drive(state: PhysicsDirectBodyState3D) -> void:
	var tuning := settings.values
	last_drive_speed = target_speed()
	if not is_on_floor() and (held_cube != null or (grip_launch and is_zero_approx(direction))):
		last_drive_impulse = Vector3.ZERO
		return
	var drive_budget := drive_strength
	var response := braking_response if is_zero_approx(direction) else drive_response
	if support_body is RigidBody3D:
		# Dynamic footing has less traction than solid ground and can give way.
		drive_budget *= 0.40
		response *= 1.6
	elif not is_on_floor():
		var drag_floor := 0.0 if is_zero_approx(direction) else 0.15
		drive_budget *= lerpf(1.0, drag_floor, tuning.air_inertia / 100.0)

	var difference := last_drive_speed - (state.linear_velocity.x - support_velocity.x)
	var impulse := clampf(difference * mass * state.step / response, -drive_budget * state.step, drive_budget * state.step)
	last_drive_impulse = Vector3(impulse, 0, 0)
	state.apply_central_impulse(last_drive_impulse)
	# Traction against a movable support exchanges momentum at the foot contact.
	if support_body is RigidBody3D:
		support_body.apply_impulse(-last_drive_impulse, support_position - support_body.global_position)


func takeoff(state: PhysicsDirectBodyState3D) -> void:
	var launch_speed: float = settings.values.max_jump if jump_held else settings.values.min_jump
	var effective_mass := mass
	if support_body is RigidBody3D and not support_body.freeze:
		effective_mass = 1.0 / (state.inverse_mass + 1.0 / support_body.mass)
	var impulse := Vector3.UP * (maxf(0.0, launch_speed - support_relative_y) * effective_mass)
	last_takeoff_impulse = impulse
	state.apply_central_impulse(impulse)
	if support_body is RigidBody3D:
		support_body.apply_impulse(-impulse, support_position - support_body.global_position)


func update_balance(state: PhysicsDirectBodyState3D) -> void:
	var angle := state.transform.basis.y.signed_angle_to(Vector3.UP, Vector3.BACK)
	# A stronger upright preference during locomotion leaves room to swing under grip load.
	var stiffness := 500.0 if held_cube == null else 145.0
	var damping := 48.0 if held_cube == null else 26.0
	var torque_limit := 210.0 if held_cube == null else 105.0
	last_upright_torque = clampf(stiffness * angle - damping * state.angular_velocity.z, -torque_limit, torque_limit)
	state.apply_torque_impulse(Vector3.BACK * last_upright_torque * state.step)


func apply_attachment(state: PhysicsDirectBodyState3D) -> void:
	var rim_offset := held_cube.global_basis * grip_anchor
	var shoulder_offset := state.transform.basis * (grip_shoulder - Vector3.UP * physical_crouch)
	var visual_offset := held_cube.global_basis * (grip_anchor + grip_normal * grip_clearance)
	var separation := held_cube.global_position + visual_offset - state.transform.origin - shoulder_offset
	var distance := separation.length()
	var lever := shoulder_offset - state.transform.basis * state.center_of_mass_local
	last_grip_sample = {
		"shoulder": state.transform.origin + shoulder_offset,
		"center": state.transform * state.center_of_mass_local,
		"lever": lever,
		"contact_count": state.get_contact_count(),
		"roll_speed": state.angular_velocity.z,
		"torque": 0.0,
	}
	var nominal_length := grip_reach * 0.94
	if grip_age == 0.0:
		grip_rest_length = maxf(distance, nominal_length)
	# Take up slack only as the endpoints come together on their own.
	grip_rest_length = maxf(nominal_length, minf(grip_rest_length, distance))
	grip_age += state.step
	if distance < grip_rest_length or is_zero_approx(distance):
		return

	var axis := separation / distance
	var shoulder_velocity := state.linear_velocity + state.angular_velocity.cross(lever)
	var rim_velocity := held_cube.linear_velocity + held_cube.angular_velocity.cross(visual_offset)
	var tension := (distance - grip_rest_length) * GRIP_STIFFNESS
	tension += (rim_velocity - shoulder_velocity).dot(axis) * GRIP_DAMPING
	var engagement := smoothstep(0.0, GRIP_ENGAGEMENT_TIME, grip_age - state.step)
	var impulse := axis * clampf(tension, 0.0, GRIP_FORCE) * engagement * state.step
	impulse.z = 0.0
	last_grip_sample["torque"] = lever.cross(impulse).z / state.step
	state.apply_impulse(impulse, shoulder_offset)
	held_cube.apply_impulse(-impulse, rim_offset)
	last_grip_force = -impulse / state.step


func release_grip() -> void:
	if held_cube != null:
		grip_launch = true
		can_cut_jump = false
		angular_damp = 0.0
	held_cube = null
	grip_from_above = false
	motion.grip_cube = null


func update_grip(target: RigidBody3D, held: bool) -> void:
	var candidates: Array[RigidBody3D] = []
	if target != null:
		candidates.append(target)
	update_grip_candidates(candidates, held)


func update_grip_candidates(candidates: Array[RigidBody3D], held: bool) -> void:
	if not held:
		release_grip()
		return
	if held_cube != null or candidates.is_empty():
		return
	grip_shoulder = (motion.rest_shoulder("Left") + motion.rest_shoulder("Right")) * 0.5
	grip_reach = (motion.arm_reach("Left") + motion.arm_reach("Right")) * 0.5
	var origins: Array[Vector3] = [to_global(grip_shoulder)]
	if is_on_floor():
		origins.append(global_position + Vector3.UP * 0.22)
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	var space := get_world_3d().direct_space_state
	var best: Dictionary = {}
	var closest := INF
	for origin in origins:
		query.from = origin
		for ray in 24:
			var angle := TAU * ray / 24.0
			query.to = origin + Vector3(cos(angle), sin(angle), 0.0) * grip_reach * CATCH_REACH
			var hit := space.intersect_ray(query)
			if hit.is_empty() or not hit.collider is RigidBody3D or hit.collider not in candidates:
				continue
			var distance := origin.distance_to(hit.position)
			if distance < closest:
				best = hit
				closest = distance
		if not best.is_empty():
			break
	if best.is_empty():
		return
	grip_age = 0.0
	held_cube = best.collider
	grip_anchor = held_cube.to_local(best.position)
	grip_from_above = held_cube == support_body
	motion.grip_cube = held_cube
	motion.grip_anchor = grip_anchor
	grip_normal = held_cube.global_basis.inverse() * best.normal
	grip_clearance = (motion.hand_radius("Left") + motion.hand_radius("Right")) * 0.5
	motion.grip_normal = grip_normal
	# Keep the visual contact offsets fixed in surface space while the body turns.
	var lateral := held_cube.global_basis.inverse() * Vector3.BACK
	motion.grip_lateral = (lateral - grip_normal * lateral.dot(grip_normal)).normalized()
	angular_damp = 1.4


func is_on_floor() -> bool:
	return is_instance_valid(support_body)


func get_floor_normal() -> Vector3:
	return floor_normal


func get_platform_velocity() -> Vector3:
	return support_velocity


func get_real_velocity() -> Vector3:
	return linear_velocity


func reset() -> void:
	update_grip(null, false)
	motion.reach_cube = null
	motion.grip_blend = 0.0
	motion.reach_lowering = 0.0
	motion.reach_pitch = 0.0
	near_grip_footing = false
	set_physical_crouch(0.0)
	support_body = null
	support_velocity = Vector3.ZERO
	floor_normal = Vector3.ZERO
	direction = 0.0
	jump_requested = false
	can_cut_jump = false
	transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.02, 0))
	grip_launch = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	reset_physics_interpolation()
