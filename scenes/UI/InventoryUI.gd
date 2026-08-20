extends CanvasLayer
## Inventory & crafting panel -- gives the give_item/unlock_recipe game_actions (spec 5)
## somewhere to actually show up. Toggled with "toggle_inventory" (I). Recipes unlocked via
## quest rewards appear as craftable buttons; craft_equipment() applies the recipe's gear
## tier directly (no raw-material cost in this slice -- the quest-reward gate already stands
## in for that).

@onready var panel: Control = $Panel
@onready var items_list: VBoxContainer = $Panel/VBox/ItemsList
@onready var recipes_list: VBoxContainer = $Panel/VBox/RecipesList


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = false
	EventBus.vitals_changed.connect(_refresh)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		panel.visible = not panel.visible
		if panel.visible:
			_refresh()


func _refresh() -> void:
	if not panel.visible:
		return
	_refresh_items()
	_refresh_recipes()


func _refresh_items() -> void:
	for child in items_list.get_children():
		child.queue_free()
	if GameState.inventory.is_empty():
		items_list.add_child(_make_label("(empty)"))
		return
	for item_id in GameState.inventory.keys():
		items_list.add_child(_make_label("%s x%d" % [item_id, GameState.inventory[item_id]]))


func _refresh_recipes() -> void:
	for child in recipes_list.get_children():
		child.queue_free()
	var any_recipe := false
	for recipe_id in GameState.recipe_defs.keys():
		if not GameState.unlocked_recipes.get(recipe_id, false):
			continue
		any_recipe = true
		recipes_list.add_child(_make_recipe_button(recipe_id, GameState.recipe_defs[recipe_id]))
	if not any_recipe:
		recipes_list.add_child(_make_label("(no recipes unlocked yet)"))


func _make_recipe_button(recipe_id: String, recipe: Dictionary) -> Button:
	var class_id: String = recipe.get("class_id", "")
	var tier_index: int = int(recipe.get("tier_index", -1))
	var tiers: Array = GameState.class_defs.get(class_id, {}).get("armor_tiers", [])
	var tier_name: String = tiers[tier_index] if tier_index >= 0 and tier_index < tiers.size() else "?"
	var already_equipped: bool = int(GameState.class_data.get(class_id, {}).get("equipped_tier_index", 0)) >= tier_index

	var btn := Button.new()
	btn.text = ("%s equipped" % tier_name) if already_equipped else ("Craft %s (%s)" % [tier_name, class_id])
	btn.disabled = already_equipped
	btn.pressed.connect(_on_craft_pressed.bind(recipe_id))
	return btn


func _on_craft_pressed(recipe_id: String) -> void:
	GameState.craft_equipment(recipe_id)
	_refresh()


func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l
