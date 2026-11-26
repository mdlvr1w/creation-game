extends CharacterBody3D
## The test controller consumes movement intent. The mannequin is its visual child.

const Motion := preload("res://game/figurine_motion.gd")
const GrabCube := preload("res://game/grabbable_cube.gd")

const Settings := preload("res://game/movement_settings.gd")
const STICK_DEAD_ZONE := 0.18
const GRAB_GAP := 0.59
const GRAB_RANGE := 0.83

var held_cube: GrabCube
var grip_side := 0.0

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
	elif held_cube == null:
		var difference := cube.global_position - global_position
		var surface_gap := absf(difference.x) - GrabCube.HALF_SIZE
		if surface_gap <= GRAB_RANGE and absf(difference.y - GrabCube.HALF_SIZE) < 0.45:
			held_cube = cube
			grip_side = signf(difference.x)
			motion.grip_cube = cube
			motion.grip_side = grip_side


func release_grip() -> void:
	held_cube = null
	grip_side = 0.0
	motion.grip_cube = null


func step(delta: float, direction: float, jump_held: bool, jump_pressed := false) -> void:
	var grounded := is_on_floor()
	var tuning := settings.values
	var target := 0.0
	if not is_zero_approx(direction):
		target = signf(direction) * lerpf(tuning.min_speed, tuning.max_speed, absf(direction))
	if held_cube != null:
		target /= 1.0 + held_cube.mass * 0.28
		if target * grip_side < 0.0:
			# The player can pull away only as fast as the cube can follow.
			var gap := (held_cube.global_position.x - global_position.x) * grip_side - GrabCube.HALF_SIZE
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
		if held_cube == null and (jump_pressed or (jump_held and not jump_was_held)):
			velocity.y = tuning.max_jump if jump_held else tuning.min_jump
			jump_can_cut = jump_held
	else:
		velocity.y -= tuning.gravity * delta
		if jump_can_cut and not jump_held:
			velocity.y = minf(velocity.y, tuning.min_jump)
			jump_can_cut = false
	jump_was_held = jump_held
	move_and_slide()
	if held_cube != null:
		pull_cube(target)
	else:
		push_colliding_cube(target, delta)
	motion.animate(delta, velocity, is_on_floor(), tuning.max_speed, tuning.lean_degrees, direction)


func pull_cube(target_speed: float) -> void:
	var lean_offset := clampf(sin(motion.lean) * 0.38, -0.09, 0.09)
	var hold_x := global_position.x + grip_side * (GrabCube.HALF_SIZE + GRAB_GAP + lean_offset)
	var displacement := hold_x - held_cube.global_position.x
	var relative_speed := lerpf(velocity.x, target_speed, 0.75) - held_cube.linear_velocity.x
	var force := clampf(held_cube.mass * (displacement * 100.0 + relative_speed * 19.0), -150.0, 150.0)
	if absf(force) > 0.1:
		held_cube.apply_central_force(Vector3(force, 0, 0))


func push_colliding_cube(target: float, delta: float) -> void:
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		var body := collision.get_collider() as RigidBody3D
		if body != null and collision.get_normal().x * target < -0.1:
			body.apply_central_impulse(Vector3(target * delta * 9.5, 0, 0))
			return


func reset() -> void:
	release_grip()
	motion.grip_blend = 0.0
	motion.reach_cube = null
	position = Vector3(0, 0.02, 0)
	velocity = Vector3.ZERO
	jump_can_cut = false
	reset_physics_interpolation()
