extends CanvasLayer
## HUD: vitals, quest tracker, clock, minimap, hotbar (special / dodge / food), toasts, boss bar,
## interact prompt, low-HP vignette and death overlay. Pure display -- reads GameState and the
## live scene, refreshes on EventBus signals, never mutates game state.

const PANEL_BG := Color(0.07, 0.06, 0.05, 0.78)
const PANEL_EDGE := Color(0.55, 0.45, 0.25, 0.9)
const GOLD := Color(0.95, 0.82, 0.45)
const Geo = preload("res://scripts/Geo.gd")
const GuideUI = preload("res://scenes/UI/GuideUI.gd")
const MapUI = preload("res://scenes/UI/MapUI.gd")
const JournalUI = preload("res://scenes/UI/JournalUI.gd")
const MINIMAP_SIZE := Vector2(200, 130)
const MINIMAP_VIEW_W := 1500.0
const DODGE_COOLDOWN := 0.8

var _hp_bar: ProgressBar
var _hunger_bar: ProgressBar
var _exp_bar: ProgressBar
var _hp_text: Label
var _hunger_text: Label
var _exp_text: Label
var _class_label: Label
var _quest_label: Label
var _quest_title: Label
var _quest_hint: Label
var _quest_dist: Label
var _region_label: Label
var _quest_panel: PanelContainer
var _clock_label: Label
var _toasts: VBoxContainer
var _prompt: PanelContainer
var _prompt_key: Label
var _prompt_text: Label
var _boss_panel: PanelContainer
var _boss_name: Label
var _boss_bar: ProgressBar
var _vignette: TextureRect
var _death: ColorRect
var _death_label: Label
var _minimap: Control
var _special_slot: Control
var _special_fill: ColorRect
var _special_label: Label
var _special_name: Label
var _dodge_fill: ColorRect
var _food_count: Label
var _special_cd := 0.0
var _special_total := 1.0
var _player: Node2D
var _mini_timer := 0.0
var _hurt_flash := 0.0
var _last_hp := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build_vitals()
	_build_top_right()
	_build_hotbar()
	_build_toasts_and_prompt()
	_build_boss_bar()
	_build_overlays()
	EventBus.vitals_changed.connect(_refresh_vitals)
	EventBus.inventory_changed.connect(_refresh_food)
	EventBus.class_changed.connect(_on_class_changed)
	EventBus.quest_updated.connect(_on_quest_updated)
	EventBus.toast_requested.connect(_on_toast)
	EventBus.special_used.connect(_on_special_used)
	EventBus.interact_prompt_changed.connect(_on_prompt)
	EventBus.boss_engaged.connect(_on_boss_engaged)
	EventBus.boss_hp_changed.connect(_on_boss_hp)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.player_died.connect(_on_player_died)
	EventBus.player_respawned.connect(_on_player_respawned)
	_refresh_vitals()
	_refresh_food()
	_refresh_special_slot()
	_refresh_quest()
	EventBus.region_entered.connect(func(_id: String, _n: String) -> void: _refresh_quest())
	add_child(GuideUI.new())
	add_child(MapUI.new())
	add_child(JournalUI.new())


# ---------------------------------------------------------------------------
# Construction helpers
# ---------------------------------------------------------------------------

