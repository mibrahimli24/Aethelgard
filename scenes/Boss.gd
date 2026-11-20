extends "res://scenes/Enemy.gd"
## Skar, Beastmaster of the Red Fang Clan -- the Whispering Glades boss. Reuses the base Enemy
## state machine (melee lunges + charge rush) and adds: "Bloodstone Frenzy" (telegraphed ground
## slam AoE), and a phase change at 50% HP where he roars, calls two Dire Wolves, and fights
## faster. HUD boss bar is driven by EventBus boss_* signals.

@export var frenzy_cooldown: float = 5.0
@export var frenzy_damage: float = 30.0
@export var frenzy_radius: float = 90.0
@export var frenzy_telegraph_time: float = 0.8
@export var charge_cooldown: float = 7.0

var _frenzy_cd := 2.5
var _charge_cd := 4.0
var _phase2 := false
var _frenzy_ring: Polygon2D


func _ready() -> void:
	is_boss = true
	enemy_id = "skar"
	super._ready()
	knockback_resist = 0.85


func _special_ai(delta: float, _player: Node2D, dist: float, dir_to_player: Vector2) -> bool:
	_frenzy_cd -= delta
	_charge_cd -= delta
	if _frenzy_cd <= 0.0 and dist <= frenzy_radius + 25.0:
		_frenzy_cd = frenzy_cooldown * (0.7 if _phase2 else 1.0)
		_begin_windup(dir_to_player, "frenzy", frenzy_telegraph_time)
		return true
	if _charge_cd <= 0.0 and dist >= 110.0 and dist <= 280.0:
		_charge_cd = charge_cooldown * (0.7 if _phase2 else 1.0)
		_begin_windup(dir_to_player, "charge", 0.65)
		return true
	return false


func _on_windup_start(kind: String) -> void:
	if kind != "frenzy":
		return
	_frenzy_ring = Art._poly(self, Art.ellipse(frenzy_radius, frenzy_radius * 0.75, 28), Color(1.0, 0.1, 0.05, 0.22), Vector2.ZERO, -2)
	var tween := _frenzy_ring.create_tween()
	tween.tween_property(_frenzy_ring, "color:a", 0.5, frenzy_telegraph_time)
	Fx.play("roar", 1.0)


func _strike_custom(kind: String, player: Node2D) -> bool:
	if _frenzy_ring != null:
		_frenzy_ring.queue_free()
		_frenzy_ring = null
	if kind != "frenzy":
		return false
	Fx.ring(global_position, frenzy_radius, Color(1.0, 0.3, 0.15, 1.0), 0.4)
	Fx.burst(global_position + Vector2(0, -6), Color(0.7, 0.55, 0.35), 20, 160.0, 0.5)
	Fx.shake(8.0, 0.3)
	Fx.play("crit", 0.5)
	if _player_alive(player) and global_position.distance_to(player.global_position) <= frenzy_radius + 6.0:
		player.take_damage(frenzy_damage * (1.0 + (power - 1.0) * 0.6), (player.global_position - global_position).normalized(), 400.0)
	_attack_cd = attack_cooldown
	_enter(S.RECOVER, 0.7)
	return true


func _on_engaged() -> void:
	EventBus.boss_engaged.emit(display_name, max_hp)
	EventBus.boss_hp_changed.emit(hp, max_hp)
	Fx.play("roar", 0.8)
	Fx.shake(4.0, 0.3)


func _on_damaged() -> void:
	if not _phase2 and hp > 0.0 and hp <= max_hp * 0.5:
		_start_phase_two()


func _start_phase_two() -> void:
	_phase2 = true
	move_speed *= 1.2
	attack_cooldown *= 0.75
	_alert.visible = false
	_tele_line.visible = false
	if _frenzy_ring != null:
		_frenzy_ring.queue_free()
		_frenzy_ring = null
	_enter(S.RECOVER, 1.1)
	Fx.play("roar", 0.7)
	Fx.shake(9.0, 0.5)
	Fx.ring(global_position, 150.0, Color(1.0, 0.2, 0.1, 1.0), 0.6)
	EventBus.toast_requested.emit("Skar bellows -- his hounds answer!", Color(1.0, 0.5, 0.3))
	var wolf_scene: PackedScene = load("res://scenes/Enemy.tscn")
	for off: Vector2 in [Vector2(-70, 25), Vector2(70, 25)]:
		var wolf := wolf_scene.instantiate()
		wolf.enemy_id = "dire_wolf"
		wolf.global_position = global_position + off
		get_parent().add_child(wolf)
		Fx.burst(wolf.global_position + Vector2(0, -8), Color(0.5, 0.5, 0.55), 10, 80.0, 0.4)


func _on_death() -> void:
	if _frenzy_ring != null:
		_frenzy_ring.queue_free()
	EventBus.boss_defeated.emit()
	Fx.play("victory")
	Fx.shake(10.0, 0.5)
	Fx.hit_stop(0.12)
	EventBus.toast_requested.emit("Skar the Beastmaster is defeated!", Color(1.0, 0.85, 0.3))
	for e: Node in get_tree().get_nodes_in_group("enemies"):
		if e != self and is_instance_valid(e) and e.get("enemy_id") == "dire_wolf" and e.get("_state") != S.DEAD:
			e.take_damage(9999.0, Vector2.ZERO, 0.0, false)
