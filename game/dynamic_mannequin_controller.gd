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
const FOOT_HOLD_RESPONSE := 0.25
const TAKEOFF_TIME := 0.07
const TAKEOFF_EXTENSION := 0.28

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
var jump_surface: RigidBody3D
var jump_contact := Vector3.ZERO
var jump_start_height := 0.0
var jump_foot_height := 0.0
var jump_foot_speed := 0.0
var jump_speed := 0.0
var jump_age := 0.0
var jump_spent := 0.0
var floor_normal := Vector3.ZERO
var support_velocity := Vector3.ZERO
var support_body: PhysicsBody3D
var support_position := Vector3.ZERO
var support_travel_speed := 0.0
var support_local_position := Vector3.ZERO
var support_creep := 0.0

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
	var grounded := is_on_floor()
	var relative_velocity := linear_velocity - support_velocity if grounded else linear_velocity
	motion.animate(delta, relative_velocity, grounded, settings.values.max_speed, settings.values.lean_degrees,
		direction, target_speed(), support_travel_speed)


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
	var started_jump := jump_requested and jump_surface == null and support_body != null and takeoff(state)
	if started_jump:
		can_cut_jump = jump_held
	else:
		continue_takeoff(state)
		if can_cut_jump and not jump_held and state.linear_velocity.y > settings.values.min_jump:
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
	var previous_support := support_body
	support_body = null
	floor_normal = Vector3.ZERO
	support_velocity = Vector3.ZERO
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

	support_travel_speed = 0.0
	if support_body != previous_support:
		support_creep = 0.0
	if is_on_floor():
		var axis := support_tangent()
		var origin := state.transform.origin
		if support_body == previous_support:
			# Measure travel after the contact solver has finished moving both bodies.
			support_travel_speed = (origin - support_body.to_global(support_local_position)).dot(axis) / state.step
		else:
			support_travel_speed = (state.linear_velocity - support_velocity).dot(axis)
		support_local_position = support_body.to_local(origin)


func target_speed() -> float:
	return signf(direction) * lerpf(settings.values.min_speed, settings.values.max_speed, absf(direction))


func support_tangent() -> Vector3:
	return Vector3(floor_normal.y, -floor_normal.x, 0.0).normalized()


func apply_drive(state: PhysicsDirectBodyState3D) -> void:
	last_drive_speed = target_speed()
	var grounded := is_on_floor()
	if not grounded and (held_cube != null or (grip_launch and is_zero_approx(direction))):
		last_drive_impulse = Vector3.ZERO
		return
	var axis := support_tangent() if grounded else Vector3.RIGHT
	var drive_budget := drive_strength
	var response := braking_response if is_zero_approx(direction) else drive_response
	if not grounded:
		var drag_floor := 0.0 if is_zero_approx(direction) else 0.15
		drive_budget *= lerpf(1.0, drag_floor, settings.values.air_inertia / 100.0)

	var relative_speed := support_travel_speed if grounded else state.linear_velocity.x
	var speed_error := last_drive_speed - relative_speed
	if grounded and is_zero_approx(direction):
		# Remove steady drift against the support without storing an unlimited correction.
		var hold_weight := 1.0 - smoothstep(0.20, 0.70, absf(relative_speed))
		var creep_limit := drive_budget * response * FOOT_HOLD_RESPONSE / mass
		support_creep = clampf((support_creep + relative_speed * state.step) * hold_weight, -creep_limit, creep_limit)
		speed_error -= support_creep / FOOT_HOLD_RESPONSE
	else:
		support_creep = 0.0
	var force := speed_error * mass / response
	if grounded:
		# A very light support can change relative speed sharply under a single drive impulse.
		var inverse_mass := state.inverse_mass + support_inverse_mass(axis)
		var correction_limit := absf(speed_error) / (inverse_mass * state.step)
		force = clampf(force, -correction_limit, correction_limit)
		# Support the character against its weight along the contact, within the walking force budget.
		force -= state.total_gravity.dot(axis) * mass
	var impulse := clampf(force, -drive_budget, drive_budget) * state.step
	last_drive_impulse = axis * impulse
	state.apply_central_impulse(last_drive_impulse)
	# The same traction acts back on a finite-mass surface at the foot contact.
	if support_body is RigidBody3D:
		support_body.apply_impulse(-last_drive_impulse, support_position - support_body.global_position)


