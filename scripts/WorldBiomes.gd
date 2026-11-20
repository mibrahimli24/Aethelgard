extends RefCounted
## Per-region biome profiles and the lazy scatter steps (trees, rocks, deco, forage) that fill a region.
## `d` is the WorldDecor instance (solids grid, exclusion checks, ground/entity layers).

const Art = preload("res://scripts/Art.gd")
const ArtBiome = preload("res://scripts/ArtBiome.gd")
const Regions = preload("res://scripts/Regions.gd")

const FLOWER_COLORS := [Color(0.95, 0.85, 0.3), Color(0.9, 0.4, 0.5), Color(0.95, 0.95, 0.95), Color(0.55, 0.5, 0.95), Color(0.95, 0.6, 0.25)]

# trees: [kind, weight]; rocks: [kind, weight]; deco: [kind, count]; forage: [item, count, optional [x,y,w,h] rects]
const P := {
	"whispering_glades": {
		"biome": "forest", "ground": Color(0.2, 0.39, 0.18), "alts": [Color(0.27, 0.46, 0.22, 0.55), Color(0.16, 0.33, 0.15, 0.55)],
		"tuft": Color(0.15, 0.32, 0.14), "green": Color(0.2, 0.45, 0.2), "road": [Color(0.42, 0.35, 0.25), Color(0.5, 0.42, 0.3)],
		"trees": [["pine", 0.55], ["oak", 0.45]], "tree_px": 34000, "rocks": [["rock", 1.0]], "rock_n": 70, "rock_col": Color(0.5, 0.5, 0.52),
		"deco": [["bush", 110], ["flower", 150], ["tuft", 420], ["grass", 60]], "bush_tint": 1.0,
		"forage": [["berries", 14], ["mushroom", 14], ["healing_herb", 10], ["copper_ore", 6, [[1130, 430, 540, 540]]], ["oak_wood", 10]],
	},
	"thornwood": {
		"biome": "forest", "ground": Color(0.13, 0.27, 0.17), "alts": [Color(0.17, 0.33, 0.2, 0.55), Color(0.09, 0.2, 0.12, 0.55)],
		"tuft": Color(0.08, 0.2, 0.1), "green": Color(0.14, 0.36, 0.2), "road": [Color(0.3, 0.25, 0.2), Color(0.38, 0.32, 0.25)],
		"trees": [["lpine", 0.55], ["twist", 0.25], ["dead", 0.2]], "tree_px": 28000, "rocks": [["rock", 0.7], ["boulder", 0.3]], "rock_n": 50, "rock_col": Color(0.4, 0.42, 0.42),
		"deco": [["bush", 90], ["mush", 40], ["grass", 120], ["tuft", 320], ["bones", 10]], "bush_tint": 0.75,
		"forage": [["mushroom", 12], ["healing_herb", 8], ["pine_resin", 12], ["oak_wood", 6]],
	},
	"hollow_peaks": {
		"biome": "snow", "ground": Color(0.86, 0.9, 0.94), "alts": [Color(0.96, 0.98, 1.0, 0.6), Color(0.74, 0.8, 0.88, 0.55)],
		"tuft": Color(0.68, 0.76, 0.86), "green": Color(0.2, 0.4, 0.34), "road": [Color(0.62, 0.66, 0.72), Color(0.72, 0.76, 0.8)],
		"trees": [["spine", 0.72], ["dead", 0.18], ["lpine", 0.1]], "tree_px": 52000, "rocks": [["boulder", 0.6], ["crystal", 0.4]], "rock_n": 70, "rock_col": Color(0.55, 0.58, 0.64),
		"deco": [["ice", 50], ["tuft", 260], ["bones", 8], ["rubble", 20]], "bush_tint": 0.9,
		"forage": [["frost_bloom", 12], ["pine_resin", 4], ["mushroom", 3]],
	},
	"highmeadow": {
		"biome": "meadow", "ground": Color(0.45, 0.6, 0.25), "alts": [Color(0.55, 0.7, 0.3, 0.55), Color(0.38, 0.52, 0.2, 0.5)],
		"tuft": Color(0.33, 0.46, 0.17), "green": Color(0.3, 0.55, 0.22), "road": [Color(0.55, 0.45, 0.3), Color(0.64, 0.54, 0.38)],
		"trees": [["loak", 0.8], ["pine", 0.2]], "tree_px": 110000, "rocks": [["rock", 1.0]], "rock_n": 36, "rock_col": Color(0.55, 0.54, 0.5),
		"deco": [["bush", 90], ["flower", 260], ["wheat", 90], ["tuft", 420], ["grass", 80]], "bush_tint": 1.1,
		"forage": [["berries", 12], ["healing_herb", 8], ["oak_wood", 5], ["mushroom", 5]],
	},
	"ironhold_hills": {
		"biome": "hills", "ground": Color(0.42, 0.4, 0.37), "alts": [Color(0.5, 0.47, 0.43, 0.55), Color(0.34, 0.32, 0.3, 0.55)],
		"tuft": Color(0.3, 0.3, 0.26), "green": Color(0.25, 0.4, 0.22), "road": [Color(0.3, 0.28, 0.26), Color(0.4, 0.37, 0.34)],
		"trees": [["dead", 0.4], ["lpine", 0.5], ["twist", 0.1]], "tree_px": 100000, "rocks": [["boulder", 0.7], ["rock", 0.3]], "rock_n": 130, "rock_col": Color(0.5, 0.46, 0.42),
		"deco": [["rubble", 60], ["tuft", 260], ["bones", 8], ["grass", 40]], "bush_tint": 0.8,
		"forage": [["iron_ore", 16], ["copper_ore", 10], ["coal", 6], ["healing_herb", 4]],
	},
	"sunscorch_dunes": {
		"biome": "desert", "ground": Color(0.86, 0.72, 0.45), "alts": [Color(0.92, 0.8, 0.52, 0.55), Color(0.78, 0.62, 0.37, 0.5)],
		"tuft": Color(0.65, 0.5, 0.28), "green": Color(0.3, 0.5, 0.25), "road": [Color(0.7, 0.55, 0.34), Color(0.78, 0.64, 0.42)],
		"trees": [["cactus", 0.6], ["dead", 0.3], ["palm", 0.1]], "tree_px": 95000, "rocks": [["boulder", 0.7], ["rock", 0.3]], "rock_n": 60, "rock_col": Color(0.72, 0.58, 0.4),
		"deco": [["bones", 30], ["rubble", 30], ["tuft", 220], ["grass", 30]], "bush_tint": 0.7,
		"forage": [["cactus_fruit", 8], ["sun_date", 4], ["amber", 4]],
	},
	"stormcoast": {
		"biome": "coast", "ground": Color(0.58, 0.6, 0.4), "alts": [Color(0.7, 0.68, 0.5, 0.5), Color(0.46, 0.53, 0.35, 0.5)],
		"tuft": Color(0.42, 0.48, 0.28), "green": Color(0.25, 0.48, 0.3), "road": [Color(0.55, 0.48, 0.36), Color(0.64, 0.57, 0.44)],
		"trees": [["palm", 0.35], ["lpine", 0.35], ["loak", 0.3]], "tree_px": 120000, "rocks": [["boulder", 0.6], ["rock", 0.4]], "rock_n": 60, "rock_col": Color(0.5, 0.52, 0.52),
		"deco": [["driftwood", 40], ["shell", 70], ["tuft", 260], ["grass", 60], ["bush", 40]], "bush_tint": 0.9,
		"forage": [["sea_kelp", 10, [[100, 6500, 80, 2000], [200, 8360, 3300, 50]]], ["pearl_shell", 6, [[100, 6500, 80, 2000], [200, 8360, 3300, 50]]], ["berries", 4]],
		"skip_edges": ["w", "s"],
	},
	"gloomfen": {
		"biome": "swamp", "ground": Color(0.2, 0.27, 0.17), "alts": [Color(0.26, 0.33, 0.2, 0.55), Color(0.14, 0.2, 0.14, 0.6)],
		"tuft": Color(0.12, 0.2, 0.1), "green": Color(0.2, 0.34, 0.2), "road": [Color(0.28, 0.24, 0.18), Color(0.36, 0.3, 0.22)],
		"trees": [["twist", 0.6], ["dead", 0.3], ["loak", 0.1]], "tree_px": 42000, "rocks": [["rock", 1.0]], "rock_n": 30, "rock_col": Color(0.38, 0.42, 0.36),
		"deco": [["reed", 150], ["mush", 60], ["bush", 60], ["tuft", 260], ["bones", 8]], "bush_tint": 0.7,
		"forage": [["bog_lily", 10], ["glowcap", 8], ["mushroom", 8], ["healing_herb", 4]],
	},
	"ashen_wastes": {
		"biome": "ash", "ground": Color(0.22, 0.2, 0.21), "alts": [Color(0.3, 0.27, 0.28, 0.55), Color(0.15, 0.13, 0.14, 0.6)],
		"tuft": Color(0.2, 0.17, 0.17), "green": Color(0.2, 0.2, 0.2), "road": [Color(0.14, 0.12, 0.12), Color(0.22, 0.2, 0.2)],
		"trees": [["dead", 0.65], ["spike", 0.35]], "tree_px": 80000, "rocks": [["spike", 0.5], ["boulder", 0.5]], "rock_n": 110, "rock_col": Color(0.26, 0.24, 0.26),
		"deco": [["rubble", 70], ["lava", 24], ["bones", 24], ["tuft", 150]], "bush_tint": 0.5,
		"forage": [["sulfur", 10], ["obsidian_shard", 8], ["coal", 6]],
	},
}


