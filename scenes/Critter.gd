extends Node2D
## Harmless ambient wildlife: rabbits, frogs, lizards and crabs scurry away when the player gets
## close; deer graze and trot off. Purely decorative (no collision, no drops). Set `kind` before add_child.

const Art = preload("res://scripts/Art.gd")

var kind := "rabbit"

var _vel := Vector2.ZERO
var _wait := randf_range(0.5, 3.0)
var _hop_t := 0.0
var _body: Node2D
var _face := 1.0
var _player: Node2D
var _home := Vector2.ZERO
var _bounds := Rect2(-150, -150, 12000, 9000)
var _t := randf() * 10.0
var _tail: Node2D
var _claws: Array = []

const TUNING := {
	"rabbit": {"trigger": 90.0, "speed": 110.0, "hop": 4.0, "rate": 10.0},
	"deer": {"trigger": 130.0, "speed": 120.0, "hop": 2.0, "rate": 10.0},
	"frog": {"trigger": 70.0, "speed": 95.0, "hop": 7.0, "rate": 8.0},
	"lizard": {"trigger": 80.0, "speed": 150.0, "hop": 0.6, "rate": 22.0},
	"crab": {"trigger": 75.0, "speed": 85.0, "hop": 0.8, "rate": 18.0},
}


func _ready() -> void:
	_home = position
	var world := get_tree().current_scene
	if world != null and world.has_method("get_world_rect"):
		_bounds = (world.get_world_rect() as Rect2).grow(-40)
	match kind:
		"deer":
			_build_deer()
		"frog":
			_build_frog()
		"lizard":
			_build_lizard()
		"crab":
			_build_crab()
		_:
			_build_rabbit()


func _build_rabbit() -> void:
	_body = Node2D.new()
	add_child(_body)
	Art.shadow(_body, 6, 2.5, 0.25)
	var fur := Color(0.72, 0.66, 0.58)
	Art._poly(_body, Art.ellipse(6, 4.5, 10), fur, Vector2(0, -5))
	Art._poly(_body, Art.ellipse(3.5, 3.2, 8), fur.lightened(0.06), Vector2(5, -8))
	Art._poly(_body, Art.ellipse(1.1, 3.6, 6), fur.darkened(0.1), Vector2(4.5, -13))
	Art._poly(_body, Art.ellipse(1.1, 3.6, 6), fur.darkened(0.1), Vector2(6.5, -12.5))
	Art._poly(_body, Art.ellipse(2.0, 2.0, 6), Color(0.95, 0.95, 0.95), Vector2(-6.5, -6))
	Art._poly(_body, Art.ellipse(0.7, 0.7, 4), Color(0.1, 0.08, 0.08), Vector2(7, -9))


func _build_deer() -> void:
	_body = Node2D.new()
	add_child(_body)
	Art.shadow(_body, 12, 4, 0.25)
	var fur := Color(0.58, 0.4, 0.24)
	for x in [-7.0, -4.0, 6.0, 9.0]:
		Art._poly(_body, Art.rect(-0.9, 0, 1.8, 12), fur.darkened(0.25), Vector2(x, -12))
	Art._poly(_body, Art.ellipse(11, 5.5, 12), fur, Vector2(0, -15))
	Art._poly(_body, Art.ellipse(7, 3, 10), Color(0.85, 0.78, 0.66), Vector2(0, -12))
	Art._poly(_body, PackedVector2Array([Vector2(8, -17), Vector2(12, -28), Vector2(15, -26), Vector2(12, -15)]), fur)
	Art._poly(_body, Art.ellipse(4, 3, 8), fur.lightened(0.05), Vector2(15, -28))
	Art._poly(_body, Art.tri(Vector2(12, -30), Vector2(10, -35), Vector2(15, -31)), fur.darkened(0.1))
	Art._poly(_body, Art.ellipse(0.8, 0.8, 4), Color(0.1, 0.08, 0.08), Vector2(17, -29))
	Art._poly(_body, Art.tri(Vector2(-10, -18), Vector2(-14, -21), Vector2(-10, -14)), Color(0.95, 0.9, 0.85))


func _build_frog() -> void:
	_body = Node2D.new()
	add_child(_body)
	Art.shadow(_body, 5, 2, 0.25)
	var skin := Color(0.3, 0.55, 0.28)
	Art._poly(_body, Art.ellipse(4.5, 3.4, 9), skin, Vector2(0, -3.5))
	Art._poly(_body, Art.ellipse(3.0, 2.0, 8), skin.lightened(0.25), Vector2(0, -2.2))
	Art._poly(_body, Art.ellipse(3.2, 2.6, 8), skin.lightened(0.05), Vector2(3.5, -5))
	Art._poly(_body, Art.ellipse(1.1, 1.1, 5), Color(0.95, 0.9, 0.5), Vector2(4.5, -7.2))
	Art._poly(_body, Art.ellipse(0.5, 0.5, 4), Color(0.05, 0.05, 0.05), Vector2(4.8, -7.2))
	Art._poly(_body, Art.ellipse(2.4, 1.3, 6), skin.darkened(0.2), Vector2(-3.5, -1.2))


