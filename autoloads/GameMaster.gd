extends Node
## GameMaster: local stand-in for the "Lead World Master" LLM.
##
## process_dialogue(npc_id, player_input) returns the same strict shape a real model call
## would return:
##   { "dialogue", "npc_mood", "generated_lore_snippet": String|null, "game_actions": Array,
##     "chips": Array[{label, say}], "end": bool }
## The words themselves come from the token-free DialogueEngine (language understanding +
## data-driven NPC profiles + persistent per-NPC memory). The legacy quest hooks below
## still drive the original Glenbrook storyline and override the engine's reply when they fire.
##
## USE_REAL_API is the seam for a future Anthropic call: flip it on, implement
## _call_real_api(), and nothing upstream (NPC.gd / DialogueUI.gd) has to change.

const DialogueEngineScript = preload("res://scripts/DialogueEngine.gd")

const NPCS_PATH := "res://data/npcs.json"
const WHISPERS_QUEST_ID := "whispers_in_the_glade"
const REBUILDING_QUEST_ID := "rebuilding_glenbrook"
const USE_REAL_API := false

var npc_profiles: Dictionary = {}
var engine: RefCounted = null


func _ready() -> void:
	npc_profiles = _load_npcs()
	engine = DialogueEngineScript.new()
	engine.setup(npc_profiles)


func process_dialogue(npc_id: String, player_input: String) -> Dictionary:
	var profile: Dictionary = npc_profiles.get(npc_id, {})
	if profile.is_empty():
		return {"dialogue": "...", "npc_mood": "Neutral", "generated_lore_snippet": null, "game_actions": [], "chips": [], "end": true}

	if USE_REAL_API:
		var remote: Dictionary = _call_real_api(npc_id, player_input)
		if not remote.is_empty():
			return remote

	var text: String = player_input.strip_edges().to_lower()
	var hook: Dictionary = _try_quest_hooks(npc_id, text)
	var out: Dictionary = engine.respond(npc_id, player_input, hook)
	var snippet: String = str(out.get("lore_snippet", ""))
	return {
		"dialogue": str(out.get("text", "...")),
		"npc_mood": str(out.get("mood", "Neutral")),
		"generated_lore_snippet": snippet if snippet != "" else null,
		"game_actions": out.get("actions", []),
		"chips": out.get("chips", []),
		"end": bool(out.get("end", false)),
	}


## Placeholder for the real-model call; must return the same Dictionary shape or {} to fall back.
func _call_real_api(_npc_id: String, _player_input: String) -> Dictionary:
	return {}


