extends Node2D
## Ties the world together. This is the one node with real scene-tree access, so it realizes
## GameMaster's "physical" game_actions (spawn_camp, boss-fight stage) as spawned nodes.
## It builds the scenery (WorldDecor, streamed region by region around the player), places NPCs
## at their landmarks, runs the day/night cycle, keeps each region's wilds and landmark guards
## populated (scaled to the player's level), and animates fireflies.

const WorldDecor = preload("res://scripts/WorldDecor.gd")
const Art = preload("res://scripts/Art.gd")
const Regions = preload("res://scripts/Regions.gd")
const Biomes = preload("res://scripts/WorldBiomes.gd")
const Ambient = preload("res://scripts/Ambient.gd")
const Critter = preload("res://scenes/Critter.gd")
const ENEMY_SCENE := preload("res://scenes/Enemy.tscn")
const BOSS_SCENE := preload("res://scenes/Boss.tscn")
const NPC_SCENE := preload("res://scenes/NPC.tscn")
const INTERACTABLE_SCENE := preload("res://scenes/Interactable.tscn")
const BIOME_DATA_PATH := "res://data/biome_whispering_glades.json"

const DAY_COLOR := Color(1.0, 1.0, 1.0)
const DUSK_COLOR := Color(1.0, 0.72, 0.56)
const NIGHT_COLOR := Color(0.2, 0.25, 0.46)

const INITIAL_WILDS := [
	["dire_wolf", Vector2(750, 350)], ["dire_wolf", Vector2(900, 620)], ["dire_wolf", Vector2(650, 760)],
	["dire_wolf", Vector2(1000, 300)], ["dire_wolf", Vector2(1250, 470)], ["dire_wolf", Vector2(1250, 900)],
	["boar", Vector2(450, 720)], ["boar", Vector2(950, 760)], ["boar", Vector2(700, 150)], ["boar", Vector2(1150, 190)],
]
const WILD_TARGET := 11
const WISP_TARGET := 4
const STREAM_RANGE := 900.0

const REGION_WILDS := {
	"whispering_glades": [["dire_wolf", 3], ["boar", 2], ["wisp", 2]],
	"thornwood": [["shadow_wolf", 4], ["dire_wolf", 2], ["boar", 1], ["bone_soldier", 1], ["wisp", 2]],
	"hollow_peaks": [["snow_wolf", 4], ["frost_bear", 2], ["ice_wisp", 2]],
	"highmeadow": [["boar", 3], ["dire_wolf", 2], ["highway_bandit", 2]],
	"ironhold_hills": [["hill_brigand", 3], ["rock_golem", 2], ["dire_wolf", 1]],
	"sunscorch_dunes": [["dune_jackal", 4], ["giant_scorpion", 3], ["dust_wraith", 1]],
	"stormcoast": [["shore_crab", 4], ["drowned_sailor", 2], ["boar", 1], ["wisp", 1]],
	"gloomfen": [["bog_lurker", 3], ["bog_boar", 3], ["wisp", 3]],
	"ashen_wastes": [["cinder_hound", 3], ["ember_golem", 2], ["ash_wraith", 3], ["ashen_knight", 2]],
}

const GUARDS := {
	"bandit_lookout": [["highway_bandit", 4]],
	"slag_camp": [["hill_brigand", 4]],
	"smugglers_camp": [["highway_bandit", 4]],
	"legion_camp": [["ashen_knight", 3], ["ash_wraith", 2]],
	"spider_den": [["shadow_wolf", 3]],
	"rimefang_den": [["frost_bear", 2], ["snow_wolf", 2]],
	"scorpion_pit": [["giant_scorpion", 4]],
	"drowned_hollow": [["bog_lurker", 3]],
	"toad_mound": [["bog_boar", 3]],
	"dwarven_ruin": [["rock_golem", 2]],
	"hollow_ruins": [["bone_soldier", 4]],
	"sunken_chapel": [["bog_lurker", 3]],
	"cinder_ruins": [["ash_wraith", 2]],
	"ember_throne": [["ashen_knight", 2], ["ember_golem", 2]],
	"obsidian_spire": [["ash_wraith", 3]],
	"lava_fields": [["cinder_hound", 4]],
	"tidecaller_cave": [["shore_crab", 4]],
	"wreck_cove": [["drowned_sailor", 3]],
	"deepvein_mine": [["hill_brigand", 3], ["rock_golem", 1]],
}
const GUARD_RESPAWN := 180.0
const GUARD_NEAR := 1100.0
const GUARD_FAR := 2000.0

