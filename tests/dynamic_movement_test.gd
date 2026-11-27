extends SceneTree

const Preview := preload("res://game/movement_preview.tscn")
const Settings := preload("res://game/movement_settings.gd")
const DT := 1.0 / 60.0

var failures := 0
var preview: Node3D


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	preview = Preview.instantiate()
	preview.use_dynamic_controller = true
	root.add_child(preview)
	preview.set_physics_process(false)
	var player = preview.player
	var cube = preview.cube
	player.settings = Settings.new()
	await frames(20)
	check(player.is_on_floor(), "dynamic body finds static ground")
	await frames(35, 0.5)
	check(player.position.x > 1.2 and player.velocity.x > 2.4, "partial stick moves the dynamic body")
	check(player.last_drive_impulse.length() <= player.drive_strength * DT + 0.001, "drive respects its impulse budget")
	await frames(16)
	check(absf(player.velocity.x) < 0.3, "the released stick brakes on the ground")

	var short_jump := await measure_jump(1)
	var full_jump := await measure_jump(35)
	check(full_jump > short_jump + 0.55 and full_jump > 1.15, "tap and hold keep distinct jumps")

	preview.reset_sandbox()
	cube.position = Vector3(-1.23, cube.HALF_SIZE + 0.02, 0)
	await frames(20, 0.0, false, true)
	check(player.held_cube == cube, "the reachable side can be grabbed")
	var anchor: Vector3 = player.grip_anchor
	var cube_height: float = cube.position.y
	await frames(16, 0.0, true, true)
	check(cube.position.y > cube_height + 0.18 and absf(cube.rotation.z) > 0.15, "a side jump lifts and tips the cube")
	check(player.grip_anchor == anchor, "the grip stays at the same local surface point")
	await frames(1)
	check(player.held_cube == null, "releasing removes the relationship")

	var light_progress := await push_for_distance(2.0)
	var heavy_progress := await push_for_distance(14.0)
	check(light_progress > heavy_progress + 0.12, "the same drive moves a lighter cube farther")

	cube.mass = 3.0
	preview.start_on_cube()
	await frames(36, 0.0, false, true)
	check(player.support_body == cube and player.grip_from_above, "top grab identifies the supporting cube")
	var top_start: float = center_height()
	var maximum := top_start
	var takeoffs := 0
	for attempt in 17:
		for frame in 24:
			await frames(1, 0.0, frame < 12, true)
			maximum = maxf(maximum, center_height())
			if player.last_takeoff_impulse.y > 0.0:
				takeoffs += 1
	check(takeoffs >= 10, "the repeated-jump regression actually attempts takeoffs from the cube")
	check(maximum < top_start + 0.5 and center_height() < top_start + 0.15,
		"repeated top-grab jumps do not ratchet the pair upward")

	preview.start_on_cube()
	await frames(36, 0.0, false, true)
	var start_x: float = player.position.x
	for frame in 18:
		cube.apply_central_force(Vector3.LEFT * 105.0)
		await frames(1, 0.0, false, true)
	check(player.position.x < start_x - 0.12, "a moving cube can still carry the figurine")
	await check_quiet_acquisition()
	await check_close_cube_release()
	await check_grab_facing()
	await check_off_center_ride()
	await check_gentle_wheel_catch()
	await check_slow_wheel_footing()
	await check_rotating_wheel()
	await check_fast_wheel_release()

	await check_irregular_fixture()
	await check_incline_traction()
	await check_moving_footing()
	await check_jump_support()
	await check_non_bouncy_landings()

	if failures == 0:
		print("Dynamic movement checks passed.")
	quit(int(failures > 0))


func check_quiet_acquisition() -> void:
	var player = preview.player
	var cube = preview.cube
	for distance in [1.05, 1.30]:
		preview.reset_sandbox()
		cube.position.x = -distance
		await frames(28)
		var peak_force := 0.0
		var peak_speed := 0.0
		for frame in 18:
			await frames(1, 0.0, false, true)
			peak_force = maxf(peak_force, player.last_grip_force.length())
			peak_speed = maxf(peak_speed, cube.linear_velocity.length())
		check(player.held_cube == cube and peak_force < 2.0 and peak_speed < 0.02,
			"a neutral grab takes hold without kicking a stationary cube")


