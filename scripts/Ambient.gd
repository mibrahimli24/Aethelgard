extends Node
## Ambient: world ambience driver. World.gd calls `Ambient.setup(world)` once after the world is built.
##
## CONVENTIONS (anything that builds props, including ArtBiome.gd, follows these):
##  * Wind sway:  node.add_to_group("swayers"); node.set_meta("sway", amp_radians)
##      - put the swaying part in its own Node2D whose ORIGIN is at its base/roots (it rotates about
##        the origin). Typical amps: tree canopy 0.02-0.04, bush 0.05, flower/grass 0.10-0.14, reed 0.08.
##      - optional meta "sway_speed" (float multiplier, default 1.0). Phase is derived from position.
##  * Light flicker: PointLight2D (made by Fx.make_light) gets meta "flicker" = amplitude 0..0.4.
##      Warm lights with radius >= 100 that nobody tagged (lamps, torches) auto-flicker lightly.
##      Set meta "no_flicker" to opt out. The driver writes the light's meta "base_energy" (World scales
##      energy by night from that), using meta "flicker_base" as the un-flickered value.
##  * Emitters: Node2D in group "emitters" with meta "emit" = "smoke" | "fire" | "steam" | "embers"
##      (optional meta "emit_rate" multiplier). Spawns pooled particles at its global position.
##  * Water: Ambient.animate_water(poly_nodes) shimmers Polygon2D/Line2D water layers;
##      Ambient.ripple_layer(parent, rx, ry, count) adds expanding ripple rings inside an ellipse.
##  * Particles: Ambient.puff(parent, pos, color, n), Ambient.spark(pos), Ambient.smoke(pos),
##      Ambient.footstep(pos, fast), Ambient.glow(pos, color). `pos` is GLOBAL (world) position.
##  * Biome flavour: Ambient.set_biome_ambient("forest"|"snow"|"desert"|"swamp"|"ash"|"coast"|"meadow"|"hills")
##  * Everything is culled to ~900px around the camera and updated in batches; pools are fixed-size.

const AMB_N := 64
const FX_N := 160
const CULL := 900.0
const CULL2 := CULL * CULL

static var _inst: Node = null
static var _pending_biome := "forest"

var _t := 0.0
var _world: Node2D
var _layer: Node2D
var _cam_pos := Vector2.ZERO
var _half := Vector2(640, 360)
var _player: Node2D
var _dark := 0.0

# particle pool (first AMB_N slots = biome ambience, rest = transient fx ring buffer)
var _nodes: Array = []
var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _grow := PackedFloat32Array()
var _grav := PackedFloat32Array()
var _ph := PackedFloat32Array()
var _col := PackedColorArray()
var _lay := PackedInt32Array()
var _fx_next := 0
var _shapes: Dictionary = {}
var _layers: Array = []
var _biome := ""

# sway
var _sway_all: Array = []
var _sway_scan := 0
var _sway_next: Array = []
var _sway_active: Array = []
var _sway_refresh := 0.0
var _rus: Dictionary = {}

# lights / emitters / water / ripples
var _flick: Array = []
var _emit: Array = []
var _water: Array = []
var _ripples: Array = []
var _slow := 0.0


# ---------------------------------------------------------------------------
# Public static API
# ---------------------------------------------------------------------------

static func setup(world: Node2D) -> void:
	if _inst != null and is_instance_valid(_inst):
		_inst.queue_free()
	var d: Node = (load("res://scripts/Ambient.gd") as GDScript).new()
	d.name = "AmbientDriver"
	world.add_child(d)
	d.call("_init_world", world)
	_inst = d
	set_biome_ambient(_pending_biome)


static func set_biome_ambient(kind: String) -> void:
	_pending_biome = kind
	if _inst != null and is_instance_valid(_inst):
		_inst.call("_apply_biome", kind)


static func puff(_parent: Node, pos: Vector2, color: Color, n: int = 6) -> void:
	if not _ok():
		return
	for i in n:
		var a: float = randf() * TAU
		var sp: float = randf_range(8.0, 34.0)
		_inst.call("_spawn", pos + Vector2(randf_range(-4, 4), randf_range(-2, 2)), Vector2(cos(a) * sp, sin(a) * sp * 0.5 - 10.0), randf_range(0.45, 0.8), color, randf_range(2.5, 4.5), 1.6, -6.0, "circle")


