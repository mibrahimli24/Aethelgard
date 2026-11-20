extends Area2D
## Straight-flying projectile shared by the player's ranged classes and enemy archers/wisps.
## launch() configures and aims it; hits_player flips which physics layers it collides with.
## Layers: 1 = player, 2 = enemies, 4 = world obstacles. It always stops on world obstacles.

var _direction := Vector2.RIGHT
var _speed := 300.0
var _max_range := 300.0
var _damage := 10.0
var _traveled := 0.0
var _hit := false
var _color := Color.WHITE
var _hits_player := false
var _trail: Line2D
var _pierce := 0

@onready var visual: Polygon2D = $Polygon2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	z_index = 5
	_trail = Line2D.new()
	_trail.width = 4.0
	_trail.top_level = true
	_trail.z_index = 4
	_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.8)])
	_trail.gradient = grad
	add_child(_trail)


func launch(from_position: Vector2, direction: Vector2, projectile_damage: float, projectile_speed: float, projectile_range: float, color: Color, hits_player: bool = false, pierce: int = 0) -> void:
	global_position = from_position
	_direction = direction.normalized() if direction.length() > 0.0 else Vector2.RIGHT
	_damage = projectile_damage
	_speed = projectile_speed
	_max_range = projectile_range
	_color = color
	_hits_player = hits_player
	_pierce = pierce
	rotation = _direction.angle()
	visual.color = color
	collision_mask = 5 if hits_player else 6
	var light := Fx.make_light(46.0, color, 0.8)
	add_child(light)


func _physics_process(delta: float) -> void:
	var step := _direction * _speed * delta
	global_position += step
	_traveled += step.length()
	_trail.default_color = Color(_color.r, _color.g, _color.b, 0.7)
	_trail.add_point(global_position)
	if _trail.get_point_count() > 9:
		_trail.remove_point(0)
	if _traveled >= _max_range:
		_finish()


func _on_body_entered(body: Node2D) -> void:
	if _hit:
		return
	if body.has_method("take_damage"):
		body.take_damage(_damage, _direction)
		Fx.burst(global_position, _color, 6, 70.0, 0.3)
		if _pierce > 0:
			_pierce -= 1
			return
		_hit = true
		_finish()
	elif body is StaticBody2D:
		_hit = true
		Fx.burst(global_position, _color, 4, 50.0, 0.25)
		_finish()


func _finish() -> void:
	set_deferred("monitoring", false)
	visible = false
	_trail.visible = false
	queue_free()
