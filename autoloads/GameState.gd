extends Node
## GameState: the authoritative player ledger. Stands in for the PostgreSQL player-data table
## described in the spec -- same shape (per-class level/exp JSON blob), just persisted to a local
## JSON save file instead of a database row. Every other system (Player, HUD, GameMaster,
## DialogueUI) reads/writes through here rather than keeping its own copy of truth.

const SAVE_PATH := "user://save.json"
const CLASSES_PATH := "res://data/classes.json"
const QUESTS_PATH := "res://data/quests.json"
const ITEMS_PATH := "res://data/items.json"
const ENEMIES_PATH := "res://data/enemies.json"

## One full day/night cycle, in real seconds.
const DAY_LENGTH_SEC := 300.0
const BASE_MAX_HP := 100.0
const HP_PER_LEVEL := 8.0
const DAMAGE_PER_LEVEL := 0.05

var class_defs: Dictionary = {}
## quest_id -> quest definition dict (title/biome/stages/[requires_game_phase]).
## Multiple quests can be tracked at once -- whispers_in_the_glade is the main chain,
## rebuilding_glenbrook is a short Rebuilding Era follow-up gated on game_phase.
var quest_defs: Dictionary = {}
var exp_curve_base: int = 100
var recipe_defs: Dictionary = {}
## item_id -> {name, type, hunger, hp, color, desc, [cookable_into]}
var item_defs: Dictionary = {}
var enemy_defs: Dictionary = {}

## 0..1 fraction through the day. 0.0 = dawn, 0.5 = dusk. Persisted so night stays night on reload.
var world_time: float = 0.1
var total_kills: int = 0
var play_time: float = 0.0

## Mirrors DYNAMIC_PLAYER_STATE.class_level_map_json -- independent level/exp/gear per role.
var class_data: Dictionary = {
	"swordsman": {"level": 1, "exp": 0, "equipped_tier_index": 0},
	"bowman": {"level": 0, "exp": 0, "equipped_tier_index": 0},
	"magic_user": {"level": 0, "exp": 0, "equipped_tier_index": 0},
	"rogue": {"level": 0, "exp": 0, "equipped_tier_index": 0},
	"alchemist": {"level": 0, "exp": 0, "equipped_tier_index": 0},
}

var active_class: String = "swordsman"

var hp: float = 100.0
var max_hp: float = 100.0
var hunger: float = 100.0

var game_phase: String = "Story_Mode" # or "Rebuilding_Era"

## quest_id -> current stage index (int)
var quest_progress: Dictionary = {}
## free-form story/dialogue flags, e.g. "reported_wolf_proof_to_garrick": true
var story_flags: Dictionary = {}
## npc_id -> rapport score (int), used for dialogue-rapport story gating
var rapport: Dictionary = {}
## enemy_id -> kill count (int), used for kill_count quest advance conditions
var kill_counts: Dictionary = {}
## item_id -> count
var inventory: Dictionary = {}
## recipe_id -> true
var unlocked_recipes: Dictionary = {}
## npc_id -> free-form dictionary owned by the dialogue engine (topics discussed, times talked, ...)
var npc_memory: Dictionary = {}
## region the player is currently in (updated by the Guide node), "" before the first update
var current_region: String = ""
## region_id -> true
var visited_regions: Dictionary = {}
## landmark_id -> true
var discovered_landmarks: Dictionary = {}
## "cx,cy" -> true : fog-of-war cells revealed on the world map (cell size = EXPLORE_CELL px)
var explored_cells: Dictionary = {}
const EXPLORE_CELL := 200
## item ids the player has ever held (for the item codex)
var seen_items: Dictionary = {}
## quest ids the player has been told about / completed, for the quest log
var completed_quests: Dictionary = {}

## "qid:stage" -> kill counter snapshot taken when a relative "kill" stage began
var quest_baselines: Dictionary = {}
## quest the player pinned in the quest log ("" = automatic choice)
var tracked_quest: String = ""
var _talk_npc: String = ""
var _player_pos: Vector2 = Vector2(-99999, -99999)
var _quest_event: Dictionary = {} # npc_id -> {kind, quest_id, title} from the latest dialogue open

const HUNGER_DRAIN_PER_SEC := 0.35
const HUNGER_LOW_THRESHOLD := 25.0
const HUNGER_MOVE_PENALTY := 0.5 # multiplier applied to move speed when starving


var _autosave_timer: Timer


