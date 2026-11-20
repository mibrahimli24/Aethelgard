extends RefCounted
## ArtBiome: Polygon2D builders for the biome props and creatures added with the big world.
## Same conventions as Art.gd: origin at FEET, builders return the Node2D (creatures return the
## Art.beast-shaped dict {root, body, legs[], tail?}). Swaying parts (canopies, reeds, grass) live
## under their own child Node2D joined to group "swayers" with meta "sway" (radians).
##
## LEAD: creature art ids to dispatch in Enemy._build_visual:
##   "scorpion", "frostbear", "lurker", "golem", "crab"  ->  ArtBiome.build_creature(self, art, cfg)
##   cfg = {"color": Color, "eye": Color, "scale": float, "glow": Color (golem only)}
##   (use ArtBiome.is_creature(art) to test; treat result as _visual_kind "beast").

const Art = preload("res://scripts/Art.gd")

const CREATURES := ["scorpion", "frostbear", "lurker", "golem", "crab"]


static func is_creature(art: String) -> bool:
	return art in CREATURES


static func build_creature(parent: Node, art: String, cfg: Dictionary) -> Dictionary:
	match art:
		"scorpion":
			return scorpion(parent, cfg)
		"frostbear":
			return frostbear(parent, cfg)
		"lurker":
			return lurker(parent, cfg)
		"golem":
			return golem(parent, cfg)
		"crab":
			return crab(parent, cfg)
	return Art.beast(parent, cfg)


static func _sway(parent: Node2D, pivot_y: float, amp: float) -> Node2D:
	var h := Node2D.new()
	h.position = Vector2(0, pivot_y)
	parent.add_child(h)
	h.add_to_group("swayers")
	h.set_meta("sway", amp)
	return h


static func _root(parent: Node, cfg: Dictionary) -> Node2D:
	var root := Node2D.new()
	root.name = "Visual"
	parent.add_child(root)
	var s: float = float(cfg.get("scale", 1.0))
	root.scale = Vector2(s, s)
	return root


# ---------------------------------------------------------------------------
# Creatures
# ---------------------------------------------------------------------------

static func scorpion(parent: Node, cfg: Dictionary) -> Dictionary:
	var root := _root(parent, cfg)
	var col: Color = cfg.get("color", Color(0.6, 0.45, 0.2))
	var eye: Color = cfg.get("eye", Color(0.9, 0.1, 0.1))
	Art.shadow(root, 18, 6)
	var legs: Array = []
	for x in [-8.0, -2.0, 4.0, 10.0]:
		legs.append(Art._poly(root, Art.rect(-1.0, 0, 2.0, 8), Art.shade(col, 0.55), Vector2(x, -6)))
	var body := Node2D.new()
	root.add_child(body)
	var tail := Node2D.new()
	body.add_child(tail)
	Art._poly(tail, PackedVector2Array([Vector2(-10, -10), Vector2(-20, -16), Vector2(-24, -28), Vector2(-18, -36), Vector2(-14, -33), Vector2(-18, -27), Vector2(-15, -18), Vector2(-8, -8)]), Art.shade(col, 0.9))
	Art._poly(tail, Art.tri(Vector2(-18, -36), Vector2(-10, -34), Vector2(-14, -30)), Color(0.85, 0.2, 0.15))
	Art._poly(body, Art.ellipse(13, 7, 14), col, Vector2(0, -9))
	Art._poly(body, Art.ellipse(8, 4.5, 10), Art.shade(col, 1.2), Vector2(-1, -11))
	Art._poly(body, Art.ellipse(6, 5.5, 10), Art.shade(col, 1.05), Vector2(13, -9))
	Art._poly(body, PackedVector2Array([Vector2(16, -12), Vector2(26, -17), Vector2(27, -11), Vector2(20, -9)]), Art.shade(col, 1.15))
	Art._poly(body, PackedVector2Array([Vector2(16, -6), Vector2(26, -3), Vector2(27, -8), Vector2(20, -8)]), Art.shade(col, 1.15))
	Art._poly(body, Art.ellipse(1.2, 1.2, 6), eye, Vector2(17, -12))
	return {"root": root, "body": body, "legs": legs, "tail": tail}


static func frostbear(parent: Node, cfg: Dictionary) -> Dictionary:
	var root := _root(parent, cfg)
	var col: Color = cfg.get("color", Color(0.85, 0.9, 0.95))
	var eye: Color = cfg.get("eye", Color(0.2, 0.6, 1.0))
	Art.shadow(root, 22, 7)
	var legs: Array = []
	for x in [-12.0, -5.0, 8.0, 15.0]:
		legs.append(Art._poly(root, Art.rect(-3, 0, 6, 10), Art.shade(col, 0.7), Vector2(x, -10)))
	var body := Node2D.new()
	root.add_child(body)
	Art._poly(body, Art.ellipse(19, 12, 16), col, Vector2(0, -17))
	Art._poly(body, PackedVector2Array([Vector2(-14, -27), Vector2(-2, -31), Vector2(10, -27), Vector2(0, -24)]), Art.shade(col, 1.1))
	Art._poly(body, Art.ellipse(9, 7, 12), Art.shade(col, 0.88), Vector2(-2, -12))
	Art._poly(body, Art.ellipse(8, 7.5, 12), Art.shade(col, 1.05), Vector2(19, -21))
	Art._poly(body, Art.ellipse(4.5, 3.4, 8), Art.shade(col, 0.8), Vector2(26, -19))
	Art._poly(body, Art.ellipse(1.8, 1.4, 6), Color(0.1, 0.1, 0.12), Vector2(29, -20))
	Art._poly(body, Art.ellipse(3, 3, 8), Art.shade(col, 0.8), Vector2(15, -28))
	Art._poly(body, Art.ellipse(3, 3, 8), Art.shade(col, 0.8), Vector2(22, -28))
	Art._poly(body, Art.ellipse(1.5, 1.5, 6), eye, Vector2(22, -23))
	Art._poly(body, Art.tri(Vector2(25, -16), Vector2(27, -11), Vector2(23, -15)), Color(0.95, 0.95, 0.9))
	return {"root": root, "body": body, "legs": legs}


