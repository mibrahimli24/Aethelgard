extends Node2D
## Ties the Whispering Glades vertical slice together. This is the one node with real scene-tree
## access, so it's where GameMaster's "physical" game_actions (spawn_camp, and the boss-fight
## stage transition) actually get realized as spawned nodes -- everything else in the mocked LLM
## pipeline only ever produces data.

const ENEMY_SCENE := preload("res://scenes/Enemy.tscn")
const BOSS_SCENE := preload("res://scenes/Boss.tscn")
const BIOME_DATA_PATH := "res://data/biome_whispering_glades.json"

@onready var camp_marker: Node2D = $CampMarker
@onready var bandit_spawn_point: Marker2D = $CampMarker/BanditSpawnPoint
@onready var boss_spawn_point: Marker2D = $CampMarker/BossSpawnPoint

var _biome_data: Dictionary = {}
var _camp_revealed := false
var _boss_spawned := false


func _ready() -> void:
	_biome_data = _load_biome_data()
	camp_marker.visible = false
	if GameState.has_story_flag("camp_red_fang_camp_spawned"):
		_camp_revealed = true
		camp_marker.visible = true
		_spawn_remaining_bandits()
	EventBus.action_dispatched.connect(_on_action_dispatched)
	EventBus.quest_updated.connect(_on_quest_updated)
	if GameState.get_current_stage("whispers_in_the_glade").get("id", "") == "boss_fight":
		_spawn_boss()


func _on_action_dispatched(action: Dictionary) -> void:
	if action.get("action_type", "") == "spawn_camp" and not _camp_revealed:
		_camp_revealed = true
		camp_marker.visible = true
		_spawn_remaining_bandits()


func _on_quest_updated(_quest_id: String, _stage: int, _objective: String) -> void:
	if GameState.get_current_stage("whispers_in_the_glade").get("id", "") == "boss_fight" and not _boss_spawned:
		_spawn_boss()


## Spawns however many camp bandits are still owed (total minus already-killed), so reloading
## a save made mid-camp-clear doesn't lose or duplicate progress -- the dynamically-added
## bandit nodes themselves aren't persisted, only the kill_count ledger is.
func _spawn_remaining_bandits() -> void:
	var camp: Dictionary = _biome_data.get("camp", {})
	var bandit_id: String = camp.get("bandit_id", "red_fang_bandit")
	var total: int = int(camp.get("bandit_count", 4))
	var remaining: int = max(0, total - GameState.get_kill_count(bandit_id))
	for i in remaining:
		var bandit := ENEMY_SCENE.instantiate()
		bandit.enemy_id = bandit_id
		bandit.display_name = "Red Fang Bandit"
		bandit.max_hp = float(camp.get("bandit_hp", 60))
		bandit.damage = float(camp.get("bandit_damage", 8))
		bandit.exp_reward = int(camp.get("bandit_exp_reward", 40))
		bandit.global_position = bandit_spawn_point.global_position + Vector2(randf_range(-70, 70), randf_range(-70, 70))
		add_child(bandit)


func _spawn_boss() -> void:
	_boss_spawned = true
	var boss := BOSS_SCENE.instantiate()
	boss.global_position = boss_spawn_point.global_position
	add_child(boss)


func _load_biome_data() -> Dictionary:
	if not FileAccess.file_exists(BIOME_DATA_PATH):
		return {}
	var file := FileAccess.open(BIOME_DATA_PATH, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