func _ready() -> void:
	var classes_file: Dictionary = _load_json(CLASSES_PATH)
	class_defs = classes_file.get("classes", {})
	exp_curve_base = int(classes_file.get("exp_curve", {}).get("base", 100))
	recipe_defs = classes_file.get("recipes", {})

	item_defs = _load_json(ITEMS_PATH).get("items", {})
	enemy_defs = _load_json(ENEMIES_PATH).get("enemies", {})

	var quests_file: Dictionary = _load_json(QUESTS_PATH)
	for q in quests_file.get("quests", []):
		var qid: String = q.get("quest_id", "")
		if qid != "":
			quest_defs[qid] = q

	load_from_disk()
	recompute_max_hp()
	# Idempotent for quests already in quest_progress (from a save) -- only seeds stage 0
	# for quests that haven't been started yet, e.g. rebuilding_glenbrook once game_phase
	# flips to Rebuilding_Era after a fresh whispers_in_the_glade completion.
	for qid in quest_defs.keys():
		_start_quest_if_needed(qid)
	EventBus.dialogue_requested.connect(_on_dialogue_opened)

	# Autosave is the only thing standing in for the spec's PostgreSQL persistence layer --
	# without it, closing the window silently throws away all progress. Saves periodically
	# and (via _notification below) on quit.
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = 20.0
	_autosave_timer.autostart = true
	_autosave_timer.timeout.connect(save_to_disk)
	add_child(_autosave_timer)


func _process(delta: float) -> void:
	_tick_hunger(delta)
	world_time = fposmod(world_time + delta / DAY_LENGTH_SEC, 1.0)
	play_time += delta


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_to_disk()
		get_tree().quit()


# ---------------------------------------------------------------------------
# Vitals
# ---------------------------------------------------------------------------

func _tick_hunger(delta: float) -> void:
	hunger = max(0.0, hunger - HUNGER_DRAIN_PER_SEC * delta)
	if hunger > HUNGER_LOW_THRESHOLD and hp < max_hp:
		hp = min(max_hp, hp + 1.0 * delta) # slow passive regen while fed
	EventBus.vitals_changed.emit()


func get_move_speed_multiplier() -> float:
	return HUNGER_MOVE_PENALTY if hunger <= 0.0 else 1.0


func eat_food(hunger_restored: float, hp_restored: float = 0.0) -> void:
	hunger = min(100.0, hunger + hunger_restored)
	hp = min(max_hp, hp + hp_restored)
	EventBus.vitals_changed.emit()


func get_item_def(item_id: String) -> Dictionary:
	return item_defs.get(item_id, {"name": item_id.capitalize().replace("_", " "), "type": "material", "color": [0.8, 0.8, 0.8, 1]})


func get_item_name(item_id: String) -> String:
	return str(get_item_def(item_id).get("name", item_id))


func get_item_color(item_id: String) -> Color:
	var c: Array = get_item_def(item_id).get("color", [0.8, 0.8, 0.8, 1])
	return Color(c[0], c[1], c[2], c[3] if c.size() > 3 else 1.0)


## Consumes one of a food item and applies its hunger/hp. Returns false if not edible or not owned.
func eat_item(item_id: String) -> bool:
	var def: Dictionary = get_item_def(item_id)
	if def.get("type", "") != "food" or int(inventory.get(item_id, 0)) <= 0:
		return false
	remove_item(item_id, 1)
	eat_food(float(def.get("hunger", 0)), float(def.get("hp", 0)))
	return true


## Eats whichever owned food restores the most, weighting hp higher so it's chosen when hurt.
func eat_best_food() -> String:
	var best := ""
	var best_score := -1.0
	for item_id in inventory.keys():
		var def: Dictionary = get_item_def(item_id)
		if def.get("type", "") != "food":
			continue
		var hunger_gain: float = minf(float(def.get("hunger", 0)), 100.0 - hunger)
		var hp_gain: float = minf(float(def.get("hp", 0)), max_hp - hp)
		var score: float = hunger_gain + hp_gain * 1.5
		if score > best_score:
			best_score = score
			best = item_id
	if best != "" and best_score > 0.0 and eat_item(best):
		return best
	return ""


func get_food_items() -> Array:
	var out: Array = []
	for item_id in inventory.keys():
		if get_item_def(item_id).get("type", "") == "food":
			out.append(item_id)
	return out


## Hour of day 0..24, with 6.0 = dawn (world_time 0), for the HUD clock.
func get_clock_hour() -> float:
	return fposmod(6.0 + world_time * 24.0, 24.0)


