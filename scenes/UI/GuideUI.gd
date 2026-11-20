extends CanvasLayer
## Player guidance: tracks region/landmark discovery and map fog, feeds the quest system with the
## player's position, shows region banners, an objective compass and one-shot contextual tips.
## Created by the HUD. Display + discovery only; all persistent state lives in GameState.

const Geo = preload("res://scripts/Geo.gd")
const UiStyle = preload("res://scripts/UiStyle.gd")

const TICK := 0.25
const REVEAL_R2 := 10

var _player: Node2D
var _tick_t := 0.0
var _target: Dictionary = {}

var _banner_box: VBoxContainer
var _banner_title: Label
var _banner_sub: Label
var _banner_queue: Array = []
var _banner_busy := false

var _compass: Control
var _tip_panel: PanelContainer
var _tip_label: Label
var _tip_busy := false
var _tip_gap := 2.5
var _session_t := 0.0


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_build()
	EventBus.quest_updated.connect(func(_a: String, _b: int, _c: String) -> void: _refresh_target())


func _build() -> void:
	_banner_box = VBoxContainer.new()
	_banner_box.anchor_left = 0.5
	_banner_box.anchor_right = 0.5
	_banner_box.offset_left = -300
	_banner_box.offset_right = 300
	_banner_box.offset_top = 92
	_banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_box.modulate.a = 0.0
	add_child(_banner_box)
	_banner_title = _outlined("", 34, UiStyle.GOLD)
	_banner_sub = _outlined("", 15, Color(0.9, 0.86, 0.75))
	_banner_box.add_child(_banner_title)
	_banner_box.add_child(_banner_sub)

	_compass = Control.new()
	_compass.set_anchors_preset(Control.PRESET_FULL_RECT)
	_compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass.draw.connect(_draw_compass)
	add_child(_compass)

	_tip_panel = PanelContainer.new()
	_tip_panel.position = Vector2(12, 124)
	_tip_panel.custom_minimum_size = Vector2(300, 0)
	_tip_panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0.07, 0.06, 0.05, 0.86), Color(0.45, 0.75, 0.9), 6, 12))
	_tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_panel.modulate.a = 0.0
	add_child(_tip_panel)
	var v := VBoxContainer.new()
	_tip_panel.add_child(v)
	v.add_child(_outlined("TIP", 11, Color(0.55, 0.85, 1.0)))
	_tip_label = _outlined("", 13, UiStyle.TEXT)
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.custom_minimum_size = Vector2(276, 0)
	v.add_child(_tip_label)


