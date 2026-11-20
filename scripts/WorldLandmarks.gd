extends RefCounted
## Places the set pieces of each landmark. Layout data lives in WorldLayoutsA/B as piece specs
## [kind, dx, dy, params...] relative to the landmark centre.

const Art = preload("res://scripts/Art.gd")
const ArtBiome = preload("res://scripts/ArtBiome.gd")
const Ambient = preload("res://scripts/Ambient.gd")
const Biomes = preload("res://scripts/WorldBiomes.gd")
const LayoutsA = preload("res://scripts/WorldLayoutsA.gd")
const LayoutsB = preload("res://scripts/WorldLayoutsB.gd")

const FOOT := {
	"kingsford": 300.0, "glenbrook": 300.0, "dust_bazaar": 280.0, "driftwood_harbor": 240.0, "frozen_lake": 230.0,
	"lava_fields": 230.0, "red_fang_camp": 200.0, "iron_tarn": 200.0, "leech_pools": 200.0, "sun_temple": 190.0,
	"ember_throne": 190.0, "frostwatch_outpost": 190.0, "harvest_farm": 220.0, "cinder_ruins": 180.0, "legion_camp": 180.0,
	"thornwood_lodge": 170.0, "glade_pond": 150.0, "oasis_of_tamsin": 190.0, "sunken_chapel": 170.0, "dwarven_ruin": 170.0,
}
const FORCE := ["fire", "gnd", "dock", "web", "field", "pool", "lava", "chest"]


static func footprint(id: String) -> float:
	return float(FOOT.get(id, 110.0))


static func layout(id: String) -> Array:
	if LayoutsA.L.has(id):
		return LayoutsA.L[id]
	if LayoutsB.L.has(id):
		return LayoutsB.L[id]
	return []


static func build(d, lm: Dictionary) -> void:
	var id: String = str(lm.get("id", ""))
	var rid: String = str(lm.get("region", ""))
	var c: Vector2 = lm["pos_v"]
	if lm.has("waystone_uid") and rid != "whispering_glades":
		d.interactable("waystone", c + Vector2(-48, 52), "", str(lm["waystone_uid"]))
	var prof: Dictionary = Biomes.profile(rid)
	var r := RandomNumberGenerator.new()
	r.seed = hash(id)
	for spec: Array in layout(id):
		_place(d, c, spec, prof, r)


