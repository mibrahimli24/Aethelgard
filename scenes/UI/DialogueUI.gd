extends CanvasLayer
## The dialogue modal: sends free-text player input (or a clicked suggestion chip) to
## GameMaster.process_dialogue() and renders the returned {dialogue, npc_mood,
## generated_lore_snippet, game_actions, chips, end} contract. Pauses the SceneTree while open
## (a conversation is a modal beat) -- this node's process_mode is ALWAYS so it keeps working.
##
## The 0.6s delay before showing a response simulates the latency of a real model round trip,
## so the "NPC is thinking..." UX is exercised even though no network call happens.

const UiStyle = preload("res://scripts/UiStyle.gd")

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
var _busy := false
var _chip_box: HFlowContainer
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = false
	thinking_label.visible = false
	(panel as PanelContainer).add_theme_stylebox_override("panel", UiStyle.box())
	npc_name_label.add_theme_color_override("font_color", UiStyle.GOLD)
	dialogue_text.fit_content = false
	dialogue_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialogue_text.scroll_following = true
	dialogue_text.add_theme_font_size_override("normal_font_size", 16)
	dialogue_text.add_theme_font_size_override("italics_font_size", 16)
	thinking_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	_chip_box = HFlowContainer.new()
	_chip_box.add_theme_constant_override("h_separation", 6)
	_chip_box.add_theme_constant_override("v_separation", 4)
	$Panel/VBox.add_child(_chip_box)
	$Panel/VBox.move_child(_chip_box, input_field.get_index())
	EventBus.dialogue_requested.connect(_on_dialogue_requested)
	input_field.text_submitted.connect(_on_submit)


func _unhandled_input(event: InputEvent) -> void:
	if _is_open and event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _on_dialogue_requested(npc_id: String, display_name: String) -> void:
	if _is_open:
		return
	_open(npc_id, display_name)


func _open(npc_id: String, display_name: String) -> void:
	_current_npc_id = npc_id
	_is_open = true
	_busy = false
	get_tree().paused = true
	panel.visible = true
	Fx.play("click")
	npc_name_label.text = display_name
	dialogue_text.text = ""
	input_field.text = ""
	_clear_chips()
	input_field.grab_focus()
	_send_to_game_master("")


func _close() -> void:
	_is_open = false
	get_tree().paused = false
	panel.visible = false
	_clear_chips()


func _on_submit(text: String) -> void:
	_say(text)


func _say(text: String) -> void:
	if _busy or text.strip_edges() == "":
		return
	input_field.text = ""
	_append("[color=#e8c872]You:[/color] [i]%s[/i]\n" % text.strip_edges().replace("[", "(").replace("]", ")"))
	_send_to_game_master(text)


func _clear_chips() -> void:
	for c in _chip_box.get_children():
		c.queue_free()


func _set_chips(chips: Array) -> void:
	_clear_chips()
	for ch in chips:
		var b := Button.new()
		b.text = str(ch.get("label", "..."))
		b.focus_mode = Control.FOCUS_NONE
		UiStyle.style_button(b)
		b.add_theme_font_size_override("font_size", 13)
		var say: String = str(ch.get("say", b.text))
		b.pressed.connect(func() -> void: _say(say))
		_chip_box.add_child(b)


func _send_to_game_master(player_input: String) -> void:
	_busy = true
	thinking_label.visible = true
	input_field.editable = false
	_clear_chips()
	await get_tree().create_timer(0.6, true).timeout
	if not _is_open:
		return
	var payload: Dictionary = GameMaster.process_dialogue(_current_npc_id, player_input)
	thinking_label.visible = false
	input_field.editable = true
	input_field.grab_focus()
	_busy = false
	_render_response(payload)
	EventBus.dialogue_ready.emit(_current_npc_id, payload)
	for action in payload.get("game_actions", []):
		EventBus.action_dispatched.emit(action)
	if bool(payload.get("end", false)):
		await get_tree().create_timer(1.1, true).timeout
		if _is_open:
			_close()
		return
	_set_chips(payload.get("chips", []))


func _render_response(payload: Dictionary) -> void:
	var mood: String = payload.get("npc_mood", "Neutral")
	var color: String = MOOD_COLORS.get(mood, "white")
	var line := "[color=%s]%s[/color]  [i](%s)[/i]\n" % [color, payload.get("dialogue", ""), mood]
	var lore = payload.get("generated_lore_snippet", null)
	if lore != null and String(lore) != "":
		line += "[i][color=lightblue]Rumor: %s[/color][/i]\n" % lore
	_append(line, true)


func _append(bb: String, animate: bool = false) -> void:
	var start: int = dialogue_text.get_total_character_count()
	dialogue_text.append_text(bb)
	if _tween and _tween.is_valid():
		_tween.kill()
	if not animate:
		dialogue_text.visible_characters = -1
		return
	var total: int = dialogue_text.get_total_character_count()
	dialogue_text.visible_characters = start
	_tween = create_tween()
	_tween.tween_property(dialogue_text, "visible_characters", total, maxf(0.2, float(total - start) * 0.012))
	_tween.tween_callback(func() -> void: dialogue_text.visible_characters = -1)
