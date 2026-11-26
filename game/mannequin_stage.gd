extends Node3D

var floor_mesh := MeshInstance3D.new()


func _ready() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("#283338")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("#e2eaf0")
	world.environment.ambient_light_energy = 0.26
	add_child(world)

	var mesh := PlaneMesh.new()
	mesh.size = Vector2(300.0, 300.0)
	floor_mesh.mesh = mesh
	var surface := StandardMaterial3D.new()
	surface.albedo_color = Color("#404b51")
	surface.roughness = 1.0
	floor_mesh.material_override = surface
	floor_mesh.position.y = -0.003
	add_child(floor_mesh)

	add_light(Vector3(-48, -32, 0), Color("#fff3e4"), 0.22, true)
	add_light(Vector3(-26, 145, 0), Color("#d9ebff"), 0.12, false)


func add_light(angle: Vector3, color: Color, energy: float, casts_shadow: bool) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = angle
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = casts_shadow
	light.directional_shadow_max_distance = 12.0
	add_child(light)
