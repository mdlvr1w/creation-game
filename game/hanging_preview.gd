extends Node3D

const Rig := preload("res://game/hanging_rig.gd")
const Mannequin := preload("res://game/mannequin.gd")
const Stage := preload("res://game/mannequin_stage.gd")
const Controller := preload("res://game/mannequin_controller.gd")
const Recorder := preload("res://game/playtest_recorder.gd")
const HAND_HEIGHT := 3.9
const PIVOT_HEIGHT := 5.65

var rig: Rig
var apparatus: Node3D
var support: PhysicsBody3D
var ledge: AnimatableBody3D
var articulated := false
var movable := false
var raised := false
var proportions := ""
var recorder := Recorder.new()
var status := Label.new()
var recording_status := Label.new()
var record_button: Button
var stop_button: Button


func _ready() -> void:
	var tree := get_tree()
	proportions = tree.get_meta("preview_proportions", FileAccess.get_file_as_string(Mannequin.WORKING_PROPORTIONS))
	tree.remove_meta("preview_proportions")
	add_child(Stage.new())
	add_child(recorder)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.5
	camera.position = Vector3(3.0, 4.35, 11)
	add_child(camera)
	camera.look_at(Vector3(0, 2.88, 0))
	camera.make_current()
	add_controls()
	restart()


func restart() -> void:
	if apparatus != null:
		remove_child(apparatus)
		apparatus.queue_free()
	apparatus = Node3D.new()
	add_child(apparatus)
	raised = false

	var ceiling := StaticBody3D.new()
	apparatus_add(ceiling, Vector3(0, PIVOT_HEIGHT, 0))
	box(ceiling, Vector3(2.45, 0.20, 0.95), Vector3.ZERO, Color("#3a615f"))

	if movable:
		var swing := RigidBody3D.new()
		swing.mass = 3.2
		swing.inertia = Vector3(1.5, 1.5, 1.15)
		swing.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		swing.axis_lock_linear_z = true
		swing.axis_lock_angular_x = true
		swing.axis_lock_angular_y = true
		swing.angular_damp = 0.25
		swing.linear_damp = 0.12
		swing.can_sleep = false
		support = swing
	else:
		support = StaticBody3D.new()
	apparatus_add(support, Vector3(0, HAND_HEIGHT, 0))
	var bridge_height := 0.73
	var span := PIVOT_HEIGHT - HAND_HEIGHT - bridge_height
	box(support, Vector3(1.22, 0.12, 0.55), Vector3.UP * bridge_height, Color("#c6844b"))
	box(support, Vector3(0.12, span, 0.12), Vector3.UP * (bridge_height + span * 0.5), Color("#758d8d"))
	if movable:
		var hinge := PinJoint3D.new()
		hinge.position.y = PIVOT_HEIGHT
		apparatus.add_child(hinge)
		hinge.node_a = hinge.get_path_to(ceiling)
		hinge.node_b = hinge.get_path_to(support)

	for index in 2:
		var marker := Rig.HAND_SPREAD * float(index * 2 - 1)
		box(support, Vector3(0.10, bridge_height, 0.10), marker + Vector3.UP * bridge_height * 0.5, Color("#c6844b"))
		box(support, Vector3(0.16, 0.09, 0.17), marker, Color("#ffd788"))

	ledge = AnimatableBody3D.new()
	ledge.position = Vector3(0, 0.18, 0)
	apparatus.add_child(ledge)
	box(ledge, Vector3(3.1, 0.27, 1.7), Vector3.ZERO, Color("#558478"), true)
	rig = Rig.new()
	apparatus.add_child(rig)
	rig.configure(support, ledge, articulated, proportions)
	recorder.log_event("hanging_setup", {"articulated": articulated, "movable_support": movable})


func apparatus_add(body: PhysicsBody3D, center: Vector3) -> void:
	body.position = center
	body.collision_layer = 0
	body.collision_mask = 0
	apparatus.add_child(body)


func box(parent: Node3D, dimensions: Vector3, center: Vector3, color: Color, solid := false) -> void:
	var shape := BoxShape3D.new()
	shape.size = dimensions
	if parent is RigidBody3D or solid:
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = center
		parent.add_child(collider)
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = center
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.77
	visual.material_override = material
	parent.add_child(visual)