func _outlined(text: String, size: int, color: Color) -> Label:
	var l := UiStyle.label(text, size, color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ---------------------------------------------------------------------------
# Per-frame
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
		if _player == null:
			return
	_session_t += delta
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = TICK
		_tick()
	if not _banner_busy and not _banner_queue.is_empty():
		_play_banner(_banner_queue.pop_front())
	if not _tip_busy:
		_tip_gap -= delta
		if _tip_gap <= 0.0:
			_try_tip()
	if not _target.is_empty():
		_compass.queue_redraw()


func _tick() -> void:
	var p: Vector2 = _player.global_position
	var rid: String = Geo.region_id_at(p)
	if rid != "" and rid != GameState.current_region:
		_enter_region(rid)
	var cx: int = floori(p.x / float(Geo.EXPLORE_CELL))
	var cy: int = floori(p.y / float(Geo.EXPLORE_CELL))
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			if dx * dx + dy * dy <= REVEAL_R2:
				GameState.explored_cells["%d,%d" % [cx + dx, cy + dy]] = true
	for lm: Dictionary in Geo.landmarks():
		var id: String = str(lm.get("id", ""))
		if id == "" or GameState.discovered_landmarks.get(id, false):
			continue
		if p.distance_to(Geo.landmark_pos(lm)) <= float(lm.get("reveal_radius", 300.0)):
			_discover(lm)
	GameState.notify_player_pos(p)
	_refresh_target()


func _refresh_target() -> void:
	_target = GameState.get_objective_target()


func _enter_region(rid: String) -> void:
	var first: bool = not GameState.visited_regions.get(rid, false)
	GameState.current_region = rid
	GameState.visited_regions[rid] = true
	var reg: Dictionary = Geo.region(rid)
	var rname: String = Geo.region_name(rid)
	EventBus.region_entered.emit(rid, rname)
	var lv: Array = reg.get("level_range", [])
	var sub := ""
	if lv.size() >= 2:
		sub = "Recommended level %d-%d" % [int(lv[0]), int(lv[1])]
	if first and GameState.visited_regions.size() > 1:
		sub = ("New region discovered   " + sub).strip_edges()
	_banner_queue.append({"title": rname, "sub": sub, "color": UiStyle.GOLD, "size": 34})
	if lv.size() >= 2 and not GameState.has_story_flag("warn_" + rid):
		var mine: int = int(GameState.class_data[GameState.active_class]["level"])
		if int(lv[0]) > mine + 2:
			GameState.set_story_flag("warn_" + rid, true)
			EventBus.toast_requested.emit("%s is dangerous for level %d. Tread carefully." % [rname, mine], Color(1.0, 0.5, 0.4))


func _discover(lm: Dictionary) -> void:
	var id: String = str(lm.get("id", ""))
	GameState.discovered_landmarks[id] = true
	var lname: String = str(lm.get("name", id))
	EventBus.landmark_discovered.emit(id, lname)
	if str(lm.get("type", "")) != "waystone":
		_banner_queue.append({"title": lname, "sub": str(lm.get("desc", "")), "color": Color(0.9, 0.85, 0.7), "size": 24})


func _play_banner(b: Dictionary) -> void:
	_banner_busy = true
	_banner_title.text = str(b["title"])
	_banner_title.add_theme_font_size_override("font_size", int(b["size"]))
	_banner_title.add_theme_color_override("font_color", b["color"])
	_banner_sub.text = str(b["sub"])
	var tw := create_tween()
	tw.tween_property(_banner_box, "modulate:a", 1.0, 0.5)
	tw.tween_interval(2.6)
	tw.tween_property(_banner_box, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func() -> void: _banner_busy = false)


# ---------------------------------------------------------------------------
# Objective compass
# ---------------------------------------------------------------------------

func _draw_compass() -> void:
	if _target.is_empty() or _player == null:
		return
	var tpos: Vector2 = _target["pos"]
	var ppos: Vector2 = _player.global_position
	if ppos.distance_to(tpos) < float(_target.get("radius", 120.0)):
		return
	var vp := get_viewport()
	var size: Vector2 = vp.get_visible_rect().size
	var sp: Vector2 = vp.get_canvas_transform() * tpos
	var font: Font = ThemeDB.fallback_font
	var text := "%s  %s" % [str(_target.get("label", "")), Geo.distance_text(ppos, tpos)]
	var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var inset := Rect2(Vector2(60, 70), size - Vector2(120, 190))
	var col := Color(1.0, 0.85, 0.35)
	if inset.has_point(sp):
		var bob: float = sin(Time.get_ticks_msec() * 0.005) * 4.0
		var tip: Vector2 = sp + Vector2(0, -46.0 + bob)
		_chevron(tip, Vector2.DOWN, col)
		_compass_text(font, text, Vector2(clampf(tip.x - tw * 0.5, 8.0, size.x - tw - 8.0), tip.y - 26.0), col)
	else:
		var c: Vector2 = inset.get_center()
		var dir: Vector2 = sp - c
		if dir.length() < 1.0:
			return
		var half: Vector2 = inset.size * 0.5
		var k: float = minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
		var pos: Vector2 = c + dir * k
		var dn: Vector2 = dir.normalized()
		_chevron(pos, dn, col)
		var tp: Vector2 = pos - dn * 40.0
		_compass_text(font, text, Vector2(clampf(tp.x - tw * 0.5, 8.0, size.x - tw - 8.0), tp.y + 4.0), col)


func _chevron(tip: Vector2, dir: Vector2, col: Color) -> void:
	var perp := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([tip, tip - dir * 20.0 + perp * 13.0, tip - dir * 13.0, tip - dir * 20.0 - perp * 13.0])
	_compass.draw_colored_polygon(pts, col)
	_compass.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0.1, 0.06, 0.02), 2.0)