static func lurker(parent: Node, cfg: Dictionary) -> Dictionary:
	var root := _root(parent, cfg)
	var col: Color = cfg.get("color", Color(0.3, 0.42, 0.22))
	var eye: Color = cfg.get("eye", Color(1.0, 0.85, 0.2))
	Art.shadow(root, 17, 6)
	var legs: Array = []
	legs.append(Art._poly(root, Art.rect(-2.5, 0, 5, 8), Art.shade(col, 0.6), Vector2(-9, -8)))
	legs.append(Art._poly(root, Art.rect(-2.5, 0, 5, 8), Art.shade(col, 0.6), Vector2(-3, -8)))
	legs.append(Art._poly(root, Art.rect(-2, 0, 4, 8), Art.shade(col, 0.6), Vector2(9, -8)))
	legs.append(Art._poly(root, Art.rect(-2, 0, 4, 8), Art.shade(col, 0.6), Vector2(14, -8)))
	var body := Node2D.new()
	root.add_child(body)
	Art._poly(body, Art.ellipse(15, 9, 14), col, Vector2(-1, -13))
	Art._poly(body, Art.ellipse(10, 5.5, 10), Color(0.62, 0.68, 0.4), Vector2(0, -9))
	for p in [Vector2(-8, -19), Vector2(-1, -21), Vector2(6, -19)]:
		Art._poly(body, Art.ellipse(2.2, 1.6, 6), Art.shade(col, 0.65), p)
	Art._poly(body, Art.ellipse(8, 6.5, 12), Art.shade(col, 1.1), Vector2(14, -14))
	Art._poly(body, PackedVector2Array([Vector2(14, -10), Vector2(24, -11), Vector2(24, -8), Vector2(15, -7)]), Color(0.55, 0.15, 0.15))
	Art._poly(body, Art.ellipse(3, 3, 8), Color(0.9, 0.95, 0.7), Vector2(13, -21))
	Art._poly(body, Art.ellipse(3, 3, 8), Color(0.9, 0.95, 0.7), Vector2(19, -21))
	Art._poly(body, Art.ellipse(1.4, 1.8, 6), eye, Vector2(14, -21))
	Art._poly(body, Art.ellipse(1.4, 1.8, 6), eye, Vector2(20, -21))
	return {"root": root, "body": body, "legs": legs}


static func golem(parent: Node, cfg: Dictionary) -> Dictionary:
	var root := _root(parent, cfg)
	var col: Color = cfg.get("color", Color(0.5, 0.5, 0.52))
	var glow: Color = cfg.get("glow", Color(1.0, 0.45, 0.1))
	var eye: Color = cfg.get("eye", glow)
	Art.shadow(root, 22, 7)
	var legs: Array = []
	legs.append(Art._poly(root, Art.rect(-5, 0, 10, 14), Art.shade(col, 0.6), Vector2(-9, -14)))
	legs.append(Art._poly(root, Art.rect(-5, 0, 10, 14), Art.shade(col, 0.6), Vector2(9, -14)))
	var body := Node2D.new()
	root.add_child(body)
	Art._poly(body, PackedVector2Array([Vector2(-18, -14), Vector2(-20, -34), Vector2(-10, -46), Vector2(10, -46), Vector2(20, -34), Vector2(18, -14)]), col)
	Art._poly(body, PackedVector2Array([Vector2(-10, -46), Vector2(10, -46), Vector2(20, -34), Vector2(2, -30), Vector2(-14, -34)]), Art.shade(col, 1.15))
	Art._poly(body, Art.rect(-24, -38, 9, 26), Art.shade(col, 0.8))
	Art._poly(body, Art.rect(15, -38, 9, 26), Art.shade(col, 0.8))
	Art._poly(body, Art.ellipse(6, 6, 8), Art.shade(col, 0.7), Vector2(-20, -10))
	Art._poly(body, Art.ellipse(6, 6, 8), Art.shade(col, 0.7), Vector2(20, -10))
	Art._poly(body, PackedVector2Array([Vector2(-4, -44), Vector2(0, -36), Vector2(-3, -28), Vector2(2, -20)]), glow)
	Art._poly(body, PackedVector2Array([Vector2(8, -40), Vector2(11, -32), Vector2(7, -24)]), glow)
	Art._poly(body, Art.ellipse(8, 7, 10), Art.shade(col, 0.95), Vector2(6, -50))
	Art._poly(body, Art.rect(6, -52, 6, 3), eye)
	return {"root": root, "body": body, "legs": legs}


static func crab(parent: Node, cfg: Dictionary) -> Dictionary:
	var root := _root(parent, cfg)
	var col: Color = cfg.get("color", Color(0.85, 0.4, 0.3))
	Art.shadow(root, 14, 5)
	var legs: Array = []
	for x in [-9.0, -4.0, 4.0, 9.0]:
		legs.append(Art._poly(root, Art.rect(-1, 0, 2, 7), Art.shade(col, 0.6), Vector2(x, -6)))
	var body := Node2D.new()
	root.add_child(body)
	Art._poly(body, Art.ellipse(12, 7, 14), col, Vector2(0, -10))
	Art._poly(body, Art.ellipse(8, 4, 10), Art.shade(col, 1.2), Vector2(0, -12))
	Art._poly(body, PackedVector2Array([Vector2(10, -12), Vector2(17, -19), Vector2(23, -16), Vector2(19, -11), Vector2(22, -8), Vector2(16, -7)]), Art.shade(col, 1.1))
	Art._poly(body, PackedVector2Array([Vector2(8, -6), Vector2(15, -3), Vector2(20, -5), Vector2(16, -8)]), Art.shade(col, 1.1))
	Art._poly(body, Art.ellipse(1.6, 1.6, 6), Color(0.05, 0.05, 0.05), Vector2(7, -17))
	Art._poly(body, Art.ellipse(1.6, 1.6, 6), Color(0.05, 0.05, 0.05), Vector2(3, -17))
	return {"root": root, "body": body, "legs": legs}


# ---------------------------------------------------------------------------
# Trees and plants
# ---------------------------------------------------------------------------