## Legacy storyline hooks. `text` is "" when the dialogue has just been opened, so quest
## stages that only need a visit or already-held items advance without any typing.
## Returns {dialogue, npc_mood, game_actions} to override the engine, or {}.
func _try_quest_hooks(npc_id: String, text: String) -> Dictionary:
	var opened: bool = text == ""

	if npc_id == "garrick_hale" and GameState.get_current_stage_index(WHISPERS_QUEST_ID) == 0:
		GameState.force_advance_if_at_stage(WHISPERS_QUEST_ID, 0)
		return _hook("Garrick grunts. \"Wolves have been coming out of the Glades wrong -- teeth bared at shadows, snapping in broad daylight. Not natural. Go kill a few, bring me proof of what's on 'em, and maybe I'll believe you're worth listening to.\"", "Neutral", [
			{"action_type": "update_quest", "target_id": WHISPERS_QUEST_ID, "value": "investigate_wolves"}])

	if npc_id == "garrick_hale" and GameState.get_current_stage_index(WHISPERS_QUEST_ID) == 2 and (opened or _has_any(text, ["proof", "wolves", "report", "here", "found"])):
		if GameState.get_kill_count("dire_wolf") >= 3:
			GameState.set_story_flag("reported_wolf_proof_to_garrick", true)
			GameState.grant_exp(GameState.active_class, 50)
			return _hook("Garrick examines the claw marks grimly. \"...Aye. That's not hunger, that's something driving them mad. Talk to Mira -- she knows more about the old things buried out here than she lets on.\"", "Suspicious", [
				{"action_type": "update_quest", "target_id": WHISPERS_QUEST_ID, "value": "report_to_garrick"},
				{"action_type": "grant_exp", "target_id": GameState.active_class, "value": 50}])
		if not opened:
			return _hook("\"You don't have enough proof yet. Get back out there and deal with more of those wolves.\"", "Neutral", [])

	if npc_id == "mira_thistlewood" and GameState.get_current_stage("mira_remedy").get("id", "") == "deliver_herbs" and (opened or _has_any(text, ["herb", "brought", "here", "delivered", "remedy", "poultice"])):
		if GameState.remove_item("healing_herb", 3):
			GameState.set_story_flag("delivered_herbs", true)
			return _hook("Mira's eyes brighten as she counts the leaves. \"Fresh, and no blight on them. You've a gardener's hands under all that steel, dear. Here -- a stew for the road.\"", "Friendly", [
				{"action_type": "update_quest", "target_id": "mira_remedy", "value": "complete"}])
		if not opened:
			return _hook("\"I only count fewer than three herbs on you, dear. Look for the bright green patches in the grass.\"", "Neutral", [])

	if npc_id == "garrick_hale" and GameState.get_current_stage("hunters_bounty").get("id", "") == "deliver_tusks" and (opened or _has_any(text, ["tusk", "brought", "here", "bounty", "delivered", "boar"])):
		if GameState.remove_item("boar_tusk", 3):
			GameState.set_story_flag("delivered_tusks", true)
			return _hook("Garrick turns a tusk over and actually smiles. \"Clean kills. Coin's tight, so take this -- and my respect, for what it's worth.\"", "Friendly", [
				{"action_type": "update_quest", "target_id": "hunters_bounty", "value": "complete"}])
		if not opened:
			return _hook("\"Three tusks. I count fewer. Boars in the south -- go on.\"", "Neutral", [])

	if npc_id == "old_ferris" and GameState.get_current_stage_index(REBUILDING_QUEST_ID) == 0:
		GameState.force_advance_if_at_stage(REBUILDING_QUEST_ID, 0)
		return _hook("Ferris nods slowly. \"Heard you're the one who cleared that camp. That shard fragment you picked up off Skar -- bring it here sometime. Metal that runs warm like that, I want to see what it's good for.\"", "Friendly", [
			{"action_type": "update_quest", "target_id": REBUILDING_QUEST_ID, "value": "bring_shard"}])

	if npc_id == "old_ferris" and GameState.get_current_stage_index(REBUILDING_QUEST_ID) == 1 and (opened or _has_any(text, ["shard", "fragment", "bloodstone", "here", "take it", "brought"])):
		if GameState.remove_item("bloodstone_shard_fragment", 1):
			GameState.set_story_flag("gave_shard_to_ferris", true)
			return _hook("Ferris turns the shard fragment over in his tongs, eyes narrowing at the heat coming off it. \"Strange stuff. Give me a day and I'll have something worth wearing out of this. Come back and I'll have new gear fitted to whatever you're playing at these days.\"", "Friendly", [
				{"action_type": "update_quest", "target_id": REBUILDING_QUEST_ID, "value": "complete"}])
		if not opened:
			return _hook("\"You don't seem to be carrying it on you. Bring me the Bloodstone Shard fragment when you've got it.\"", "Neutral", [])

	return {}


func _hook(dialogue: String, mood: String, actions: Array) -> Dictionary:
	return {"dialogue": dialogue, "npc_mood": mood, "game_actions": actions}


func _has_any(text: String, needles: Array) -> bool:
	for n in needles:
		if text.find(String(n)) != -1:
			return true
	return false


func _load_npcs() -> Dictionary:
	if not FileAccess.file_exists(NPCS_PATH):
		push_warning("Missing data file: %s" % NPCS_PATH)
		return {}
	var file := FileAccess.open(NPCS_PATH, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	var result := {}
	if typeof(parsed) == TYPE_DICTIONARY:
		for npc in parsed.get("npcs", []):
			result[npc["npc_id"]] = npc
	return result
