extends Node2D

const DIRECTIONS := [
	Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP, Vector2(0.707107, -0.707107), Vector2(0.707107, 0.707107),
]
const FREE_HANDLE := 4
const MIRROR_HANDLE := 5
const HELP := [
	"Drag to extend right", "Drag to extend down", "Drag to extend left",
	"Drag to extend up", "Drag to extend in any direction",
	"Click to mirror the next pull around this point",
]
const OFFSET := 29.0
const HIT_RADIUS := 9.0
const ACCENT := Color("#00765e")

var center := Vector2.ZERO
var visible_handles: Array[int] = []
var hovered := -1
var mirror_armed := false
var hint := Label.new()


func _ready() -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color("#222827")
	background.set_corner_radius_all(5)
	background.content_margin_left = 8
	background.content_margin_right = 8
	background.content_margin_top = 4
	background.content_margin_bottom = 4
	hint.add_theme_stylebox_override("normal", background)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.hide()
	add_child(hint)


func refresh() -> void:
	hint.visible = hovered >= 0 and visible_handles.has(hovered)
	if hint.visible:
		hint.text = "Click to turn off mirroring" if hovered == MIRROR_HANDLE and mirror_armed else HELP[hovered]
		hint.reset_size()
		var tip := position_for(hovered)
		var bounds := get_viewport_rect()
		var x := clampf(tip.x + 13.0, 4.0, maxf(4.0, bounds.size.x - hint.size.x - 4.0))
		var y := minf(tip.y + 13.0, bounds.size.y - hint.size.y - 4.0)
		hint.position = Vector2(x, y)
	queue_redraw()


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
		if index == MIRROR_HANDLE:
			if mirror_armed:
				draw_circle(tip, HIT_RADIUS, ACCENT, true, -1.0, true)
				color = Color.WHITE
			draw_line(tip + Vector2(0, -6), tip + Vector2(0, 6), color, 1.5, true)
			draw_colored_polygon(PackedVector2Array([
				tip + Vector2(-7, 0), tip + Vector2(-3, -4), tip + Vector2(-3, 4),
			]), color)
			draw_colored_polygon(PackedVector2Array([
				tip + Vector2(7, 0), tip + Vector2(3, -4), tip + Vector2(3, 4),
			]), color)
		elif index == FREE_HANDLE:
			draw_arc(tip, 5.0, 0.0, TAU, 20, color, 2.0, true)
		else:
			draw_line(tip - direction * 6.0, tip + direction * 4.0, color, 2.0, true)
			draw_colored_polygon(PackedVector2Array([
				tip + direction * 6.0, tip + side * 4.0, tip - side * 4.0,
			]), color)
