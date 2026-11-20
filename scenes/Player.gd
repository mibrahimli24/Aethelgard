extends CharacterBody2D
## Top-down player controller: movement, dodge-roll, combo melee / ranged attacks, per-class
## special ability, interaction, and death/respawn. Vitals truth lives in GameState -- this
## script only reads/writes through it. Attack numbers come from GameState.get_active_combat_stats()
## (data/classes.json "combat" block) and specials from the "special" block, so every role's
## feel lives in data rather than scattered across scripts.
##
## Node origin is at the character's FEET (y-sorting + collisions rely on that); the visual body
## is built in code by Art.humanoid() and rebuilt when the class or gear tier changes.

const Art = preload("res://scripts/Art.gd")
const Anim = preload("res://scripts/Anim.gd")
const PROJECTILE_SCENE := preload("res://scenes/Projectile.tscn")

const BASE_SPEED := 140.0
const RESPAWN_DELAY := 2.5
const DODGE_TIME := 0.22
const DODGE_COOLDOWN := 0.8
const IFRAME_AFTER_HIT := 0.35
const CHEST := Vector2(0, -14)
const ASSIST_RANGE := 300.0

const LOOKS := {
	"swordsman": {"tunic": Color(0.25, 0.4, 0.78), "pants": Color(0.28, 0.24, 0.2), "hat": "helm", "hat_color": Color(0.62, 0.64, 0.7), "weapon": "sword", "hair": Color(0.35, 0.22, 0.1)},
	"bowman": {"tunic": Color(0.24, 0.5, 0.28), "pants": Color(0.36, 0.26, 0.16), "hat": "hood", "hat_color": Color(0.2, 0.36, 0.2), "weapon": "bow", "hair": Color(0.5, 0.35, 0.15)},
	"magic_user": {"tunic": Color(0.5, 0.3, 0.78), "pants": Color(0.3, 0.2, 0.45), "hat": "pointy", "hat_color": Color(0.4, 0.22, 0.66), "weapon": "staff", "hair": Color(0.85, 0.85, 0.9)},
	"rogue": {"tunic": Color(0.2, 0.2, 0.25), "pants": Color(0.14, 0.14, 0.17), "hat": "hood", "hat_color": Color(0.13, 0.13, 0.17), "weapon": "dagger", "hair": Color(0.1, 0.1, 0.1), "cape": Color(0.11, 0.11, 0.14)},
	"alchemist": {"tunic": Color(0.82, 0.52, 0.2), "pants": Color(0.38, 0.28, 0.18), "hat": "cap", "hat_color": Color(0.45, 0.3, 0.14), "weapon": "flask", "hair": Color(0.6, 0.25, 0.1)},
}
const SLASH_COLORS := {
	"swordsman": Color(0.85, 0.92, 1.0, 0.75),
	"rogue": Color(0.75, 0.55, 0.95, 0.75),
}

@onready var respawn_timer: Timer = $RespawnTimer
@onready var camera: Camera2D = $Camera2D

var swing_offset := 0.0

var _facing := Vector2.DOWN
var _spawn_position: Vector2
var _parts: Dictionary = {}
var _built_class := ""
var _built_tier := -1
var _anim: Dictionary = Anim.make_state()

var _attack_cd := 0.0
var _combo := 0
var _combo_timer := 0.0
var _special_cd := 0.0
var _crit_ready := 0.0

var _dodge_time := 0.0
var _dodge_cd := 0.0
var _dodge_dir := Vector2.DOWN
var _dash_speed := 380.0
var _iframes := 0.0
var _kb_velocity := Vector2.ZERO

var _shake_amount := 0.0
var _shake_time := 0.0
var _shake_total := 0.1

var _dead_handled := false
var _interact_target: Node = null
var _last_prompt := ""


func _ready() -> void:
	add_to_group("player")
	_spawn_position = global_position
	EventBus.vitals_changed.connect(_on_vitals_changed)
	EventBus.class_changed.connect(_on_class_changed)
	EventBus.level_up.connect(_on_level_up)
	_rebuild_visuals()
	var lantern := Fx.make_light(190.0, Color(1.0, 0.85, 0.6), 0.7)
	lantern.position = CHEST
	add_child(lantern)
	var world := get_tree().current_scene
	if world != null and world.has_method("get_world_rect"):
		var r: Rect2 = world.get_world_rect()
		camera.limit_left = int(r.position.x)
		camera.limit_top = int(r.position.y)
		camera.limit_right = int(r.end.x)
		camera.limit_bottom = int(r.end.y)


