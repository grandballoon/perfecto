## The spike's one screen: chords from a controller or the keyboard on the
## kernel, and what the mixing thread is doing, measured as it plays.
##
## A B X Y: the chords pad.json gives them in C, without LT and with it held
## (A I, B IV, X V, Y vii°; with LT, A I, B ii, X iii, Y vi). Pulling or
## letting go of LT while a face button holds a chord switches it to the
## button's chord in the other layer.
## Z X C V B N M: all seven, I to vii°. LB and RB (or Q and E): the sound.
## RT: swell the held chord, from 0.6 of its level to all of it.
## D-pad up and down (or the arrows): the player's volume, 6 dB a step, to
## hear whether Godot's volume ramp clicks at a short mix chunk.
## Back (or S): strike a lead ahead (constant latency, the default) or as
## soon as possible (sooner on average, but it varies by up to a chunk).
## Start (or T): strike chords by themselves for twenty seconds and measure
## how long each waits for a render.
##
## Run from the command line, after `--`:
##   --measure        that measurement, silent, printed, then quit
##   --sound <id>     the sound to measure with (a preset's id)
##   --voices <n>     strike chords of n notes, not four
##   --hold           strike one chord and hold it throughout, so exactly
##                    n voices sound (to set beside the offline benchmark)
##   --pad <file>     the face buttons' map, in place of pad.json
##   --asap           strike each chord as soon as possible, not a fixed lead
##                    from now (a block and a millisecond)
extends Control

## The seven chords of C major by degree, I to vii°: a bass and a close
## triad around middle C.
const CHORDS := [
	[48, 60, 64, 67],
	[38, 62, 65, 69],
	[40, 59, 64, 67],
	[41, 60, 65, 69],
	[43, 59, 62, 67],
	[45, 60, 64, 69],
	[47, 59, 62, 65],
]
const DEGREE_NAMES := ["I", "ii", "iii", "IV", "V", "vi", "vii°"]
## LT counts as held past this far, and let go short of it, apart enough
## that a trigger resting near one place cannot flicker between the layers.
const SHIFT_PULL := 0.55
const SHIFT_LET_GO := 0.45
const KEYS := {KEY_Z: 0, KEY_X: 1, KEY_C: 2, KEY_V: 3, KEY_B: 4, KEY_N: 5, KEY_M: 6}
const VELOCITY := 0.7
const REVERB := 0.16
const MEASURE_SECONDS := 20.0
const READOUT_SECONDS := 0.5
const VOLUME_STEP_DB := 6.0
const VOLUME_MIN_DB := -36.0

var stream := PerfectoStream.new()
var player := AudioStreamPlayer.new()
var presets: Array
var sound := 0
var label := Label.new()
var face_buttons: FaceButtons
var lt_held := false

## The input holding the chord sounding ("pad:<button>" or "key:<keycode>"),
## whose lifting ends it, and the chord's degree; and the face button, if a
## face button holds it (-1 if not), whose chord LT switches.
var held_input := ""
var held_button := -1
var held_degree := -1
var held_ids: Array[int] = []
var next_id := 1
## How loud the held chord is: 0.6 at rest, RT pulled all the way is whole.
var swell := 0.6
## Notes in each chord struck: the chord's own four, or more from the command line.
var voices := 4
var holding := false
## The frame each chord is struck for: -1 is the lead, 0 as soon as possible.
var strike_frame := -1

var measuring := 0.0
var next_strike := 0.0
var waits: Array[float] = []
var late := 0
var totals := MixTotals.new()
var window := MixTotals.new()
var shown := MixTotals.new()
var since_readout := 0.0
var quit_after_measure := false


## Mix statistics added up over a stretch of time.
class MixTotals:
	var calls := 0
	var frames := 0
	var block_min := 1 << 30
	var block_max := 0
	var interval_max_ms := 0.0
	var render_ns := 0.0
	var render_max_us := 0.0
	var load_max := 0.0

	func add(stats: Dictionary) -> void:
		if stats["calls"] == 0:
			return
		calls += stats["calls"]
		frames += stats["frames"]
		block_min = mini(block_min, stats["block_min"])
		block_max = maxi(block_max, stats["block_max"])
		interval_max_ms = maxf(interval_max_ms, stats["interval_max_ms"])
		render_ns += stats["render_mean_us"] * 1000.0 * stats["calls"]
		render_max_us = maxf(render_max_us, stats["render_max_us"])
		load_max = maxf(load_max, stats["load_max"])

	func load(rate: float) -> float:
		return render_ns / (frames / rate * 1e9) if frames else 0.0


func _ready() -> void:
	presets = Sounds.load_into(stream)
	player.stream = stream
	add_child(player)
	player.play()
	label.position = Vector2(24, 24)
	label.add_theme_font_size_override("font_size", 15)
	add_child(label)
	get_tree().auto_accept_quit = false
	read_arguments()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		leave()


## Quits once the mixing thread has let go of the playback: quitting while
## a player plays leaks it (Godot 4.7.2 does so with its own streams too).
func leave() -> void:
	player.stop()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()


