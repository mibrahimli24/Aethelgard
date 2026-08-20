extends Node
## GameMaster: a rule-based stand-in for the "Lead World Master" LLM described in the spec.
##
## process_dialogue(npc_id, player_input) takes the same conceptual inputs a real Claude call
## would receive -- a DYNAMIC_NPC_PROFILE (loaded from data/npcs.json) plus the live
## DYNAMIC_PLAYER_STATE (read straight from the GameState autoload) plus free-text player
## input -- and returns a Dictionary shaped EXACTLY like the strict JSON contract from the
## spec's output-format section:
##   { "dialogue": String, "npc_mood": String, "generated_lore_snippet": String|null,
##     "game_actions": Array[{action_type, target_id, value}] }
##
## Swapping this module for a real Anthropic API call later should not require changing any
## caller -- NPC.gd / DialogueUI.gd only ever see this Dictionary shape, never GameMaster's
## internals. Ledger mutations (rapport, story flags, exp, items) are applied here directly
## rather than round-tripped through a generic action executor, since this single-process
## prototype has no separate backend process to do that validation step; the returned
## game_actions[] is still the authoritative, inspectable record of "what happened" that
## DialogueUI/World react to (e.g. World listens for spawn_camp / trigger_boss_fight).
##
## PHASING NOTE (this is "Phase 1"): everything below is deterministic and data-driven --
## keyword matching, rapport counters, no-repeat rotation, and a couple of hardcoded quest
## hooks. A real "Phase 2" would replace only the body of process_dialogue() with an actual
## Anthropic API call (still fed the npc profile + a GameState snapshot + player_input, still
## returning this exact Dictionary shape) -- USE_REAL_API is that seam, switched off until an
## API key and network layer exist. Everything upstream/downstream of this file already
## assumes nothing more than "a Dictionary with this shape comes back eventually," so Phase 2
## is additive, not a rewrite.

const NPCS_PATH := "res://data/npcs.json"
const WHISPERS_QUEST_ID := "whispers_in_the_glade"
const REBUILDING_QUEST_ID := "rebuilding_glenbrook"
const USE_REAL_API := false

const CASUAL_TOPIC_SYNONYMS := {
	"weather": ["weather", "rain", "storm", "cold", "mist", "fog"],
	"crafting": ["craft", "forge", "smith", "armor", "weapon", "ore"],
	"life": ["who are you", "your life", "how long have you", "yourself", "your story"],
	"quest_hint": ["what should i do", "help me", "what now", "any advice", "hint", "what next"],
	"village": ["glenbrook", "village", "the hollow", "this town"],
	"opinion_of_player": ["what do you think of me", "do you trust me", "about me"],
	"rumor": ["rumor", "rumour", "gossip", "heard anything", "any news"],
	"aftermath": ["camp now", "rebuilding", "safer now", "since skar", "after the fight", "aftermath"],
}

var lore_pool: Array[String] = [
	"Old Barrow was raised centuries before Glenbrook existed, by hands nobody living remembers.",
	"Herbalists say a rabbit born with red-tinted fur near the Glades is a bad omen -- the beasts sense the Bloodstone before people do.",
	"Some Glenbrook children swear the Whispering Glades got their name because the trees repeat the last words of anyone lost in them.",
	"Copper veins near the Old Barrow run warm to the touch, though no one's found a reason why.",
	"A wandering tinker once claimed the Red Fang Clan used to be simple trappers, decades before Skar ever led them.",
	"The well at the heart of Glenbrook Hollow never freezes, even in the hardest winters -- nobody's dug deep enough to find out why.",
	"Every generation, one Glenbrook child is born who can't stand the smell of the Glades' night-blooming moss. The old folk call it 'the warning nose.'",
	"A retired trader once swore he saw lights moving inside Old Barrow at night, long before anyone knew Skar had made a home of it.",
	"The dire wolves of the Whispering Glades used to keep their distance from Glenbrook entirely -- some say the Bloodstone is the only thing that ever changed that.",
	"There's a cairn past the tree line nobody in Glenbrook will name. Ask an elder and they change the subject.",
	"Glenbrook's gate used to have a second, smaller door built into it -- for messengers, some say, or for something else entirely.",
	"The Old Barrow ridge is higher than the maps say. Nobody's corrected the maps; the ridge doesn't like being measured, or so the joke goes.",
]

