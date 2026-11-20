extends RefCounted
## Anim: shared procedural animation for Art-built characters. Purely visual -- owners feed it
## their existing state (velocity, facing, attack timings) and it poses the parts dicts returned by
## Art.humanoid / Art.beast / Art.wisp. Nothing here changes gameplay timing.
##
## Humanoid usage:
##   var st := Anim.make_state()                       # once per built visual
##   Anim.update_humanoid(parts, st, delta, velocity, facing, {"max_speed": 140.0})
##   Anim.start_attack(st, "sword", wind, strike, recover, side)   # when an attack begins
##   Anim.hurt(st, knock_dir)                                        # flinch
## opts for update_humanoid: max_speed, dust (bool), weapon (bool: drive weapon pose), legs, arms,
## head (bool: drive blink/look), swing_offset (extra weapon angle), frozen (treat as not moving).
## Beast usage: Anim.update_beast(parts, st, delta, velocity, face_x, {crouch, lunge, base_scale}).

const Ambient = preload("res://scripts/Ambient.gd")
const CHEST := Vector2(0, -15)


static func make_state() -> Dictionary:
	return {
		"phase": randf() * TAU, "move": 0.0, "lean": 0.0, "sq": 0.0, "t": randf() * 10.0,
		"blink_in": randf_range(1.5, 4.0), "blink": 0.0, "look_in": randf_range(2.0, 5.0),
		"look": Vector2.ZERO, "look_tgt": Vector2.ZERO, "cape_a": 0.0, "cape_v": 0.0,
		"hat_a": 0.0, "hat_v": 0.0, "hurt": 0.0, "hurt_dir": Vector2.RIGHT,
		"atk_kind": "", "atk_t": -1.0, "atk_wind": 0.1, "atk_strike": 0.1, "atk_rec": 0.2, "atk_side": 1.0,
		"aw": 0.0, "draw": 0.0, "cast": 0.0, "was_moving": false, "step_n": 0, "rolling": false,
		"trail_t": 0.0, "last_draw": -1.0,
	}


static func start_attack(st: Dictionary, kind: String, wind: float, strike: float, rec: float, side: float = 1.0) -> void:
	st["atk_kind"] = kind
	st["atk_t"] = 0.0
	st["atk_wind"] = maxf(wind, 0.01)
	st["atk_strike"] = maxf(strike, 0.01)
	st["atk_rec"] = maxf(rec, 0.01)
	st["atk_side"] = side


static func attacking(st: Dictionary) -> bool:
	return float(st.get("atk_t", -1.0)) >= 0.0


static func cancel_attack(st: Dictionary) -> void:
	st["atk_t"] = -1.0


static func hurt(st: Dictionary, dir: Vector2) -> void:
	st["hurt"] = 1.0
	st["hurt_dir"] = dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT


static func _ease_out(u: float) -> float:
	return 1.0 - (1.0 - u) * (1.0 - u)


static func _ease_in(u: float) -> float:
	return u * u


## Returns Vector3(weapon angle offset, thrust px, body lean px) for attack time t.
static func _attack_pose(st: Dictionary, kind: String) -> Vector3:
	var t: float = st["atk_t"]
	var w: float = st["atk_wind"]
	var s: float = st["atk_strike"]
	var r: float = st["atk_rec"]
	var side: float = st["atk_side"]
	var a := Vector3.ZERO
	var wp := Vector3(-1.5 * side, -3.0, -1.6)
	var sp := Vector3(1.3 * side, 4.0, 2.6)
	match kind:
		"dagger":
			wp = Vector3(-0.25 * side, -5.0, -1.2)
			sp = Vector3(0.15 * side, 9.0, 2.4)
		"bow":
			wp = Vector3(0.0, -1.0, -1.6)
			sp = Vector3(0.0, -2.0, 1.0)
		"staff":
			wp = Vector3(-0.55 * side, -4.0, -1.0)
			sp = Vector3(0.0, 7.0, 2.4)
		"flask":
			wp = Vector3(-1.8 * side, -2.0, -1.4)
			sp = Vector3(0.5 * side, 5.0, 2.6)
		"axe", "hammer":
			wp = Vector3(-1.9 * side, -4.0, -2.0)
			sp = Vector3(1.4 * side, 4.0, 3.0)
	if t < w:
		return a.lerp(wp, _ease_out(t / w))
	if t < w + s:
		return wp.lerp(sp, _ease_in(clampf((t - w) / s, 0.0, 1.0) * 0.6 + 0.4 * clampf((t - w) / s, 0.0, 1.0)))
	return sp.lerp(a, _ease_out(clampf((t - w - s) / r, 0.0, 1.0)))


