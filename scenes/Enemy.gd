extends CharacterBody2D
## Data-driven hostile AI. Everything about a creature (stats, behavior, art, drops) comes from
## data/enemies.json keyed by `enemy_id`; set enemy_id (and optionally `power`) BEFORE add_child.
##
## Behaviors: "melee" (chase, wind up, lunge), "charger" (telegraphed straight-line rush),
## "ranged" (keeps distance, fires projectiles), "boss" (melee + hooks used by Boss.gd).
## Every attack has a visible windup (red "!" + pulse) so the player can read it and dodge --
## the player's dodge-roll i-frames are what make that windup matter.
##
## Node origin is at the creature's feet. Damage is delivered through take_damage() on the
## player; hits on this enemy arrive via take_damage(amount, from_dir, knockback, crit).

const Art = preload("res://scripts/Art.gd")
const ArtBiome = preload("res://scripts/ArtBiome.gd")
const Anim = preload("res://scripts/Anim.gd")
const PROJECTILE_SCENE := preload("res://scenes/Projectile.tscn")

enum S { IDLE, CHASE, WINDUP, STRIKE, CHARGE, RECOVER, STUN, DEAD }

const STRIKE_TIME := 0.16
const CHARGE_TIME := 0.5

@export var enemy_id: String = "dire_wolf"
## Difficulty multiplier applied on top of the data values (World scales this with player level).
@export var power: float = 1.0

var display_name := "Enemy"
var max_hp := 40.0
var hp := 40.0
var damage := 6.0
var exp_reward := 25
var move_speed := 90.0
var chase_range := 220.0
var attack_range := 28.0
var attack_cooldown := 1.0
var windup_time := 0.3
var preferred_range := 0.0
var hit_radius := 10.0
var behavior := "melee"
var def: Dictionary = {}
var knockback_resist := 0.0
var is_boss := false

var _state: int = S.IDLE
var _state_time := 0.0
var _attack_cd := 0.6
var _attack_kind := "melee"
var _dir := Vector2.RIGHT
var _dealt := false
var _kb := Vector2.ZERO
var _home := Vector2.ZERO
var _wander_dir := Vector2.ZERO
var _wander_time := 0.0
var _strafe := 1.0
var _anim_t := randf() * 10.0
var _face_x := 1.0
var _visual_kind := "humanoid"
var _base_scale := 1.0
var _parts: Dictionary = {}
var _bar: Node2D
var _bar_fill: Polygon2D
var _alert: Node2D
var _tele_line: Polygon2D
var _body_color := Color(0.6, 0.2, 0.2)
var _vanish_check := 0.0
var _flying := false
var _engaged := false
var _anim: Dictionary = Anim.make_state()
var _weapon_kind := "none"


func _ready() -> void:
	add_to_group("enemies")
	def = GameState.enemy_defs.get(enemy_id, {})
	_apply_def()
	hp = max_hp
	_home = global_position
	_strafe = 1.0 if randf() < 0.5 else -1.0
	_build_visual()
	_build_shape()
	_build_bar()
	_build_alert()
	if _flying:
		collision_mask = 0
	else:
		collision_mask = 4


func _apply_def() -> void:
	display_name = str(def.get("name", enemy_id))
	behavior = str(def.get("behavior", "melee"))
	max_hp = float(def.get("hp", 40)) * power
	damage = float(def.get("damage", 6)) * (1.0 + (power - 1.0) * 0.6)
	exp_reward = int(round(float(def.get("exp", 20)) * power))
	move_speed = float(def.get("speed", 90))
	chase_range = float(def.get("chase_range", 220))
	attack_range = float(def.get("attack_range", 28))
	attack_cooldown = float(def.get("attack_cooldown", 1.2))
	windup_time = float(def.get("windup", 0.3))
	preferred_range = float(def.get("preferred_range", 0.0))
	hit_radius = float(def.get("collision_radius", 9)) + 3.0
	_flying = bool(def.get("flying", false))
	knockback_resist = float(def.get("knockback_resist", knockback_resist))


static func _color_of(value, fallback: Color) -> Color:
	if value is Array and value.size() >= 3:
		return Color(value[0], value[1], value[2], value[3] if value.size() > 3 else 1.0)
	return fallback