## 0 = full daylight, 1 = deepest night. Smoothed so dusk/dawn fade over a few hours each.
func get_darkness() -> float:
	var h: float = get_clock_hour()
	if h >= 8.0 and h <= 18.0:
		return 0.0
	if h > 18.0 and h < 21.0:
		return smoothstep(18.0, 21.0, h)
	if h >= 21.0 or h <= 4.0:
		return 1.0
	return 1.0 - smoothstep(4.0, 8.0, h)


func recompute_max_hp() -> void:
	var lvl: int = maxi(1, get_class_level(active_class))
	max_hp = BASE_MAX_HP + HP_PER_LEVEL * float(lvl - 1)
	hp = minf(hp, max_hp)


func get_level_damage_multiplier() -> float:
	var lvl: int = maxi(1, get_class_level(active_class))
	return 1.0 + DAMAGE_PER_LEVEL * float(lvl - 1)


## Returns the damage actually dealt after armor mitigation (for damage-number display).
func take_damage(amount: float) -> float:
	var mitigation := get_active_armor_mitigation()
	var final_damage: float = max(1.0, amount - mitigation)
	hp = max(0.0, hp - final_damage)
	EventBus.vitals_changed.emit()
	return final_damage


func get_active_armor_mitigation() -> float:
	var def: Dictionary = class_defs.get(active_class, {})
	var mitigations: Array = def.get("armor_mitigation_by_tier", [])
	var tier_index: int = class_data[active_class].get("equipped_tier_index", 0)
	if tier_index >= 0 and tier_index < mitigations.size():
		return mitigations[tier_index]
	return 0.0


func is_dead() -> bool:
	return hp <= 0.0


# ---------------------------------------------------------------------------
# Class progression (spec 2: Dynamic Role & Level Retention)
# ---------------------------------------------------------------------------

func switch_class(new_class_id: String) -> void:
	if not class_data.has(new_class_id):
		push_warning("Unknown class id: %s" % new_class_id)
		return
	if new_class_id == active_class:
		return
	# The outgoing class's level/exp/gear stay exactly as they are in class_data --
	# we simply change which key is "active". Nothing about the old class is touched.
	active_class = new_class_id
	recompute_max_hp()
	EventBus.class_changed.emit(active_class)
	EventBus.vitals_changed.emit()


func grant_exp(class_id: String, amount: int) -> void:
	if not class_data.has(class_id):
		return
	var entry: Dictionary = class_data[class_id]
	entry["exp"] = int(entry["exp"]) + amount
	var leveled := false
	var next_needed := _exp_to_next_level(int(entry["level"]))
	while entry["exp"] >= next_needed and next_needed > 0:
		entry["exp"] -= next_needed
		entry["level"] = int(entry["level"]) + 1
		leveled = true
		next_needed = _exp_to_next_level(int(entry["level"]))
	class_data[class_id] = entry
	if leveled:
		if class_id == active_class:
			recompute_max_hp()
			hp = max_hp
		EventBus.level_up.emit(class_id, int(entry["level"]))
	EventBus.vitals_changed.emit()


func _exp_to_next_level(level: int) -> int:
	return exp_curve_base * max(1, level)


func get_exp_to_next_level(class_id: String) -> int:
	return _exp_to_next_level(get_class_level(class_id))


func get_class_level(class_id: String) -> int:
	return class_data.get(class_id, {}).get("level", 0)


func get_equipped_tier_name(class_id: String) -> String:
	var def: Dictionary = class_defs.get(class_id, {})
	var tiers: Array = def.get("armor_tiers", [])
	var idx: int = class_data.get(class_id, {}).get("equipped_tier_index", 0)
	if idx >= 0 and idx < tiers.size():
		return tiers[idx]
	return "None"


func upgrade_equipment(class_id: String) -> void:
	if not class_data.has(class_id):
		return
	var def: Dictionary = class_defs.get(class_id, {})
	var tiers: Array = def.get("armor_tiers", [])
	var entry: Dictionary = class_data[class_id]
	entry["equipped_tier_index"] = min(int(entry["equipped_tier_index"]) + 1, tiers.size() - 1)
	class_data[class_id] = entry
	EventBus.vitals_changed.emit()


## Combat stats for whichever class is currently active (spec 2: per-role loadouts).
## Player.gd reads this instead of hardcoding attack numbers, so every class's fight
## feel lives in data/classes.json rather than scattered across scripts.
func get_active_combat_stats() -> Dictionary:
	return class_defs.get(active_class, {}).get("combat", {})