static func _zig(w: float, h: float, tiers: int) -> PackedVector2Array:
	# silhouette of a tiered conifer, base at y=0, tip at y=-h, symmetric about x=0.
	var right := PackedVector2Array()
	for i in tiers:
		var t0: float = float(i) / float(tiers)
		var t1: float = float(i + 1) / float(tiers)
		var half: float = w * 0.5 * (1.0 - t0 * 0.7)
		right.append(Vector2(half, -h * t0))
		right.append(Vector2(half * 0.55, -h * (t0 + (t1 - t0) * 0.55)))
	var pts := PackedVector2Array()
	pts.append(Vector2(0, -h))
	for i in range(right.size() - 1, -1, -1):
		pts.append(right[i])
	pts.append(Vector2(0, 0))
	# mirror
	for i in range(right.size()):
		pts.append(Vector2(-right[i].x, right[i].y))
	return pts


static func lite_pine(parent: Node, s: float, green: Color, snow: bool = false) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(s, s)
	Art.shadow(n, 14, 4, 0.26)
	Art._poly(n, Art.rect(-2.5, -12, 5, 12), Color(0.33, 0.22, 0.13))
	var h := _sway(n, -10.0, 0.03)
	var zs := PackedVector2Array()
	for p in [Vector2(0, -58), Vector2(9, -38), Vector2(5, -38), Vector2(14, -22), Vector2(8, -22), Vector2(19, -2), Vector2(-19, -2), Vector2(-8, -22), Vector2(-14, -22), Vector2(-5, -38), Vector2(-9, -38)]:
		zs.append(p)
	Art._poly(h, zs, green)
	Art._poly(h, PackedVector2Array([Vector2(0, -58), Vector2(9, -38), Vector2(5, -38), Vector2(14, -22), Vector2(8, -22), Vector2(19, -2), Vector2(2, -2)]), Art.shade(green, 1.18))
	if snow:
		Art._poly(h, PackedVector2Array([Vector2(0, -58), Vector2(7, -42), Vector2(0, -44), Vector2(-7, -42)]), Color(0.95, 0.97, 1.0))
		Art._poly(h, PackedVector2Array([Vector2(-10, -24), Vector2(-14, -22), Vector2(-8, -22), Vector2(0, -25), Vector2(8, -22), Vector2(14, -22), Vector2(10, -24), Vector2(0, -27)]), Color(0.93, 0.96, 1.0))
	return n


static func lite_oak(parent: Node, s: float, green: Color) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(s, s)
	Art.shadow(n, 19, 6, 0.26)
	Art._poly(n, PackedVector2Array([Vector2(-4, 0), Vector2(-3, -22), Vector2(3, -22), Vector2(4, 0)]), Color(0.38, 0.26, 0.15))
	var h := _sway(n, -24.0, 0.04)
	Art._poly(h, Art.ellipse(24, 16, 12), Art.shade(green, 0.85), Vector2(0, -6))
	Art._poly(h, Art.ellipse(18, 13, 12), Art.shade(green, 1.05), Vector2(-3, -12))
	Art._poly(h, Art.ellipse(9, 6, 8), Art.shade(green, 1.3), Vector2(-7, -17))
	return n


static func twisted_tree(parent: Node, s: float, green: Color) -> Node2D:
	# swamp / thorn tree: crooked trunk, drooping canopy
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(s, s)
	Art.shadow(n, 18, 5, 0.3)
	Art._poly(n, PackedVector2Array([Vector2(-5, 0), Vector2(-2, -16), Vector2(-7, -30), Vector2(-3, -38), Vector2(2, -30), Vector2(0, -18), Vector2(5, 0)]), Color(0.25, 0.2, 0.15))
	var h := _sway(n, -34.0, 0.035)
	Art._poly(h, Art.ellipse(22, 10, 12), Art.shade(green, 0.8), Vector2(0, 0))
	Art._poly(h, Art.ellipse(16, 8, 10), Art.shade(green, 1.0), Vector2(3, -6))
	for x in [-16.0, -6.0, 8.0, 17.0]:
		Art._poly(h, Art.tri(Vector2(x - 2, 4), Vector2(x + 2, 4), Vector2(x, 16)), Art.shade(green, 0.7))
	return n


static func cactus(parent: Node, s: float) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(s, s)
	Art.shadow(n, 10, 3, 0.26)
	var g := Color(0.3, 0.55, 0.3)
	Art._poly(n, PackedVector2Array([Vector2(-4, 0), Vector2(-4, -30), Vector2(0, -34), Vector2(4, -30), Vector2(4, 0)]), g)
	Art._poly(n, Art.rect(-1, -30, 2, 30), Art.shade(g, 1.2))
	Art._poly(n, PackedVector2Array([Vector2(-4, -12), Vector2(-12, -12), Vector2(-12, -24), Vector2(-9, -24), Vector2(-9, -15), Vector2(-4, -15)]), Art.shade(g, 0.9))
	Art._poly(n, PackedVector2Array([Vector2(4, -18), Vector2(11, -18), Vector2(11, -28), Vector2(8, -28), Vector2(8, -21), Vector2(4, -21)]), Art.shade(g, 0.9))
	return n


static func palm(parent: Node, s: float) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(s, s)
	Art.shadow(n, 16, 5, 0.26)
	Art._poly(n, PackedVector2Array([Vector2(-3, 0), Vector2(-1, -40), Vector2(3, -42), Vector2(4, 0)]), Color(0.5, 0.36, 0.2))
	var h := _sway(n, -42.0, 0.06)
	var leaf := Color(0.25, 0.55, 0.25)
	for a in [-2.6, -2.0, -1.2, -0.5, 0.2]:
		var d := Vector2.RIGHT.rotated(a)
		Art._poly(h, PackedVector2Array([Vector2.ZERO, d * 14 + d.orthogonal() * 4, d * 28 + Vector2(0, 7), d * 14 - d.orthogonal() * 3]), Art.shade(leaf, 0.85 + absf(a) * 0.08))
	return n


static func grass_clump(parent: Node, col: Color, s: float = 1.0, h: float = 12.0) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(s, s)
	var sw := _sway(n, 0.0, 0.07)
	Art._poly(sw, PackedVector2Array([Vector2(-6, 0), Vector2(-5, -h * 0.8), Vector2(-3, 0), Vector2(-1, -h), Vector2(1, 0), Vector2(3, -h * 0.9), Vector2(5, 0), Vector2(7, -h * 0.6), Vector2(8, 0)]), col)
	return n


