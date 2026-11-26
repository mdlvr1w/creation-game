extends CharacterBody3D
## The test controller consumes movement intent. The mannequin is its visual child.

const Motion := preload("res://game/figurine_motion.gd")
const GrabCube := preload("res://game/grabbable_cube.gd")

const Settings := preload("res://game/movement_settings.gd")
const STICK_DEAD_ZONE := 0.18
const GRAB_GAP := 0.59
const GRAB_RANGE := 0.83
const SIDE_GRIP_HEIGHT := 1.205
const GRIP_FACE_MARGIN := 0.145
const PLAYER_GRIP_MASS := 15.0

var held_cube: GrabCube
var grip_side := 0.0
var grip_anchor := Vector3.ZERO
var grip_height := 0.0
var grip_horizontal_offset := 0.0
var grip_from_above := false

var settings := Settings.new()
var jump_was_held := false
var jump_can_cut := false
@export var acceleration := 23.0
@export var braking := 30.0

var motion := Motion.new()


func _ready() -> void:
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 2.45
	collider.shape = capsule
	collider.position.y = capsule.height * 0.5
	add_child(collider)
	add_child(motion)
	floor_snap_length = 0.15
	collision_mask = 3
	platform_floor_layers = 1


static func stick_intent(axis: float) -> float:
	return signf(axis) * clampf(inverse_lerp(STICK_DEAD_ZONE, 1.0, absf(axis)), 0.0, 1.0)


func update_grip(cube: GrabCube, grab_held: bool) -> void:
	if not grab_held:
		release_grip()
		return
	if held_cube != null:
		return

	if is_on_floor() and try_top_grip(cube):
		return

	var separation := cube.global_position.x - global_position.x
	if absf(separation) < 0.52 or absf(separation) > GrabCube.HALF_SIZE * 1.42 + GRAB_RANGE:
		return
	var side := signf(separation)
	var local_out := cube.global_basis.inverse() * Vector3(-side, 0, 0)
	var normal := Vector3(signf(local_out.x), 0, 0) if absf(local_out.x) >= absf(local_out.y) else Vector3(0, signf(local_out.y), 0)
	var hand_level := global_position + Vector3.UP * SIDE_GRIP_HEIGHT
	var local_hand := cube.to_local(hand_level)
	var tangent := Vector3(-normal.y, normal.x, 0)
	var half := GrabCube.HALF_SIZE
	var along := clampf(local_hand.dot(tangent), -half + GRIP_FACE_MARGIN, half - GRIP_FACE_MARGIN)
	var anchor := normal * half + tangent * along
	var world_anchor := cube.to_global(anchor)
	var gap := (world_anchor.x - global_position.x) * side
	if gap < 0.25 or gap > GRAB_RANGE or absf(world_anchor.y - hand_level.y) > 0.62:
		return

	begin_grip(cube, anchor, normal, side, false)


func try_top_grip(cube: GrabCube) -> bool:
	var feet := cube.to_local(global_position)
	var up := cube.global_basis.inverse() * Vector3.UP
	var face_size := GrabCube.HALF_SIZE
	for normal in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT]:
		var up_alignment: float = normal.dot(up)
		if up_alignment < 0.55:
			continue
		var distance: float = (feet.dot(normal) - face_size) / up_alignment
		if distance < -0.12 or distance > 0.22:
			continue
		var foot_on_face := feet - up * distance
		var tangent := Vector3(-normal.y, normal.x, 0)
		var foot_along := foot_on_face.dot(tangent)
		if absf(foot_along) > face_size or absf(foot_on_face.z) > face_size:
			continue
		var facing := motion.facing
		var forward := cube.global_basis.inverse() * Vector3(facing, 0, 0)
		var margin := face_size - GRIP_FACE_MARGIN
		var along := clampf(foot_along + 0.20 * forward.dot(tangent), -margin, margin)
		begin_grip(cube, normal * face_size + tangent * along, normal, facing, true)
		return true
	return false


func begin_grip(cube: GrabCube, anchor: Vector3, normal: Vector3, side: float, from_above: bool) -> void:
	var world_offset := cube.to_global(anchor) - global_position
	held_cube = cube
	grip_side = side
	grip_anchor = anchor
	grip_height = world_offset.y
	grip_horizontal_offset = world_offset.x
	grip_from_above = from_above
	# Let the character ride the cube's moving surface while its feet still support it.
	platform_floor_layers = 3 if from_above else 1
	platform_on_leave = PLATFORM_ON_LEAVE_DO_NOTHING if from_above else PLATFORM_ON_LEAVE_ADD_VELOCITY
	motion.grip_cube = cube
	motion.grip_side = side
	motion.grip_anchor = anchor
	motion.grip_normal = normal
	motion.grip_from_above = from_above


func release_grip() -> void:
	held_cube = null
	grip_side = 0.0
	grip_from_above = false
	platform_floor_layers = 1
	platform_on_leave = PLATFORM_ON_LEAVE_ADD_VELOCITY
	motion.grip_cube = null


