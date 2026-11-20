extends CanvasLayer
## World map (M). Fog of war from GameState.explored_cells, discovered landmarks, region names,
## the current objective, pan / zoom, and fast travel between attuned waystones.

const Geo = preload("res://scripts/Geo.gd")
const UiStyle = preload("res://scripts/UiStyle.gd")

const FOG_COL := Color(0.04, 0.035, 0.03, 0.95)
const BG_COL := Color(0.09, 0.075, 0.06)
const MAX_ZOOM_MULT := 7.0

var _root: Control
var _view: Control
var _side: VBoxContainer
var _fog_tex: ImageTexture
var _fog_origin := Vector2.ZERO
var _fog_size := Vector2.ZERO

var _center := Vector2.ZERO
var _zoom := 0.05
var _fit := 0.05
var _dragging := false
var _drag_moved := 0.0
var _mouse := Vector2(-1000, -1000)
var _selected := ""
var _opened_paused := false
var _pulse := 0.0
var _player: Node2D


func _ready() -> void:
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 40
	panel.offset_right = -40
	panel.offset_top = 30
	panel.offset_bottom = -30
	panel.add_theme_stylebox_override("panel", UiStyle.box())
	_root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	col.add_child(UiStyle.label("WORLD MAP OF AETHELGARD", 20, UiStyle.GOLD))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	_view = Control.new()
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.clip_contents = true
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_view.draw.connect(_draw_map)
	_view.gui_input.connect(_on_view_input)
	row.add_child(_view)
	var side_scroll := ScrollContainer.new()
	side_scroll.custom_minimum_size = Vector2(270, 0)
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(side_scroll)
	_side = VBoxContainer.new()
	_side.custom_minimum_size = Vector2(262, 0)
	_side.add_theme_constant_override("separation", 6)
	side_scroll.add_child(_side)
	col.add_child(UiStyle.label("Drag to pan   |   Wheel or +/- to zoom   |   Click a place for details   |   C centers on you   |   M or Esc closes", 11, Color(0.65, 0.6, 0.5)))


# ---------------------------------------------------------------------------
# Open / close
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = (event as InputEventKey).physical_keycode
	if not _root.visible:
		if k == KEY_M and not get_tree().paused and not GameState.is_dead():
			_open()
			get_viewport().set_input_as_handled()
		return
	match k:
		KEY_M, KEY_ESCAPE:
			_close()
		KEY_C, KEY_HOME:
			_center_on_player()
		KEY_EQUAL, KEY_KP_ADD:
			_zoom_at(_view.size * 0.5, 1.25)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_zoom_at(_view.size * 0.5, 0.8)
		KEY_T:
			var lm: Dictionary = Geo.landmark(_selected)
			if not lm.is_empty() and _can_travel(lm):
				_travel(lm)
	get_viewport().set_input_as_handled()


func _open() -> void:
	_player = get_tree().get_first_node_in_group("player") as Node2D
	_opened_paused = true
	get_tree().paused = true
	_root.visible = true
	Fx.play("click")
	_build_fog()
	var wr: Rect2 = Geo.world_rect()
	await get_tree().process_frame
	_fit = minf(_view.size.x / wr.size.x, _view.size.y / wr.size.y) * 0.96
	_zoom = _fit
	_center = wr.get_center()
	_center_on_player()
	_refresh_side()


func _close() -> void:
	_root.visible = false
	if _opened_paused:
		get_tree().paused = false
	_opened_paused = false
	Fx.play("click")


func _center_on_player() -> void:
	if _player != null and is_instance_valid(_player):
		_center = _player.global_position
		_zoom = maxf(_zoom, _fit * 2.2)


func _process(delta: float) -> void:
	if not _root.visible:
		return
	_pulse += delta
	var pan := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
	if pan != Vector2.ZERO:
		_center += pan * 600.0 * delta / _zoom * 0.35
		_clamp_center()
	_view.queue_redraw()


# ---------------------------------------------------------------------------
# Fog
# ---------------------------------------------------------------------------

