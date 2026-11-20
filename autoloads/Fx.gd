extends Node
## Fx: shared "game feel" helpers -- procedural sound effects and music (no audio assets exist in
## this project, so every sound is synthesized into an AudioStreamWAV at startup), floating damage
## numbers, screen shake, hit-stop, particle bursts, and soft glow lights. Everything visual is
## added to the current scene so it depends on nothing but the scene tree.

const MIX_RATE := 22050
const MUSIC_RATE := 8000

var muted := false

var _sounds: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_index := 0
var _music_player: AudioStreamPlayer
var _hitstop_active := false
var _glow_texture: GradientTexture2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_sounds()
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.volume_db = -4.0
		add_child(p)
		_pool.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.volume_db = -19.0
	add_child(_music_player)
	WorkerThreadPool.add_task(_build_music_task)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_N:
		toggle_mute()


# ---------------------------------------------------------------------------
# Audio
# ---------------------------------------------------------------------------

func play(sound_name: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not _sounds.has(sound_name) or _pool.is_empty():
		return
	var p: AudioStreamPlayer = _pool[_pool_index]
	_pool_index = (_pool_index + 1) % _pool.size()
	p.stream = _sounds[sound_name]
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.volume_db = -4.0 + volume_db
	p.play()


func toggle_mute() -> void:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)
	EventBus.toast_requested.emit("Sound %s" % ("off" if muted else "on"), Color(0.8, 0.8, 0.8))


func _build_sounds() -> void:
	_sounds["swing"] = _make_wav(_synth(0.13, 520.0, 180.0, 0.85, 0.30, 5.0))
	_sounds["hit"] = _make_wav(_synth(0.11, 240.0, 80.0, 0.5, 0.55, 6.0))
	_sounds["crit"] = _make_wav(_mix([_synth(0.16, 700.0, 240.0, 0.4, 0.5, 5.0), _synth(0.16, 180.0, 60.0, 0.5, 0.5, 5.0)]))
	_sounds["hurt"] = _make_wav(_synth(0.2, 320.0, 110.0, 0.25, 0.5, 4.5, true))
	_sounds["enemy_die"] = _make_wav(_synth(0.32, 220.0, 55.0, 0.45, 0.5, 4.0))
	_sounds["shoot"] = _make_wav(_synth(0.12, 950.0, 320.0, 0.25, 0.28, 6.0))
	_sounds["magic"] = _make_wav(_synth(0.26, 380.0, 900.0, 0.1, 0.3, 3.5))
	_sounds["dodge"] = _make_wav(_synth(0.16, 260.0, 640.0, 0.75, 0.25, 4.5))
	_sounds["special"] = _make_wav(_synth(0.4, 140.0, 620.0, 0.3, 0.45, 2.5))
	_sounds["pickup"] = _make_wav(_synth(0.13, 620.0, 1240.0, 0.0, 0.32, 3.0))
	_sounds["eat"] = _make_wav(_synth(0.17, 160.0, 90.0, 0.9, 0.5, 4.0))
	_sounds["click"] = _make_wav(_synth(0.05, 1000.0, 800.0, 0.0, 0.25, 6.0))
	_sounds["roar"] = _make_wav(_synth(0.7, 95.0, 45.0, 0.35, 0.6, 2.0, true))
	_sounds["death"] = _make_wav(_synth(0.7, 300.0, 40.0, 0.2, 0.5, 2.5))
	_sounds["level_up"] = _make_wav(_arpeggio([523.25, 659.25, 783.99, 1046.5], 0.11))
	_sounds["quest"] = _make_wav(_arpeggio([392.0, 523.25, 659.25], 0.13))
	_sounds["victory"] = _make_wav(_arpeggio([392.0, 523.25, 659.25, 783.99, 1046.5], 0.14))