static func profile(rid: String) -> Dictionary:
	return P.get(rid, P["whispering_glades"])


static func ambient_kind(rid: String) -> String:
	return str(profile(rid).get("biome", "forest"))


static func pick(list: Array, r: RandomNumberGenerator) -> String:
	var total := 0.0
	for e in list:
		total += float(e[1])
	var x: float = r.randf() * total
	for e in list:
		x -= float(e[1])
		if x <= 0.0:
			return str(e[0])
	return str(list[list.size() - 1][0])


static func steps(d, rid: String) -> Array:
	var prof: Dictionary = profile(rid)
	var rect: Rect2 = Regions.rect_of(Regions.get_region(rid))
	var r := RandomNumberGenerator.new()
	r.seed = hash(rid)
	var out: Array = []
	var total: int = int(rect.get_area() / float(prof["tree_px"]))
	var per: int = int(ceil(total / 3.0))
	for c in 3:
		out.append(func(): _scatter_trees(d, prof, rect, r, per))
	out.append(func(): _edge_trees(d, prof, rect, r))
	out.append(func(): _scatter_rocks(d, prof, rect, r))
	out.append(func(): _scatter_deco(d, prof, rect, r))
	out.append(func(): _scatter_forage(d, prof, rect, r))
	return out


static func make_tree(d, kind: String, r: RandomNumberGenerator, prof: Dictionary) -> Array:
	var parent: Node2D = d.entities
	var green: Color = prof["green"]
	green = green.lightened(r.randf_range(-0.1, 0.12))
	var s: float = r.randf_range(0.85, 1.25)
	match kind:
		"pine":
			return [Art.pine(parent, s, r.randf_range(0.9, 1.1)), 6.0]
		"oak":
			return [Art.oak(parent, s, r.randf_range(0.9, 1.1)), 7.0]
		"dead":
			return [Art.dead_tree(parent, r.randf_range(0.9, 1.3)), 5.0]
		"lpine":
			return [ArtBiome.lite_pine(parent, s, green, false), 6.0]
		"spine":
			return [ArtBiome.lite_pine(parent, s, green, true), 6.0]
		"loak":
			return [ArtBiome.lite_oak(parent, s, green), 7.0]
		"twist":
			return [ArtBiome.twisted_tree(parent, s, green), 6.0]
		"cactus":
			return [ArtBiome.cactus(parent, r.randf_range(0.8, 1.2)), 5.0]
		"palm":
			return [ArtBiome.palm(parent, r.randf_range(0.9, 1.2)), 5.0]
		"spike":
			return [ArtBiome.obsidian_spike(parent, r.randf_range(0.8, 1.3)), 6.0]
	return [Art.pine(parent, s, 1.0), 6.0]


