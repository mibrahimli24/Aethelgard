extends RefCounted
## Art: procedural "sprite" builders. The game has no image assets -- every character and prop is
## assembled from Polygon2D primitives. Each builder returns a Node2D whose origin is at the
## object's FEET (so y-sorting and collisions line up) and which faces +x where facing matters.

static func _poly(parent: Node, pts: PackedVector2Array, color: Color, pos: Vector2 = Vector2.ZERO, z: int = 0) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = pts
	p.color = color
	p.position = pos
	p.z_index = mini(z, 0)
	parent.add_child(p)
	return p


static func ellipse(rx: float, ry: float, points: int = 14) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points:
		var a: float = TAU * float(i) / float(points)
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func rect(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])


static func tri(a: Vector2, b: Vector2, c: Vector2) -> PackedVector2Array:
	return PackedVector2Array([a, b, c])


static func shade(c: Color, amount: float) -> Color:
	return Color(clampf(c.r * amount, 0.0, 1.0), clampf(c.g * amount, 0.0, 1.0), clampf(c.b * amount, 0.0, 1.0), c.a)


static func shadow(parent: Node, rx: float, ry: float, alpha: float = 0.32) -> Polygon2D:
	return _poly(parent, ellipse(rx, ry), Color(0, 0, 0, alpha), Vector2.ZERO, -1)


# ---------------------------------------------------------------------------
# Humanoids (player classes, NPCs, bandits, the boss)
# ---------------------------------------------------------------------------