func _build_fog() -> void:
	var wr: Rect2 = Geo.world_rect()
	var cell := float(Geo.EXPLORE_CELL)
	var c0 := Vector2i(floori(wr.position.x / cell), floori(wr.position.y / cell))
	var c1 := Vector2i(floori(wr.end.x / cell), floori(wr.end.y / cell))
	var w: int = c1.x - c0.x + 1
	var h: int = c1.y - c0.y + 1
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(FOG_COL)
	for key: Variant in GameState.explored_cells.keys():
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() != 2:
			continue
		var x: int = int(parts[0]) - c0.x
		var y: int = int(parts[1]) - c0.y
		if x >= 0 and y >= 0 and x < w and y < h:
			img.set_pixel(x, y, Color(FOG_COL.r, FOG_COL.g, FOG_COL.b, 0.0))
	_fog_tex = ImageTexture.create_from_image(img)
	_fog_origin = Vector2(c0) * cell
	_fog_size = Vector2(w, h) * cell


# ---------------------------------------------------------------------------
# Coordinates and input
# ---------------------------------------------------------------------------

func _w2s(p: Vector2) -> Vector2:
	return (p - _center) * _zoom + _view.size * 0.5


func _s2w(s: Vector2) -> Vector2:
	return (s - _view.size * 0.5) / _zoom + _center


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before: Vector2 = _s2w(screen_pos)
	_zoom = clampf(_zoom * factor, _fit * 0.9, _fit * MAX_ZOOM_MULT)
	_center += before - _s2w(screen_pos)
	_clamp_center()


func _clamp_center() -> void:
	var wr: Rect2 = Geo.world_rect()
	_center = _center.clamp(wr.position, wr.end)


func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = (event as InputEventMouseMotion).position
		if _dragging:
			var rel: Vector2 = (event as InputEventMouseMotion).relative
			_drag_moved += rel.length()
			_center -= rel / _zoom
			_clamp_center()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.2)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.2)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_moved = 0.0
			else:
				_dragging = false
				if _drag_moved < 6.0:
					_select_at(mb.position)


func _shown_landmarks() -> Array:
	var out: Array = []
	for lm: Dictionary in Geo.landmarks():
		if GameState.discovered_landmarks.get(str(lm.get("id", "")), false):
			out.append(lm)
	return out


