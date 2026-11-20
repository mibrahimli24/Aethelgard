extends RefCounted
## DialogueEngine: token-free "mock LLM". Pipeline per player line:
##   normalise + typo-correct -> intent/entity/topic scoring (DialogueNLU)
##   -> handler picks NPC-profile-aware content (no-repeat, rapport-gated, state-aware)
##   -> style wrapper (openers/closers/asides/offers) -> payload for GameMaster.
## All persistent state lives in GameState.npc_memory[npc_id] (JSON-friendly).

const T = preload("res://scripts/DialogueText.gd")
const NLU = preload("res://scripts/DialogueNLU.gd")
const Geo = preload("res://scripts/Geo.gd")

var nlu = NLU.new()
var lore: Dictionary = {}
var profiles: Dictionary = {}
var _convo: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _global_turn: int = 0
var _bark_next: Dictionary = {}
var _bark_recent: Dictionary = {}
var _sec_keys: Dictionary = {}


func setup(p_profiles: Dictionary) -> void:
	profiles = p_profiles


func _ensure() -> void:
	if nlu.built:
		return
	nlu.build(profiles)
	lore = nlu.lore
	_merge_legacy_fields()


## Old npcs.json entries (mira/garrick/ferris) used casual_keywords; feed them into the new schema.
func _merge_legacy_fields() -> void:
	for nid in profiles.keys():
		var p: Dictionary = profiles[nid]
		var cas: Dictionary = p.get("casual_keywords", {})
		var tl: Dictionary = p.get("topic_lines", {})
		p["topic_lines"] = tl
		var mapping: Dictionary = {"weather": "weather", "crafting": "crafting", "quest_hint": "hint_none"}
		for ck in mapping.keys():
			if cas.has(ck) and not tl.has(mapping[ck]):
				tl[mapping[ck]] = _as_array(cas[ck])
		if cas.has("life") and not p.has("about_self"):
			p["about_self"] = _as_array(cas["life"])
		if cas.has("rumor") and not p.has("rumors"):
			p["rumors"] = _as_array(cas["rumor"])
		if cas.has("village") and not p.has("home_lines"):
			p["home_lines"] = _as_array(cas["village"])
		if cas.has("opinion_of_player") and not p.has("opinion_player"):
			p["opinion_player"] = _as_array(cas["opinion_of_player"])
		var epi: Dictionary = p.get("epilogue_casual_keywords", {})
		if epi.has("aftermath"):
			tl["aftermath"] = _as_array(epi["aftermath"])
		if not p.has("display_name"):
			p["display_name"] = p.get("name", nid)


func _plural(w: String) -> String:
	if w.ends_with("wolf"):
		return w.trim_suffix("f") + "ves"
	if w.ends_with("s") or w.ends_with("ves"):
		return w
	if w.ends_with("ch") or w.ends_with("sh") or w.ends_with("x"):
		return w + "es"
	return w + "s"


func _as_array(v: Variant) -> Array:
	if typeof(v) == TYPE_ARRAY:
		return v
	return [str(v)]


# ---------------------------------------------------------------- memory / state

func mem(npc_id: String) -> Dictionary:
	var m: Variant = GameState.npc_memory.get(npc_id, null)
	if typeof(m) != TYPE_DICTIONARY:
		m = {}
		GameState.npc_memory[npc_id] = m
	var defaults: Dictionary = {
		"times_talked": 0, "turns": 0, "topics_seen": [], "told": [], "told_frag": [],
		"secrets_told": [], "last_mood": "Neutral", "insults": 0, "player_class_said": "",
		"player_name": "", "last_visit_day": -1, "last_visit_time": -1.0, "epilogue_greeted": false,
	}
	for k in defaults.keys():
		if not m.has(k):
			m[k] = defaults[k]
	return m


func cv(npc_id: String) -> Dictionary:
	if not _convo.has(npc_id):
		_convo[npc_id] = {"turn": 0, "last": {}, "pending": {}, "asides": {}, "cold": false, "history": []}
	return _convo[npc_id]


func _day() -> int:
	return int(GameState.play_time / GameState.DAY_LENGTH_SEC)


func _time_key() -> String:
	var h: float = GameState.get_clock_hour()
	if h >= 5.0 and h < 12.0:
		return "morning"
	if h >= 12.0 and h < 17.0:
		return "day"
	if h >= 17.0 and h < 21.0:
		return "evening"
	return "night"


func _time_word() -> String:
	var h: float = GameState.get_clock_hour()
	if h < 5.0 or h >= 22.0:
		return "dead of night"
	if h < 8.0:
		return "early morning"
	if h < 12.0:
		return "morning"
	if h < 17.0:
		return "afternoon"
	if h < 21.0:
		return "evening"
	return "night"


func _class_name(cid: String) -> String:
	return str(GameState.class_defs.get(cid, {}).get("display_name", cid.capitalize())).to_lower()


func _region_name(rid: String) -> String:
	return str(lore.get("regions", {}).get(rid, {}).get("name", ""))


func _landmark_name(lid: String) -> String:
	return str(lore.get("landmarks", {}).get(lid, {}).get("name", ""))


func _home(p: Dictionary) -> Dictionary:
	var h: Dictionary = p.get("home", {})
	var rid: String = str(h.get("region", ""))
	var lid: String = str(h.get("landmark", ""))
	return {"region": rid, "landmark": lid, "region_name": _region_name(rid), "landmark_name": _landmark_name(lid)}


func _place_phrase(p: Dictionary) -> String:
	var h: Dictionary = _home(p)
	if h["landmark_name"] != "" and h["region_name"] != "":
		return "%s in %s" % [h["landmark_name"], h["region_name"]]
	if h["region_name"] != "":
		return str(h["region_name"])
	return str(p.get("region", ""))


func quest_ctx(npc_id: String) -> Dictionary:
	if GameState.has_method("get_npc_quest_context"):
		var r: Variant = GameState.call("get_npc_quest_context", npc_id)
		if typeof(r) == TYPE_DICTIONARY:
			return r
	return {}


func _ctx_nonempty(ctx: Dictionary) -> bool:
	return not (ctx.get("offer", []) as Array).is_empty() or not (ctx.get("active", []) as Array).is_empty() or not (ctx.get("turn_in", []) as Array).is_empty()


func _quest_titles(ctx: Dictionary) -> Array:
	var out: Array = []
	for k in ["offer", "active", "turn_in"]:
		for q in ctx.get(k, []):
			if typeof(q) == TYPE_DICTIONARY:
				out.append(q)
	return out