static func reed_clump(parent: Node, col: Color, s: float = 1.0) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(s, s)
	var sw := _sway(n, 0.0, 0.08)
	for x in [-5.0, -1.0, 3.0, 6.0]:
		Art._poly(sw, Art.rect(x - 0.7, -22 - absf(x), 1.4, 22 + absf(x)), col)
	Art._poly(sw, Art.ellipse(1.8, 4, 6), Color(0.45, 0.3, 0.16), Vector2(-1, -24))
	Art._poly(sw, Art.ellipse(1.8, 4, 6), Color(0.45, 0.3, 0.16), Vector2(3, -22))
	return n


static func wheat(parent: Node, s: float = 1.0) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(s, s)
	var sw := _sway(n, 0.0, 0.08)
	for x in [-6.0, -2.0, 2.0, 6.0]:
		Art._poly(sw, Art.rect(x - 0.6, -15, 1.2, 15), Color(0.72, 0.62, 0.25))
		Art._poly(sw, Art.ellipse(1.6, 3.4, 6), Color(0.9, 0.78, 0.3), Vector2(x, -17))
	return n


static func big_mushroom(parent: Node, s: float, cap: Color) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(s, s)
	Art.shadow(n, 11, 3, 0.25)
	Art._poly(n, Art.rect(-2.5, -14, 5, 14), Color(0.85, 0.82, 0.7))
	Art._poly(n, Art.ellipse(11, 7, 10), cap, Vector2(0, -15))
	Art._poly(n, Art.ellipse(3, 2, 6), Art.shade(cap, 1.5), Vector2(-3, -18))
	return n


static func obsidian_spike(parent: Node, s: float) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(s, s)
	Art.shadow(n, 12, 4, 0.35)
	Art._poly(n, PackedVector2Array([Vector2(-10, 0), Vector2(-6, -24), Vector2(-1, -44), Vector2(5, -22), Vector2(11, 0)]), Color(0.13, 0.11, 0.15))
	Art._poly(n, PackedVector2Array([Vector2(-1, -44), Vector2(5, -22), Vector2(11, 0), Vector2(2, 0)]), Color(0.28, 0.2, 0.3))
	Art._poly(n, PackedVector2Array([Vector2(-3, -34), Vector2(-1, -44), Vector2(0, -30)]), Color(0.75, 0.3, 0.15, 0.85))
	return n


static func tinted(node: Node2D, col: Color) -> Node2D:
	node.modulate = col
	return node


static func rubble(parent: Node, s: float, col: Color) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(s, s)
	Art.shadow(n, 12, 3, 0.25)
	Art._poly(n, PackedVector2Array([Vector2(-10, 0), Vector2(-8, -6), Vector2(-2, -8), Vector2(3, -5), Vector2(2, 0)]), Art.shade(col, 0.9))
	Art._poly(n, PackedVector2Array([Vector2(2, 0), Vector2(4, -9), Vector2(10, -6), Vector2(12, 0)]), Art.shade(col, 1.1))
	return n


static func bones(parent: Node, s: float = 1.0) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(s, s)
	var b := Color(0.86, 0.83, 0.74)
	Art._poly(n, Art.ellipse(9, 4, 10), b, Vector2(0, -4))
	Art._poly(n, Art.ellipse(9, 3.4, 10), Color(0.12, 0.1, 0.1), Vector2(0, -3))
	for x in [-10.0, 10.0]:
		Art._poly(n, Art.ellipse(2.5, 2, 6), b, Vector2(x, -6))
	var l := Line2D.new()
	l.points = PackedVector2Array([Vector2(-14, 2), Vector2(12, -2)])
	l.width = 2.4
	l.default_color = b
	n.add_child(l)
	return n


static func driftwood(parent: Node, s: float = 1.0) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(s, s)
	Art.shadow(n, 14, 3, 0.2)
	var l := Line2D.new()
	l.points = PackedVector2Array([Vector2(-14, -2), Vector2(-3, -5), Vector2(14, -1)])
	l.width = 4.0
	l.default_color = Color(0.65, 0.58, 0.48)
	n.add_child(l)
	var l2 := Line2D.new()
	l2.points = PackedVector2Array([Vector2(-3, -5), Vector2(4, -13)])
	l2.width = 2.0
	l2.default_color = Color(0.6, 0.53, 0.43)
	n.add_child(l2)
	return n


static func shell(parent: Node, col: Color) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	Art._poly(n, Art.ellipse(3.5, 2.6, 8), col)
	Art._poly(n, Art.ellipse(1.6, 1.2, 6), Art.shade(col, 1.2), Vector2(0, -1))
	return n


static func ice_crystal(parent: Node, s: float) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(s, s)
	Art.shadow(n, 10, 3, 0.2)
	Art._poly(n, PackedVector2Array([Vector2(-8, 0), Vector2(-5, -20), Vector2(-1, -26), Vector2(2, -8), Vector2(0, 0)]), Color(0.6, 0.82, 0.95, 0.9))
	Art._poly(n, PackedVector2Array([Vector2(1, 0), Vector2(3, -28), Vector2(8, -16), Vector2(10, 0)]), Color(0.75, 0.92, 1.0, 0.9))
	return n


static func boulder(parent: Node, s: float, col: Color) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(s, s)
	Art.shadow(n, 22, 6, 0.3)
	Art._poly(n, PackedVector2Array([Vector2(-22, 0), Vector2(-24, -14), Vector2(-14, -28), Vector2(4, -32), Vector2(20, -22), Vector2(24, 0)]), Art.shade(col, 0.85))
	Art._poly(n, PackedVector2Array([Vector2(-14, -28), Vector2(4, -32), Vector2(20, -22), Vector2(4, -16), Vector2(-16, -18)]), Art.shade(col, 1.12))
	return n


static func lava_glow(parent: Node, s: float) -> Node2D:
	# a small glowing ember vent for ground decor
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(s, s)
	Art._poly(n, Art.ellipse(9, 4, 10), Color(0.15, 0.08, 0.06))
	Art._poly(n, Art.ellipse(6, 2.6, 10), Color(0.95, 0.4, 0.1))
	Art._poly(n, Art.ellipse(3, 1.2, 8), Color(1.0, 0.85, 0.3))
	return n


# ---------------------------------------------------------------------------
# Buildings / structures
# ---------------------------------------------------------------------------