## Crafting/upgrade hook for recipe rewards (e.g. "iron_tier_swordsman_armor" unlocked by
## finishing the Whispering Glades quest). No raw-material cost in this slice -- unlocking
## the recipe via a quest/reward is the gate; crafting just applies the tier it points to.
func craft_equipment(recipe_id: String) -> bool:
	if not unlocked_recipes.get(recipe_id, false):
		return false
	var recipe: Dictionary = recipe_defs.get(recipe_id, {})
	if recipe.is_empty():
		return false
	var class_id: String = recipe.get("class_id", "")
	var tier_index: int = int(recipe.get("tier_index", -1))
	if not class_data.has(class_id) or tier_index < 0:
		return false
	var entry: Dictionary = class_data[class_id]
	if int(entry.get("equipped_tier_index", 0)) >= tier_index:
		return false # already at or past this tier
	entry["equipped_tier_index"] = tier_index
	class_data[class_id] = entry
	EventBus.vitals_changed.emit()
	return true


# ---------------------------------------------------------------------------
# Story / quest state (spec 3: Autonomous Story & Quest Generation Rules)
# ---------------------------------------------------------------------------

func _start_quest_if_needed(qid: String) -> void:
	if qid == "" or quest_progress.has(qid):
		return
	var def: Dictionary = quest_defs.get(qid, {})
	var required_phase: String = def.get("requires_game_phase", "")
	if required_phase != "" and required_phase != game_phase:
		return
	var required_flag: String = def.get("requires_story_flag", "")
	if required_flag != "" and not has_story_flag(required_flag):
		return
	var required_quest: String = def.get("requires_quest", "")
	if required_quest != "" and not completed_quests.get(required_quest, false):
		return
	var stages: Array = def.get("stages", [])
	if stages.is_empty() or not bool(stages[0].get("auto_active", false)):
		return
	quest_progress[qid] = 0
	_enter_stage(qid, 0)
	EventBus.quest_updated.emit(qid, 0, stages[0].get("objective", ""))


## True if the quest can be handed out right now (giver quests start when you talk to the giver).
func is_quest_available(qid: String) -> bool:
	var def: Dictionary = quest_defs.get(qid, {})
	if def.is_empty() or quest_progress.has(qid) or str(def.get("giver", "")) == "":
		return false
	var required_phase: String = def.get("requires_game_phase", "")
	if required_phase != "" and required_phase != game_phase:
		return false
	var required_flag: String = def.get("requires_story_flag", "")
	if required_flag != "" and not has_story_flag(required_flag):
		return false
	var required_quest: String = def.get("requires_quest", "")
	if required_quest != "" and not completed_quests.get(required_quest, false):
		return false
	return true


func accept_quest(qid: String) -> void:
	if quest_progress.has(qid) or not quest_defs.has(qid):
		return
	quest_progress[qid] = 0
	_enter_stage(qid, 0)
	var stages: Array = quest_defs[qid].get("stages", [])
	EventBus.quest_updated.emit(qid, 0, stages[0].get("objective", "") if not stages.is_empty() else "")
	EventBus.toast_requested.emit("New quest: %s" % get_quest_title(qid), Color(1.0, 0.88, 0.45))
	Fx.play("quest")
	if tracked_quest == "":
		tracked_quest = qid
	_check_quest_advance()


func _enter_stage(qid: String, idx: int) -> void:
	var stages: Array = quest_defs.get(qid, {}).get("stages", [])
	if idx < 0 or idx >= stages.size():
		return
	var cond: Dictionary = stages[idx].get("advance_condition", {})
	if cond.get("type", "") == "kill":
		quest_baselines["%s:%d" % [qid, idx]] = get_kill_count(_kill_key(cond))


func _kill_key(cond: Dictionary) -> String:
	var t: String = str(cond.get("target", "@any"))
	var region: String = str(cond.get("region", ""))
	if region != "":
		return "@region:" + region
	return "@any" if t == "any" else t


func get_quest_title(qid: String) -> String:
	return str(quest_defs.get(qid, {}).get("title", qid.capitalize().replace("_", " ")))


func _on_dialogue_opened(npc_id: String, _display_name: String) -> void:
	_quest_event.erase(npc_id)
	for qid: String in quest_defs.keys():
		if str(quest_defs[qid].get("giver", "")) == npc_id and is_quest_available(qid):
			accept_quest(qid)
			_quest_event[npc_id] = {"kind": "accepted", "quest_id": qid, "title": get_quest_title(qid)}
	_talk_npc = npc_id
	var before: Dictionary = completed_quests.duplicate()
	_check_quest_advance()
	_talk_npc = ""
	for qid: String in completed_quests.keys():
		if not before.has(qid):
			_quest_event[npc_id] = {"kind": "completed", "quest_id": qid, "title": get_quest_title(qid)}


