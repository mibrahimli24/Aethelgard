extends Node2D
## Villager. Built from Art.humanoid keyed by npc_id, stands behind a small collider, turns to
## look at the player when near, and shows a bobbing "!" while the active quest wants the
## player to talk to them (quests.json stage field "marker_npc"). Conversation itself lives in
## GameMaster; this only raises EventBus.dialogue_requested.

const Art = preload("res://scripts/Art.gd")
const Anim = preload("res://scripts/Anim.gd")

const LOOKS := {
	"mira_thistlewood": {"tunic": Color(0.5, 0.72, 0.4), "pants": Color(0.4, 0.3, 0.2), "hat": "hood", "hat_color": Color(0.33, 0.52, 0.3), "weapon": "crook", "hair": Color(0.8, 0.8, 0.82), "cape": Color(0.3, 0.5, 0.28)},
	"garrick_hale": {"tunic": Color(0.5, 0.4, 0.3), "pants": Color(0.26, 0.22, 0.18), "hat": "cap", "hat_color": Color(0.35, 0.26, 0.16), "weapon": "axe", "hair": Color(0.3, 0.2, 0.12), "scale": 1.06},
	"old_ferris": {"tunic": Color(0.55, 0.55, 0.6), "pants": Color(0.25, 0.22, 0.2), "hat": "none", "weapon": "hammer", "hair": Color(0.85, 0.85, 0.85), "scale": 1.04},
	"pip_wren": {"tunic": Color(0.75, 0.55, 0.3), "pants": Color(0.35, 0.28, 0.2), "hat": "cap", "hat_color": Color(0.55, 0.35, 0.2), "hair": Color(0.7, 0.45, 0.2), "scale": 0.86},
	"reeve_corwin_ashby": {"tunic": Color(0.5, 0.2, 0.25), "pants": Color(0.25, 0.2, 0.2), "hat": "cap", "hat_color": Color(0.3, 0.14, 0.18), "hair": Color(0.5, 0.5, 0.5), "weapon": "staff", "cape": Color(0.4, 0.14, 0.18), "scale": 1.05},
	"bess_hartwell": {"tunic": Color(0.7, 0.4, 0.3), "pants": Color(0.4, 0.28, 0.2), "hat": "none", "hair": Color(0.55, 0.28, 0.15)},
	"lark_the_bard": {"tunic": Color(0.3, 0.55, 0.65), "pants": Color(0.3, 0.25, 0.3), "hat": "bandana", "hat_color": Color(0.85, 0.7, 0.2), "hair": Color(0.9, 0.75, 0.4), "cape": Color(0.7, 0.3, 0.45)},
	"old_maud_fennick": {"tunic": Color(0.72, 0.62, 0.4), "pants": Color(0.4, 0.32, 0.22), "hat": "hood", "hat_color": Color(0.6, 0.5, 0.3), "hair": Color(0.85, 0.85, 0.85), "weapon": "crook", "scale": 0.94},
	"sylas_underbough": {"tunic": Color(0.28, 0.42, 0.28), "pants": Color(0.25, 0.22, 0.16), "hat": "hood", "hat_color": Color(0.2, 0.32, 0.2), "hair": Color(0.3, 0.22, 0.14), "weapon": "bow", "cape": Color(0.22, 0.34, 0.22)},
	"elowen_moonsong": {"tunic": Color(0.55, 0.6, 0.85), "pants": Color(0.35, 0.35, 0.55), "hat": "hood", "hat_color": Color(0.4, 0.45, 0.75), "hair": Color(0.88, 0.9, 0.98), "weapon": "staff", "cape": Color(0.4, 0.4, 0.75)},
	"captain_ysolde_varn": {"tunic": Color(0.3, 0.38, 0.55), "pants": Color(0.22, 0.24, 0.3), "hat": "helm", "hat_color": Color(0.6, 0.64, 0.7), "hair": Color(0.2, 0.15, 0.12), "weapon": "sword", "cape": Color(0.2, 0.3, 0.55), "scale": 1.05},
	"brannoch_the_hermit": {"tunic": Color(0.5, 0.45, 0.4), "pants": Color(0.3, 0.26, 0.22), "hat": "hood", "hat_color": Color(0.42, 0.38, 0.34), "hair": Color(0.8, 0.8, 0.82), "weapon": "staff", "cape": Color(0.4, 0.36, 0.32)},
	"dorn_ashvale": {"tunic": Color(0.5, 0.42, 0.36), "pants": Color(0.22, 0.2, 0.2), "hat": "none", "hair": Color(0.45, 0.25, 0.12), "weapon": "hammer", "scale": 1.1},
	"hilde_coppergate": {"tunic": Color(0.6, 0.45, 0.3), "pants": Color(0.28, 0.24, 0.22), "hat": "helm", "hat_color": Color(0.7, 0.55, 0.25), "hair": Color(0.6, 0.3, 0.15), "weapon": "hammer", "scale": 0.98},
	"zahra_qasim": {"tunic": Color(0.8, 0.35, 0.3), "pants": Color(0.7, 0.55, 0.3), "hat": "bandana", "hat_color": Color(0.9, 0.75, 0.3), "hair": Color(0.12, 0.08, 0.08), "cape": Color(0.85, 0.6, 0.25)},
	"tamsin_the_well_keeper": {"tunic": Color(0.3, 0.6, 0.6), "pants": Color(0.75, 0.65, 0.45), "hat": "hood", "hat_color": Color(0.25, 0.5, 0.52), "hair": Color(0.85, 0.85, 0.88), "weapon": "crook", "scale": 0.94},
	"odo_saltmarsh": {"tunic": Color(0.25, 0.3, 0.45), "pants": Color(0.22, 0.22, 0.28), "hat": "cap", "hat_color": Color(0.2, 0.24, 0.36), "hair": Color(0.75, 0.75, 0.78), "scale": 1.02},
	"nell_tidewater": {"tunic": Color(0.4, 0.55, 0.62), "pants": Color(0.35, 0.3, 0.25), "hat": "bandana", "hat_color": Color(0.8, 0.8, 0.85), "hair": Color(0.5, 0.35, 0.25)},
	"marrow_vane": {"tunic": Color(0.3, 0.2, 0.38), "pants": Color(0.2, 0.16, 0.24), "hat": "pointy", "hat_color": Color(0.24, 0.16, 0.3), "hair": Color(0.5, 0.55, 0.5), "weapon": "flask", "cape": Color(0.28, 0.22, 0.34)},
	"brother_alder": {"tunic": Color(0.55, 0.5, 0.42), "pants": Color(0.35, 0.3, 0.25), "hat": "hood", "hat_color": Color(0.5, 0.45, 0.38), "hair": Color(0.8, 0.8, 0.8), "weapon": "staff", "cape": Color(0.5, 0.44, 0.36)},
	"ignatius_vale": {"tunic": Color(0.6, 0.25, 0.15), "pants": Color(0.2, 0.18, 0.18), "hat": "pointy", "hat_color": Color(0.35, 0.12, 0.1), "hair": Color(0.18, 0.15, 0.15), "weapon": "flask", "cape": Color(0.45, 0.14, 0.1)},
}