func _process(delta: float) -> void:
	if _shake_time > 0.0:
		_shake_time -= delta
		var k: float = clampf(_shake_time / _shake_total, 0.0, 1.0)
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake_amount * k
		if _shake_time <= 0.0:
			camera.offset = Vector2.ZERO
			_shake_amount = 0.0


func shake(amount: float, duration: float = 0.18) -> void:
	if amount < _shake_amount * (_shake_time / _shake_total):
		return
	_shake_amount = amount
	_shake_time = duration
	_shake_total = maxf(duration, 0.01)


func _physics_process(delta: float) -> void:
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_combo_timer = maxf(0.0, _combo_timer - delta)
	_special_cd = maxf(0.0, _special_cd - delta)
	_crit_ready = maxf(0.0, _crit_ready - delta)
	_dodge_cd = maxf(0.0, _dodge_cd - delta)
	_iframes = maxf(0.0, _iframes - delta)

	if GameState.is_dead():
		velocity = Vector2.ZERO
		return

	if GameState.get_equipped_tier_name(GameState.active_class) != "" and int(GameState.class_data[GameState.active_class].get("equipped_tier_index", 0)) != _built_tier:
		_rebuild_visuals()

	var input_dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()

	if _dodge_time > 0.0:
		_dodge_time -= delta
		velocity = _dodge_dir * _dash_speed * (0.55 + 0.45 * clampf(_dodge_time / DODGE_TIME, 0.0, 1.0))
	else:
		if input_dir.length() > 0.1:
			_facing = input_dir.normalized()
		var slow := 0.6 if _attack_cd > 0.0 else 1.0
		velocity = input_dir * BASE_SPEED * GameState.get_move_speed_multiplier() * slow
	velocity += _kb_velocity
	_kb_velocity = _kb_velocity.move_toward(Vector2.ZERO, 900.0 * delta)
	move_and_slide()

	_update_visuals(delta, input_dir)
	_update_interaction()

	if Input.is_action_just_pressed("dodge") and _dodge_cd <= 0.0 and _dodge_time <= 0.0:
		_start_dodge(input_dir if input_dir.length() > 0.1 else _facing)
	if _dodge_time <= 0.0:
		if Input.is_action_pressed("attack") and _attack_cd <= 0.0:
			_perform_attack()
		if Input.is_action_just_pressed("special"):
			_use_special()
		if Input.is_action_just_pressed("use_food"):
			_quick_eat()


# ---------------------------------------------------------------------------
# Visuals
# ---------------------------------------------------------------------------

func _rebuild_visuals() -> void:
	var old: Node = get_node_or_null("Visual")
	if old != null:
		old.free()
	var class_id: String = GameState.active_class
	var tier: int = int(GameState.class_data[class_id].get("equipped_tier_index", 0))
	var cfg: Dictionary = LOOKS.get(class_id, LOOKS["swordsman"]).duplicate()
	_parts = Art.humanoid(self, cfg)
	var body: Node2D = _parts["body"]
	if tier >= 1:
		var metal := Color(0.55, 0.57, 0.62).lightened(0.08 * float(tier - 1))
		var pl := Polygon2D.new()
		pl.polygon = Art.ellipse(4.5, 3.2, 8)
		pl.color = metal
		pl.position = Vector2(-9, -22)
		pl.z_index = 0
		body.add_child(pl)
		var pr := Polygon2D.new()
		pr.polygon = Art.ellipse(4.5, 3.2, 8)
		pr.color = metal
		pr.position = Vector2(9, -22)
		pr.z_index = 0
		body.add_child(pr)
	if tier >= 2:
		var chest := Polygon2D.new()
		chest.polygon = PackedVector2Array([Vector2(-5, -22), Vector2(5, -22), Vector2(4, -14), Vector2(-4, -14)])
		chest.color = Color(0.6, 0.62, 0.68, 0.85)
		chest.z_index = 0
		body.add_child(chest)
	_built_class = class_id
	_built_tier = tier