## Called by the Guide every fraction of a second with the player's world position; drives
## "reach" / "visit_region" stages that depend on where the player is.
func notify_player_pos(pos: Vector2) -> void:
	_player_pos = pos
	_check_quest_advance()


func increment_rapport(npc_id: String, amount: int = 1) -> void:
	rapport[npc_id] = int(rapport.get(npc_id, 0)) + amount


func get_rapport(npc_id: String) -> int:
	return int(rapport.get(npc_id, 0))


func set_story_flag(flag: String, value: bool = true) -> void:
	story_flags[flag] = value
	for qid in quest_defs.keys():
		_start_quest_if_needed(qid)
	_check_quest_advance()


func has_story_flag(flag: String) -> bool:
	return bool(story_flags.get(flag, false))


func register_kill(enemy_id: String) -> void:
	kill_counts[enemy_id] = int(kill_counts.get(enemy_id, 0)) + 1
	kill_counts["@any"] = int(kill_counts.get("@any", 0)) + 1
	if current_region != "":
		var rk := "@region:" + current_region
		kill_counts[rk] = int(kill_counts.get(rk, 0)) + 1
	total_kills += 1
	_check_quest_advance()


func get_kill_count(enemy_id: String) -> int:
	return int(kill_counts.get(enemy_id, 0))


func get_current_stage_index(qid: String) -> int:
	return int(quest_progress.get(qid, -1))


func get_current_stage(qid: String) -> Dictionary:
	var stages: Array = quest_defs.get(qid, {}).get("stages", [])
	var idx := get_current_stage_index(qid)
	if idx >= 0 and idx < stages.size():
		return stages[idx]
	return {}


func get_current_objective(qid: String) -> String:
	return get_current_stage(qid).get("objective", "")


## Quests currently in progress (not complete), main quests first.
func get_active_quests() -> Array:
	var out: Array = []
	for qid: String in quest_progress.keys():
		var stage: Dictionary = get_current_stage(qid)
		if stage.is_empty() or str(stage.get("id", "")) == "complete":
			continue
		out.append(qid)
	out.sort_custom(func(a: String, b: String) -> bool:
		var ta: int = 0 if str(quest_defs[a].get("tier", "side")) == "main" else 1
		var tb: int = 0 if str(quest_defs[b].get("tier", "side")) == "main" else 1
		if ta != tb:
			return ta < tb
		return a < b)
	return out


func get_tracked_quest() -> String:
	var active := get_active_quests()
	if tracked_quest != "" and active.has(tracked_quest):
		return tracked_quest
	return active[0] if not active.is_empty() else ""


func set_tracked_quest(qid: String) -> void:
	tracked_quest = qid
	EventBus.quest_updated.emit(qid, get_current_stage_index(qid), get_current_objective(qid))


## Objective text for the HUD: the tracked quest's current stage.
func get_display_objective() -> String:
	var qid := get_tracked_quest()
	if qid != "":
		return get_current_objective(qid)
	return "Glenbrook is safer now. Explore the wider world -- press M for the map, J for your journal."


## Where the tracked quest's current stage wants the player to go:
## {"label": String, "pos": Vector2, "radius": float, "npc": String} or {} if unknown.
func get_objective_target(qid: String = "") -> Dictionary:
	if qid == "":
		qid = get_tracked_quest()
	if qid == "":
		return {}
	var stage: Dictionary = get_current_stage(qid)
	var t: Dictionary = stage.get("target", {})
	var cond: Dictionary = stage.get("advance_condition", {})
	if t.is_empty():
		if cond.has("npc"):
			t = {"npc": cond["npc"]}
		elif cond.has("npc_id"):
			t = {"npc": cond["npc_id"]}
		elif stage.has("marker_npc"):
			t = {"npc": stage["marker_npc"]}
		elif cond.has("landmark"):
			t = {"landmark": cond["landmark"]}
		elif cond.has("region"):
			t = {"region": cond["region"]}
	if t.is_empty():
		return {}
	var out: Dictionary = {"label": "", "radius": 120.0}
	if t.has("npc"):
		var npc_id: String = str(t["npc"])
		out["npc"] = npc_id
		out["label"] = _npc_display_name(npc_id)
		var np: Variant = _npc_position(npc_id)
		if np != null:
			out["pos"] = np
	elif t.has("landmark"):
		var lm: Dictionary = _landmark(str(t["landmark"]))
		if not lm.is_empty():
			var lp: Array = lm.get("pos", [0, 0])
			out["pos"] = Vector2(float(lp[0]), float(lp[1]))
			out["label"] = str(lm.get("name", ""))
	elif t.has("region"):
		var reg: Dictionary = _region(str(t["region"]))
		if not reg.is_empty():
			var rr: Array = reg.get("rect", [0, 0, 0, 0])
			out["pos"] = Vector2(float(rr[0]) + float(rr[2]) * 0.5, float(rr[1]) + float(rr[3]) * 0.5)
			out["label"] = str(reg.get("name", ""))
			out["radius"] = minf(float(rr[2]), float(rr[3])) * 0.35
	elif t.has("pos"):
		var pa: Array = t["pos"]
		out["pos"] = Vector2(float(pa[0]), float(pa[1]))
		out["label"] = str(t.get("label", "Objective"))
	if not out.has("pos"):
		return {}
	return out


