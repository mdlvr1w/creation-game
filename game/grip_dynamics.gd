extends RefCounted
## Transfers force at a grip point and returns the opposite reaction for the character.


static func exchange(cube: RigidBody3D, offset: Vector3, gap: Vector3, driver: Vector3) -> Vector3:
	var contact_velocity := cube.linear_velocity + cube.angular_velocity.cross(offset)
	var relative_velocity := driver - contact_velocity
	var mass := cube.mass
	var force := Vector3(
		clampf(mass * (gap.x * 100.0 + relative_velocity.x * 19.0), -150.0, 150.0),
		clampf(mass * (gap.y * 95.0 + relative_velocity.y * 12.0), -115.0, 115.0),
		0.0
	)
	if force.length_squared() > 0.01:
		cube.apply_force(force, offset)
	return -force


static func brace_against_support(cube: RigidBody3D, offset: Vector3, drive_speed: float) -> Vector3:
	# Feet already carry the character on this body. Only active effort drives the shared support.
	var force := Vector3(drive_speed * cube.mass * 11.0, 0, 0)
	if not is_zero_approx(drive_speed):
		cube.apply_force(force, offset)
	return force