static func update_humanoid(parts: Dictionary, st: Dictionary, delta: float, vel: Vector2, facing: Vector2, opts: Dictionary = {}) -> void:
	if parts.is_empty():
		return
	var body: Node2D = parts["body"]
	var legs: Array = parts["legs"]
	var head: Node2D = parts["head"]
	var eyes: Node2D = parts["eyes"]
	var weapon: Node2D = parts["weapon"]
	var arm_l: Node2D = parts["arm_l"]
	var arm_r: Node2D = parts["arm_r"]
	var max_speed: float = float(opts.get("max_speed", 140.0))
	var speed: float = vel.length()
	var moving: bool = speed > 18.0 and not bool(opts.get("frozen", false))
	st["t"] += delta
	var t: float = st["t"]

	# movement blend + stride phase
	var mv: float = move_toward(float(st["move"]), 1.0 if moving else 0.0, delta * 9.0)
	st["move"] = mv
	var ph: float = st["phase"]
	if moving:
		ph += delta * speed * 0.085
		st["phase"] = ph
	# squash/stretch on start/stop
	var sq: float = st["sq"]
	var was_moving: bool = st["was_moving"]
	if moving and not was_moving:
		sq = -0.09
	elif was_moving and not moving:
		sq = 0.10
	st["was_moving"] = moving
	sq = lerpf(sq, 0.0, 1.0 - exp(-12.0 * delta))
	st["sq"] = sq

	var dirn: Vector2 = vel / speed if speed > 1.0 else facing
	var ax: float = absf(dirn.x)
	var s0: float = sin(ph)

	# attack timeline
	var atk_kind: String = st["atk_kind"]
	var pose := Vector3.ZERO
	var atk_active: bool = float(st["atk_t"]) >= 0.0
	var draw := 0.0
	var cast := 0.0
	if atk_active:
		st["atk_t"] += delta
		var at: float = st["atk_t"]
		var total: float = float(st["atk_wind"]) + float(st["atk_strike"]) + float(st["atk_rec"])
		pose = _attack_pose(st, atk_kind)
		var w: float = st["atk_wind"]
		var s: float = st["atk_strike"]
		if atk_kind == "bow":
			draw = clampf(at / w, 0.0, 1.0) if at < w else maxf(0.0, 1.0 - (at - w) / (s * 0.6))
		elif atk_kind == "staff" or atk_kind == "flask":
			cast = clampf(at / w, 0.0, 1.0) if at < w + s else maxf(0.0, 1.0 - (at - w - s) / float(st["atk_rec"]))
		if at >= total:
			st["atk_t"] = -1.0
			atk_active = false
	st["draw"] = draw
	st["cast"] = cast
	var aw: float = move_toward(float(st["aw"]), 1.0 if atk_active else 0.0, delta * 9.0)
	st["aw"] = aw

	# hurt flinch
	var hurt_v: float = st["hurt"]
	if hurt_v > 0.0:
		hurt_v = maxf(0.0, hurt_v - delta * 3.4)
		st["hurt"] = hurt_v
	var hdir: Vector2 = st["hurt_dir"]

	# body: bob, lean, squash, breathing
	var breath: float = sin(t * 2.2) * (1.0 - mv)
	var lean_t: float = clampf(vel.x / max_speed, -1.0, 1.0) * 0.10 + s0 * 0.03 * mv
	lean_t += pose.z * 0.03 * facing.x * aw
	lean_t += -hdir.x * 0.3 * hurt_v
	var lean: float = lerpf(float(st["lean"]), lean_t, 1.0 - exp(-14.0 * delta))
	st["lean"] = lean
	body.rotation = lean
	body.position = Vector2(hdir.x * 3.0 * hurt_v, -absf(s0) * 1.5 * mv + breath * 0.35)
	if atk_active:
		body.position += Vector2(facing.x, facing.y * 0.5) * pose.z * 0.5
	body.scale = Vector2(1.0 + sq + breath * 0.008 + 0.06 * hurt_v, 1.0 - sq + breath * 0.012 - 0.08 * hurt_v)

	# legs
	if bool(opts.get("legs", true)):
		var amp: float = 0.55 * mv * (0.3 + 0.7 * ax)
		legs[0].rotation = s0 * amp
		legs[1].rotation = -s0 * amp
		legs[0].position.y = -9.0 - maxf(0.0, s0) * 2.4 * mv
		legs[1].position.y = -9.0 - maxf(0.0, -s0) * 2.4 * mv

	# arms
	if bool(opts.get("arms", true)):
		var swing: float = 0.5 * mv * (0.4 + 0.6 * ax)
		var idle: float = sin(t * 1.6) * 0.03 * (1.0 - mv)
		var wl: float = -s0 * swing + idle
		var wr: float = s0 * swing - idle
		if aw > 0.01:
			var wa: float = facing.angle() + pose.x + float(opts.get("swing_offset", 0.0))
			var ta: float = wa - PI * 0.5
			var tl: float = -0.35
			if atk_kind == "bow":
				tl = ta
				ta = ta + 0.5 * draw
			wr = lerp_angle(wr, ta, aw)
			wl = lerp_angle(wl, tl, aw)
		arm_l.rotation = wl
		arm_r.rotation = wr

	# head: blink, look-around, follow-through
	if bool(opts.get("head", true)):
		var bl: float = st["blink"]
		if bl > 0.0:
			bl -= delta
			st["blink"] = bl
		else:
			st["blink_in"] -= delta
			if float(st["blink_in"]) <= 0.0:
				st["blink"] = 0.12
				st["blink_in"] = randf_range(2.0, 5.5)
		eyes.scale.y = 0.12 if float(st["blink"]) > 0.0 else 1.0
		var look: Vector2 = st["look"]
		st["look_in"] -= delta
		if float(st["look_in"]) <= 0.0:
			if (st["look_tgt"] as Vector2) == Vector2.ZERO:
				st["look_tgt"] = Vector2(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5))
				st["look_in"] = randf_range(0.8, 1.6)
			else:
				st["look_tgt"] = Vector2.ZERO
				st["look_in"] = randf_range(2.0, 5.0)
		look = look.lerp(st["look_tgt"], 1.0 - exp(-6.0 * delta))
		st["look"] = look
		var lk: float = (1.0 - mv) * (1.0 - aw)
		eyes.position = Vector2(facing.x * 2.0 + look.x * 1.2 * lk, facing.y * 1.3 + look.y * 0.8 * lk)
		head.position = Vector2(look.x * 0.8 * lk + hdir.x * 1.5 * hurt_v, -28.0 + sin(ph * 2.0 - 0.8) * 0.6 * mv + breath * 0.25)
		head.rotation = look.x * 0.07 * lk + hdir.x * 0.3 * hurt_v + s0 * 0.03 * mv

	# secondary motion: cape + hat lag behind acceleration
	var tgt: float = clampf(vel.x / max_speed, -1.0, 1.0) * 0.45 + sin(t * 1.3) * 0.02 + sin(t * 7.0 + ph) * 0.05 * mv
	var cape: Node2D = parts.get("cape", null)
	if cape != null:
		var ca: float = st["cape_a"]
		var cv: float = st["cape_v"]
		cv += ((tgt - ca) * 90.0 - cv * 9.0) * delta
		ca += cv * delta
		st["cape_a"] = ca
		st["cape_v"] = cv
		cape.rotation = ca
		cape.scale.y = 1.0 - clampf(vel.y / max_speed, -1.0, 1.0) * 0.12
	var hat: Node2D = parts.get("hat", null)
	if hat != null:
		var ha: float = st["hat_a"]
		var hv: float = st["hat_v"]
		hv += ((tgt * 0.6 - ha) * 70.0 - hv * 8.0) * delta
		ha += hv * delta
		st["hat_a"] = ha
		st["hat_v"] = hv
		hat.rotation = ha

	# weapon
	if bool(opts.get("weapon", true)):
		var thrust: float = pose.y if atk_active else 0.0
		weapon.rotation = facing.angle() + pose.x + float(opts.get("swing_offset", 0.0))
		weapon.position = CHEST + facing * (2.0 + thrust) + Vector2(0, body.position.y)
		weapon.z_index = -1 if facing.y < -0.5 else 0
		_weapon_fx(parts, draw, cast)

	# footstep dust
	if bool(opts.get("dust", true)) and mv > 0.8:
		var n: int = int(floorf(ph / PI))
		if n != int(st["step_n"]):
			st["step_n"] = n
			Ambient.footstep((parts["root"] as Node2D).global_position, speed > max_speed * 0.8)