const NPC_OVERRIDES := {
	"mira_thistlewood": Vector2(250, 262),
	"garrick_hale": Vector2(550, 312),
	"old_ferris": Vector2(420, 492),
}
const FIREFLY_BIOMES := ["forest", "meadow", "swamp"]
const CRITTERS := {
	"forest": ["deer", "rabbit"], "meadow": ["deer", "rabbit", "rabbit"], "snow": ["rabbit"], "hills": ["rabbit"],
	"desert": ["lizard"], "coast": ["crab", "rabbit"], "swamp": ["frog"], "ash": [],
}

@onready var entities: Node2D = $Entities
@onready var ground: Node2D = $Ground
@onready var atmosphere: CanvasModulate = $Atmosphere

var decor: RefCounted
var _biome_data: Dictionary = {}
var _camp_revealed := false
var _camp_built := false
var _boss_spawned := false
var _spawn_cd := 5.0
var _stream_cd := 0.0
var _was_night := false
var _fireflies: Array = []
var _player: Node2D
var _region_id := ""
var _critter_regions: Dictionary = {}
var _guards: Dictionary = {}
var _time := 0.0


func _ready() -> void:
	_biome_data = _load_biome_data()
	Ambient.setup(self)
	decor = WorldDecor.new()
	decor.build(ground, entities)
	_player = get_tree().get_first_node_in_group("player") as Node2D
	var start := WorldDecor.PLAYER_START
	if _player != null:
		start = _player.global_position
	_region_id = Regions.region_id_at(start)
	decor.queue_region("whispering_glades")
	decor.queue_region(_region_id)
	decor.pump_all()
	_spawn_npcs()
	_build_fireflies()
	_spawn_critters("whispering_glades")
	if _region_id != "whispering_glades":
		_spawn_critters(_region_id)
	for entry: Array in INITIAL_WILDS:
		_spawn_wild(str(entry[0]), entry[1])
	if GameState.has_story_flag("camp_red_fang_camp_spawned"):
		_camp_revealed = true
		_build_camp(false)
		_spawn_remaining_bandits()
	EventBus.action_dispatched.connect(_on_action_dispatched)
	EventBus.quest_updated.connect(_on_quest_updated)
	if GameState.get_current_stage("whispers_in_the_glade").get("id", "") == "boss_fight":
		_spawn_boss()
	Ambient.set_biome_ambient(Biomes.ambient_kind(_region_id))
	_update_atmosphere(0.0)
	_was_night = GameState.get_darkness() > 0.6


func get_world_rect() -> Rect2:
	return Regions.world_rect()


func _process(delta: float) -> void:
	_time += delta
	var d: float = GameState.get_darkness()
	_update_atmosphere(d)
	var night: bool = d > 0.6
	if night != _was_night:
		_was_night = night
		if night:
			EventBus.toast_requested.emit("Night falls. Wisps drift out of the trees.", Color(0.6, 0.7, 1.0))
		else:
			EventBus.toast_requested.emit("Dawn breaks.", Color(1.0, 0.85, 0.5))
	_update_fireflies(delta, d)
	_pump_decor()
	_stream_cd -= delta
	if _stream_cd <= 0.0:
		_stream_cd = 0.5
		_stream_regions()
	_spawn_cd -= delta
	if _spawn_cd <= 0.0:
		_spawn_cd = 6.0
		_maintain_wilds(d)
		_maintain_guards()


func _update_atmosphere(d: float) -> void:
	if d < 0.5:
		atmosphere.color = DAY_COLOR.lerp(DUSK_COLOR, d * 2.0)
	else:
		atmosphere.color = DUSK_COLOR.lerp(NIGHT_COLOR, (d - 0.5) * 2.0)
	var k: float = clampf(d * 1.8, 0.0, 1.0)
	for l: Node in get_tree().get_nodes_in_group("night_lights"):
		if l is PointLight2D:
			l.energy = float(l.get_meta("base_energy", 1.0)) * k


