extends RefCounted
## Language-understanding half of the local dialogue engine: loads data/lore.json, compiles
## keyword/phrase tables, normalises + typo-corrects player text, extracts entities (NPCs,
## regions, landmarks, items, enemies, quests), scores intents and topics.

const T = preload("res://scripts/DialogueText.gd")
const LORE_PATH := "res://data/lore.json"
const WORLD_LORE_PATH := "res://data/lore_world.json"

## Order doubles as tie-break priority (earlier wins ties).
const INTENT_ORDER := [
	"threat", "insult", "apology", "farewell", "greeting", "thanks", "compliment",
	"ask_hint", "ask_help", "ask_self", "ask_here", "ask_person", "ask_place", "ask_item",
	"ask_enemy", "ask_secret", "rumors", "trade", "ask_advice", "smalltalk_how", "joke",
	"story", "gossip_player", "ask_topic", "more", "yes", "no",
]
const SOCIAL := ["greeting", "farewell", "thanks", "yes", "no", "apology"]
const PRONOUNS := ["he", "she", "him", "her", "they", "them", "it", "there", "hes", "shes"]

var lore: Dictionary = {}
var profiles: Dictionary = {}
var built: bool = false

var norm_map: Dictionary = {}
var fillers: Dictionary = {}
var stop: Dictionary = {}
var class_words: Dictionary = {}
var intent_tbl: Dictionary = {}   # intent -> Array[{s, w}]
var topic_tbl: Dictionary = {}    # topic -> Array[{s, w}]
var entities: Array = []          # {type, id, s, w}
var intent_words: Dictionary = {}
var vocab_set: Dictionary = {}
var vocab_stems: Dictionary = {}
var vocab_by_len: Dictionary = {}
var corr_cache: Dictionary = {}
var _split_re: RegEx = RegEx.new()


func build(p_profiles: Dictionary) -> void:
	profiles = p_profiles
	lore = _load_json(LORE_PATH)
	var world: Dictionary = _load_json(WORLD_LORE_PATH)
	for k in ["regions", "landmarks", "enemies", "items"]:
		lore[k] = world.get(k, {})
	_split_re.compile("[^a-z0-9]+")
	norm_map = lore.get("normalize", {})
	for w in lore.get("fillers", []):
		fillers[str(w)] = true
	for w in lore.get("common_words", []):
		stop[str(w)] = true
	class_words = lore.get("class_words", {})
	_apply_regions_module()
	_compile_intents()
	_compile_topics()
	_compile_entities()
	_build_vocab()
	built = true


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Missing data file: %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## Optional integration with the world agent's Regions script so names stay identical to the HUD.
func _apply_regions_module() -> void:
	if not ResourceLoader.exists("res://scripts/Regions.gd"):
		return
	var R: Variant = load("res://scripts/Regions.gd")
	if R == null:
		return
	var regs: Dictionary = lore.get("regions", {})
	for rid in regs.keys():
		var d: Variant = R.get_region(rid) if R.has_method("get_region") else null
		if typeof(d) == TYPE_DICTIONARY and str(d.get("name", "")) != "":
			regs[rid]["name"] = str(d["name"])
	if R.has_method("landmarks"):
		var lms: Variant = R.landmarks()
		var lore_lms: Dictionary = lore.get("landmarks", {})
		var items: Array = []
		if typeof(lms) == TYPE_ARRAY:
			items = lms
		elif typeof(lms) == TYPE_DICTIONARY:
			for k in lms.keys():
				var v: Variant = lms[k]
				if typeof(v) == TYPE_DICTIONARY:
					var dd: Dictionary = v.duplicate()
					if not dd.has("id"):
						dd["id"] = k
					items.append(dd)
		for it in items:
			if typeof(it) == TYPE_DICTIONARY:
				var lid: String = str(it.get("id", ""))
				if lore_lms.has(lid) and str(it.get("name", "")) != "":
					lore_lms[lid]["name"] = str(it["name"])


# ---------------------------------------------------------------- compile

func phrase_key(phrase: String) -> String:
	var toks: Array = _basic_tokens(phrase)
	var stems: Array = []
	for t in toks:
		stems.append(T.stem(str(t)))
	return " " + " ".join(stems) + " "