static func stall(parent: Node, awning: Color, goods: Color = Color(0.8, 0.3, 0.2)) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	Art.shadow(n, 26, 6, 0.26)
	Art._poly(n, Art.rect(-22, -14, 44, 14), Color(0.48, 0.33, 0.18))
	Art._poly(n, Art.rect(-22, -16, 44, 3), Color(0.6, 0.44, 0.26))
	for i in 5:
		Art._poly(n, Art.ellipse(3, 2.4, 6), Art.shade(goods, 0.8 + 0.1 * float(i % 3)), Vector2(-16 + i * 8, -19))
	Art._poly(n, Art.rect(-22, -38, 2.5, 24), Color(0.4, 0.27, 0.15))
	Art._poly(n, Art.rect(19.5, -38, 2.5, 24), Color(0.4, 0.27, 0.15))
	Art._poly(n, PackedVector2Array([Vector2(-26, -34), Vector2(26, -34), Vector2(22, -46), Vector2(-22, -46)]), awning)
	for i in 4:
		Art._poly(n, Art.rect(-26 + i * 13, -34, 6.5, 5), Art.shade(awning, 1.4))
	return n


static func market_tent(parent: Node, col: Color, s: float = 1.0) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(s, s)
	Art.shadow(n, 38, 8, 0.28)
	Art._poly(n, PackedVector2Array([Vector2(-34, 0), Vector2(-30, -26), Vector2(0, -44), Vector2(30, -26), Vector2(34, 0)]), col)
	Art._poly(n, PackedVector2Array([Vector2(0, -44), Vector2(30, -26), Vector2(34, 0), Vector2(10, 0)]), Art.shade(col, 0.8))
	for i in 4:
		Art._poly(n, PackedVector2Array([Vector2(-30 + i * 15, -26 + absf(i - 1.5) * 4), Vector2(-22 + i * 15, -27), Vector2(-24 + i * 15, -8)]), Art.shade(col, 1.35))
	Art._poly(n, PackedVector2Array([Vector2(-9, 0), Vector2(0, -24), Vector2(9, 0)]), Color(0.14, 0.09, 0.07))
	return n


static func barn(parent: Node, wall: Color, roof: Color, w: float = 110.0, h: float = 54.0) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	var hw: float = w * 0.5
	Art.shadow(n, hw + 10, 9, 0.28)
	Art._poly(n, Art.rect(-hw, -h, w, h), wall)
	Art._poly(n, PackedVector2Array([Vector2(-hw - 6, -h), Vector2(-hw + 8, -h - 22), Vector2(hw - 8, -h - 22), Vector2(hw + 6, -h)]), roof)
	Art._poly(n, PackedVector2Array([Vector2(-hw - 6, -h), Vector2(hw + 6, -h), Vector2(hw + 5, -h + 5), Vector2(-hw - 5, -h + 5)]), Art.shade(roof, 0.7))
	Art._poly(n, Art.rect(-16, -34, 32, 34), Color(0.4, 0.2, 0.12))
	Art._poly(n, Art.tri(Vector2(-16, -34), Vector2(16, -34), Vector2(0, -2)), Color(0.85, 0.75, 0.6, 0.35))
	Art._poly(n, Art.rect(-2, -34, 4, 34), Color(0.85, 0.75, 0.6))
	return n


static func haystack(parent: Node, s: float = 1.0) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(s, s)
	Art.shadow(n, 14, 4, 0.25)
	Art._poly(n, PackedVector2Array([Vector2(-13, 0), Vector2(-11, -14), Vector2(-4, -22), Vector2(4, -22), Vector2(11, -14), Vector2(13, 0)]), Color(0.85, 0.72, 0.3))
	Art._poly(n, PackedVector2Array([Vector2(-4, -22), Vector2(4, -22), Vector2(11, -14), Vector2(0, -12), Vector2(-10, -14)]), Color(0.95, 0.82, 0.4))
	Art._poly(n, Art.rect(-12, -8, 24, 1.6), Color(0.55, 0.4, 0.15))
	return n


static func scarecrow(parent: Node) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	Art.shadow(n, 8, 3, 0.25)
	Art._poly(n, Art.rect(-1.2, -30, 2.4, 30), Color(0.42, 0.3, 0.18))
	Art._poly(n, Art.rect(-14, -24, 28, 2.4), Color(0.42, 0.3, 0.18))
	Art._poly(n, PackedVector2Array([Vector2(-6, -26), Vector2(6, -26), Vector2(5, -14), Vector2(-5, -14)]), Color(0.55, 0.4, 0.3))
	Art._poly(n, Art.ellipse(4.5, 4.5, 8), Color(0.85, 0.72, 0.4), Vector2(0, -33))
	Art._poly(n, PackedVector2Array([Vector2(-8, -36), Vector2(8, -36), Vector2(3, -46), Vector2(-3, -46)]), Color(0.3, 0.22, 0.14))
	return n


static func windmill(parent: Node) -> Dictionary:
	var n := Node2D.new()
	parent.add_child(n)
	Art.shadow(n, 34, 9, 0.3)
	Art._poly(n, PackedVector2Array([Vector2(-26, 0), Vector2(-16, -76), Vector2(16, -76), Vector2(26, 0)]), Color(0.82, 0.76, 0.64))
	Art._poly(n, PackedVector2Array([Vector2(-26, 0), Vector2(-21, -28), Vector2(21, -28), Vector2(26, 0)]), Color(0.7, 0.64, 0.52))
	Art._poly(n, PackedVector2Array([Vector2(-20, -76), Vector2(20, -76), Vector2(0, -102)]), Color(0.55, 0.3, 0.22))
	Art._poly(n, Art.rect(-6, -18, 12, 18), Color(0.3, 0.19, 0.1))
	var blades := Node2D.new()
	blades.position = Vector2(0, -74)
	n.add_child(blades)
	for i in 4:
		var d := Vector2.RIGHT.rotated(TAU * float(i) / 4.0 + 0.4)
		var o := d.orthogonal()
		Art._poly(blades, PackedVector2Array([d * 4 - o * 1.5, d * 54 - o * 1.5, d * 54 + o * 12, d * 14 + o * 12]), Color(0.9, 0.85, 0.7))
		Art._poly(blades, PackedVector2Array([d * 4 - o * 1.5, d * 54 - o * 1.5, d * 54 + o * 0.5, d * 4 + o * 0.5]), Color(0.4, 0.28, 0.16))
	return {"root": n, "blades": blades}