func slots_for(npc_id: String, extra: Dictionary = {}) -> Dictionary:
	var p: Dictionary = profiles.get(npc_id, {})
	var m: Dictionary = mem(npc_id)
	var h: Dictionary = _home(p)
	var cur_region: String = _region_name(GameState.current_region)
	var s: Dictionary = {
		"npc_name": str(p.get("name", "")),
		"role": str(p.get("role", "")).to_lower(),
		"player_class": _class_name(GameState.active_class),
		"class": _class_name(GameState.active_class),
		"level": str(GameState.get_class_level(GameState.active_class)),
		"region": cur_region if cur_region != "" else str(h["region_name"]),
		"time_of_day": _time_word(),
		"home": str(h["landmark_name"]),
		"home_region": str(h["region_name"]),
		"player_name": str(m.get("player_name", "")),
		"kills": str(GameState.total_kills),
	}
	for k in extra.keys():
		s[k] = extra[k]
	return s


# ---------------------------------------------------------------- picking

func _seed(npc_id: String, key: String) -> void:
	_global_turn += 1
	_rng.seed = hash("%s|%d|%s" % [npc_id, int(mem(npc_id).get("turns", 0)) * 7 + _global_turn, key])


func _is_told(list: Array, h: int) -> bool:
	for x in list:
		if int(x) == h:
			return true
	return false


func _mark(m: Dictionary, track: String, h: int, cap: int) -> void:
	var list: Array = m[track]
	var idx: int = -1
	for i in range(list.size()):
		if int(list[i]) == h:
			idx = i
			break
	if idx >= 0:
		list.remove_at(idx)
	list.append(h)
	while list.size() > cap:
		list.remove_at(0)


## Pick one usable, not-recently-told line. Returns {"text": String, "fresh": bool}.
func pick_line(npc_id: String, lines: Array, slots: Dictionary, track: String = "told") -> Dictionary:
	var m: Dictionary = mem(npc_id)
	var told: Array = m[track]
	var fresh: Array = []
	var all_ok: Array = []
	for l in lines:
		var ls: String = str(l)
		var filled: String = T.fill(ls, slots)
		if filled == "":
			continue
		all_ok.append([ls, filled])
		if not _is_told(told, ls.hash()):
			fresh.append([ls, filled])
	var cap: int = 150 if track == "told" else 24
	if not fresh.is_empty():
		var pk: Array = fresh[_rng.randi() % fresh.size()]
		_mark(m, track, str(pk[0]).hash(), cap)
		return {"text": str(pk[1]), "fresh": true}
	if not all_ok.is_empty():
		# everything told: take the one told longest ago
		var best: Array = all_ok[0]
		var best_i: int = 1 << 30
		for e in all_ok:
			for i in range(told.size()):
				if int(told[i]) == str(e[0]).hash():
					if i < best_i:
						best_i = i
						best = e
					break
		_mark(m, track, str(best[0]).hash(), cap)
		return {"text": str(best[1]), "fresh": false}
	return {"text": "", "fresh": false}


## Weighted multi-pool pick; prefers pools that still have unseen lines.
func pick_pools(npc_id: String, pools: Array, slots: Dictionary) -> Dictionary:
	var m: Dictionary = mem(npc_id)
	var told: Array = m["told"]
	var live: Array = []
	var total: float = 0.0
	for pool in pools:
		var arr: Array = pool[0]
		var has_fresh: bool = false
		for l in arr:
			if T.fill(str(l), slots) != "" and not _is_told(told, str(l).hash()):
				has_fresh = true
				break
		if has_fresh:
			live.append(pool)
			total += float(pool[1])
	if live.is_empty():
		var merged: Array = []
		for pool in pools:
			merged.append_array(pool[0])
		return pick_line(npc_id, merged, slots)
	var roll: float = _rng.randf() * total
	for pool in live:
		roll -= float(pool[1])
		if roll <= 0.0:
			return pick_line(npc_id, pool[0], slots)
	return pick_line(npc_id, live[0][0], slots)


func style_of(npc_id: String) -> String:
	return str(profiles.get(npc_id, {}).get("speech_style", "warm"))


func frag(npc_id: String, key: String, slots: Dictionary = {}) -> String:
	var style: Dictionary = lore.get("styles", {}).get(style_of(npc_id), {})
	var pool: Array = (style.get(key, []) as Array).duplicate()
	var common: Array = lore.get("common", {}).get(key, [])
	if pool.size() < 3 or _rng.randf() < 0.22:
		pool.append_array(common)
	return str(pick_line(npc_id, pool, slots, "told_frag")["text"])


func _mood_for(npc_id: String, base: String) -> String:
	var r: int = GameState.get_rapport(npc_id)
	if base == "Neutral":
		if r >= 7:
			return "Friendly"
		if r <= -3:
			return "Suspicious"
		return str(profiles.get(npc_id, {}).get("default_mood", "Neutral"))
	return base


func _wrap(npc_id: String, core: String, opts: Dictionary = {}) -> String:
	var t: String = core.strip_edges()
	var n: int = t.length()
	if opts.get("opener", true) and n < 190 and _rng.randf() < 0.36:
		var o: String = frag(npc_id, "openers")
		if o != "":
			t = o + " " + t
	if opts.get("closer", true) and n < 150 and T.sentence_count(t) <= 2 and _rng.randf() < 0.16:
		var cl: String = frag(npc_id, "closers")
		if cl != "":
			t += " " + cl
	return t


func _aside(npc_id: String) -> String:
	var c: Dictionary = cv(npc_id)
	var done: Dictionary = c["asides"]
	var asides: Dictionary = lore.get("common", {}).get("state_asides", {})
	var cands: Array = []
	if GameState.hp < GameState.max_hp * 0.35:
		cands.append("low_hp")
	if GameState.hunger < GameState.HUNGER_LOW_THRESHOLD:
		cands.append("hungry")
	if GameState.get_darkness() > 0.7:
		cands.append("night")
	if GameState.total_kills >= 10:
		cands.append("kills")
	if GameState.get_class_level(GameState.active_class) <= 2:
		cands.append("level_low")
	elif GameState.get_class_level(GameState.active_class) >= 8:
		cands.append("level_high")
	if GameState.game_phase == "Rebuilding_Era":
		cands.append("epilogue")
	cands.append("class")
	var shuffled: Array = cands.duplicate()
	shuffled.shuffle()
	for k in shuffled:
		if done.has(k):
			continue
		var line: String = str(pick_line(npc_id, asides.get(k, []), slots_for(npc_id), "told_frag")["text"])
		if line != "":
			done[k] = true
			return line
	return ""


func _finish(npc_id: String, core: String, mood: String, topic: String, opts: Dictionary = {}) -> Dictionary:
	var c: Dictionary = cv(npc_id)
	var text: String = _wrap(npc_id, core, opts)
	if opts.get("aside", true) and T.sentence_count(text) <= 2 and text.length() < 150 and _rng.randf() < 0.17:
		var a: String = _aside(npc_id)
		if a != "":
			text += " " + a
	if opts.get("offer", true) and T.sentence_count(text) <= 2 and text.length() < 170 and (c["pending"] as Dictionary).is_empty() and _rng.randf() < 0.22:
		var o: String = _offer(npc_id)
		if o != "":
			text += " " + o
	text = text.replace("  ", " ").strip_edges()
	return {"text": text, "mood": mood, "topic": topic, "lore": opts.get("lore", true), "actions": [], "end": opts.get("end", false)}