func _physics_process(delta: float) -> void:
	if rig == null:
		return
	var target_y := 0.18
	if raised:
		target_y = HAND_HEIGHT - rig.average_span("LowerArm") - rig.average_span("UpperArm")
		target_y += rig.model.floor_height - rig.shoulder_y - 0.04
	ledge.position.y = move_toward(ledge.position.y, target_y, delta * 0.85)
	var intention := read_intention()
	rig.advance(delta, intention)
	status.text = "Feet supported" if rig.foot_contact else "Hanging from grip"
	if recorder.recording:
		var support_speed: Vector3 = support.linear_velocity if support is RigidBody3D else Vector3.ZERO
		recorder.log_event("hanging_physics", {
			"rig": "articulated" if articulated else "procedural",
			"movable_support": movable, "move": intention, "effort": rig.effort,
			"feet_supported": rig.foot_contact, "ledge_y": ledge.position.y,
			"torso_position": values(rig.torso.position), "torso_velocity": values(rig.torso.linear_velocity),
			"torso_roll": rig.torso.rotation.z, "support_position": values(support.position),
			"support_velocity": values(support_speed), "support_roll": support.rotation.z,
			"grip_render_error": rig.grip_error,
			"grip_force": null if articulated else values(rig.grip_force),
			"hand_anchors": [values(rig.hand_point(0)), values(rig.hand_point(1))],
			"leg_angles": leg_sample(),
		})


func leg_sample() -> Array:
	if articulated:
		return rig.leg_bodies.map(func(body: RigidBody3D): return body.rotation.z)
	return rig.leg_angles.map(func(angles: Vector2): return [angles.x, angles.y])


func read_intention() -> float:
	var left := Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)
	var right := Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
	if left or right:
		return float(right) - float(left)
	var intent := 0.0
	for device in Input.get_connected_joypads():
		var stick := Controller.stick_intent(Input.get_joy_axis(device, JOY_AXIS_LEFT_X))
		if absf(stick) > absf(intent):
			intent = stick
	return intent


func nudge() -> void:
	var body: RigidBody3D = support as RigidBody3D if movable else rig.torso
	body.apply_central_impulse(Vector3.RIGHT * 5.0)
	recorder.log_event("nudge", {"body": "support" if movable else "torso"})


func values(vector: Vector3) -> Array[float]:
	return [vector.x, vector.y, vector.z]


func add_controls() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := VBoxContainer.new()
	panel.position = Vector2(20, 18)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(panel)
	var row := HBoxContainer.new()
	panel.add_child(row)
	button(row, "Back to proportions", return_to_viewer)
	var mode := OptionButton.new()
	mode.focus_mode = Control.FOCUS_NONE
	mode.add_item("Procedural inertia")
	mode.add_item("Partial articulation")
	mode.item_selected.connect(func(index: int):
		articulated = index == 1
		restart()
	)
	row.add_child(mode)
	var support_mode := OptionButton.new()
	support_mode.focus_mode = Control.FOCUS_NONE
	support_mode.add_item("Fixed support")
	support_mode.add_item("Movable support")
	support_mode.item_selected.connect(func(index: int):
		movable = index == 1
		restart()
	)
	row.add_child(support_mode)
	button(row, "Nudge", nudge)
	var footing_button := button(row, "Raise footing", func():
		raised = not raised
		recorder.log_event("footing", {"raised": raised})
	)
	footing_button.toggle_mode = true
	button(row, "Reset", func():
		restart()
		footing_button.set_pressed_no_signal(false)
	)
	var instructions := Label.new()
	instructions.text = "Already holding on · A / D, ← / → or left stick to try moving"
	panel.add_child(instructions)
	panel.add_child(status)
	var capture := HBoxContainer.new()
	panel.add_child(capture)
	record_button = button(capture, "Record", func():
		var build := "source checkout"
		if FileAccess.file_exists("res://game/build_revision.txt"):
			build = FileAccess.get_file_as_string("res://game/build_revision.txt").strip_edges()
		recorder.start({
			"schema": 1, "scene": "hanging_experiment", "build": build,
			"physics_hz": Engine.physics_ticks_per_second, "articulated": articulated,
			"movable_support": movable, "proportions": JSON.parse_string(proportions),
		})
	)
	stop_button = button(capture, "Stop recording", recorder.stop)
	stop_button.disabled = true
	capture.add_child(recording_status)
	recorder.status_changed.connect(func(message: String):
		record_button.disabled = recorder.recording
		stop_button.disabled = not recorder.recording
		recording_status.text = message
	)
	mode.item_selected.connect(func(_index: int): footing_button.set_pressed_no_signal(false))
	support_mode.item_selected.connect(func(_index: int): footing_button.set_pressed_no_signal(false))


func button(row: HBoxContainer, text: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = text
	control.focus_mode = Control.FOCUS_NONE
	control.custom_minimum_size.y = 32
	control.pressed.connect(action)
	row.add_child(control)
	return control


func return_to_viewer() -> void:
	get_tree().set_meta("preview_proportions", proportions)
	get_tree().change_scene_to_file("res://game/mannequin_view.tscn")
