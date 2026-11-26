extends Node2D

const DIRECTIONS := [
	Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP, Vector2(0.707107, -0.707107),
]
const FREE_HANDLE := 4
const OFFSET := 29.0
const HIT_RADIUS := 9.0
const ACCENT := Color("#00765e")

var center := Vector2.ZERO
var visible_handles: Array[int] = []
var hovered := -1


func position_for(index: int) -> Vector2:
	return center + DIRECTIONS[index] * OFFSET


func hit_test(cursor: Vector2) -> int:
	for index in visible_handles:
		if cursor.distance_to(position_for(index)) <= HIT_RADIUS:
			return index
	return -1


func _draw() -> void:
	for index in visible_handles:
		var tip := position_for(index)
		var direction: Vector2 = DIRECTIONS[index]
		var side := direction.orthogonal()
		var color := ACCENT if hovered == index else ACCENT.lerp(Color.WHITE, 0.22)
		draw_circle(tip, HIT_RADIUS, Color("#faf9f5"), true, -1.0, true)
		if index == FREE_HANDLE:
			draw_arc(tip, 5.0, 0.0, TAU, 20, color, 2.0, true)
		else:
			draw_line(tip - direction * 6.0, tip + direction * 4.0, color, 2.0, true)
			draw_colored_polygon(PackedVector2Array([
				tip + direction * 6.0, tip + side * 4.0, tip - side * 4.0,
			]), color)