## Offer a follow-up topic and remember it so a bare "yes" delivers it.
func _offer(npc_id: String) -> String:
	var p: Dictionary = profiles.get(npc_id, {})
	var m: Dictionary = mem(npc_id)
	var c: Dictionary = cv(npc_id)
	var seen: Array = m["topics_seen"]
	var cands: Array = []
	for t in (p.get("topic_lines", {}) as Dictionary).keys():
		if not seen.has("topic:" + t) and lore.get("topics", {}).has(t):
			cands.append({"type": "topic", "id": t, "label": str(lore["topics"][t].get("label", t))})
	for rid in (p.get("knows", {}).get("regions", []) as Array):
		if not seen.has("region:" + str(rid)):
			cands.append({"type": "region", "id": str(rid), "label": _region_name(str(rid))})
	for nid in (p.get("knows", {}).get("npcs", []) as Array):
		if profiles.has(nid) and not seen.has("npc:" + str(nid)):
			cands.append({"type": "npc", "id": str(nid), "label": str(profiles[nid].get("name", ""))})
	if not seen.has("story"):
		cands.append({"type": "story", "id": "", "label": "an old story"})
	if cands.is_empty():
		return ""
	var pk: Dictionary = cands[_rng.randi() % cands.size()]
	if str(pk["label"]) == "":
		return ""
	var line: String = frag(npc_id, "offer", {"topic": pk["label"]})
	if line != "":
		c["pending"] = pk
	return line


func _note_seen(npc_id: String, key: String) -> void:
	var seen: Array = mem(npc_id)["topics_seen"]
	if not seen.has(key):
		seen.append(key)
		while seen.size() > 40:
			seen.remove_at(0)


# ---------------------------------------------------------------- small helpers

func _L(key: String) -> Array:
	return lore.get("lines", {}).get(key, [])


func _say(npc_id: String, key: String, extra: Dictionary = {}) -> String:
	return str(pick_line(npc_id, _L(key), slots_for(npc_id, extra))["text"])


func _player_pos() -> Variant:
	var pp: Vector2 = GameState._player_pos
	if pp.x < -90000.0:
		return null
	return pp


func _direction(from: Vector2, to: Vector2) -> String:
	var d: Vector2 = to - from
	if d.length() < 90.0:
		return ""
	var idx: int = int(round(rad_to_deg(atan2(d.y, d.x)) / 45.0))
	var names: Array = ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
	return str(names[((idx % 8) + 8) % 8])


func _loc_line(npc_id: String, target: Variant) -> String:
	var pp: Variant = _player_pos()
	if pp == null or target == null:
		return ""
	var dir: String = _direction(pp, target)
	if dir == "":
		return "That is right where you are standing, near enough."
	var slots: Dictionary = {"direction": dir, "distance": Geo.distance_text(pp, target)}
	return str(pick_line(npc_id, _L("hint_direction"), slots, "told_frag")["text"])


func _gain(npc_id: String, amount: int) -> void:
	var c: Dictionary = cv(npc_id)
	if amount > 0:
		if int(c.get("gain", 0)) >= 4:
			return
		c["gain"] = int(c.get("gain", 0)) + amount
	GameState.increment_rapport(npc_id, amount)


func _ql(p: Dictionary, qid: String, key: String) -> Array:
	var q: Variant = (p.get("quest_lines", {}) as Dictionary).get(qid, {})
	if typeof(q) != TYPE_DICTIONARY or not (q as Dictionary).has(key):
		return []
	return _as_array((q as Dictionary)[key])


func _quest_slots(npc_id: String, qid: String, ctx: Dictionary) -> Dictionary:
	var title: String = GameState.get_quest_title(qid)
	var objective: String = ""
	var hint: String = ""
	for q in _quest_titles(ctx):
		if str(q.get("quest_id", "")) == qid:
			objective = str(q.get("objective", ""))
			hint = str(q.get("hint", ""))
			if str(q.get("pitch", "")) != "":
				objective = objective if objective != "" else str(q.get("pitch", ""))
	var def: Dictionary = GameState.quest_defs.get(qid, {})
	var pitch: String = str(def.get("pitch", def.get("summary", "")))
	return slots_for(npc_id, {
		"title": title, "objective": objective, "objective_lower": T.lower_first(objective).trim_suffix("."),
		"pitch": pitch, "hint": hint,
	})


func _result(npc_id: String, core: String, mood: String, topic: String, opts: Dictionary = {}) -> Dictionary:
	if core.strip_edges() == "":
		core = _say(npc_id, "unknown_plain")
	return _finish(npc_id, core, _mood_for(npc_id, mood), topic, opts)


# ---------------------------------------------------------------- entry points

func respond(npc_id: String, text: String, override: Dictionary = {}) -> Dictionary:
	_ensure()
	var m: Dictionary = mem(npc_id)
	var c: Dictionary = cv(npc_id)
	m["turns"] = int(m["turns"]) + 1
	c["turn"] = int(c["turn"]) + 1
	_seed(npc_id, "turn")
	var raw: String = text.strip_edges()
	var out: Dictionary = _open(npc_id) if raw == "" else _converse(npc_id, raw)
	if not override.is_empty():
		out["text"] = str(override.get("dialogue", out["text"]))
		out["mood"] = str(override.get("npc_mood", out["mood"]))
		(out["actions"] as Array).append_array(override.get("game_actions", []))
		out["end"] = false
		out["lore_snippet"] = ""
	out["chips"] = _chips(npc_id, out)
	m["last_mood"] = str(out["mood"])
	return out


