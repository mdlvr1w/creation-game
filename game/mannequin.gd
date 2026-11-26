extends Node3D
## The starter figurine's visual geometry in a neutral pose.
## Local +Z is the front. Limb lengths are measured between joint centers.

const MIN_FACTOR := 0.55
const MAX_FACTOR := 1.65
const MAX_OFFSET := 0.35
const DEFAULT_FACTORS := Vector4(1, 1, 1, 0)
const TORSO_CENTER := Vector3(0, 1.19, 0)
const TORSO_SIZE := Vector3(0.81, 0.78, 0.52)
const FACTOR_KEYS := ["size", "length", "thickness", "height_offset"]

var limb_factors: Dictionary[StringName, Vector4] = {}
var limb_meshes: Dictionary[StringName, MeshInstance3D] = {}
var torso_factors := DEFAULT_FACTORS
var torso: MeshInstance3D
var head: MeshInstance3D
var neck: MeshInstance3D
var floor_height := 0.0
var material := StandardMaterial3D.new()


func _ready() -> void:
	material.albedo_color = Color.WHITE
	material.roughness = 0.82
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	head = add_ellipsoid("Head", Vector3(0.0, 2.11, 0.025), Vector3.ONE * 1.06)
	neck = add_capsule("Neck", Vector3(0.0, 1.48, 0.0), Vector3(0.0, 1.64, 0.0), 0.147)
	torso = add_ellipsoid("Torso", TORSO_CENTER, TORSO_SIZE)
	update_limbs()


func update_limbs() -> void:
	var width := torso_factors.x * torso_factors.z
	var height := torso_factors.x * torso_factors.y
	torso.scale = TORSO_SIZE * Vector3(width, height, width)
	var top_change := (torso.scale.y - TORSO_SIZE.y) * 0.5
	head.position.y = 2.11 + top_change
	neck.position.y = 1.56 + top_change
	floor_height = INF
	update_side("Left", -1.0)
	update_side("Right", 1.0)


func update_side(side: String, sign_x: float) -> void:
	var shoulder := Vector3(sign_x * 0.37, 1.40, 0.0)
	var elbow := Vector3(sign_x * 0.54, 1.12, 0.015)
	var arm_end := Vector3(sign_x * 0.61, 0.88, 0.065)
	var elbow_joint := update_limb(side + "UpperArm", torso_attachment(shoulder, side + "UpperArm"),
		elbow - shoulder, 0.124, side + "LowerArm")
	update_limb(side + "LowerArm", elbow_joint, arm_end - elbow, 0.109)

	var hip := Vector3(sign_x * 0.205, 0.94, 0.0)
	var knee := Vector3(sign_x * 0.24, 0.55, 0.028)
	var leg_end := Vector3(sign_x * 0.265, 0.143, 0.015)
	var knee_joint := update_limb(side + "UpperLeg", torso_attachment(hip, side + "UpperLeg"),
		knee - hip, 0.161, side + "LowerLeg")
	update_limb(side + "LowerLeg", knee_joint, leg_end - knee, 0.143)


func torso_attachment(rest: Vector3, limb_name: StringName) -> Vector3:
	var normalized := (rest - TORSO_CENTER) / TORSO_SIZE
	var factors: Vector4 = limb_factors.get(limb_name, DEFAULT_FACTORS)
	normalized.y += factors.w * 0.45
	# Follow the torso's contour to keep the shoulder or hip attached.
	var rest_y := (rest.y - TORSO_CENTER.y) / TORSO_SIZE.y
	var reach := absf(normalized.x) / sqrt(0.25 - rest_y * rest_y)
	normalized.x = signf(normalized.x) * minf(reach, 0.99) * sqrt(0.25 - normalized.y * normalized.y)
	return TORSO_CENTER + normalized * torso.scale


func update_limb(limb_name: StringName, start: Vector3, rest_offset: Vector3,
		rest_radius: float, lower_limb: StringName = &"") -> Vector3:
	var factors: Vector4 = limb_factors.get(limb_name, DEFAULT_FACTORS)
	limb_factors[limb_name] = factors
	var offset := rest_offset * factors.x * factors.y
	if lower_limb != &"":
		var lower_factors: Vector4 = limb_factors.get(lower_limb, DEFAULT_FACTORS)
		offset.y += offset.length() * lower_factors.w
	var end := start + offset
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
		values[String(limb)] = encode_factors(limb_factors[limb])
	return JSON.stringify({"version": 2, "torso": encode_factors(torso_factors), "limbs": values}, "\t")


func encode_factors(factors: Vector4) -> Dictionary:
	var values := {}
	for index in FACTOR_KEYS.size():
		values[FACTOR_KEYS[index]] = snappedf(factors[index], 0.01)
	return values


func decode_proportions(contents: String) -> bool:
	var decoded: Variant = JSON.parse_string(contents)
	if not decoded is Dictionary or (decoded.get("version") != 1 and decoded.get("version") != 2):
		return false
	var legacy: bool = decoded.version == 1
	var values: Variant = decoded.get("limbs")
	if not values is Dictionary or values.size() != limb_factors.size():
		return false
	var restored: Dictionary[StringName, Vector4] = {}
	for limb in limb_factors:
		var validated := decode_factors(values.get(String(limb)), legacy)
		if not validated.is_finite():
			return false
		restored[limb] = validated
	var restored_torso := DEFAULT_FACTORS if legacy else decode_factors(decoded.get("torso"), false)
	if not restored_torso.is_finite() or not is_zero_approx(restored_torso.w):
		return false
	limb_factors = restored
	torso_factors = restored_torso
	update_limbs()
	return true


func decode_factors(values: Variant, legacy: bool) -> Vector4:
	var count := 3 if legacy else FACTOR_KEYS.size()
	if not values is Dictionary or values.size() != count:
		return Vector4.INF
	var factors := DEFAULT_FACTORS
	for index in count:
		var value: Variant = values.get(FACTOR_KEYS[index])
		var minimum := -MAX_OFFSET if index == 3 else MIN_FACTOR
		var maximum := MAX_OFFSET if index == 3 else MAX_FACTOR
		if not value is float or not is_finite(value) or value < minimum or value > maximum:
			return Vector4.INF
		factors[index] = value
	return factors


func add_ellipsoid(part_name: String, center: Vector3, dimensions: Vector3) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	var part := add_part(part_name, mesh, center)
	part.scale = dimensions
	return part


func add_capsule(part_name: String, start: Vector3, end: Vector3, radius: float) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = start.distance_to(end) + 2.0 * radius
	var part := add_part(part_name, mesh, (start + end) * 0.5)
	part.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	return part


func add_part(part_name: String, mesh: PrimitiveMesh, center: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.material_override = material
	part.position = center
	add_child(part)
	return part