func _weight_of(phrase_key_str: String) -> float:
	var n: int = phrase_key_str.strip_edges().split(" ", false).size()
	return 1.0 if n <= 1 else 1.5 + 0.5 * float(n - 1)


func _compile_list(phrases: Array) -> Array:
	var out: Array = []
	for p in phrases:
		var k: String = phrase_key(str(p))
		if k.strip_edges() == "":
			continue
		out.append({"s": k, "w": _weight_of(k)})
	return out


func _compile_intents() -> void:
	var intents: Dictionary = lore.get("intents", {})
	for k in intents.keys():
		intent_tbl[k] = _compile_list(intents[k])
		for p in intents[k]:
			for w in _basic_tokens(str(p)):
				intent_words[str(w)] = true


func _compile_topics() -> void:
	var topics: Dictionary = lore.get("topics", {})
	for k in topics.keys():
		topic_tbl[k] = _compile_list(topics[k].get("keys", []))


func _add_entity(type: String, id: String, phrases: Array) -> void:
	for p in phrases:
		var k: String = phrase_key(str(p))
		if k.strip_edges() == "":
			continue
		entities.append({"type": type, "id": id, "s": k, "w": k.strip_edges().split(" ", false).size()})


func _compile_entities() -> void:
	entities.clear()
	for nid in profiles.keys():
		var p: Dictionary = profiles[nid]
		var names: Array = []
		var full: String = str(p.get("name", ""))
		names.append(full)
		for part in full.split(" ", false):
			if str(part).length() >= 3 and not ["old", "the", "brother", "captain", "reeve", "hermit"].has(str(part).to_lower()):
				names.append(str(part))
		for a in p.get("aliases", []):
			names.append(str(a))
		_add_entity("npc", nid, names)
	for rid in lore.get("regions", {}).keys():
		var r: Dictionary = lore["regions"][rid]
		var rn: Array = [str(r.get("name", ""))]
		rn.append_array(r.get("keys", []))
		_add_entity("region", rid, rn)
	for lid in lore.get("landmarks", {}).keys():
		var l: Dictionary = lore["landmarks"][lid]
		var ln: Array = [str(l.get("name", ""))]
		ln.append_array(l.get("keys", []))
		_add_entity("landmark", lid, ln)
	var enemies_lore: Dictionary = lore.get("enemies", {})
	var enemy_ids: Dictionary = {}
	for eid in enemies_lore.keys():
		enemy_ids[eid] = true
	for eid in GameState.enemy_defs.keys():
		enemy_ids[eid] = true
	for eid in enemy_ids.keys():
		var en: Array = [str(eid).replace("_", " ")]
		en.append(str(GameState.enemy_defs.get(eid, {}).get("name", "")))
		en.append_array(enemies_lore.get(eid, {}).get("keys", []))
		_add_entity("enemy", eid, en)
	var items_lore: Dictionary = lore.get("items", {})
	var item_ids: Dictionary = {}
	for iid in items_lore.keys():
		item_ids[iid] = true
	for iid in GameState.item_defs.keys():
		item_ids[iid] = true
	for iid in item_ids.keys():
		var itn: Array = [str(iid).replace("_", " ")]
		itn.append(str(GameState.item_defs.get(iid, {}).get("name", "")))
		itn.append_array(items_lore.get(iid, {}).get("keys", []))
		_add_entity("item", iid, itn)


func _build_vocab() -> void:
	vocab_set.clear()
	vocab_stems.clear()
	vocab_by_len.clear()
	var words: Dictionary = {}
	for w in intent_words.keys():
		words[w] = true
	for tk in topic_tbl.keys():
		for e in topic_tbl[tk]:
			for w in str(e["s"]).strip_edges().split(" ", false):
				words[str(w)] = true
	for e in entities:
		for w in str(e["s"]).strip_edges().split(" ", false):
			words[str(w)] = true
	for w in words.keys():
		var ws: String = str(w)
		vocab_stems[ws] = true
		if ws.length() >= 5 and not stop.has(ws):
			vocab_set[ws] = true
			var l: int = ws.length()
			if not vocab_by_len.has(l):
				vocab_by_len[l] = []
			vocab_by_len[l].append(ws)


# ---------------------------------------------------------------- normalise