func _open(npc_id: String) -> Dictionary:
	var p: Dictionary = profiles.get(npc_id, {})
	var m: Dictionary = mem(npc_id)
	var c: Dictionary = cv(npc_id)
	c["gain"] = 0
	c["pending"] = {}
	c["last"] = {}
	var ctx: Dictionary = quest_ctx(npc_id)
	var first: bool = int(m["times_talked"]) == 0
	var ev: Dictionary = ctx.get("event", {})
	var evq: String = str(ev.get("quest_id", ""))
	var kind: String = str(ev.get("kind", ""))
	var core: String = ""
	var mood: String = "Friendly"
	var quest_event: bool = false
	if kind == "completed" and evq != "":
		var arr: Array = _ql(p, evq, "done")
		var qs: Dictionary = _quest_slots(npc_id, evq, ctx)
		qs["title"] = str(ev.get("title", qs["title"]))
		core = str(pick_line(npc_id, arr if not arr.is_empty() else _L("quest_done"), qs)["text"])
		quest_event = core != ""
		_gain(npc_id, 2)
	elif kind == "accepted" and evq != "":
		var arr2: Array = _ql(p, evq, "give")
		var qs2: Dictionary = _quest_slots(npc_id, evq, ctx)
		if not arr2.is_empty():
			core = str(pick_line(npc_id, arr2, qs2)["text"])
		else:
			core = str(pick_line(npc_id, _L("quest_give"), qs2)["text"])
			if str(qs2["objective"]) != "":
				core += " " + str(qs2["objective"])
		quest_event = core != ""
		_gain(npc_id, 1)
	if core == "" and GameState.game_phase == "Rebuilding_Era" and not bool(m["epilogue_greeted"]):
		m["epilogue_greeted"] = true
		var eg: String = str(p.get("epilogue_greeting", ""))
		core = eg if eg != "" else _say(npc_id, "greeting_epilogue")
	if core == "":
		var pool: Array = []
		if first:
			var pg: Variant = p.get("greeting_first", [])
			pool = _as_array(pg) if not (typeof(pg) == TYPE_ARRAY and (pg as Array).is_empty()) and str(pg) != "" else []
			if pool.is_empty():
				pool = _L("greeting_first")
		elif GameState.get_darkness() > 0.6 and _rng.randf() < 0.7:
			pool = _L("greeting_night")
		elif int(m["last_visit_day"]) == _day() and absf(GameState.play_time - float(m["last_visit_time"])) < GameState.DAY_LENGTH_SEC * 0.25:
			pool = _L("greeting_again")
		else:
			pool = _L("greeting_return")
		core = str(pick_line(npc_id, pool, slots_for(npc_id))["text"])
		if core == "":
			core = _say(npc_id, "greeting_first")
		if first:
			_gain(npc_id, 1)
		elif not (ctx.get("active", []) as Array).is_empty() and _rng.randf() < 0.65:
			var aq: Dictionary = (ctx["active"] as Array)[0]
			var aid: String = str(aq.get("quest_id", ""))
			var ra: Array = _ql(p, aid, "remind")
			var rl: String = str(pick_line(npc_id, ra if not ra.is_empty() else _L("quest_remind"), _quest_slots(npc_id, aid, ctx))["text"])
			if rl != "":
				core += " " + rl
	m["times_talked"] = int(m["times_talked"]) + 1
	m["last_visit_day"] = _day()
	m["last_visit_time"] = GameState.play_time
	var opts: Dictionary = {"opener": false, "closer": false, "aside": not quest_event, "offer": not quest_event and not first}
	return _result(npc_id, core, mood, "greeting", opts)


func _converse(npc_id: String, raw: String) -> Dictionary:
	var p: Dictionary = profiles.get(npc_id, {})
	var m: Dictionary = mem(npc_id)
	var c: Dictionary = cv(npc_id)
	var ctx: Dictionary = quest_ctx(npc_id)
	var a: Dictionary = nlu.analyze(raw, _quest_titles(ctx))
	var intent: String = str(a["intent"])
	var ents: Dictionary = a["entities"]
	var sc: Dictionary = a.get("scores", {})
	var had_self: bool = (ents["npc"] as Array).has(npc_id)
	(ents["npc"] as Array).erase(npc_id)
	if intent == "ask_person" and (ents["npc"] as Array).is_empty() and had_self:
		intent = "greeting" if float(sc.get("greeting", 0.0)) > 0.0 and int(a["n"]) <= 3 else "ask_self"
	var pending: Dictionary = c["pending"]
	c["pending"] = {}
	var out: Dictionary

	# secrets (legacy trigger keywords or a plain "any secrets?")
	var low: String = raw.to_lower()
	var secret_hit: bool = intent == "ask_secret"
	for kw in p.get("trigger_keywords", []):
		if low.find(str(kw).to_lower()) != -1:
			secret_hit = true
	if secret_hit and not ["threat", "insult", "farewell", "thanks"].has(intent):
		out = _h_secret(npc_id)
		_remember(c, "ask_secret", a)
		return out

	if not pending.is_empty() and (intent == "yes" or intent == "more"):
		out = _deliver_pending(npc_id, pending, ctx)
	elif not pending.is_empty() and intent == "no":
		out = _result(npc_id, _say(npc_id, "no_idle"), "Neutral", "decline", {"offer": false})
	elif intent == "more":
		var last: Dictionary = c["last"]
		if last.is_empty():
			out = _result(npc_id, _say(npc_id, "more_idle"), "Neutral", "more")
		else:
			out = _dispatch(npc_id, str(last["intent"]), last["a"], ctx)
	else:
		out = _dispatch(npc_id, intent, a, ctx)
		if not ["yes", "no", "more", "greeting", "farewell", "thanks", "tell_fact", "unknown"].has(intent):
			_remember(c, intent, a)

	# rapport + occasional lore snippet
	match intent:
		"insult":
			_gain(npc_id, -2 if int(m["insults"]) > 1 else -1)
		"threat":
			_gain(npc_id, -2)
		"unknown", "yes", "no", "more", "farewell", "greeting":
			pass
		_:
			_gain(npc_id, 1)
	out["lore_snippet"] = ""
	if ["smalltalk_how", "ask_topic", "ask_here", "story", "ask_self", "ask_place", "ask_advice"].has(intent) and _rng.randf() < 0.14:
		var pool: Array = lore.get("epilogue_rumors", []) if GameState.game_phase == "Rebuilding_Era" else lore.get("global_rumors", [])
		out["lore_snippet"] = str(pick_line(npc_id, pool, {}, "told_frag")["text"])
	return out


func _remember(c: Dictionary, intent: String, a: Dictionary) -> void:
	c["last"] = {"intent": intent, "a": a}


