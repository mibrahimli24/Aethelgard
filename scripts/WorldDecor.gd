extends RefCounted
## World scenery core. Builds the ground of every region up front (cheap polygons: base colour, blots,
## neighbour blends, roads, the Stormcoast sea) and exposes grid-indexed solids/zones so landmark and
## biome builders can scatter props lazily, one step per frame, as the player approaches a region.

const Art = preload("res://scripts/Art.gd")
const ArtBiome = preload("res://scripts/ArtBiome.gd")
const Ambient = preload("res://scripts/Ambient.gd")
const Regions = preload("res://scripts/Regions.gd")
const Biomes = preload("res://scripts/WorldBiomes.gd")
const Landmarks = preload("res://scripts/WorldLandmarks.gd")
const InteractableScene := preload("res://scenes/Interactable.tscn")

const VILLAGE_RECT := Rect2(150, 150, 500, 450)
const RIDGE_RECT := Rect2(1100, 400, 600, 600)
const CAMP_POS := Vector2(1400, 700)
const POND_POS := Vector2(880, 900)
const PLAYER_START := Vector2(400, 400)
const CELL := 64.0
const ROAD_CELL := 200.0
const BLEND_DEPTHS := [330.0, 220.0, 130.0, 60.0]
const BLEND_ALPHA := [0.22, 0.18, 0.14, 0.1]

var MAIN_PATH := PackedVector2Array([Vector2(650, 470), Vector2(780, 488), Vector2(930, 528), Vector2(1080, 575), Vector2(1250, 640), Vector2(1400, 700)])
var VILLAGE_PATHS := [
	PackedVector2Array([Vector2(650, 470), Vector2(520, 435), Vector2(400, 400)]),
	PackedVector2Array([Vector2(400, 400), Vector2(310, 330), Vector2(250, 262)]),
	PackedVector2Array([Vector2(400, 400), Vector2(480, 350), Vector2(550, 312)]),
	PackedVector2Array([Vector2(400, 400), Vector2(410, 445), Vector2(420, 492)]),
	PackedVector2Array([Vector2(420, 492), Vector2(380, 530), Vector2(350, 550)]),
]

var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
var ground: Node2D
var entities: Node2D
var g_base: Node2D
var g_patch: Node2D
var g_roads: Node2D
var g_deco: Node2D
var world_rect: Rect2
var water_polys: Array = []

var _cells: Dictionary = {}
var _max_r := 0.0
var _zones: Array = []
var _safe: Array = []
var _waters: Array = []
var _spots: Array = []
var _road_cells: Dictionary = {}
var _queue: Array = []
var _built: Dictionary = {}


func build(ground_node: Node2D, entities_node: Node2D) -> void:
	ground = ground_node
	entities = entities_node
	world_rect = Regions.world_rect()
	rng.seed = 1187
	noise.seed = 4242
	noise.frequency = 0.0016
	noise.fractal_octaves = 2
	g_base = _layer()
	g_patch = _layer()
	g_roads = _layer()
	g_deco = _layer()
	_collect_zones()
	_build_ground()
	_build_blends()
	_build_glades_ground()
	_build_roads()
	_build_sea()
	_build_boundary()


func _layer() -> Node2D:
	var n := Node2D.new()
	ground.add_child(n)
	return n


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func add_solid(pos: Vector2, r: float) -> void:
	var key := Vector2i(int(floor(pos.x / CELL)), int(floor(pos.y / CELL)))
	if not _cells.has(key):
		_cells[key] = []
	(_cells[key] as Array).append(Vector3(pos.x, pos.y, r))
	_max_r = maxf(_max_r, r)


func is_free(pos: Vector2, radius: float) -> bool:
	var reach: float = radius + _max_r
	var x0 := int(floor((pos.x - reach) / CELL))
	var x1 := int(floor((pos.x + reach) / CELL))
	var y0 := int(floor((pos.y - reach) / CELL))
	var y1 := int(floor((pos.y + reach) / CELL))
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			var arr: Variant = _cells.get(Vector2i(cx, cy))
			if arr == null:
				continue
			for s: Vector3 in arr:
				var lim: float = s.z + radius
				if pos.distance_squared_to(Vector2(s.x, s.y)) < lim * lim:
					return false
	return true