func _panel_style(bg: Color = PANEL_BG, edge: Color = PANEL_EDGE, radius: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	return sb


func _make_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel_style())
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _make_label(text: String, size: int = 14, color: Color = Color(0.93, 0.9, 0.82)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _make_bar(parent: Control, fill: Color, height: float = 16.0) -> Array:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, height)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.1, 0.09, 0.95)
	bg.set_corner_radius_all(3)
	bg.border_color = Color(0, 0, 0, 0.8)
	bg.set_border_width_all(1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	var txt := _make_label("", 11)
	txt.set_anchors_preset(Control.PRESET_FULL_RECT)
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	txt.add_theme_constant_override("outline_size", 2)
	bar.add_child(txt)
	parent.add_child(bar)
	return [bar, txt]


func _build_vitals() -> void:
	var root := _make_panel()
	root.position = Vector2(12, 12)
	root.custom_minimum_size = Vector2(252, 0)
	add_child(root)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	root.add_child(vb)
	_class_label = _make_label("", 14, GOLD)
	vb.add_child(_class_label)
	var hp: Array = _make_bar(vb, Color(0.78, 0.18, 0.18), 18.0)
	_hp_bar = hp[0]
	_hp_text = hp[1]
	var hu: Array = _make_bar(vb, Color(0.8, 0.55, 0.14), 12.0)
	_hunger_bar = hu[0]
	_hunger_text = hu[1]
	var ex: Array = _make_bar(vb, Color(0.28, 0.52, 0.9), 10.0)
	_exp_bar = ex[0]
	_exp_text = ex[1]


func _build_top_right() -> void:
	var box := VBoxContainer.new()
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -300
	box.offset_right = -12
	box.offset_top = 12
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_quest_panel = _make_panel()
	box.add_child(_quest_panel)
	var qv := VBoxContainer.new()
	_quest_panel.add_child(qv)
	qv.add_child(_make_label("CURRENT QUEST", 10, GOLD))
	_quest_title = _make_label("", 14, GOLD)
	_quest_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_title.custom_minimum_size = Vector2(260, 0)
	qv.add_child(_quest_title)
	_quest_label = _make_label("", 13)
	_quest_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_label.custom_minimum_size = Vector2(260, 0)
	qv.add_child(_quest_label)
	_quest_hint = _make_label("", 11, Color(0.6, 0.85, 1.0))
	_quest_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_hint.custom_minimum_size = Vector2(260, 0)
	qv.add_child(_quest_hint)
	_quest_dist = _make_label("", 11, Color(1.0, 0.85, 0.4))
	qv.add_child(_quest_dist)
	qv.add_child(_make_label("[J] Journal   [M] Map", 10, Color(0.7, 0.66, 0.56)))

	var mp := _make_panel()
	mp.size_flags_horizontal = Control.SIZE_SHRINK_END
	box.add_child(mp)
	var mv := VBoxContainer.new()
	mp.add_child(mv)
	_clock_label = _make_label("", 12, GOLD)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(_clock_label)
	_minimap = Control.new()
	_minimap.custom_minimum_size = MINIMAP_SIZE
	_minimap.clip_contents = true
	_minimap.draw.connect(_draw_minimap)
	mv.add_child(_minimap)
	_region_label = _make_label("", 11, Color(0.9, 0.86, 0.72))
	_region_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(_region_label)


func _build_hotbar() -> void:
	var bar := HBoxContainer.new()
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -110
	bar.offset_right = 110
	bar.offset_top = -78
	bar.offset_bottom = -12
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 10)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	_special_slot = _make_slot(bar, "Q")
	_special_fill = _special_slot.get_meta("fill")
	_special_label = _special_slot.get_meta("center")
	_special_name = _special_slot.get_meta("caption")

	var dodge := _make_slot(bar, "Shift")
	_dodge_fill = dodge.get_meta("fill")
	(dodge.get_meta("center") as Label).text = "Dodge"
	(dodge.get_meta("caption") as Label).text = ""

	var food := _make_slot(bar, "F")
	_food_count = food.get_meta("center")
	(food.get_meta("caption") as Label).text = "Eat"
	(food.get_meta("fill") as ColorRect).visible = false


func _make_slot(parent: Control, key: String) -> Control:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(66, 58)
	slot.add_theme_stylebox_override("panel", _panel_style(PANEL_BG, PANEL_EDGE, 8))
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(slot)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(holder)
	var fill := ColorRect.new()
	fill.color = Color(0, 0, 0, 0.62)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.anchor_left = 0.0
	fill.anchor_right = 1.0
	fill.anchor_top = 1.0
	fill.anchor_bottom = 1.0
	holder.add_child(fill)
	var center := _make_label("", 13)
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(center)
	var keycap := _make_label(key, 11, GOLD)
	keycap.position = Vector2(-4, -8)
	holder.add_child(keycap)
	var caption := _make_label("", 10, Color(0.8, 0.78, 0.7))
	caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.offset_top = -14
	holder.add_child(caption)
	slot.set_meta("fill", fill)
	slot.set_meta("center", center)
	slot.set_meta("caption", caption)
	return slot