func _build_visual() -> void:
	var art: String = str(def.get("art", "wolf"))
	var s: float = float(def.get("scale", 1.0))
	_base_scale = s
	if art == "wolf" or art == "boar" or ArtBiome.is_creature(art):
		_visual_kind = "beast"
		var col: Color = _color_of(def.get("color"), Color(0.45, 0.45, 0.5))
		_body_color = col
		var bcfg := {"color": col, "eye": _color_of(def.get("eye"), Color(1, 0.2, 0.15)), "kind": art, "scale": s}
		if def.has("glow"):
			bcfg["glow"] = _color_of(def.get("glow"), Color(1.0, 0.45, 0.1))
		if ArtBiome.is_creature(art):
			_parts = ArtBiome.build_creature(self, art, bcfg)
		else:
			_parts = Art.beast(self, bcfg)
	elif art == "wisp":
		_visual_kind = "wisp"
		var wc: Color = _color_of(def.get("color"), Color(0.5, 0.95, 1.0))
		_body_color = wc
		_parts = Art.wisp(self, {"color": wc})
		var light := Fx.make_light(80.0, wc, 0.9)
		light.position = Vector2(0, -22)
		add_child(light)
	else:
		_visual_kind = "humanoid"
		var cfg := {
			"tunic": _color_of(def.get("tunic"), Color(0.5, 0.2, 0.2)),
			"pants": _color_of(def.get("pants"), Color(0.3, 0.25, 0.2)),
			"hat": str(def.get("hat", "none")),
			"hat_color": _color_of(def.get("hat_color"), Color(0.5, 0.1, 0.1)),
			"weapon": str(def.get("weapon", "none")),
			"scale": s,
			"eyes": Color(0.6, 0.05, 0.05),
			"hair": Color(0.15, 0.1, 0.08),
		}
		if def.has("cape"):
			cfg["cape"] = _color_of(def.get("cape"), Color(0.3, 0.05, 0.05))
		_body_color = cfg["tunic"]
		_parts = Art.humanoid(self, cfg)
		_weapon_kind = str(def.get("weapon", "none"))
		_parts["weapon"].position = Vector2(0, -15)


func _build_shape() -> void:
	var shape_node: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if shape_node == null:
		shape_node = CollisionShape2D.new()
		add_child(shape_node)
	var r: float = float(def.get("collision_radius", 9))
	var circle := CircleShape2D.new()
	circle.radius = r
	shape_node.shape = circle
	shape_node.position = Vector2(0, -r * 0.6)


func _bar_y() -> float:
	match _visual_kind:
		"beast":
			return -34.0 * _base_scale
		"wisp":
			return -42.0
		_:
			return -44.0 * _base_scale


func _build_bar() -> void:
	if is_boss:
		return
	_bar = Node2D.new()
	_bar.position = Vector2(0, _bar_y())
	_bar.visible = false
	_bar.z_index = 20
	add_child(_bar)
	Art._poly(_bar, Art.rect(-15, -2.5, 30, 5), Color(0, 0, 0, 0.75))
	_bar_fill = Art._poly(_bar, Art.rect(-14, -1.5, 28, 3), Color(0.85, 0.2, 0.2), Vector2.ZERO, 1)


func _build_alert() -> void:
	_alert = Node2D.new()
	_alert.position = Vector2(0, _bar_y() - 10.0)
	_alert.visible = false
	_alert.z_index = 30
	add_child(_alert)
	Art._poly(_alert, Art.rect(-1.6, -8, 3.2, 6.5), Color(1, 0.2, 0.15))
	Art._poly(_alert, Art.ellipse(1.8, 1.8, 6), Color(1, 0.2, 0.15), Vector2(0, 1.5))
	_tele_line = Art._poly(self, Art.rect(0, -3, 1, 6), Color(1, 0.15, 0.1, 0.28), Vector2(0, -6), 0)
	_tele_line.visible = false


# ---------------------------------------------------------------------------
# AI
# ---------------------------------------------------------------------------

func _enter(state: int, time: float = 0.0) -> void:
	if state == S.STUN:
		Anim.cancel_attack(_anim)
	_state = state
	_state_time = time


func _find_player() -> Node2D:
	var p: Node = get_tree().get_first_node_in_group("player")
	return p as Node2D


func _player_alive(p: Node2D) -> bool:
	return p != null and not GameState.is_dead()