static func stone_tower(parent: Node, w: float = 44.0, h: float = 96.0, col: Color = Color(0.55, 0.55, 0.58), broken: bool = false) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	var hw: float = w * 0.5
	Art.shadow(n, hw + 8, 8, 0.3)
	Art._poly(n, PackedVector2Array([Vector2(-hw, 0), Vector2(-hw + 3, -h), Vector2(hw - 3, -h), Vector2(hw, 0)]), col)
	Art._poly(n, PackedVector2Array([Vector2(0, -h), Vector2(hw - 3, -h), Vector2(hw, 0), Vector2(hw * 0.3, 0)]), Art.shade(col, 0.8))
	for i in 4:
		Art._poly(n, Art.rect(-hw + 2, -h * 0.2 - i * h * 0.2, w - 4, 1.4), Art.shade(col, 0.72))
	Art._poly(n, Art.rect(-5, -14, 10, 14), Color(0.16, 0.12, 0.1))
	Art._poly(n, Art.rect(-2.5, -h * 0.6, 5, 11), Color(0.1, 0.08, 0.08))
	if broken:
		Art._poly(n, PackedVector2Array([Vector2(-hw + 3, -h), Vector2(-hw * 0.3, -h - 8), Vector2(0, -h - 2), Vector2(hw * 0.4, -h - 10), Vector2(hw - 3, -h)]), Art.shade(col, 0.9))
	else:
		Art._poly(n, Art.rect(-hw - 4, -h - 8, w + 8, 9), Art.shade(col, 1.1))
		for i in 4:
			Art._poly(n, Art.rect(-hw - 4 + i * (w + 8) * 0.27, -h - 15, (w + 8) * 0.17, 8), Art.shade(col, 1.1))
	return n


static func lighthouse(parent: Node) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	Art.shadow(n, 30, 8, 0.3)
	Art._poly(n, PackedVector2Array([Vector2(-22, 0), Vector2(-13, -120), Vector2(13, -120), Vector2(22, 0)]), Color(0.93, 0.92, 0.9))
	for i in 4:
		var y0: float = -i * 30.0 - 6.0
		Art._poly(n, PackedVector2Array([Vector2(-21.0 + i * 2.2, y0), Vector2(-19.0 + i * 2.2, y0 - 15), Vector2(19.0 - i * 2.2, y0 - 15), Vector2(21.0 - i * 2.2, y0)]), Color(0.75, 0.15, 0.12))
	Art._poly(n, Art.rect(-17, -128, 34, 9), Color(0.25, 0.25, 0.3))
	Art._poly(n, Art.rect(-11, -150, 22, 22), Color(1.0, 0.9, 0.5))
	Art._poly(n, Art.rect(-2, -150, 4, 22), Color(0.35, 0.3, 0.2))
	Art._poly(n, PackedVector2Array([Vector2(-15, -150), Vector2(15, -150), Vector2(0, -168)]), Color(0.7, 0.14, 0.12))
	Art._poly(n, Art.rect(-5, -16, 10, 16), Color(0.25, 0.15, 0.1))
	return n


static func boat(parent: Node, hull: Color, length: float = 70.0) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	var hl: float = length * 0.5
	Art.shadow(n, hl, 7, 0.28)
	Art._poly(n, PackedVector2Array([Vector2(-hl, -10), Vector2(-hl * 0.7, 0), Vector2(hl * 0.7, 0), Vector2(hl, -12), Vector2(hl * 0.6, -14), Vector2(-hl * 0.7, -14)]), hull)
	Art._poly(n, Art.rect(-hl * 0.65, -14, length * 0.65, 3), Art.shade(hull, 0.6))
	Art._poly(n, Art.rect(-1.5, -44, 3, 32), Color(0.4, 0.28, 0.16))
	Art._poly(n, PackedVector2Array([Vector2(1.5, -44), Vector2(18, -22), Vector2(1.5, -16)]), Color(0.93, 0.9, 0.8))
	return n


static func crate(parent: Node, s: float = 1.0) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(s, s)
	Art.shadow(n, 12, 3, 0.25)
	Art._poly(n, Art.rect(-9, -14, 18, 14), Color(0.55, 0.4, 0.22))
	Art._poly(n, Art.rect(-9, -14, 18, 2.4), Color(0.68, 0.52, 0.3))
	Art._poly(n, Art.rect(-1, -14, 2, 14), Color(0.4, 0.28, 0.15))
	return n


static func barrel(parent: Node, s: float = 1.0) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(s, s)
	Art.shadow(n, 9, 3, 0.25)
	Art._poly(n, PackedVector2Array([Vector2(-7, 0), Vector2(-8, -10), Vector2(-6, -18), Vector2(6, -18), Vector2(8, -10), Vector2(7, 0)]), Color(0.5, 0.33, 0.18))
	Art._poly(n, Art.rect(-8, -14, 16, 2), Color(0.25, 0.22, 0.2))
	Art._poly(n, Art.rect(-7.5, -6, 15, 2), Color(0.25, 0.22, 0.2))
	Art._poly(n, Art.ellipse(6, 2, 8), Color(0.62, 0.45, 0.25), Vector2(0, -18))
	return n


static func palisade(parent: Node, length: float) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	var count: int = int(length / 9.0) + 1
	for i in count:
		var h: float = 30.0 + float((i * 7) % 5)
		Art._poly(n, PackedVector2Array([Vector2(-4, 0), Vector2(-4, -h), Vector2(0, -h - 7), Vector2(4, -h), Vector2(4, 0)]), Color(0.42, 0.3, 0.2).lightened(0.03 * float(i % 3)), Vector2(float(i) * 9.0, 0))
	return n


static func ruin_wall(parent: Node, length: float, col: Color = Color(0.5, 0.5, 0.52), h: float = 34.0) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	Art.shadow(n, length * 0.5, 5, 0.25).position = Vector2(length * 0.5, 0)
	var pts := PackedVector2Array([Vector2(0, 0)])
	var x := 0.0
	var i := 0
	while x < length:
		var hh: float = h * (0.45 + 0.55 * absf(sin(float(i) * 1.7 + length)))
		pts.append(Vector2(x, -hh))
		x += length / 6.0
		pts.append(Vector2(minf(x, length), -hh * 0.8))
		i += 1
	pts.append(Vector2(length, 0))
	Art._poly(n, pts, col)
	Art._poly(n, Art.rect(0, -5, length, 5), Art.shade(col, 0.72))
	return n


