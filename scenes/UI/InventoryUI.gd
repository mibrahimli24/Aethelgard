extends CanvasLayer
## Satchel (I): item list with icons + category filter, a detail panel for the selected item
## (lore, where to find it, what it is for), recipes and journey stats.

const UiStyle = preload("res://scripts/UiStyle.gd")
const ItemIcon = preload("res://scripts/ItemIcon.gd")

const FILTERS := ["all", "food", "material", "treasure", "quest"]

var _panel: PanelContainer
var _items_box: VBoxContainer
var _recipes_box: VBoxContainer
var _stats_label: Label
var _detail_box: VBoxContainer
var _filter_btns: Dictionary = {}
var _filter := "all"
var _selected := ""
var _count_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 21
	_build()
	_panel.visible = false
	EventBus.vitals_changed.connect(_refresh)
	EventBus.inventory_changed.connect(_refresh)


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -440
	_panel.offset_right = 440
	_panel.offset_top = -270
	_panel.offset_bottom = 270
	_panel.add_theme_stylebox_override("panel", UiStyle.box())
	add_child(_panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_panel.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var title := UiStyle.label("SATCHEL", 20, UiStyle.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_count_label = UiStyle.label("", 12, Color(0.7, 0.65, 0.55))
	head.add_child(_count_label)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(290, 0)
	left.add_theme_constant_override("separation", 6)
	cols.add_child(left)
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 3)
	left.add_child(frow)
	for f: String in FILTERS:
		var b := Button.new()
		b.text = f.capitalize()
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 11)
		UiStyle.style_button(b)
		b.pressed.connect(_set_filter.bind(f))
		frow.add_child(b)
		_filter_btns[f] = b
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_items_box = VBoxContainer.new()
	_items_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items_box.add_theme_constant_override("separation", 3)
	scroll.add_child(_items_box)

	var mid := PanelContainer.new()
	mid.custom_minimum_size = Vector2(330, 0)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_stylebox_override("panel", UiStyle.box(Color(0.05, 0.04, 0.03, 0.9), Color(0.4, 0.32, 0.18), 6, 12))
	cols.add_child(mid)
	_detail_box = VBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", 6)
	mid.add_child(_detail_box)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(190, 0)
	right.add_theme_constant_override("separation", 6)
	cols.add_child(right)
	right.add_child(UiStyle.label("Recipes", 15, UiStyle.GOLD))
	_recipes_box = VBoxContainer.new()
	right.add_child(_recipes_box)
	right.add_child(UiStyle.label("Journey", 15, UiStyle.GOLD))
	_stats_label = UiStyle.label("", 13)
	right.add_child(_stats_label)

	root.add_child(UiStyle.label("I close   |   F eats the best food   |   Click an item for details   |   Cook raw food at a campfire", 11, Color(0.65, 0.6, 0.5)))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory") and not get_tree().paused:
		_panel.visible = not _panel.visible
		Fx.play("click")
		if _panel.visible:
			_refresh()
	elif _panel.visible and event.is_action_pressed("ui_cancel"):
		_panel.visible = false
		get_viewport().set_input_as_handled()


func _set_filter(f: String) -> void:
	_filter = f
	_refresh()


func _refresh() -> void:
	if not _panel.visible:
		return
	_refresh_items()
	_refresh_detail()
	_refresh_recipes()
	_refresh_stats()


func _sorted_ids() -> Array:
	var ids: Array = []
	for item_id: String in GameState.inventory.keys():
		if int(GameState.inventory[item_id]) <= 0:
			continue
		if _filter != "all" and str(GameState.get_item_def(item_id).get("type", "material")) != _filter:
			continue
		ids.append(item_id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ra: int = UiStyle.RARITY.keys().find(str(GameState.get_item_def(a).get("rarity", "common")))
		var rb: int = UiStyle.RARITY.keys().find(str(GameState.get_item_def(b).get("rarity", "common")))
		if ra != rb:
			return ra > rb
		return GameState.get_item_name(a) < GameState.get_item_name(b))
	return ids


func _refresh_items() -> void:
	for f: String in _filter_btns.keys():
		(_filter_btns[f] as Button).button_pressed = (f == _filter)
	for child in _items_box.get_children():
		child.queue_free()
	var total := 0
	for k: String in GameState.inventory.keys():
		total += int(GameState.inventory[k])
	_count_label.text = "%d items" % total
	var ids := _sorted_ids()
	if ids.is_empty():
		_items_box.add_child(UiStyle.label("(nothing here -- forage, hunt, or loot chests)", 13, Color(0.6, 0.57, 0.5)))
		_selected = ""
		return
	if _selected == "" or not ids.has(_selected):
		_selected = ids[0]
	for item_id: String in ids:
		_items_box.add_child(_make_item_row(item_id))