# ---------------------------------------------------------------------------
# Region streaming
# ---------------------------------------------------------------------------

func _pump_decor() -> void:
	if decor.pending() <= 0:
		return
	var t0 := Time.get_ticks_usec()
	while decor.pending() > 0 and Time.get_ticks_usec() - t0 < 4000:
		decor.pump()


func _stream_regions() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
		return
	var pos: Vector2 = _player.global_position
	var here: String = Regions.region_id_at(pos)
	if here != "" and not decor.region_built(here):
		decor.queue_region(here)
		decor.pump_all()
	for reg: Dictionary in Regions.all():
		var rid: String = str(reg.get("id", ""))
		if not decor.region_built(rid) and Regions.rect_of(reg).grow(STREAM_RANGE).has_point(pos):
			decor.queue_region(rid)
	if here != "" and here != _region_id:
		_region_id = here
		Ambient.set_biome_ambient(Biomes.ambient_kind(here))
	for reg2: Dictionary in Regions.all():
		var rid2: String = str(reg2.get("id", ""))
		if decor.region_built(rid2) and not _critter_regions.has(rid2):
			_spawn_critters(rid2)


# ---------------------------------------------------------------------------
# NPCs
# ---------------------------------------------------------------------------

func _spawn_npcs() -> void:
	var used: Dictionary = {}
	for npc_id: String in GameMaster.npc_profiles.keys():
		var prof: Dictionary = GameMaster.npc_profiles[npc_id]
		var home: Dictionary = prof.get("home", {})
		var lm: Dictionary = Regions.get_landmark(str(home.get("landmark", "")))
		if lm.is_empty():
			continue
		var lid: String = str(lm.get("id", ""))
		var idx: int = int(used.get(lid, 0))
		used[lid] = idx + 1
		var spots: Array = lm.get("spots_v", [])
		var pos: Vector2
		if NPC_OVERRIDES.has(npc_id):
			pos = NPC_OVERRIDES[npc_id]
		elif idx < spots.size():
			pos = spots[idx]
		else:
			pos = (lm["pos_v"] as Vector2) + Vector2(60.0 * float(idx + 1), 40.0)
		var npc: Node2D = NPC_SCENE.instantiate()
		npc.npc_id = npc_id
		npc.display_name = str(prof.get("display_name", prof.get("name", npc_id)))
		npc.position = pos
		entities.add_child(npc)


# ---------------------------------------------------------------------------
# Fireflies / critters
# ---------------------------------------------------------------------------

func _build_fireflies() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var center := Vector2(600, 500)
	if _player != null:
		center = _player.global_position
	for i in 16:
		var anchor: Vector2 = center + Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(80.0, 600.0)
		var n := Node2D.new()
		n.position = anchor
		n.z_index = 20
		add_child(n)
		var dot := Art._poly(n, Art.ellipse(1.7, 1.7, 6), Color(1.0, 1.0, 0.55))
		var light := Fx.make_light(34.0, Color(0.95, 1.0, 0.5), 0.9)
		n.add_child(light)
		_fireflies.append({"node": n, "dot": dot, "light": light, "anchor": anchor, "phase": rng.randf() * TAU, "speed": rng.randf_range(0.5, 1.1)})


func _update_fireflies(delta: float, d: float) -> void:
	var active: bool = FIREFLY_BIOMES.has(Biomes.ambient_kind(_region_id)) and d > 0.25
	var ppos := Vector2.ZERO
	var have_player: bool = _player != null and is_instance_valid(_player)
	if have_player:
		ppos = _player.global_position
	for f: Dictionary in _fireflies:
		var n: Node2D = f["node"]
		n.visible = active
		if not active:
			continue
		f["phase"] += delta * f["speed"]
		if have_player and (f["anchor"] as Vector2).distance_to(ppos) > 700.0:
			var a: Vector2 = ppos + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(250.0, 600.0)
			if decor.in_water(a, 10.0) or decor.in_safe_zone(a, 0.0):
				continue
			f["anchor"] = a
		var ph: float = f["phase"]
		n.position = f["anchor"] + Vector2(sin(ph * 1.3) * 26.0, cos(ph * 0.9) * 18.0 - 14.0)
		var blink: float = 0.35 + 0.65 * absf(sin(ph * 2.2))
		f["dot"].color.a = blink
		f["light"].set_meta("base_energy", 0.9 * blink)