var epilogue_lore_pool: Array[String] = [
	"Since Skar fell, the Old Barrow's gone quiet in a way even the elders admit they've never heard before.",
	"Traders have started using the old road past the ridge again, now that the Red Fang name doesn't mean anything out here anymore.",
	"Some say the Bloodstone Shard's heat fades a little more each week, now that it's split from whatever whole it used to be part of.",
	"Glenbrook's put up a new marker near the well for the patrol Garrick lost, all those years back. Overdue, most agree.",
]

var npc_profiles: Dictionary = {}
var _lore_already_told: Dictionary = {} # npc_id -> Array[int] indices already surfaced (lore_pool)
var _epilogue_lore_already_told: Dictionary = {} # npc_id -> Array[int] indices (epilogue_lore_pool)
var _follow_up_index: Dictionary = {} # npc_id -> next index into follow_up_lines, rotates in order
var _lang_regex := RegEx.new()


func _ready() -> void:
	npc_profiles = _load_npcs()
	_lang_regex.compile("[a-zA-Z]")


func process_dialogue(npc_id: String, player_input: String) -> Dictionary:
	var profile: Dictionary = npc_profiles.get(npc_id, {})
	if profile.is_empty():
		return {
			"dialogue": "...",
			"npc_mood": "Neutral",
			"generated_lore_snippet": null,
			"game_actions": [],
		}

	var text := player_input.strip_edges().to_lower()

	if text == "":
		return _greeting_response(profile)

	GameState.increment_rapport(npc_id, 1)

	# Edge-case safety (spec 5.3): nonsensical input gets an in-character confused reply.
	if _lang_regex.search(text) == null:
		return {
			"dialogue": "%s squints at you. \"...What in the world are you on about?\"" % profile.get("name", "The stranger"),
			"npc_mood": "Neutral",
			"generated_lore_snippet": null,
			"game_actions": [],
		}

	if _contains_any(text, ["kill you", "attack you", "i'll murder", "die, "]):
		return {
			"dialogue": "%s recoils, hand on their belt. \"Touch me and you'll regret it!\"" % profile.get("name", "The stranger"),
			"npc_mood": "Hostile",
			"generated_lore_snippet": null,
			"game_actions": [],
		}

	var quest_result := _try_quest_hooks(npc_id, profile, text)
	if not quest_result.is_empty():
		return quest_result

	# Story Gating (spec 3): only reveal hidden_knowledge once the player mentions the right
	# topic AND has built enough rapport AND (if required) hit the right quest flag.
	if profile.has("trigger_keywords") and _contains_any(text, profile["trigger_keywords"]):
		return _try_reveal_secret(npc_id, profile)

	# Non-Story Chat (spec 3): casual topics get a full in-character reply, no story pressure.
	var casual := _match_casual(profile, text)
	if casual != "":
		return {
			"dialogue": casual,
			"npc_mood": "Friendly",
			"generated_lore_snippet": _maybe_generate_lore(npc_id),
			"game_actions": [],
		}

	return {
		"dialogue": "%s considers your words. \"Can't say I have much to add to that.\"" % profile.get("name", "The stranger"),
		"npc_mood": "Neutral",
		"generated_lore_snippet": _maybe_generate_lore(npc_id),
		"game_actions": [],
	}