func _build_lizard() -> void:
	_body = Node2D.new()
	add_child(_body)
	Art.shadow(_body, 7, 2, 0.22)
	var skin := Color(0.58, 0.5, 0.3)
	_tail = Node2D.new()
	_tail.position = Vector2(-5, -2.5)
	_body.add_child(_tail)
	Art._poly(_tail, PackedVector2Array([Vector2(0, -1.5), Vector2(-9, -0.4), Vector2(-14, 0.6), Vector2(-9, 0.8), Vector2(0, 1.5)]), skin.darkened(0.1))
	Art._poly(_body, Art.ellipse(5.5, 2.2, 9), skin, Vector2(0, -2.5))
	Art._poly(_body, Art.ellipse(2.6, 1.8, 8), skin.lightened(0.08), Vector2(6, -2.6))
	Art._poly(_body, Art.ellipse(0.55, 0.55, 4), Color(0.05, 0.05, 0.05), Vector2(7.2, -3.2))
	for x in [-2.0, 3.0]:
		Art._poly(_body, Art.rect(-0.5, 0, 1.0, 2.2), skin.darkened(0.25), Vector2(x, -2.5))
	Art._poly(_body, Art.ellipse(3.5, 0.9, 6), skin.lightened(0.2), Vector2(-0.5, -3.6))


func _build_crab() -> void:
	_body = Node2D.new()
	add_child(_body)
	Art.shadow(_body, 6, 2.2, 0.22)
	var shell := Color(0.82, 0.38, 0.28)
	for x in [-4.0, -1.5, 1.5, 4.0]:
		Art._poly(_body, Art.rect(-0.4, 0, 0.8, 3.2), shell.darkened(0.25), Vector2(x, -3.6))
	Art._poly(_body, Art.ellipse(5.5, 3.3, 10), shell, Vector2(0, -4.8))
	Art._poly(_body, Art.ellipse(3.2, 1.6, 8), shell.lightened(0.15), Vector2(0, -5.6))
	Art._poly(_body, Art.ellipse(0.6, 1.0, 4), Color(0.05, 0.05, 0.05), Vector2(-1.6, -8.6))
	Art._poly(_body, Art.ellipse(0.6, 1.0, 4), Color(0.05, 0.05, 0.05), Vector2(1.6, -8.6))
	for sx in [-1.0, 1.0]:
		var claw := Node2D.new()
		claw.position = Vector2(sx * 5.5, -5.5)
		_body.add_child(claw)
		Art._poly(claw, Art.ellipse(2.4, 1.8, 7), shell.lightened(0.05), Vector2(sx * 2.0, -2.0))
		Art._poly(claw, Art.tri(Vector2(sx * 3.5, -3.2), Vector2(sx * 5.8, -4.6), Vector2(sx * 4.6, -1.2)), shell.darkened(0.1))
		_claws.append(claw)


func _process(delta: float) -> void:
	_t += delta
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	var tune: Dictionary = TUNING.get(kind, TUNING["rabbit"])
	var scared := false
	var away := Vector2.ZERO
	if _player != null:
		var off: Vector2 = global_position - _player.global_position
		var trigger: float = tune["trigger"]
		if off.length() < trigger:
			scared = true
			away = off.normalized()
	var speed: float = tune["speed"]
	if scared:
		_vel = away * speed
		_wait = 0.3
	else:
		_wait -= delta
		if _wait <= 0.0:
			if _vel == Vector2.ZERO:
				var dir := Vector2.RIGHT.rotated(randf() * TAU)
				if position.distance_to(_home) > 120.0:
					dir = (_home - position).normalized()
				_vel = dir * (speed * 0.3)
				_wait = randf_range(0.4, 0.9)
			else:
				_vel = Vector2.ZERO
				_wait = randf_range(1.0, 4.0)
	var moving: bool = _vel != Vector2.ZERO
	if moving:
		position += _vel * delta
		position = position.clamp(_bounds.position, _bounds.end)
		_hop_t += delta * (float(tune["rate"]) * (1.6 if scared else 1.0))
		var hop: float = float(tune["hop"])
		_body.position.y = -absf(sin(_hop_t)) * hop
		if kind == "crab":
			_body.rotation = sin(_hop_t) * 0.06
			if absf(_vel.x) > 1.0:
				_face = signf(_vel.x)
		elif absf(_vel.x) > 1.0:
			_face = signf(_vel.x)
	else:
		_body.position.y = 0.0
		_body.rotation = 0.0
	var breath: float = sin(_t * 2.4) * (0.0 if moving else 0.035)
	var squash: float = 0.0
	if moving and kind in ["rabbit", "frog", "deer"]:
		squash = -0.12 * sin(_hop_t * 2.0) * (1.0 if kind != "deer" else 0.3)
	_body.scale = Vector2(_face * (1.0 - breath * 0.6 - squash * 0.5), 1.0 + breath + squash)
	if _tail != null:
		_tail.rotation = sin(_t * (14.0 if moving else 2.0)) * (0.5 if moving else 0.12)
	for i in _claws.size():
		var cl: Node2D = _claws[i]
		cl.rotation = sin(_t * (3.0 if not moving else 12.0) + i * 2.0) * 0.25 * (1.0 if i == 0 else -1.0)