## cfg keys: tunic, pants, skin, hair, eyes, hat ("none"|"hood"|"pointy"|"helm"|"bandana"|"cap"|"horned"),
## hat_color, weapon ("none"|"sword"|"bow"|"staff"|"dagger"|"flask"|"axe"|"hammer"|"crook"),
## cape (Color or absent), scale.
## Returns {root, body, legs[2], eyes, head, weapon, arm_l, arm_r, shadow, weapon_kind, cape?, hat?}.
## cape / hat are Node2D holders pivoted at the neck / crown so Anim can spring them.
static func humanoid(parent: Node, cfg: Dictionary) -> Dictionary:
	var root := Node2D.new()
	root.name = "Visual"
	parent.add_child(root)
	var s: float = float(cfg.get("scale", 1.0))
	root.scale = Vector2(s, s)
	var tunic: Color = cfg.get("tunic", Color(0.5, 0.5, 0.6))
	var pants: Color = cfg.get("pants", Color(0.3, 0.25, 0.2))
	var skin: Color = cfg.get("skin", Color(0.93, 0.76, 0.6))
	var hair: Color = cfg.get("hair", Color(0.3, 0.2, 0.1))
	var parts := {"root": root}

	parts["shadow"] = shadow(root, 11, 4.5)
	if cfg.has("cape"):
		var cape_c: Color = cfg["cape"]
		var cape := Node2D.new()
		cape.position = Vector2(0, -23)
		root.add_child(cape)
		_poly(cape, PackedVector2Array([Vector2(-7, 0), Vector2(7, 0), Vector2(10, 20), Vector2(-10, 20)]), cape_c)
		_poly(cape, PackedVector2Array([Vector2(-10, 20), Vector2(10, 20), Vector2(9, 17), Vector2(-9, 17)]), shade(cape_c, 0.7))
		parts["cape"] = cape

	var legs: Array = []
	for lx in [-3.5, 3.5]:
		var leg := _poly(root, rect(-2.5, 0, 5, 9), pants, Vector2(lx, -9))
		_poly(leg, rect(-1.0, 6, 7, 3), shade(pants, 0.6), Vector2(-2.5, 0))
		legs.append(leg)

	var body := Node2D.new()
	root.add_child(body)
	_poly(body, PackedVector2Array([Vector2(-7, -23), Vector2(7, -23), Vector2(6.5, -9), Vector2(-6.5, -9)]), tunic)
	_poly(body, rect(-6.5, -12, 13, 2.5), shade(tunic, 0.6))
	_poly(body, PackedVector2Array([Vector2(-7, -23), Vector2(-2, -23), Vector2(-3, -20)]), shade(tunic, 1.2))
	var arm_l := _poly(body, rect(-2, 0, 4, 10), shade(tunic, 0.85), Vector2(-9, -22))
	var arm_r := _poly(body, rect(-2, 0, 4, 10), shade(tunic, 0.85), Vector2(9, -22))
	_poly(arm_l, ellipse(2.2, 2.2, 8), skin, Vector2(0, 11))
	_poly(arm_r, ellipse(2.2, 2.2, 8), skin, Vector2(0, 11))

	var head := Node2D.new()
	head.position = Vector2(0, -28)
	body.add_child(head)
	_poly(head, ellipse(6.2, 6.2, 14), skin)
	_poly(head, PackedVector2Array([Vector2(-6.4, -1), Vector2(-5, -5.5), Vector2(0, -7), Vector2(5, -5.5), Vector2(6.4, -1), Vector2(3, -3.5), Vector2(-3, -3.5)]), hair)
	var eyes := Node2D.new()
	head.add_child(eyes)
	var eye_c: Color = cfg.get("eyes", Color(0.1, 0.08, 0.08))
	_poly(eyes, ellipse(1.1, 1.4, 6), eye_c, Vector2(-2.3, 0.5))
	_poly(eyes, ellipse(1.1, 1.4, 6), eye_c, Vector2(2.3, 0.5))

	var hat_color: Color = cfg.get("hat_color", tunic)
	var hat_kind: String = str(cfg.get("hat", "none"))
	if hat_kind != "none":
		var hat := Node2D.new()
		hat.position = Vector2(0, -3)
		head.add_child(hat)
		parts["hat"] = hat
		var o := Vector2(0, 3)
		match hat_kind:
			"hood":
				_poly(hat, PackedVector2Array([Vector2(-7.5, 1), Vector2(-6, -6), Vector2(0, -9.5), Vector2(6, -6), Vector2(7.5, 1), Vector2(4.5, -3), Vector2(-4.5, -3)]), hat_color, o)
			"pointy":
				_poly(hat, PackedVector2Array([Vector2(-8.5, -3), Vector2(8.5, -3), Vector2(2, -5), Vector2(1, -17), Vector2(-3, -5)]), hat_color, o)
				_poly(hat, rect(-6, -4.5, 12, 2), shade(hat_color, 0.7), o)
			"helm":
				_poly(hat, PackedVector2Array([Vector2(-6.8, 0), Vector2(-6.5, -6), Vector2(0, -8), Vector2(6.5, -6), Vector2(6.8, 0), Vector2(4, -2.5), Vector2(-4, -2.5)]), hat_color, o)
				_poly(hat, rect(-1, -7, 2, 6), shade(hat_color, 1.3), o)
			"bandana":
				_poly(hat, rect(-6.4, -4.5, 12.8, 3), hat_color, o)
				_poly(hat, tri(Vector2(6, -4), Vector2(11, -1), Vector2(7, -1.5)), hat_color, o)
			"cap":
				_poly(hat, PackedVector2Array([Vector2(-6.5, -2), Vector2(-5, -7), Vector2(5, -7), Vector2(6.5, -2), Vector2(9, -1.5), Vector2(6, -3.5)]), hat_color, o)
			"horned":
				_poly(hat, PackedVector2Array([Vector2(-6.8, 0), Vector2(-6.5, -6), Vector2(0, -8), Vector2(6.5, -6), Vector2(6.8, 0), Vector2(4, -2.5), Vector2(-4, -2.5)]), hat_color, o)
				_poly(hat, PackedVector2Array([Vector2(-6, -5), Vector2(-10, -13), Vector2(-4, -7)]), Color(0.9, 0.88, 0.8), o)
				_poly(hat, PackedVector2Array([Vector2(6, -5), Vector2(10, -13), Vector2(4, -7)]), Color(0.9, 0.88, 0.8), o)

	var weapon := Node2D.new()
	weapon.position = Vector2(0, -15)
	root.add_child(weapon)
	var wkind: String = str(cfg.get("weapon", "none"))
	_build_weapon(weapon, wkind, cfg.get("weapon_color", Color(0.85, 0.87, 0.92)))

	parts["body"] = body
	parts["legs"] = legs
	parts["eyes"] = eyes
	parts["head"] = head
	parts["weapon"] = weapon
	parts["weapon_kind"] = wkind
	parts["arm_l"] = arm_l
	parts["arm_r"] = arm_r
	return parts