func _spawn_critters(rid: String) -> void:
	_critter_regions[rid] = true
	var kinds: Array = CRITTERS.get(Biomes.ambient_kind(rid), [])
	if kinds.is_empty():
		return
	var rect: Rect2 = Regions.rect_of(Regions.get_region(rid)).grow(-200)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(rid) + 501
	var placed := 0
	var tries := 0
	while placed < 8 and tries < 80:
		tries += 1
		var pos := Vector2(rng.randf_range(rect.position.x, rect.end.x), rng.randf_range(rect.position.y, rect.end.y))
		if rid == "whispering_glades" and (WorldDecor.RIDGE_RECT.has_point(pos) or pos.x > 1100.0):
			continue
		if decor.blocked(pos, 20.0) or not decor.is_free(pos, 14.0):
			continue
		var c := Critter.new()
		c.kind = str(kinds[rng.randi_range(0, kinds.size() - 1)])
		c.position = pos
		entities.add_child(c)
		placed += 1


# ---------------------------------------------------------------------------
# Enemy spawning
# ---------------------------------------------------------------------------

func _power() -> float:
	var lvl: int = maxi(1, GameState.get_class_level(GameState.active_class))
	return minf(2.0, 1.0 + 0.08 * float(lvl - 1))


func _spawn_enemy(id: String, pos: Vector2, scaled: bool = true) -> Node2D:
	var e: Node2D = ENEMY_SCENE.instantiate()
	e.enemy_id = id
	e.power = _power() if scaled else 1.0
	e.position = pos
	entities.add_child(e)
	return e


func _spawn_wild(id: String, pos: Vector2) -> void:
	var e := _spawn_enemy(id, pos)
	e.add_to_group("wild")


func _pick_weighted(table: Array, want_wisp: bool) -> String:
	var total := 0.0
	for e: Array in table:
		if str(e[0]).contains("wisp") == want_wisp:
			total += float(e[1])
	if total <= 0.0:
		return ""
	var x: float = randf() * total
	for e2: Array in table:
		if str(e2[0]).contains("wisp") != want_wisp:
			continue
		x -= float(e2[1])
		if x <= 0.0:
			return str(e2[0])
	return ""


func _maintain_wilds(d: float) -> void:
	if _player == null or not is_instance_valid(_player) or GameState.is_dead():
		return
	var ppos: Vector2 = _player.global_position
	var wisps := 0
	var ground_count := 0
	for e: Node in get_tree().get_nodes_in_group("wild"):
		var ne := e as Node2D
		if ne == null:
			continue
		var dist: float = ne.global_position.distance_to(ppos)
		if dist > 1700.0:
			ne.queue_free()
			continue
		if dist > 1300.0:
			continue
		if str(e.get("enemy_id")).contains("wisp"):
			wisps += 1
		else:
			ground_count += 1
	var table: Array = REGION_WILDS.get(Regions.region_id_at(ppos), [])
	if table.is_empty():
		return
	if d > 0.7 and wisps < WISP_TARGET:
		var wid: String = _pick_weighted(table, true)
		var wpos: Variant = _find_spawn_point(230.0, 420.0, 10.0)
		if wid != "" and wpos != null:
			_spawn_wild(wid, wpos)
	if ground_count < WILD_TARGET:
		var gid: String = _pick_weighted(table, false)
		var gpos: Variant = _find_spawn_point(380.0, 650.0, 16.0)
		if gid != "" and gpos != null:
			_spawn_wild(gid, gpos)


func _find_spawn_point(min_dist: float, max_dist: float, clearance: float) -> Variant:
	var wr: Rect2 = Regions.world_rect().grow(-90)
	for i in 14:
		var pos: Vector2 = _player.global_position + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(min_dist, max_dist)
		if not wr.has_point(pos):
			continue
		if decor.in_safe_zone(pos, 50.0) or decor.in_water(pos, 10.0) or pos.distance_to(WorldDecor.CAMP_POS) < 190.0:
			continue
		if decor.is_free(pos, clearance):
			return pos
	return null