func _basic_tokens(text: String) -> Array:
	var t: String = text.to_lower().replace("'", "").replace("’", "")
	t = _split_re.sub(t, " ", true)
	var out: Array = []
	for w in t.split(" ", false):
		var ws: String = str(w)
		if norm_map.has(ws):
			for x in str(norm_map[ws]).split(" ", false):
				out.append(str(x))
		else:
			out.append(ws)
	return out


func _correct(tok: String) -> String:
	if tok.length() < 5 or stop.has(tok) or vocab_set.has(tok):
		return tok
	if vocab_stems.has(T.stem(tok)):
		return tok
	if corr_cache.has(tok):
		return str(corr_cache[tok])
	var tol: int = 1 if tok.length() <= 8 else 2
	var best: String = tok
	var bestd: int = tol + 1
	for l in range(tok.length() - tol, tok.length() + tol + 1):
		if not vocab_by_len.has(l):
			continue
		for w in vocab_by_len[l]:
			var d: int = T.edit_distance(tok, str(w), tol)
			if d < bestd:
				bestd = d
				best = str(w)
	corr_cache[tok] = best
	return best


func normalize(text: String) -> Array:
	var clipped: String = text.substr(0, 280)
	var raw: Array = _basic_tokens(clipped)
	var out: Array = []
	for t in raw:
		var ts: String = str(t)
		if fillers.has(ts):
			continue
		out.append(_correct(ts))
		if out.size() >= 40:
			break
	return out


# ---------------------------------------------------------------- analyse

func _score_list(tbl: Array, padded: String) -> float:
	var best: float = 0.0
	var total: float = 0.0
	for e in tbl:
		if padded.find(str(e["s"])) != -1:
			var w: float = float(e["w"])
			total += w
			best = maxf(best, w)
	return best + 0.25 * (total - best)


func analyze(text: String, quest_titles: Array = []) -> Dictionary:
	var toks: Array = normalize(text)
	var stems: Array = []
	for t in toks:
		stems.append(T.stem(str(t)))
	var padded: String = " " + " ".join(stems) + " "
	var n: int = toks.size()
	var res: Dictionary = {
		"tokens": toks, "n": n, "padded": padded, "intent": "unknown", "where": false, "tell_q": false,
		"entities": {"npc": [], "region": [], "landmark": [], "item": [], "enemy": [], "quest": []},
		"topic": "", "subject": "", "class_fact": "", "name_fact": "", "pronoun": false, "scores": {},
	}
	if n == 0:
		return res

	var sc: Dictionary = {}
	for intent in intent_tbl.keys():
		sc[intent] = _score_list(intent_tbl[intent], padded)
	res["where"] = float(sc.get("where_q", 0.0)) > 0.0
	res["tell_q"] = float(sc.get("tell_q", 0.0)) > 0.0

	# entities
	var ents: Dictionary = res["entities"]
	var ent_w: Dictionary = {}
	for e in entities:
		if padded.find(str(e["s"])) != -1:
			var key: String = "%s:%s" % [e["type"], e["id"]]
			ent_w[key] = maxf(float(ent_w.get(key, 0.0)), float(e["w"]))
	var keys: Array = ent_w.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return float(ent_w[a]) > float(ent_w[b]))
	for k in keys:
		var parts: PackedStringArray = str(k).split(":")
		ents[parts[0]].append(parts[1])
	for q in quest_titles:
		var words: Array = []
		for w in str(q.get("title", "")).to_lower().split(" ", false):
			var cw: String = "".join(_basic_tokens(str(w)))
			if cw.length() > 3 and not stop.has(cw):
				words.append(T.stem(cw))
		var hit: int = 0
		for w in words:
			if padded.find(" " + str(w) + " ") != -1:
				hit += 1
		if words.size() > 0 and hit >= mini(words.size(), 2):
			ents["quest"].append(str(q.get("quest_id", "")))
	if not ents["npc"].is_empty():
		sc["ask_person"] = float(sc.get("ask_person", 0.0)) + 3.2
	if not ents["region"].is_empty() or not ents["landmark"].is_empty():
		sc["ask_place"] = float(sc.get("ask_place", 0.0)) + 3.2
	if not ents["item"].is_empty():
		sc["ask_item"] = float(sc.get("ask_item", 0.0)) + 3.8
	if not ents["enemy"].is_empty():
		sc["ask_enemy"] = float(sc.get("ask_enemy", 0.0)) + 3.8
	if not ents["quest"].is_empty():
		sc["ask_help"] = float(sc.get("ask_help", 0.0)) + 3.4

	# topics
	var best_topic: String = ""
	var best_ts: float = 0.0
	var tscores: Dictionary = {}
	for tk in topic_tbl.keys():
		var s: float = _score_list(topic_tbl[tk], padded)
		if s > 0.0:
			tscores[tk] = s
			if s > best_ts:
				best_ts = s
				best_topic = tk
	res["topic"] = best_topic
	res["topic_scores"] = tscores
	if best_topic != "":
		sc["ask_topic"] = 1.7 * best_ts

	# boosts / demotions
	for k in ["threat", "insult", "compliment"]:
		sc[k] = float(sc.get(k, 0.0)) * 1.3
	for k in SOCIAL:
		var v: float = float(sc.get(k, 0.0))
		if n > 8:
			v *= 0.2
		elif n > 4:
			v *= 0.45
		sc[k] = v
	if n > 3:
		sc["yes"] = float(sc.get("yes", 0.0)) * 0.3
		sc["no"] = float(sc.get("no", 0.0)) * 0.3
	if n > 6:
		sc["more"] = float(sc.get("more", 0.0)) * 0.4

	var bi: String = "unknown"
	var bs: float = 0.99
	for intent in INTENT_ORDER:
		var v2: float = float(sc.get(intent, 0.0))
		if v2 > bs:
			bs = v2
			bi = intent
	res["intent"] = bi
	res["scores"] = sc
	for t in toks:
		if PRONOUNS.has(str(t)):
			res["pronoun"] = true

	_extract_facts(res, toks)
	if bi == "unknown" or bi == "ask_topic" or bi == "ask_person" or bi == "ask_place":
		res["subject"] = _subject(toks)
	# facts override mid-strength intents
	if res["class_fact"] != "" or res["name_fact"] != "":
		if bi in ["unknown", "ask_topic", "yes", "no", "gossip_player", "ask_item", "more", "ask_self"]:
			res["intent"] = "tell_fact"
	return res