## Weapons are drawn pointing along +x from the pivot; the owner rotates the pivot to face.
static func _build_weapon(w: Node2D, kind: String, metal: Color) -> void:
	var wood := Color(0.45, 0.3, 0.16)
	match kind:
		"sword":
			_poly(w, rect(10, -1.4, 17, 2.8), metal)
			_poly(w, tri(Vector2(27, -1.4), Vector2(31, 0), Vector2(27, 1.4)), metal)
			_poly(w, rect(8, -4, 2.5, 8), Color(0.75, 0.6, 0.2))
			_poly(w, rect(4, -1, 4, 2), wood)
		"dagger":
			_poly(w, rect(9, -1, 9, 2), metal)
			_poly(w, tri(Vector2(18, -1), Vector2(22, 0), Vector2(18, 1)), metal)
			_poly(w, rect(7, -2.5, 2, 5), Color(0.3, 0.3, 0.35))
		"bow":
			var arc := PackedVector2Array()
			for i in 9:
				var a: float = lerpf(-1.2, 1.2, float(i) / 8.0)
				arc.append(Vector2(cos(a) * 3.5 + 11, sin(a) * 11))
			var line := Line2D.new()
			line.points = arc
			line.width = 2.2
			line.default_color = wood
			w.add_child(line)
			var string := Line2D.new()
			string.points = PackedVector2Array([arc[0], arc[arc.size() - 1]])
			string.width = 0.8
			string.default_color = Color(0.9, 0.9, 0.85)
			w.add_child(string)
			var arrow := Node2D.new()
			arrow.visible = false
			w.add_child(arrow)
			_poly(arrow, rect(12.3, -0.5, 14, 1.0), Color(0.6, 0.45, 0.25))
			_poly(arrow, tri(Vector2(26.3, -2), Vector2(30.5, 0), Vector2(26.3, 2)), Color(0.8, 0.82, 0.88))
			_poly(arrow, tri(Vector2(12.3, 0), Vector2(15.5, -2.4), Vector2(15.5, 0)), Color(0.85, 0.85, 0.8))
			_poly(arrow, tri(Vector2(12.3, 0), Vector2(15.5, 2.4), Vector2(15.5, 0)), Color(0.85, 0.85, 0.8))
			w.set_meta("string", string)
			w.set_meta("arrow", arrow)
		"staff":
			_poly(w, rect(-6, -1.2, 30, 2.4), wood)
			var orb := Node2D.new()
			orb.position = Vector2(26, 0)
			w.add_child(orb)
			_poly(orb, ellipse(4, 4, 10), Color(0.5, 0.75, 1.0))
			_poly(orb, ellipse(2, 2, 8), Color(0.9, 0.97, 1.0))
			w.set_meta("orb", orb)
		"flask":
			_poly(w, rect(9, -2, 5, 6), Color(0.5, 0.9, 0.5, 0.9), Vector2(0, -2))
			_poly(w, ellipse(4.5, 4.5, 10), Color(0.5, 0.9, 0.5, 0.9), Vector2(14, 0))
			_poly(w, rect(16, -1, 4, 2), Color(0.8, 0.8, 0.85), Vector2(0, 0))
		"axe":
			_poly(w, rect(4, -1.4, 22, 2.8), wood)
			_poly(w, PackedVector2Array([Vector2(20, -1), Vector2(28, -9), Vector2(30, -2), Vector2(30, 6), Vector2(22, 1)]), metal)
		"hammer":
			_poly(w, rect(4, -1.4, 18, 2.8), wood)
			_poly(w, rect(20, -6, 8, 12), Color(0.45, 0.45, 0.5))
		"crook":
			_poly(w, rect(-4, -1.2, 28, 2.4), wood)
			var hook := Line2D.new()
			hook.points = PackedVector2Array([Vector2(24, 0), Vector2(28, -3), Vector2(28, -7)])
			hook.width = 2.2
			hook.default_color = wood
			w.add_child(hook)


# ---------------------------------------------------------------------------
# Creatures
# ---------------------------------------------------------------------------

