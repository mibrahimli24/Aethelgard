extends CanvasLayer
## Pause menu (Esc). Freezes the tree; offers Resume, Save, Mute toggle and Quit, plus a controls
## cheat-sheet. Esc is ignored while another modal (dialogue) already has the tree paused.

const UiStyle = preload("res://scripts/UiStyle.gd")

var _root: Control
var _mute_btn: Button
var _open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	_build()
	_root.visible = false


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -190
	panel.offset_right = 190
	panel.offset_top = -210
	panel.offset_bottom = 210
	panel.add_theme_stylebox_override("panel", UiStyle.box())
	_root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var title := UiStyle.label("AETHELGARD", 26, UiStyle.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := UiStyle.label("Paused", 14, Color(0.7, 0.65, 0.55))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	vb.add_child(_button("Resume", _resume))
	vb.add_child(_button("Save game", _save))
	_mute_btn = _button("Sound: on", _toggle_mute)
	vb.add_child(_mute_btn)
	vb.add_child(_button("Quit", _quit))
	var help := UiStyle.label("WASD move   Space attack   Q special   Shift dodge\nE interact   F eat   I satchel   C class   Esc pause\nM map   J journal   N mutes sound", 12, Color(0.7, 0.66, 0.56))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(help)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 38)
	UiStyle.style_button(b)
	b.pressed.connect(cb)
	return b


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause_menu"):
		return
	if _open:
		_resume()
		get_viewport().set_input_as_handled()
	elif not get_tree().paused and not GameState.is_dead():
		_show()
		get_viewport().set_input_as_handled()


func _show() -> void:
	_open = true
	get_tree().paused = true
	_root.visible = true
	_mute_btn.text = "Sound: off" if Fx.muted else "Sound: on"
	Fx.play("click")


func _resume() -> void:
	_open = false
	get_tree().paused = false
	_root.visible = false
	Fx.play("click")


func _save() -> void:
	GameState.save_to_disk()
	EventBus.toast_requested.emit("Game saved.", Color(0.7, 0.95, 0.7))
	Fx.play("pickup")


func _toggle_mute() -> void:
	Fx.toggle_mute()
	_mute_btn.text = "Sound: off" if Fx.muted else "Sound: on"


func _quit() -> void:
	GameState.save_to_disk()
	get_tree().quit()