static func pillar(parent: Node, h: float = 52.0, col: Color = Color(0.72, 0.68, 0.6), broken: bool = false) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	Art.shadow(n, 13, 4, 0.28)
	Art._poly(n, Art.rect(-11, -6, 22, 6), Art.shade(col, 0.85))
	if broken:
		Art._poly(n, PackedVector2Array([Vector2(-8, -6), Vector2(-7, -h * 0.7), Vector2(-2, -h * 0.75), Vector2(2, -h * 0.6), Vector2(8, -h * 0.68), Vector2(8, -6)]), col)
	else:
		Art._poly(n, Art.rect(-8, -h, 16, h - 6), col)
		Art._poly(n, Art.rect(-11, -h - 6, 22, 7), Art.shade(col, 1.12))
	Art._poly(n, Art.rect(2, -h * 0.6, 6, h * 0.6 - 6), Art.shade(col, 0.85))
	return n


static func standing_stone(parent: Node, s: float = 1.0, glow: Color = Color(0.5, 0.8, 1.0)) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	n.scale = Vector2(s, s)
	Art.shadow(n, 12, 4, 0.3)
	Art._poly(n, PackedVector2Array([Vector2(-9, 0), Vector2(-7, -30), Vector2(-2, -42), Vector2(6, -34), Vector2(9, 0)]), Color(0.42, 0.44, 0.5))
	Art._poly(n, PackedVector2Array([Vector2(-2, -42), Vector2(6, -34), Vector2(9, 0), Vector2(1, 0)]), Color(0.32, 0.34, 0.4))
	Art._poly(n, PackedVector2Array([Vector2(-2, -34), Vector2(1, -24), Vector2(-2, -14), Vector2(-4, -24)]), Color(glow.r, glow.g, glow.b, 0.85))
	return n


static func moonwell(parent: Node) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	Art.shadow(n, 34, 12, 0.3)
	Art._poly(n, Art.ellipse(32, 15, 18), Color(0.5, 0.52, 0.56), Vector2(0, -6))
	Art._poly(n, Art.ellipse(25, 11, 18), Color(0.35, 0.6, 0.85), Vector2(0, -9))
	Art._poly(n, Art.ellipse(16, 6, 14), Color(0.7, 0.9, 1.0, 0.85), Vector2(-2, -10))
	Art._poly(n, Art.rect(-32, -6, 64, 6), Color(0.42, 0.44, 0.48))
	return n


static func mine_entrance(parent: Node) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	Art.shadow(n, 52, 10, 0.3)
	Art._poly(n, PackedVector2Array([Vector2(-58, 0), Vector2(-50, -44), Vector2(-24, -72), Vector2(24, -72), Vector2(50, -44), Vector2(58, 0)]), Color(0.45, 0.42, 0.4))
	Art._poly(n, PackedVector2Array([Vector2(-24, -72), Vector2(24, -72), Vector2(50, -44), Vector2(0, -40), Vector2(-46, -46)]), Color(0.56, 0.52, 0.48))
	Art._poly(n, PackedVector2Array([Vector2(-22, 0), Vector2(-22, -36), Vector2(0, -44), Vector2(22, -36), Vector2(22, 0)]), Color(0.04, 0.03, 0.04))
	Art._poly(n, Art.rect(-26, -40, 6, 40), Color(0.45, 0.3, 0.16))
	Art._poly(n, Art.rect(20, -40, 6, 40), Color(0.45, 0.3, 0.16))
	Art._poly(n, Art.rect(-28, -46, 56, 7), Color(0.5, 0.34, 0.18))
	return n


static func cave_mouth(parent: Node, col: Color = Color(0.4, 0.4, 0.42), w: float = 90.0) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	var hw: float = w * 0.5
	Art.shadow(n, hw, 10, 0.3)
	Art._poly(n, PackedVector2Array([Vector2(-hw, 0), Vector2(-hw * 0.9, -46), Vector2(-hw * 0.4, -72), Vector2(hw * 0.4, -74), Vector2(hw * 0.9, -44), Vector2(hw, 0)]), col)
	Art._poly(n, PackedVector2Array([Vector2(-hw * 0.4, -72), Vector2(hw * 0.4, -74), Vector2(hw * 0.9, -44), Vector2(0, -46), Vector2(-hw * 0.8, -48)]), Art.shade(col, 1.18))
	Art._poly(n, PackedVector2Array([Vector2(-hw * 0.4, 0), Vector2(-hw * 0.38, -30), Vector2(0, -42), Vector2(hw * 0.38, -30), Vector2(hw * 0.4, 0)]), Color(0.03, 0.03, 0.04))
	return n


static func hut(parent: Node, wall: Color, roof: Color, w: float = 46.0, h: float = 30.0, stilts: float = 0.0) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	var hw: float = w * 0.5
	Art.shadow(n, hw + 6, 6, 0.26)
	if stilts > 0.0:
		for x in [-hw + 4, -hw * 0.3, hw * 0.3, hw - 4]:
			Art._poly(n, Art.rect(x - 2, -stilts, 4, stilts), Color(0.3, 0.22, 0.14))
	var by: float = -stilts
	Art._poly(n, Art.rect(-hw, by - h, w, h), wall)
	Art._poly(n, Art.rect(-6, by - 20, 12, 20), Color(0.26, 0.17, 0.1))
	Art._poly(n, Art.rect(-hw + 6, by - h + 8, 9, 9), Color(0.95, 0.85, 0.5))
	Art._poly(n, PackedVector2Array([Vector2(-hw - 6, by - h + 2), Vector2(hw + 6, by - h + 2), Vector2(hw - 4, by - h - 20), Vector2(-hw + 4, by - h - 20)]), roof)
	if stilts > 0.0:
		Art._poly(n, Art.rect(hw - 2, by, 5, stilts), Color(0.5, 0.36, 0.2))
	return n


