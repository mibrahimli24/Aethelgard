extends Control
## Procedural item icon: draws a simple shape per item "icon" id, tinted with the item colour.
## Usage: var ic = ItemIcon.new(); ic.setup("herb", Color(...), 40.0)

var icon_id := "ore"
var tint := Color(0.8, 0.8, 0.8)
var bg := Color(0.12, 0.1, 0.08, 0.9)


func setup(icon: String, color: Color, px: float = 40.0) -> Control:
	icon_id = icon
	tint = color
	custom_minimum_size = Vector2(px, px)
	size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()
	return self


func _pt(u: float, v: float) -> Vector2:
	return Vector2(u, v) * size


func _poly(pts: Array, col: Color) -> void:
	var arr := PackedVector2Array()
	for p: Vector2 in pts:
		arr.append(_pt(p.x, p.y))
	draw_colored_polygon(arr, col)


func _circ(u: float, v: float, r: float, col: Color) -> void:
	draw_circle(_pt(u, v), r * size.x, col)


func _ln(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	draw_line(_pt(a.x, a.y), _pt(b.x, b.y), col, w * size.x, true)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), bg)
	draw_rect(Rect2(Vector2.ZERO, size), tint.darkened(0.3), false, 1.5)
	var c := tint
	var d := tint.darkened(0.35)
	var l := tint.lightened(0.35)
	match icon_id:
		"herb", "leaf":
			_ln(Vector2(0.5, 0.9), Vector2(0.5, 0.35), 0.05, d)
			_poly([Vector2(0.5, 0.15), Vector2(0.72, 0.4), Vector2(0.5, 0.5), Vector2(0.28, 0.4)], c)
			_poly([Vector2(0.5, 0.45), Vector2(0.8, 0.62), Vector2(0.5, 0.72)], l)
			_poly([Vector2(0.5, 0.5), Vector2(0.2, 0.66), Vector2(0.5, 0.76)], c)
		"berry":
			_circ(0.38, 0.6, 0.15, c)
			_circ(0.62, 0.6, 0.15, c)
			_circ(0.5, 0.4, 0.15, l)
			_ln(Vector2(0.5, 0.25), Vector2(0.58, 0.12), 0.04, Color(0.3, 0.6, 0.3))
		"meat":
			_poly([Vector2(0.2, 0.55), Vector2(0.35, 0.3), Vector2(0.68, 0.3), Vector2(0.82, 0.55), Vector2(0.65, 0.78), Vector2(0.3, 0.76)], c)
			_circ(0.5, 0.52, 0.1, l)
			_ln(Vector2(0.8, 0.6), Vector2(0.92, 0.85), 0.07, Color(0.92, 0.9, 0.8))
		"mushroom":
			_poly([Vector2(0.4, 0.55), Vector2(0.4, 0.85), Vector2(0.6, 0.85), Vector2(0.6, 0.55)], Color(0.9, 0.85, 0.75))
			_poly([Vector2(0.12, 0.56), Vector2(0.2, 0.3), Vector2(0.5, 0.15), Vector2(0.8, 0.3), Vector2(0.88, 0.56)], c)
			_circ(0.4, 0.35, 0.05, l)
			_circ(0.64, 0.4, 0.04, l)
		"stew":
			_poly([Vector2(0.15, 0.45), Vector2(0.85, 0.45), Vector2(0.75, 0.8), Vector2(0.25, 0.8)], Color(0.3, 0.27, 0.25))
			_poly([Vector2(0.2, 0.42), Vector2(0.8, 0.42), Vector2(0.78, 0.5), Vector2(0.22, 0.5)], c)
			_ln(Vector2(0.4, 0.3), Vector2(0.45, 0.15), 0.03, Color(1, 1, 1, 0.6))
			_ln(Vector2(0.6, 0.32), Vector2(0.55, 0.15), 0.03, Color(1, 1, 1, 0.6))
		"pelt":
			_poly([Vector2(0.15, 0.3), Vector2(0.4, 0.22), Vector2(0.6, 0.22), Vector2(0.85, 0.3), Vector2(0.78, 0.55), Vector2(0.88, 0.78), Vector2(0.6, 0.72), Vector2(0.4, 0.72), Vector2(0.12, 0.78), Vector2(0.22, 0.55)], c)
			_ln(Vector2(0.35, 0.4), Vector2(0.65, 0.6), 0.03, d)
		"tusk":
			_poly([Vector2(0.25, 0.85), Vector2(0.3, 0.45), Vector2(0.5, 0.2), Vector2(0.78, 0.12), Vector2(0.6, 0.35), Vector2(0.5, 0.55), Vector2(0.5, 0.85)], c)
			_ln(Vector2(0.35, 0.75), Vector2(0.48, 0.3), 0.025, l)
		"ore":
			_poly([Vector2(0.15, 0.78), Vector2(0.2, 0.45), Vector2(0.42, 0.22), Vector2(0.7, 0.3), Vector2(0.86, 0.6), Vector2(0.78, 0.8)], d)
			_poly([Vector2(0.25, 0.72), Vector2(0.3, 0.48), Vector2(0.45, 0.32), Vector2(0.62, 0.4), Vector2(0.56, 0.65)], c)
			_circ(0.6, 0.36, 0.05, l)
			_circ(0.35, 0.6, 0.04, l)
		"wood":
			_poly([Vector2(0.15, 0.4), Vector2(0.85, 0.3), Vector2(0.88, 0.5), Vector2(0.18, 0.62)], c)
			_poly([Vector2(0.2, 0.62), Vector2(0.88, 0.5), Vector2(0.9, 0.7), Vector2(0.22, 0.82)], d)
			_circ(0.15, 0.51, 0.1, l)
		"insignia":
			_poly([Vector2(0.5, 0.12), Vector2(0.85, 0.3), Vector2(0.78, 0.7), Vector2(0.5, 0.9), Vector2(0.22, 0.7), Vector2(0.15, 0.3)], c)
			_poly([Vector2(0.4, 0.3), Vector2(0.5, 0.65), Vector2(0.6, 0.3), Vector2(0.5, 0.4)], Color(0.95, 0.9, 0.85))
		"shard", "gem":
			_poly([Vector2(0.5, 0.1), Vector2(0.8, 0.4), Vector2(0.62, 0.9), Vector2(0.38, 0.9), Vector2(0.2, 0.4)], c)
			_poly([Vector2(0.5, 0.1), Vector2(0.62, 0.9), Vector2(0.5, 0.6)], l)
			_poly([Vector2(0.2, 0.4), Vector2(0.5, 0.6), Vector2(0.38, 0.9)], d)
		"flower":
			for i in 5:
				var a := TAU * float(i) / 5.0
				_circ(0.5 + cos(a) * 0.2, 0.42 + sin(a) * 0.2, 0.13, c)
			_circ(0.5, 0.42, 0.09, Color(1.0, 0.9, 0.4))
			_ln(Vector2(0.5, 0.6), Vector2(0.5, 0.92), 0.04, Color(0.3, 0.6, 0.3))
		"honey":
			_poly([Vector2(0.5, 0.12), Vector2(0.78, 0.55), Vector2(0.72, 0.78), Vector2(0.5, 0.88), Vector2(0.28, 0.78), Vector2(0.22, 0.55)], c)
			_circ(0.42, 0.55, 0.07, l)
		"shell":
			_poly([Vector2(0.12, 0.7), Vector2(0.2, 0.4), Vector2(0.5, 0.18), Vector2(0.8, 0.4), Vector2(0.88, 0.7), Vector2(0.5, 0.85)], c)
			for x in [0.32, 0.5, 0.68]:
				_ln(Vector2(0.5, 0.82), Vector2(x, 0.3), 0.02, d)
		"fish":
			_poly([Vector2(0.12, 0.5), Vector2(0.35, 0.3), Vector2(0.65, 0.3), Vector2(0.78, 0.5), Vector2(0.65, 0.7), Vector2(0.35, 0.7)], c)
			_poly([Vector2(0.75, 0.5), Vector2(0.92, 0.3), Vector2(0.92, 0.7)], d)
			_circ(0.28, 0.45, 0.04, Color(0.05, 0.05, 0.05))
		"bone":
			_ln(Vector2(0.25, 0.75), Vector2(0.75, 0.25), 0.1, c)
			_circ(0.2, 0.7, 0.09, c)
			_circ(0.28, 0.82, 0.09, c)
			_circ(0.72, 0.18, 0.09, c)
			_circ(0.82, 0.28, 0.09, c)
		"scale":
			for r in 3:
				for k in 3:
					_circ(0.25 + k * 0.25 + (r % 2) * 0.12, 0.3 + r * 0.2, 0.11, c if (r + k) % 2 == 0 else d)
		"coin":
			_circ(0.5, 0.5, 0.36, d)
			_circ(0.5, 0.5, 0.29, c)
			_ln(Vector2(0.5, 0.3), Vector2(0.5, 0.7), 0.05, d)
		"key":
			_circ(0.3, 0.3, 0.16, c)
			_circ(0.3, 0.3, 0.07, bg)
			_ln(Vector2(0.4, 0.4), Vector2(0.85, 0.85), 0.07, c)
			_ln(Vector2(0.7, 0.7), Vector2(0.8, 0.6), 0.06, c)
		"bread":
			_poly([Vector2(0.1, 0.6), Vector2(0.2, 0.35), Vector2(0.5, 0.25), Vector2(0.8, 0.35), Vector2(0.9, 0.6), Vector2(0.7, 0.75), Vector2(0.3, 0.75)], c)
			for x in [0.35, 0.5, 0.65]:
				_ln(Vector2(x, 0.38), Vector2(x + 0.05, 0.55), 0.03, d)
		"cheese":
			_poly([Vector2(0.12, 0.7), Vector2(0.5, 0.25), Vector2(0.88, 0.5), Vector2(0.88, 0.75), Vector2(0.12, 0.75)], c)
			_circ(0.35, 0.65, 0.05, d)
			_circ(0.65, 0.62, 0.04, d)
		"cloth":
			_poly([Vector2(0.15, 0.25), Vector2(0.5, 0.2), Vector2(0.85, 0.28), Vector2(0.78, 0.6), Vector2(0.86, 0.85), Vector2(0.5, 0.78), Vector2(0.15, 0.85), Vector2(0.22, 0.55)], c)
			_ln(Vector2(0.3, 0.4), Vector2(0.7, 0.45), 0.02, d)
		_:
			_circ(0.5, 0.5, 0.3, c)