func add_zone(pos: Vector2, r: float, safe: bool) -> void:
	_zones.append(Vector3(pos.x, pos.y, r))
	_safe.append(safe)


func in_zone(pos: Vector2, margin: float = 0.0) -> bool:
	for z: Vector3 in _zones:
		var lim: float = z.z + margin
		if lim > 0.0 and pos.distance_squared_to(Vector2(z.x, z.y)) < lim * lim:
			return true
	return false


func in_safe_zone(pos: Vector2, margin: float = 0.0) -> bool:
	for i in _zones.size():
		if not _safe[i]:
			continue
		var z: Vector3 = _zones[i]
		var lim: float = z.z + margin
		if pos.distance_squared_to(Vector2(z.x, z.y)) < lim * lim:
			return true
	return false


func add_water(center: Vector2, rx: float, ry: float, collide: bool = true) -> void:
	_waters.append([center, rx, ry])
	if collide:
		var body := StaticBody2D.new()
		body.collision_layer = 4
		body.collision_mask = 0
		body.position = center
		var poly := CollisionPolygon2D.new()
		poly.polygon = Art.ellipse(rx * 0.78, ry * 0.7, 16)
		body.add_child(poly)
		entities.add_child(body)


func in_water(pos: Vector2, margin: float = 0.0) -> bool:
	for w: Array in _waters:
		var c: Vector2 = w[0]
		var d := (pos - c) / Vector2(float(w[1]) + margin, float(w[2]) + margin)
		if d.length_squared() < 1.0:
			return true
	return false


func near_spot(pos: Vector2, dist: float) -> bool:
	for s: Vector2 in _spots:
		if pos.distance_squared_to(s) < dist * dist:
			return true
	return false


func near_road(pos: Vector2, dist: float) -> bool:
	var cx := int(floor(pos.x / ROAD_CELL))
	var cy := int(floor(pos.y / ROAD_CELL))
	for ix in range(cx - 1, cx + 2):
		for iy in range(cy - 1, cy + 2):
			var arr: Variant = _road_cells.get(Vector2i(ix, iy))
			if arr == null:
				continue
			for sg: Vector4 in arr:
				var c: Vector2 = Geometry2D.get_closest_point_to_segment(pos, Vector2(sg.x, sg.y), Vector2(sg.z, sg.w))
				if pos.distance_squared_to(c) < dist * dist:
					return true
	return false


func blocked(pos: Vector2, margin: float = 0.0, soft: bool = false) -> bool:
	if in_zone(pos, margin) or in_water(pos, margin + 6.0):
		return true
	if near_road(pos, (22.0 if soft else 34.0) + margin):
		return true
	return near_spot(pos, 46.0 + margin)


func _collect_zones() -> void:
	add_zone(Vector2(400, 380), 300.0, true)
	add_zone(CAMP_POS, 200.0, false)
	for lm: Dictionary in Regions.landmarks():
		var pos: Vector2 = lm["pos_v"]
		var spots: Array = lm["spots_v"]
		for s: Vector2 in spots:
			_spots.append(s)
		var id: String = str(lm.get("id", ""))
		if lm.get("waystone", false):
			add_zone(pos, 70.0, true)
			continue
		var safe: bool = not spots.is_empty() and id != "red_fang_camp" and id != "old_barrow"
		add_zone(pos, Landmarks.footprint(id), safe)


# ---------------------------------------------------------------------------
# Lazy region building
# ---------------------------------------------------------------------------

func region_built(rid: String) -> bool:
	return _built.has(rid)


func queue_region(rid: String) -> void:
	if _built.has(rid):
		return
	_built[rid] = true
	var steps: Array = []
	if rid == "whispering_glades":
		steps.append_array([Callable(self, "_build_village"), Callable(self, "_build_ridge"), Callable(self, "_build_pond"), Callable(self, "_build_points_of_interest")])
	for lm: Dictionary in Regions.landmarks():
		if str(lm.get("region", "")) == rid:
			steps.append(func(): Landmarks.build(self, lm))
	steps.append_array(Biomes.steps(self, rid))
	_queue.append_array(steps)


func pump() -> bool:
	if _queue.is_empty():
		return false
	var c: Callable = _queue.pop_front()
	c.call()
	return not _queue.is_empty()


