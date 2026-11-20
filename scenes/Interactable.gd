extends Node2D
## World interactables that aren't people: forageable patches, campfires (cook / rest), waystones
## (heal + set respawn), and one-time loot chests. Joins the "interactable" group; Player picks the
## nearest one in range and calls interact(). Origin is at the prop's feet.

const Art = preload("res://scripts/Art.gd")

const FORAGE_QTY := {"berries": [2, 4], "mushroom": [1, 2], "healing_herb": [1, 2], "copper_ore": [1, 2], "oak_wood": [1, 3],
	"iron_ore": [1, 3], "coal": [1, 3], "sulfur": [1, 2], "obsidian_shard": [1, 2], "amber": [1, 1], "pine_resin": [1, 3],
	"sea_kelp": [2, 4], "pearl_shell": [1, 1], "cactus_fruit": [2, 3], "sun_date": [2, 4], "honeycomb": [1, 1]}
const RESPAWN_SEC := 120.0

@export_enum("forage", "campfire", "waystone", "chest") var kind: String = "forage"
@export var item_id: String = "berries"
@export var interact_range: float = 38.0
## Chest contents, "item:count,item:count".
@export var loot: String = "cooked_meat:2,healing_herb:1"
@export var uid: String = ""

var _cooldown := 0.0
var _visual: Node2D
var _bounty: Node2D
var _flame: Node2D
var _light: PointLight2D
var _lid: Node2D
var _t := randf() * 10.0
var _sleeping := false


func _ready() -> void:
	add_to_group("interactable")
	match kind:
		"forage":
			_build_forage()
		"campfire":
			_build_campfire()
			interact_range = 46.0
		"waystone":
			_build_waystone()
			interact_range = 46.0
		"chest":
			_build_chest()
	if kind != "forage" and kind != "chest":
		var body := StaticBody2D.new()
		body.collision_layer = 4
		body.collision_mask = 0
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 9.0 if kind == "waystone" else 8.0
		shape.shape = circle
		shape.position = Vector2(0, -4)
		body.add_child(shape)
		add_child(body)


func _process(delta: float) -> void:
	_t += delta
	if _cooldown > 0.0:
		_cooldown -= delta
		if _cooldown <= 0.0 and kind == "forage":
			_set_ripe(true)
	match kind:
		"campfire":
			_flame.scale = Vector2(1.0 + 0.08 * sin(_t * 14.0), 1.0 + 0.16 * sin(_t * 9.0 + 1.0))
			_light.set_meta("base_energy", 0.9 + 0.12 * sin(_t * 11.0))
		"waystone":
			_light.set_meta("base_energy", 0.7 + 0.25 * sin(_t * 2.0))
		"forage":
			if item_id == "healing_herb" and _light != null:
				_light.set_meta("base_energy", 0.55 + 0.2 * sin(_t * 3.0))


# ---------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------