static func footstep(pos: Vector2, fast: bool = false) -> void:
	if not _ok() or not _inst.call("_near", pos):
		return
	var c := Color(0.62, 0.55, 0.4, 0.3)
	for i in (3 if fast else 2):
		_inst.call("_spawn", pos + Vector2(randf_range(-3, 3), -1), Vector2(randf_range(-10, 10), randf_range(-12, -4)), randf_range(0.3, 0.5), c, randf_range(1.6, 2.6), 1.5, -4.0, "circle")


static func glow(pos: Vector2, color: Color) -> void:
	if not _ok() or not _inst.call("_near", pos):
		return
	_inst.call("_spawn", pos + Vector2(randf_range(-2, 2), randf_range(-2, 2)), Vector2(randf_range(-6, 6), randf_range(-8, 2)), 0.55, Color(color.r, color.g, color.b, 0.5), 4.0, -0.8, 0.0, "circle")


static func spark(pos: Vector2, color: Color = Color(1.0, 0.65, 0.2, 1.0)) -> void:
	if not _ok() or not _inst.call("_near", pos):
		return
	_inst.call("_spawn", pos, Vector2(randf_range(-14, 14), randf_range(-60, -30)), randf_range(0.5, 0.9), color, 1.4, -0.7, 10.0, "circle")


static func smoke(pos: Vector2, color: Color = Color(0.72, 0.72, 0.76, 0.32)) -> void:
	if not _ok() or not _inst.call("_near", pos):
		return
	_inst.call("_spawn", pos, Vector2(randf_range(4, 12), randf_range(-22, -14)), randf_range(2.0, 3.2), color, 3.0, 2.4, -2.0, "circle")


## Shimmer water layers (Polygon2D / Line2D). Opaque layers breathe in brightness; translucent
## highlight layers also drift a pixel or two. Call once per layer list after building the water.
static func animate_water(nodes: Array, amp: float = 1.0) -> void:
	if not _ok():
		return
	_inst.call("_add_water", nodes, amp)


## Adds slowly expanding ripple rings inside an ellipse (rx, ry) centred at `center` of `parent`.
static func ripple_layer(parent: Node, rx: float, ry: float, count: int = 4, color: Color = Color(1, 1, 1, 0.35), center: Vector2 = Vector2.ZERO) -> Node2D:
	var holder := Node2D.new()
	holder.position = center
	holder.set_meta("rx", rx)
	holder.set_meta("ry", ry)
	parent.add_child(holder)
	for i in count:
		var ring := Line2D.new()
		var pts := PackedVector2Array()
		for k in 14:
			var a: float = TAU * float(k) / 14.0
			pts.append(Vector2(cos(a), sin(a) * 0.6))
		ring.points = pts
		ring.closed = true
		ring.width = 1.0
		ring.default_color = color
		ring.set_meta("rip_i", i)
		ring.set_meta("rip_n", count)
		ring.set_meta("rip_cycle", -1)
		ring.scale = Vector2(0.01, 0.01)
		holder.add_child(ring)
	if _ok():
		_inst.call("_add_ripples", holder)
	return holder


static func _ok() -> bool:
	return _inst != null and is_instance_valid(_inst)


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func _init_world(world: Node2D) -> void:
	_world = world
	_layer = Node2D.new()
	_layer.name = "AmbientFx"
	_layer.z_index = 10
	world.add_child(_layer)
	_shapes["circle"] = _ell(1.0, 1.0, 8)
	_shapes["leaf"] = PackedVector2Array([Vector2(-2, 0), Vector2(0, -1), Vector2(2, 0), Vector2(0, 1)])
	_shapes["streak"] = PackedVector2Array([Vector2(-4, -0.4), Vector2(4, -0.4), Vector2(4, 0.4), Vector2(-4, 0.4)])
	_shapes["butterfly"] = PackedVector2Array([Vector2(0, 0), Vector2(-2, -1.6), Vector2(-1.2, 0.8), Vector2(0, 0.3), Vector2(1.2, 0.8), Vector2(2, -1.6)])
	_shapes["mist"] = _ell(9.0, 2.6, 10)
	var total: int = AMB_N + FX_N
	_pos.resize(total)
	_vel.resize(total)
	_age.resize(total)
	_life.resize(total)
	_size.resize(total)
	_grow.resize(total)
	_grav.resize(total)
	_ph.resize(total)
	_col.resize(total)
	_lay.resize(total)
	for i in total:
		var p := Polygon2D.new()
		p.polygon = _shapes["circle"]
		p.visible = false
		_layer.add_child(p)
		_nodes.append(p)
		_life[i] = 0.0
		_lay[i] = -1
		_ph[i] = randf() * TAU
	_refresh_groups()


