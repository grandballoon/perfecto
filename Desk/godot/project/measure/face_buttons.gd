## What the face buttons strike, as `pad.json` (or the file given with
## `--pad`) says: a degree for each of A, B, X and Y, without LT and with it
## held. A button a layer leaves out strikes nothing in it.
##
##   {"plain": {"A": "I", "B": "IV", "X": "V", "Y": "vii°"},
##    "LT":    {"A": "I", "B": "ii", "X": "iii", "Y": "vi"}}
class_name FaceButtons

const DEFAULT_PATH := "res://measure/pad.json"
const BUTTONS := {"A": JOY_BUTTON_A, "B": JOY_BUTTON_B, "X": JOY_BUTTON_X, "Y": JOY_BUTTON_Y}
const LAYERS := ["plain", "LT"]

## Each layer, a button's index to a degree (0 is I).
var plain := {}
var shifted := {}
## What was wrong with the file, or "" if nothing was.
var error := ""


static func read(path: String, degree_names: Array) -> FaceButtons:
	if not FileAccess.file_exists(path):
		var missing := FaceButtons.new()
		missing.error = "%s: no such file" % path
		return missing
	return parse(FileAccess.get_file_as_string(path), degree_names, path)


## The layers in `text`, with degrees named as `degree_names` names them
## ("vii" is also vii°). Anything wrong leaves both layers empty, so a
## mistake is never played as half a map.
static func parse(text: String, degree_names: Array, source: String) -> FaceButtons:
	var buttons := FaceButtons.new()
	var problems := PackedStringArray()
	var json = JSON.parse_string(text)
	if not json is Dictionary:
		buttons.error = "%s is not a JSON object" % source
		return buttons
	for name in json:
		if name not in LAYERS:
			problems.append("no layer \"%s\" (there are %s)" % [name, ", ".join(LAYERS)])
	var layers := [{}, {}]
	for i in LAYERS.size():
		var given = json.get(LAYERS[i], {})
		if not given is Dictionary:
			problems.append("\"%s\" is not an object" % LAYERS[i])
			continue
		for button in given:
			var degree_name := str(given[button])
			var degree := degree_names.find("vii°" if degree_name == "vii" else degree_name)
			if button not in BUTTONS:
				problems.append("no button \"%s\" (there are A, B, X and Y)" % button)
			elif degree < 0:
				problems.append("no degree \"%s\" (there are %s)" % [given[button], ", ".join(degree_names)])
			else:
				layers[i][BUTTONS[button]] = degree
	if problems:
		buttons.error = "%s: %s" % [source, "; ".join(problems)]
	else:
		buttons.plain = layers[0]
		buttons.shifted = layers[1]
	return buttons


func layer(lt_held: bool) -> Dictionary:
	return shifted if lt_held else plain


## A layer as the screen shows it: "A I, B IV, X V, Y vii°".
func describe(lt_held: bool, degree_names: Array) -> String:
	var parts := PackedStringArray()
	for name in BUTTONS:
		var degree: int = layer(lt_held).get(BUTTONS[name], -1)
		parts.append("%s %s" % [name, degree_names[degree] if degree >= 0 else "–"])
	return ", ".join(parts)