func _landmark_at(screen_pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 16.0
	for lm: Dictionary in _shown_landmarks():
		var d: float = _w2s(Geo.landmark_pos(lm)).distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best = lm
	return best


func _select_at(screen_pos: Vector2) -> void:
	var lm: Dictionary = _landmark_at(screen_pos)
	_selected = str(lm.get("id", ""))
	if _selected != "":
		Fx.play("click")
	_refresh_side()


# ---------------------------------------------------------------------------
# Fast travel
# ---------------------------------------------------------------------------

func _can_travel(lm: Dictionary) -> bool:
	if not bool(lm.get("waystone", false)):
		return false
	var uid: String = str(lm.get("waystone_uid", ""))
	return uid != "" and GameState.has_story_flag("waystone_" + uid)


func _travel(lm: Dictionary) -> void:
	var dest: Vector2 = Geo.landmark_pos(lm) + Vector2(0, 44)
	_close()
	if _player != null and is_instance_valid(_player):
		_player.global_position = dest
		if "velocity" in _player:
			_player.velocity = Vector2.ZERO
	EventBus.toast_requested.emit("Fast travel: %s" % str(lm.get("name", "waystone")), Color(0.6, 0.9, 1.0))


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw_map() -> void:
	var v := _view
	var font: Font = ThemeDB.fallback_font
	v.draw_rect(Rect2(Vector2.ZERO, v.size), BG_COL)
	var wr: Rect2 = Geo.world_rect()
	var world_tl: Vector2 = _w2s(wr.position)
	v.draw_rect(Rect2(world_tl, wr.size * _zoom), Color(0.17, 0.3, 0.16))
	for reg: Dictionary in Geo.regions():
		var rr: Rect2 = Geo.region_rect(reg)
		var c: Color = Geo.region_color(reg)
		v.draw_rect(Rect2(_w2s(rr.position), rr.size * _zoom), Color(c.r, c.g, c.b, 0.85))
	for road: PackedVector2Array in Geo.roads():
		var pts := PackedVector2Array()
		for pt: Vector2 in road:
			pts.append(_w2s(pt))
		if pts.size() >= 2:
			v.draw_polyline(pts, Color(0.62, 0.52, 0.36, 0.9), maxf(1.5, 28.0 * _zoom * 0.25), true)
	for reg: Dictionary in Geo.regions():
		var rr2: Rect2 = Geo.region_rect(reg)
		v.draw_rect(Rect2(_w2s(rr2.position), rr2.size * _zoom), Color(0, 0, 0, 0.35), false, 1.0)
	if _fog_tex != null:
		v.draw_texture_rect(_fog_tex, Rect2(_w2s(_fog_origin), _fog_size * _zoom), false)
	for reg: Dictionary in Geo.regions():
		var id: String = str(reg.get("id", ""))
		if not GameState.visited_regions.get(id, false):
			continue
		var rr3: Rect2 = Geo.region_rect(reg)
		var lab: String = str(reg.get("name", id)).to_upper()
		var fs := 22
		var w: float = font.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cpos: Vector2 = _w2s(rr3.get_center()) - Vector2(w * 0.5, 0.0)
		v.draw_string_outline(font, cpos, lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.6))
		v.draw_string(font, cpos, lab, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.42))
	var hover: Dictionary = _landmark_at(_mouse)
	var labels_all: bool = _zoom > _fit * 1.4
	for lm: Dictionary in _shown_landmarks():
		var sp: Vector2 = _w2s(Geo.landmark_pos(lm))
		if not Rect2(Vector2(-20, -20), v.size + Vector2(40, 40)).has_point(sp):
			continue
		var t: String = str(lm.get("type", "landmark"))
		var sel: bool = str(lm.get("id", "")) == _selected
		_draw_icon(t, sp, lm, sel)
		var major: bool = t in ["village", "harbor", "camp", "ruin", "dungeon", "tower"]
		if labels_all or major or sel or (not hover.is_empty() and hover == lm):
			var nm: String = str(lm.get("name", ""))
			var nw: float = font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var np: Vector2 = sp + Vector2(-nw * 0.5, 22.0)
			v.draw_string_outline(font, np, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.9))
			v.draw_string(font, np, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.96, 0.92, 0.8))
	_draw_objective(font)
	if _player != null and is_instance_valid(_player):
		var pp: Vector2 = _w2s(_player.global_position)
		var r: float = 9.0 + sin(_pulse * 4.0) * 1.5
		v.draw_circle(pp, r + 3.0, Color(0, 0, 0, 0.6))
		v.draw_circle(pp, r, Color(1.0, 0.92, 0.5))
		v.draw_circle(pp, r - 4.0, Color(0.95, 0.95, 0.95))
		v.draw_string_outline(font, pp + Vector2(-8, -16), "You", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.9))
		v.draw_string(font, pp + Vector2(-8, -16), "You", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1))
	v.draw_rect(Rect2(Vector2.ZERO, v.size), Color(0.6, 0.48, 0.26), false, 2.0)


func _draw_objective(font: Font) -> void:
	var tgt: Dictionary = GameState.get_objective_target()
	if tgt.is_empty():
		return
	var tp: Vector2 = _w2s(tgt["pos"])
	var v := _view
	if _player != null and is_instance_valid(_player):
		v.draw_dashed_line(_w2s(_player.global_position), tp, Color(1.0, 0.85, 0.35, 0.7), 2.0, 8.0)
	var pr: float = 12.0 + fmod(_pulse * 10.0, 14.0)
	v.draw_arc(tp, pr, 0.0, TAU, 28, Color(1.0, 0.85, 0.35, 1.0 - (pr - 12.0) / 14.0), 2.0)
	v.draw_colored_polygon(PackedVector2Array([tp + Vector2(0, -10), tp + Vector2(8, 0), tp + Vector2(0, 10), tp + Vector2(-8, 0)]), Color(1.0, 0.85, 0.3))
	v.draw_polyline(PackedVector2Array([tp + Vector2(0, -10), tp + Vector2(8, 0), tp + Vector2(0, 10), tp + Vector2(-8, 0), tp + Vector2(0, -10)]), Color(0.15, 0.08, 0.02), 2.0)
	var nm: String = "Objective: " + str(tgt.get("label", ""))
	var nw: float = font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	v.draw_string_outline(font, tp + Vector2(-nw * 0.5, -18.0), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.9))
	v.draw_string(font, tp + Vector2(-nw * 0.5, -18.0), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.9, 0.5))


