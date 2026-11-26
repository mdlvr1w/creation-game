extends Node3D
## The starter figurine's visual geometry in a neutral pose.
## Local +Z is the front. Limb lengths are measured between joint centers.

const MIN_FACTOR := 0.55
const MAX_FACTOR := 1.65
const DEFAULT_FACTORS := Vector3.ONE
const FACTOR_KEYS := ["size", "length", "thickness"]

var limb_factors: Dictionary[StringName, Vector3] = {}
var limb_meshes: Dictionary[StringName, MeshInstance3D] = {}
var floor_height := 0.0
var material := StandardMaterial3D.new()


func _ready() -> void:
	material.albedo_color = Color.WHITE
	material.roughness = 0.82
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	add_ellipsoid("Head", Vector3(0.0, 2.11, 0.025), Vector3.ONE * 1.06)
	add_capsule("Neck", Vector3(0.0, 1.48, 0.0), Vector3(0.0, 1.64, 0.0), 0.147)
	add_ellipsoid("Torso", Vector3(0.0, 1.19, 0.0), Vector3(0.81, 0.78, 0.52))
	update_limbs()


func update_limbs() -> void:
	floor_height = INF
	update_side("Left", -1.0)
	update_side("Right", 1.0)


func update_side(side: String, sign_x: float) -> void:
	var shoulder := Vector3(sign_x * 0.37, 1.40, 0.0)
	var elbow := Vector3(sign_x * 0.54, 1.12, 0.015)
	var arm_end := Vector3(sign_x * 0.61, 0.88, 0.065)
	var elbow_joint := update_limb(side + "UpperArm", shoulder, elbow - shoulder, 0.124)
	update_limb(side + "LowerArm", elbow_joint, arm_end - elbow, 0.109)

	var hip := Vector3(sign_x * 0.205, 0.94, 0.0)
	var knee := Vector3(sign_x * 0.24, 0.55, 0.028)
	var leg_end := Vector3(sign_x * 0.265, 0.143, 0.015)
	var knee_joint := update_limb(side + "UpperLeg", hip, knee - hip, 0.161)
	update_limb(side + "LowerLeg", knee_joint, leg_end - knee, 0.143)


func update_limb(limb_name: StringName, start: Vector3, rest_offset: Vector3, rest_radius: float) -> Vector3:
	var factors := limb_factors.get(limb_name, DEFAULT_FACTORS) as Vector3
	limb_factors[limb_name] = factors
	var end := start + rest_offset * factors.x * factors.y
	var radius := rest_radius * factors.x * factors.z
	var length := start.distance_to(end)
	var height := length + 2.0 * radius
	var center := (start + end) * 0.5
	var orientation := Quaternion(Vector3.UP, (end - start).normalized())

	var part := limb_meshes.get(limb_name) as MeshInstance3D
	if part == null:
		part = add_part(limb_name, CapsuleMesh.new(), center)
		limb_meshes[limb_name] = part
		var target := Area3D.new()
		target.name = "PickTarget"
		target.collision_layer = 1
		target.collision_mask = 0
		target.monitoring = false
		target.monitorable = false
		part.add_child(target)
		var collision := CollisionShape3D.new()
		collision.name = "Capsule"
		collision.shape = CapsuleShape3D.new()
		target.add_child(collision)
	var mesh := part.mesh as CapsuleMesh
	mesh.radius = radius
	mesh.height = height
	part.position = center
	part.quaternion = orientation
	var collision := part.get_node("PickTarget/Capsule") as CollisionShape3D
	var shape := collision.shape as CapsuleShape3D
	shape.radius = radius
	shape.height = height
	floor_height = minf(floor_height, minf(start.y, end.y) - radius)
	return end


func encode_proportions() -> String:
	var values := {}
	for limb in limb_factors:
		var factors := limb_factors[limb]
		values[String(limb)] = {"size": factors.x, "length": factors.y, "thickness": factors.z}
	return JSON.stringify({"version": 1, "limbs": values}, "\t")


func decode_proportions(contents: String) -> bool:
	var decoded: Variant = JSON.parse_string(contents)
	if not decoded is Dictionary or decoded.get("version") != 1:
		return false
	var values: Variant = decoded.get("limbs")
	if not values is Dictionary or values.size() != limb_factors.size():
		return false
	var restored: Dictionary[StringName, Vector3] = {}
	for limb in limb_factors:
		var factors: Variant = values.get(String(limb))
		if not factors is Dictionary or factors.size() != FACTOR_KEYS.size():
			return false
		var validated := Vector3.ZERO
		for index in FACTOR_KEYS.size():
			var factor: Variant = factors.get(FACTOR_KEYS[index])
			if not factor is float or not is_finite(factor) or factor < MIN_FACTOR or factor > MAX_FACTOR:
				return false
			validated[index] = factor
		restored[limb] = validated
	limb_factors = restored
	update_limbs()
	return true


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