func _dispatch(npc_id: String, intent: String, a: Dictionary, ctx: Dictionary) -> Dictionary:
	match intent:
		"greeting":
			return _result(npc_id, _say(npc_id, "greeting_again"), "Friendly", "greeting", {"opener": false})
		"farewell":
			return _h_farewell(npc_id, ctx)
		"thanks":
			return _result(npc_id, _say(npc_id, "thanks"), "Friendly", "thanks")
		"apology":
			var m: Dictionary = mem(npc_id)
			if int(m["insults"]) > 0:
				m["insults"] = int(m["insults"]) - 1
				_gain(npc_id, 1)
			return _result(npc_id, _say(npc_id, "apology"), "Neutral", "apology")
		"compliment":
			_gain(npc_id, 1)
			return _result(npc_id, _say(npc_id, "compliment"), "Friendly", "compliment")
		"insult":
			var mm: Dictionary = mem(npc_id)
			mm["insults"] = int(mm["insults"]) + 1
			var key: String = "insult_1" if int(mm["insults"]) <= 1 else "insult_2"
			return _result(npc_id, _say(npc_id, key), "Suspicious" if int(mm["insults"]) <= 1 else "Hostile", "insult", {"offer": false, "aside": false})
		"threat":
			return _result(npc_id, _say(npc_id, "threat"), "Hostile", "threat", {"offer": false, "aside": false})
		"ask_help", "ask_hint":
			return _h_help(npc_id, intent, a, ctx)
		"ask_person":
			return _h_person(npc_id, a)
		"ask_place":
			return _h_place(npc_id, a)
		"ask_here":
			return _h_here(npc_id)
		"ask_self":
			return _h_self(npc_id)
		"ask_item":
			return _h_item(npc_id, a)
		"ask_enemy":
			return _h_enemy(npc_id, a)
		"ask_secret":
			return _h_secret(npc_id)
		"rumors":
			return _h_rumors(npc_id)
		"trade":
			return _h_trade(npc_id)
		"ask_advice":
			return _h_advice(npc_id)
		"smalltalk_how":
			return _result(npc_id, _say(npc_id, "smalltalk_how"), "Friendly", "smalltalk")
		"joke":
			var jk: Array = _as_array(profiles.get(npc_id, {}).get("jokes", []))
			var jl: Array = _L("joke") if jk.is_empty() else jk + _L("joke")
			return _result(npc_id, str(pick_line(npc_id, jl, slots_for(npc_id))["text"]), "Friendly", "joke")
		"story":
			return _h_story(npc_id)
		"gossip_player":
			return _h_opinion(npc_id)
		"ask_topic":
			return _h_topic(npc_id, a, ctx)
		"tell_fact":
			return _h_fact(npc_id, a)
		"yes":
			return _result(npc_id, _say(npc_id, "yes_idle"), "Neutral", "yes")
		"no":
			return _result(npc_id, _say(npc_id, "no_idle"), "Neutral", "no")
	return _h_unknown(npc_id, a)


func _deliver_pending(npc_id: String, pending: Dictionary, ctx: Dictionary) -> Dictionary:
	var fake: Dictionary = {"entities": {"npc": [], "region": [], "landmark": [], "item": [], "enemy": [], "quest": []}, "topic": "", "where": false, "n": 2, "subject": ""}
	var t: String = str(pending.get("type", ""))
	var id: String = str(pending.get("id", ""))
	match t:
		"topic":
			fake["topic"] = id
			return _h_topic(npc_id, fake, ctx)
		"region":
			(fake["entities"]["region"] as Array).append(id)
			return _h_place(npc_id, fake)
		"npc":
			(fake["entities"]["npc"] as Array).append(id)
			return _h_person(npc_id, fake)
		"story":
			return _h_story(npc_id)
	return _result(npc_id, _say(npc_id, "yes_idle"), "Neutral", "yes")


# ---------------------------------------------------------------- handlers

func _h_farewell(npc_id: String, ctx: Dictionary) -> Dictionary:
	var core: String = ""
	var act: Array = ctx.get("active", [])
	if not act.is_empty() and _rng.randf() < 0.6:
		var q: Dictionary = act[0]
		core = _say(npc_id, "farewell_quest", {"title": GameState.get_quest_title(str(q.get("quest_id", "")))})
	if core == "":
		core = _say(npc_id, "farewell")
	return _result(npc_id, core, "Friendly", "farewell", {"end": true, "offer": false, "aside": false, "opener": false})


func _h_help(npc_id: String, intent: String, a: Dictionary, ctx: Dictionary) -> Dictionary:
	var p: Dictionary = profiles.get(npc_id, {})
	var ents: Dictionary = a["entities"]
	var actions: Array = []
	var core: String = ""
	var offers: Array = ctx.get("offer", [])
	var active: Array = ctx.get("active", [])
	var qid: String = ""
	if not offers.is_empty():
		qid = str((offers[0] as Dictionary).get("quest_id", ""))
		var arr: Array = _ql(p, qid, "give")
		var qs: Dictionary = _quest_slots(npc_id, qid, ctx)
		core = str(pick_line(npc_id, arr if not arr.is_empty() else _L("quest_give"), qs)["text"])
		GameState.accept_quest(qid)
		_gain(npc_id, 1)
	elif not active.is_empty():
		qid = str((active[0] as Dictionary).get("quest_id", ""))
		for q in ents.get("quest", []):
			qid = str(q)
		var tr: String = GameState.get_tracked_quest()
		if (ents.get("quest", []) as Array).is_empty() and tr != "":
			for q2 in active:
				if str(q2.get("quest_id", "")) == tr:
					qid = tr
		var ra: Array = _ql(p, qid, "remind")
		var qs2: Dictionary = _quest_slots(npc_id, qid, ctx)
		core = str(pick_line(npc_id, ra if not ra.is_empty() else _L("quest_remind"), qs2)["text"])
		if intent == "ask_hint":
			var h: String = str(qs2.get("hint", ""))
			if h != "":
				core += " " + h
			var tgt: Dictionary = GameState.get_objective_target(qid)
			if not tgt.is_empty():
				var loc: String = _loc_line(npc_id, tgt["pos"])
				if loc != "":
					core += " " + loc
	elif intent == "ask_hint" and GameState.get_tracked_quest() != "":
		var tq: String = GameState.get_tracked_quest()
		var tslots: Dictionary = slots_for(npc_id, {"objective": GameState.get_display_objective(), "objective_lower": T.lower_first(GameState.get_display_objective()).trim_suffix(".")})
		core = str(pick_line(npc_id, _L("hint_generic"), tslots)["text"])
		var tt: Dictionary = GameState.get_objective_target(tq)
		if not tt.is_empty():
			var loc2: String = _loc_line(npc_id, tt["pos"])
			if loc2 != "":
				core += " " + loc2
	else:
		core = _say(npc_id, "quest_none")
		var giver: String = _nearest_available_giver(npc_id)
		if giver != "":
			var gp: String = _place_phrase(profiles.get(giver, {}))
			var ptr: String = _say(npc_id, "quest_none_pointer", {"giver": str(profiles[giver].get("name", "")), "place": gp})
			if ptr != "":
				core = ptr
	var out: Dictionary = _result(npc_id, core, "Friendly", "quest", {"offer": false, "aside": false, "opener": false})
	(out["actions"] as Array).append_array(actions)
	return out


func _nearest_available_giver(npc_id: String) -> String:
	var best: String = ""
	var best_d: float = INF
	var pp: Variant = _player_pos()
	for qid in GameState.quest_defs.keys():
		if not GameState.is_quest_available(qid):
			continue
		var g: String = str(GameState.quest_defs[qid].get("giver", ""))
		if g == "" or g == npc_id or not profiles.has(g):
			continue
		var gpos: Variant = GameState._npc_position(g)
		var d: float = (pp as Vector2).distance_to(gpos) if pp != null and gpos != null else 1000000.0 + _rng.randf()
		if d < best_d:
			best_d = d
			best = g
	return best


func _knows_npc(p: Dictionary, target: String) -> bool:
	if (p.get("knows", {}).get("npcs", []) as Array).has(target):
		return true
	var tp: Dictionary = profiles.get(target, {})
	var rid: String = str(p.get("home", {}).get("region", ""))
	return rid != "" and rid == str(tp.get("home", {}).get("region", ""))