func _try_quest_hooks(npc_id: String, profile: Dictionary, text: String) -> Dictionary:
	var npc_name: String = profile.get("name", "The stranger")

	if npc_id == "garrick_hale" and GameState.get_current_stage_index(WHISPERS_QUEST_ID) == 0:
		GameState.force_advance_if_at_stage(WHISPERS_QUEST_ID, 0)
		return {
			"dialogue": "%s grunts. \"Wolves have been coming out of the Glades wrong -- teeth bared at shadows, snapping in broad daylight. Not natural. Go kill a few, bring me proof of what's on 'em, and maybe I'll believe you're worth listening to.\"" % npc_name,
			"npc_mood": "Neutral",
			"generated_lore_snippet": null,
			"game_actions": [
				{"action_type": "update_quest", "target_id": WHISPERS_QUEST_ID, "value": "investigate_wolves"},
			],
		}

	if npc_id == "garrick_hale" and GameState.get_current_stage_index(WHISPERS_QUEST_ID) == 2 and _contains_any(text, ["proof", "wolves", "report", "here", "found"]):
		if GameState.get_kill_count("dire_wolf") >= 3:
			GameState.set_story_flag("reported_wolf_proof_to_garrick", true)
			GameState.grant_exp(GameState.active_class, 50)
			return {
				"dialogue": "Garrick examines the claw marks grimly. \"...Aye. That's not hunger, that's something driving them mad. Talk to Mira -- she knows more about the old things buried out here than she lets on.\"",
				"npc_mood": "Suspicious",
				"generated_lore_snippet": null,
				"game_actions": [
					{"action_type": "update_quest", "target_id": WHISPERS_QUEST_ID, "value": "report_to_garrick"},
					{"action_type": "grant_exp", "target_id": GameState.active_class, "value": 50},
				],
			}
		else:
			return {
				"dialogue": "\"You don't have enough proof yet. Get back out there and deal with more of those wolves.\"",
				"npc_mood": "Neutral",
				"generated_lore_snippet": null,
				"game_actions": [],
			}

	if npc_id == "old_ferris" and GameState.get_current_stage_index(REBUILDING_QUEST_ID) == 0:
		GameState.force_advance_if_at_stage(REBUILDING_QUEST_ID, 0)
		return {
			"dialogue": "Ferris nods slowly. \"Heard you're the one who cleared that camp. That shard fragment you picked up off Skar -- bring it here sometime. Metal that runs warm like that, I want to see what it's good for.\"",
			"npc_mood": "Friendly",
			"generated_lore_snippet": null,
			"game_actions": [
				{"action_type": "update_quest", "target_id": REBUILDING_QUEST_ID, "value": "bring_shard"},
			],
		}

	if npc_id == "old_ferris" and GameState.get_current_stage_index(REBUILDING_QUEST_ID) == 1 and _contains_any(text, ["shard", "fragment", "bloodstone", "here", "take it", "brought"]):
		if GameState.remove_item("bloodstone_shard_fragment", 1):
			GameState.set_story_flag("gave_shard_to_ferris", true)
			return {
				"dialogue": "Ferris turns the shard fragment over in his tongs, eyes narrowing at the heat coming off it. \"Strange stuff. Give me a day and I'll have something worth wearing out of this. Come back and I'll have new gear fitted to whatever you're playing at these days.\"",
				"npc_mood": "Friendly",
				"generated_lore_snippet": null,
				"game_actions": [
					{"action_type": "update_quest", "target_id": REBUILDING_QUEST_ID, "value": "complete"},
				],
			}
		else:
			return {
				"dialogue": "\"You don't seem to be carrying it on you. Bring me the Bloodstone Shard fragment when you've got it.\"",
				"npc_mood": "Neutral",
				"generated_lore_snippet": null,
				"game_actions": [],
			}

	return {}


func _try_reveal_secret(npc_id: String, profile: Dictionary) -> Dictionary:
	var reveal_flag: String = profile.get("reveal_story_flag", "")
	if reveal_flag != "" and GameState.has_story_flag(reveal_flag):
		return _already_revealed_response(npc_id, profile)

	var npc_name: String = profile.get("name", "The stranger")
	var threshold: int = int(profile.get("rapport_threshold_for_secret", 999))
	var required_flag = profile.get("requires_quest_flag", null)
	var rapport_ok: bool = GameState.get_rapport(npc_id) >= threshold
	var flag_ok: bool = required_flag == null or GameState.has_story_flag(required_flag)

	if rapport_ok and flag_ok:
		var actions: Array = []
		if reveal_flag != "":
			GameState.set_story_flag(reveal_flag, true)
			actions.append({"action_type": "update_quest", "target_id": WHISPERS_QUEST_ID, "value": reveal_flag})
		if profile.has("reveal_spawns_camp"):
			var camp_id: String = profile["reveal_spawns_camp"]
			GameState.set_story_flag("camp_%s_spawned" % camp_id, true)
			actions.append({"action_type": "spawn_camp", "target_id": camp_id, "value": "revealed"})
		return {
			"dialogue": "%s leans in, voice dropping low. \"%s\"" % [npc_name, profile.get("hidden_knowledge", "")],
			"npc_mood": "Suspicious",
			"generated_lore_snippet": null,
			"game_actions": actions,
		}
	elif not flag_ok:
		return {
			"dialogue": "%s shakes their head. \"There's more to that, but not yet -- ask Garrick Hale about the wolves first.\"" % npc_name,
			"npc_mood": "Suspicious",
			"generated_lore_snippet": null,
			"game_actions": [],
		}
	else:
		return {
			"dialogue": "%s eyes you warily. \"I don't know you well enough to speak on that yet. Talk with me a bit more.\"" % npc_name,
			"npc_mood": "Suspicious",
			"generated_lore_snippet": null,
			"game_actions": [],
		}