static func _weapon_fx(parts: Dictionary, draw: float, cast: float) -> void:
	var weapon: Node2D = parts["weapon"]
	if weapon.has_meta("string"):
		var line: Line2D = weapon.get_meta("string")
		var arrow: Node2D = weapon.get_meta("arrow")
		arrow.visible = draw > 0.05
		arrow.position.x = -draw * 9.0
		var pts: PackedVector2Array = line.points
		var px: float = 12.27 - draw * 9.0
		if absf(pts[1].x - px) > 0.05:
			line.points = PackedVector2Array([Vector2(12.27, -10.2), Vector2(px, 0.0), Vector2(12.27, 10.2)]) if draw > 0.01 else PackedVector2Array([Vector2(12.27, -10.2), Vector2(12.27, 10.2)])
	if weapon.has_meta("orb"):
		var orb: Node2D = weapon.get_meta("orb")
		var k: float = 1.0 + 0.7 * cast
		orb.scale = Vector2(k, k)


## Rotate the whole humanoid about its body centre for the dodge roll. prog 0..1, sign = spin dir.
static func roll(parts: Dictionary, st: Dictionary, prog: float, sign_dir: float) -> void:
	var root: Node2D = parts["root"]
	var body: Node2D = parts["body"]
	var s: float = root.scale.x if root.scale.x != 0.0 else 1.0
	var e: float = prog * prog * (3.0 - 2.0 * prog)
	var rot: float = TAU * e * sign_dir
	var c := Vector2(0, -12)
	root.rotation = rot
	root.position = c * s - c.rotated(rot) * s
	body.scale = Vector2(1.05, 0.8)
	if parts.has("shadow"):
		var sh: Node2D = parts["shadow"]
		sh.rotation = -rot
		sh.position = (-root.position).rotated(-rot) / s
	var legs: Array = parts["legs"]
	legs[0].rotation = 0.5
	legs[1].rotation = -0.5
	st["rolling"] = true