func _physics_process(delta: float) -> void:
	if _state == S.DEAD:
		return
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_state_time -= delta
	var player := _find_player()
	var alive: bool = _player_alive(player)
	var dist: float = global_position.distance_to(player.global_position) if player != null else INF

	_vanish_check -= delta
	if _vanish_check <= 0.0:
		_vanish_check = 1.0
		if bool(def.get("night_only", false)) and GameState.get_darkness() < 0.12 and _state != S.WINDUP:
			_vanish()
			return

	velocity = Vector2.ZERO
	match _state:
		S.IDLE:
			_do_idle(delta, player, alive, dist)
		S.CHASE:
			_do_chase(delta, player, alive, dist)
		S.WINDUP:
			if alive:
				_dir = _dir.lerp((player.global_position - global_position).normalized(), 0.15).normalized() if _attack_kind == "shoot" else _dir
			_update_telegraph()
			if _state_time <= 0.0:
				_begin_strike(player)
		S.STRIKE:
			velocity = _dir * 230.0
			if not _dealt and alive and dist <= attack_range + hit_radius * 0.5 + 10.0:
				_deal_damage(player, damage, 1.0)
			if _state_time <= 0.0:
				_enter(S.RECOVER, 0.35)
		S.CHARGE:
			velocity = _dir * move_speed * 3.4
			if not _dealt and alive and dist <= hit_radius + 12.0:
				_deal_damage(player, damage * 1.2, 1.4)
			if get_slide_collision_count() > 0 and _state_time < CHARGE_TIME - 0.12:
				Fx.shake(3.0, 0.15)
				Fx.burst(global_position + Vector2(0, -10), Color(0.7, 0.65, 0.5), 8, 70.0, 0.4)
				_enter(S.STUN, 0.9)
			elif _state_time <= 0.0:
				_enter(S.RECOVER, 0.6)
		S.RECOVER:
			if _state_time <= 0.0:
				_enter(S.CHASE)
		S.STUN:
			if _state_time <= 0.0:
				_enter(S.CHASE)

	velocity += _kb + _separation()
	_kb = _kb.move_toward(Vector2.ZERO, 700.0 * delta)
	move_and_slide()
	_animate(delta)


func _separation() -> Vector2:
	var push := Vector2.ZERO
	for other: Node2D in get_tree().get_nodes_in_group("enemies"):
		if other == self or not is_instance_valid(other):
			continue
		var off: Vector2 = global_position - other.global_position
		var d: float = off.length()
		if d > 0.01 and d < 22.0:
			push += off / d * (22.0 - d) * 4.0
	return push


func _do_idle(delta: float, player: Node2D, alive: bool, dist: float) -> void:
	if alive and dist <= chase_range:
		_engage()
		return
	_wander_time -= delta
	if _wander_time <= 0.0:
		_wander_time = randf_range(1.5, 3.5)
		if randf() < 0.4:
			_wander_dir = Vector2.ZERO
		else:
			_wander_dir = Vector2.RIGHT.rotated(randf() * TAU)
		if global_position.distance_to(_home) > 90.0:
			_wander_dir = (_home - global_position).normalized()
	velocity = _wander_dir * move_speed * 0.3


func _engage() -> void:
	_enter(S.CHASE)
	if not _engaged:
		_engaged = true
		_on_engaged()


func _on_engaged() -> void:
	pass


func _do_chase(delta: float, player: Node2D, alive: bool, dist: float) -> void:
	if not alive or dist > chase_range * 1.5:
		_enter(S.IDLE)
		_engaged = false
		return
	var to: Vector2 = (player.global_position - global_position)
	var dir: Vector2 = to.normalized()
	if _special_ai(delta, player, dist, dir):
		return
	match behavior:
		"ranged":
			_ranged_ai(player, dist, dir)
		"charger":
			if _attack_cd <= 0.0 and dist <= 190.0 and dist >= 70.0:
				_begin_windup(dir, "charge", windup_time)
			elif _attack_cd <= 0.0 and dist <= attack_range:
				_begin_windup(dir, "melee", windup_time * 0.7)
			elif dist > attack_range * 0.8:
				velocity = dir * move_speed
		_:
			if _attack_cd <= 0.0 and dist <= attack_range:
				_begin_windup(dir, "melee", windup_time)
			elif dist > attack_range * 0.7:
				velocity = dir * move_speed


func _ranged_ai(player: Node2D, dist: float, dir: Vector2) -> void:
	var want: float = preferred_range if preferred_range > 0.0 else attack_range * 0.8
	if dist < want - 25.0:
		velocity = -dir * move_speed * 0.9
	elif dist > want + 25.0:
		velocity = dir * move_speed
	else:
		velocity = dir.orthogonal() * _strafe * move_speed * 0.45
	if _attack_cd <= 0.0 and dist <= attack_range:
		_begin_windup(dir, "shoot", windup_time)


## Boss.gd overrides this to inject its own abilities; return true if it took over this frame.
func _special_ai(_delta: float, _player: Node2D, _dist: float, _dir_to_player: Vector2) -> bool:
	return false