static func _rand_in(area: Rect2, r: RandomNumberGenerator) -> Vector2:
	return Vector2(r.randf_range(area.position.x, area.end.x), r.randf_range(area.position.y, area.end.y))


static func _scatter_trees(d, prof: Dictionary, rect: Rect2, r: RandomNumberGenerator, count: int) -> void:
	var area: Rect2 = rect.grow(-40)
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 14:
		tries += 1
		var pos: Vector2 = _rand_in(area, r)
		var n: float = d.noise.get_noise_2d(pos.x, pos.y)
		if r.randf() > clampf(0.55 + n * 1.3, 0.08, 1.0):
			continue
		if d.blocked(pos, 0.0) or not d.is_free(pos, 34.0):
			continue
		var t: Array = make_tree(d, pick(prof["trees"], r), r, prof)
		d.prop(t[0], pos, float(t[1]), 30.0)
		placed += 1


static func _edge_trees(d, prof: Dictionary, rect: Rect2, r: RandomNumberGenerator) -> void:
	var w: Rect2 = d.world_rect
	var skip: Array = prof.get("skip_edges", [])
	var spots: Array = []
	var kind: String = str(prof["trees"][0][0])
	if rect.position.y <= w.position.y + 1.0 and not skip.has("n"):
		var x: float = rect.position.x + 30.0
		while x < rect.end.x - 20.0:
			spots.append(Vector2(x, w.position.y + r.randf_range(20, 46)))
			x += r.randf_range(46, 62)
	if rect.end.y >= w.end.y - 1.0 and not skip.has("s"):
		var x2: float = rect.position.x + 30.0
		while x2 < rect.end.x - 20.0:
			spots.append(Vector2(x2, w.end.y - r.randf_range(10, 34)))
			x2 += r.randf_range(46, 62)
	if rect.position.x <= w.position.x + 1.0 and not skip.has("w"):
		var y: float = rect.position.y + 70.0
		while y < rect.end.y - 40.0:
			spots.append(Vector2(w.position.x + r.randf_range(20, 46), y))
			y += r.randf_range(46, 62)
	if rect.end.x >= w.end.x - 1.0 and not skip.has("e"):
		var y2: float = rect.position.y + 70.0
		while y2 < rect.end.y - 40.0:
			spots.append(Vector2(w.end.x - r.randf_range(20, 46), y2))
			y2 += r.randf_range(46, 62)
	for pos: Vector2 in spots:
		if d.is_free(pos, 20.0) and not d.in_zone(pos, 0.0) and not d.in_water(pos, 0.0):
			var t: Array = make_tree(d, kind, r, prof)
			(t[0] as Node2D).scale *= 1.15
			d.prop(t[0], pos, float(t[1]), 20.0)