func _build_forage() -> void:
	_visual = Node2D.new()
	add_child(_visual)
	_bounty = Node2D.new()
	match item_id:
		"berries":
			Art.bush(_visual, 1.0, 1.0)
			for p: Vector2 in [Vector2(-8, -8), Vector2(2, -14), Vector2(9, -8), Vector2(-2, -6), Vector2(6, -13)]:
				Art._poly(_bounty, Art.ellipse(1.9, 1.9, 6), Color(0.62, 0.18, 0.7), p)
		"mushroom":
			for p: Vector2 in [Vector2(-8, 0), Vector2(0, 2), Vector2(8, -1)]:
				var m := Node2D.new()
				m.position = p
				_visual.add_child(m)
				Art._poly(m, Art.rect(-1.3, -6, 2.6, 6), Color(0.9, 0.85, 0.75))
				Art._poly(m, Art.ellipse(5, 3.2, 10), Color(0.72, 0.5, 0.32), Vector2(0, -6), 1)
			Art.shadow(_visual, 13, 4, 0.22)
			Art._poly(_bounty, Art.ellipse(1, 1, 5), Color(1, 1, 0.9), Vector2(-9, -8))
		"healing_herb":
			for p: Vector2 in [Vector2(-6, 0), Vector2(0, 1), Vector2(6, 0), Vector2(-2, -1)]:
				var g := Node2D.new()
				g.position = p
				_visual.add_child(g)
				Art._poly(g, Art.tri(Vector2(-1.2, 0), Vector2(0, -12), Vector2(1.2, 0)), Color(0.35, 0.8, 0.4))
				Art._poly(g, Art.ellipse(3.2, 1.6, 8), Color(0.45, 0.9, 0.5), Vector2(3, -7), 1)
				Art._poly(g, Art.ellipse(3.2, 1.6, 8), Color(0.4, 0.85, 0.45), Vector2(-3, -5), 1)
			Art._poly(_bounty, Art.ellipse(2, 2, 6), Color(0.85, 1.0, 0.7, 0.9), Vector2(0, -13))
			_light = Fx.make_light(60.0, Color(0.5, 1.0, 0.6), 0.6)
			_light.position = Vector2(0, -8)
			add_child(_light)
		"copper_ore":
			Art.rock(_visual, 0.85, 0.95)
			for p: Vector2 in [Vector2(-5, -8), Vector2(4, -12), Vector2(7, -5)]:
				Art._poly(_bounty, Art.ellipse(2.2, 1.8, 6), Color(0.82, 0.48, 0.25), p)
		"oak_wood":
			Art.shadow(_visual, 12, 4, 0.25)
			for i in 3:
				var l := Line2D.new()
				l.points = PackedVector2Array([Vector2(-10, -3 - i * 4), Vector2(10, -3 - i * 4 + (i - 1) * 1.5)])
				l.width = 5.0
				l.default_color = Color(0.45, 0.3, 0.16).lightened(0.05 * i)
				_visual.add_child(l)
			Art._poly(_bounty, Art.ellipse(2.5, 2.5, 6), Color(0.7, 0.5, 0.3), Vector2(10, -6))
		_:
			_build_generic_forage()
	add_child(_bounty)


func _build_generic_forage() -> void:
	var col: Color = GameState.get_item_color(item_id)
	match item_id:
		"iron_ore", "coal", "sulfur", "obsidian_shard", "amber":
			Art.rock(_visual, 0.8, 0.95)
			for p: Vector2 in [Vector2(-5, -8), Vector2(4, -12), Vector2(7, -5), Vector2(-1, -4)]:
				Art._poly(_bounty, Art.ellipse(2.4, 2.0, 6), col, p)
				Art._poly(_bounty, Art.ellipse(0.9, 0.9, 4), col.lightened(0.5), p + Vector2(-0.8, -0.8))
		"sea_kelp":
			Art.shadow(_visual, 12, 4, 0.2)
			for p: Vector2 in [Vector2(-7, 0), Vector2(0, 1), Vector2(7, 0)]:
				var l := Line2D.new()
				l.points = PackedVector2Array([p, p + Vector2(2, -7), p + Vector2(-2, -13), p + Vector2(1, -18)])
				l.width = 3.0
				l.default_color = col
				_visual.add_child(l)
			Art._poly(_bounty, Art.ellipse(2, 2, 6), col.lightened(0.3), Vector2(1, -18))
		"pearl_shell":
			Art.shadow(_visual, 10, 3, 0.2)
			Art._poly(_visual, Art.ellipse(7, 4.5, 10), Color(0.75, 0.7, 0.72), Vector2(0, -3), 1)
			Art._poly(_visual, Art.ellipse(4.5, 3, 10), Color(0.6, 0.55, 0.6), Vector2(0, -3), 1)
			Art._poly(_bounty, Art.ellipse(2.2, 2.2, 8), col, Vector2(0, -5))
		"pine_resin":
			Art.shadow(_visual, 10, 3, 0.2)
			Art._poly(_visual, Art.rect(-2.5, -20, 5, 20), Color(0.36, 0.25, 0.16))
			Art._poly(_visual, Art.ellipse(7, 4, 8), Color(0.2, 0.4, 0.25), Vector2(0, -20), 1)
			for p: Vector2 in [Vector2(-1, -12), Vector2(1, -7)]:
				Art._poly(_bounty, Art.ellipse(1.6, 2.4, 6), col, p)
		"honeycomb":
			Art.shadow(_visual, 10, 3, 0.2)
			Art._poly(_visual, Art.rect(-6, -14, 12, 14), Color(0.45, 0.32, 0.18))
			Art._poly(_bounty, Art.ellipse(5, 4, 6), col, Vector2(0, -16))
			Art._poly(_bounty, Art.ellipse(1.5, 1.5, 5), col.darkened(0.3), Vector2(-2, -16))
		"cactus_fruit", "sun_date":
			var body_col := Color(0.28, 0.5, 0.3) if item_id == "cactus_fruit" else Color(0.4, 0.28, 0.16)
			Art.shadow(_visual, 10, 3, 0.25)
			Art._poly(_visual, Art.rect(-3, -20, 6, 20), body_col)
			Art._poly(_visual, Art.rect(-9, -13, 3, 8), body_col)
			Art._poly(_visual, Art.rect(6, -16, 3, 9), body_col)
			for p: Vector2 in [Vector2(-7, -15), Vector2(7, -18), Vector2(0, -22)]:
				Art._poly(_bounty, Art.ellipse(2.2, 2.2, 6), col, p)
		_:
			Art.shadow(_visual, 12, 4, 0.2)
			for p: Vector2 in [Vector2(-6, 0), Vector2(0, 1), Vector2(6, 0)]:
				Art._poly(_visual, Art.tri(Vector2(-1.2, 0), Vector2(0, -10), Vector2(1.2, 0)), Color(0.3, 0.5, 0.35), p)
			for p: Vector2 in [Vector2(-6, -11), Vector2(0, -13), Vector2(6, -11)]:
				Art._poly(_bounty, Art.ellipse(3, 3, 7), col, p)
				Art._poly(_bounty, Art.ellipse(1.1, 1.1, 5), col.lightened(0.6), p)
			if item_id in ["glowcap", "frost_bloom", "bog_lily"]:
				_light = Fx.make_light(54.0, col, 0.5)
				_light.position = Vector2(0, -8)
				add_child(_light)