@export var npc_id: String = ""
@export var display_name: String = ""
@export var body_color: Color = Color(0.6, 0.5, 0.2, 1)
@export var interact_range: float = 52.0

var _parts: Dictionary = {}
var _t := randf() * 6.0
var _marker: Node2D
var _name_label: Label
var _player: Node2D
var _anim: Dictionary = Anim.make_state()
var _work_in := randf_range(3.0, 8.0)
var _wkind := "none"
var _upright := false
var _face_x := 1.0
var _marker_bang: Node2D
var _marker_q: Node2D


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("npcs")
	var cfg: Dictionary = LOOKS.get(npc_id, {"tunic": body_color}).duplicate()
	_parts = Art.humanoid(self, cfg)
	var weapon: Node2D = _parts["weapon"]
	_wkind = str(cfg.get("weapon", "none"))
	_upright = _wkind in ["crook", "staff"]
	_apply_rest_weapon()

	var body := StaticBody2D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 7.0
	shape.shape = circle
	shape.position = Vector2(0, -5)
	body.add_child(shape)
	add_child(body)

	_name_label = Label.new()
	_name_label.text = display_name
	_name_label.custom_minimum_size = Vector2(140, 0)
	_name_label.size = Vector2(140, 16)
	_name_label.position = Vector2(-70, -64)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 11)
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_name_label.add_theme_constant_override("outline_size", 4)
	_name_label.modulate.a = 0.0
	_name_label.z_index = 40
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

	_marker = Node2D.new()
	_marker.position = Vector2(0, -56)
	_marker.z_index = 40
	add_child(_marker)
	_marker_bang = Node2D.new()
	_marker.add_child(_marker_bang)
	Art._poly(_marker_bang, Art.rect(-2, -10, 4, 8), Color(1.0, 0.85, 0.2))
	Art._poly(_marker_bang, Art.ellipse(2.2, 2.2, 8), Color(1.0, 0.85, 0.2), Vector2(0, 1.5))
	Art._poly(_marker_bang, Art.rect(-3.4, -11.5, 6.8, 12.5), Color(0.2, 0.12, 0.0, 0.7), Vector2.ZERO, -1)
	_marker_q = Node2D.new()
	_marker.add_child(_marker_q)
	var qc := Color(0.55, 0.85, 1.0)
	Art._poly(_marker_q, Art.ellipse(5.2, 5.2, 12), Color(0.05, 0.12, 0.2, 0.7), Vector2(0, -8), -1)
	var arc := Line2D.new()
	arc.width = 3.0
	arc.default_color = qc
	var pts := PackedVector2Array()
	for i in 9:
		var a: float = lerpf(-PI * 0.95, PI * 0.45, i / 8.0)
		pts.append(Vector2(cos(a) * 3.4, -9.0 + sin(a) * 3.4))
	pts.append(Vector2(0, -3.5))
	arc.points = pts
	_marker_q.add_child(arc)
	Art._poly(_marker_q, Art.ellipse(1.7, 1.7, 8), qc, Vector2(0, 1.5))
	_marker.visible = false

	EventBus.quest_updated.connect(func(_q, _s, _o): _refresh_marker())
	EventBus.inventory_changed.connect(_refresh_marker)
	_refresh_marker()