static func _scatter_rocks(d, prof: Dictionary, rect: Rect2, r: RandomNumberGenerator) -> void:
	var area: Rect2 = rect.grow(-60)
	var count: int = int(prof["rock_n"])
	var rc: Color = prof["rock_col"]
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 12:
		tries += 1
		var pos: Vector2 = _rand_in(area, r)
		if d.blocked(pos, -6.0) or not d.is_free(pos, 18.0):
			continue
		var s: float = r.randf_range(0.7, 1.5)
		var kind: String = pick(prof["rocks"], r)
		var node: Node2D
		match kind:
			"boulder":
				node = ArtBiome.boulder(d.entities, s, rc.lightened(r.randf_range(-0.08, 0.08)))
			"spike":
				node = ArtBiome.obsidian_spike(d.entities, s)
			"crystal":
				node = ArtBiome.ice_crystal(d.entities, s)
			_:
				node = Art.rock(d.entities, s, r.randf_range(0.85, 1.1))
		d.prop(node, pos, 9.0 * minf(s, 1.2), 22.0)
		placed += 1


static func _make_deco(d, kind: String, pos: Vector2, prof: Dictionary, r: RandomNumberGenerator) -> void:
	var e: Node2D = d.entities
	var green: Color = prof["green"]
	var node: Node2D = null
	var clear := 8.0
	match kind:
		"flower":
			var col: Color = FLOWER_COLORS[r.randi_range(0, FLOWER_COLORS.size() - 1)]
			for i in r.randi_range(2, 4):
				var f: Node2D = Art.flower(d.g_deco, col)
				f.position = pos + Vector2(r.randf_range(-16, 16), r.randf_range(-10, 10))
			return
		"tuft":
			var h: float = r.randf_range(4, 8)
			var tuft: Polygon2D = Art._poly(d.g_deco, PackedVector2Array([Vector2(-3, 0), Vector2(-1.5, -h), Vector2(0, -h * 0.5), Vector2(1.5, -h * 1.1), Vector2(3, 0)]), prof["tuft"])
			tuft.position = pos
			return
		"bush":
			node = Art.bush(e, r.randf_range(0.8, 1.3), float(prof["bush_tint"]) * r.randf_range(0.9, 1.1))
			clear = 12.0
		"grass":
			node = ArtBiome.grass_clump(e, green, r.randf_range(0.8, 1.3), r.randf_range(9, 15))
		"reed":
			node = ArtBiome.reed_clump(e, green, r.randf_range(0.8, 1.3))
		"wheat":
			node = ArtBiome.wheat(e, r.randf_range(0.8, 1.2))
		"mush":
			var caps := [Color(0.75, 0.25, 0.25), Color(0.6, 0.45, 0.75), Color(0.85, 0.7, 0.3)]
			node = ArtBiome.big_mushroom(e, r.randf_range(0.8, 1.4), caps[r.randi_range(0, 2)])
			clear = 12.0
		"ice":
			node = ArtBiome.ice_crystal(e, r.randf_range(0.6, 1.1))
		"rubble":
			node = ArtBiome.rubble(e, r.randf_range(0.7, 1.3), prof["rock_col"])
		"bones":
			node = ArtBiome.bones(e, r.randf_range(0.8, 1.3))
		"driftwood":
			node = ArtBiome.driftwood(e, r.randf_range(0.8, 1.3))
		"shell":
			node = ArtBiome.shell(e, Color(0.92, 0.82, 0.76))
		"lava":
			node = ArtBiome.lava_glow(e, r.randf_range(0.8, 1.4))
			clear = 16.0
	if node != null:
		d.prop(node, pos, 0.0, clear)


