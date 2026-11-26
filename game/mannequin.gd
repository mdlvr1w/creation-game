extends Node3D
## The starter figurine's visual geometry in a neutral pose.
## Local +Z is the front. The soles rest at Y = 0.

var material := StandardMaterial3D.new()


func _ready() -> void:
	material.albedo_color = Color.WHITE
	material.roughness = 0.82
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	add_ellipsoid("Head", Vector3(0.0, 2.11, 0.025), Vector3.ONE * 1.06)
	add_capsule("Neck", Vector3(0.0, 1.48, 0.0), Vector3(0.0, 1.64, 0.0), 0.147)
	add_ellipsoid("Torso", Vector3(0.0, 1.19, 0.0), Vector3(0.81, 0.78, 0.52))
	add_limbs("Left", -1.0)
	add_limbs("Right", 1.0)


func add_limbs(side: String, sign_x: float) -> void:
	var shoulder := Vector3(sign_x * 0.37, 1.40, 0.0)
	var elbow := Vector3(sign_x * 0.54, 1.12, 0.015)
	var arm_end := Vector3(sign_x * 0.61, 0.88, 0.065)
	add_capsule(side + "UpperArm", shoulder, elbow, 0.124)
	add_capsule(side + "LowerArm", elbow, arm_end, 0.109)

	var hip := Vector3(sign_x * 0.205, 0.94, 0.0)
	var knee := Vector3(sign_x * 0.24, 0.55, 0.028)
	var leg_end := Vector3(sign_x * 0.265, 0.143, 0.015)
	add_capsule(side + "UpperLeg", hip, knee, 0.161)
	add_capsule(side + "LowerLeg", knee, leg_end, 0.143)


func add_ellipsoid(part_name: String, center: Vector3, dimensions: Vector3) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	var part := add_part(part_name, mesh, center)
	part.scale = dimensions


func add_capsule(part_name: String, start: Vector3, end: Vector3, radius: float) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = start.distance_to(end) + 2.0 * radius
	var part := add_part(part_name, mesh, (start + end) * 0.5)
	part.quaternion = Quaternion(Vector3.UP, (end - start).normalized())


func add_part(part_name: String, mesh: PrimitiveMesh, center: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.material_override = material
	part.position = center
	add_child(part)
	return part