## Four-legged beast built facing +x. cfg: color, belly, eye, scale, kind ("wolf"|"boar")
static func beast(parent: Node, cfg: Dictionary) -> Dictionary:
	var root := Node2D.new()
	root.name = "Visual"
	parent.add_child(root)
	var s: float = float(cfg.get("scale", 1.0))
	root.scale = Vector2(s, s)
	var col: Color = cfg.get("color", Color(0.45, 0.45, 0.5))
	var kind: String = cfg.get("kind", "wolf")
	var eye: Color = cfg.get("eye", Color(1, 0.2, 0.15))
	var legs: Array = []
	shadow(root, 16, 5)
	if kind == "boar":
		for x in [-9.0, -3.0, 6.0, 11.0]:
			legs.append(_poly(root, rect(-1.8, 0, 3.6, 7), shade(col, 0.6), Vector2(x, -7)))
		var body := Node2D.new()
		root.add_child(body)
		_poly(body, ellipse(15, 9.5, 16), col, Vector2(0, -12))
		_poly(body, PackedVector2Array([Vector2(-12, -19), Vector2(-4, -22), Vector2(6, -22), Vector2(12, -19), Vector2(4, -18), Vector2(-6, -18)]), shade(col, 0.55), Vector2.ZERO, 1)
		_poly(body, ellipse(8, 6, 12), Color(cfg.get("belly", col.lightened(0.15))), Vector2(-1, -9))
		_poly(body, ellipse(7, 6.5, 12), shade(col, 1.1), Vector2(14, -12), 1)
		_poly(body, ellipse(3.5, 3, 8), Color(0.75, 0.55, 0.55), Vector2(20, -10), 2)
		_poly(body, tri(Vector2(17, -8), Vector2(23, -14), Vector2(19, -6)), Color(0.95, 0.92, 0.8), Vector2.ZERO, 2)
		_poly(body, tri(Vector2(17, -8), Vector2(22, -3), Vector2(19, -8)), Color(0.95, 0.92, 0.8), Vector2.ZERO, 2)
		_poly(body, tri(Vector2(10, -18), Vector2(13, -24), Vector2(15, -17)), shade(col, 0.6), Vector2.ZERO, 2)
		_poly(body, ellipse(1.3, 1.3, 6), eye, Vector2(15, -14), 3)
		_poly(root, ellipse(2.5, 2.5, 6), shade(col, 0.5), Vector2(-15, -14))
		return {"root": root, "body": body, "legs": legs}
	# wolf
	for x in [-10.0, -5.0, 7.0, 12.0]:
		legs.append(_poly(root, rect(-1.6, 0, 3.2, 9), shade(col, 0.65), Vector2(x, -9)))
	var wb := Node2D.new()
	root.add_child(wb)
	var tail := _poly(wb, PackedVector2Array([Vector2(-12, -15), Vector2(-22, -20), Vector2(-23, -16), Vector2(-13, -11)]), shade(col, 0.85), Vector2.ZERO, -1)
	_poly(wb, ellipse(14, 7.5, 16), col, Vector2(0, -14))
	_poly(wb, ellipse(8, 4.5, 12), Color(cfg.get("belly", col.lightened(0.25))), Vector2(1, -11))
	_poly(wb, PackedVector2Array([Vector2(-10, -20), Vector2(-2, -23), Vector2(8, -21), Vector2(0, -19)]), shade(col, 0.6), Vector2.ZERO, 1)
	_poly(wb, ellipse(6.5, 5.5, 12), shade(col, 1.08), Vector2(14, -17), 1)
	_poly(wb, PackedVector2Array([Vector2(17, -19), Vector2(26, -16), Vector2(25, -14), Vector2(17, -13)]), shade(col, 1.15), Vector2.ZERO, 2)
	_poly(wb, ellipse(1.6, 1.6, 6), Color(0.08, 0.05, 0.05), Vector2(25, -16), 3)
	_poly(wb, tri(Vector2(11, -21), Vector2(12, -28), Vector2(16, -21)), shade(col, 0.7), Vector2.ZERO, 2)
	_poly(wb, tri(Vector2(15, -21), Vector2(18, -27), Vector2(19, -20)), shade(col, 0.7), Vector2.ZERO, 2)
	_poly(wb, ellipse(1.4, 1.4, 6), eye, Vector2(18, -18), 3)
	return {"root": root, "body": wb, "legs": legs, "tail": tail}