func _region(id: String) -> Dictionary:
	if id == "" or not ResourceLoader.exists("res://scripts/Regions.gd"):
		return {}
	var r = load("res://scripts/Regions.gd")
	return r.get_region(id)


func _npc_display_name(npc_id: String) -> String:
	var gm = get_node_or_null("/root/GameMaster")
	if gm != null:
		var prof: Dictionary = gm.npc_profiles.get(npc_id, {})
		return str(prof.get("display_name", prof.get("name", npc_id.capitalize().replace("_", " "))))
	return npc_id


func _npc_position(npc_id: String) -> Variant:
	for n in get_tree().get_nodes_in_group("npcs"):
		if str(n.get("npc_id")) == npc_id:
			return (n as Node2D).global_position
	var gm = get_node_or_null("/root/GameMaster")
	if gm != null:
		var home: Dictionary = gm.npc_profiles.get(npc_id, {}).get("home", {})
		var lm: Dictionary = _landmark(str(home.get("landmark", "")))
		if not lm.is_empty():
			var lp: Array = lm.get("pos", [0, 0])
			return Vector2(float(lp[0]), float(lp[1]))
	return null


## "!" (new quest / new info), "?" (turn-in or report back) or "" for an NPC.
func get_npc_marker(npc_id: String) -> String:
	for qid: String in get_active_quests():
		var stage: Dictionary = get_current_stage(qid)
		var cond: Dictionary = stage.get("advance_condition", {})
		var involved: bool = str(stage.get("marker_npc", "")) == npc_id or str(cond.get("npc", "")) == npc_id
		if not involved:
			continue
		if cond.get("type", "") == "deliver" and int(inventory.get(str(cond.get("item", "")), 0)) < int(cond.get("count", 1)):
			continue
		return str(stage.get("marker", "?" if cond.get("type", "") in ["deliver", "talk"] else "!"))
	for qid: String in quest_defs.keys():
		if str(quest_defs[qid].get("giver", "")) == npc_id and is_quest_available(qid):
			return "!"
	return ""


## Everything the dialogue engine needs to talk about quests with this NPC.
func get_npc_quest_context(npc_id: String) -> Dictionary:
	var ctx: Dictionary = {"offer": [], "active": [], "turn_in": [], "completed": [], "event": _quest_event.get(npc_id, {})}
	for qid: String in quest_defs.keys():
		var def: Dictionary = quest_defs[qid]
		if str(def.get("giver", "")) == npc_id:
			if is_quest_available(qid):
				ctx["offer"].append({"quest_id": qid, "title": get_quest_title(qid), "pitch": str(def.get("pitch", def.get("summary", "")))})
			elif completed_quests.get(qid, false):
				ctx["completed"].append(qid)
	for qid: String in get_active_quests():
		var stage: Dictionary = get_current_stage(qid)
		var cond: Dictionary = stage.get("advance_condition", {})
		var entry: Dictionary = {"quest_id": qid, "title": get_quest_title(qid), "objective": str(stage.get("objective", "")), "hint": str(stage.get("hint", ""))}
		var giver_is_me: bool = str(quest_defs[qid].get("giver", "")) == npc_id
		var involved: bool = str(stage.get("marker_npc", "")) == npc_id or str(cond.get("npc", "")) == npc_id or str(cond.get("npc_id", "")) == npc_id
		if giver_is_me or involved:
			ctx["active"].append(entry)
		if involved and cond.get("type", "") in ["deliver", "talk", "dialogue_flag"]:
			ctx["turn_in"].append(entry)
	return ctx


