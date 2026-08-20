extends CharacterBody2D
## Generic hostile-fauna/bandit AI: idles until the player enters chase_range, then chases and
## deals periodic contact damage. On death, registers the kill with GameState (for quest
## kill_count tracking, spec 3) and grants EXP to the player's active class.
## Reused for every hostile creature in the biome (Dire Wolf, Boar, Red Fang bandits) by
## overriding the @export values per scene instance -- see World.tscn.

@export var enemy_id: String = "dire_wolf"
@export var display_name: String = "Dire Wolf"
@export var max_hp: float = 40.0
@export var damage: float = 6.0
@export var exp_reward: int = 25
@export var move_speed: float = 90.0
@export var chase_range: float = 220.0
@export var attack_range: float = 28.0
@export var attack_cooldown: float = 1.0

var hp: float
var _attack_timer := 0.0
var _base_color: Color

@onready var hp_bar: ProgressBar = $HpBar
@onready var body_polygon: Polygon2D = $Polygon2D


func _ready() -> void:
	hp = max_hp
	add_to_group("enemies")
	_base_color = body_polygon.color
	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value = hp


func _physics_process(delta: float) -> void:
	_attack_timer = max(0.0, _attack_timer - delta)
	var player := _find_player()
	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var dist := global_position.distance_to(player.global_position)
	if dist <= chase_range:
		var dir := (player.global_position - global_position).normalized()
		if dist > attack_range:
			velocity = dir * move_speed
		else:
			velocity = Vector2.ZERO
			_try_attack(player)
	else:
		velocity = Vector2.ZERO
	move_and_slide()


func _try_attack(player: Node2D) -> void:
	if _attack_timer <= 0.0:
		_attack_timer = attack_cooldown
		if player.has_method("take_damage"):
			player.take_damage(damage)


func _find_player() -> Node2D:
	var nodes := get_tree().get_nodes_in_group("player")
	return nodes[0] if nodes.size() > 0 else null


func take_damage(amount: float) -> void:
	hp = max(0.0, hp - amount)
	if hp_bar:
		hp_bar.value = hp
	_flash_hit()
	if hp <= 0.0:
		_die()


func _flash_hit() -> void:
	body_polygon.color = Color(1, 1, 1, 1)
	var tween := create_tween()
	tween.tween_property(body_polygon, "color", _base_color, 0.18)


func _die() -> void:
	GameState.register_kill(enemy_id)
	GameState.grant_exp(GameState.active_class, exp_reward)
	_spawn_death_burst()
	queue_free()


func _spawn_death_burst() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var burst := CPUParticles2D.new()
	burst.position = global_position
	burst.emitting = false
	burst.one_shot = true
	burst.amount = 14
	burst.lifetime = 0.5
	burst.explosiveness = 1.0
	burst.direction = Vector2.UP
	burst.spread = 180.0
	burst.gravity = Vector2(0, 200)
	burst.initial_velocity_min = 40.0
	burst.initial_velocity_max = 110.0
	burst.scale_amount_min = 2.0
	burst.scale_amount_max = 4.0
	burst.color = _base_color
	parent.add_child(burst)
	burst.emitting = true
	get_tree().create_timer(burst.lifetime + 0.1).timeout.connect(burst.queue_free)