func _set_ripe(ripe: bool) -> void:
	_bounty.visible = ripe
	_visual.modulate = Color.WHITE if ripe else Color(0.6, 0.6, 0.6)
	if _light != null:
		_light.visible = ripe


func _build_campfire() -> void:
	var parts: Dictionary = Art.campfire(self)
	_visual = parts["root"]
	_flame = parts["flame"]
	_light = Fx.make_light(190.0, Color(1.0, 0.65, 0.3), 0.9)
	_light.position = Vector2(0, -8)
	add_child(_light)


func _build_waystone() -> void:
	_visual = Art.waystone(self)
	_light = Fx.make_light(110.0, Color(0.5, 0.85, 1.0), 0.8)
	_light.position = Vector2(0, -20)
	add_child(_light)
	if uid != "" and GameState.has_story_flag("waystone_" + uid):
		_visual.modulate = Color(1.2, 1.3, 1.4)


func _build_chest() -> void:
	var parts: Dictionary = Art.crate_chest(self)
	_visual = parts["root"]
	_lid = parts["lid"]
	if _is_opened():
		_lid.rotation = -1.1


func _is_opened() -> bool:
	return uid != "" and GameState.has_story_flag("chest_" + uid)


# ---------------------------------------------------------------------------
# Interaction
# ---------------------------------------------------------------------------

func can_interact() -> bool:
	if _sleeping:
		return false
	match kind:
		"forage":
			return _cooldown <= 0.0
		"chest":
			return not _is_opened()
	return true


func get_prompt() -> String:
	match kind:
		"forage":
			return "E   Gather %s" % GameState.get_item_name(item_id)
		"campfire":
			if _cookable_count() > 0:
				return "E   Cook food"
			if GameState.get_darkness() > 0.5:
				return "E   Rest until morning"
			return "E   Warm yourself"
		"waystone":
			return "E   Touch the waystone"
		"chest":
			return "E   Open chest"
	return ""


func interact(player: Node) -> void:
	match kind:
		"forage":
			_do_forage()
		"campfire":
			_do_campfire()
		"waystone":
			_do_waystone(player)
		"chest":
			_do_chest()


func _do_forage() -> void:
	var range_arr: Array = FORAGE_QTY.get(item_id, [1, 2])
	var qty: int = randi_range(int(range_arr[0]), int(range_arr[1]))
	GameState.add_item(item_id, qty)
	_cooldown = RESPAWN_SEC
	_set_ripe(false)
	Fx.play("pickup")
	Fx.floating_text(global_position + Vector2(0, -30), "+%d %s" % [qty, GameState.get_item_name(item_id)], GameState.get_item_color(item_id).lightened(0.3))
	Fx.burst(global_position + Vector2(0, -10), GameState.get_item_color(item_id), 8, 60.0, 0.4)