func step(delta: float, direction: float, jump_held: bool, jump_pressed := false) -> void:
	var grounded := is_on_floor()
	var tuning := settings.values
	var target := 0.0
	if not is_zero_approx(direction):
		target = signf(direction) * lerpf(tuning.min_speed, tuning.max_speed, absf(direction))
	if held_cube != null:
		target /= 1.0 + held_cube.mass * 0.28
		if grip_from_above:
			target = limit_top_grip_speed(target, grounded)
		elif target * grip_side < 0.0:
			# The player can pull away only as fast as the cube can follow.
			var gap := (held_cube.to_global(grip_anchor).x - global_position.x) * grip_side
			var cube_follow_speed := maxf(0.0, -held_cube.linear_velocity.x * grip_side)
			var slack := maxf(0.0, GRAB_RANGE - gap)
			target = -grip_side * minf(absf(target), cube_follow_speed + slack * 12.0)
	var coasting := is_zero_approx(direction)
	var rate := braking if coasting else acceleration
	if not grounded:
		var inertia: float = tuning.air_inertia / 100.0
		# Full inertia preserves coasting but still permits steering.
		rate *= lerpf(1.0, 0.0 if coasting else 0.15, inertia)
	velocity.x = move_toward(velocity.x, target, rate * delta)
	if grounded:
		jump_can_cut = false
		if jump_pressed or (jump_held and not jump_was_held):
			velocity.y = (tuning.max_jump if jump_held else tuning.min_jump) * jump_load()
			jump_can_cut = jump_held
	else:
		velocity.y -= tuning.gravity * delta
		if jump_can_cut and not jump_held:
			velocity.y = minf(velocity.y, tuning.min_jump * jump_load())
			jump_can_cut = false
	jump_was_held = jump_held
	if held_cube != null:
		pull_cube(target, delta, grounded)
	move_and_slide()
	if held_cube == null:
		push_colliding_cube(target, delta)
	motion.animate(delta, velocity, is_on_floor(), tuning.max_speed, tuning.lean_degrees, direction)


func limit_top_grip_speed(target: float, grounded: bool) -> float:
	var offset := held_cube.global_basis * grip_anchor
	var error := held_cube.global_position.x + offset.x - global_position.x - grip_horizontal_offset
	if absf(error) < 0.18:
		return target
	var anchor_speed := held_cube.linear_velocity.x + held_cube.angular_velocity.cross(offset).x
	var inherited := get_platform_velocity().x if grounded else 0.0
	var relative := target + inherited - anchor_speed
	if relative * error >= 0.0:
		return target
	var slack := maxf(0.0, 0.50 - absf(error))
	return anchor_speed - inherited - signf(error) * minf(absf(relative), slack * 11.0)


func jump_load() -> float:
	return 1.0 if held_cube == null else 1.0 / sqrt(1.0 + held_cube.mass * 0.23)


func pull_cube(target_speed: float, delta: float, grounded: bool) -> void:
	if grip_from_above and motion.grip_blend < 0.75:
		return
	var offset := held_cube.global_basis * grip_anchor
	var anchor := held_cube.global_position + offset
	var contact_speed := held_cube.linear_velocity + held_cube.angular_velocity.cross(offset)
	var lean_offset := clampf(sin(motion.lean) * 0.38, -0.09, 0.09)
	var horizontal_gap := grip_horizontal_offset if grip_from_above else grip_side * (GRAB_GAP + lean_offset)
	var hold_point := global_position + Vector3(horizontal_gap, grip_height, 0)
	var displacement := hold_point - anchor
	var driver_x := lerpf(velocity.x, target_speed, 0.75)
	var driver := Vector3(driver_x, velocity.y, 0)
	if grounded and grip_from_above:
		driver += get_platform_velocity()
	var horizontal_force := displacement.x * 100.0 + (driver.x - contact_speed.x) * 19.0
	var vertical_force := displacement.y * 95.0 + (driver.y - contact_speed.y) * 12.0
	var mass := held_cube.mass
	var force := Vector3(clampf(mass * horizontal_force, -150.0, 150.0),
		clampf(mass * vertical_force, -115.0, 115.0), 0)
	if force.length_squared() > 0.01:
		held_cube.apply_force(force, offset)
	# A loaded airborne grip pulls on the character as well as the cube.
	if not grounded:
		velocity.y -= force.y * delta / PLAYER_GRIP_MASS
		if grip_from_above:
			velocity.x -= force.x * delta / (PLAYER_GRIP_MASS * 0.65)


func push_colliding_cube(target: float, delta: float) -> void:
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		var body := collision.get_collider() as RigidBody3D
		if body != null and collision.get_normal().x * target < -0.1:
			body.apply_central_impulse(Vector3(target * delta * 10.5, 0, 0))
			return


func reset() -> void:
	release_grip()
	motion.grip_blend = 0.0
	motion.reach_cube = null
	position = Vector3(0, 0.02, 0)
	velocity = Vector3.ZERO
	jump_can_cut = false
	reset_physics_interpolation()
