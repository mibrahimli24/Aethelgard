extends RefCounted
## Static region / landmark lookup over data/regions.json (cached after first load).
## Everything is a static func so UI code can call e.g. Regions.region_id_at(pos) freely.

const DATA_PATH := "res://data/regions.json"

static var _data: Dictionary = {}
static var _loaded := false
static var _regions: Array = []
static var _landmarks: Array = []
static var _landmark_index: Dictionary = {}
static var _region_index: Dictionary = {}
static var _world := Rect2(-150, -150, 12000, 9000)


static func load_data() -> Dictionary:
	if _loaded:
		return _data
	_loaded = true
	if FileAccess.file_exists(DATA_PATH):
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			_data = parsed
	var wr: Array = _data.get("world_rect", [-150, -150, 12000, 9000])
	_world = Rect2(float(wr[0]), float(wr[1]), float(wr[2]), float(wr[3]))
	_regions = _data.get("regions", [])
	for r: Dictionary in _regions:
		_region_index[str(r.get("id", ""))] = r
		var rr: Array = r.get("rect", [0, 0, 1, 1])
		r["rect_v"] = Rect2(float(rr[0]), float(rr[1]), float(rr[2]), float(rr[3]))
		for lm: Dictionary in r.get("landmarks", []):
			lm["region"] = str(r.get("id", ""))
			var p: Array = lm.get("pos", [0, 0])
			lm["pos_v"] = Vector2(float(p[0]), float(p[1]))
			var spots: Array = []
			for s in lm.get("npc_spots", []):
				spots.append(Vector2(float(s[0]), float(s[1])))
			lm["spots_v"] = spots
			_landmarks.append(lm)
			_landmark_index[str(lm.get("id", ""))] = lm
	return _data


static func world_rect() -> Rect2:
	load_data()
	return _world


static func all() -> Array:
	load_data()
	return _regions


static func rect_of(region: Dictionary) -> Rect2:
	load_data()
	if region.has("rect_v"):
		return region["rect_v"]
	var rr: Array = region.get("rect", [0, 0, 1, 1])
	return Rect2(float(rr[0]), float(rr[1]), float(rr[2]), float(rr[3]))


static func region_at(pos: Vector2) -> Dictionary:
	load_data()
	for r: Dictionary in _regions:
		if (r["rect_v"] as Rect2).has_point(pos):
			return r
	# outside every rect (border padding): nearest region by clamped distance
	var best: Dictionary = {}
	var best_d := INF
	for r: Dictionary in _regions:
		var rc: Rect2 = r["rect_v"]
		var c := Vector2(clampf(pos.x, rc.position.x, rc.end.x), clampf(pos.y, rc.position.y, rc.end.y))
		var d: float = pos.distance_squared_to(c)
		if d < best_d:
			best_d = d
			best = r
	return best


static func region_id_at(pos: Vector2) -> String:
	return str(region_at(pos).get("id", ""))


static func landmarks() -> Array:
	load_data()
	return _landmarks


static func get_landmark(id: String) -> Dictionary:
	load_data()
	return _landmark_index.get(id, {})


static func get_region(id: String) -> Dictionary:
	load_data()
	return _region_index.get(id, {})


static func roads() -> Array:
	load_data()
	var out: Array = []
	for road in _data.get("roads", []):
		var pts := PackedVector2Array()
		for p in road:
			pts.append(Vector2(float(p[0]), float(p[1])))
		out.append(pts)
	return out
