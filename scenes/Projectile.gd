extends Area2D
## Ranged-attack projectile shared by Bowman/Magic User/Alchemist (spec 2: per-role combat).
## Player.gd spawns and configures one via launch(), then adds it to the main scene so its
## position/rotation are independent of the player's own transform. Travels in a straight
## line, damages the first enemy body it touches, and despawns past max_range.

var _direction := Vector2.RIGHT
var _speed := 300.0
var _max_range := 300.0
var _damage := 10.0
var _traveled := 0.0
var _hit := false

@onready var visual: Polygon2D = $Polygon2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func launch(from_position: Vector2, direction: Vector2, projectile_damage: float, projectile_speed: float, projectile_range: float, color: Color) -> void:
	global_position = from_position
	_direction = direction.normalized() if direction.length() > 0.0 else Vector2.RIGHT
	_damage = projectile_damage
	_speed = projectile_speed
	_max_range = projectile_range
	rotation = _direction.angle()
	visual.color = color


func _physics_process(delta: float) -> void:
	var step := _direction * _speed * delta
	global_position += step
	_traveled += step.length()
	if _traveled >= _max_range:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if _hit:
		return
	if body.has_method("take_damage"):
		_hit = true
		body.take_damage(_damage)
		queue_free()