func check_close_cube_release() -> void:
	preview.reset_sandbox()
	var player = preview.player
	var cube = preview.cube
	cube.position.x = -1.05
	await frames(24)
	await frames(6, -1.0)
	await frames(5, -1.0, false, true)
	check(player.held_cube == cube, "the close release test starts with a grip")
	var before_release: float = player.position.y
	await frames(6, -1.0)
	check(player.held_cube == null and absf(player.position.y - before_release) < 0.08
		and player.is_on_floor(), "releasing during a close push keeps the body on the ground")


func check_grab_facing() -> void:
	var player = preview.player
	var cube = preview.cube
	for side in [-1.0, 1.0]:
		preview.reset_sandbox()
		cube.position.x = side * 1.23
		await frames(24)
		await frames(20, 0.0, false, true)
		var anchor: Vector3 = player.grip_anchor
		await frames(24, side, false, true)
		check(player.velocity.x * side > 0.7 and player.motion.rotation.y * side > 1.4,
			"pushing moves toward the cube while facing it")
		await frames(26, -side, false, true)
		var phase: float = player.motion.phase
		await frames(1, -side, false, true)
		check(player.velocity.x * side < -0.7 and player.motion.rotation.y * side > 1.4
			and angle_difference(phase, player.motion.phase) < 0.0,
			"pulling faces the cube and walks backward")
		var least_facing := PI * 0.5
		for frame in 8:
			await frames(1, side, false, true)
			least_facing = minf(least_facing, player.motion.rotation.y * side)
		check(least_facing > 1.4, "reversing a pull into a push keeps facing the cube")
		check(player.held_cube == cube and player.grip_anchor == anchor and player.motion.hand_error() < 0.08,
			"turning and reversing keep the same grip and visible hand contacts")

		# Get back into a pull before leaving the ground, then hold the same input in the air.
		await frames(20, -side, false, true)
		var airborne := 0
		var facing_during_jump := PI * 0.5
		for frame in 24:
			await frames(1, -side, true, true)
			if not player.is_on_floor():
				airborne += 1
				facing_during_jump = minf(facing_during_jump, player.motion.rotation.y * side)
		check(airborne >= 12 and facing_during_jump > 1.0 and player.held_cube == cube
			and player.grip_anchor == anchor, "an airborne pull keeps facing the same attachment")


func check_off_center_ride() -> void:
	preview.reset_sandbox()
	var player = preview.player
	var cube = preview.cube
	cube.position = Vector3(-22, cube.HALF_SIZE + 0.02, 0)
	player.position = Vector3(-21.65, cube.HALF_SIZE * 2.0 + 0.08, 0)
	await frames(16)
	await frames(36, 0.0, false, true)
	check(player.grip_from_above, "off-center stance can grab the top")
	check(absf(cube.linear_velocity.x) < 0.8, "neutral stance does not drive the cube")
	check(is_zero_approx(player.last_drive_speed), "the neutral stick requests no drive speed")
	var peak_speed := 0.0
	for frame in 120:
		await frames(1, -0.20, false, true)
		peak_speed = maxf(peak_speed, absf(cube.linear_velocity.x))
	check(peak_speed < 7.0, "a small stick tilt does not produce runaway lateral motion")
	await frames(60, 0.0, false, true)
	check(absf(cube.linear_velocity.x) < 0.8, "the cube settles after steering stops")


func check_gentle_wheel_catch() -> void:
	var player = preview.player
	var wheel = preview.wheel
	player.settings.values.gravity = 17.6
	player.settings.values.max_jump = 7.5
	player.settings.values.min_jump = 2.5
	for speed in [0.0, 0.8]:
		preview.reset_sandbox()
		wheel.spin_speed = speed
		player.position.x = wheel.position.x
		await frames(24)
		var caught := -1
		var anchor := Vector3.ZERO
		var peak_roll := 0.0
		var touched_upper_tread := false
		for frame in 480:
			await wheel_frame(frame < 9)
			if player.held_cube != wheel:
				continue
			if caught < 0:
				caught = frame
				anchor = player.grip_anchor
			if frame - caught <= 60:
				peak_roll = maxf(peak_roll, absf(player.rotation.z))
			touched_upper_tread = touched_upper_tread or (
				player.support_body == wheel and player.position.y > wheel.position.y)
		check(caught >= 0 and player.held_cube == wheel and player.grip_anchor == anchor,
			"the gentle catch maintains the original grip")
		check(peak_roll < deg_to_rad(30.0), "the initial stationary or slow catch stays predominantly upright")
		if speed > 0.0:
			check(touched_upper_tread, "the body makes contact on the upper tread during a slow hold")
	wheel.spin_speed = 0.82