func _make_item_row(item_id: String) -> Control:
	var def: Dictionary = GameState.get_item_def(item_id)
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = (item_id == _selected)
	b.custom_minimum_size = Vector2(0, 34)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	UiStyle.style_button(b, UiStyle.rarity_color(str(def.get("rarity", "common"))))
	b.pressed.connect(_select.bind(item_id))
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var icon := ItemIcon.new()
	icon.setup(str(def.get("icon", "ore")), GameState.get_item_color(item_id), 26.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var text := UiStyle.label(GameState.get_item_name(item_id), 14, UiStyle.rarity_color(str(def.get("rarity", "common"))))
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var cnt := UiStyle.label("x%d" % int(GameState.inventory[item_id]), 14)
	cnt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(cnt)
	return b


func _select(item_id: String) -> void:
	_selected = item_id
	Fx.play("click")
	_refresh()


func _refresh_detail() -> void:
	for child in _detail_box.get_children():
		child.queue_free()
	if _selected == "" or int(GameState.inventory.get(_selected, 0)) <= 0:
		_detail_box.add_child(UiStyle.label("Select an item to read about it.", 13, Color(0.6, 0.57, 0.5)))
		return
	var def: Dictionary = GameState.get_item_def(_selected)
	var rarity: String = str(def.get("rarity", "common"))
	var rc: Color = UiStyle.rarity_color(rarity)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_detail_box.add_child(head)
	var icon := ItemIcon.new()
	icon.setup(str(def.get("icon", "ore")), GameState.get_item_color(_selected), 64.0)
	head.add_child(icon)
	var hv := VBoxContainer.new()
	head.add_child(hv)
	hv.add_child(UiStyle.label(GameState.get_item_name(_selected), 18, rc))
	hv.add_child(UiStyle.label("%s  -  %s" % [rarity.capitalize(), str(def.get("type", "material")).capitalize()], 12, Color(0.72, 0.68, 0.58)))
	hv.add_child(UiStyle.label("Owned: %d    Value: %d" % [int(GameState.inventory[_selected]), int(def.get("value", 0))], 12, Color(0.72, 0.68, 0.58)))
	_detail_box.add_child(_wrapped(str(def.get("desc", "")), 14, UiStyle.TEXT))
	if def.has("lore") and str(def["lore"]) != "":
		_detail_box.add_child(_wrapped("\"%s\"" % def["lore"], 13, Color(0.75, 0.72, 0.6)))
	if str(def.get("type", "")) == "food":
		var eff: Array = []
		if int(def.get("hunger", 0)) > 0:
			eff.append("+%d hunger" % int(def["hunger"]))
		if int(def.get("hp", 0)) > 0:
			eff.append("+%d HP" % int(def["hp"]))
		_detail_box.add_child(_section("Effect", ", ".join(eff) if not eff.is_empty() else "Nothing much."))
	if def.has("cookable_into"):
		_detail_box.add_child(_section("Cooking", "Cook at a campfire into %s." % GameState.get_item_name(str(def["cookable_into"]))))
	if def.has("sources"):
		_detail_box.add_child(_section("Where to find", str(def["sources"])))
	if def.has("uses"):
		_detail_box.add_child(_section("Uses", str(def["uses"])))
	if str(def.get("type", "")) == "food":
		var eat := Button.new()
		eat.text = "Eat"
		UiStyle.style_button(eat, UiStyle.GOLD)
		eat.pressed.connect(_on_eat.bind(_selected))
		_detail_box.add_child(eat)


func _section(head: String, body: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.add_child(UiStyle.label(head, 12, UiStyle.GOLD))
	v.add_child(_wrapped(body, 13, UiStyle.TEXT))
	return v


func _wrapped(text: String, size: int, color: Color) -> Label:
	var l := UiStyle.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	return l


func _on_eat(item_id: String) -> void:
	if GameState.eat_item(item_id):
		Fx.play("eat")
	_refresh()


func _refresh_recipes() -> void:
	for child in _recipes_box.get_children():
		child.queue_free()
	var any := false
	for recipe_id: String in GameState.recipe_defs.keys():
		if not GameState.unlocked_recipes.get(recipe_id, false):
			continue
		any = true
		_recipes_box.add_child(_make_recipe_button(recipe_id, GameState.recipe_defs[recipe_id]))
	if not any:
		_recipes_box.add_child(UiStyle.label("(none unlocked yet)", 13, Color(0.6, 0.57, 0.5)))


func _make_recipe_button(recipe_id: String, recipe: Dictionary) -> Button:
	var class_id: String = recipe.get("class_id", "")
	var tier_index: int = int(recipe.get("tier_index", -1))
	var tiers: Array = GameState.class_defs.get(class_id, {}).get("armor_tiers", [])
	var tier_name: String = tiers[tier_index] if tier_index >= 0 and tier_index < tiers.size() else "?"
	var already: bool = int(GameState.class_data.get(class_id, {}).get("equipped_tier_index", 0)) >= tier_index
	var btn := Button.new()
	btn.text = ("%s equipped" % tier_name) if already else ("Craft %s (%s)" % [tier_name, class_id])
	btn.disabled = already
	btn.add_theme_font_size_override("font_size", 12)
	UiStyle.style_button(btn, UiStyle.GOLD)
	btn.pressed.connect(_on_craft_pressed.bind(recipe_id))
	return btn


func _on_craft_pressed(recipe_id: String) -> void:
	if GameState.craft_equipment(recipe_id):
		Fx.play("quest")
		EventBus.toast_requested.emit("Gear crafted and equipped.", Color(1.0, 0.85, 0.4))
	_refresh()


func _refresh_stats() -> void:
	var entry: Dictionary = GameState.class_data[GameState.active_class]
	var mins: int = int(GameState.play_time / 60.0)
	_stats_label.text = "Level %d %s\nArmor: %s\nEnemies slain: %d\nTime played: %d min\nRegions seen: %d" % [
		int(entry["level"]),
		GameState.class_defs.get(GameState.active_class, {}).get("display_name", GameState.active_class),
		GameState.get_equipped_tier_name(GameState.active_class),
		GameState.total_kills,
		mins,
		GameState.visited_regions.size(),
	]
