extends RefCounted

const FORMAT_VERSION := 1

var points: Array[Vector3] = []
var links: Array[Vector2i] = []


func connect_points(first: int, second: int) -> bool:
	if first < 0 or second < 0 or first >= points.size() or second >= points.size():
		return false
	if first == second:
		return false
	var link := Vector2i(mini(first, second), maxi(first, second))
	if links.has(link):
		return false
	links.append(link)
	return true


func remove_point(index: int) -> void:
	if index < 0 or index >= points.size():
		return
	points.remove_at(index)
	var remaining: Array[Vector2i] = []
	for link in links:
		if link.x == index or link.y == index:
			continue
		remaining.append(Vector2i(link.x - int(link.x > index), link.y - int(link.y > index)))
	links = remaining


func encode() -> String:
	var coordinates: Array = []
	var connections: Array = []
	for point in points:
		coordinates.append([point.x, point.y, point.z])
	for link in links:
		connections.append([link.x, link.y])
	return JSON.stringify({"version": FORMAT_VERSION, "points": coordinates, "links": connections})


func decode(data: String) -> bool:
	var decoded: Variant = JSON.parse_string(data)
	if not decoded is Dictionary or decoded.get("version") != FORMAT_VERSION:
		return false
	var coordinates: Variant = decoded.get("points")
	var connections: Variant = decoded.get("links")
	if not coordinates is Array or not connections is Array:
		return false

	var candidate = get_script().new()
	for point in coordinates:
		if not point is Array or point.size() != 3:
			return false
		for coordinate in point:
			if not coordinate is float or not is_finite(coordinate):
				return false
		candidate.points.append(Vector3(point[0], point[1], point[2]))
	for link in connections:
		if not link is Array or link.size() != 2:
			return false
		for index in link:
			if not index is float or index < 0 or index >= candidate.points.size() or index != floor(index):
				return false
		if not candidate.connect_points(int(link[0]), int(link[1])):
			return false
	points = candidate.points
	links = candidate.links
	return true