func read_arguments() -> void:
	var args := OS.get_cmdline_user_args()
	var pad_path := FaceButtons.DEFAULT_PATH
	for i in args.size():
		match args[i]:
			"--sound":
				sound = presets.find_custom(func(p): return p["id"] == args[i + 1])
			"--voices":
				voices = int(args[i + 1])
			"--pad":
				pad_path = args[i + 1]
			"--hold":
				holding = true
			"--asap":
				strike_frame = 0
	face_buttons = FaceButtons.read(pad_path, DEGREE_NAMES)
	if face_buttons.error:
		push_error(face_buttons.error)
	if "--measure" in args:
		AudioServer.set_bus_volume_db(0, -80)
		quit_after_measure = true
		start_measuring()


func _process(delta: float) -> void:
	var stats: Dictionary = stream.take_mix_stats()
	late += stats["late"]
	if stats["block_max"]:
		stream.set_lead_frames(maxi(totals.block_max, stats["block_max"]) + int(stream.sample_rate() / 1000))
	totals.add(stats)
	window.add(stats)
	waits.append_array(stats["waits_ms"])
	if measuring > 0:
		measuring -= delta
		next_strike -= delta
		if next_strike <= 0 and not (holding and held_ids):
			strike(randi() % CHORDS.size(), "measure")
			next_strike = randf_range(0.15, 0.35)
		if measuring <= 0:
			release()
			print(report())
			if quit_after_measure:
				leave()
	since_readout += delta
	if since_readout > READOUT_SECONDS:
		since_readout = 0
		shown = window
		window = MixTotals.new()
		label.text = report()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		if event.button_index in FaceButtons.BUTTONS.values():
			var degree: int = face_buttons.layer(lt_held).get(event.button_index, -1)
			chord_input("pad:%d" % event.button_index, degree, event.pressed)
			if event.pressed and degree >= 0:
				held_button = event.button_index
		else:
			button(event.button_index, event.pressed)
	elif event is InputEventKey and not event.echo:
		if event.keycode in KEYS:
			chord_input("key:%d" % event.keycode, KEYS[event.keycode], event.pressed)
		elif event.pressed and event.keycode == KEY_Q:
			button(JOY_BUTTON_LEFT_SHOULDER, true)
		elif event.pressed and event.keycode == KEY_E:
			button(JOY_BUTTON_RIGHT_SHOULDER, true)
		elif event.pressed and event.keycode == KEY_T:
			button(JOY_BUTTON_START, true)
		elif event.pressed and event.keycode == KEY_S:
			button(JOY_BUTTON_BACK, true)
		elif event.pressed and event.keycode == KEY_UP:
			button(JOY_BUTTON_DPAD_UP, true)
		elif event.pressed and event.keycode == KEY_DOWN:
			button(JOY_BUTTON_DPAD_DOWN, true)
	elif event is InputEventJoypadMotion and event.axis == JOY_AXIS_TRIGGER_LEFT:
		var pull := (event as InputEventJoypadMotion).axis_value
		if (pull < SHIFT_LET_GO) if lt_held else (pull > SHIFT_PULL):
			switch_layer(not lt_held)
	elif event is InputEventJoypadMotion and event.axis == JOY_AXIS_TRIGGER_RIGHT:
		var level := 0.6 + 0.4 * (event as InputEventJoypadMotion).axis_value
		if absf(level - swell) > 0.01:
			swell = level
			for id in held_ids:
				stream.note_change(id, 1.0, swell, REVERB)


## LT pulled or let go: a face button holding a chord switches to its chord
## in the other layer, or ends it if it has none there. A button with the
## same chord in both (A) goes on sounding.
func switch_layer(held: bool) -> void:
	lt_held = held
	if held_button < 0:
		label.text = report()
		return
	var degree: int = face_buttons.layer(lt_held).get(held_button, -1)
	if degree < 0:
		release()
	elif degree != held_degree:
		var button := held_button
		strike(degree, held_input)
		held_button = button
	label.text = report()


## A chord's button or key: pressed, it strikes `degree` (-1 is none, a
## button its layer leaves out); lifted, it ends the chord if it is the one
## holding it, whatever LT has done meanwhile.
func chord_input(input: String, degree: int, pressed: bool) -> void:
	if pressed and degree >= 0:
		strike(degree, input)
	elif not pressed and input == held_input:
		release()


func button(index: int, pressed: bool) -> void:
	if pressed and index == JOY_BUTTON_LEFT_SHOULDER:
		sound = posmod(sound - 1, presets.size())
	elif pressed and index == JOY_BUTTON_RIGHT_SHOULDER:
		sound = posmod(sound + 1, presets.size())
	elif pressed and index == JOY_BUTTON_START:
		start_measuring()
	elif pressed and index == JOY_BUTTON_BACK:
		strike_frame = 0 if strike_frame < 0 else -1
		forget_waits()
	elif pressed and index == JOY_BUTTON_DPAD_UP:
		player.volume_db = minf(0.0, player.volume_db + VOLUME_STEP_DB)
	elif pressed and index == JOY_BUTTON_DPAD_DOWN:
		player.volume_db = maxf(VOLUME_MIN_DB, player.volume_db - VOLUME_STEP_DB)


