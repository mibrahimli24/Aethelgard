extends CanvasLayer
## The dialogue modal: sends free-text player input to GameMaster.process_dialogue() (the
## mocked LLM) and renders the returned {dialogue, npc_mood, generated_lore_snippet,
## game_actions} contract. Pauses the SceneTree while open (a conversation is a modal beat,
## not something that should happen while wolves are chewing on you) -- this node's own
## process_mode is ALWAYS so it keeps working while everything else is paused.
##
## The 0.6s delay before showing a response simulates the latency of the real
## Redis/Celery -> Claude API round trip described in the spec, so the "NPC is thinking..."
## UX is exercised even though no network call actually happens here.

const MOOD_COLORS := {
	"Friendly": "seagreen",
	"Neutral": "lightgray",
	"Suspicious": "goldenrod",
	"Hostile": "crimson",
	"Terrified": "mediumpurple",
}

@onready var panel: Control = $Panel
@onready var npc_name_label: Label = $Panel/VBox/NpcNameLabel
@onready var dialogue_text: RichTextLabel = $Panel/VBox/DialogueText
@onready var thinking_label: Label = $Panel/VBox/ThinkingLabel
@onready var input_field: LineEdit = $Panel/VBox/InputField

var _current_npc_id := ""
var _is_open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = false
	thinking_label.visible = false
	EventBus.dialogue_requested.connect(_on_dialogue_requested)
	input_field.text_submitted.connect(_on_submit)


func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event.is_action_pressed("ui_cancel"):
		_close()


func _on_dialogue_requested(npc_id: String, display_name: String) -> void:
	if _is_open:
		return
	_open(npc_id, display_name)


func _open(npc_id: String, display_name: String) -> void:
	_current_npc_id = npc_id
	_is_open = true
	get_tree().paused = true
	panel.visible = true
	npc_name_label.text = display_name
	dialogue_text.text = ""
	input_field.text = ""
	input_field.grab_focus()
	_send_to_game_master("") # empty input triggers the NPC's canned greeting


func _close() -> void:
	_is_open = false
	get_tree().paused = false
	panel.visible = false


func _on_submit(text: String) -> void:
	if text.strip_edges() == "":
		return
	input_field.text = ""
	_send_to_game_master(text)


func _send_to_game_master(player_input: String) -> void:
	thinking_label.visible = true
	input_field.editable = false
	await get_tree().create_timer(0.6, true).timeout
	if not _is_open:
		return # player closed the dialogue while the mock "request" was in flight
	var payload: Dictionary = GameMaster.process_dialogue(_current_npc_id, player_input)
	thinking_label.visible = false
	input_field.editable = true
	input_field.grab_focus()
	_render_response(payload)
	EventBus.dialogue_ready.emit(_current_npc_id, payload)
	for action in payload.get("game_actions", []):
		EventBus.action_dispatched.emit(action)


func _render_response(payload: Dictionary) -> void:
	var mood: String = payload.get("npc_mood", "Neutral")
	var color: String = MOOD_COLORS.get(mood, "white")
	var line := "[color=%s]%s[/color]  [i](%s)[/i]\n" % [color, payload.get("dialogue", ""), mood]
	var lore = payload.get("generated_lore_snippet", null)
	if lore != null and String(lore) != "":
		line += "[i][color=lightblue]Rumor: %s[/color][/i]\n" % lore
	dialogue_text.append_text(line)