func _h_person(npc_id: String, a: Dictionary) -> Dictionary:
	var p: Dictionary = profiles.get(npc_id, {})
	var targets: Array = a["entities"]["npc"]
	if targets.is_empty():
		var names: Array = []
		for nid in (p.get("knows", {}).get("npcs", []) as Array):
			if profiles.has(nid) and nid != npc_id:
				names.append(str(profiles[nid].get("name", "")))
		if names.is_empty():
			return _result(npc_id, _say(npc_id, "no_one_else"), "Neutral", "people")
		names.shuffle()
		var shown: Array = names.slice(0, 3)
		var joined: String = shown[0] if shown.size() == 1 else ", ".join(shown.slice(0, shown.size() - 1)) + " and " + str(shown[shown.size() - 1])
		return _result(npc_id, _say(npc_id, "person_list", {"names": joined}), "Neutral", "people")
	var target: String = str(targets[0])
	var tp: Dictionary = profiles.get(target, {})
	if tp.is_empty():
		return _result(npc_id, _say(npc_id, "person_unknown"), "Neutral", "people")
	_note_seen(npc_id, "npc:" + target)
	var tname: String = str(tp.get("name", ""))
	var opinions: Dictionary = p.get("opinions", {})
	var parts: Array = []
	if opinions.has(target):
		parts.append(str(opinions[target]))
	elif _knows_npc(p, target):
		parts.append(_say(npc_id, "person_intro", {"target": tname, "blurb": str(tp.get("blurb", ""))}))
	else:
		return _result(npc_id, _say(npc_id, "person_unknown"), "Neutral", "people")
	if _rng.randf() < 0.75:
		var place: String = _place_phrase(tp)
		if place != "":
			parts.append(_say(npc_id, "person_known_generic", {"target": tname, "role": str(tp.get("role", "")).to_lower(), "place": place}))
		var loc: String = _loc_line(npc_id, GameState._npc_position(target))
		if loc != "" and (bool(a.get("where", false)) or _rng.randf() < 0.5):
			parts.append(loc)
	var core: String = " ".join(parts.filter(func(x: Variant) -> bool: return str(x) != ""))
	return _result(npc_id, core, "Friendly", "people")


func _mark_landmark(npc_id: String, lid: String, out: Dictionary) -> String:
	var info: Dictionary = lore.get("landmarks", {}).get(lid, {})
	if bool(info.get("no_mark", false)) or GameState.discovered_landmarks.get(lid, false):
		return ""
	GameState.discovered_landmarks[lid] = true
	EventBus.toast_requested.emit("Map updated: %s" % _landmark_name(lid), Color(0.7, 0.9, 1.0))
	(out["actions"] as Array).append({"action_type": "mark_map", "target_id": lid, "value": "told"})
	return _say(npc_id, "place_marked")


func _h_place(npc_id: String, a: Dictionary) -> Dictionary:
	var p: Dictionary = profiles.get(npc_id, {})
	var ents: Dictionary = a["entities"]
	var lms: Array = ents["landmark"]
	var regs: Array = ents["region"]
	var out: Dictionary = {}
	var core: String = ""
	var target: Variant = null
	var mark_id: String = ""
	if not lms.is_empty():
		var lid: String = str(lms[0])
		var info: Dictionary = lore.get("landmarks", {}).get(lid, {})
		var lm: Dictionary = Geo.landmark(lid)
		_note_seen(npc_id, "landmark:" + lid)
		if not lm.is_empty():
			target = Geo.landmark_pos(lm)
		core = str(pick_line(npc_id, _as_array(info.get("lines", [])), slots_for(npc_id))["text"])
		mark_id = lid
	elif not regs.is_empty():
		var rid: String = str(regs[0])
		var rinfo: Dictionary = lore.get("regions", {}).get(rid, {})
		_note_seen(npc_id, "region:" + rid)
		var reg: Dictionary = Geo.region(rid)
		if not reg.is_empty():
			target = Geo.region_rect(reg).get_center()
		core = str(pick_line(npc_id, _as_array(rinfo.get("lines", [])), slots_for(npc_id))["text"])
	else:
		var known: Array = (p.get("knows", {}).get("regions", []) as Array).duplicate()
		known.shuffle()
		if not known.is_empty():
			var kr: String = str(known[0])
			var kinfo: Dictionary = lore.get("regions", {}).get(kr, {})
			core = str(pick_line(npc_id, _as_array(kinfo.get("lines", [])), slots_for(npc_id))["text"])
			var kreg: Dictionary = Geo.region(kr)
			if not kreg.is_empty():
				target = Geo.region_rect(kreg).get_center()
			_note_seen(npc_id, "region:" + kr)
	if core == "":
		var dirs: String = ""
		if target != null and _player_pos() != null:
			dirs = _direction(_player_pos(), target)
		core = _say(npc_id, "place_unknown_region", {"direction": dirs})
	elif target != null and (bool(a.get("where", false)) or _rng.randf() < 0.6):
		var loc: String = _loc_line(npc_id, target)
		if loc != "":
			core += " " + loc
	out = _result(npc_id, core, "Neutral", "place")
	if mark_id != "":
		var mk: String = _mark_landmark(npc_id, mark_id, out)
		if mk != "":
			out["text"] = str(out["text"]) + " " + mk
	return out


func _h_here(npc_id: String) -> Dictionary:
	var p: Dictionary = profiles.get(npc_id, {})
	var h: Dictionary = _home(p)
	var pools: Array = []
	var hl: Array = _as_array(p.get("home_lines", []))
	if not hl.is_empty():
		pools.append([hl, 3.0])
	var lm: Array = _as_array(lore.get("landmarks", {}).get(str(h["landmark"]), {}).get("lines", []))
	if not lm.is_empty():
		pools.append([lm, 2.0])
	pools.append([_L("ask_here_generic"), 1.0])
	return _result(npc_id, str(pick_pools(npc_id, pools, slots_for(npc_id))["text"]), "Friendly", "here")


func _h_self(npc_id: String) -> Dictionary:
	var p: Dictionary = profiles.get(npc_id, {})
	var pools: Array = []
	var ab: Array = _as_array(p.get("about_self", []))
	if not ab.is_empty():
		pools.append([ab, 4.0])
	pools.append([_L("ask_self_generic"), 1.0])
	return _result(npc_id, str(pick_pools(npc_id, pools, slots_for(npc_id))["text"]), "Friendly", "self")


