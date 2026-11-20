extends CanvasLayer
## Journal (J): active quests with stage checklist and hints, rumours (quests you can still pick up),
## completed quests, and a controls cheat-sheet. Lets the player choose which quest is tracked.

const Geo = preload("res://scripts/Geo.gd")
const UiStyle = preload("res://scripts/UiStyle.gd")

const CONTROLS := [
	["WASD / Arrows", "Move"],
	["Space", "Attack (hold to keep swinging)"],
	["Shift", "Dodge roll"],
	["Q", "Class special ability"],
	["E", "Talk / interact / gather / attune waystones"],
	["F", "Eat your best food"],
	["I", "Satchel: item lore, uses and where to find them"],
	["C", "Change class"],
	["M", "World map (drag, zoom, fast travel)"],
	["J", "This journal"],
	["N", "Mute / unmute sound"],
	["Esc", "Pause menu"],
]

var _root: Control
var _tabs: HBoxContainer
var _list: VBoxContainer
var _detail: VBoxContainer
var _tab := "active"
var _sel := ""
var _tab_buttons: Dictionary = {}


func _ready() -> void:
	layer = 21
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
	panel.offset_left = 90
	panel.offset_right = -90
	panel.offset_top = 50
	panel.offset_bottom = -50
	panel.add_theme_stylebox_override("panel", UiStyle.box())
	_root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	col.add_child(head)
	head.add_child(UiStyle.label("JOURNAL", 20, UiStyle.GOLD))
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	head.add_child(_tabs)
	for t: Array in [["active", "Quests"], ["rumours", "Rumours"], ["done", "Completed"], ["help", "Controls"]]:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		UiStyle.style_button(b)
		b.pressed.connect(_set_tab.bind(str(t[0])))
		_tabs.add_child(b)
		_tab_buttons[t[0]] = b
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	col.add_child(body)
	var ls := ScrollContainer.new()
	ls.custom_minimum_size = Vector2(290, 0)
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(ls)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(280, 0)
	_list.add_theme_constant_override("separation", 4)
	ls.add_child(_list)
	var ds := ScrollContainer.new()
	ds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ds.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(ds)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 6)
	ds.add_child(_detail)
	col.add_child(UiStyle.label("J or Esc closes", 11, Color(0.65, 0.6, 0.5)))


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = (event as InputEventKey).physical_keycode
	if not _root.visible:
		if k == KEY_J and not get_tree().paused and not GameState.is_dead():
			_open()
			get_viewport().set_input_as_handled()
		return
	if k == KEY_J or k == KEY_ESCAPE:
		_close()
	get_viewport().set_input_as_handled()


func _open() -> void:
	get_tree().paused = true
	_root.visible = true
	Fx.play("click")
	_sel = GameState.get_tracked_quest()
	_set_tab("active")


func _close() -> void:
	_root.visible = false
	get_tree().paused = false
	Fx.play("click")


func _set_tab(tab: String) -> void:
	_tab = tab
	for k: String in _tab_buttons.keys():
		(_tab_buttons[k] as Button).button_pressed = (k == tab)
	var ids: Array = _ids_for(tab)
	if not ids.has(_sel):
		_sel = ids[0] if not ids.is_empty() else ""
	_refresh()


func _ids_for(tab: String) -> Array:
	match tab:
		"active":
			return GameState.get_active_quests()
		"rumours":
			var out: Array = []
			for qid: String in GameState.quest_defs.keys():
				if GameState.is_quest_available(qid):
					out.append(qid)
			out.sort_custom(func(a: String, b: String) -> bool:
				return int(_level_of(a)) < int(_level_of(b)))
			return out
		"done":
			var out2: Array = []
			for qid: String in GameState.completed_quests.keys():
				if GameState.completed_quests[qid] and GameState.quest_defs.has(qid):
					out2.append(qid)
			return out2
	return []


