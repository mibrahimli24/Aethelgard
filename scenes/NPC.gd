extends Node2D
## Interactable NPC. Shows a "Press E to talk" prompt when the player is in range and, on
## interact, requests a conversation via EventBus. Actual dialogue generation happens in
## GameMaster (the mocked LLM) -- NPC itself only knows its own id, kept decoupled from
## whatever UI is listening for dialogue_requested.

@export var npc_id: String = ""
@export var display_name: String = ""
@export var body_color: Color = Color(0.6, 0.5, 0.2, 1)

var _player_in_range := false

@onready var interact_area: Area2D = $InteractArea
@onready var prompt_label: Label = $PromptLabel
@onready var body_polygon: Polygon2D = $Polygon2D


func _ready() -> void:
	prompt_label.visible = false
	body_polygon.color = body_color
	interact_area.body_entered.connect(_on_body_entered)
	interact_area.body_exited.connect(_on_body_exited)


func _process(_delta: float) -> void:
	if _player_in_range and Input.is_action_just_pressed("interact"):
		EventBus.dialogue_requested.emit(npc_id, display_name)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		prompt_label.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		prompt_label.visible = false