func check_slow_wheel_footing() -> void:
	preview.reset_sandbox()
	var player = preview.player
	var wheel = preview.wheel
	wheel.spin_speed = 0.4
	player.position.x = wheel.position.x + 0.07
	await frames(24)
	var caught := false
	var anchor := Vector3.ZERO
	var travel := 0.0
	var last_angle: float = wheel.rotation.z
	var peak_roll := 0.0
	var load_frames := 0
	var hanging_again := false
	for frame in 1240:
		await physics_frame
		player.update_grip(wheel, frame >= 6)
		player.step(DT, 0.0, frame < 4)
		if not caught and player.held_cube == wheel:
			caught = true
			anchor = player.grip_anchor
			last_angle = wheel.rotation.z
		if not caught or player.held_cube != wheel:
			continue
		travel += absf(angle_difference(last_angle, wheel.rotation.z))
		last_angle = wheel.rotation.z
		peak_roll = maxf(peak_roll, absf(player.rotation.z))
		if player.support_body == wheel and player.last_support_impulse > 0.5 				and absf(player.rotation.z) < deg_to_rad(30.0) and player.physical_crouch > 0.2:
			load_frames += 1
		if load_frames > 0 and not player.is_on_floor() and player.physical_crouch < 0.01:
			hanging_again = true
	check(caught and player.held_cube == wheel and player.grip_anchor == anchor and travel > TAU,
		"the slow crossing keeps one rim point through a full revolution")
	check(load_frames > 30 and hanging_again and peak_roll < deg_to_rad(50.0),
		"the crouch carries load at the crown and gives way to hanging without inversion")
	wheel.spin_speed = 0.82


func check_rotating_wheel() -> void:
	preview.reset_sandbox()
	var player = preview.player
	var wheel = preview.wheel
	player.settings.values.gravity = 17.6
	player.settings.values.max_jump = 7.5
	player.position.x = wheel.position.x
	await frames(24)
	player.update_grip(wheel, true)
	check(player.held_cube == null, "the rim requires a jump from the floor")

	for frame in 32:
		await wheel_frame(true)
		if player.held_cube == wheel:
			break
	check(player.held_cube == wheel, "a jump can catch the rim")
	if player.held_cube != wheel:
		return
	var anchor: Vector3 = player.grip_anchor
	var slow_roll := 0.0
	var fast_roll := 0.0
	var slow_yaw := 0.0
	var fast_yaw := 0.0
	var steady_slow_frames := 0
	var body_top := 0.0
	var lateral_span := Vector2.ZERO
	var hand_error := 0.0
	for frame in 880:
		if frame == 550:
			wheel.spin_speed = 2.0
		await wheel_frame(frame < 26)
		if frame > 6 and player.held_cube == wheel:
			hand_error = maxf(hand_error, player.motion.hand_error())
		var lateral_speed: float = player.velocity.x
		if frame < 550 and not player.is_on_floor() and absf(lateral_speed) < 1.2:
			steady_slow_frames += 1
			if steady_slow_frames > 8:
				slow_yaw = maxf(slow_yaw, absf(player.motion.rotation.y))
		else:
			steady_slow_frames = 0
		if frame > 570 and not player.is_on_floor() and absf(lateral_speed) > 2.4:
			fast_yaw = maxf(fast_yaw, player.motion.rotation.y * signf(lateral_speed))
		if frame < 550:
			slow_roll = maxf(slow_roll, absf(player.rotation.z))
			body_top = maxf(body_top, player.position.y)
			var offset_x: float = player.position.x - wheel.position.x
			lateral_span.x = minf(lateral_span.x, offset_x)
			lateral_span.y = maxf(lateral_span.y, offset_x)
		else:
			fast_roll = maxf(fast_roll, absf(player.rotation.z))
	check(player.held_cube == wheel and player.grip_anchor == anchor,
		"the same hand holds the same point through slow and faster turns")
	check(is_zero_approx(wheel.position.z) and is_zero_approx(anchor.z),
		"the wheel and the held point are centered on the movement plane")
	check(body_top > wheel.position.y - 0.65 and lateral_span.x < -0.5 and lateral_span.y > 0.5,
		"the body rises and is carried around both sides of the axle")
	check(slow_yaw > 0.0 and slow_yaw < 0.65 and fast_yaw > 1.0,
		"without input the body turns farther with faster lateral carry")
	check(slow_roll > 0.04 and fast_roll > 0.12, "the body visibly responds at both wheel speeds")
	check(hand_error < 0.08, "the visible forearm stays at the rim")

	for frame in 220:
		if wheel.to_global(anchor).y < wheel.position.y - 1.48:
			break
		await wheel_frame()
	wheel.spin_speed = 0.0
	for frame in 360:
		await wheel_frame()
	var ledge := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 0.2, 2.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	ledge.add_child(collider)
	ledge.position = Vector3(player.position.x, player.position.y + 0.08, 0.0)
	preview.add_child(ledge)
	for frame in 50:
		await wheel_frame()
	check(player.support_body == ledge and player.held_cube == wheel, "the feet find support during the same hold")
	ledge.queue_free()
	for frame in 35:
		await wheel_frame()
	check(not player.is_on_floor() and player.held_cube == wheel and player.grip_anchor == anchor,
		"removing footing returns to hanging without changing the grip")
	player.update_grip(wheel, false)
	check(player.held_cube == null, "releasing the button releases the wheel")