func _update_visuals(delta: float, _input_dir: Vector2) -> void:
	if _parts.is_empty():
		return
	var root: Node2D = _parts["root"]
	if _dodge_time > 0.0:
		var prog: float = 1.0 - clampf(_dodge_time / DODGE_TIME, 0.0, 1.0)
		Anim.roll(_parts, _anim, prog, 1.0 if _dodge_dir.x >= 0.0 else -1.0)
		root.modulate.a = 0.6
	else:
		Anim.roll_end(_parts, _anim)
		var vel: Vector2 = velocity - _kb_velocity
		Anim.update_humanoid(_parts, _anim, delta, vel, _facing, {"max_speed": BASE_SPEED, "swing_offset": swing_offset})
		if _iframes <= 0.0:
			root.modulate = root.modulate.lerp(Color.WHITE, minf(1.0, delta * 12.0))
		else:
			root.modulate.a = 0.75 if int(_iframes * 24.0) % 2 == 0 else 1.0


func _attack_kind() -> String:
	return str(LOOKS.get(GameState.active_class, LOOKS["swordsman"]).get("weapon", "sword"))


func _flash(color: Color) -> void:
	if _parts.is_empty():
		return
	var root: Node2D = _parts["root"]
	root.modulate = color
	var tween := create_tween()
	tween.tween_property(root, "modulate", Color.WHITE, 0.2)


func _spawn_slash(dir: Vector2, reach: float, half_angle: float, color: Color) -> void:
	var slash := Polygon2D.new()
	var pts := PackedVector2Array()
	var steps := 9
	for i in steps + 1:
		var a: float = lerpf(-half_angle, half_angle, float(i) / float(steps))
		pts.append(Vector2(cos(a), sin(a)) * reach)
	for i in range(steps, -1, -1):
		var a2: float = lerpf(-half_angle, half_angle, float(i) / float(steps))
		pts.append(Vector2(cos(a2), sin(a2)) * reach * 0.55)
	slash.polygon = pts
	slash.color = color
	slash.position = CHEST
	slash.rotation = dir.angle()
	slash.z_index = 3
	add_child(slash)
	var tween := slash.create_tween()
	tween.set_parallel(true)
	tween.tween_property(slash, "modulate:a", 0.0, 0.16)
	tween.tween_property(slash, "scale", Vector2(1.12, 1.12), 0.16)
	tween.chain().tween_callback(slash.queue_free)


func _sweep_weapon(from_angle: float, to_angle: float, duration: float = 0.12) -> void:
	swing_offset = from_angle
	var tween := create_tween()
	tween.tween_property(self, "swing_offset", to_angle, duration).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "swing_offset", 0.0, 0.1)


# ---------------------------------------------------------------------------
# Combat
# ---------------------------------------------------------------------------

func _aim_dir(max_range: float, min_dot: float) -> Vector2:
	var best_dir := _facing
	var best_score := -INF
	for e: Node2D in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var to: Vector2 = e.global_position - global_position
		var d: float = to.length()
		if d > max_range or d < 1.0:
			continue
		var dir: Vector2 = to / d
		var dot: float = dir.dot(_facing)
		if dot < min_dot:
			continue
		var score: float = dot * 100.0 - d * 0.1
		if score > best_score:
			best_score = score
			best_dir = dir
	return best_dir


func _perform_attack() -> void:
	var stats: Dictionary = GameState.get_active_combat_stats()
	if stats.is_empty():
		return
	_attack_cd = float(stats.get("attack_cooldown", 0.45))
	if stats.get("attack_type", "melee") == "ranged":
		_fire_projectile(stats)
	else:
		_melee_attack(stats)