static func _place(d, c: Vector2, spec: Array, prof: Dictionary, r: RandomNumberGenerator) -> void:
	var kind: String = str(spec[0])
	var pos: Vector2 = c + Vector2(float(spec[1]), float(spec[2]))
	var p: Array = spec.slice(3)
	if not FORCE.has(kind):
		if d.near_spot(pos, 44.0) or d.near_road(pos, 22.0):
			return
	var e: Node2D = d.entities
	var node: Node2D = null
	match kind:
		"house":
			d.house(pos, p[0], p[1], float(p[2]), float(p[3]))
		"hut":
			node = ArtBiome.hut(e, p[0], p[1], float(p[2]), float(p[3]), 24.0 if bool(p[4]) else 0.0)
			_body(d, node, pos, Vector2(float(p[2]) - 4.0, 14.0), float(p[2]) * 0.5 + 20.0)
		"tent":
			var s: float = float(p[1])
			node = Art.tent(e, p[0])
			node.scale = Vector2(s, s)
			_body(d, node, pos, Vector2(46.0 * s, 12.0), 46.0 * s)
		"mtent":
			node = ArtBiome.market_tent(e, p[0], float(p[1]))
			_body(d, node, pos, Vector2(38.0, 12.0), 40.0)
		"stall":
			node = ArtBiome.stall(e, p[0], p[1])
			_body(d, node, pos, Vector2(40.0, 10.0), 34.0)
		"barn":
			node = ArtBiome.barn(e, p[0], p[1], float(p[2]), float(p[3]))
			_body(d, node, pos, Vector2(float(p[2]) - 6.0, 18.0), float(p[2]) * 0.5 + 24.0)
		"hay":
			d.prop(ArtBiome.haystack(e, float(p[0])), pos, 12.0, 26.0)
		"scare":
			d.prop(ArtBiome.scarecrow(e), pos, 0.0, 20.0)
		"mill":
			var m: Dictionary = ArtBiome.windmill(e)
			node = m["root"]
			_body(d, node, pos, Vector2(36.0, 14.0), 50.0)
			var blades: Node2D = m["blades"]
			if blades != null:
				var tw := blades.create_tween().set_loops()
				tw.tween_method(func(a: float): blades.rotation = a, 0.0, TAU, 9.0)
		"tower":
			node = ArtBiome.stone_tower(e, float(p[0]), float(p[1]), p[2], bool(p[3]))
			_body(d, node, pos, Vector2(float(p[0]) - 6.0, 14.0), float(p[0]) * 0.5 + 24.0)
		"light":
			node = ArtBiome.lighthouse(e)
			_body(d, node, pos, Vector2(30.0, 14.0), 44.0)
			var lt := Fx.make_light(260.0, Color(1.0, 0.9, 0.6), 0.8)
			lt.position = Vector2(0, -110)
			lt.set_meta("flicker", true)
			node.add_child(lt)
		"boat":
			node = ArtBiome.boat(e, p[0], float(p[1]))
			_body(d, node, pos, Vector2(float(p[1]) * 0.8, 10.0), float(p[1]) * 0.5)
		"crate":
			d.prop(ArtBiome.crate(e, float(p[0])), pos, 8.0 * float(p[0]), 16.0)
		"barrel":
			d.prop(ArtBiome.barrel(e, float(p[0])), pos, 7.0 * float(p[0]), 16.0)
		"pal":
			var len: float = float(p[0])
			node = ArtBiome.palisade(e, len)
			_strip(d, node, pos, len)
		"wall":
			var wl: float = float(p[0])
			node = ArtBiome.ruin_wall(e, wl, p[1], float(p[2]))
			_strip(d, node, pos, wl)
		"pillar":
			d.prop(ArtBiome.pillar(e, float(p[0]), p[1], bool(p[2])), pos, 6.0, 18.0)
		"stone":
			d.prop(ArtBiome.standing_stone(e, float(p[0]), p[1]), pos, 7.0 * float(p[0]), 20.0)
		"moonwell":
			d.prop(ArtBiome.moonwell(e), pos, 20.0, 40.0)
		"mine":
			node = ArtBiome.mine_entrance(e)
			_body(d, node, pos, Vector2(60.0, 14.0), 50.0)
		"cave":
			node = ArtBiome.cave_mouth(e, p[0], float(p[1]))
			_body(d, node, pos, Vector2(float(p[1]), 14.0), float(p[1]) * 0.5 + 20.0)
		"throne":
			node = ArtBiome.throne(e)
			_body(d, node, pos, Vector2(40.0, 14.0), 40.0)
		"wreck":
			node = ArtBiome.shipwreck(e)
			_body(d, node, pos, Vector2(90.0, 16.0), 70.0)
		"chapel":
			node = ArtBiome.chapel(e)
			_body(d, node, pos, Vector2(80.0, 22.0), 70.0)
		"sign":
			d.prop(ArtBiome.sign_post(e, p[0] if p.size() > 0 else Color(0.5, 0.4, 0.28)), pos, 0.0, 14.0)
		"logs":
			node = ArtBiome.log_pile(e)
			_body(d, node, pos, Vector2(40.0, 10.0), 28.0)
		"dummy":
			d.prop(ArtBiome.training_dummy(e), pos, 6.0, 18.0)
		"cart":
			node = ArtBiome.cart(e, p[0])
			_body(d, node, pos, Vector2(44.0, 12.0), 32.0)
		"fire":
			d.interactable("campfire", pos)
		"lamp":
			d.lamp(pos)
		"torch":
			torch(d, pos)
		"banner":
			banner(d, pos)
		"well":
			d.prop(Art.well(e), pos, 11.0, 26.0)
		"fence":
			var fl: float = float(p[0])
			node = Art.fence(e, fl)
			node.position = pos
			d.add_solid(pos + Vector2(fl * 0.5, 0), fl * 0.5)
		"tree":
			var t: Array = Biomes.make_tree(d, str(p[0]), r, prof)
			d.prop(t[0], pos, float(t[1]), 28.0)
		"reed":
			d.prop(ArtBiome.reed_clump(e, prof["green"], float(p[0])), pos, 0.0, 10.0)
		"mush":
			d.prop(ArtBiome.big_mushroom(e, float(p[0]), p[1]), pos, 0.0, 12.0)
		"crystal":
			d.prop(ArtBiome.ice_crystal(e, float(p[0])), pos, 0.0, 12.0)
		"spike":
			d.prop(ArtBiome.obsidian_spike(e, float(p[0])), pos, 6.0, 16.0)
		"boulder":
			d.prop(ArtBiome.boulder(e, float(p[0]), p[1]), pos, 9.0 * minf(float(p[0]), 1.3), 20.0)
		"rubble":
			d.prop(ArtBiome.rubble(e, float(p[0]), p[1]), pos, 0.0, 12.0)
		"bones":
			d.prop(ArtBiome.bones(e, float(p[0])), pos, 0.0, 10.0)
		"driftwood":
			d.prop(ArtBiome.driftwood(e, float(p[0])), pos, 0.0, 10.0)
		"shell":
			d.prop(ArtBiome.shell(e, Color(0.92, 0.82, 0.76)), pos, 0.0, 8.0)
		"chest":
			d.interactable("chest", pos, "", str(p[0]), str(p[1]))
		"gnd":
			d.gpoly(d.blob(pos, float(p[1]), float(p[2])), p[0])
		"pool":
			_pool(d, pos, float(p[0]), float(p[1]), p[2], bool(p[3]))
		"lava":
			_lava(d, pos, float(p[0]), float(p[1]))
		"web":
			_web(d, pos, float(p[0]))
		"field":
			_field(d, pos, float(p[0]), float(p[1]))
		"dock":
			ArtBiome.dock_planks(d.g_patch, Rect2(pos - Vector2(float(p[0]) * 0.5, 0), Vector2(float(p[0]), float(p[1]))))
			d.add_solid(pos + Vector2(0, float(p[1]) * 0.5), 40.0)