func check_fast_wheel_release() -> void:
	preview.reset_sandbox()
	var player = preview.player
	var wheel = preview.wheel
	wheel.spin_speed = 4.0
	player.position.x = wheel.position.x
	await frames(24)
	var anchor := Vector3.ZERO
	var caught := false
	var travel := 0.0
	var previous_angle := 0.0
	var peak_error := 0.0
	for frame in 300:
		await wheel_frame(frame < 9)
		if player.held_cube != wheel:
			continue
		if not caught:
			anchor = player.grip_anchor
			caught = true
			previous_angle = wheel.rotation.z
		travel += absf(angle_difference(previous_angle, wheel.rotation.z))
		previous_angle = wheel.rotation.z
		peak_error = maxf(peak_error, player.motion.hand_error())
		if travel > TAU and absf(player.rotation.z) > 0.18 and player.position.y > 2.0:
			break
	check(player.held_cube == wheel and travel > TAU and player.grip_anchor == anchor
		and caught, "a grab at full speed survives a complete turn")
	check(peak_error < 0.08, "the fast grip keeps both visible hands near the rim")
	if player.held_cube != wheel:
		return
	check(absf(player.rotation.z) > 0.18, "release starts while the body is tilted")
	var launch: Vector3 = player.velocity
	var release_roll: float = player.rotation.z
	player.update_grip(wheel, false)
	await frames(1)
	check(absf(angle_difference(release_roll, player.rotation.z)) < 0.15
		and absf(player.rotation.z) > 0.05, "releasing does not snap rotation")
	check(absf(player.velocity.x - launch.x) < 0.05
		and absf(player.velocity.y - (launch.y - player.settings.values.gravity * DT)) < 0.06,
		"straightening preserves launch velocity apart from gravity")
	await frames(6)
	check(not player.is_on_floor() and absf(player.velocity.x - launch.x) < 0.06,
		"neutral input does not brake the airborne launch")
	await frames(20)
	check(absf(player.rotation.z) < 0.05, "balance promptly brings the released body upright")
	await frames(120)
	check(player.is_on_floor() and absf(player.rotation.z) < 0.025, "the launch lands upright")
	await frames(15, -0.6)
	check(player.velocity.x < -0.8, "walking is available after landing")


func wheel_frame(jump := false) -> void:
	await physics_frame
	preview.player.update_grip(preview.wheel, true)
	preview.player.step(DT, 0.0, jump)


func check_irregular_fixture() -> void:
	preview.reset_sandbox()
	var player = preview.player
	var fixture: RigidBody3D = preview.irregular
	player.position = fixture.position + Vector3(0.43, 0.41, 0.0)
	await frames(22)
	check(player.support_body == fixture and player.last_support_impulse > 0.0,
		"the compound fixture provides load-bearing support")
	var targets: Array[RigidBody3D] = [preview.cube, preview.wheel, fixture]
	for frame in 35:
		await physics_frame
		player.update_grip_candidates(targets, true)
		player.step(DT, 0.0, false)
	check(player.held_cube == fixture and player.last_shared_support,
		"shared acquisition catches a supported compound body")
	if player.held_cube != fixture:
		return
	var anchor: Vector3 = player.grip_anchor
	check(player.motion.hand_error() < 0.16, "both hands reach the compound fixture")
	fixture.apply_impulse(Vector3.RIGHT * 2.0, Vector3.UP * 0.45)
	for frame in 60:
		await physics_frame
		player.update_grip_candidates(targets, true)
		player.step(DT, 0.0, false)
	check(player.held_cube == fixture and player.grip_anchor == anchor,
		"moving the compound body preserves its local attachment")
	player.update_grip_candidates(targets, false)
	check(player.held_cube == null, "releasing the compound body clears the shared grip")