func _begin_windup(dir: Vector2, kind: String, time: float) -> void:
	_attack_kind = kind
	_dir = dir
	_face(dir)
	_dealt = false
	_enter(S.WINDUP, time)
	_alert.visible = true
	Fx.play("roar", 2.2, -12.0)
	if _visual_kind == "humanoid" and _weapon_kind != "none":
		var ak: String = "bow" if kind == "shoot" and _weapon_kind == "bow" else _weapon_kind
		Anim.start_attack(_anim, ak, time, STRIKE_TIME, 0.35, _face_x)
	_on_windup_start(kind)


func _on_windup_start(_kind: String) -> void:
	pass


func _begin_strike(player: Node2D) -> void:
	_alert.visible = false
	_tele_line.visible = false
	_dealt = false
	if _strike_custom(_attack_kind, player):
		return
	match _attack_kind:
		"charge":
			_attack_cd = attack_cooldown
			_enter(S.CHARGE, CHARGE_TIME)
			Fx.play("dodge", 0.7)
		"shoot":
			_attack_cd = attack_cooldown
			_fire_projectile(player)
			_enter(S.RECOVER, 0.3)
		_:
			_attack_cd = attack_cooldown
			_enter(S.STRIKE, STRIKE_TIME)
			Fx.play("swing", 0.8)


## Hook for Boss.gd abilities; return true when the boss handled the strike itself.
func _strike_custom(_kind: String, _player: Node2D) -> bool:
	return false


func _fire_projectile(player: Node2D) -> void:
	var from: Vector2 = global_position + Vector2(0, -16)
	var aim: Vector2 = _dir
	if _player_alive(player):
		aim = ((player.global_position + Vector2(0, -12)) - from).normalized()
	var proj := PROJECTILE_SCENE.instantiate()
	get_tree().current_scene.add_child(proj)
	var col: Color = _color_of(def.get("projectile_color"), Color(0.9, 0.7, 0.3))
	proj.launch(from + aim * 12.0, aim, damage, float(def.get("projectile_speed", 240)), attack_range + 90.0, col, true)
	Fx.play("magic" if _visual_kind == "wisp" else "shoot", 0.9)


func _deal_damage(player: Node2D, amount: float, kb_mult: float) -> void:
	_dealt = true
	if player.has_method("take_damage"):
		player.take_damage(amount, _dir, 200.0 * kb_mult)


func _update_telegraph() -> void:
	if _attack_kind == "charge":
		_tele_line.visible = true
		_tele_line.rotation = _dir.angle()
		_tele_line.scale = Vector2(190.0, 1.0)
	_alert.scale = Vector2.ONE * (1.0 + 0.25 * sin(_anim_t * 3.0))


func _face(dir: Vector2) -> void:
	if absf(dir.x) > 0.05:
		_face_x = signf(dir.x)


# ---------------------------------------------------------------------------
# Damage / death
# ---------------------------------------------------------------------------

func take_damage(amount: float, from_dir: Vector2 = Vector2.ZERO, knock: float = 0.0, crit: bool = false) -> void:
	if _state == S.DEAD:
		return
	hp = maxf(0.0, hp - amount)
	_kb += from_dir * knock * (1.0 - knockback_resist)
	Fx.damage_number(global_position + Vector2(0, _bar_y() + 4.0), amount, Color(1.0, 0.75, 0.2) if crit else Color(1, 1, 1), crit)
	Fx.burst(global_position + Vector2(0, -12), _body_color.lightened(0.2), 5, 70.0, 0.3)
	_flash_hit()
	Anim.hurt(_anim, from_dir)
	if _bar != null:
		_bar.visible = true
		_bar_fill.scale.x = clampf(hp / max_hp, 0.0, 1.0)
	if not _engaged and _state == S.IDLE:
		_engage()
	if is_boss:
		EventBus.boss_hp_changed.emit(hp, max_hp)
	_on_damaged()
	if hp <= 0.0:
		_die()
		return
	if _state == S.WINDUP and knock >= 300.0 and not is_boss:
		_alert.visible = false
		_tele_line.visible = false
		_enter(S.STUN, 0.4)
		_attack_cd = maxf(_attack_cd, attack_cooldown * 0.5)
	elif _state != S.STRIKE and _state != S.CHARGE and _state != S.WINDUP and knock >= 300.0 and not is_boss:
		_enter(S.STUN, 0.3)


func _on_damaged() -> void:
	pass


