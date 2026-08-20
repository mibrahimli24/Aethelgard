extends Node
## GameState: the authoritative player ledger. Stands in for the PostgreSQL player-data table
## described in the spec -- same shape (per-class level/exp JSON blob), just persisted to a local
## JSON save file instead of a database row. Every other system (Player, HUD, GameMaster,
## DialogueUI) reads/writes through here rather than keeping its own copy of truth.

const SAVE_PATH := "user://save.json"
const CLASSES_PATH := "res://data/classes.json"
const QUESTS_PATH := "res://data/quests.json"

var class_defs: Dictionary = {}
## quest_id -> quest definition dict (title/biome/stages/[requires_game_phase]).
## Multiple quests can be tracked at once -- whispers_in_the_glade is the main chain,
## rebuilding_glenbrook is a short Rebuilding Era follow-up gated on game_phase.
var quest_defs: Dictionary = {}
var exp_curve_base: int = 100
var recipe_defs: Dictionary = {}

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

const HUNGER_DRAIN_PER_SEC := 0.35
const HUNGER_LOW_THRESHOLD := 25.0
const HUNGER_MOVE_PENALTY := 0.5 # multiplier applied to move speed when starving


var _autosave_timer: Timer


func _ready() -> void:
	var classes_file: Dictionary = _load_json(CLASSES_PATH)
	class_defs = classes_file.get("classes", {})
	exp_curve_base = int(classes_file.get("exp_curve", {}).get("base", 100))
	recipe_defs = classes_file.get("recipes", {})

	var quests_file: Dictionary = _load_json(QUESTS_PATH)
	for q in quests_file.get("quests", []):
		var qid: String = q.get("quest_id", "")
		if qid != "":
			quest_defs[qid] = q

	load_from_disk()
	# Idempotent for quests already in quest_progress (from a save) -- only seeds stage 0
	# for quests that haven't been started yet, e.g. rebuilding_glenbrook once game_phase
	# flips to Rebuilding_Era after a fresh whispers_in_the_glade completion.
	for qid in quest_defs.keys():
		_start_quest_if_needed(qid)

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


func eat_food(hunger_restored: float) -> void:
	hunger = min(100.0, hunger + hunger_restored)
	EventBus.vitals_changed.emit()


func take_damage(amount: float) -> void:
	var mitigation := get_active_armor_mitigation()
	var final_damage: float = max(1.0, amount - mitigation)
	hp = max(0.0, hp - final_damage)
	EventBus.vitals_changed.emit()


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
	EventBus.class_changed.emit(active_class)
	EventBus.vitals_changed.emit()


func grant_exp(class_id: String, amount: int) -> void:
	if not class_data.has(class_id):
		return
	var entry: Dictionary = class_data[class_id]
	entry["exp"] = int(entry["exp"]) + amount
	var next_needed := _exp_to_next_level(entry["level"])
	while entry["exp"] >= next_needed and next_needed > 0:
		entry["exp"] -= next_needed
		entry["level"] += 1
		next_needed = _exp_to_next_level(entry["level"])
	class_data[class_id] = entry
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
	var stages: Array = def.get("stages", [])
	if stages.is_empty() or not bool(stages[0].get("auto_active", false)):
		return
	quest_progress[qid] = 0
	EventBus.quest_updated.emit(qid, 0, stages[0].get("objective", ""))


func increment_rapport(npc_id: String, amount: int = 1) -> void:
	rapport[npc_id] = int(rapport.get(npc_id, 0)) + amount


func get_rapport(npc_id: String) -> int:
	return int(rapport.get(npc_id, 0))


func set_story_flag(flag: String, value: bool = true) -> void:
	story_flags[flag] = value
	_check_quest_advance()


func has_story_flag(flag: String) -> bool:
	return bool(story_flags.get(flag, false))


func register_kill(enemy_id: String) -> void:
	kill_counts[enemy_id] = int(kill_counts.get(enemy_id, 0)) + 1
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


## Picks whichever tracked quest is most relevant to show in the HUD: the main chain while
## it's incomplete, then the Rebuilding Era follow-up, then a generic epilogue line once both
## are done. Kept centralized here so HUD.gd doesn't need to know quest ordering/priority.
func get_display_objective() -> String:
	var main_stage: Dictionary = get_current_stage("whispers_in_the_glade")
	if main_stage.get("id", "") != "complete":
		return main_stage.get("objective", "Explore the Whispering Glades.")
	var rebuilding_stage: Dictionary = get_current_stage("rebuilding_glenbrook")
	if not rebuilding_stage.is_empty() and rebuilding_stage.get("id", "") != "complete":
		return rebuilding_stage.get("objective", "")
	return "Glenbrook is safer now. Talk to its people -- there's always more to hear."


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
		if met:
			_advance_quest(qid, idx + 1)


## Force-advances a quest by one stage iff it is currently sitting at expected_stage_index.
## Used for stages whose "advance_condition" is really just narrative (e.g. stage 0's objective
## is simply "talk to Garrick") rather than a checkable kill_count/dialogue_flag.
func force_advance_if_at_stage(qid: String, expected_stage_index: int) -> bool:
	if get_current_stage_index(qid) != expected_stage_index:
		return false
	_advance_quest(qid, expected_stage_index + 1)
	return true


func _advance_quest(qid: String, new_stage_index: int) -> void:
	var stages: Array = quest_defs.get(qid, {}).get("stages", [])
	quest_progress[qid] = new_stage_index
	if new_stage_index < stages.size():
		var stage: Dictionary = stages[new_stage_index]
		EventBus.quest_updated.emit(qid, new_stage_index, stage.get("objective", ""))
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
	if rewards.has("unlock_recipe"):
		unlocked_recipes[rewards["unlock_recipe"]] = true
	if rewards.has("unlock_recipe_for_active_class"):
		var pattern: String = rewards["unlock_recipe_for_active_class"]
		unlocked_recipes[pattern % active_class] = true


func add_item(item_id: String, count: int = 1) -> void:
	inventory[item_id] = int(inventory.get(item_id, 0)) + count


func remove_item(item_id: String, count: int = 1) -> bool:
	var have := int(inventory.get(item_id, 0))
	if have < count:
		return false
	inventory[item_id] = have - count
	if inventory[item_id] <= 0:
		inventory.erase(item_id)
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
