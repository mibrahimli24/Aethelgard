extends CharacterBody2D
## Top-down player controller: movement, class-driven attack, hunger-scaled speed,
## death/respawn. All vitals truth lives in GameState -- this script only reads/writes
## through it. Attack behavior (melee vs. ranged, damage, cooldown, crit) is read from
## GameState.get_active_combat_stats(), which pulls the active class's "combat" block
## from data/classes.json -- so every role's fight feel lives in data, not scattered
## across scripts (spec 2: per-role loadouts).

const BASE_SPEED := 140.0
const RESPAWN_DELAY := 2.0
const PROJECTILE_SCENE := preload("res://scenes/Projectile.tscn")
const PROJECTILE_SPAWN_OFFSET := 20.0

@onready var attack_area: Area2D = $AttackArea
@onready var attack_cooldown_timer: Timer = $AttackCooldownTimer
@onready var respawn_timer: Timer = $RespawnTimer
@onready var body_polygon: Polygon2D = $Polygon2D
@onready var facing_indicator: Polygon2D = $FacingIndicator

var _can_attack := true
var _spawn_position: Vector2
var _facing := Vector2.DOWN
var _body_base_color: Color


func _ready() -> void:
	add_to_group("player")
	_spawn_position = global_position
	_body_base_color = body_polygon.color
	EventBus.vitals_changed.connect(_on_vitals_changed)


func _physics_process(_delta: float) -> void:
	if GameState.is_dead():
		velocity = Vector2.ZERO
		return

	var input_dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()
	if input_dir.length() > 0.1:
		_facing = input_dir.normalized()
	velocity = input_dir * BASE_SPEED * GameState.get_move_speed_multiplier()
	move_and_slide()
	facing_indicator.position = _facing * 18.0
	facing_indicator.rotation = _facing.angle() + PI / 2.0

	if Input.is_action_just_pressed("attack") and _can_attack:
		_perform_attack()


func _perform_attack() -> void:
	var stats: Dictionary = GameState.get_active_combat_stats()
	if stats.is_empty():
		return
	_can_attack = false
	attack_cooldown_timer.start(float(stats.get("attack_cooldown", 0.45)))
	if stats.get("attack_type", "melee") == "ranged":
		_fire_projectile(stats)
	else:
		_melee_attack(stats)


func _melee_attack(stats: Dictionary) -> void:
	var damage: float = float(stats.get("attack_damage", 10))
	var crit_chance: float = float(stats.get("crit_chance", 0.0))
	if crit_chance > 0.0 and randf() < crit_chance:
		damage *= float(stats.get("crit_multiplier", 1.5))
	for body in attack_area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(damage)


func _fire_projectile(stats: Dictionary) -> void:
	var projectile := PROJECTILE_SCENE.instantiate()
	get_tree().current_scene.add_child(projectile)
	var color_arr: Array = stats.get("projectile_color", [1, 1, 1, 1])
	var color := Color(color_arr[0], color_arr[1], color_arr[2], color_arr[3] if color_arr.size() > 3 else 1.0)
	projectile.launch(
		global_position + _facing * PROJECTILE_SPAWN_OFFSET,
		_facing,
		float(stats.get("attack_damage", 10)),
		float(stats.get("projectile_speed", 300)),
		float(stats.get("projectile_range", 300)),
		color
	)


## Called by enemies via body.take_damage() -- routes through GameState so armor
## mitigation (spec 2: Equipment & Armor Progression) is applied consistently.
func take_damage(amount: float) -> void:
	GameState.take_damage(amount)
	_flash_hit()


func _flash_hit() -> void:
	body_polygon.color = Color(1, 0.3, 0.3, 1)
	var tween := create_tween()
	tween.tween_property(body_polygon, "color", _body_base_color, 0.18)


func _on_vitals_changed() -> void:
	if GameState.is_dead() and respawn_timer.is_stopped():
		respawn_timer.start(RESPAWN_DELAY)


func _on_attack_cooldown_timer_timeout() -> void:
	_can_attack = true


func _on_respawn_timer_timeout() -> void:
	GameState.hp = GameState.max_hp
	GameState.hunger = max(GameState.hunger, 50.0)
	EventBus.vitals_changed.emit()
	global_position = _spawn_position