func check_incline_traction() -> void:
	var player = preview.player
	for movable in [false, true]:
		var surface := add_traction_surface(-0.24, movable)
		preview.reset_sandbox()
		player.position = surface.position + Vector3.UP * 0.22
		await frames(90)
		var at_rest := surface.to_local(player.position)
		await frames(90)
		check(player.support_body == surface and absf(surface.to_local(player.position).x - at_rest.x) < 0.04
			and player.motion.stride < 0.03, "neutral input holds footing on a gentle incline")

		for direction: float in [-1.0, 1.0]:
			await frames(30)
			var start := surface.to_local(player.position)
			await frames(22, direction * 0.4)
			var walk := (surface.to_local(player.position).x - start.x) * direction
			check(player.support_body == surface and walk > 0.28 and player.motion.stride > 0.22,
				"partial input walks and animates on the incline")
			start = surface.to_local(player.position)
			await frames(22, direction)
			var run := (surface.to_local(player.position).x - start.x) * direction
			check(player.support_body == surface and run > walk + 0.30 and player.motion.stride > 0.5,
				"full input runs faster on the same incline")
		surface.queue_free()
		await frames(1)


func check_moving_footing() -> void:
	var player = preview.player
	var platform := add_traction_surface(0.0, true) as RigidBody3D
	preview.reset_sandbox()
	player.position = platform.position + Vector3.UP * 0.22
	await frames(40)
	player.linear_velocity = Vector3.RIGHT * 2.5
	platform.linear_velocity = player.linear_velocity
	var start := platform.to_local(player.position)
	await frames(36)
	check(player.support_body == platform and absf(platform.to_local(player.position).x - start.x) < 0.04
		and player.motion.stride < 0.03 and player.velocity.x > 2.0, "riding a moving support keeps the feet still")
	var momentum := horizontal_momentum(player, platform)
	var platform_speed := platform.linear_velocity.x
	await frames(22, 0.8)
	check(player.support_body == platform and player.velocity.x > platform.linear_velocity.x + 1.0
		and platform.linear_velocity.x < platform_speed - 0.6,
		"walking on a movable support sends momentum back through the feet")
	var after := horizontal_momentum(player, platform)
	check(absf(after - momentum) < 0.03, "traction conserves horizontal momentum on an unconstrained axis")
	platform.queue_free()


func horizontal_momentum(first: RigidBody3D, second: RigidBody3D) -> float:
	# Read both velocities from the same solver snapshot.
	var first_state := PhysicsServer3D.body_get_direct_state(first.get_rid())
	var second_state := PhysicsServer3D.body_get_direct_state(second.get_rid())
	return first.mass * first_state.linear_velocity.x + second.mass * second_state.linear_velocity.x