func _h_item(npc_id: String, a: Dictionary) -> Dictionary:
	var items: Array = a["entities"]["item"]
	if items.is_empty():
		return _result(npc_id, _say(npc_id, "item_unknown"), "Neutral", "item")
	var iid: String = str(items[0])
	var d: Dictionary = GameState.item_defs.get(iid, {})
	if d.is_empty():
		return _result(npc_id, _say(npc_id, "item_unknown"), "Neutral", "item")
	var nm: String = str(d.get("name", iid))
	var facets: Array = []
	if str(d.get("desc", "")) != "":
		facets.append("%s: %s" % [nm, str(d["desc"])])
	if str(d.get("lore", "")) != "":
		facets.append(str(d["lore"]))
	if str(d.get("sources", "")) != "":
		facets.append("As for finding %s: %s" % [nm.to_lower(), str(d["sources"])])
	if str(d.get("uses", "")) != "":
		facets.append("What is it good for? %s" % str(d["uses"]))
	if d.has("value"):
		facets.append("A %s %s fetches around %d coin." % [str(d.get("rarity", "common")), nm.to_lower(), int(d["value"])])
	var core: String = str(pick_line(npc_id, facets, {})["text"])
	var cnt: int = int(GameState.inventory.get(iid, 0))
	if cnt > 0 and _rng.randf() < 0.6:
		core += " " + _say(npc_id, "item_have", {"count": str(cnt)})
	_note_seen(npc_id, "item:" + iid)
	return _result(npc_id, core, "Neutral", "item")


func _h_enemy(npc_id: String, a: Dictionary) -> Dictionary:
	var ens: Array = a["entities"]["enemy"]
	if ens.is_empty():
		return _result(npc_id, _say(npc_id, "enemy_unknown"), "Neutral", "enemy")
	var eid: String = str(ens[0])
	var def: Dictionary = GameState.enemy_defs.get(eid, {})
	var ename: String = str(def.get("name", eid.replace("_", " ").capitalize()))
	var facets: Array = _as_array(lore.get("enemies", {}).get(eid, {}).get("tips", [])).duplicate()
	var homes: Array = []
	for reg in Geo.regions():
		for e in reg.get("enemies", []):
			if str(e.get("id", "")) == eid:
				homes.append(str(reg.get("name", "")))
	if not homes.is_empty():
		var hs: String = homes[0] if homes.size() == 1 else ", ".join(homes.slice(0, homes.size() - 1)) + " and " + str(homes[homes.size() - 1])
		facets.append("You will meet %s in %s." % [_plural(ename.to_lower()), hs])
	if not def.is_empty():
		var tough: String = "tough" if float(def.get("hp", 30)) >= GameState.max_hp * 1.2 else "manageable"
		facets.append("%s is %s for someone of your build. It hits for about %d." % [ename, tough, int(def.get("damage", 5))])
	if facets.is_empty():
		return _result(npc_id, _say(npc_id, "enemy_unknown"), "Neutral", "enemy")
	_note_seen(npc_id, "enemy:" + eid)
	return _result(npc_id, str(pick_line(npc_id, facets, {})["text"]), "Neutral", "enemy")


func _h_rumors(npc_id: String) -> Dictionary:
	var p: Dictionary = profiles.get(npc_id, {})
	var pools: Array = []
	var own: Array = _as_array(p.get("rumors", []))
	if not own.is_empty():
		pools.append([own, 3.0])
	if GameState.game_phase == "Rebuilding_Era":
		pools.append([lore.get("epilogue_rumors", []), 2.0])
	pools.append([lore.get("global_rumors", []), 2.0])
	return _result(npc_id, str(pick_pools(npc_id, pools, slots_for(npc_id))["text"]), "Neutral", "rumor", {"lore": true})


func _h_trade(npc_id: String) -> Dictionary:
	var tl: Array = _as_array(profiles.get(npc_id, {}).get("trade_lines", []))
	var pool: Array = tl if not tl.is_empty() else _L("trade")
	return _result(npc_id, str(pick_line(npc_id, pool, slots_for(npc_id))["text"]), "Neutral", "trade")


func _h_advice(npc_id: String) -> Dictionary:
	var p: Dictionary = profiles.get(npc_id, {})
	var pools: Array = []
	if GameState.hunger < GameState.HUNGER_LOW_THRESHOLD:
		pools.append([_L("advice_hungry"), 4.0])
	if GameState.hp < GameState.max_hp * 0.4:
		pools.append([_L("advice_low_hp"), 4.0])
	if GameState.get_darkness() > 0.7:
		pools.append([_L("advice_night"), 3.0])
	if GameState.get_class_level(GameState.active_class) <= 2:
		pools.append([_L("advice_level_low"), 2.0])
	pools.append([_L("advice_class"), 1.5])
	pools.append([_L("advice_generic"), 1.5])
	var own: Array = _as_array(p.get("advice", []))
	if not own.is_empty():
		pools.append([own, 2.5])
	var cc: Array = _as_array(lore.get("class_comment", {}).get(GameState.active_class, []))
	if not cc.is_empty():
		pools.append([cc, 1.0])
	return _result(npc_id, str(pick_pools(npc_id, pools, slots_for(npc_id))["text"]), "Friendly", "advice")


func _h_story(npc_id: String) -> Dictionary:
	var p: Dictionary = profiles.get(npc_id, {})
	var pools: Array = []
	var own: Array = _as_array(p.get("stories", []))
	if not own.is_empty():
		pools.append([own, 4.0])
	pools.append([_L("story"), 1.0])
	_note_seen(npc_id, "story")
	return _result(npc_id, str(pick_pools(npc_id, pools, slots_for(npc_id))["text"]), "Friendly", "story", {"offer": false})


func _h_opinion(npc_id: String) -> Dictionary:
	var p: Dictionary = profiles.get(npc_id, {})
	var r: int = GameState.get_rapport(npc_id)
	var pools: Array = []
	var own: Array = _as_array(p.get("opinion_player", []))
	if not own.is_empty():
		pools.append([own, 3.0])
	var key: String = "opinion_low" if r <= -2 else ("opinion_high" if r >= 5 else "opinion_mid")
	pools.append([_L(key), 2.0])
	return _result(npc_id, str(pick_pools(npc_id, pools, slots_for(npc_id))["text"]), "Neutral", "opinion")


func _h_topic(npc_id: String, a: Dictionary, ctx: Dictionary) -> Dictionary:
	var p: Dictionary = profiles.get(npc_id, {})
	var topic: String = str(a.get("topic", ""))
	if topic == "":
		return _h_unknown(npc_id, a)
	if topic == "hint_none":
		return _h_help(npc_id, "ask_hint", a, ctx)
	_note_seen(npc_id, "topic:" + topic)
	var pools: Array = []
	var own: Array = _as_array((p.get("topic_lines", {}) as Dictionary).get(topic, []))
	if not own.is_empty():
		pools.append([own, 4.0])
	var gen: Array = _as_array(lore.get("topics", {}).get(topic, {}).get("lines", []))
	if not gen.is_empty():
		pools.append([gen, 1.0])
	if pools.is_empty():
		return _result(npc_id, _say(npc_id, "topic_unsure"), "Neutral", topic)
	return _result(npc_id, str(pick_pools(npc_id, pools, slots_for(npc_id))["text"]), "Neutral", topic)