func _melee_attack(stats: Dictionary) -> void:
	if _combo_timer <= 0.0:
		_combo = 0
	var finisher: bool = _combo >= 2
	var dir: Vector2 = _aim_dir(130.0, 0.2)
	_facing = dir
	var reach: float = float(stats.get("attack_range", 34.0)) + 18.0 + (10.0 if finisher else 0.0)
	var half: float = 1.9 if finisher else 1.3
	var base: float = float(stats.get("attack_damage", 10)) * GameState.get_level_damage_multiplier() * (1.7 if finisher else 1.0)
	var crit_chance: float = float(stats.get("crit_chance", 0.0))
	var crit_mult: float = float(stats.get("crit_multiplier", 1.75))

	var slash_color: Color = SLASH_COLORS.get(GameState.active_class, Color(1, 1, 1, 0.7))
	if finisher:
		slash_color = Color(1.0, 0.75, 0.3, 0.85)
	_spawn_slash(dir, reach, half, slash_color)
	var side: float = 1.0 if _combo % 2 == 0 else -1.0
	Anim.start_attack(_anim, _attack_kind(), 0.09 if finisher else 0.06, 0.09, 0.26 if finisher else 0.2, side)
	_kb_velocity += dir * (170.0 if finisher else 100.0)

	var hit_any := false
	var any_crit := false
	for e: Node2D in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var to: Vector2 = e.global_position - global_position
		var d: float = to.length()
		if d > reach + float(e.hit_radius):
			continue
		if d > 10.0 and absf(dir.angle_to(to)) > half:
			continue
		var crit: bool = _crit_ready > 0.0 or (crit_chance > 0.0 and randf() < crit_chance)
		var dmg: float = base * (crit_mult if crit else 1.0)
		e.take_damage(dmg, to.normalized(), 320.0 if finisher else 170.0, crit)
		hit_any = true
		any_crit = any_crit or crit
	if hit_any:
		_crit_ready = 0.0
		Fx.play("crit" if any_crit else "hit", 0.85 if finisher else 1.0)
		Fx.shake(4.5 if finisher else 2.2, 0.14)
		if finisher or any_crit:
			Fx.hit_stop(0.055)
	else:
		Fx.play("swing", 1.15 if finisher else 1.0)
	_combo = 0 if finisher else _combo + 1
	_combo_timer = 0.9
	if finisher:
		_attack_cd += 0.18


func _fire_projectile(stats: Dictionary) -> void:
	var dir: Vector2 = _aim_dir(ASSIST_RANGE, 0.75)
	_facing = dir
	var color_arr: Array = stats.get("projectile_color", [1, 1, 1, 1])
	var color := Color(color_arr[0], color_arr[1], color_arr[2], color_arr[3] if color_arr.size() > 3 else 1.0)
	var dmg: float = float(stats.get("attack_damage", 10)) * GameState.get_level_damage_multiplier()
	_spawn_projectile(dir, dmg, float(stats.get("projectile_speed", 300)), float(stats.get("projectile_range", 300)), color)
	Anim.start_attack(_anim, _attack_kind(), 0.09, 0.07, 0.2)
	_kb_velocity -= dir * 45.0
	Fx.play("shoot" if GameState.active_class == "bowman" else "magic")


func _spawn_projectile(dir: Vector2, dmg: float, speed: float, proj_range: float, color: Color, pierce: int = 0) -> void:
	var projectile := PROJECTILE_SCENE.instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.launch(global_position + CHEST + dir * 16.0, dir, dmg, speed, proj_range, color, false, pierce)


func _damage_enemies_in_radius(center: Vector2, radius: float, dmg: float, knock: float, stun_time: float = 0.0) -> int:
	var count := 0
	for e: Node2D in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var to: Vector2 = e.global_position - center
		if to.length() <= radius + float(e.hit_radius):
			e.take_damage(dmg, to.normalized() if to.length() > 1.0 else Vector2.RIGHT, knock, false)
			if stun_time > 0.0:
				e.stun(stun_time)
			count += 1
	return count