## Hovering ghost-light. cfg: color
static func wisp(parent: Node, cfg: Dictionary) -> Dictionary:
	var root := Node2D.new()
	root.name = "Visual"
	parent.add_child(root)
	var col: Color = cfg.get("color", Color(0.5, 0.95, 1.0))
	shadow(root, 8, 3, 0.2)
	var body := Node2D.new()
	body.position = Vector2(0, -22)
	root.add_child(body)
	_poly(body, ellipse(13, 13, 16), Color(col.r, col.g, col.b, 0.15))
	_poly(body, ellipse(9, 9, 14), Color(col.r, col.g, col.b, 0.3))
	_poly(body, PackedVector2Array([Vector2(0, -9), Vector2(6, -2), Vector2(4, 8), Vector2(0, 14), Vector2(-4, 8), Vector2(-6, -2)]), Color(col.r, col.g, col.b, 0.85), Vector2.ZERO, 1)
	_poly(body, ellipse(3.6, 3.6, 10), Color(1, 1, 1, 0.95), Vector2(0, -1), 2)
	return {"root": root, "body": body, "legs": []}


# ---------------------------------------------------------------------------
# Props
# ---------------------------------------------------------------------------

static func pine(parent: Node, scale_factor: float = 1.0, tint: float = 1.0) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(scale_factor, scale_factor)
	shadow(n, 16, 5, 0.28)
	_poly(n, rect(-3, -14, 6, 14), Color(0.35, 0.22, 0.12))
	var g1 := Color(0.13, 0.33, 0.17)
	var g2 := Color(0.17, 0.42, 0.21)
	var g3 := Color(0.24, 0.52, 0.27)
	_poly(n, tri(Vector2(-19, -12), Vector2(19, -12), Vector2(0, -42)), shade(g1, tint), Vector2.ZERO, 1)
	_poly(n, tri(Vector2(-15, -26), Vector2(15, -26), Vector2(0, -54)), shade(g2, tint), Vector2.ZERO, 1)
	_poly(n, tri(Vector2(-11, -40), Vector2(11, -40), Vector2(0, -66)), shade(g3, tint), Vector2.ZERO, 1)
	_poly(n, tri(Vector2(-11, -40), Vector2(0, -40), Vector2(0, -66)), shade(g3, tint * 1.12), Vector2.ZERO, 2)
	return n


static func oak(parent: Node, scale_factor: float = 1.0, tint: float = 1.0) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(scale_factor, scale_factor)
	shadow(n, 20, 6, 0.28)
	_poly(n, PackedVector2Array([Vector2(-4, 0), Vector2(-3, -20), Vector2(3, -20), Vector2(4, 0)]), Color(0.4, 0.27, 0.15))
	var base := Color(0.2, 0.45, 0.18)
	_poly(n, ellipse(20, 15, 14), shade(base, 0.8 * tint), Vector2(-4, -32), 1)
	_poly(n, ellipse(19, 15, 14), shade(base, 0.9 * tint), Vector2(7, -30), 1)
	_poly(n, ellipse(20, 17, 14), shade(base, 1.0 * tint), Vector2(0, -42), 2)
	_poly(n, ellipse(11, 8, 10), shade(base, 1.25 * tint), Vector2(-5, -47), 3)
	return n


static func dead_tree(parent: Node, scale_factor: float = 1.0) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(scale_factor, scale_factor)
	shadow(n, 12, 4, 0.25)
	var bark := Color(0.28, 0.22, 0.2)
	_poly(n, PackedVector2Array([Vector2(-4, 0), Vector2(-2, -34), Vector2(2, -34), Vector2(4, 0)]), bark)
	for b in [[Vector2(0, -22), Vector2(-16, -36)], [Vector2(0, -28), Vector2(14, -44)], [Vector2(0, -34), Vector2(-6, -50)], [Vector2(-8, -30), Vector2(-20, -32)]]:
		var l := Line2D.new()
		l.points = PackedVector2Array([b[0], b[1]])
		l.width = 3.0
		l.default_color = bark
		l.z_index = 1
		n.add_child(l)
	return n