func _maintain_guards() -> void:
	if _player == null or not is_instance_valid(_player) or GameState.is_dead():
		return
	var ppos: Vector2 = _player.global_position
	for lid: String in GUARDS.keys():
		var lm: Dictionary = Regions.get_landmark(lid)
		if lm.is_empty():
			continue
		var c: Vector2 = lm["pos_v"]
		var st: Dictionary = _guards.get(lid, {"nodes": [], "spawned": false, "respawn_at": 0.0})
		_guards[lid] = st
		var dist: float = c.distance_to(ppos)
		var alive: Array = []
		for n in st["nodes"]:
			if is_instance_valid(n):
				alive.append(n)
		st["nodes"] = alive
		if dist > GUARD_FAR:
			if not alive.is_empty():
				for n2 in alive:
					n2.queue_free()
				st["nodes"] = []
				st["spawned"] = false
			continue
		if st["spawned"] and alive.is_empty() and float(st["respawn_at"]) <= 0.0:
			st["respawn_at"] = _time + GUARD_RESPAWN
		if dist > GUARD_NEAR or not alive.is_empty():
			continue
		if st["spawned"] and _time < float(st["respawn_at"]):
			continue
		st["spawned"] = true
		st["respawn_at"] = 0.0
		for g: Array in GUARDS[lid]:
			for i in int(g[1]):
				var e := _spawn_enemy(str(g[0]), _guard_pos(c))
				e.add_to_group("guard")
				st["nodes"].append(e)


func _guard_pos(c: Vector2) -> Vector2:
	var pos: Vector2 = c
	for i in 10:
		pos = c + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(50.0, 150.0)
		if decor.is_free(pos, 14.0) and not decor.in_water(pos, 10.0):
			return pos
	return pos


# ---------------------------------------------------------------------------
# Camp, bandits, boss
# ---------------------------------------------------------------------------

func _on_action_dispatched(action: Dictionary) -> void:
	if action.get("action_type", "") == "spawn_camp" and not _camp_revealed:
		_camp_revealed = true
		_build_camp(true)
		_spawn_remaining_bandits()


func _on_quest_updated(_quest_id: String, _stage: int, _objective: String) -> void:
	if GameState.get_current_stage("whispers_in_the_glade").get("id", "") == "boss_fight" and not _boss_spawned:
		_spawn_boss()


func _camp_prop(node: Node2D, offset: Vector2, size: Vector2 = Vector2.ZERO) -> Node2D:
	node.position = WorldDecor.CAMP_POS + offset
	if size != Vector2.ZERO:
		var body := StaticBody2D.new()
		body.collision_layer = 4
		body.collision_mask = 0
		var cs := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = size
		cs.shape = rs
		cs.position = Vector2(0, -size.y * 0.5)
		body.add_child(cs)
		node.add_child(body)
	decor.add_solid(node.position, maxf(size.x * 0.5, 14.0))
	return node


func _torch(offset: Vector2) -> Node2D:
	var n := Node2D.new()
	entities.add_child(n)
	Art.shadow(n, 5, 2, 0.25)
	Art._poly(n, Art.rect(-1.3, -26, 2.6, 26), Color(0.3, 0.2, 0.12))
	var flame := Art._poly(n, PackedVector2Array([Vector2(0, -42), Vector2(4, -32), Vector2(2, -27), Vector2(-2, -27), Vector2(-4, -32)]), Color(1.0, 0.55, 0.15))
	Art._poly(n, PackedVector2Array([Vector2(0, -38), Vector2(2, -32), Vector2(-2, -32)]), Color(1.0, 0.9, 0.5))
	var light := Fx.make_light(120.0, Color(1.0, 0.6, 0.25), 1.0)
	light.position = Vector2(0, -32)
	n.add_child(light)
	var tween := flame.create_tween().set_loops()
	tween.tween_property(flame, "scale", Vector2(1.0, 1.15), 0.18)
	tween.tween_property(flame, "scale", Vector2(0.92, 0.9), 0.14)
	return _camp_prop(n, offset, Vector2(5, 5))