func support_inverse_mass(axis: Vector3) -> float:
	var body := support_body as RigidBody3D
	if body == null or body.freeze:
		return 0.0
	var linear_axis := Vector3(0.0 if body.axis_lock_linear_x else axis.x,
		0.0 if body.axis_lock_linear_y else axis.y, 0.0)
	var inverse_mass := linear_axis.length_squared() / body.mass
	if not body.lock_rotation and not body.axis_lock_angular_z:
		var support_state := PhysicsServer3D.body_get_direct_state(body.get_rid())
		if support_state != null:
			var center := support_state.transform * support_state.center_of_mass_local
			var lever := (support_position - center).cross(axis).z
			inverse_mass += lever * lever * support_state.inverse_inertia_tensor.z.z
	return inverse_mass


func takeoff(state: PhysicsDirectBodyState3D) -> bool:
	var surface := support_body as RigidBody3D
	var foot_speed := support_velocity.y
	var moving_surface := surface != null and not surface.freeze
	if moving_surface:
		foot_speed = surface_speed_at(surface, support_position)
	var relative_speed := state.linear_velocity.y - foot_speed
	if relative_speed >= 0.8:
		return false

	var launch_speed: float = settings.values.max_jump if jump_held else settings.values.min_jump
	var speed_change := maxf(0.0, launch_speed - relative_speed)
	var inverse_mass := state.inverse_mass + support_inverse_mass(Vector3.UP)
	var impulse := speed_change / inverse_mass
	# Start with a pulse safe for a freely recoiling surface, then read its solved response.
	# When the same surface is in the hands, the tether already couples the two bodies.
	if moving_surface and surface != held_cube:
		jump_surface = surface
		jump_contact = surface.to_local(support_position)
		jump_start_height = state.transform.origin.y
		jump_foot_height = support_position.y
		jump_foot_speed = foot_speed
		jump_speed = launch_speed
		jump_age = 0.0
		impulse = minf(impulse, launch_speed * mass * 0.5)
		jump_spent = impulse
	push_off(state, surface, support_position, impulse)
	return true


func continue_takeoff(state: PhysicsDirectBodyState3D) -> void:
	if not is_instance_valid(jump_surface):
		jump_surface = null
		return
	jump_age += state.step
	var contact := jump_surface.to_global(jump_contact)
	var rise := state.transform.origin.y - jump_start_height
	if jump_age > TAKEOFF_TIME or rise - (contact.y - jump_foot_height) > TAKEOFF_EXTENSION:
		jump_surface = null
		return
	# Foot displacement includes the solver's response through contacts and joints below it.
	var settled_speed := (contact.y - jump_foot_height) / jump_age
	var measured_speed := minf(settled_speed, surface_speed_at(jump_surface, contact))
	var recoil := maxf(0.0, jump_foot_speed - measured_speed - 0.12)
	if not jump_held:
		jump_speed = minf(jump_speed, settings.values.min_jump)
	var height_from_carrier := maxf(0.0, rise - jump_foot_speed * jump_age)
	var remaining_speed := sqrt(maxf(0.0, jump_speed * jump_speed + 2.0 * state.total_gravity.y * height_from_carrier))
	var speed_change := remaining_speed + jump_foot_speed - recoil - state.linear_velocity.y
	if speed_change <= 0.0:
		jump_surface = null
		return
	var inverse_mass := state.inverse_mass + recoil / maxf(jump_spent, 0.01)
	var impulse := minf(speed_change / inverse_mass, jump_speed * mass * 0.5)
	push_off(state, jump_surface, contact, impulse)
	jump_spent += impulse


func surface_speed_at(surface: RigidBody3D, point: Vector3) -> float:
	var direct := PhysicsServer3D.body_get_direct_state(surface.get_rid())
	var center := surface.global_position if direct == null else direct.transform * direct.center_of_mass_local
	return (surface.linear_velocity + surface.angular_velocity.cross(point - center)).y


func push_off(state: PhysicsDirectBodyState3D, surface: RigidBody3D, contact: Vector3, amount: float) -> void:
	var impulse := Vector3.UP * amount
	last_takeoff_impulse = impulse
	state.apply_central_impulse(impulse)
	if surface != null:
		surface.apply_impulse(-impulse, contact - surface.global_position)


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
	support_travel_speed = 0.0
	support_creep = 0.0
	floor_normal = Vector3.ZERO
	direction = 0.0
	jump_requested = false
	can_cut_jump = false
	jump_surface = null
	transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.02, 0))
	grip_launch = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	reset_physics_interpolation()