func _level_of(qid: String) -> int:
	var reg: Dictionary = Geo.region(str(GameState.quest_defs[qid].get("region", "")))
	var lv: Array = reg.get("level_range", [])
	return int(lv[0]) if lv.size() >= 1 else 1


func _clear(n: Node) -> void:
	for c in n.get_children():
		c.queue_free()


func _wrapped(text: String, size: int = 14, color: Color = UiStyle.TEXT) -> Label:
	var l := UiStyle.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(300, 0)
	return l


func _refresh() -> void:
	_clear(_list)
	_clear(_detail)
	if _tab == "help":
		_show_controls()
		return
	var ids: Array = _ids_for(_tab)
	if ids.is_empty():
		var empty: String = {
			"active": "No active quests. Talk to people (E) and check the Rumours tab.",
			"rumours": "No rumours right now. Explore, and speak to everyone you meet.",
			"done": "Nothing finished yet.",
		}.get(_tab, "")
		_list.add_child(_wrapped(empty, 13, Color(0.7, 0.66, 0.56)))
		return
	var tracked: String = GameState.get_tracked_quest()
	for qid: String in ids:
		var b := Button.new()
		var prefix := ""
		if qid == tracked and _tab == "active":
			prefix = "> "
		var tier: String = str(GameState.quest_defs[qid].get("tier", "side"))
		b.text = "%s%s%s" % [prefix, GameState.get_quest_title(qid), "  [main]" if tier == "main" else ""]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.custom_minimum_size = Vector2(270, 0)
		UiStyle.style_button(b, UiStyle.GOLD if qid == _sel else UiStyle.EDGE)
		b.pressed.connect(func() -> void:
			_sel = qid
			_refresh())
		_list.add_child(b)
	_show_quest(_sel)


func _npc_name(id: String) -> String:
	return str(GameState._npc_display_name(id))


func _show_quest(qid: String) -> void:
	if qid == "" or not GameState.quest_defs.has(qid):
		return
	var def: Dictionary = GameState.quest_defs[qid]
	_detail.add_child(UiStyle.label(GameState.get_quest_title(qid), 20, UiStyle.GOLD))
	var rid: String = str(def.get("region", ""))
	var meta: String = ("Main quest" if str(def.get("tier", "side")) == "main" else "Side quest")
	if rid != "":
		meta += "   |   " + Geo.region_name(rid)
	_detail.add_child(UiStyle.label(meta, 12, Color(0.78, 0.72, 0.6)))
	var summary: String = str(def.get("summary", def.get("pitch", "")))
	if summary != "":
		_detail.add_child(_wrapped(summary, 13, Color(0.85, 0.82, 0.74)))
	_detail.add_child(HSeparator.new())

	if _tab == "rumours":
		var giver: String = str(def.get("giver", ""))
		_detail.add_child(_wrapped("Speak to %s to take this on." % _npc_name(giver), 14, Color(1.0, 0.9, 0.55)))
		var gp: Variant = GameState._npc_position(giver)
		var pp0: Variant = _player_pos()
		if gp != null and pp0 != null:
			_detail.add_child(UiStyle.label("About " + Geo.distance_text(pp0, gp) + " away", 12))
		var rew0: Dictionary = _reward_of(def)
		if not rew0.is_empty():
			_detail.add_child(_wrapped("Reward: " + _reward_text(rew0), 12, Color(0.75, 0.9, 0.6)))
		return

	var stages: Array = def.get("stages", [])
	var cur: int = GameState.get_current_stage_index(qid)
	var done_quest: bool = _tab == "done"
	_detail.add_child(UiStyle.label("Progress", 13, UiStyle.GOLD))
	for i in stages.size():
		var st: Dictionary = stages[i]
		if str(st.get("id", "")) == "complete":
			if done_quest:
				_detail.add_child(_wrapped("[x] " + str(st.get("objective", "Done.")), 13, Color(0.55, 0.8, 0.55)))
			continue
		var mark := "[ ]"
		var col := Color(0.6, 0.57, 0.5)
		if done_quest or i < cur:
			mark = "[x]"
			col = Color(0.55, 0.8, 0.55)
		elif i == cur:
			mark = "[>]"
			col = Color(1.0, 0.9, 0.5)
		if i > cur and not done_quest:
			_detail.add_child(_wrapped("[ ] ...", 13, col))
			break
		_detail.add_child(_wrapped("%s %s" % [mark, str(st.get("objective", ""))], 13, col))
		if i == cur and not done_quest and str(st.get("hint", "")) != "":
			_detail.add_child(_wrapped("Hint: " + str(st["hint"]), 12, Color(0.6, 0.85, 1.0)))

	if _tab == "active":
		var tgt2: Dictionary = GameState.get_objective_target(qid)
		if not tgt2.is_empty() and tgt2.has("pos"):
			var pp: Variant = _player_pos()
			var where: String = str(tgt2.get("label", ""))
			if pp != null:
				where += "  (" + Geo.distance_text(pp, tgt2["pos"]) + ")"
			_detail.add_child(_wrapped("Go to: " + where, 13, Color(1.0, 0.85, 0.4)))
		var rew: Dictionary = _reward_of(def)
		if not rew.is_empty():
			_detail.add_child(_wrapped("Reward: " + _reward_text(rew), 12, Color(0.75, 0.9, 0.6)))
		var tb := Button.new()
		var is_tr: bool = qid == GameState.get_tracked_quest()
		tb.text = "Tracking" if is_tr else "Track this quest"
		tb.disabled = is_tr
		UiStyle.style_button(tb, UiStyle.GOLD)
		tb.pressed.connect(func() -> void:
			GameState.set_tracked_quest(qid)
			Fx.play("click")
			_refresh())
		_detail.add_child(tb)