func _cookable_count() -> int:
	var n := 0
	for id in GameState.inventory.keys():
		if GameState.get_item_def(id).has("cookable_into"):
			n += int(GameState.inventory[id])
	return n


func _heal(amount: float) -> void:
	GameState.hp = minf(GameState.max_hp, GameState.hp + amount)
	EventBus.vitals_changed.emit()


func _do_campfire() -> void:
	var cooked := 0
	for id in GameState.inventory.keys().duplicate():
		var def: Dictionary = GameState.get_item_def(id)
		if not def.has("cookable_into"):
			continue
		var n: int = int(GameState.inventory[id])
		if GameState.remove_item(id, n):
			GameState.add_item(str(def["cookable_into"]), n)
			cooked += n
			Fx.floating_text(global_position + Vector2(0, -44 - 12 * cooked), "%d x %s" % [n, GameState.get_item_name(str(def["cookable_into"]))], GameState.get_item_color(str(def["cookable_into"])).lightened(0.3))
	if cooked > 0:
		Fx.play("eat", 1.3)
		Fx.burst(global_position + Vector2(0, -14), Color(1.0, 0.6, 0.2), 10, 60.0, 0.5)
		EventBus.toast_requested.emit("Cooked %d item%s over the fire." % [cooked, "" if cooked == 1 else "s"], Color(1.0, 0.8, 0.5))
		return
	if GameState.get_darkness() > 0.5:
		_sleep()
		return
	_heal(20.0)
	Fx.floating_text(global_position + Vector2(0, -44), "The fire warms you.", Color(1.0, 0.8, 0.5))


func _sleep() -> void:
	_sleeping = true
	var layer := CanvasLayer.new()
	layer.layer = 80
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var rect := ColorRect.new()
	rect.color = Color(0.02, 0.02, 0.05, 1.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate.a = 0.0
	layer.add_child(rect)
	get_tree().current_scene.add_child(layer)
	var tween := layer.create_tween()
	tween.tween_property(rect, "modulate:a", 1.0, 0.6)
	tween.tween_callback(func():
		GameState.world_time = 0.0
		GameState.hp = GameState.max_hp
		GameState.hunger = maxf(10.0, GameState.hunger - 12.0)
		EventBus.vitals_changed.emit()
		Fx.play("level_up", 0.7, -8.0))
	tween.tween_interval(0.5)
	tween.tween_property(rect, "modulate:a", 0.0, 0.9)
	tween.tween_callback(func():
		EventBus.toast_requested.emit("You wake at dawn, fully rested.", Color(1.0, 0.9, 0.6))
		_sleeping = false
		layer.queue_free())


func _do_waystone(player: Node) -> void:
	var first: bool = uid != "" and not GameState.has_story_flag("waystone_" + uid)
	if uid != "":
		GameState.set_story_flag("waystone_" + uid, true)
	GameState.hp = GameState.max_hp
	EventBus.vitals_changed.emit()
	if player.has_method("set_respawn"):
		player.set_respawn(global_position + Vector2(0, 18))
	_visual.modulate = Color(1.2, 1.3, 1.4)
	Fx.play("quest")
	Fx.ring(global_position + Vector2(0, -4), 60.0, Color(0.5, 0.9, 1.0, 1.0), 0.6)
	Fx.burst(global_position + Vector2(0, -20), Color(0.6, 0.9, 1.0), 14, 90.0, 0.7)
	EventBus.toast_requested.emit("Waystone attuned -- you will return here if you fall." if first else "The waystone restores you.", Color(0.6, 0.9, 1.0))


func _do_chest() -> void:
	if uid != "":
		GameState.set_story_flag("chest_" + uid, true)
	var tween := create_tween()
	tween.tween_property(_lid, "rotation", -1.1, 0.25)
	Fx.play("pickup", 0.8)
	var idx := 0
	for entry in loot.split(",", false):
		var bits: PackedStringArray = entry.split(":")
		var id: String = bits[0].strip_edges()
		var n: int = int(bits[1]) if bits.size() > 1 else 1
		GameState.add_item(id, n)
		Fx.floating_text(global_position + Vector2(0, -26 - 13 * idx), "+%d %s" % [n, GameState.get_item_name(id)], GameState.get_item_color(id).lightened(0.3))
		idx += 1
	Fx.burst(global_position + Vector2(0, -14), Color(1.0, 0.85, 0.3), 12, 90.0, 0.6)