func pump_all() -> void:
	while pump():
		pass


func pending() -> int:
	return _queue.size()


# ---------------------------------------------------------------------------
# Ground
# ---------------------------------------------------------------------------

func blob(center: Vector2, rx: float, ry: float, jitter: float = 0.16, n: int = 18) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a: float = TAU * float(i) / float(n)
		var k: float = 1.0 + rng.randf_range(-jitter, jitter)
		pts.append(center + Vector2(cos(a) * rx * k, sin(a) * ry * k))
	return pts


func gpoly(pts: PackedVector2Array, color: Color, layer: Node2D = null) -> Polygon2D:
	return Art._poly(layer if layer != null else g_patch, pts, color)


func gline(pts: PackedVector2Array, width: float, color: Color, layer: Node2D = null) -> Line2D:
	var l := Line2D.new()
	l.points = pts
	l.width = width
	l.default_color = color
	l.joint_mode = Line2D.LINE_JOINT_ROUND
	l.begin_cap_mode = Line2D.LINE_CAP_ROUND
	l.end_cap_mode = Line2D.LINE_CAP_ROUND
	(layer if layer != null else g_patch).add_child(l)
	return l


func _build_ground() -> void:
	for reg: Dictionary in Regions.all():
		var rid: String = str(reg["id"])
		var rc: Rect2 = Regions.rect_of(reg)
		var prof: Dictionary = Biomes.profile(rid)
		var pad := Vector4(2, 2, 2, 2)
		if rc.position.x <= world_rect.position.x + 1.0:
			pad.x = 400
		if rc.position.y <= world_rect.position.y + 1.0:
			pad.y = 400
		if rc.end.x >= world_rect.end.x - 1.0:
			pad.z = 400
		if rc.end.y >= world_rect.end.y - 1.0:
			pad.w = 400
		var big := Rect2(rc.position.x - pad.x, rc.position.y - pad.y, rc.size.x + pad.x + pad.z, rc.size.y + pad.y + pad.w)
		gpoly(Art.rect(big.position.x, big.position.y, big.size.x, big.size.y), prof["ground"], g_base)
		var alts: Array = prof["alts"]
		for i in 70:
			var c := Vector2(rng.randf_range(rc.position.x + 40, rc.end.x - 40), rng.randf_range(rc.position.y + 40, rc.end.y - 40))
			gpoly(blob(c, rng.randf_range(80, 220), rng.randf_range(50, 140), 0.25, 14), alts[i % alts.size()], g_base)


func _build_blends() -> void:
	for a: Dictionary in Regions.all():
		var ra: Rect2 = Regions.rect_of(a)
		var east: Dictionary = Regions.region_at(Vector2(ra.end.x + 20.0, ra.position.y + ra.size.y * 0.5))
		var south: Dictionary = Regions.region_at(Vector2(ra.position.x + ra.size.x * 0.5, ra.end.y + 20.0))
		if str(east.get("id", "")) != str(a["id"]):
			_blend_border(true, ra.end.x, ra.position.y, ra.end.y, Biomes.profile(str(a["id"]))["ground"], Biomes.profile(str(east["id"]))["ground"])
		if str(south.get("id", "")) != str(a["id"]):
			_blend_border(false, ra.end.y, ra.position.x, ra.end.x, Biomes.profile(str(a["id"]))["ground"], Biomes.profile(str(south["id"]))["ground"])


## `vertical` borders run along x = edge; side A lies before the edge, side B after it.
func _blend_border(vertical: bool, edge: float, from: float, to: float, col_a: Color, col_b: Color) -> void:
	for side in 2:
		var dir: float = -1.0 if side == 0 else 1.0
		var col: Color = col_b if side == 0 else col_a
		for li in BLEND_DEPTHS.size():
			var depth: float = BLEND_DEPTHS[li]
			var c := Color(col.r, col.g, col.b, BLEND_ALPHA[li])
			var pts := PackedVector2Array()
			pts.append(_bp(vertical, edge, from))
			var t := from
			while t < to:
				pts.append(_bp(vertical, edge + dir * depth * rng.randf_range(0.55, 1.2), t))
				t += 110.0
			pts.append(_bp(vertical, edge + dir * depth * rng.randf_range(0.55, 1.2), to))
			pts.append(_bp(vertical, edge, to))
			gpoly(pts, c, g_base)


