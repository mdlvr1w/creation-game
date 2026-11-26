extends CharacterBody3D
## The test controller consumes movement intent. The mannequin is its visual child.

const Motion := preload("res://game/figurine_motion.gd")

const Settings := preload("res://game/movement_settings.gd")
const STICK_DEAD_ZONE := 0.18

var settings := Settings.new()
var jump_was_held := false
var jump_can_cut := false
@export var acceleration := 23.0
@export var braking := 30.0
@export var gravity := 22.0

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


static func stick_intent(axis: float) -> float:
	return signf(axis) * clampf(inverse_lerp(STICK_DEAD_ZONE, 1.0, absf(axis)), 0.0, 1.0)


func step(delta: float, direction: float, jump_held: bool, jump_pressed := false) -> void:
	var grounded := is_on_floor()
	var tuning := settings.values
	var target := 0.0
	if not is_zero_approx(direction):
		target = signf(direction) * lerpf(tuning.min_speed, tuning.max_speed, absf(direction))
	var rate := braking if is_zero_approx(direction) else acceleration
	velocity.x = move_toward(velocity.x, target, rate * delta)
	if grounded:
		jump_can_cut = false
		if jump_pressed or (jump_held and not jump_was_held):
			velocity.y = tuning.max_jump if jump_held else tuning.min_jump
			jump_can_cut = jump_held
	else:
		velocity.y -= gravity * delta
		if jump_can_cut and not jump_held:
			velocity.y = minf(velocity.y, tuning.min_jump)
			jump_can_cut = false
	jump_was_held = jump_held
	move_and_slide()
	motion.animate(delta, velocity, is_on_floor(), tuning.max_speed, tuning.lean_degrees)


func reset() -> void:
	position = Vector3(0, 0.02, 0)
	velocity = Vector3.ZERO
	jump_can_cut = false