static func rock(parent: Node, scale_factor: float = 1.0, tint: float = 1.0) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(scale_factor, scale_factor)
	shadow(n, 16, 5, 0.3)
	var base := Color(0.5, 0.5, 0.52)
	_poly(n, PackedVector2Array([Vector2(-14, 0), Vector2(-16, -9), Vector2(-8, -17), Vector2(4, -19), Vector2(15, -11), Vector2(16, 0)]), shade(base, 0.85 * tint))
	_poly(n, PackedVector2Array([Vector2(-8, -17), Vector2(4, -19), Vector2(15, -11), Vector2(2, -9), Vector2(-9, -10)]), shade(base, 1.1 * tint), Vector2.ZERO, 1)
	_poly(n, PackedVector2Array([Vector2(-2, -19), Vector2(4, -19), Vector2(8, -15), Vector2(0, -14)]), shade(base, 1.3 * tint), Vector2.ZERO, 2)
	return n


static func bush(parent: Node, scale_factor: float = 1.0, tint: float = 1.0) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(scale_factor, scale_factor)
	shadow(n, 13, 4, 0.25)
	var base := Color(0.2, 0.42, 0.17)
	_poly(n, ellipse(10, 7, 12), shade(base, 0.8 * tint), Vector2(-6, -6))
	_poly(n, ellipse(10, 7, 12), shade(base, 0.95 * tint), Vector2(6, -6), 1)
	_poly(n, ellipse(10, 8, 12), shade(base, 1.1 * tint), Vector2(0, -11), 2)
	return n


static func house(parent: Node, wall: Color, roof: Color, width: float = 70.0, height: float = 42.0) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	var hw: float = width * 0.5
	shadow(n, hw + 8, 8, 0.28)
	_poly(n, rect(-hw, -height, width, height), wall)
	_poly(n, rect(-hw, -8, width, 8), shade(wall, 0.72))
	_poly(n, rect(-9, -26, 18, 26), Color(0.3, 0.19, 0.1), Vector2.ZERO, 1)
	_poly(n, ellipse(1.4, 1.4, 6), Color(0.85, 0.7, 0.3), Vector2(5, -13), 2)
	_poly(n, rect(-hw + 8, -height + 12, 12, 12), Color(0.95, 0.85, 0.5), Vector2.ZERO, 1)
	_poly(n, rect(hw - 20, -height + 12, 12, 12), Color(0.95, 0.85, 0.5), Vector2.ZERO, 1)
	_poly(n, PackedVector2Array([Vector2(-hw - 8, -height + 2), Vector2(hw + 8, -height + 2), Vector2(hw - 6, -height - 26), Vector2(-hw + 6, -height - 26)]), roof, Vector2.ZERO, 3)
	_poly(n, PackedVector2Array([Vector2(-hw - 8, -height + 2), Vector2(hw + 8, -height + 2), Vector2(hw + 6, -height - 3), Vector2(-hw - 6, -height - 3)]), shade(roof, 0.7), Vector2.ZERO, 4)
	return n


static func campfire(parent: Node) -> Dictionary:
	var n := Node2D.new()
	parent.add_child(n)
	shadow(n, 14, 5, 0.3)
	for i in 8:
		var a: float = TAU * float(i) / 8.0
		_poly(n, ellipse(3.5, 3, 6), Color(0.45, 0.45, 0.48), Vector2(cos(a) * 11, sin(a) * 5 - 2))
	var l1 := Line2D.new()
	l1.points = PackedVector2Array([Vector2(-9, -2), Vector2(9, -6)])
	l1.width = 4.0
	l1.default_color = Color(0.4, 0.26, 0.14)
	n.add_child(l1)
	var l2 := Line2D.new()
	l2.points = PackedVector2Array([Vector2(9, -2), Vector2(-9, -6)])
	l2.width = 4.0
	l2.default_color = Color(0.36, 0.22, 0.12)
	n.add_child(l2)
	var flame := Node2D.new()
	flame.position = Vector2(0, -5)
	flame.z_index = 1
	n.add_child(flame)
	_poly(flame, PackedVector2Array([Vector2(0, -22), Vector2(8, -8), Vector2(6, 0), Vector2(-6, 0), Vector2(-8, -8)]), Color(0.95, 0.4, 0.1))
	_poly(flame, PackedVector2Array([Vector2(0, -16), Vector2(5, -6), Vector2(3, 0), Vector2(-3, 0), Vector2(-5, -6)]), Color(1.0, 0.75, 0.2), Vector2.ZERO, 1)
	_poly(flame, PackedVector2Array([Vector2(0, -9), Vector2(2.5, -3), Vector2(-2.5, -3)]), Color(1.0, 0.95, 0.7), Vector2.ZERO, 2)
	return {"root": n, "flame": flame}


