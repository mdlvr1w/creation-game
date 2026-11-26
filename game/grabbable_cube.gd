extends RigidBody3D

const HALF_SIZE := 0.675

var start := Vector3(-3.7, HALF_SIZE + 0.02, 0)


func _ready() -> void:
	mass = 3.0
	axis_lock_linear_z = true
	lock_rotation = true
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.34
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * HALF_SIZE * 2.0
	collider.shape = shape
	add_child(collider)

	var mesh := BoxMesh.new()
	mesh.size = shape.size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#c88549")
	material.roughness = 0.85
	visual.material_override = material
	add_child(visual)
	reset()


func reset() -> void:
	global_position = start
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false
	reset_physics_interpolation()