static func throne(parent: Node) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	Art.shadow(n, 60, 14, 0.4)
	Art._poly(n, Art.ellipse(60, 22, 18), Color(0.12, 0.1, 0.13), Vector2(0, -6))
	Art._poly(n, Art.ellipse(46, 16, 18), Color(0.2, 0.16, 0.22), Vector2(0, -14))
	Art._poly(n, PackedVector2Array([Vector2(-20, -16), Vector2(-24, -80), Vector2(-10, -96), Vector2(0, -74), Vector2(10, -96), Vector2(24, -80), Vector2(20, -16)]), Color(0.1, 0.08, 0.12))
	Art._poly(n, PackedVector2Array([Vector2(-10, -24), Vector2(-12, -64), Vector2(0, -56), Vector2(12, -64), Vector2(10, -24)]), Color(0.3, 0.12, 0.1))
	Art._poly(n, PackedVector2Array([Vector2(0, -74), Vector2(10, -96), Vector2(24, -80), Vector2(20, -50), Vector2(8, -60)]), Color(0.75, 0.3, 0.1, 0.7))
	return n


static func shipwreck(parent: Node) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	Art.shadow(n, 70, 14, 0.3)
	var wood := Color(0.42, 0.3, 0.2)
	Art._poly(n, PackedVector2Array([Vector2(-70, -30), Vector2(-50, 0), Vector2(40, 0), Vector2(74, -40), Vector2(60, -42), Vector2(-50, -34)]), wood)
	for i in 6:
		Art._poly(n, Art.rect(-56 + i * 18, -34 + i * 0.6, 3, 30), Art.shade(wood, 0.6))
	Art._poly(n, Art.rect(-6, -74, 4, 40), Color(0.35, 0.24, 0.15))
	Art._poly(n, PackedVector2Array([Vector2(-2, -72), Vector2(20, -54), Vector2(-2, -44)]), Color(0.8, 0.75, 0.65, 0.85))
	return n


static func chapel(parent: Node) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	Art.shadow(n, 64, 10, 0.3)
	var stone := Color(0.46, 0.5, 0.46)
	Art._poly(n, PackedVector2Array([Vector2(-56, 0), Vector2(-56, -50), Vector2(-40, -58), Vector2(-30, -48), Vector2(-20, -60), Vector2(-14, -40), Vector2(-14, 0)]), stone)
	Art._poly(n, PackedVector2Array([Vector2(14, 0), Vector2(14, -44), Vector2(30, -62), Vector2(46, -50), Vector2(56, -58), Vector2(56, 0)]), Art.shade(stone, 0.9))
	Art._poly(n, PackedVector2Array([Vector2(-14, 0), Vector2(-14, -40), Vector2(0, -74), Vector2(14, -44), Vector2(14, 0)]), Color(0.05, 0.07, 0.06))
	Art._poly(n, Art.rect(-18, -90, 4, 30), Color(0.35, 0.3, 0.26))
	Art._poly(n, Art.rect(-26, -82, 20, 4), Color(0.35, 0.3, 0.26))
	Art._poly(n, Art.ellipse(6, 7, 8), Color(0.7, 0.6, 0.3), Vector2(36, -36))
	return n


static func dock_planks(parent: Node, rect: Rect2) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	Art._poly(n, Art.rect(rect.position.x, rect.position.y, rect.size.x, rect.size.y), Color(0.42, 0.3, 0.18))
	var y := rect.position.y + 6.0
	while y < rect.end.y:
		Art._poly(n, Art.rect(rect.position.x, y, rect.size.x, 1.3), Color(0.28, 0.19, 0.11))
		y += 12.0
	Art._poly(n, Art.rect(rect.position.x, rect.position.y, 3, rect.size.y), Color(0.3, 0.2, 0.12))
	Art._poly(n, Art.rect(rect.end.x - 3, rect.position.y, 3, rect.size.y), Color(0.3, 0.2, 0.12))
	return n


static func sign_post(parent: Node, col: Color = Color(0.55, 0.4, 0.22)) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	Art.shadow(n, 6, 2, 0.25)
	Art._poly(n, Art.rect(-1.2, -28, 2.4, 28), Color(0.35, 0.24, 0.14))
	Art._poly(n, Art.rect(-11, -30, 22, 11), col)
	Art._poly(n, Art.rect(-8, -27, 16, 1.6), Art.shade(col, 0.5))
	Art._poly(n, Art.rect(-8, -23.5, 12, 1.6), Art.shade(col, 0.5))
	return n


static func log_pile(parent: Node) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	Art.shadow(n, 16, 4, 0.25)
	for i in 6:
		var row: int = 0 if i < 3 else 1
		var x: float = -8.0 + float(i % 3) * 8.0 + float(row) * 4.0
		Art._poly(n, Art.ellipse(4.2, 4.2, 8), Color(0.5, 0.35, 0.2).lightened(0.04 * float(i % 2)), Vector2(x, -4 - row * 7))
		Art._poly(n, Art.ellipse(2.2, 2.2, 6), Color(0.72, 0.55, 0.35), Vector2(x, -4 - row * 7))
	return n


static func training_dummy(parent: Node) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	Art.shadow(n, 9, 3, 0.25)
	Art._poly(n, Art.rect(-1.5, -26, 3, 26), Color(0.4, 0.28, 0.16))
	Art._poly(n, Art.rect(-11, -22, 22, 3), Color(0.4, 0.28, 0.16))
	Art._poly(n, Art.ellipse(7, 9, 10), Color(0.75, 0.62, 0.4), Vector2(0, -28))
	Art._poly(n, Art.ellipse(4, 5, 8), Color(0.8, 0.2, 0.2), Vector2(0, -28))
	Art._poly(n, Art.ellipse(1.6, 2, 6), Color(0.9, 0.9, 0.8), Vector2(0, -28))
	return n


static func cart(parent: Node, load_col: Color = Color(0.4, 0.4, 0.42)) -> Node2D:
	var n := Node2D.new()
	parent.add_child(n)
	Art.shadow(n, 22, 6, 0.28)
	Art._poly(n, PackedVector2Array([Vector2(-20, -12), Vector2(20, -12), Vector2(17, -4), Vector2(-17, -4)]), Color(0.5, 0.34, 0.18))
	Art._poly(n, PackedVector2Array([Vector2(-16, -12), Vector2(-10, -20), Vector2(0, -22), Vector2(10, -19), Vector2(16, -12)]), load_col)
	Art._poly(n, Art.ellipse(6, 6, 10), Color(0.3, 0.22, 0.14), Vector2(-12, -4))
	Art._poly(n, Art.ellipse(6, 6, 10), Color(0.3, 0.22, 0.14), Vector2(12, -4))
	return n