func _refresh_marker() -> void:
	var m: String = GameState.get_npc_marker(npc_id)
	_marker.visible = m != ""
	_marker_q.visible = m == "?"
	_marker_bang.visible = m == "!"


func _apply_rest_weapon() -> void:
	var weapon: Node2D = _parts["weapon"]
	weapon.position = Vector2(11, -13)
	weapon.rotation = -PI * 0.5 if _upright else 1.75


func _process(delta: float) -> void:
	_t += delta
	_marker.position.y = -56.0 + sin(_t * 4.0) * 2.5
	_marker.scale = Vector2.ONE * (1.0 + 0.06 * sin(_t * 4.0))
	var to := Vector2(0, 1)
	var near := false
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	else:
		to = _player.global_position - global_position
		near = to.length() < 130.0
		_name_label.modulate.a = move_toward(_name_label.modulate.a, 1.0 if near else 0.0, delta * 4.0)
	if near and absf(to.x) > 8.0:
		_face_x = 1.0 if to.x >= 0.0 else -1.0
		_parts["root"].scale.x = absf(_parts["root"].scale.x) * _face_x
	var working: bool = Anim.attacking(_anim)
	if not near and _wkind in ["hammer", "axe", "dagger"]:
		_work_in -= delta
		if _work_in <= 0.0 and not working:
			Anim.start_attack(_anim, _wkind, 0.28, 0.1, 0.4, 1.0)
			_work_in = randf_range(1.6, 3.2) if randf() < 0.55 else randf_range(5.0, 9.0)
	Anim.update_humanoid(_parts, _anim, delta, Vector2.ZERO, Vector2(1, 0.25), {"weapon": working, "dust": false})
	if not working:
		_apply_rest_weapon()
	if near:
		var look: Vector2 = Vector2(to.x * _face_x, to.y).normalized()
		_parts["eyes"].position = Vector2(look.x * 2.0, look.y * 1.3)


func can_interact() -> bool:
	return true


func get_prompt() -> String:
	return "E   Talk to %s" % display_name


func interact(_player_node: Node) -> void:
	Fx.play("click")
	EventBus.dialogue_requested.emit(npc_id, display_name)