func stun(time: float) -> void:
	if _state == S.DEAD or is_boss:
		return
	_alert.visible = false
	_tele_line.visible = false
	_enter(S.STUN, time)


func _flash_hit() -> void:
	if _parts.is_empty():
		return
	var root: Node2D = _parts["root"]
	root.modulate = Color(2.2, 2.2, 2.2)
	var tween := create_tween()
	tween.tween_property(root, "modulate", Color.WHITE, 0.14)


func _die() -> void:
	_enter(S.DEAD)
	_alert.visible = false
	_tele_line.visible = false
	if _bar != null:
		_bar.visible = false
	set_deferred("collision_layer", 0)
	GameState.register_kill(enemy_id)
	GameState.grant_exp(GameState.active_class, exp_reward)
	Fx.play("enemy_die", 0.8 if is_boss else 1.0)
	Fx.burst(global_position + Vector2(0, -12), _body_color, 16 if not is_boss else 40, 130.0, 0.6)
	Fx.floating_text(global_position + Vector2(0, _bar_y() - 12.0), "+%d EXP" % exp_reward, Color(0.6, 0.85, 1.0))
	_roll_drops()
	_on_death()
	var tween := Anim.death_tween(self, _parts, _visual_kind, _face_x, is_boss)
	tween.tween_callback(queue_free).set_delay(1.4 if _visual_kind != "wisp" else 0.6)


func _on_death() -> void:
	pass


func _roll_drops() -> void:
	var idx := 0
	for d: Dictionary in def.get("drops", []):
		if randf() > float(d.get("chance", 1.0)):
			continue
		var qty: int = randi_range(int(d.get("min", 1)), int(d.get("max", 1)))
		var item: String = str(d.get("item", ""))
		if item == "" or qty <= 0:
			continue
		GameState.add_item(item, qty)
		var pos: Vector2 = global_position + Vector2(0, -26.0 - 13.0 * idx)
		Fx.floating_text(pos, "+%d %s" % [qty, GameState.get_item_name(item)], GameState.get_item_color(item).lightened(0.3))
		idx += 1
	if idx > 0:
		Fx.play("pickup")


func _vanish() -> void:
	_enter(S.DEAD)
	set_deferred("collision_layer", 0)
	var root: Node2D = _parts["root"]
	var tween := create_tween()
	tween.tween_property(root, "modulate:a", 0.0, 0.8)
	tween.tween_callback(queue_free)


# ---------------------------------------------------------------------------
# Animation
# ---------------------------------------------------------------------------

func _animate(delta: float) -> void:
	if _parts.is_empty() or _state == S.DEAD:
		return
	var moving: bool = velocity.length() > 20.0 and _state != S.STUN
	_anim_t += delta * (13.0 if moving else 2.5)
	if velocity.x > 8.0:
		_face_x = 1.0
	elif velocity.x < -8.0:
		_face_x = -1.0
	var root: Node2D = _parts["root"]
	var face_vec := Vector2(_face_x, 0.0)
	if _state == S.WINDUP or _state == S.STRIKE or _state == S.CHARGE:
		face_vec = _dir
		_face(_dir)
	var vel: Vector2 = velocity - _kb
	var stunned: bool = _state == S.STUN

	match _visual_kind:
		"beast":
			var crouch: float = 0.0
			var lunge: float = 0.0
			if _state == S.WINDUP:
				crouch = clampf(1.0 - _state_time / maxf(windup_time, 0.05), 0.0, 1.0)
			elif _state == S.STRIKE or _state == S.CHARGE:
				lunge = 1.0
			Anim.update_beast(_parts, _anim, delta, vel, _face_x, {"crouch": crouch, "lunge": lunge, "base_scale": _base_scale, "frozen": stunned})
		"wisp":
			Anim.update_wisp(_parts, _anim, delta, vel, _body_color)
		_:
			Anim.update_humanoid(_parts, _anim, delta, vel, face_vec.normalized(), {"max_speed": move_speed * 1.2, "frozen": stunned, "weapon": _weapon_kind != "none"})

	if _state == S.WINDUP:
		var pulse: float = 0.5 + 0.5 * sin(_anim_t * 4.0)
		root.modulate = Color(1.0 + 0.5 * pulse, 1.0 - 0.25 * pulse, 1.0 - 0.25 * pulse)
	elif root.modulate.a > 0.95 and root.modulate.r < 1.05:
		root.modulate = Color.WHITE
	if _state == S.STUN:
		root.rotation = sin(_anim_t * 2.0) * 0.08
	elif _state != S.DEAD:
		root.rotation = 0.0
