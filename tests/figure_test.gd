extends SceneTree

const Figure := preload("res://game/figure.gd")

var failures := 0


func _initialize() -> void:
	var original := Figure.new()
	original.points.assign([Vector3.ZERO, Vector3(1, 2, 3), Vector3(-2, 1, 0)])
	check(original.connect_points(1, 0), "connect two points")
	check(original.connect_points(2, 1), "connect a second pair")
	check(not original.connect_points(0, 1), "reject reverse duplicate")
	check(not original.connect_points(1, 1), "reject self-link")
	var restored := Figure.new()
	check(restored.decode(original.encode()), "decode a saved figure")
	check(restored.points == original.points, "preserve point positions and depth")
	check(restored.links == original.links, "preserve links")
	var saved := restored.encode()
	var malformed := '{"version":1,"points":[[0,0,0]],"links":[[0,7]]}'
	check(not restored.decode(malformed), "reject invalid endpoint")
	check(restored.encode() == saved, "preserve existing figure on malformed load")
	restored.remove_point(0)
	check(restored.links == [Vector2i(0, 1)], "delete incident links and reindex survivors")
	if failures == 0:
		print("Figure checks passed.")
	quit(int(failures > 0))


func check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)
