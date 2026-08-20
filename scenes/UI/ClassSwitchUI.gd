extends CanvasLayer
## Role picker (spec 2: Dynamic Role & Level Retention). Toggled with the "toggle_class_menu"
## input. Each button shows that role's independently-tracked level; picking one calls
## GameState.switch_class(), which swaps the active gear set without touching the other
## four roles' level/exp entries.

const CLASS_IDS := ["swordsman", "bowman", "magic_user", "rogue", "alchemist"]

@onready var panel: Control = $Panel
var _buttons: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = false
	for class_id in CLASS_IDS:
		var btn: Button = panel.get_node("VBox/%s" % class_id)
		_buttons[class_id] = btn
		btn.pressed.connect(_on_class_button_pressed.bind(class_id))
	EventBus.vitals_changed.connect(_refresh_labels)
	EventBus.class_changed.connect(func(_new_class_id): _refresh_labels())
	_refresh_labels()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_class_menu"):
		panel.visible = not panel.visible
		if panel.visible:
			_refresh_labels()


func _on_class_button_pressed(class_id: String) -> void:
	GameState.switch_class(class_id)
	panel.visible = false


func _refresh_labels() -> void:
	for class_id in CLASS_IDS:
		var def: Dictionary = GameState.class_defs.get(class_id, {})
		var entry: Dictionary = GameState.class_data.get(class_id, {})
		var display_name: String = def.get("display_name", class_id)
		var suffix := "  (active)" if class_id == GameState.active_class else ""
		_buttons[class_id].text = "%s -- Lv.%d%s" % [display_name, int(entry.get("level", 0)), suffix]