static func _body(d, node: Node2D, pos: Vector2, size: Vector2, clear: float) -> void:
	node.position = pos
	d.add_body(node, d.rect_shape(size), Vector2(0, -size.y * 0.5))
	d.add_solid(Vector2(pos.x, pos.y - 10.0), clear)


static func _strip(d, node: Node2D, pos: Vector2, length: float) -> void:
	node.position = pos - Vector2(length * 0.5, 0)
	var x := 0.0
	while x <= length:
		d.add_body(node, d.circle(9.0), Vector2(x, -6))
		d.add_solid(pos + Vector2(x - length * 0.5, 0), 20.0)
		x += 40.0


static func torch(d, pos: Vector2) -> void:
	var n := Node2D.new()
	n.position = pos
	d.entities.add_child(n)
	Art.shadow(n, 4, 2, 0.25)
	Art._poly(n, Art.rect(-1.2, -26, 2.4, 26), Color(0.3, 0.2, 0.12))
	var flame: Node2D = Node2D.new()
	flame.position = Vector2(0, -28)
	n.add_child(flame)
	Art._poly(flame, PackedVector2Array([Vector2(-4, 0), Vector2(0, -12), Vector2(4, 0)]), Color(1.0, 0.55, 0.15))
	Art._poly(flame, PackedVector2Array([Vector2(-2, 0), Vector2(0, -7), Vector2(2, 0)]), Color(1.0, 0.9, 0.4))
	var light := Fx.make_light(150.0, Color(1.0, 0.65, 0.3), 0.7)
	light.position = Vector2(0, -30)
	n.add_child(light)
	d.add_body(n, d.circle(3.0), Vector2(0, -2))
	d.add_solid(pos, 14.0)