func _draw_icon(t: String, p: Vector2, lm: Dictionary, selected: bool) -> void:
	var v := _view
	var ink := Color(0.98, 0.93, 0.78)
	var edge := Color(0.1, 0.07, 0.04)
	if selected:
		v.draw_arc(p, 14.0, 0.0, TAU, 24, Color(1.0, 0.85, 0.35), 2.0)
	match t:
		"village":
			v.draw_colored_polygon(PackedVector2Array([p + Vector2(-8, 6), p + Vector2(-8, -2), p + Vector2(0, -9), p + Vector2(8, -2), p + Vector2(8, 6)]), ink)
			v.draw_rect(Rect2(p + Vector2(-2, 0), Vector2(4, 6)), edge)
		"camp":
			v.draw_colored_polygon(PackedVector2Array([p + Vector2(-9, 7), p + Vector2(0, -8), p + Vector2(9, 7)]), Color(0.9, 0.35, 0.25))
			v.draw_polyline(PackedVector2Array([p + Vector2(-9, 7), p + Vector2(0, -8), p + Vector2(9, 7), p + Vector2(-9, 7)]), edge, 1.5)
		"ruin":
			v.draw_polyline(PackedVector2Array([p + Vector2(-8, 7), p + Vector2(-8, -6), p + Vector2(-3, -6), p + Vector2(-3, -1)]), ink, 2.5)
			v.draw_polyline(PackedVector2Array([p + Vector2(8, 7), p + Vector2(8, -2), p + Vector2(3, -2)]), ink, 2.5)
			v.draw_line(p + Vector2(-8, 7), p + Vector2(8, 7), ink, 2.5)
		"cave", "mine", "dungeon":
			v.draw_circle(p, 9.0, edge)
			v.draw_circle(p + Vector2(0, 1), 6.5, Color(0.55, 0.5, 0.45) if t != "dungeon" else Color(0.75, 0.3, 0.3))
			v.draw_rect(Rect2(p + Vector2(-3, -1), Vector2(6, 8)), edge)
		"tower":
			v.draw_rect(Rect2(p + Vector2(-4, -10), Vector2(8, 18)), ink)
			v.draw_rect(Rect2(p + Vector2(-6, -12), Vector2(12, 4)), ink)
			v.draw_rect(Rect2(p + Vector2(-1, -4), Vector2(2, 5)), edge)
		"shrine":
			v.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -10), p + Vector2(7, 0), p + Vector2(0, 10), p + Vector2(-7, 0)]), Color(0.7, 0.55, 0.95))
			v.draw_polyline(PackedVector2Array([p + Vector2(0, -10), p + Vector2(7, 0), p + Vector2(0, 10), p + Vector2(-7, 0), p + Vector2(0, -10)]), edge, 1.5)
		"lake":
			v.draw_circle(p, 8.0, Color(0.3, 0.55, 0.85))
			v.draw_arc(p, 8.0, 0.0, TAU, 16, edge, 1.5)
		"harbor":
			v.draw_arc(p + Vector2(0, -3), 4.0, 0.0, TAU, 12, ink, 2.0)
			v.draw_line(p + Vector2(0, 1), p + Vector2(0, 9), ink, 2.5)
			v.draw_arc(p + Vector2(0, 2), 8.0, 0.2, PI - 0.2, 12, ink, 2.5)
			v.draw_line(p + Vector2(-4, 4), p + Vector2(4, 4), ink, 2.0)
		"waystone":
			var ok: bool = _can_travel(lm)
			var c: Color = Color(0.45, 0.9, 1.0) if ok else Color(0.45, 0.5, 0.55)
			v.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -10), p + Vector2(6, 0), p + Vector2(0, 10), p + Vector2(-6, 0)]), c)
			v.draw_polyline(PackedVector2Array([p + Vector2(0, -10), p + Vector2(6, 0), p + Vector2(0, 10), p + Vector2(-6, 0), p + Vector2(0, -10)]), edge, 1.5)
		_:
			v.draw_circle(p, 6.0, ink)
			v.draw_arc(p, 6.0, 0.0, TAU, 12, edge, 1.5)


# ---------------------------------------------------------------------------
# Side panel
# ---------------------------------------------------------------------------