func _bp(vertical: bool, along_edge: float, t: float) -> Vector2:
	return Vector2(along_edge, t) if vertical else Vector2(t, along_edge)


func _build_glades_ground() -> void:
	gpoly(blob(Vector2(400, 375), 300, 255, 0.07, 24), Color(0.3, 0.5, 0.25))
	gpoly(blob(Vector2(400, 375), 250, 210, 0.08, 24), Color(0.33, 0.53, 0.27))
	gpoly(blob(Vector2(1400, 700), 350, 340, 0.1, 26), Color(0.33, 0.3, 0.23))
	for i in 18:
		var c := Vector2(1400, 700) + Vector2(rng.randf_range(-300, 300), rng.randf_range(-290, 290))
		var dark: bool = rng.randf() < 0.5
		gpoly(blob(c, rng.randf_range(30, 90), rng.randf_range(20, 60), 0.25, 10), Color(0.27, 0.25, 0.2, 0.7) if dark else Color(0.42, 0.39, 0.31, 0.6))
	gpoly(blob(CAMP_POS, 165, 125, 0.1, 20), Color(0.28, 0.2, 0.16))
	gpoly(blob(CAMP_POS, 120, 90, 0.1, 16), Color(0.22, 0.15, 0.12))
	gpoly(Art.ellipse(70, 46, 22), Color(0.42, 0.35, 0.25)).position = Vector2(400, 398)
	gpoly(Art.ellipse(60, 39, 22), Color(0.52, 0.44, 0.32)).position = Vector2(400, 398)


# ---------------------------------------------------------------------------
# Roads
# ---------------------------------------------------------------------------