func _subject(toks: Array) -> String:
	var cands: Array = []
	for t in toks:
		var ts: String = str(t)
		if ts.length() >= 3 and not stop.has(ts) and not intent_words.has(ts):
			cands.append(ts)
	if cands.is_empty() or cands.size() > 4:
		return ""
	if cands.size() > 2:
		cands = cands.slice(cands.size() - 2)
	return " ".join(cands)


func _extract_facts(res: Dictionary, toks: Array) -> void:
	var n: int = toks.size()
	for i in range(n):
		var t: String = str(toks[i])
		var j: int = -1
		if t == "i" and i + 3 < n and str(toks[i + 1]) == "am" and str(toks[i + 2]) == "called":
			res["name_fact"] = str(toks[i + 3])
			continue
		if t == "i" and i + 1 < n and ["am", "play", "fight", "use", "be"].has(str(toks[i + 1])):
			j = i + 2
		elif t == "my" and i + 2 < n and str(toks[i + 1]) == "class" and str(toks[i + 2]) == "is":
			j = i + 3
		elif t == "i" and i + 2 < n and str(toks[i + 1]) == "am" and str(toks[i + 2]) == "called" and i + 3 < n:
			res["name_fact"] = str(toks[i + 3])
			continue
		elif t == "my" and i + 3 < n and str(toks[i + 1]) == "name" and str(toks[i + 2]) == "is":
			res["name_fact"] = str(toks[i + 3])
			continue
		elif t == "call" and i + 1 < n and str(toks[i + 1]) == "me" and i + 2 < n:
			res["name_fact"] = str(toks[i + 2])
			continue
		if j >= 0:
			while j < n and ["a", "an", "the", "as", "just", "now", "also", "playing"].has(str(toks[j])):
				j += 1
			if j < n:
				var w1: String = str(toks[j])
				var w2: String = w1 + " " + (str(toks[j + 1]) if j + 1 < n else "")
				if class_words.has(w2.strip_edges()):
					res["class_fact"] = str(class_words[w2.strip_edges()])
				elif class_words.has(w1):
					res["class_fact"] = str(class_words[w1])
	var nm: String = str(res["name_fact"])
	if nm != "" and (nm.length() < 2 or nm.length() > 16 or stop.has(nm) or intent_words.has(nm)):
		res["name_fact"] = ""
