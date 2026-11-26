extends CharacterBody3D
## The test controller consumes movement intent. The mannequin is its visual child.

const Motion := preload("res://game/figurine_motion.gd")

@export var speed := 5.5
@export var jump_speed := 7.5
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


func step(delta: float, direction: float, jump: bool) -> void:
	var grounded := is_on_floor()
	var rate := braking if is_zero_approx(direction) else acceleration
	velocity.x = move_toward(velocity.x, direction * speed, rate * delta)
	if grounded and jump:
		velocity.y = jump_speed
	elif not grounded:
		velocity.y -= gravity * delta
	move_and_slide()
	motion.animate(delta, velocity, is_on_floor(), speed)


func reset() -> void:
	position = Vector3(0, 0.02, 0)
	velocity = Vector3.ZERO