func _build_toasts_and_prompt() -> void:
	_toasts = VBoxContainer.new()
	_toasts.anchor_left = 0.5
	_toasts.anchor_right = 0.5
	_toasts.anchor_top = 1.0
	_toasts.anchor_bottom = 1.0
	_toasts.offset_left = -260
	_toasts.offset_right = 260
	_toasts.offset_top = -260
	_toasts.offset_bottom = -140
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.add_theme_constant_override("separation", 4)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)

	_prompt = _make_panel()
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.offset_top = -124
	_prompt.offset_bottom = -92
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.visible = false
	add_child(_prompt)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	_prompt.add_child(hb)
	_prompt_key = _make_label("E", 14, GOLD)
	hb.add_child(_prompt_key)
	_prompt_text = _make_label("", 14)
	hb.add_child(_prompt_text)


func _build_boss_bar() -> void:
	_boss_panel = _make_panel()
	_boss_panel.anchor_left = 0.5
	_boss_panel.anchor_right = 0.5
	_boss_panel.offset_left = -240
	_boss_panel.offset_right = 240
	_boss_panel.offset_top = 14
	_boss_panel.visible = false
	add_child(_boss_panel)
	var vb := VBoxContainer.new()
	_boss_panel.add_child(vb)
	_boss_name = _make_label("", 15, Color(1.0, 0.75, 0.5))
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_boss_name)
	_boss_bar = _make_bar(vb, Color(0.7, 0.12, 0.12), 14.0)[0]


func _build_overlays() -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(0.8, 0.0, 0.0, 0.0))
	grad.set_color(1, Color(0.8, 0.0, 0.0, 0.85))
	grad.set_offset(0, 0.55)
	grad.set_offset(1, 1.0)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	_vignette = TextureRect.new()
	_vignette.texture = tex
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	add_child(_vignette)

	_death = ColorRect.new()
	_death.color = Color(0.05, 0.0, 0.0, 0.0)
	_death.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_death)
	_death_label = _make_label("YOU HAVE FALLEN", 44, Color(0.85, 0.2, 0.18))
	_death_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_label.modulate.a = 0.0
	_death.add_child(_death_label)


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

func _refresh_vitals() -> void:
	_hp_bar.max_value = GameState.max_hp
	_hp_bar.value = GameState.hp
	_hp_text.text = "%d / %d" % [ceili(GameState.hp), int(GameState.max_hp)]
	_hunger_bar.max_value = 100.0
	_hunger_bar.value = GameState.hunger
	_hunger_text.text = "Hunger %d%%" % int(GameState.hunger) if GameState.hunger > GameState.HUNGER_LOW_THRESHOLD else "STARVING"
	var entry: Dictionary = GameState.class_data[GameState.active_class]
	_exp_bar.max_value = GameState.get_exp_to_next_level(GameState.active_class)
	_exp_bar.value = entry["exp"]
	_exp_text.text = "EXP %d / %d" % [int(entry["exp"]), GameState.get_exp_to_next_level(GameState.active_class)]
	var display_name: String = GameState.class_defs.get(GameState.active_class, {}).get("display_name", GameState.active_class)
	_class_label.text = "%s  Lv.%d  -  %s" % [display_name, int(entry["level"]), GameState.get_equipped_tier_name(GameState.active_class)]
	if _last_hp >= 0.0 and GameState.hp < _last_hp - 0.5:
		_hurt_flash = 0.45
	_last_hp = GameState.hp


func _refresh_food() -> void:
	var n := 0
	for id in GameState.get_food_items():
		n += int(GameState.inventory.get(id, 0))
	_food_count.text = "x%d" % n
	_food_count.modulate = Color(1, 1, 1) if n > 0 else Color(0.5, 0.5, 0.5)


func _refresh_special_slot() -> void:
	var sp: Dictionary = GameState.class_defs.get(GameState.active_class, {}).get("special", {})
	_special_name.text = str(sp.get("name", ""))
	_special_total = maxf(0.1, float(sp.get("cooldown", 8.0)))
	_special_cd = 0.0


func _on_class_changed(_class_id: String) -> void:
	_refresh_vitals()
	_refresh_special_slot()


func _on_special_used(cooldown: float) -> void:
	_special_total = maxf(0.1, cooldown)
	_special_cd = cooldown