func check_jump_support() -> void:
	var player = preview.player
	var cube = preview.cube
	var floor_height := await measure_jump(35)
	for weight in [0.25, 3.0, 30.0]:
		preview.start_on_cube()
		cube.mass = weight
		await frames(50)
		check(player.support_body == cube, "the grounded cube supports the takeoff")
		var cube_height := await jump_rise(35)
		check(absf(cube_height - floor_height) < 0.08, "floor-backed takeoff is independent of cube mass")

	preview.reset_sandbox()
	player.position = preview.irregular.position + Vector3(-0.44, 0.88, 0.0)
	await frames(50)
	check(player.support_body == preview.irregular, "the compound incline supports the takeoff")
	var incline_height := await jump_rise(35)
	check(absf(incline_height - floor_height) < 0.08, "another floor-backed shape gives the same full jump")

	for count: int in [2, 5, 10]:
		preview.reset_sandbox(true)
		await frames(1)
		for level in count:
			preview.spawn_cube(Vector3(-20.0, preview.cube.HALF_SIZE + level * (preview.cube.SIZE + 0.01), 0.0))
		var top: RigidBody3D = preview.placed_cubes[-1]
		player.position = top.position + Vector3.UP * (preview.cube.HALF_SIZE + 0.05)
		await frames(100)
		check(player.support_body == top, "the player is standing on the top cube of a settled stack")
		var stack_height := await jump_rise(35)
		check(absf(stack_height - floor_height) < 0.09, "stable stacks give the same jump as terrain")
	preview.reset_sandbox(true)
	await frames(1)

	var platform := add_traction_surface(0.0, true) as RigidBody3D
	platform.axis_lock_linear_y = false
	platform.freeze = true
	preview.reset_sandbox()
	player.position = platform.position + Vector3.UP * 0.22
	await frames(40)
	check(player.support_body == platform, "the unsupported-platform check starts with footing")
	platform.freeze = false
	await frames(3, 0.0, true)
	check(player.velocity.y > 0.75 and player.velocity.y < player.settings.values.max_jump * 0.75
		and platform.linear_velocity.y < -3.0, "an unbacked surface recoils and shares the jump impulse")
	platform.queue_free()

	await frames(1)

	var plank := add_traction_surface(0.0, true) as RigidBody3D
	plank.lock_rotation = false
	plank.axis_lock_angular_x = true
	plank.axis_lock_angular_y = true
	plank.axis_lock_linear_x = true
	plank.freeze = true
	preview.reset_sandbox()
	player.position = plank.position + Vector3(4.5, 0.22, 0.0)
	await frames(40)
	check(player.support_body == plank, "the tipping support starts under the player's feet")
	plank.freeze = false
	var tipping_height := await jump_rise(35)
	check(tipping_height < floor_height - 0.2 and absf(plank.rotation.z) > 0.10,
		"a surface can yield by rotating even when its center cannot move down")
	plank.queue_free()


func check_non_bouncy_landings() -> void:
	var player = preview.player
	var cube = preview.cube
	for weight in [0.25, 3.0, 30.0]:
		preview.reset_sandbox()
		cube.mass = weight
		cube.adjust_property(&"bounce", 0.0)
		await frames(35)
		var surface_height: float = cube.position.y
		player.position = cube.position + Vector3.UP * 3.2
		var highest := surface_height
		var touched := false
		for frame in 85:
			await frames(1)
			touched = touched or player.support_body == cube
			highest = maxf(highest, cube.position.y)
		check(touched and highest - surface_height < 0.025, "a zero-bounce cube stays down on a centered landing")


func add_traction_surface(grade: float, movable: bool) -> PhysicsBody3D:
	var surface: PhysicsBody3D = RigidBody3D.new() if movable else StaticBody3D.new()
	if surface is RigidBody3D:
		# Isolate horizontal motion so ground friction and tipping cannot hide impulse exchange.
		surface.mass = 3.5
		surface.lock_rotation = true
		surface.axis_lock_linear_y = true
		surface.axis_lock_linear_z = true
		surface.gravity_scale = 0.0
		surface.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		surface.linear_damp = 0.0
	surface.collision_layer = 2
	surface.collision_mask = 1
	surface.position = Vector3(-24.0, 3.2, 0.0)
	var collider := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(14.0, 0.24, 1.4)
	collider.shape = slab
	collider.rotation.z = grade
	surface.add_child(collider)
	preview.add_child(surface)
	return surface


func frames(count: int, direction := 0.0, jump := false, grab := false) -> void:
	for frame in count:
		await physics_frame
		preview.player.update_grip(preview.cube, grab)
		preview.player.step(DT, direction, jump)


func measure_jump(hold_frames: int) -> float:
	preview.reset_sandbox()
	await frames(20)
	return await jump_rise(hold_frames)


func jump_rise(hold_frames: int) -> float:
	var start_height: float = preview.player.position.y
	var apex := start_height
	for frame in 65:
		await frames(1, 0.0, frame < hold_frames)
		apex = maxf(apex, preview.player.position.y)
	return apex - start_height


func push_for_distance(cube_mass: float) -> float:
	preview.reset_sandbox()
	preview.cube.mass = cube_mass
	preview.cube.position.x = -1.23
	await frames(20, 0.0, false, true)
	check(preview.player.held_cube == preview.cube, "each mass comparison starts with a grip")
	var initial_x: float = preview.cube.position.x
	await frames(50, -1.0, false, true)
	check(is_equal_approx(preview.player.last_drive_speed, -5.5), "grabbing preserves movement intent")
	return initial_x - preview.cube.position.x


func center_height() -> float:
	var player = preview.player
	var cube = preview.cube
	return (player.position.y * player.mass + cube.position.y * cube.mass) / (player.mass + cube.mass)


func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)
