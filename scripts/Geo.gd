extends RefCounted
## Thin, fail-soft wrapper around scripts/Regions.gd so the map, HUD and guide keep working
## (with a single-region fallback) even if the region data is missing.

const FALLBACK_RECT := Rect2(-150, -150, 2000, 1300)
const EXPLORE_CELL := 200

static var _R: Variant = null
static var _tried := false


static func _regions() -> Variant:
	if not _tried:
		_tried = true
		if ResourceLoader.exists("res://scripts/Regions.gd"):
			_R = load("res://scripts/Regions.gd")
	return _R


static func available() -> bool:
	return _regions() != null


static func world_rect() -> Rect2:
	var r: Variant = _regions()
	return r.world_rect() if r != null else FALLBACK_RECT


static func regions() -> Array:
	var r: Variant = _regions()
	return r.all() if r != null else []


static func region_id_at(pos: Vector2) -> String:
	var r: Variant = _regions()
	return str(r.region_id_at(pos)) if r != null else "whispering_glades"


static func region(id: String) -> Dictionary:
	var r: Variant = _regions()
	return r.get_region(id) if r != null else {}


static func region_rect(reg: Dictionary) -> Rect2:
	var a: Array = reg.get("rect", [0, 0, 0, 0])
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


static func region_name(id: String) -> String:
	var reg: Dictionary = region(id)
	if reg.is_empty():
		return id.capitalize().replace("_", " ")
	return str(reg.get("name", id))


static func region_color(reg: Dictionary) -> Color:
	return Color.html(str(reg.get("color", "#557744")))


static func landmarks() -> Array:
	var r: Variant = _regions()
	return r.landmarks() if r != null else []


static func landmark(id: String) -> Dictionary:
	var r: Variant = _regions()
	return r.get_landmark(id) if r != null else {}


static func landmark_pos(lm: Dictionary) -> Vector2:
	if lm.has("pos_v"):
		return lm["pos_v"]
	var a: Array = lm.get("pos", [0, 0])
	return Vector2(float(a[0]), float(a[1]))


static func roads() -> Array:
	var r: Variant = _regions()
	if r == null:
		return []
	return r.roads()


static func cell_key(pos: Vector2) -> String:
	return "%d,%d" % [floori(pos.x / float(EXPLORE_CELL)), floori(pos.y / float(EXPLORE_CELL))]


## Short "how far" text: paces are ~1/20 of a world unit.
static func distance_text(from: Vector2, to: Vector2) -> String:
	var d: float = from.distance_to(to) / 20.0
	return "%dm" % int(round(d / 5.0) * 5.0) if d >= 100.0 else "%dm" % int(d)