func _compass_text(font: Font, text: String, pos: Vector2, col: Color) -> void:
	_compass.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.9))
	_compass.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)


# ---------------------------------------------------------------------------
# Contextual tips (each shown once per save)
# ---------------------------------------------------------------------------

const TIPS := [
	["intro", "Welcome to Aethelgard. Move with WASD and follow the gold arrow to your first objective. Press E near people and objects."],
	["talk", "Press E to talk. A gold ! over a head means a new quest, a ? means someone is waiting for your report. Ask them about anything: rumours, the road, their past."],
	["attack", "Enemies nearby. Hold Space to attack, Shift to dodge, Q for your class special."],
	["journal", "Press J to open your journal: track quests, read what to do next and see which rumours are worth chasing."],
	["satchel", "Press I to open your satchel. Every item has lore, tells you where to find it and what it is used for."],
	["hunger", "You are getting hungry. Press F to eat your best food. Raw meat is poor fare: cook it at a campfire first."],
	["map", "Press M to open the world map. Areas reveal themselves as you explore, and attuned waystones let you fast travel."],
	["waystone", "Waystones attune you: you wake at the last one you touched if you fall, and you can fast travel between attuned waystones from the map (M)."],
	["campfire", "Campfires (E) cook raw food, and give warm light against the dark."],
	["night", "Night falls and the wilds grow bolder. Keep to lit paths and villages, or bed down by a campfire."],
	["class", "Press C to change class. Each class levels separately and has its own special ability."],
]


func _tip_ready(id: String) -> bool:
	var p: Vector2 = _player.global_position
	match id:
		"intro":
			return _session_t > 1.5
		"talk":
			return _near_group("npcs", p, 150.0)
		"attack":
			return _near_group("enemies", p, 380.0)
		"journal":
			return GameState.get_active_quests().size() > 0 and GameState.has_story_flag("hint_talk")
		"satchel":
			var n := 0
			for k: String in GameState.inventory.keys():
				n += int(GameState.inventory[k])
			return n > 0
		"hunger":
			return GameState.hunger < 62.0
		"map":
			return _session_t > 50.0 and GameState.has_story_flag("hint_journal")
		"waystone":
			return _near_kind(p, "waystone", 170.0)
		"campfire":
			return _near_kind(p, "campfire", 170.0)
		"night":
			return GameState.get_darkness() > 0.55
		"class":
			return int(GameState.class_data[GameState.active_class]["level"]) >= 2
	return false


func _near_group(group: String, p: Vector2, r: float) -> bool:
	for n: Node in get_tree().get_nodes_in_group(group):
		if p.distance_to((n as Node2D).global_position) < r:
			return true
	return false


func _near_kind(p: Vector2, kind: String, r: float) -> bool:
	for n: Node in get_tree().get_nodes_in_group("interactable"):
		if n.get("kind") == kind and p.distance_to((n as Node2D).global_position) < r:
			return true
	return false


func _try_tip() -> void:
	_tip_gap = 1.0
	for t: Array in TIPS:
		var id: String = t[0]
		if GameState.has_story_flag("hint_" + id):
			continue
		if _tip_ready(id):
			GameState.set_story_flag("hint_" + id, true)
			_show_tip(str(t[1]))
			return


func _show_tip(text: String) -> void:
	_tip_busy = true
	_tip_label.text = text
	var tw := create_tween()
	tw.tween_property(_tip_panel, "modulate:a", 1.0, 0.4)
	tw.tween_interval(clampf(3.0 + text.length() * 0.055, 6.0, 12.0))
	tw.tween_property(_tip_panel, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func() -> void:
		_tip_busy = false
		_tip_gap = 3.0)
