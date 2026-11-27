extends Node3D
## The starter figurine's visual geometry in a neutral pose.
## Local +Z is the front. Limb lengths are measured between joint centers.

const WORKING_PROPORTIONS := "res://game/default_proportions.json"
const LOCAL_PROPORTIONS := "user://mannequin-proportions.json"
const MIN_FACTOR := 0.55
const MAX_FACTOR := 1.65
const MAX_OFFSET := 0.35
const DEFAULT_FACTORS := Vector4(1, 1, 1, 0)
const TORSO_CENTER := Vector3(0, 1.19, 0)
const TORSO_SIZE := Vector3(0.81, 0.78, 0.52)
const FACTOR_KEYS := ["size", "length", "thickness", "height_offset"]

var pickable := true
var limb_factors: Dictionary[StringName, Vector4] = {}
var limb_meshes: Dictionary[StringName, MeshInstance3D] = {}
var torso_factors := DEFAULT_FACTORS
var head_factors := DEFAULT_FACTORS
var neck_factors := DEFAULT_FACTORS
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
	neck = add_pickable_capsule(&"Neck")
	torso = add_ellipsoid("Torso", TORSO_CENTER, TORSO_SIZE)
	update_proportions()


func update_proportions() -> void:
	var width := torso_factors.x * torso_factors.z
	var height := torso_factors.x * torso_factors.y
	torso.scale = TORSO_SIZE * Vector3(width, height, width)
	var neck_span := 0.16 * neck_factors.x * neck_factors.y
	var neck_base := TORSO_CENTER + Vector3.UP * (torso.scale.y * 0.5 - minf(0.10, neck_span * 0.625))
	var neck_top := neck_base + Vector3.UP * neck_span
	update_capsule(neck, neck_base, neck_top, 0.147 * neck_factors.x * neck_factors.z)
	head.scale = 1.06 * head_factors.x * Vector3(head_factors.z, head_factors.y, head_factors.z)
	head.position.y = neck_top.y - minf(0.06, neck_span * 0.375) + head.scale.y * 0.5
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
	var part := limb_meshes.get(limb_name) as MeshInstance3D
	if part == null:
		part = add_pickable_capsule(limb_name)
		limb_meshes[limb_name] = part
	update_capsule(part, start, end, radius)
	floor_height = minf(floor_height, minf(start.y, end.y) - radius)
	return end


func add_pickable_capsule(part_name: StringName) -> MeshInstance3D:
	var part := add_part(part_name, CapsuleMesh.new(), Vector3.ZERO)
	if not pickable:
		return part
	var target := Area3D.new()
	target.name = "PickTarget"
	target.collision_mask = 0
	target.monitoring = false
	target.monitorable = false
	part.add_child(target)
	var collision := CollisionShape3D.new()
	collision.name = "Capsule"
	collision.shape = CapsuleShape3D.new()
	target.add_child(collision)
	return part


func update_capsule(part: MeshInstance3D, start: Vector3, end: Vector3, radius: float) -> void:
	var height := start.distance_to(end) + 2.0 * radius
	var mesh := part.mesh as CapsuleMesh
	mesh.radius = radius
	mesh.height = height
	part.position = (start + end) * 0.5
	part.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	if pickable:
		var shape := part.get_node("PickTarget/Capsule").shape as CapsuleShape3D
		shape.radius = radius
		shape.height = height


func encode_proportions() -> String:
	var values := {}
	for limb in limb_factors:
		values[String(limb)] = encode_factors(limb_factors[limb])
	return JSON.stringify({
		"version": 3, "limbs": values, "torso": encode_factors(torso_factors),
		"head": encode_factors(head_factors), "neck": encode_factors(neck_factors),
	}, "\t")


func encode_factors(factors: Vector4) -> Dictionary:
	var values := {}
	for index in FACTOR_KEYS.size():
		values[FACTOR_KEYS[index]] = snappedf(factors[index], 0.01)
	return values


func decode_proportions(contents: String) -> bool:
	var decoded: Variant = JSON.parse_string(contents)
	if not decoded is Dictionary:
		return false
	var version: Variant = decoded.get("version")
	if version != 1 and version != 2 and version != 3:
		return false
	var legacy: bool = version == 1
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
	var restored_head := decode_factors(decoded.get("head"), false) if version == 3 else DEFAULT_FACTORS
	var restored_neck := decode_factors(decoded.get("neck"), false) if version == 3 else DEFAULT_FACTORS
	for factors: Vector4 in [restored_torso, restored_head, restored_neck]:
		if not factors.is_finite() or not is_zero_approx(factors.w):
			return false
	limb_factors = restored
	torso_factors = restored_torso
	head_factors = restored_head
	neck_factors = restored_neck
	update_proportions()
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


func add_part(part_name: String, mesh: PrimitiveMesh, center: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.material_override = material
	part.position = center
	add_child(part)
	return part