static func tent(parent: Node, color: Color) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	shadow(n, 34, 8, 0.3)
	_poly(n, PackedVector2Array([Vector2(-32, 0), Vector2(0, -38), Vector2(32, 0)]), color)
	_poly(n, PackedVector2Array([Vector2(0, -38), Vector2(32, 0), Vector2(8, 0)]), shade(color, 0.78), Vector2.ZERO, 1)
	_poly(n, PackedVector2Array([Vector2(-7, 0), Vector2(0, -20), Vector2(7, 0)]), Color(0.12, 0.08, 0.06), Vector2.ZERO, 2)
	return n


static func well(parent: Node) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	shadow(n, 16, 6, 0.3)
	_poly(n, ellipse(13, 7, 14), Color(0.5, 0.5, 0.53), Vector2(0, -8))
	_poly(n, ellipse(9, 4.5, 14), Color(0.08, 0.12, 0.2), Vector2(0, -10), 1)
	_poly(n, rect(-14, -8, 28, 8), Color(0.42, 0.42, 0.46), Vector2.ZERO, 2)
	_poly(n, rect(-13, -30, 3, 24), Color(0.4, 0.26, 0.14), Vector2.ZERO, 3)
	_poly(n, rect(10, -30, 3, 24), Color(0.4, 0.26, 0.14), Vector2.ZERO, 3)
	_poly(n, PackedVector2Array([Vector2(-17, -30), Vector2(17, -30), Vector2(0, -42)]), Color(0.55, 0.3, 0.2), Vector2.ZERO, 4)
	return n


static func fence(parent: Node, length: float) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	var posts: int = int(length / 16.0) + 1
	for i in posts:
		_poly(n, rect(-1.5, -16, 3, 16), Color(0.42, 0.28, 0.16), Vector2(float(i) * 16.0, 0), 1)
	_poly(n, rect(0, -13, length, 2.5), Color(0.5, 0.35, 0.2), Vector2.ZERO, 0)
	_poly(n, rect(0, -7, length, 2.5), Color(0.5, 0.35, 0.2), Vector2.ZERO, 0)
	return n


static func waystone(parent: Node) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	shadow(n, 12, 4, 0.3)
	_poly(n, PackedVector2Array([Vector2(-9, 0), Vector2(-8, -28), Vector2(0, -34), Vector2(8, -28), Vector2(9, 0)]), Color(0.42, 0.44, 0.5))
	_poly(n, PackedVector2Array([Vector2(-1, -30), Vector2(3, -20), Vector2(-1, -10), Vector2(-4, -20)]), Color(0.5, 0.85, 0.95, 0.85), Vector2.ZERO, 1)
	return n


static func crate_chest(parent: Node) -> Dictionary:
	var n := Node2D.new()
	parent.add_child(n)
	shadow(n, 13, 4, 0.3)
	var lid := Node2D.new()
	lid.position = Vector2(0, -12)
	n.add_child(lid)
	_poly(n, rect(-11, -12, 22, 12), Color(0.5, 0.32, 0.16))
	_poly(n, rect(-11, -7, 22, 2), Color(0.75, 0.6, 0.25), Vector2.ZERO, 1)
	_poly(lid, PackedVector2Array([Vector2(-11, 0), Vector2(-9, -8), Vector2(9, -8), Vector2(11, 0)]), Color(0.58, 0.38, 0.2), Vector2.ZERO, 2)
	_poly(lid, rect(-2, -3, 4, 5), Color(0.85, 0.7, 0.3), Vector2.ZERO, 3)
	return {"root": n, "lid": lid}


static func flower(parent: Node, color: Color) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	_poly(n, rect(-0.5, -6, 1, 6), Color(0.2, 0.45, 0.2))
	for i in 5:
		var a: float = TAU * float(i) / 5.0
		_poly(n, ellipse(1.6, 1.6, 6), color, Vector2(cos(a) * 2.2, -7 + sin(a) * 2.2))
	_poly(n, ellipse(1.2, 1.2, 6), Color(0.95, 0.85, 0.3), Vector2(0, -7), 1)
	return n