func _h_fact(npc_id: String, a: Dictionary) -> Dictionary:
	var m: Dictionary = mem(npc_id)
	var parts: Array = []
	var nm: String = str(a.get("name_fact", ""))
	if nm != "":
		m["player_name"] = nm.capitalize()
		parts.append(_say(npc_id, "name_ack", {"player_name": m["player_name"]}))
	var cl: String = str(a.get("class_fact", ""))
	if cl != "":
		m["player_class_said"] = cl
		parts.append(_say(npc_id, "class_ack", {"class": _class_name(cl)}))
		var cc: Array = _as_array(lore.get("class_comment", {}).get(cl, []))
		if not cc.is_empty():
			parts.append(str(pick_line(npc_id, cc, {})["text"]))
	return _result(npc_id, " ".join(parts), "Friendly", "fact")


func _h_unknown(npc_id: String, a: Dictionary) -> Dictionary:
	var subject: String = str(a.get("subject", ""))
	var core: String = ""
	if subject != "":
		core = _say(npc_id, "unknown_subject", {"subject": subject})
	elif int(a.get("n", 0)) <= 1:
		core = _say(npc_id, "nonsense")
	if core == "":
		core = _say(npc_id, "unknown_plain")
	var off: String = _offer(npc_id)
	if off != "":
		core += " " + off
	return _result(npc_id, core, "Neutral", "unknown", {"offer": false, "closer": false})


func _h_secret(npc_id: String) -> Dictionary:
	var p: Dictionary = profiles.get(npc_id, {})
	var m: Dictionary = mem(npc_id)
	var flag: String = str(p.get("reveal_story_flag", ""))
	var knowledge: String = str(p.get("hidden_knowledge", ""))
	var plain: Dictionary = {"offer": false, "aside": false, "opener": false, "closer": false}
	if knowledge == "":
		return _result(npc_id, _say(npc_id, "secret_none"), "Neutral", "secret", plain)
	var told: bool = GameState.has_story_flag(flag) if flag != "" else (m["secrets_told"] as Array).has("main")
	if told:
		var pool: Array = []
		if GameState.game_phase == "Rebuilding_Era":
			pool = _as_array(p.get("epilogue_follow_up_lines", []))
		if pool.is_empty():
			pool = _as_array(p.get("follow_up_lines", []))
		if pool.is_empty():
			pool = _L("secret_none")
		return _result(npc_id, str(pick_line(npc_id, pool, slots_for(npc_id))["text"]), "Neutral", "secret", plain)
	var reqv: Variant = p.get("requires_quest_flag", null)
	var req: String = "" if reqv == null else str(reqv)
	if req != "" and not GameState.has_story_flag(req):
		var hint: String = str(p.get("requires_hint", ""))
		return _result(npc_id, hint if hint != "" else _say(npc_id, "secret_none"), "Suspicious", "secret", plain)
	if GameState.get_rapport(npc_id) < int(p.get("rapport_threshold_for_secret", 0)):
		return _result(npc_id, _say(npc_id, "secret_low_rapport"), "Suspicious", "secret", plain)
	var out: Dictionary = _result(npc_id, knowledge, "Suspicious", "secret", plain)
	if flag != "":
		GameState.set_story_flag(flag, true)
	(m["secrets_told"] as Array).append("main")
	var xp: int = int(p.get("reveal_exp", 0))
	if xp > 0:
		GameState.grant_exp(GameState.active_class, xp)
		EventBus.toast_requested.emit("+%d XP: %s trusts you" % [xp, str(p.get("name", ""))], Color(1.0, 0.9, 0.5))
	for mid in _as_array(p.get("reveal_marks", [])):
		if lore.get("landmarks", {}).has(str(mid)):
			_mark_landmark(npc_id, str(mid), out)
	if p.has("reveal_spawns_camp"):
		var camp_id: String = str(p["reveal_spawns_camp"])
		GameState.set_story_flag("camp_%s_spawned" % camp_id, true)
		(out["actions"] as Array).append({"action_type": "spawn_camp", "target_id": camp_id, "value": "revealed"})
		if lore.get("landmarks", {}).has(camp_id):
			var mk: String = _mark_landmark(npc_id, camp_id, out)
			if mk != "":
				out["text"] = str(out["text"]) + " " + mk
	_gain(npc_id, 1)
	return out


# ---------------------------------------------------------------- suggestion chips

func _chips(npc_id: String, out: Dictionary) -> Array:
	if bool(out.get("end", false)):
		return []
	var p: Dictionary = profiles.get(npc_id, {})
	var m: Dictionary = mem(npc_id)
	var c: Dictionary = cv(npc_id)
	var seen: Array = m["topics_seen"]
	var chips: Array = []
	if not (c["pending"] as Dictionary).is_empty():
		chips.append({"label": "Yes, go on", "say": "yes please"})
		chips.append({"label": "No thanks", "say": "no thanks"})
	var ctx: Dictionary = quest_ctx(npc_id)
	if not (ctx.get("active", []) as Array).is_empty():
		chips.append({"label": "What should I do?", "say": "what should i do next"})
	elif GameState.get_tracked_quest() != "":
		chips.append({"label": "Where should I go?", "say": "where should i go next"})
	else:
		chips.append({"label": "Any work for me?", "say": "do you have any work for me"})
	var pool: Array = []
	for t in (p.get("topic_lines", {}) as Dictionary).keys():
		if lore.get("topics", {}).has(t) and not seen.has("topic:" + str(t)) and str(t) != "hint_none" and (str(t) != "aftermath" or GameState.game_phase == "Rebuilding_Era"):
			var lab: String = str(lore["topics"][t].get("label", t))
			pool.append({"label": "Ask about " + lab, "say": "tell me about " + lab})
	for rid in (p.get("knows", {}).get("regions", []) as Array):
		if not seen.has("region:" + str(rid)) and _region_name(str(rid)) != "":
			pool.append({"label": "About " + _region_name(str(rid)), "say": "tell me about " + _region_name(str(rid))})
	for nid in (p.get("knows", {}).get("npcs", []) as Array):
		if profiles.has(nid) and nid != npc_id and not seen.has("npc:" + str(nid)):
			pool.append({"label": "Who is %s?" % str(profiles[nid].get("name", "")), "say": "who is %s" % str(profiles[nid].get("name", ""))})
	pool.shuffle()
	for i in range(mini(3, pool.size())):
		chips.append(pool[i])
	if not seen.has("story") and chips.size() < 5:
		chips.append({"label": "Tell me a story", "say": "tell me a story"})
	if chips.size() < 6:
		chips.append({"label": "Any rumours?", "say": "any rumors"})
	chips.append({"label": "Goodbye", "say": "goodbye"})
	var res: Array = []
	for ch in chips:
		if res.size() >= 7:
			break
		res.append(ch)
	return res