func _synth(duration: float, f0: float, f1: float, noise: float, volume: float, decay: float, square: bool = false) -> PackedFloat32Array:
	var n: int = int(duration * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t: float = float(i) / float(n)
		phase += TAU * lerpf(f0, f1, t) / MIX_RATE
		var tone: float = sin(phase)
		if square:
			tone = signf(tone) * 0.6
		var env: float = exp(-decay * t) * minf(1.0, float(i) / 40.0)
		out[i] = (tone * (1.0 - noise) + randf_range(-1.0, 1.0) * noise) * env * volume
	return out


func _mix(waves: Array) -> PackedFloat32Array:
	var longest := 0
	for w: PackedFloat32Array in waves:
		longest = maxi(longest, w.size())
	var out := PackedFloat32Array()
	out.resize(longest)
	for w: PackedFloat32Array in waves:
		for i in w.size():
			out[i] += w[i]
	return out


func _arpeggio(freqs: Array, step: float) -> PackedFloat32Array:
	var parts: Array = []
	var offset := 0
	var total := 0
	for f in freqs:
		var note: PackedFloat32Array = _synth(step * 2.2, float(f), float(f), 0.0, 0.3, 3.5)
		parts.append([offset, note])
		total = maxi(total, offset + note.size())
		offset += int(step * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(total)
	for part: Array in parts:
		var start: int = part[0]
		var note: PackedFloat32Array = part[1]
		for i in note.size():
			out[start + i] += note[i]
	return out


func _make_wav(samples: PackedFloat32Array, rate: int = MIX_RATE, looped: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	if looped:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


## Runs on a worker thread (see _ready) -- an ambient loop is a few hundred thousand samples of
## GDScript math, which would otherwise be a visible hitch at boot.
func _build_music_task() -> void:
	var seconds := 16.0
	var n: int = int(seconds * MUSIC_RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	# Every frequency is a multiple of 1/16 Hz, so each sine completes a whole number of cycles
	# in the 16s loop and the loop point is seamless.
	var chord: Array[float] = [110.0, 164.8125, 220.0, 261.625]
	for i in n:
		var t: float = float(i) / MUSIC_RATE
		var swell: float = 0.7 + 0.3 * sin(TAU * t / 8.0)
		var v := 0.0
		for f in chord:
			v += sin(TAU * f * t)
		s[i] = v * 0.045 * swell
	# Sparse pentatonic bells over the drone.
	var bells: Array = [[1.0, 659.25], [3.5, 523.25], [6.0, 783.99], [8.5, 587.33], [11.0, 659.25], [13.0, 440.0]]
	for b: Array in bells:
		var start: int = int(float(b[0]) * MUSIC_RATE)
		var freq: float = float(b[1])
		var length: int = int(2.4 * MUSIC_RATE)
		for i in length:
			var t: float = float(i) / MUSIC_RATE
			var env: float = exp(-2.2 * t) * minf(1.0, float(i) / 60.0)
			s[(start + i) % n] += sin(TAU * freq * t) * env * 0.05
	call_deferred("_on_music_ready", _make_wav(s, MUSIC_RATE, true))


func _on_music_ready(wav: AudioStreamWAV) -> void:
	_music_player.stream = wav
	_music_player.play()


# ---------------------------------------------------------------------------
# Visual juice
# ---------------------------------------------------------------------------

func damage_number(world_pos: Vector2, amount: float, color: Color = Color.WHITE, big: bool = false) -> void:
	_floating_text(world_pos, str(int(round(amount))), color, 22 if big else 15)


func floating_text(world_pos: Vector2, text: String, color: Color = Color.WHITE) -> void:
	_floating_text(world_pos, text, color, 14)


func _floating_text(world_pos: Vector2, text: String, color: Color, font_size: int) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(80, 0)
	label.size = Vector2(80, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	label.z_as_relative = false
	label.z_index = 3000
	label.position = world_pos + Vector2(-40 + randf_range(-8, 8), -8)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(label)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 34.0, 0.7).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.35).set_delay(0.4)
	tween.chain().tween_callback(label.queue_free)


func shake(amount: float, duration: float = 0.18) -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("shake"):
		player.shake(amount, duration)


## Freezes the game for a few frames on a heavy hit. Uses time_scale rather than pausing so
## tweens/particles freeze too; the recovery timer ignores time_scale so it always fires.
func hit_stop(duration: float = 0.05) -> void:
	if _hitstop_active:
		return
	_hitstop_active = true
	Engine.time_scale = 0.08
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstop_active = false


func burst(pos: Vector2, color: Color, amount: int = 12, speed: float = 100.0, lifetime: float = 0.5) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var p := CPUParticles2D.new()
	p.position = pos
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2(0, 220)
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = color
	p.z_as_relative = false
	p.z_index = 2000
	scene.add_child(p)
	p.emitting = true
	get_tree().create_timer(lifetime + 0.2).timeout.connect(p.queue_free)


## Expanding ring -- used for AoE abilities so the radius the player sees matches the radius
## the damage check actually uses.
func ring(pos: Vector2, radius: float, color: Color, duration: float = 0.35) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var line := Line2D.new()
	line.points = circle(radius, 32)
	line.closed = true
	line.width = 3.0
	line.default_color = color
	line.position = pos
	line.scale = Vector2(0.25, 0.25)
	line.z_as_relative = false
	line.z_index = 1900
	scene.add_child(line)
	var tween := line.create_tween()
	tween.set_parallel(true)
	tween.tween_property(line, "scale", Vector2.ONE, duration).set_ease(Tween.EASE_OUT)
	tween.tween_property(line, "modulate:a", 0.0, duration)
	tween.chain().tween_callback(line.queue_free)


## Soft radial glow. Meant for PointLight2D use against the world's night-time CanvasModulate;
## radius is in world pixels. Add the returned light to the "night_lights" group and World.gd
## scales its energy with how dark it is.
func make_light(radius: float, color: Color, energy: float = 1.0) -> PointLight2D:
	if _glow_texture == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.3, 0.65, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.14), Color(1, 1, 1, 0)])
		_glow_texture = GradientTexture2D.new()
		_glow_texture.gradient = grad
		_glow_texture.fill = GradientTexture2D.FILL_RADIAL
		_glow_texture.fill_from = Vector2(0.5, 0.5)
		_glow_texture.fill_to = Vector2(1.0, 0.5)
		_glow_texture.width = 256
		_glow_texture.height = 256
	var light := PointLight2D.new()
	light.texture = _glow_texture
	light.texture_scale = radius / 128.0
	light.color = color
	light.energy = energy
	light.set_meta("base_energy", energy)
	light.add_to_group("night_lights")
	return light


static func ellipse(rx: float, ry: float, points: int = 16) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points:
		var a: float = TAU * float(i) / float(points)
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func circle(r: float, points: int = 16) -> PackedVector2Array:
	return ellipse(r, r, points)


## Convenience for building character/prop art out of Polygon2D primitives.
static func poly(parent: Node, points: PackedVector2Array, color: Color, pos: Vector2 = Vector2.ZERO, z: int = 0) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = points
	p.color = color
	p.position = pos
	p.z_index = z
	parent.add_child(p)
	return p