## Once a secret's already been revealed, repeating its trigger keywords used to replay the
## exact same monologue forever -- the concrete mechanism behind "NPCs don't have much to say"
## once a quest wraps up. Now it rotates through a small bank of shorter, less dramatic
## follow-up lines instead (an epilogue-flavored bank once game_phase flips).
func _already_revealed_response(npc_id: String, profile: Dictionary) -> Dictionary:
	var pool: Array = []
	if GameState.game_phase == "Rebuilding_Era":
		pool = profile.get("epilogue_follow_up_lines", [])
	if pool.is_empty():
		pool = profile.get("follow_up_lines", [])
	var npc_name: String = profile.get("name", "The stranger")
	if pool.is_empty():
		return {
			"dialogue": "%s has already told you what they know about that." % npc_name,
			"npc_mood": "Neutral",
			"generated_lore_snippet": null,
			"game_actions": [],
		}
	var idx: int = int(_follow_up_index.get(npc_id, 0)) % pool.size()
	_follow_up_index[npc_id] = idx + 1
	return {
		"dialogue": pool[idx],
		"npc_mood": "Neutral",
		"generated_lore_snippet": _maybe_generate_lore(npc_id),
		"game_actions": [],
	}


func _match_casual(profile: Dictionary, text: String) -> String:
	var casual: Dictionary = profile.get("casual_keywords", {})
	var epilogue_casual: Dictionary = profile.get("epilogue_casual_keywords", {})
	var in_epilogue: bool = GameState.game_phase == "Rebuilding_Era"
	for topic in CASUAL_TOPIC_SYNONYMS.keys():
		if not _contains_any(text, CASUAL_TOPIC_SYNONYMS[topic]):
			continue
		if in_epilogue and epilogue_casual.has(topic):
			return _pick_variant(epilogue_casual[topic])
		if casual.has(topic):
			return _pick_variant(casual[topic])
	return ""


func _pick_variant(value) -> String:
	if typeof(value) == TYPE_ARRAY:
		var arr: Array = value
		if arr.is_empty():
			return ""
		return String(arr[randi() % arr.size()])
	return String(value)


func _maybe_generate_lore(npc_id: String):
	if randf() > 0.35:
		return null
	if GameState.game_phase == "Rebuilding_Era":
		var epilogue_pick = _pick_no_repeat(epilogue_lore_pool, _epilogue_lore_already_told, npc_id)
		if epilogue_pick != null:
			return epilogue_pick
	return _pick_no_repeat(lore_pool, _lore_already_told, npc_id)


func _pick_no_repeat(pool: Array, told_map: Dictionary, npc_id: String):
	var told: Array = told_map.get(npc_id, [])
	var candidates: Array = []
	for i in pool.size():
		if not told.has(i):
			candidates.append(i)
	if candidates.is_empty():
		return null
	var pick: int = candidates[randi() % candidates.size()]
	told.append(pick)
	told_map[npc_id] = told
	return pool[pick]


func _greeting_response(profile: Dictionary) -> Dictionary:
	if GameState.game_phase == "Rebuilding_Era" and profile.has("epilogue_greeting"):
		return {
			"dialogue": profile["epilogue_greeting"],
			"npc_mood": "Friendly",
			"generated_lore_snippet": null,
			"game_actions": [],
		}
	var casual: Dictionary = profile.get("casual_keywords", {})
	return {
		"dialogue": _pick_variant(casual.get("greeting", "%s nods at you." % profile.get("name", ""))),
		"npc_mood": "Neutral",
		"generated_lore_snippet": null,
		"game_actions": [],
	}


func _contains_any(text: String, needles: Array) -> bool:
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
	var parsed = JSON.parse_string(text)
	var result := {}
	if typeof(parsed) == TYPE_DICTIONARY:
		for npc in parsed.get("npcs", []):
			result[npc["npc_id"]] = npc
	return result