func _smooth(pts: PackedVector2Array, wobble: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pts.size() < 2:
		return pts
	for i in pts.size() - 1:
		var p0: Vector2 = pts[maxi(i - 1, 0)]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p3: Vector2 = pts[mini(i + 2, pts.size() - 1)]
		var n: int = maxi(2, int(p1.distance_to(p2) / 40.0))
		for k in n:
			out.append(p1.cubic_interpolate(p2, p0, p3, float(k) / float(n)))
	out.append(pts[pts.size() - 1])
	if wobble <= 0.0:
		return out
	var src := out.duplicate()
	var phase: float = rng.randf() * TAU
	var acc := 0.0
	for i in src.size():
		if i > 0:
			acc += src[i].distance_to(src[i - 1])
		var a: Vector2 = src[maxi(i - 1, 0)]
		var b: Vector2 = src[mini(i + 1, src.size() - 1)]
		var nrm: Vector2 = (b - a).orthogonal().normalized()
		var edge: float = clampf(minf(float(i), float(src.size() - 1 - i)) / 3.0, 0.0, 1.0)
		out[i] = src[i] + nrm * (sin(acc * 0.012 + phase) * wobble + sin(acc * 0.031 + phase * 2.0) * wobble * 0.4) * edge
	return out


func _build_roads() -> void:
	for pts: PackedVector2Array in Regions.roads():
		_draw_road(_smooth(pts, 12.0), 36.0)
	_draw_road(_smooth(MAIN_PATH, 0.0), 30.0)
	for p: PackedVector2Array in VILLAGE_PATHS:
		_draw_road(_smooth(p, 0.0), 30.0)


func _draw_road(samples: PackedVector2Array, width: float) -> void:
	for i in samples.size() - 1:
		var a: Vector2 = samples[i]
		var b: Vector2 = samples[i + 1]
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
		for cx in range(int(floor(lo.x / ROAD_CELL)), int(floor(hi.x / ROAD_CELL)) + 1):
			for cy in range(int(floor(lo.y / ROAD_CELL)), int(floor(hi.y / ROAD_CELL)) + 1):
				var key := Vector2i(cx, cy)
				if not _road_cells.has(key):
					_road_cells[key] = []
				(_road_cells[key] as Array).append(Vector4(a.x, a.y, b.x, b.y))
	var run := PackedVector2Array()
	var cur := ""
	for p: Vector2 in samples:
		var rid: String = Regions.region_id_at(p)
		if cur == "":
			cur = rid
		if rid != cur:
			run.append(p)
			_emit_road(run, cur, width)
			run = PackedVector2Array()
			cur = rid
		run.append(p)
	_emit_road(run, cur, width)


func _emit_road(run: PackedVector2Array, rid: String, width: float) -> void:
	if run.size() < 2:
		return
	var cols: Array = Biomes.profile(rid)["road"]
	gline(run, width, cols[0], g_roads)
	gline(run, width * 0.72, cols[1], g_roads)


# ---------------------------------------------------------------------------
# Sea (Stormcoast: west and south shores)
# ---------------------------------------------------------------------------

func _build_sea() -> void:
	var west := PackedVector2Array()
	var south := PackedVector2Array()
	var y := 6000.0
	while y <= 8900.0:
		west.append(Vector2(_west_shore(y), y))
		y += 60.0
	var x := -400.0
	while x <= 3900.0:
		south.append(Vector2(x, _south_shore(x)))
		x += 60.0
	_sea_poly(west, Vector2(-400, 6000), Vector2(-400, 8900), Vector2(-1, 0))
	_sea_poly(south, Vector2(-400, 8900), Vector2(3900, 8900), Vector2(0, 1))


func _west_shore(y: float) -> float:
	var ramp: float = smoothstep(6000.0, 6500.0, y)
	return lerpf(-250.0, 118.0 + sin(y * 0.004) * 18.0 + sin(y * 0.013) * 8.0, ramp)


func _south_shore(x: float) -> float:
	return 8440.0 + sin(x * 0.005) * 16.0 + sin(x * 0.017) * 7.0 + smoothstep(3300.0, 3800.0, x) * 420.0


## `sea_dir` points from the shoreline out to sea.
func _sea_poly(shore: PackedVector2Array, start: Vector2, finish: Vector2, sea_dir: Vector2) -> void:
	var poly := PackedVector2Array()
	poly.append(start)
	poly.append_array(shore)
	poly.append(finish)
	var deep: Polygon2D = gpoly(poly, Color(0.12, 0.3, 0.5), g_patch)
	var near := PackedVector2Array()
	for p in shore:
		near.append(p + sea_dir * 46.0)
	var strip := PackedVector2Array(shore)
	var rev := near.duplicate()
	rev.reverse()
	strip.append_array(rev)
	var shal: Polygon2D = gpoly(strip, Color(0.22, 0.46, 0.64, 0.75), g_patch)
	var foam: Line2D = gline(shore, 5.0, Color(1, 1, 1, 0.55), g_patch)
	var foam2: Line2D = gline(shore, 12.0, Color(1, 1, 1, 0.18), g_patch)
	water_polys.append_array([deep, shal, foam, foam2])
	Ambient.animate_water([deep, shal, foam, foam2])
	var inset := PackedVector2Array()
	inset.append(start)
	for p in shore:
		inset.append(p - sea_dir * 14.0)
	inset.append(finish)
	var body := StaticBody2D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var cp := CollisionPolygon2D.new()
	cp.polygon = inset
	body.add_child(cp)
	entities.add_child(body)
	for i in range(0, shore.size(), 3):
		_waters.append([shore[i] + sea_dir * 80.0, 110.0, 110.0])


func _build_boundary() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var r := world_rect
	var t := 60.0
	for rc: Rect2 in [Rect2(r.position.x - t, r.position.y - t, r.size.x + t * 2.0, t), Rect2(r.position.x - t, r.end.y, r.size.x + t * 2.0, t), Rect2(r.position.x - t, r.position.y, t, r.size.y), Rect2(r.end.x, r.position.y, t, r.size.y)]:
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = rc.size
		cs.shape = shape
		cs.position = rc.position + rc.size * 0.5
		body.add_child(cs)
	entities.add_child(body)


# ---------------------------------------------------------------------------
# Prop helpers (shared with WorldLandmarks)
# ---------------------------------------------------------------------------

func add_body(parent: Node2D, shape: Shape2D, pos: Vector2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)
	parent.add_child(body)


func circle(r: float) -> CircleShape2D:
	var c := CircleShape2D.new()
	c.radius = r
	return c


func rect_shape(size: Vector2) -> RectangleShape2D:
	var rs := RectangleShape2D.new()
	rs.size = size
	return rs


func prop(node: Node2D, pos: Vector2, collide_r: float, clear_r: float) -> Node2D:
	node.position = pos
	if collide_r > 0.0:
		add_body(node, circle(collide_r), Vector2(0, -collide_r * 0.6))
	add_solid(pos, clear_r)
	return node


func house(pos: Vector2, wall: Color, roof: Color, width: float = 70.0, height: float = 42.0) -> Node2D:
	var n: Node2D = Art.house(entities, wall, roof, width, height)
	n.position = pos
	add_body(n, rect_shape(Vector2(width - 4.0, 16.0)), Vector2(0, -8))
	add_solid(Vector2(pos.x, pos.y - 10.0), width * 0.5 + 24.0)
	return n


func lamp(pos: Vector2) -> void:
	var n := Node2D.new()
	n.position = pos
	entities.add_child(n)
	Art.shadow(n, 5, 2, 0.25)
	Art._poly(n, Art.rect(-1.2, -30, 2.4, 30), Color(0.25, 0.2, 0.16))
	Art._poly(n, Art.rect(-4, -38, 8, 8), Color(1.0, 0.82, 0.35))
	Art._poly(n, Art.rect(-5.5, -40, 11, 2.5), Color(0.2, 0.16, 0.12))
	var light := Fx.make_light(140.0, Color(1.0, 0.78, 0.42), 0.6)
	light.position = Vector2(0, -34)
	n.add_child(light)
	add_body(n, circle(3.0), Vector2(0, -2))
	add_solid(pos, 16.0)


func interactable(kind: String, pos: Vector2, item_id: String = "", uid: String = "", loot: String = "") -> Node2D:
	var n: Node2D = InteractableScene.instantiate()
	n.kind = kind
	if item_id != "":
		n.item_id = item_id
	n.uid = uid
	if loot != "":
		n.loot = loot
	n.position = pos
	entities.add_child(n)
	add_solid(pos, 20.0)
	return n


# ---------------------------------------------------------------------------
# Whispering Glades legacy set pieces: village, barrow ridge, pond, points of interest
# ---------------------------------------------------------------------------

func _build_village() -> void:
	# fences/paths first so houses and lamps sit on top
	house(Vector2(235, 205), Color(0.74, 0.64, 0.46), Color(0.32, 0.5, 0.3), 64.0, 40.0)
	house(Vector2(352, 178), Color(0.76, 0.67, 0.52), Color(0.6, 0.3, 0.22), 70.0, 42.0)
	house(Vector2(568, 212), Color(0.56, 0.46, 0.36), Color(0.4, 0.28, 0.2), 78.0, 44.0)
	house(Vector2(592, 512), Color(0.72, 0.62, 0.5), Color(0.5, 0.3, 0.25), 66.0, 40.0)
	house(Vector2(198, 482), Color(0.7, 0.6, 0.5), Color(0.55, 0.36, 0.2), 62.0, 38.0)
	house(Vector2(330, 566), Color(0.5, 0.5, 0.54), Color(0.3, 0.3, 0.36), 72.0, 40.0)
	prop(Art.well(entities), Vector2(400, 292), 11.0, 26.0)
	for pos in [Vector2(345, 358), Vector2(458, 350), Vector2(352, 452), Vector2(470, 448)]:
		lamp(pos)
	for f in [[Vector2(160, 545), 120.0], [Vector2(470, 588), 96.0], [Vector2(150, 415), 70.0]]:
		var fence: Node2D = Art.fence(entities, float(f[1]))
		fence.position = f[0]
	for pos in [Vector2(215, 322), Vector2(246, 338), Vector2(228, 358)]:
		prop(Art.bush(entities, 0.8, 1.05), pos, 0.0, 12.0)
	interactable("forage", Vector2(196, 338), "healing_herb")
	interactable("forage", Vector2(262, 360), "healing_herb")
	interactable("forage", Vector2(620, 270), "berries")
	interactable("forage", Vector2(160, 570), "berries")
	interactable("campfire", Vector2(316, 468))
	interactable("waystone", Vector2(478, 392), "", "village")
	for pos in [Vector2(180, 250), Vector2(618, 400), Vector2(530, 560), Vector2(250, 590)]:
		prop(Art.oak(entities, rng.randf_range(0.9, 1.1), 1.0), pos, 7.0, 30.0)


func _build_ridge() -> void:
	var barrow := Node2D.new()
	entities.add_child(barrow)
	barrow.position = Vector2(1580, 915)
	Art.shadow(barrow, 66, 14, 0.3)
	Art._poly(barrow, Art.ellipse(64, 40, 20), Color(0.3, 0.36, 0.24), Vector2(0, -22))
	Art._poly(barrow, Art.ellipse(46, 26, 18), Color(0.36, 0.43, 0.29), Vector2(-6, -34), 0)
	Art._poly(barrow, Art.rect(-14, -30, 28, 26), Color(0.06, 0.05, 0.06), Vector2(0, 0), 0)
	Art._poly(barrow, Art.rect(-18, -34, 5, 32), Color(0.5, 0.5, 0.52), Vector2(0, 0), 0)
	Art._poly(barrow, Art.rect(13, -34, 5, 32), Color(0.5, 0.5, 0.52), Vector2(0, 0), 0)
	Art._poly(barrow, Art.rect(-20, -38, 40, 6), Color(0.56, 0.56, 0.58), Vector2(0, 0), 0)
	add_body(barrow, rect_shape(Vector2(120, 22)), Vector2(0, -11))
	add_solid(Vector2(1580, 905), 78.0)
	var glow := Fx.make_light(90.0, Color(0.9, 0.2, 0.3), 0.6)
	glow.position = Vector2(0, -16)
	barrow.add_child(glow)
	for pos in [Vector2(1520, 960), Vector2(1650, 958)]:
		prop(Art.dead_tree(entities, 1.1), pos, 5.0, 30.0)


func _build_pond() -> void:
	gpoly(blob(POND_POS, 90, 58, 0.05, 22), Color(0.72, 0.68, 0.48))
	var deep: Polygon2D = gpoly(blob(POND_POS, 76, 46, 0.05, 22), Color(0.17, 0.34, 0.54))
	var mid: Polygon2D = gpoly(blob(POND_POS + Vector2(-10, -6), 48, 22, 0.08, 16), Color(0.26, 0.46, 0.66, 0.7))
	var hi: Polygon2D = gpoly(blob(POND_POS + Vector2(-18, -10), 18, 5, 0.1, 10), Color(0.6, 0.78, 0.9, 0.6))
	for lp in [Vector2(30, 8), Vector2(46, -6), Vector2(-40, 14)]:
		gpoly(Art.ellipse(7, 3.5, 10), Color(0.2, 0.5, 0.25)).position = POND_POS + lp
	Ambient.animate_water([deep, mid, hi])
	Ambient.ripple_layer(g_patch, 60.0, 34.0, 4, Color(1, 1, 1, 0.3), POND_POS)
	add_water(POND_POS, 90.0, 58.0, true)
	for i in 7:
		var a: float = rng.randf() * TAU
		var pos: Vector2 = POND_POS + Vector2(cos(a) * 82.0, sin(a) * 52.0)
		var reed: Node2D = ArtBiome.reed_clump(entities, Color(0.32, 0.5, 0.25), 0.8)
		reed.position = pos


func _build_points_of_interest() -> void:
	interactable("waystone", Vector2(908, 492), "", "glade")
	interactable("waystone", Vector2(1118, 598), "", "ridge")
	interactable("chest", Vector2(282, 930), "", "sw", "cooked_meat:2,healing_herb:2")
	interactable("chest", Vector2(1592, 470), "", "ridge_ne", "copper_ore:3,mushroom_stew:1")
	interactable("chest", Vector2(760, 1032), "", "south", "oak_wood:3,berries:4,healing_herb:1")
	interactable("campfire", Vector2(1000, 640))
	for pos in [Vector2(700, 440), Vector2(1010, 560), Vector2(1190, 625)]:
		var cairn := Node2D.new()
		entities.add_child(cairn)
		Art.shadow(cairn, 8, 3, 0.25)
		for i in 3:
			Art._poly(cairn, Art.ellipse(7.0 - i * 2.0, 3.0, 8), Color(0.5, 0.5, 0.52).darkened(0.05 * i), Vector2(0, -3 - i * 5))
		prop(cairn, pos, 5.0, 14.0)