func _use_special() -> void:
	var sp: Dictionary = GameState.class_defs.get(GameState.active_class, {}).get("special", {})
	if sp.is_empty():
		return
	if _special_cd > 0.0:
		Fx.floating_text(global_position + Vector2(0, -44), "%.1fs" % _special_cd, Color(0.7, 0.7, 0.7))
		return
	_special_cd = float(sp.get("cooldown", 8.0))
	EventBus.special_used.emit(_special_cd)
	var base: float = float(GameState.get_active_combat_stats().get("attack_damage", 10)) * GameState.get_level_damage_multiplier()
	var dmg: float = base * float(sp.get("damage_mult", 1.0))
	var center: Vector2 = global_position + CHEST
	Fx.play("special")
	match str(sp.get("kind", "")):
		"whirlwind":
			var radius: float = float(sp.get("radius", 90))
			_sweep_weapon(0.0, TAU * 1.5, 0.28)
			Fx.ring(center, radius, Color(0.85, 0.92, 1.0, 0.9))
			Fx.burst(center, Color(0.85, 0.92, 1.0), 14, 130.0, 0.4)
			Fx.shake(6.0, 0.22)
			if _damage_enemies_in_radius(global_position, radius, dmg, float(sp.get("knockback", 300))) > 0:
				Fx.hit_stop(0.06)
			_iframes = maxf(_iframes, 0.2)
		"volley":
			var count: int = int(sp.get("count", 7))
			var spread: float = deg_to_rad(float(sp.get("spread_deg", 50)))
			var dir: Vector2 = _aim_dir(ASSIST_RANGE, 0.5)
			_facing = dir
			var stats: Dictionary = GameState.get_active_combat_stats()
			var ca: Array = stats.get("projectile_color", [1, 1, 1, 1])
			var col := Color(ca[0], ca[1], ca[2], 1.0)
			for i in count:
				var a: float = lerpf(-spread * 0.5, spread * 0.5, float(i) / float(maxi(count - 1, 1)))
				_spawn_projectile(dir.rotated(a), dmg, float(stats.get("projectile_speed", 400)) * 1.1, float(stats.get("projectile_range", 340)), col, 1)
			Anim.start_attack(_anim, "bow", 0.1, 0.07, 0.25)
			Fx.shake(3.0, 0.15)
		"nova":
			Anim.start_attack(_anim, "staff", 0.12, 0.1, 0.3)
			var nr: float = float(sp.get("radius", 125))
			Fx.ring(center, nr, Color(0.5, 0.7, 1.0, 0.95), 0.45)
			Fx.ring(center, nr * 0.6, Color(0.8, 0.9, 1.0, 0.8), 0.3)
			Fx.burst(center, Color(0.55, 0.75, 1.0), 20, 150.0, 0.5)
			Fx.shake(7.0, 0.25)
			if _damage_enemies_in_radius(global_position, nr, dmg, float(sp.get("knockback", 400)), float(sp.get("stun", 1.0))) > 0:
				Fx.hit_stop(0.06)
			_iframes = maxf(_iframes, 0.25)
		"shadowstep":
			var dist: float = float(sp.get("distance", 150))
			var sdir: Vector2 = _facing
			Fx.burst(global_position + CHEST, Color(0.4, 0.3, 0.6), 12, 90.0, 0.4)
			_dodge_dir = sdir
			_dash_speed = dist / (DODGE_TIME * 0.775)
			_dodge_time = DODGE_TIME
			_iframes = 0.4
			_crit_ready = float(sp.get("crit_window", 3.0))
			Fx.floating_text(global_position + Vector2(0, -44), "Next hit crits!", Color(0.8, 0.6, 1.0))
		"firebomb":
			var range_px: float = float(sp.get("range", 150))
			var fdir: Vector2 = _aim_dir(range_px + 80.0, 0.4)
			_facing = fdir
			var target: Vector2 = global_position + fdir * range_px
			for e: Node2D in get_tree().get_nodes_in_group("enemies"):
				if is_instance_valid(e) and e.global_position.distance_to(global_position + fdir * range_px) < 70.0:
					target = e.global_position
					break
			var fr: float = float(sp.get("radius", 80))
			Anim.start_attack(_anim, "flask", 0.14, 0.1, 0.3)
			Fx.ring(target, fr, Color(1.0, 0.5, 0.15, 0.6), float(sp.get("delay", 0.35)))
			await get_tree().create_timer(float(sp.get("delay", 0.35))).timeout
			Fx.play("crit", 0.7)
			Fx.ring(target, fr, Color(1.0, 0.6, 0.2, 1.0), 0.4)
			Fx.burst(target, Color(1.0, 0.5, 0.15), 22, 160.0, 0.5)
			Fx.shake(6.0, 0.22)
			_damage_enemies_in_radius(target, fr, dmg, 260.0)


func _quick_eat() -> void:
	var eaten: String = GameState.eat_best_food()
	if eaten == "":
		EventBus.toast_requested.emit("Nothing to eat (or already full).", Color(0.85, 0.7, 0.6))
		return
	Fx.play("eat")
	var def: Dictionary = GameState.get_item_def(eaten)
	var msg := "Ate %s" % GameState.get_item_name(eaten)
	var hp_gain: int = int(def.get("hp", 0))
	if hp_gain > 0:
		msg += "  (+%d HP)" % hp_gain
	Fx.floating_text(global_position + Vector2(0, -44), msg, Color(0.6, 1.0, 0.6))