static func _scatter_deco(d, prof: Dictionary, rect: Rect2, r: RandomNumberGenerator) -> void:
	var area: Rect2 = rect.grow(-40)
	for entry: Array in prof["deco"]:
		var kind: String = str(entry[0])
		var count: int = int(entry[1])
		var placed := 0
		var tries := 0
		while placed < count and tries < count * 8:
			tries += 1
			var pos: Vector2 = _rand_in(area, r)
			if d.blocked(pos, -12.0, true) or (kind != "tuft" and kind != "flower" and not d.is_free(pos, 12.0)):
				continue
			_make_deco(d, kind, pos, prof, r)
			placed += 1


static func _scatter_forage(d, prof: Dictionary, rect: Rect2, r: RandomNumberGenerator) -> void:
	for entry: Array in prof["forage"]:
		var rects: Array = []
		if entry.size() > 2:
			for a in entry[2]:
				rects.append(Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3])))
		else:
			rects.append(rect.grow(-120))
		var placed := 0
		var tries := 0
		while placed < int(entry[1]) and tries < 500:
			tries += 1
			var pos: Vector2 = _rand_in(rects[r.randi_range(0, rects.size() - 1)], r)
			if d.blocked(pos, 6.0) or not d.is_free(pos, 22.0):
				continue
			d.interactable("forage", pos, str(entry[0]))
			placed += 1
