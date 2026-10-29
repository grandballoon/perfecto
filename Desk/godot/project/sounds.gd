## The presets as `dump-presets` wrote them, loaded into a stream's kernel
## with the mix the desk uses (`DeskAudio`).
class_name Sounds

static func load_into(stream: PerfectoStream) -> Array:
	var presets: Array = JSON.parse_string(FileAccess.get_file_as_string("res://presets.json"))
	var count := mini(presets.size(), stream.sound_count())
	for i in count:
		stream.set_sound(i, presets[i]["patch"])
	stream.set_mix(0.8, 2.6, 0.02, 5200, 0.47, 0.35)
	return presets.slice(0, count)