## Checks every quest currently in progress (not just one hardcoded chain) against its current
## stage's advance_condition, so kill_count/dialogue_flag events raised anywhere can progress
## whichever quests are actually listening for them.
func _check_quest_advance() -> void:
	for qid in quest_progress.keys():
		var stages: Array = quest_defs.get(qid, {}).get("stages", [])
		var idx: int = int(quest_progress[qid])
		if idx < 0 or idx >= stages.size():
			continue
		var stage: Dictionary = stages[idx]
		var cond: Dictionary = stage.get("advance_condition", {})
		if cond.is_empty():
			continue
		var met := false
		match cond.get("type", ""):
			"kill_count":
				met = get_kill_count(cond.get("target", "")) >= int(cond.get("count", 1))
			"dialogue_flag":
				met = has_story_flag(cond.get("flag", ""))
			"have_item", "collect":
				met = int(inventory.get(cond.get("item", ""), 0)) >= int(cond.get("count", 1))
				if met and bool(cond.get("consume", false)):
					remove_item(cond.get("item", ""), int(cond.get("count", 1)))
			"kill":
				var base: int = int(quest_baselines.get("%s:%d" % [qid, idx], 0))
				met = get_kill_count(_kill_key(cond)) - base >= int(cond.get("count", 1))
			"talk":
				met = _talk_npc != "" and _talk_npc == str(cond.get("npc", ""))
			"deliver":
				var need: int = int(cond.get("count", 1))
				met = _talk_npc != "" and _talk_npc == str(cond.get("npc", "")) and int(inventory.get(cond.get("item", ""), 0)) >= need
				if met and bool(cond.get("consume", true)):
					remove_item(str(cond.get("item", "")), need)
			"reach":
				met = _is_reached(cond)
			"visit_region":
				met = bool(visited_regions.get(str(cond.get("region", "")), false))
			"visit_regions":
				met = visited_regions.size() >= int(cond.get("count", 1))
		if met:
			_advance_quest(qid, idx + 1)
			_check_quest_advance() # re-scan: this may satisfy the next stage or start new quests
			return


## Force-advances a quest by one stage iff it is currently sitting at expected_stage_index.
## Used for stages whose "advance_condition" is really just narrative (e.g. stage 0's objective
## is simply "talk to Garrick") rather than a checkable kill_count/dialogue_flag.
func force_advance_if_at_stage(qid: String, expected_stage_index: int) -> bool:
	if get_current_stage_index(qid) != expected_stage_index:
		return false
	_advance_quest(qid, expected_stage_index + 1)
	return true


func _is_reached(cond: Dictionary) -> bool:
	if _player_pos.x < -90000.0:
		return false
	var radius: float = float(cond.get("radius", 220.0))
	if cond.has("pos"):
		var arr: Array = cond["pos"]
		return _player_pos.distance_to(Vector2(float(arr[0]), float(arr[1]))) <= radius
	var lm: Dictionary = _landmark(str(cond.get("landmark", "")))
	if lm.is_empty():
		return false
	var lp: Array = lm.get("pos", [0, 0])
	return _player_pos.distance_to(Vector2(float(lp[0]), float(lp[1]))) <= radius


func _landmark(id: String) -> Dictionary:
	if id == "" or not ResourceLoader.exists("res://scripts/Regions.gd"):
		return {}
	var r = load("res://scripts/Regions.gd")
	return r.get_landmark(id)


func _advance_quest(qid: String, new_stage_index: int) -> void:
	var stages: Array = quest_defs.get(qid, {}).get("stages", [])
	quest_progress[qid] = new_stage_index
	_enter_stage(qid, new_stage_index)
	if new_stage_index < stages.size():
		var stage: Dictionary = stages[new_stage_index]
		EventBus.quest_updated.emit(qid, new_stage_index, stage.get("objective", ""))
		if str(stage.get("id", "")) == "complete":
			completed_quests[qid] = true
			EventBus.toast_requested.emit("Quest complete: %s" % get_quest_title(qid), Color(1.0, 0.88, 0.45))
			Fx.play("quest")
			if tracked_quest == qid:
				tracked_quest = ""
		elif new_stage_index > 0:
			EventBus.toast_requested.emit("Quest updated: %s" % get_quest_title(qid), Color(0.9, 0.85, 0.6))
		var rewards: Dictionary = stage.get("rewards", {})
		if not rewards.is_empty():
			_apply_rewards(rewards)
		var next_phase: String = stage.get("triggers_game_phase", "")
		if next_phase != "" and next_phase != game_phase:
			game_phase = next_phase
			# A new phase may unlock quests that were waiting on requires_game_phase.
			for other_qid in quest_defs.keys():
				_start_quest_if_needed(other_qid)