static func roll_end(parts: Dictionary, st: Dictionary) -> void:
	if not bool(st.get("rolling", false)):
		return
	st["rolling"] = false
	var root: Node2D = parts["root"]
	root.rotation = 0.0
	root.position = Vector2.ZERO
	if parts.has("shadow"):
		var sh: Node2D = parts["shadow"]
		sh.rotation = 0.0
		sh.position = Vector2.ZERO
	st["sq"] = 0.12


# ---------------------------------------------------------------------------
# Beasts (any parts dict shaped {root, body, legs[], tail?, head?})
# ---------------------------------------------------------------------------

static func update_beast(parts: Dictionary, st: Dictionary, delta: float, vel: Vector2, face_x: float, opts: Dictionary = {}) -> void:
	if parts.is_empty():
		return
	var root: Node2D = parts["root"]
	var body: Node2D = parts["body"]
	var legs: Array = parts["legs"]
	var base: float = float(opts.get("base_scale", 1.0))
	var crouch: float = float(opts.get("crouch", 0.0))
	var lunge: float = float(opts.get("lunge", 0.0))
	var speed: float = vel.length()
	var moving: bool = speed > 14.0 and not bool(opts.get("frozen", false))
	st["t"] += delta
	var t: float = st["t"]
	var mv: float = move_toward(float(st["move"]), 1.0 if moving else 0.0, delta * 8.0)
	st["move"] = mv
	var ph: float = st["phase"]
	if moving:
		ph += delta * speed * 0.115
		st["phase"] = ph
	var hurt_v: float = st["hurt"]
	if hurt_v > 0.0:
		hurt_v = maxf(0.0, hurt_v - delta * 3.4)
		st["hurt"] = hurt_v
	var sq: float = st["sq"]
	sq = lerpf(sq, 0.0, 1.0 - exp(-10.0 * delta))
	st["sq"] = sq
	root.scale = Vector2(base * face_x, base)
	var s0: float = sin(ph)
	var breath: float = sin(t * 2.4) * (1.0 - mv)
	var quiver: float = sin(t * 70.0) * 0.7 * crouch
	body.position = Vector2(-3.5 * crouch + 5.0 * lunge + quiver - 2.0 * hurt_v, -absf(s0) * 1.7 * mv + 3.5 * crouch)
	body.rotation = sin(ph) * 0.035 * mv - 0.06 * crouch - 0.12 * hurt_v
	body.scale = Vector2(1.0 + 0.08 * crouch + 0.2 * lunge + sq * 0.5, 1.0 - 0.14 * crouch - 0.16 * lunge + breath * 0.014 - sq * 0.5 + 0.05 * hurt_v)
	var n: int = legs.size()
	for i in n:
		var diag: bool = (i == 0 or i == 3) if n == 4 else (i % 2 == 0)
		var sw: float = s0 if diag else -s0
		var front: bool = i >= n / 2
		var r: float = sw * 0.62 * mv
		r += (0.28 if front else -0.28) * crouch
		r += (-0.9 if front else 0.9) * lunge
		legs[i].rotation = r
		legs[i].position.y = legs[i].get_meta("y0", legs[i].position.y) - maxf(0.0, sw) * 2.0 * mv
		if not legs[i].has_meta("y0"):
			legs[i].set_meta("y0", legs[i].position.y + maxf(0.0, sw) * 2.0 * mv)
	var head: Node2D = parts.get("head", null)
	if head != null:
		head.rotation = sin(ph - 0.7) * 0.1 * mv + sin(t * 1.7) * 0.05 * (1.0 - mv) + 0.25 * crouch - 0.2 * lunge + 0.25 * hurt_v
	var tail: Node2D = parts.get("tail", null)
	if tail != null:
		tail.rotation = sin(t * (3.5 + mv * 6.0)) * (0.18 + 0.22 * mv) + (-0.5 * lunge) + 0.4 * crouch
	if bool(opts.get("dust", true)) and mv > 0.8:
		var stp: int = int(floorf(ph / PI))
		if stp != int(st["step_n"]):
			st["step_n"] = stp
			Ambient.footstep(root.global_position, false)


