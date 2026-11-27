extends "res://game/grabbable_cube.gd"
## A driven test fixture with a fixed axle and a grabbable rim.

const RADIUS := 1.5
const DEPTH := 0.60
var spin_speed := 0.82


func _ready() -> void:
	start = Vector3(2.0, 4.05, 0.0)
	mass = 24.0
	collision_layer = 2
	collision_mask = 3
	axis_lock_linear_x = true
	axis_lock_linear_y = true
	axis_lock_linear_z = true
	axis_lock_angular_x = true
	axis_lock_angular_y = true
	can_sleep = false
	continuous_cd = true

	var shape := CylinderShape3D.new()
	shape.radius = RADIUS
	shape.height = DEPTH
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.rotation.x = PI * 0.5
	add_child(collider)

	var wheel_mesh := CylinderMesh.new()
	wheel_mesh.top_radius = RADIUS
	wheel_mesh.bottom_radius = RADIUS
	wheel_mesh.height = DEPTH
	var wheel_visual := MeshInstance3D.new()
	wheel_visual.mesh = wheel_mesh
	wheel_visual.rotation.x = PI * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#387986")
	wheel_visual.material_override = material
	add_child(wheel_visual)

	for index in 6:
		var angle := index * TAU / 6.0
		var spoke := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.22, 0.11, 0.055)
		spoke.mesh = mesh
		spoke.rotation.z = angle
		spoke.position = Vector3(cos(angle) * 0.72, sin(angle) * 0.72, DEPTH * 0.5 + 0.02)
		var paint := StandardMaterial3D.new()
		paint.albedo_color = Color("#ffd37a") if index == 0 else Color("#a8d4d3")
		spoke.material_override = paint
		add_child(spoke)
	reset()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	state.angular_velocity = Vector3(0.0, 0.0, spin_speed)