func _player_pos() -> Variant:
	var p: Node2D = get_tree().get_first_node_in_group("player") as Node2D
	return p.global_position if p != null else null


func _reward_of(def: Dictionary) -> Dictionary:
	var stages: Array = def.get("stages", [])
	if stages.is_empty():
		return {}
	return stages[stages.size() - 1].get("rewards", {})


func _reward_text(rew: Dictionary) -> String:
	var parts: Array = []
	if rew.has("grant_exp"):
		parts.append("%d XP" % int(rew["grant_exp"].get("amount", 0)))
	var items: Dictionary = rew.get("give_items", {})
	for id: String in items.keys():
		var nm: String = str(GameState.item_defs.get(id, {}).get("name", id))
		parts.append("%dx %s" % [int(items[id]), nm])
	return ", ".join(parts)


func _show_controls() -> void:
	_list.add_child(_wrapped("Everything you can do. Hints appear in the corner as you play, once each.", 13, Color(0.75, 0.7, 0.6)))
	_detail.add_child(UiStyle.label("Controls", 20, UiStyle.GOLD))
	for c: Array in CONTROLS:
		var row := HBoxContainer.new()
		var k := UiStyle.label(str(c[0]), 14, UiStyle.GOLD)
		k.custom_minimum_size = Vector2(150, 0)
		row.add_child(k)
		row.add_child(UiStyle.label(str(c[1]), 14))
		_detail.add_child(row)
	_detail.add_child(HSeparator.new())
	_detail.add_child(UiStyle.label("Survival", 16, UiStyle.GOLD))
	for t: String in [
		"Hunger drains over time. Cook raw meat at a campfire before eating it.",
		"Night is dangerous. Villages and campfires are lit and safe.",
		"Dying returns you to the last waystone you attuned.",
		"Gold ! over a head: new quest. Gold ?: someone is waiting for your report.",
		"The gold arrow on screen and the diamond on the map always point at your tracked objective.",
	]:
		_detail.add_child(_wrapped("- " + t, 13))