## The chord's notes, extended upward by its own tones to `count` notes.
func notes_of(chord: Array, count: int) -> Array:
	var notes := []
	for i in count:
		notes.append(chord[i % chord.size()] + 12 * (i / chord.size()))
	return notes


func strike(degree: int, input: String) -> void:
	release()
	held_input = input
	held_degree = degree
	var notes := notes_of(CHORDS[degree], voices)
	for i in notes.size():
		var pan := lerpf(-0.3, 0.3, float(i) / maxi(1, notes.size() - 1))
		stream.note_on(next_id, notes[i], VELOCITY, sound, pan, REVERB, strike_frame)
		stream.note_change(next_id, 1.0, swell, REVERB)
		held_ids.append(next_id)
		next_id += 1
	label.text = report()


func release() -> void:
	for id in held_ids:
		stream.note_off(id, 0)
	held_ids.clear()
	held_input = ""
	held_button = -1
	held_degree = -1
	label.text = report()


func start_measuring() -> void:
	measuring = MEASURE_SECONDS
	next_strike = 0
	forget_waits()
	totals = MixTotals.new()


## Starts the strike-to-render figures afresh, as when the timing changes.
func forget_waits() -> void:
	waits.clear()
	late = 0


func report() -> String:
	var rate: float = stream.sample_rate()
	var kernel_ms: float = stream.latency_frames() / rate * 1000
	# CoreAudio reports no latency to Godot. Its device buffer is the output latency
	# setting in frames, to a power of two, and a render waits out the longer of
	# that and Godot's mix chunk (the block asked of the stream).
	var setting: int = ProjectSettings.get_setting("audio/driver/output_latency")
	var device_frames := closest_po2(int(setting * rate / 1000))
	var buffer_ms := maxf(AudioServer.get_output_latency() * 1000, maxf(device_frames, totals.block_max) / rate * 1000)
	var lines := PackedStringArray()
	lines.append("Sound: %s  (LB/RB or Q/E)" % presets[sound]["name"])
	lines.append("Strikes: %s  (Back or S)" % ("a lead ahead, constant" if strike_frame < 0 else "as soon as possible"))
	lines.append("Volume: %d dB  (d-pad or arrows up and down)" % player.volume_db)
	lines.append("Chord: %s  (keys Z to M: I to vii°)" % (DEGREE_NAMES[held_degree] if held_degree >= 0 else "none"))
	if face_buttons.error:
		lines.append("The face buttons play nothing: %s" % face_buttons.error)
	else:
		lines.append("Face buttons%s: %s.  With LT%s: %s." % [
			"" if lt_held else " (now)", face_buttons.describe(false, DEGREE_NAMES),
			" (now)" if lt_held else "", face_buttons.describe(true, DEGREE_NAMES)])
	lines.append("RT swells.  Start or T measures for %d s." % MEASURE_SECONDS)
	var chunk: int = ProjectSettings.get_setting("audio/driver/mix_buffer_frames", 512)
	if totals.block_max and totals.block_max != chunk:
		lines.append("This Godot mixes %d frames, not the %d set: open the project with ./play.sh." % [totals.block_max, chunk])
	lines.append("")
	lines.append("Mix rate %d Hz.  Mix chunk %d frames, device buffer %d frames: output buffer %.1f ms.  Kernel latency %.1f ms." % [
		rate, totals.block_max, device_frames, buffer_ms, kernel_ms])
	lines.append("Last %.1f s: %d mix calls, blocks %d–%d frames, longest gap %.2f ms, render load %.2f%%, worst block %.1f%%" % [
		READOUT_SECONDS, shown.calls, shown.block_min, shown.block_max, shown.interval_max_ms,
		shown.load(rate) * 100, shown.load_max * 100])
	lines.append("Since measuring began: %d calls, blocks %d–%d, longest gap %.2f ms, render load %.2f%%, worst render %.0f µs (%.1f%% of its block)" % [
		totals.calls, totals.block_min, totals.block_max, totals.interval_max_ms, totals.load(rate) * 100,
		totals.render_max_us, totals.load_max * 100])
	if waits:
		var sorted := waits.duplicate()
		sorted.sort()
		var mean := 0.0
		for w in sorted:
			mean += w
		mean /= sorted.size()
		lines.append("Strike → render (%s): %d strikes, %d late, mean %.2f ms, median %.2f, p95 %.2f, max %.2f" % [
			"stamped a lead ahead" if strike_frame < 0 else "as soon as possible", sorted.size(), late, mean, sorted[sorted.size() / 2], sorted[int(sorted.size() * 0.95)], sorted[-1]])
		lines.append("Strike → out of Godot (no input, no hardware): mean %.1f ms, worst %.1f ms" % [
			mean + buffer_ms + kernel_ms, sorted[-1] + buffer_ms + kernel_ms])
	if measuring > 0:
		lines.append("Measuring… %d s left" % ceili(measuring))
	return "\n".join(lines)


## The power of two nearest `n`, as Godot's CoreAudio driver sizes its buffer.
func closest_po2(n: int) -> int:
	var above := nearest_po2(n)
	return above / 2 if n - above / 2 < above - n else above