func _refresh_quest() -> void:
	var qid: String = GameState.get_tracked_quest()
	_quest_title.text = GameState.get_quest_title(qid) if qid != "" else "Free exploration"
	_quest_label.text = GameState.get_display_objective()
	var hint: String = str(GameState.get_current_stage(qid).get("hint", "")) if qid != "" else ""
	_quest_hint.text = ("Hint: " + hint) if hint != "" else ""
	_quest_hint.visible = hint != ""


func _on_quest_updated(_quest_id: String, _stage: int, _objective: String) -> void:
	_refresh_quest()
	_quest_panel.modulate = Color(1.6, 1.4, 0.9)
	_quest_panel.create_tween().tween_property(_quest_panel, "modulate", Color.WHITE, 1.2)


func _on_toast(text: String, color: Color) -> void:
	var p := _make_panel()
	p.add_theme_stylebox_override("panel", _panel_style(Color(0.07, 0.06, 0.05, 0.82), color.darkened(0.2), 5))
	var l := _make_label(text, 14, color.lightened(0.15))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.modulate.a = 0.0
	_toasts.add_child(p)
	while _toasts.get_child_count() > 5:
		var old: Node = _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(3.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


func _on_prompt(text: String) -> void:
	if text == "":
		_prompt.visible = false
		return
	var parts: PackedStringArray = text.split(" ", false, 1)
	_prompt_key.text = parts[0] if parts.size() > 1 else "E"
	_prompt_text.text = parts[1].strip_edges() if parts.size() > 1 else text
	_prompt.visible = true


func _on_boss_engaged(display_name: String, max_hp: float) -> void:
	_boss_name.text = display_name
	_boss_bar.max_value = max_hp
	_boss_bar.value = max_hp
	_boss_panel.visible = true


func _on_boss_hp(hp: float, max_hp: float) -> void:
	_boss_bar.max_value = max_hp
	_boss_bar.value = hp


func _on_boss_defeated() -> void:
	_boss_bar.value = 0
	get_tree().create_timer(2.0).timeout.connect(func() -> void: _boss_panel.visible = false)


func _on_player_died() -> void:
	create_tween().tween_property(_death, "color:a", 0.7, 0.8)
	create_tween().tween_property(_death_label, "modulate:a", 1.0, 0.8)


func _on_player_respawned() -> void:
	create_tween().tween_property(_death, "color:a", 0.0, 0.8)
	create_tween().tween_property(_death_label, "modulate:a", 0.0, 0.5)


# ---------------------------------------------------------------------------
# Per-frame
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	_special_cd = maxf(0.0, _special_cd - delta)
	_set_cooldown_fill(_special_fill, _special_cd / _special_total, _special_slot.get_meta("center") as Label, _special_cd)
	if _special_cd <= 0.0:
		_special_label.text = "READY"
		_special_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	else:
		_special_label.add_theme_color_override("font_color", Color(0.93, 0.9, 0.82))
	var dcd: float = 0.0
	if _player != null:
		dcd = float(_player.get("_dodge_cd"))
	_dodge_fill.anchor_top = 1.0 - clampf(dcd / DODGE_COOLDOWN, 0.0, 1.0)

	var hour: float = GameState.get_clock_hour()
	var h := int(hour)
	var night: bool = GameState.get_darkness() > 0.5
	_clock_label.text = "%02d:%02d  %s" % [h, int((hour - h) * 60.0), "Night" if night else "Day"]

	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	var low: float = clampf((0.4 - GameState.hp / maxf(GameState.max_hp, 1.0)) / 0.4, 0.0, 1.0)
	var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
	_vignette.modulate.a = clampf(low * (0.45 + 0.35 * pulse) + _hurt_flash * 1.2, 0.0, 1.0)

	_mini_timer -= delta
	if _mini_timer <= 0.0:
		_mini_timer = 0.1
		_minimap.queue_redraw()
		_region_label.text = Geo.region_name(GameState.current_region) if GameState.current_region != "" else ""
		var tgt: Dictionary = GameState.get_objective_target()
		if _player != null and not tgt.is_empty() and tgt.has("pos"):
			_quest_dist.text = "%s  -  %s" % [str(tgt.get("label", "")), Geo.distance_text(_player.global_position, tgt["pos"])]
		else:
			_quest_dist.text = ""


func _set_cooldown_fill(fill: ColorRect, frac: float, label: Label, cd: float) -> void:
	fill.anchor_top = 1.0 - clampf(frac, 0.0, 1.0)
	if cd > 0.0:
		label.text = "%.1f" % cd


# ---------------------------------------------------------------------------
# Minimap (local view centred on the player)
# ---------------------------------------------------------------------------

func _draw_minimap() -> void:
	var m := _minimap
	var scale: float = MINIMAP_SIZE.x / MINIMAP_VIEW_W
	m.draw_rect(Rect2(Vector2.ZERO, MINIMAP_SIZE), Color(0.1, 0.09, 0.08))
	if _player == null:
		return
	var origin: Vector2 = _player.global_position
	var half: Vector2 = MINIMAP_SIZE * 0.5
	var to_map := func(p: Vector2) -> Vector2: return (p - origin) * scale + half
	for reg: Dictionary in Geo.regions():
		var rr: Rect2 = Geo.region_rect(reg)
		var c: Color = Geo.region_color(reg)
		m.draw_rect(Rect2(to_map.call(rr.position), rr.size * scale), Color(c.r, c.g, c.b, 1.0))
	if Geo.regions().is_empty():
		var wr: Rect2 = Geo.world_rect()
		m.draw_rect(Rect2(to_map.call(wr.position), wr.size * scale), Color(0.2, 0.34, 0.18))
	for road: PackedVector2Array in Geo.roads():
		var pts := PackedVector2Array()
		for pt: Vector2 in road:
			pts.append(to_map.call(pt))
		if pts.size() >= 2:
			m.draw_polyline(pts, Color(0.6, 0.5, 0.35, 0.9), 1.5)
	for lm: Dictionary in Geo.landmarks():
		if not GameState.discovered_landmarks.get(str(lm.get("id", "")), false):
			continue
		var lp: Vector2 = to_map.call(Geo.landmark_pos(lm))
		var t: String = str(lm.get("type", ""))
		var col := Color(0.95, 0.9, 0.75)
		if t == "waystone":
			col = Color(0.5, 0.85, 1.0)
		elif t == "camp" or t == "dungeon":
			col = Color(0.9, 0.35, 0.25)
		m.draw_rect(Rect2(lp - Vector2(2.5, 2.5), Vector2(5, 5)), col)
	for e: Node in get_tree().get_nodes_in_group("enemies"):
		var ep: Vector2 = (e as Node2D).global_position
		if ep.distance_to(origin) < 500.0:
			m.draw_circle(to_map.call(ep), 1.8, Color(1.0, 0.35, 0.3))
	for npc: Node in get_tree().get_nodes_in_group("npcs"):
		var np: Vector2 = (npc as Node2D).global_position
		if np.distance_to(origin) < MINIMAP_VIEW_W * 0.5:
			m.draw_circle(to_map.call(np), 2.0, Color(1.0, 0.9, 0.4))
	var tgt: Dictionary = GameState.get_objective_target()
	if not tgt.is_empty() and tgt.has("pos"):
		var tp: Vector2 = to_map.call(tgt["pos"])
		var inner := Rect2(Vector2(6, 6), MINIMAP_SIZE - Vector2(12, 12))
		var on_edge: bool = not inner.has_point(tp)
		if on_edge:
			var dir: Vector2 = tp - half
			var k: float = minf((half.x - 6.0) / maxf(absf(dir.x), 0.001), (half.y - 6.0) / maxf(absf(dir.y), 0.001))
			tp = half + dir * k
		m.draw_colored_polygon(PackedVector2Array([tp + Vector2(0, -5), tp + Vector2(4, 0), tp + Vector2(0, 5), tp + Vector2(-4, 0)]), Color(1.0, 0.85, 0.3))
	var pc: Vector2 = half
	m.draw_circle(pc, 3.2, Color(1, 1, 1))
	m.draw_arc(pc, 3.8, 0, TAU, 12, Color(0, 0, 0), 1.0)
	m.draw_rect(Rect2(Vector2.ZERO, MINIMAP_SIZE), Color(0, 0, 0, 0.8), false, 1.0)
