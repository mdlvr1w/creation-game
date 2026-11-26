extends Node3D
## Applies a simple velocity-driven pose to the visual model. Collision is independent.

var model: Node3D
var rest: Dictionary[StringName, Transform3D] = {}
var phase := 0.0
var stride := 0.0
var air_pose := 0.0
var facing := 1.0
var lean := 0.0
var lean_axes: Array[Vector3] = []
const UPPER_BODY := [&"Torso", &"Neck", &"Head"]


func bind_model(visual: Node3D) -> void:
	model = visual
	for limb: StringName in model.limb_meshes:
		rest[limb] = model.limb_meshes[limb].transform
	for part in UPPER_BODY:
		rest[part] = model.get_node(NodePath(String(part))).transform
	for side in ["Left", "Right"]:
		var hip := StringName(side + "UpperLeg")
		var mesh: CapsuleMesh = model.limb_meshes[hip].mesh
		lean_axes.append(rest[hip].origin - rest[hip].basis.y * (mesh.height * 0.5 - mesh.radius))


func animate(delta: float, velocity: Vector3, grounded: bool, max_speed: float, max_lean: float) -> void:
	var speed := absf(velocity.x)
	var pace := clampf(speed / max_speed, 0.0, 1.0)
	stride = move_toward(stride, pace if grounded else 0.0, delta * 5.0)
	air_pose = move_toward(air_pose, 0.0 if grounded else 1.0, delta * 6.0)
	if grounded:
		phase = fposmod(phase + speed * delta * 2.2, TAU)
	if speed > 0.12:
		facing = signf(velocity.x)
	var turn := facing * lerpf(0.22, 1.05, maxf(pace, air_pose * 0.65))
	rotation.y = lerp_angle(rotation.y, turn, 1.0 - exp(-delta * 13.0))

	var target_lean := deg_to_rad(max_lean) * pow(pace, 0.72) if grounded else 0.0
	lean = lerpf(lean, target_lean, 1.0 - exp(-delta * 10.0))
	var body_lean := rotation_about((lean_axes[0] + lean_axes[1]) * 0.5, lean)
	for part in UPPER_BODY:
		model.get_node(NodePath(String(part))).transform = body_lean * rest[part]

	var swing := sin(phase) * stride
	for side in ["Left", "Right"]:
		var cycle := swing if side == "Left" else -swing
		var tuck := clampf(0.18 + velocity.y * 0.02, 0.08, 0.32) * air_pose
		pose_pair(side + "UpperLeg", side + "LowerLeg", cycle * 0.48 - tuck,
			maxf(0.0, cycle) * 0.5 + tuck * 1.5)
		pose_pair(side + "UpperArm", side + "LowerArm", -cycle * 0.40 - air_pose * 0.40,
			-0.12 * stride - air_pose * 0.22, body_lean)


func pose_pair(upper_name: StringName, lower_name: StringName, angle: float, bend: float, body_pose := Transform3D.IDENTITY) -> void:
	var upper: MeshInstance3D = model.limb_meshes[upper_name]
	var lower: MeshInstance3D = model.limb_meshes[lower_name]
	var upper_rest := rest[upper_name]
	var lower_rest := rest[lower_name]
	var mesh := upper.mesh as CapsuleMesh
	var half_span := (mesh.height - mesh.radius * 2.0) * 0.5
	var attachment := upper_rest.origin - upper_rest.basis.y * half_span
	var joint := upper_rest.origin + upper_rest.basis.y * half_span
	var swing := body_pose * rotation_about(attachment, angle)
	upper.transform = swing * upper_rest
	lower.transform = swing * rotation_about(joint, bend) * lower_rest


func rotation_about(pivot: Vector3, angle: float) -> Transform3D:
	var turn := Basis(Vector3.RIGHT, angle)
	return Transform3D(turn, pivot - turn * pivot)