func _start_dodge(dir: Vector2) -> void:
	_dodge_dir = dir.normalized()
	_dash_speed = 380.0
	_dodge_time = DODGE_TIME
	_dodge_cd = DODGE_COOLDOWN
	_iframes = maxf(_iframes, DODGE_TIME + 0.1)
	Fx.play("dodge")
	Fx.burst(global_position + Vector2(0, -2), Color(0.75, 0.68, 0.5, 0.8), 6, 60.0, 0.35)


## Called by enemies. Armor mitigation is applied inside GameState.take_damage.
func take_damage(amount: float, from_dir: Vector2 = Vector2.ZERO, _knock: float = 0.0, _crit: bool = false) -> void:
	if GameState.is_dead() or _iframes > 0.0:
		return
	var dealt: float = GameState.take_damage(amount)
	_iframes = IFRAME_AFTER_HIT
	_kb_velocity += from_dir * 190.0
	_flash(Color(1.6, 0.4, 0.4))
	Anim.hurt(_anim, from_dir)
	Fx.damage_number(global_position + Vector2(0, -38), dealt, Color(1.0, 0.35, 0.3), false)
	Fx.play("hurt")
	Fx.shake(5.0, 0.2)
	Fx.burst(global_position + CHEST, Color(0.85, 0.15, 0.15), 6, 80.0, 0.35)


# ---------------------------------------------------------------------------
# Interaction
# ---------------------------------------------------------------------------

func _update_interaction() -> void:
	var best: Node2D = null
	var best_d := INF
	for n: Node2D in get_tree().get_nodes_in_group("interactable"):
		if not is_instance_valid(n) or not n.can_interact():
			continue
		var d: float = global_position.distance_to(n.global_position)
		if d <= float(n.interact_range) and d < best_d:
			best_d = d
			best = n
	_interact_target = best
	var prompt: String = best.get_prompt() if best != null else ""
	if prompt != _last_prompt:
		_last_prompt = prompt
		EventBus.interact_prompt_changed.emit(prompt)
	if best != null and Input.is_action_just_pressed("interact"):
		best.interact(self)


# ---------------------------------------------------------------------------
# Life cycle
# ---------------------------------------------------------------------------

func _on_class_changed(_new_class: String) -> void:
	_rebuild_visuals()
	Fx.burst(global_position + CHEST, Color(1, 1, 1, 0.9), 14, 90.0, 0.4)
	Fx.play("special", 1.4, -6.0)
	_combo = 0


func _on_level_up(class_id: String, new_level: int) -> void:
	Fx.play("level_up")
	Fx.ring(global_position, 60.0, Color(1.0, 0.9, 0.3, 1.0), 0.6)
	Fx.burst(global_position + CHEST, Color(1.0, 0.9, 0.3), 18, 140.0, 0.7)
	if class_id == GameState.active_class:
		Fx.floating_text(global_position + Vector2(0, -50), "LEVEL UP!", Color(1.0, 0.9, 0.3))
	var cname: String = GameState.class_defs.get(class_id, {}).get("display_name", class_id)
	EventBus.toast_requested.emit("%s reached level %d!" % [cname, new_level], Color(1.0, 0.9, 0.3))


func _on_vitals_changed() -> void:
	if GameState.is_dead() and not _dead_handled:
		_dead_handled = true
		respawn_timer.start(RESPAWN_DELAY)
		EventBus.player_died.emit()
		Fx.play("death")
		if not _parts.is_empty():
			var root: Node2D = _parts["root"]
			var tween := create_tween()
			tween.set_parallel(true)
			tween.tween_property(root, "rotation", PI * 0.5, 0.35)
			tween.tween_property(root, "modulate:a", 0.4, 0.5)


func set_respawn(pos: Vector2) -> void:
	_spawn_position = pos


func _on_respawn_timer_timeout() -> void:
	GameState.hp = GameState.max_hp
	GameState.hunger = max(GameState.hunger, 50.0)
	_dead_handled = false
	_iframes = 1.5
	global_position = _spawn_position
	_kb_velocity = Vector2.ZERO
	if not _parts.is_empty():
		var root: Node2D = _parts["root"]
		root.rotation = 0.0
		root.modulate = Color.WHITE
	EventBus.vitals_changed.emit()
	EventBus.player_respawned.emit()
