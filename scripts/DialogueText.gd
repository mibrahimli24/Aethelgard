extends RefCounted
## Text helpers for the local dialogue engine: stemming-ish normalisation, edit distance,
## slot filling. Pure static functions, no game state.

static var _slot_re: RegEx = null


static func stem(w: String) -> String:
	var s: String = w
	if s.length() <= 3:
		return s
	if s.ends_with("ies") and s.length() > 4:
		s = s.substr(0, s.length() - 3) + "y"
	elif s.ends_with("ches") or s.ends_with("shes") or s.ends_with("sses") or s.ends_with("xes"):
		s = s.substr(0, s.length() - 2)
	elif s.ends_with("s") and not s.ends_with("ss") and not s.ends_with("us") and s.length() > 3:
		s = s.substr(0, s.length() - 1)
	if s.ends_with("ing") and s.length() > 5:
		s = s.substr(0, s.length() - 3)
	elif s.ends_with("ed") and s.length() > 4:
		s = s.substr(0, s.length() - 2)
	if s.length() > 3 and s.ends_with("e"):
		s = s.substr(0, s.length() - 1)
	var n: int = s.length()
	if n > 3 and s[n - 1] == s[n - 2] and not "aeioulsz".contains(s[n - 1]):
		s = s.substr(0, n - 1)
	return s


## Optimal-string-alignment distance; returns limit+1 when the distance exceeds limit.
static func edit_distance(a: String, b: String, limit: int) -> int:
	var la: int = a.length()
	var lb: int = b.length()
	if absi(la - lb) > limit:
		return limit + 1
	if la == 0:
		return lb
	if lb == 0:
		return la
	var prev2: Array = []
	var prev: Array = []
	for j in range(lb + 1):
		prev.append(j)
	for i in range(1, la + 1):
		var cur: Array = [i]
		var row_min: int = i
		for j in range(1, lb + 1):
			var cost: int = 0 if a[i - 1] == b[j - 1] else 1
			var v: int = mini(mini(int(prev[j]) + 1, int(cur[j - 1]) + 1), int(prev[j - 1]) + cost)
			if i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1]:
				v = mini(v, int(prev2[j - 2]) + 1)
			cur.append(v)
			row_min = mini(row_min, v)
		if row_min > limit:
			return limit + 1
		prev2 = prev
		prev = cur
	return int(prev[lb])


## Fills {slot} markers. Returns "" if any slot is missing/empty (caller skips that line).
static func fill(line: String, slots: Dictionary) -> String:
	if line.find("{") == -1:
		return line
	if _slot_re == null:
		_slot_re = RegEx.new()
		_slot_re.compile("\\{(\\w+)\\}")
	var out: String = line
	for m in _slot_re.search_all(line):
		var key: String = m.get_string(1)
		var val: String = str(slots.get(key, ""))
		if val == "":
			return ""
		out = out.replace("{%s}" % key, val)
	return out


static func needs_slots(line: String) -> Array:
	var keys: Array = []
	if line.find("{") == -1:
		return keys
	if _slot_re == null:
		_slot_re = RegEx.new()
		_slot_re.compile("\\{(\\w+)\\}")
	for m in _slot_re.search_all(line):
		keys.append(m.get_string(1))
	return keys


static func sentence_count(t: String) -> int:
	var n: int = 0
	for ch in [".", "!", "?"]:
		n += t.count(ch)
	return maxi(1, n)


static func cap_first(t: String) -> String:
	if t.length() == 0:
		return t
	return t.substr(0, 1).to_upper() + t.substr(1)


static func lower_first(t: String) -> String:
	if t.length() < 2:
		return t.to_lower()
	# keep "I", "I'm", acronyms and proper nouns-ish (second char uppercase) intact
	if t[0] == "I" and (t[1] == " " or t[1] == "'"):
		return t
	if t[1] == t[1].to_upper() and t[1] != t[1].to_lower():
		return t
	return t.substr(0, 1).to_lower() + t.substr(1)