func _wrapped(text: String, size: int = 13, color: Color = UiStyle.TEXT) -> Label:
	var l := UiStyle.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(252, 0)
	return l


func _refresh_side() -> void:
	for c in _side.get_children():
		c.queue_free()
	var rid: String = GameState.current_region
	var reg: Dictionary = Geo.region(rid)
	_side.add_child(UiStyle.label("You are in", 11, Color(0.7, 0.65, 0.55)))
	_side.add_child(UiStyle.label(Geo.region_name(rid) if rid != "" else "the wilds", 17, UiStyle.GOLD))
	var lv: Array = reg.get("level_range", [])
	if lv.size() >= 2:
		_side.add_child(UiStyle.label("Recommended level %d-%d" % [int(lv[0]), int(lv[1])], 12, Color(0.85, 0.75, 0.55)))
	if str(reg.get("description", "")) != "":
		_side.add_child(_wrapped(str(reg["description"]), 12, Color(0.8, 0.77, 0.68)))
	var total: int = Geo.landmarks().size()
	var cells_total: int = maxi(1, int(_fog_size.x / Geo.EXPLORE_CELL) * int(_fog_size.y / Geo.EXPLORE_CELL))
	_side.add_child(HSeparator.new())
	_side.add_child(UiStyle.label("Regions seen: %d / %d" % [GameState.visited_regions.size(), maxi(Geo.regions().size(), 1)], 12))
	_side.add_child(UiStyle.label("Places found: %d / %d" % [GameState.discovered_landmarks.size(), total], 12))
	_side.add_child(UiStyle.label("Map revealed: %d%%" % int(100.0 * float(GameState.explored_cells.size()) / float(cells_total)), 12))

	var tgt: Dictionary = GameState.get_objective_target()
	if not tgt.is_empty():
		_side.add_child(HSeparator.new())
		_side.add_child(UiStyle.label("Objective", 11, Color(0.7, 0.65, 0.55)))
		_side.add_child(_wrapped(GameState.get_display_objective(), 12, Color(1.0, 0.9, 0.55)))
		var b := Button.new()
		b.text = "Show on map"
		UiStyle.style_button(b, UiStyle.GOLD)
		b.pressed.connect(func() -> void:
			_center = tgt["pos"]
			_zoom = maxf(_zoom, _fit * 2.5))
		_side.add_child(b)

	var lm: Dictionary = Geo.landmark(_selected)
	if not lm.is_empty():
		_side.add_child(HSeparator.new())
		_side.add_child(UiStyle.label(str(lm.get("name", "")), 16, UiStyle.GOLD))
		_side.add_child(UiStyle.label("%s  -  %s" % [str(lm.get("type", "place")).capitalize(), Geo.region_name(str(lm.get("region", "")))], 12, Color(0.75, 0.7, 0.6)))
		_side.add_child(_wrapped(str(lm.get("desc", "")), 12))
		if bool(lm.get("waystone", false)):
			if _can_travel(lm):
				var tb := Button.new()
				tb.text = "Fast travel here (T)"
				UiStyle.style_button(tb, Color(0.45, 0.85, 1.0))
				tb.pressed.connect(_travel.bind(lm))
				_side.add_child(tb)
			else:
				_side.add_child(_wrapped("Touch this waystone (E) to attune it and unlock fast travel.", 12, Color(0.6, 0.85, 1.0)))

	var stones: Array = []
	for l2: Dictionary in _shown_landmarks():
		if _can_travel(l2):
			stones.append(l2)
	_side.add_child(HSeparator.new())
	_side.add_child(UiStyle.label("Attuned waystones", 13, UiStyle.GOLD))
	if stones.is_empty():
		_side.add_child(_wrapped("None yet. Find and touch a waystone (E) to attune it.", 12, Color(0.65, 0.6, 0.5)))
	for s: Dictionary in stones:
		var sb := Button.new()
		sb.text = str(s.get("name", "Waystone"))
		sb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		sb.add_theme_font_size_override("font_size", 12)
		UiStyle.style_button(sb, Color(0.45, 0.85, 1.0))
		sb.pressed.connect(func() -> void:
			_selected = str(s.get("id", ""))
			_center = Geo.landmark_pos(s)
			_zoom = maxf(_zoom, _fit * 3.0)
			_refresh_side())
		_side.add_child(sb)
