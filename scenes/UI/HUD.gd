extends CanvasLayer
## HUD: HP/hunger/EXP bars for the active class, equipped tier, and the live quest tracker.
## Pure display -- reads GameState directly and refreshes on EventBus signals, never mutates.

@onready var hp_bar: ProgressBar = $Root/VBox/HpBar
@onready var hunger_bar: ProgressBar = $Root/VBox/HungerBar
@onready var exp_bar: ProgressBar = $Root/VBox/ExpBar
@onready var class_label: Label = $Root/VBox/ClassLabel
@onready var quest_label: Label = $QuestPanel/QuestLabel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.vitals_changed.connect(_refresh_vitals)
	EventBus.quest_updated.connect(_on_quest_updated)
	_refresh_vitals()
	quest_label.text = "Quest: %s" % GameState.get_display_objective()


func _refresh_vitals() -> void:
	hp_bar.max_value = GameState.max_hp
	hp_bar.value = GameState.hp
	hunger_bar.max_value = 100.0
	hunger_bar.value = GameState.hunger

	var entry: Dictionary = GameState.class_data[GameState.active_class]
	exp_bar.max_value = GameState.get_exp_to_next_level(GameState.active_class)
	exp_bar.value = entry["exp"]

	var display_name: String = GameState.class_defs.get(GameState.active_class, {}).get("display_name", GameState.active_class)
	class_label.text = "%s Lv.%d -- %s" % [
		display_name,
		int(entry["level"]),
		GameState.get_equipped_tier_name(GameState.active_class),
	]


func _on_quest_updated(_quest_id: String, _stage: int, objective: String) -> void:
	quest_label.text = "Quest: %s" % objective
