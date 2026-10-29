## The kernel's cost, offline, inside Godot: each sound at several voice
## counts, rendered on a kernel of its own as fast as it goes.
##
##   godot --headless --path project --script res://measure/bench.gd
extends SceneTree

const VOICES := [0, 1, 8, 16, 32, 64]
const SECONDS := 4.0
const BLOCK := 256


func _init() -> void:
	var stream := PerfectoStream.new()
	var presets := Sounds.load_into(stream)
	print("sound, then for each of %s voices: load %% of one core (worst block %%); ns per voice-frame at 64" % [VOICES])
	var per_voice: Array[float] = []
	for i in presets.size():
		var cells := PackedStringArray()
		var silent := 0.0
		var last := {}
		for voices in VOICES:
			last = stream.benchmark(i, voices, SECONDS, BLOCK)
			if voices == 0:
				silent = last["ns_per_frame"]
			cells.append("%5.2f (%5.2f)" % [last["load"] * 100, last["worst_block_load"] * 100])
		var ns: float = (last["ns_per_frame"] - silent) / VOICES[-1]
		per_voice.append(ns)
		print("%-15s %s   %5.1f" % [presets[i]["name"], "  ".join(cells), ns])
	per_voice.sort()
	print("ns per voice-frame across sounds: min %.1f, median %.1f, max %.1f" % [
		per_voice[0], per_voice[per_voice.size() / 2], per_voice[-1]])
	quit()