# ---------------------------------------------------------------------------
# Wisps
# ---------------------------------------------------------------------------

static func update_wisp(parts: Dictionary, st: Dictionary, delta: float, vel: Vector2, color: Color, visible_trail: bool = true) -> void:
	if parts.is_empty():
		return
	var body: Node2D = parts["body"]
	st["t"] += delta
	var t: float = st["t"]
	body.position = Vector2(sin(t * 1.3) * 2.0, -22.0 + sin(t * 2.0) * 3.5)
	var k: float = 1.0 + 0.07 * sin(t * 4.3) + 0.03 * sin(t * 9.0)
	body.scale = Vector2(k * (1.0 - 0.05 * sin(t * 4.3)), k)
	body.rotation = clampf(vel.x / 120.0, -1.0, 1.0) * 0.25 + sin(t * 1.7) * 0.05
	st["trail_t"] -= delta
	if visible_trail and float(st["trail_t"]) <= 0.0:
		st["trail_t"] = 0.09
		Ambient.glow((parts["root"] as Node2D).global_position + body.position, color)


# ---------------------------------------------------------------------------
# Death
# ---------------------------------------------------------------------------

## Builds a parallel tween that topples/fades the visual. Caller chains queue_free afterwards.
static func death_tween(owner: Node2D, parts: Dictionary, kind: String, dir_x: float, big: bool = false) -> Tween:
	var root: Node2D = parts["root"]
	var tw: Tween = owner.create_tween()
	tw.set_parallel(true)
	var dust := Color(0.62, 0.56, 0.42, 0.8)
	match kind:
		"wisp":
			tw.tween_property(root, "scale", Vector2(1.8, 1.8), 0.4).set_ease(Tween.EASE_OUT)
			tw.tween_property(root, "modulate:a", 0.0, 0.4)
			tw.tween_callback(Ambient.glow.bind(root.global_position + Vector2(0, -22), Color(0.7, 1.0, 1.0))).set_delay(0.05)
		"beast":
			var fall: float = (PI * 0.5 - 0.15) * (1.0 if root.scale.x >= 0.0 else -1.0)
			tw.tween_property(root, "rotation", -0.22 * signf(fall), 0.09).set_ease(Tween.EASE_OUT)
			tw.chain().tween_property(root, "rotation", fall, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(root, "position:y", 3.0, 0.26).set_delay(0.09)
			tw.tween_callback(Ambient.puff.bind(owner.get_parent(), owner.global_position + Vector2(0, -3), dust, 8 if not big else 14)).set_delay(0.34)
			tw.tween_property(root, "modulate:a", 0.0, 0.5).set_delay(0.75)
		_:
			var dirv: float = signf(dir_x) if dir_x != 0.0 else 1.0
			var body: Node2D = parts["body"]
			tw.tween_property(root, "rotation", -0.18 * dirv, 0.08).set_ease(Tween.EASE_OUT)
			tw.chain().tween_property(root, "rotation", (PI * 0.5) * dirv, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(body, "scale", Vector2(1.1, 0.88), 0.3).set_delay(0.08)
			tw.tween_callback(Ambient.puff.bind(owner.get_parent(), owner.global_position + Vector2(0, -3), dust, 8 if not big else 16)).set_delay(0.38)
			tw.tween_property(root, "modulate:a", 0.0, 0.5).set_delay(0.85)
	return tw
