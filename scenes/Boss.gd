extends "res://scenes/Enemy.gd"
## Skar, Beastmaster of the Red Fang Clan -- final encounter of the Whispering Glades slice
## (spec 1.1: Level 15 biome boss). Extends the base Enemy AI with a telegraphed heavy attack,
## "Bloodstone Frenzy," so the fight reads as a boss fight rather than a bigger regular enemy.

@export var frenzy_cooldown: float = 5.0
@export var frenzy_damage: float = 30.0
@export var frenzy_radius: float = 90.0
@export var frenzy_telegraph_time: float = 0.8

var _frenzy_timer := 2.0 # small initial grace period before the first frenzy
var _telegraphing := false

@onready var frenzy_indicator: Polygon2D = $FrenzyIndicator


func _ready() -> void:
	super._ready()
	if frenzy_indicator:
		frenzy_indicator.visible = false


func _physics_process(delta: float) -> void:
	if _telegraphing:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	super._physics_process(delta)

	_frenzy_timer -= delta
	var player := _find_player()
	if player and _frenzy_timer <= 0.0 and global_position.distance_to(player.global_position) <= frenzy_radius:
		_start_frenzy(player)


func _start_frenzy(player: Node2D) -> void:
	_telegraphing = true
	_frenzy_timer = frenzy_cooldown
	if frenzy_indicator:
		frenzy_indicator.visible = true
	await get_tree().create_timer(frenzy_telegraph_time).timeout
	if frenzy_indicator:
		frenzy_indicator.visible = false
	_telegraphing = false
	if is_instance_valid(player) and global_position.distance_to(player.global_position) <= frenzy_radius:
		if player.has_method("take_damage"):
			player.take_damage(frenzy_damage)