static func banner(d, pos: Vector2) -> void:
	var n := Node2D.new()
	n.position = pos
	d.entities.add_child(n)
	Art.shadow(n, 5, 2, 0.25)
	Art._poly(n, Art.rect(-1.5, -58, 3, 58), Color(0.32, 0.22, 0.14))
	Art._poly(n, PackedVector2Array([Vector2(1.5, -56), Vector2(24, -52), Vector2(19, -42), Vector2(24, -32), Vector2(1.5, -34)]), Color(0.65, 0.1, 0.12))
	d.add_body(n, d.circle(4.0), Vector2(0, -2))
	d.add_solid(pos, 14.0)


static func _pool(d, pos: Vector2, rx: float, ry: float, deep: Color, collide: bool) -> void:
	d.gpoly(d.blob(pos, rx + 10.0, ry + 8.0), deep.lightened(0.35))
	var water: Polygon2D = d.gpoly(d.blob(pos, rx, ry), deep)
	var hi: Polygon2D = d.gpoly(d.blob(pos + Vector2(-rx * 0.15, -ry * 0.2), rx * 0.6, ry * 0.5), deep.lightened(0.25))
	Ambient.animate_water([water, hi])
	Ambient.ripple_layer(d.g_patch, rx * 0.8, ry * 0.7, 4, deep.lightened(0.5), pos)
	d.add_water(pos, rx, ry, collide)


static func _lava(d, pos: Vector2, rx: float, ry: float) -> void:
	d.gpoly(d.blob(pos, rx + 12.0, ry + 9.0), Color(0.08, 0.05, 0.05))
	d.gpoly(d.blob(pos, rx, ry), Color(0.75, 0.2, 0.05))
	d.gpoly(d.blob(pos, rx * 0.65, ry * 0.6), Color(1.0, 0.5, 0.1))
	d.gpoly(d.blob(pos, rx * 0.3, ry * 0.3), Color(1.0, 0.85, 0.35))
	var light := Fx.make_light(rx * 2.6, Color(1.0, 0.45, 0.15), 0.8)
	light.position = pos
	d.g_patch.add_child(light)
	var em := Node2D.new()
	em.position = pos
	em.set_meta("emit", "embers")
	em.set_meta("emit_rate", 0.6)
	em.add_to_group("emitters")
	d.g_patch.add_child(em)
	d.add_water(pos, rx, ry, true)


static func _web(d, pos: Vector2, radius: float) -> void:
	var col := Color(0.92, 0.92, 0.95, 0.35)
	for i in 8:
		var a: float = TAU * i / 8.0
		d.gline(PackedVector2Array([pos, pos + Vector2(cos(a), sin(a) * 0.7) * radius]), 1.4, col)
	for k in [0.35, 0.65, 0.95]:
		var ring := PackedVector2Array()
		for i in 17:
			var a2: float = TAU * i / 16.0
			ring.append(pos + Vector2(cos(a2), sin(a2) * 0.7) * radius * k)
		d.gline(ring, 1.1, col)


static func _field(d, pos: Vector2, w: float, h: float) -> void:
	d.gpoly(PackedVector2Array([pos + Vector2(-w * 0.5, -h * 0.5), pos + Vector2(w * 0.5, -h * 0.5), pos + Vector2(w * 0.5, h * 0.5), pos + Vector2(-w * 0.5, h * 0.5)]), Color(0.38, 0.28, 0.16))
	var y := -h * 0.5 + 12.0
	while y < h * 0.5 - 6.0:
		d.gline(PackedVector2Array([pos + Vector2(-w * 0.5 + 6, y), pos + Vector2(w * 0.5 - 6, y)]), 3.0, Color(0.3, 0.22, 0.12))
		var x := -w * 0.5 + 14.0
		while x < w * 0.5 - 8.0:
			var wh: Node2D = ArtBiome.wheat(d.g_deco, 0.7)
			wh.position = pos + Vector2(x, y + 4.0)
			x += 26.0
		y += 26.0