func _banner(offset: Vector2) -> Node2D:
	var n := Node2D.new()
	entities.add_child(n)
	Art.shadow(n, 5, 2, 0.25)
	Art._poly(n, Art.rect(-1.5, -58, 3, 58), Color(0.32, 0.22, 0.14))
	Art._poly(n, PackedVector2Array([Vector2(1.5, -56), Vector2(24, -52), Vector2(19, -42), Vector2(24, -32), Vector2(1.5, -34)]), Color(0.65, 0.1, 0.12))
	Art._poly(n, PackedVector2Array([Vector2(7, -50), Vector2(12, -48), Vector2(9, -40)]), Color(0.92, 0.9, 0.85))
	Art._poly(n, PackedVector2Array([Vector2(13, -50), Vector2(18, -48), Vector2(15, -40)]), Color(0.92, 0.9, 0.85))
	return _camp_prop(n, offset, Vector2(5, 5))


func _build_camp(animate: bool) -> void:
	if _camp_built:
		return
	_camp_built = true
	var before: int = entities.get_child_count()
	for spec in [[Vector2(-92, -30), Color(0.6, 0.14, 0.14), 1.0], [Vector2(96, -48), Color(0.36, 0.13, 0.13), 1.0], [Vector2(-8, -108), Color(0.5, 0.2, 0.12), 1.25]]:
		var tent: Node2D = Art.tent(entities, spec[1])
		var sc: float = spec[2]
		tent.scale = Vector2(sc, sc)
		_camp_prop(tent, spec[0], Vector2(46.0 * sc, 12.0))
	var fire := INTERACTABLE_SCENE.instantiate()
	fire.kind = "campfire"
	entities.add_child(fire)
	_camp_prop(fire, Vector2(0, 16))
	var chest := INTERACTABLE_SCENE.instantiate()
	chest.kind = "chest"
	chest.uid = "camp"
	chest.loot = "bandit_insignia:1,healing_herb:2,cooked_meat:2"
	entities.add_child(chest)
	_camp_prop(chest, Vector2(52, -14))
	for off in [Vector2(-135, 18), Vector2(135, 8), Vector2(-46, -72), Vector2(56, -80)]:
		_torch(off)
	_banner(Vector2(-152, -22))
	_banner(Vector2(152, -34))
	if animate:
		for i in range(before, entities.get_child_count()):
			var n: CanvasItem = entities.get_child(i) as CanvasItem
			if n == null:
				continue
			n.modulate.a = 0.0
			n.create_tween().tween_property(n, "modulate:a", 1.0, 1.2)
		Fx.ring(WorldDecor.CAMP_POS, 160.0, Color(1.0, 0.3, 0.2, 1.0), 0.9)
		Fx.play("roar", 0.6)
		EventBus.toast_requested.emit("Red Fang war camp revealed on Old Barrow Ridge.", Color(1.0, 0.5, 0.4))


## Spawns however many camp bandits are still owed (total minus already-killed), so reloading
## a save made mid-camp-clear doesn't lose or duplicate progress -- the dynamically-added
## nodes themselves aren't persisted, only the kill_count ledger is.
func _spawn_remaining_bandits() -> void:
	var camp: Dictionary = _biome_data.get("camp", {})
	var groups := [
		[str(camp.get("bandit_id", "red_fang_bandit")), int(camp.get("bandit_count", 4))],
		[str(camp.get("archer_id", "bandit_archer")), int(camp.get("archer_count", 2))],
	]
	for g: Array in groups:
		var remaining: int = maxi(0, int(g[1]) - GameState.get_kill_count(str(g[0])))
		for i in remaining:
			var pos: Vector2 = WorldDecor.CAMP_POS + Vector2(randf_range(-115, 115), randf_range(-45, 80))
			for attempt in 8:
				if decor.is_free(pos, 14.0):
					break
				pos = WorldDecor.CAMP_POS + Vector2(randf_range(-115, 115), randf_range(-45, 80))
			_spawn_enemy(str(g[0]), pos)


func _spawn_boss() -> void:
	_boss_spawned = true
	if not _camp_built:
		_camp_revealed = true
		_build_camp(false)
	var boss: Node2D = BOSS_SCENE.instantiate()
	boss.position = WorldDecor.CAMP_POS + Vector2(0, -62)
	entities.add_child(boss)


func _load_biome_data() -> Dictionary:
	if not FileAccess.file_exists(BIOME_DATA_PATH):
		return {}
	var file := FileAccess.open(BIOME_DATA_PATH, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
