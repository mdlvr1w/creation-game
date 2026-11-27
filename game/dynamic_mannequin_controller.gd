extends RigidBody3D
## The experimental body drives toward an intention with finite strength.
## Contacts and the temporary two-body grip determine the resulting motion.

const Motion := preload("res://game/figurine_motion.gd")
const Settings := preload("res://game/movement_settings.gd")
const GrabCube := preload("res://game/grabbable_cube.gd")

const REACH := 0.85
const GRIP_FREQUENCY := 13.0
const GRIP_STRENGTH := 185.0

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

var held_cube: GrabCube
var grip_anchor := Vector3.ZERO
var player_anchor := Vector3.ZERO
var grip_from_above := false
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
	lock_rotation = true
	axis_lock_linear_z = true
	can_sleep = false
	continuous_cd = true
	collision_mask = 3
	max_contacts_reported = 12
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0

	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.12
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 2.45
	collider.shape = capsule
	collider.position.y = capsule.height * 0.5
	add_child(collider)
	add_child(motion)


func step(delta: float, move_intent: float, jump_down: bool, jump_pressed := false) -> void:
	direction = move_intent
	jump_requested = jump_requested or jump_pressed or (jump_down and not jump_was_held)
	jump_was_held = jump_down
	jump_held = jump_down
	var world_gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	gravity_scale = settings.values.gravity / world_gravity
	var visual_velocity := linear_velocity
	if is_on_floor():
		visual_velocity.x -= support_velocity.x
	motion.animate(delta, visual_velocity, is_on_floor(), settings.values.max_speed, settings.values.lean_degrees, direction)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	read_support(state)
	last_simulated_input = Vector2(direction, float(jump_requested))
	apply_drive(state)
	last_takeoff_impulse = Vector3.ZERO
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
	last_shared_support = held_cube != null and held_cube == support_body
	if held_cube != null:
		apply_grip(state)


func read_support(state: PhysicsDirectBodyState3D) -> void:
	support_body = null
	floor_normal = Vector3.ZERO
	support_velocity = Vector3.ZERO
	support_relative_y = 0.0
	var best_normal := 0.70
	for index in state.get_contact_count():
		var normal := state.get_contact_local_normal(index)
		if normal.y <= best_normal:
			continue
		var local_point := state.get_contact_local_position(index)
		if local_point.y > state.transform.origin.y + 0.4:
			continue
		var collider := state.get_contact_collider_object(index) as PhysicsBody3D
		if collider == null:
			continue
		best_normal = normal.y
		support_body = collider
		floor_normal = normal
		support_position = state.get_contact_collider_position(index)
		support_velocity = state.get_contact_collider_velocity_at_position(index)
		support_relative_y = state.linear_velocity.y - support_velocity.y


func apply_drive(state: PhysicsDirectBodyState3D) -> void:
	var tuning := settings.values
	last_drive_speed = signf(direction) * lerpf(tuning.min_speed, tuning.max_speed, absf(direction))
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


func apply_grip(state: PhysicsDirectBodyState3D) -> void:
	var cube_offset := held_cube.global_basis * grip_anchor
	var cube_point := held_cube.global_position + cube_offset
	var cube_speed := held_cube.linear_velocity + held_cube.angular_velocity.cross(cube_offset)
	var gap := state.transform.origin + player_anchor - cube_point
	var drift := state.linear_velocity - cube_speed
	# Equal and opposite impulses at a persistent surface point. Rotation stays free.
	var reduced_mass := 1.0 / (state.inverse_mass + 1.0 / held_cube.mass)
	var impulse := (gap * GRIP_FREQUENCY + drift) * reduced_mass * (1.0 - exp(-state.step * GRIP_FREQUENCY))
	impulse.z = 0.0
	impulse = impulse.limit_length(GRIP_STRENGTH * state.step)
	held_cube.apply_impulse(impulse, cube_offset)
	state.apply_central_impulse(-impulse)
	last_grip_force = impulse / state.step


func update_grip(cube: GrabCube, held: bool) -> void:
	if not held:
		held_cube = null
		grip_from_above = false
		motion.grip_cube = null
		return
	if held_cube != null:
		return
	var from_above := support_body == cube
	var height := 0.16 if from_above else 1.22
	var reach_origin := cube.to_local(global_position + Vector3.UP * height)
	var best_distance := REACH
	var best_normal := Vector3.ZERO
	var best_point := Vector3.ZERO
	var half := GrabCube.HALF_SIZE
	for normal: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.UP, Vector3.DOWN]:
		if reach_origin.dot(normal) < half - 0.15:
			continue
		var tangent := Vector3(-normal.y, normal.x, 0)
		var along := clampf(reach_origin.dot(tangent), -half + 0.13, half - 0.13)
		var point := normal * half + tangent * along
		var distance := reach_origin.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best_point = point
			best_normal = normal
	if best_normal.is_zero_approx():
		return

	held_cube = cube
	grip_anchor = best_point
	player_anchor = cube.to_global(best_point) - global_position
	grip_from_above = from_above
	var side := signf(player_anchor.x)
	if is_zero_approx(side):
		side = motion.facing
	motion.grip_cube = cube
	motion.grip_anchor = best_point
	motion.grip_normal = best_normal
	motion.grip_side = side
	motion.grip_start_yaw = motion.rotation.y
	motion.grip_lateral = Vector3.BACK * -side
	if from_above:
		var lateral := cube.global_basis.inverse() * motion.global_basis.x
		motion.grip_lateral = (lateral - best_normal * lateral.dot(best_normal)).normalized()


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
	support_body = null
	support_velocity = Vector3.ZERO
	floor_normal = Vector3.ZERO
	direction = 0.0
	jump_requested = false
	can_cut_jump = false
	position = Vector3(0, 0.02, 0)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	reset_physics_interpolation()