static func _ell(rx: float, ry: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a: float = TAU * float(i) / float(n)
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _near(pos: Vector2) -> bool:
	return pos.distance_squared_to(_cam_pos) < CULL2


func _refresh_groups() -> void:
	var tree := get_tree()
	_sway_all = tree.get_nodes_in_group("swayers")
	_sway_scan = 0
	_sway_next = []


# ---------------------------------------------------------------------------
# Biome particle layers
# ---------------------------------------------------------------------------

func _layer_defs(kind: String) -> Array:
	var leaf_cols: Array = [Color(0.45, 0.62, 0.22, 0.85), Color(0.7, 0.55, 0.2, 0.85), Color(0.78, 0.4, 0.15, 0.85)]
	var mote := {"n": 10, "shape": "circle", "cols": [Color(1.0, 0.96, 0.8, 0.35)], "size": Vector2(0.8, 1.6), "vel": Vector2(4, -3), "vr": 5.0, "sway": 6.0, "swf": 0.8, "spin": 0.0, "day": 1}
	match kind:
		"snow":
			return [{"n": 46, "shape": "circle", "cols": [Color(1, 1, 1, 0.85), Color(0.9, 0.95, 1.0, 0.7)], "size": Vector2(0.9, 2.0), "vel": Vector2(-12, 38), "vr": 10.0, "sway": 10.0, "swf": 1.1, "spin": 0.0, "day": 0}]
		"desert":
			return [{"n": 30, "shape": "streak", "cols": [Color(0.85, 0.72, 0.45, 0.35)], "size": Vector2(1.0, 2.2), "vel": Vector2(150, 6), "vr": 40.0, "sway": 3.0, "swf": 2.0, "spin": 0.0, "day": 0}, mote]
		"swamp":
			return [{"n": 16, "shape": "circle", "cols": [Color(0.55, 0.85, 0.45, 0.5), Color(0.75, 0.9, 0.5, 0.4)], "size": Vector2(1.0, 2.0), "vel": Vector2(3, -9), "vr": 4.0, "sway": 9.0, "swf": 0.9, "spin": 0.0, "day": 0}, {"n": 6, "shape": "mist", "cols": [Color(0.7, 0.8, 0.7, 0.09)], "size": Vector2(3.0, 6.0), "vel": Vector2(8, 0), "vr": 2.0, "sway": 3.0, "swf": 0.3, "spin": 0.0, "day": 0}]
		"ash":
			return [{"n": 28, "shape": "circle", "cols": [Color(0.35, 0.33, 0.33, 0.7), Color(0.5, 0.48, 0.47, 0.55)], "size": Vector2(0.9, 1.9), "vel": Vector2(14, 22), "vr": 8.0, "sway": 8.0, "swf": 1.0, "spin": 0.0, "day": 0}, {"n": 12, "shape": "circle", "cols": [Color(1.0, 0.5, 0.15, 0.9), Color(1.0, 0.7, 0.25, 0.8)], "size": Vector2(0.8, 1.4), "vel": Vector2(10, -24), "vr": 8.0, "sway": 8.0, "swf": 1.5, "spin": 0.0, "day": 0}]
		"coast":
			return [{"n": 14, "shape": "circle", "cols": [Color(1, 1, 1, 0.5)], "size": Vector2(0.8, 1.6), "vel": Vector2(60, -14), "vr": 25.0, "sway": 4.0, "swf": 2.2, "spin": 0.0, "day": 0}, {"n": 4, "shape": "leaf", "cols": [Color(1, 1, 1, 0.8)], "size": Vector2(1.0, 1.5), "vel": Vector2(24, -4), "vr": 6.0, "sway": 24.0, "swf": 1.4, "spin": 0.0, "day": 1}]
		"meadow":
			return [{"n": 14, "shape": "circle", "cols": [Color(1.0, 0.95, 0.5, 0.75), Color(1, 1, 1, 0.6)], "size": Vector2(0.8, 1.5), "vel": Vector2(6, -6), "vr": 6.0, "sway": 10.0, "swf": 0.7, "spin": 0.0, "day": 1}, {"n": 5, "shape": "butterfly", "cols": [Color(0.95, 0.6, 0.2, 0.95), Color(0.5, 0.65, 1.0, 0.95), Color(1.0, 0.95, 0.4, 0.95)], "size": Vector2(2.0, 2.8), "vel": Vector2(14, 0), "vr": 4.0, "sway": 0.0, "swf": 1.0, "spin": 0.0, "day": 1}, {"n": 5, "shape": "circle", "cols": [Color(1.0, 0.96, 0.8, 0.35)], "size": Vector2(0.8, 1.6), "vel": Vector2(4, -3), "vr": 5.0, "sway": 6.0, "swf": 0.8, "spin": 0.0, "day": 1}]
		"hills":
			return [mote, {"n": 8, "shape": "streak", "cols": [Color(1, 1, 1, 0.18)], "size": Vector2(1.5, 3.0), "vel": Vector2(90, 4), "vr": 30.0, "sway": 3.0, "swf": 1.5, "spin": 0.0, "day": 0}, {"n": 5, "shape": "leaf", "cols": [Color(0.6, 0.55, 0.3, 0.8)], "size": Vector2(1.0, 1.6), "vel": Vector2(36, 12), "vr": 10.0, "sway": 10.0, "swf": 1.2, "spin": 3.0, "day": 0}]
		_:
			return [{"n": 18, "shape": "leaf", "cols": leaf_cols, "size": Vector2(1.1, 1.8), "vel": Vector2(-14, 26), "vr": 8.0, "sway": 16.0, "swf": 1.3, "spin": 2.5, "day": 0}, mote, {"n": 6, "shape": "circle", "cols": [Color(1.0, 0.96, 0.6, 0.6)], "size": Vector2(0.8, 1.3), "vel": Vector2(5, -5), "vr": 5.0, "sway": 9.0, "swf": 0.8, "spin": 0.0, "day": 1}]


func _apply_biome(kind: String) -> void:
	if kind == _biome:
		return
	_biome = kind
	_layers = _layer_defs(kind)
	var slot := 0
	for li in _layers.size():
		var L: Dictionary = _layers[li]
		for k in int(L["n"]):
			if slot >= AMB_N:
				break
			_lay[slot] = li
			var node: Polygon2D = _nodes[slot]
			node.polygon = _shapes[str(L["shape"])]
			node.visible = true
			_respawn_amb(slot, true)
			slot += 1
	while slot < AMB_N:
		_lay[slot] = -1
		(_nodes[slot] as Polygon2D).visible = false
		slot += 1


func _respawn_amb(i: int, anywhere: bool) -> void:
	var L: Dictionary = _layers[_lay[i]]
	var cols: Array = L["cols"]
	var sz: Vector2 = L["size"]
	_col[i] = cols[randi() % cols.size()]
	_size[i] = randf_range(sz.x, sz.y)
	_pos[i] = _cam_pos + Vector2(randf_range(-_half.x - 30.0, _half.x + 30.0), randf_range(-_half.y - 30.0, _half.y + 30.0))
	var v: Vector2 = L["vel"]
	var vr: float = L["vr"]
	_vel[i] = Vector2(randf_range(-vr, vr), randf_range(-vr, vr) * 0.5)
	_life[i] = randf_range(6.0, 12.0)
	_age[i] = randf_range(0.0, _life[i] * 0.6) if anywhere else 0.0
	_ph[i] = randf() * TAU
	(_nodes[i] as Polygon2D).scale = Vector2(_size[i], _size[i])
	if str(L["shape"]) == "mist":
		_size[i] = randf_range(sz.x, sz.y)
	if v == Vector2.ZERO:
		pass


# ---------------------------------------------------------------------------
# Transient particles
# ---------------------------------------------------------------------------

func _spawn(pos: Vector2, vel: Vector2, life: float, color: Color, size: float, grow: float, grav: float, shape: String) -> void:
	var i: int = AMB_N + _fx_next
	_fx_next = (_fx_next + 1) % FX_N
	_pos[i] = pos
	_vel[i] = vel
	_age[i] = 0.0
	_life[i] = life
	_size[i] = size
	_grow[i] = grow
	_grav[i] = grav
	_col[i] = color
	_lay[i] = -2
	var n: Polygon2D = _nodes[i]
	n.polygon = _shapes[shape]
	n.position = pos
	n.scale = Vector2(size, size)
	n.color = color
	n.visible = true


func _add_water(nodes: Array, amp: float) -> void:
	for n in nodes:
		if not is_instance_valid(n) or not (n is CanvasItem):
			continue
		if n.has_meta("water_c0"):
			continue
		var c: Color = n.get("color") if n.get("color") != null else n.get("default_color")
		n.set_meta("water_c0", c)
		n.set_meta("water_p0", (n as Node2D).position)
		n.set_meta("water_amp", amp)
		n.add_to_group("water_layers")


func _add_ripples(holder: Node2D) -> void:
	holder.add_to_group("ripple_layers")


# ---------------------------------------------------------------------------
# Frame update
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	_t += delta
	var vp := get_viewport()
	var cam: Camera2D = vp.get_camera_2d() if vp != null else null
	if cam == null:
		return
	_cam_pos = cam.get_screen_center_position()
	_half = vp.get_visible_rect().size / cam.zoom * 0.5
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	_dark = GameState.get_darkness()

	_slow -= delta
	if _slow <= 0.0:
		_slow = 0.3
		_refresh_slow()
	_update_sway(delta)
	_update_flicker()
	_update_emitters(delta)
	_update_water()
	_update_particles(delta)


func wind_at(pos: Vector2) -> float:
	var g: float = 0.6 + 0.4 * sin(_t * 0.27) * sin(_t * 0.61 + 1.3)
	var a: float = sin(_t * 1.25 + pos.x * 0.011 + pos.y * 0.006)
	var b: float = sin(_t * 2.7 + pos.x * 0.03 - pos.y * 0.02)
	return (a * 0.65 + b * 0.35) * g + 0.25 * g


func _refresh_slow() -> void:
	var tree := get_tree()
	_sway_refresh -= 0.3
	if _sway_refresh <= 0.0:
		_sway_refresh = 3.0
		_sway_all = tree.get_nodes_in_group("swayers")
		_sway_scan = 0
	# lights
	_flick.clear()
	for l in tree.get_nodes_in_group("night_lights"):
		if not (l is PointLight2D) or not _near((l as Node2D).global_position):
			continue
		var amp: float = 0.0
		if l.has_meta("flicker"):
			amp = float(l.get_meta("flicker"))
		elif not l.has_meta("no_flicker"):
			var c: Color = l.color
			var par: Node = l.get_parent()
			if l.texture_scale >= 0.78 and c.r > 0.9 and c.b < 0.55 and par != null and par.get("kind") == null and par != get_tree().get_first_node_in_group("player"):
				amp = 0.14
				l.set_meta("flicker", amp)
			else:
				l.set_meta("no_flicker", true)
		if amp > 0.0:
			if not l.has_meta("flicker_base"):
				l.set_meta("flicker_base", float(l.get_meta("base_energy", l.energy)))
			_flick.append(l)
	_emit.clear()
	for e in tree.get_nodes_in_group("emitters"):
		if _near((e as Node2D).global_position):
			_emit.append(e)
	_water.clear()
	for w in tree.get_nodes_in_group("water_layers"):
		_water.append(w)
	_ripples = tree.get_nodes_in_group("ripple_layers")


func _update_sway(delta: float) -> void:
	# batch-scan the full swayer list a slice per frame to build the active (near-camera) set
	var total: int = _sway_all.size()
	var end: int = mini(_sway_scan + 300, total)
	for i in range(_sway_scan, end):
		var n: Node2D = _sway_all[i] as Node2D
		if is_instance_valid(n) and n.global_position.distance_squared_to(_cam_pos) < CULL2:
			_sway_next.append(n)
	_sway_scan = end
	if _sway_scan >= total:
		_sway_active = _sway_next
		_sway_next = []
		_sway_scan = 0
	var ppos: Vector2 = _player.global_position if _player != null and is_instance_valid(_player) else Vector2(-99999, -99999)
	for n: Node2D in _sway_active:
		if not is_instance_valid(n):
			continue
		var gp: Vector2 = n.global_position
		var amp: float = float(n.get_meta("sway", 0.03))
		var sp: float = float(n.get_meta("sway_speed", 1.0))
		var w: float = wind_at(gp) if sp == 1.0 else wind_at(gp * sp)
		n.rotation = w * amp
		var off: Vector2 = gp - ppos
		if absf(off.x) < 34.0 and absf(off.y) < 34.0 and off.length_squared() < 1156.0:
			_rus[n] = signf(off.x) * (1.0 - off.length() / 34.0) * amp * 4.0
	if not _rus.is_empty():
		var done: Array = []
		for n in _rus.keys():
			if not is_instance_valid(n):
				done.append(n)
				continue
			var v: float = _rus[n]
			(n as Node2D).rotation += v
			v *= 1.0 - minf(1.0, delta * 3.0)
			_rus[n] = v
			if absf(v) < 0.002:
				done.append(n)
		for n in done:
			_rus.erase(n)


func _update_flicker() -> void:
	for l in _flick:
		if not is_instance_valid(l):
			continue
		var amp: float = l.get_meta("flicker")
		var ph: float = (l as Node2D).global_position.x * 0.13
		var n: float = 0.5 * sin(_t * 13.0 + ph) + 0.3 * sin(_t * 7.3 + ph * 2.1) + 0.2 * sin(_t * 23.0 + ph * 0.7)
		l.set_meta("base_energy", float(l.get_meta("flicker_base")) * (1.0 + amp * n))


func _update_emitters(delta: float) -> void:
	for e: Node2D in _emit:
		if not is_instance_valid(e):
			continue
		var kind: String = str(e.get_meta("emit", "smoke"))
		var rate: float = float(e.get_meta("emit_rate", 1.0))
		var acc: float = float(e.get_meta("emit_acc", 0.0)) + delta * rate
		var gp: Vector2 = e.global_position
		match kind:
			"fire":
				while acc > 0.2:
					acc -= 0.2
					spark(gp + Vector2(randf_range(-4, 4), -6))
				if randf() < delta * 1.3 * rate:
					smoke(gp + Vector2(randf_range(-3, 3), -20), Color(0.35, 0.33, 0.33, 0.28))
			"steam":
				while acc > 0.25:
					acc -= 0.25
					_spawn(gp, Vector2(randf_range(-4, 4), randf_range(-22, -15)), 1.2, Color(1, 1, 1, 0.28), 2.4, 1.8, -3.0, "circle")
			"embers":
				while acc > 0.33:
					acc -= 0.33
					spark(gp, Color(1.0, 0.5, 0.15, 0.9))
			_:
				while acc > 0.4:
					acc -= 0.4
					smoke(gp)
		e.set_meta("emit_acc", acc)


func _update_water() -> void:
	var tt: float = _t
	for w in _water:
		if not is_instance_valid(w):
			continue
		var c0: Color = w.get_meta("water_c0")
		var amp: float = w.get_meta("water_amp")
		var p0: Vector2 = w.get_meta("water_p0")
		var gp: Vector2 = (w as Node2D).global_position
		if not _near(gp) and p0 == gp:
			continue
		var ph: float = p0.x * 0.05 + p0.y * 0.03
		var k: float = 1.0 + 0.07 * amp * sin(tt * 1.3 + ph) + 0.04 * amp * sin(tt * 2.9 + ph * 1.7)
		var col := Color(c0.r * k, c0.g * k, c0.b * k, c0.a)
		if c0.a < 0.99:
			col.a = c0.a * (0.75 + 0.25 * sin(tt * 1.7 + ph))
			(w as Node2D).position = p0 + Vector2(sin(tt * 0.6 + ph) * 1.5 * amp, cos(tt * 0.5 + ph) * 0.6 * amp)
		if w is Polygon2D:
			(w as Polygon2D).color = col
		elif w is Line2D:
			(w as Line2D).default_color = col
	for h: Node2D in _ripples:
		if not is_instance_valid(h) or not _near(h.global_position):
			continue
		var rx: float = h.get_meta("rx")
		var ry: float = h.get_meta("ry")
		for ring: Line2D in h.get_children():
			var i: int = ring.get_meta("rip_i")
			var n: int = ring.get_meta("rip_n")
			var cyc: float = tt * 0.3 + float(i) / float(n)
			var cn: int = int(floorf(cyc))
			var u: float = cyc - float(cn)
			if cn != int(ring.get_meta("rip_cycle")):
				ring.set_meta("rip_cycle", cn)
				var a: float = fposmod(float(cn * 7919 + i * 104729), 6.2831)
				var rr: float = fposmod(float(cn * 31 + i * 17), 1.0) * 0.8
				ring.position = Vector2(cos(a) * rx * rr, sin(a) * ry * rr)
			var sc: float = 2.0 + u * 9.0
			ring.scale = Vector2(sc, sc)
			ring.width = 1.0 / maxf(sc, 0.1) * 1.3
			ring.modulate.a = (1.0 - u) * 0.9


func _update_particles(delta: float) -> void:
	var rect := Rect2(_cam_pos - _half - Vector2(80, 80), _half * 2.0 + Vector2(160, 160))
	var day_k: float = clampf(1.0 - _dark * 2.5, 0.0, 1.0)
	var night_k: float = clampf(_dark * 2.0 - 0.3, 0.0, 1.0)
	for i in AMB_N:
		var li: int = _lay[i]
		if li < 0:
			continue
		var L: Dictionary = _layers[li]
		var age: float = _age[i] + delta
		_age[i] = age
		var life: float = _life[i]
		var pos: Vector2 = _pos[i]
		if age >= life or not rect.has_point(pos):
			_respawn_amb(i, false)
			pos = _pos[i]
			age = 0.0
			life = _life[i]
		var ph: float = _ph[i]
		var shape: String = L["shape"]
		var v: Vector2 = L["vel"]
		var sway: float = L["sway"]
		var swf: float = L["swf"]
		var node: Polygon2D = _nodes[i]
		if shape == "butterfly":
			var a: float = ph + _t * 0.5 + sin(_t * 1.3 + ph) * 2.0
			v = Vector2(cos(a), sin(a) * 0.6) * 22.0
			node.scale = Vector2(_size[i] * absf(sin(_t * 14.0 + ph)) + 0.4, _size[i])
			node.rotation = 0.0
		else:
			v = v + Vector2(sin(_t * swf + ph) * sway, cos(_t * swf * 0.7 + ph) * sway * 0.4) + _vel[i]
			v.x += wind_at(pos) * 10.0 * (absf((L["vel"] as Vector2).x) / 20.0 + 0.3)
			var spin: float = L["spin"]
			if shape == "leaf":
				node.rotation += spin * delta
			elif shape == "streak":
				node.rotation = v.angle()
		pos += v * delta
		_pos[i] = pos
		node.position = pos
		var fade: float = minf(minf(age / 0.8, 1.0), minf((life - age) / 1.0, 1.0))
		var day: int = L["day"]
		var k: float = 1.0
		if day == 1:
			k = day_k
		elif day == 2:
			k = night_k
		var c: Color = _col[i]
		c.a *= fade * k
		node.color = c
		node.visible = c.a > 0.01
	for i in range(AMB_N, AMB_N + FX_N):
		var life: float = _life[i]
		if life <= 0.0:
			continue
		var age: float = _age[i] + delta
		if age >= life:
			_life[i] = 0.0
			(_nodes[i] as Polygon2D).visible = false
			continue
		_age[i] = age
		var u: float = age / life
		var vel: Vector2 = _vel[i]
		vel.y += _grav[i] * delta
		_vel[i] = vel
		var p: Vector2 = _pos[i] + vel * delta
		_pos[i] = p
		var node: Polygon2D = _nodes[i]
		node.position = p
		var sc: float = maxf(0.05, _size[i] * (1.0 + _grow[i] * u))
		node.scale = Vector2(sc, sc)
		var c: Color = _col[i]
		c.a *= 1.0 - u
		node.color = c