func _apply_rewards(rewards: Dictionary) -> void:
	if rewards.has("grant_exp"):
		var g: Dictionary = rewards["grant_exp"]
		grant_exp(g.get("class", active_class), int(g.get("amount", 0)))
	if rewards.has("give_item"):
		add_item(rewards["give_item"], 1)
	if rewards.has("give_items"):
		for it: String in rewards["give_items"].keys():
			add_item(it, int(rewards["give_items"][it]))
	if rewards.has("unlock_recipe"):
		unlocked_recipes[rewards["unlock_recipe"]] = true
	if rewards.has("unlock_recipe_for_active_class"):
		var pattern: String = rewards["unlock_recipe_for_active_class"]
		unlocked_recipes[pattern % active_class] = true


func add_item(item_id: String, count: int = 1) -> void:
	inventory[item_id] = int(inventory.get(item_id, 0)) + count
	seen_items[item_id] = true
	EventBus.inventory_changed.emit()
	_check_quest_advance()


func remove_item(item_id: String, count: int = 1) -> bool:
	var have := int(inventory.get(item_id, 0))
	if have < count:
		return false
	inventory[item_id] = have - count
	if inventory[item_id] <= 0:
		inventory.erase(item_id)
	EventBus.inventory_changed.emit()
	return true


# ---------------------------------------------------------------------------
# Persistence (stands in for the PostgreSQL ledger described in the spec)
# ---------------------------------------------------------------------------

func save_to_disk() -> void:
	var blob := {
		"class_data": class_data,
		"active_class": active_class,
		"hp": hp,
		"max_hp": max_hp,
		"hunger": hunger,
		"game_phase": game_phase,
		"quest_progress": quest_progress,
		"story_flags": story_flags,
		"rapport": rapport,
		"kill_counts": kill_counts,
		"inventory": inventory,
		"unlocked_recipes": unlocked_recipes,
		"npc_memory": npc_memory,
		"current_region": current_region,
		"visited_regions": visited_regions,
		"discovered_landmarks": discovered_landmarks,
		"explored_cells": explored_cells,
		"seen_items": seen_items,
		"completed_quests": completed_quests,
		"quest_baselines": quest_baselines,
		"tracked_quest": tracked_quest,
		"world_time": world_time,
		"total_kills": total_kills,
		"play_time": play_time,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(blob, "\t"))
		file.close()


func load_from_disk() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return false
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	class_data = parsed.get("class_data", class_data)
	active_class = parsed.get("active_class", active_class)
	hp = parsed.get("hp", hp)
	max_hp = parsed.get("max_hp", max_hp)
	hunger = parsed.get("hunger", hunger)
	game_phase = parsed.get("game_phase", game_phase)
	quest_progress = parsed.get("quest_progress", {})
	story_flags = parsed.get("story_flags", {})
	rapport = parsed.get("rapport", {})
	kill_counts = parsed.get("kill_counts", {})
	inventory = parsed.get("inventory", {})
	unlocked_recipes = parsed.get("unlocked_recipes", {})
	npc_memory = parsed.get("npc_memory", {})
	current_region = str(parsed.get("current_region", ""))
	visited_regions = parsed.get("visited_regions", {})
	discovered_landmarks = parsed.get("discovered_landmarks", {})
	explored_cells = parsed.get("explored_cells", {})
	seen_items = parsed.get("seen_items", {})
	completed_quests = parsed.get("completed_quests", {})
	quest_baselines = parsed.get("quest_baselines", {})
	tracked_quest = str(parsed.get("tracked_quest", ""))
	world_time = float(parsed.get("world_time", world_time))
	total_kills = int(parsed.get("total_kills", 0))
	play_time = float(parsed.get("play_time", 0.0))
	# JSON has no int type -- everything numeric comes back as float, so restore ints.
	for cid in class_data.keys():
		for key in ["level", "exp", "equipped_tier_index"]:
			class_data[cid][key] = int(class_data[cid].get(key, 0))
	for k in quest_progress.keys():
		quest_progress[k] = int(quest_progress[k])
	for k in kill_counts.keys():
		kill_counts[k] = int(kill_counts[k])
	for k in inventory.keys():
		inventory[k] = int(inventory[k])
	return true


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Missing data file: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}
