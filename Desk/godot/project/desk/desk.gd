## Perfecto Desk: played from a game controller (or the keyboard), on the
## kernel's sound and MIDI. `PerfectoDesk` holds the desk and plays its
## effects; this steps it every frame, draws the scene it shows, and does
## what is left to a script: notices, saving files, and the mouse.
##
## The window, top to bottom: the layouts and what the desk is set to; the
## stage beside the hand (what every control does) or the favorites; a line
## saying what plays; the piano. The menu opens over it all.
extends Control

const PAD := 18.0
const SIDE := 330.0
const TOP := 56.0
const STATUS := 20.0
const PIANO := 64.0
const GAP := 14.0
## How often the screen is drawn at most.
const SCREEN_RATE := 60.0
## How long a rumble and a notice are shown.
const RUMBLE_SHOWN := 0.4
const NOTICE_SHOWN := 3.0
## From C2 to C7: where the desk's chords and lines are.
const PIANO_LOW := 36
const PIANO_HIGH := 96
## What Face Chords' face buttons strike (see `FaceButtons`).
const FACE_CHORDS := "res://desk/face_chords.json"
const DEGREE_NAMES := ["I", "ii", "iii", "IV", "V", "vi", "vii°"]
const T := Paint.Text

var stream := PerfectoStream.new()
var player := AudioStreamPlayer.new()
var desk := PerfectoDesk.new()
var scene := {}
var sounding := {}
## Which the side column shows: the hand, or the favorites.
var tab := "controls"
var hits: Array = []
var rumble := ""
var rumble_time := 0.0
var notice := ""
var notice_time := 0.0
var since_drawn := 0.0
var renaming := LineEdit.new()
var renaming_table := -1


func _ready() -> void:
	fit_window()
	Paint.follow_system()
	var presets := Sounds.load_into(stream)
	# Before the stream plays: the desk loads the drums' recordings into the kernel.
	desk.setup(stream, presets)
	player.stream = stream
	add_child(player)
	player.play()
	read_face_chords()
	renaming.visible = false
	renaming.text_submitted.connect(_renamed)
	renaming.focus_exited.connect(func(): renaming.visible = false)
	add_child(renaming)
	get_tree().auto_accept_quit = false
	scene = desk.scene()


## Plays Face Chords' buttons as `face_chords.json` says, if it is there;
## a mistake in it is shown and leaves the standard map.
func read_face_chords() -> void:
	if not FileAccess.file_exists(FACE_CHORDS):
		return
	var buttons := FaceButtons.read(FACE_CHORDS, DEGREE_NAMES)
	if buttons.error:
		show_notice(buttons.error)
	else:
		desk.set_face_map(buttons.plain, buttons.shifted)


## Lays the window out in points, as the Mac desk's: 1440 by 900 to start
## with and never under 1180 by 760, within the screen.
func fit_window() -> void:
	var window := get_window()
	var scale := DisplayServer.screen_get_scale(window.current_screen)
	var screen := DisplayServer.screen_get_usable_rect(window.current_screen)
	window.content_scale_factor = scale
	var room := Vector2(screen.size) * 0.95
	window.min_size = Vector2i((Vector2(1180, 760) * scale).min(room))
	window.size = Vector2i((Vector2(1440, 900) * scale).min(room))
	window.position = screen.position + (screen.size - window.size) / 2


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		leave()


## Lets go of every note and quits once the mixing thread has let go of
## the playback: quitting while a player plays leaks it.
func leave() -> void:
	desk.let_go()
	player.stop()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()


func _process(delta: float) -> void:
	for effect in desk.step(not renaming.visible):
		match effect["kind"]:
			"rumble":
				show_rumble(effect["rumble"])
			"refuse":
				show_rumble("no")
				show_notice(effect["reason"])
			"save_midi":
				save(effect["bytes"], effect["name"])
	since_drawn += delta
	if since_drawn < 1.0 / SCREEN_RATE:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var changed := Paint.follow_system()
	if rumble and now - rumble_time > RUMBLE_SHOWN:
		rumble = ""
		changed = true
	if notice and now - notice_time > NOTICE_SHOWN:
		notice = ""
		changed = true
	var heard := desk.sounding()
	if heard != sounding:
		sounding = heard
		changed = true
	if desk.scene_changed():
		scene = desk.scene()
		changed = true
	if changed:
		since_drawn = 0
		queue_redraw()


func show_rumble(kind: String) -> void:
	rumble = kind
	rumble_time = Time.get_ticks_msec() / 1000.0


func show_notice(text: String) -> void:
	notice = text
	notice_time = Time.get_ticks_msec() / 1000.0
	queue_redraw()


## Saves a Standard MIDI File in Music › Perfecto Desk, and shows it.
func save(bytes: PackedByteArray, name: String) -> void:
	var folder := OS.get_system_dir(OS.SYSTEM_DIR_MUSIC).path_join("Perfecto Desk")
	var path := folder.path_join(name + ".mid")
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		show_notice("Could not save: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_buffer(bytes)
	file.close()
	show_notice("Saved %s in Music › Perfecto Desk" % path.get_file())
	OS.shell_show_in_file_manager(path)


# The mouse.

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	# The last drawn is on top.
	for i in range(hits.size() - 1, -1, -1):
		var hit: Array = hits[i]
		if (hit[0] as Rect2).has_point(event.position):
			choose(hit[1])
			accept_event()
			return


func choose(action: Dictionary) -> void:
	match action["kind"]:
		"tab":
			tab = action["tab"]
			queue_redraw()
		"rename":
			renaming_table = action["index"]
			renaming.text = action["name"]
			renaming.position = action["rect"].position
			renaming.size = action["rect"].size
			renaming.visible = true
			renaming.grab_focus()
			renaming.select_all()
		"none":
			pass
		_:
			desk.perform(action)
			scene = desk.scene()
			queue_redraw()


func _renamed(text: String) -> void:
	desk.perform({"kind": "rename_table", "index": renaming_table, "text": text})
	renaming.visible = false
	scene = desk.scene()
	queue_redraw()


# Drawing.

func _draw() -> void:
	hits.clear()
	var whole := Rect2(Vector2.ZERO, size)
	draw_rect(whole, Paint.color("background"))
	if scene.is_empty():
		return
	var inner := whole.grow(-PAD)
	var y := inner.position.y
	top_bar(Rect2(inner.position.x, y, inner.size.x, TOP))
	y += TOP + GAP
	var middle := inner.end.y - PIANO - GAP - STATUS - GAP - y
	Stage.draw(self, Rect2(inner.position.x, y, inner.size.x - SIDE - 16, middle), scene["stage"], hits)
	side_column(Rect2(inner.end.x - SIDE, y, SIDE, middle))
	y += middle + GAP
	status_line(Rect2(inner.position.x, y, inner.size.x, STATUS))
	y += STATUS + GAP
	piano(Rect2(inner.position.x, y, inner.size.x, PIANO))
	if scene["menu"] != null:
		menu(whole, scene["menu"])


## A capsule button with `label`, which a click on does `action`; returns its width.
func button(at: Vector2, label: String, chosen: bool, action: Dictionary, px := 13, enabled := true) -> float:
	var text := T.new(label, px, 600)
	var rect := Rect2(at, Vector2(text.width() + 28, text.height() + 12))
	var tint := Paint.CHORD if chosen else Paint.color("raised")
	if not enabled:
		tint.a *= 0.5
	Paint.capsule(self, rect, tint)
	text.draw_centred(self, rect.get_center(), Paint.INK if chosen else Paint.color("text" if enabled else "faint"))
	if enabled:
		hits.append([rect, action])
	return rect.size.x


## The layouts, chosen by Back or a click, and what the desk is set to.
func top_bar(rect: Rect2) -> void:
	var top: Dictionary = scene["top"]
	var x := rect.position.x
	for i in top["layouts"].size():
		x += button(Vector2(x, rect.position.y), top["layouts"][i], i == top["chosen"], {"kind": "choose_layout", "index": i}) + 6
	var back := T.new("Back ▸", 10, 700, true)
	back.draw_centred(self, Vector2(x + back.width() / 2, rect.position.y + 15), Paint.color("faint"))
	var menu_label := T.new("☰  Menu", 13, 600)
	button(Vector2(rect.end.x - menu_label.width() - 28, rect.position.y), "☰  Menu", false, {"kind": "toggle_menu"})
	var line := rect.position.y + 38
	T.new(top["summary"], 12).draw(self, Vector2(rect.position.x, line), Paint.color("secondary"))
	# The facts from the right, so they keep their places as the summary changes.
	var widths := []
	var total := 0.0
	for fact in top["facts"]:
		var w := T.new(fact[0].to_upper(), 9, 700, true).width() + 5 + T.new(fact[1], 12, 600).width()
		widths.append(w)
		total += w + 16
	x = rect.end.x - total + 16
	if top["guard"] != null:
		var guard_width := guard_chip(Vector2.ZERO, top["guard"], true)
		guard_chip(Vector2(x - 16 - guard_width, line - 3), top["guard"], false)
	for i in top["facts"].size():
		Stage.fact(self, Vector2(x, line), top["facts"][i][0], top["facts"][i][1])
		x += widths[i] + 16


## The consonance guard while it is on: its mode, and in the run the notes
## it has heard. Returns its width; draws it unless `measuring`.
func guard_chip(at: Vector2, guard: Array, measuring: bool) -> float:
	var mode := T.new("◆ " + guard[0], 11, 600)
	var pool := T.new(guard[1], 10, 500, true)
	var width := mode.width() + (pool.width() + 6 if guard[1] else 0.0) + 18
	if measuring:
		return width
	var rect := Rect2(at, Vector2(width, 20))
	Paint.capsule(self, rect, Paint.NEAR)
	mode.draw_centred(self, Vector2(at.x + 9 + mode.width() / 2, rect.get_center().y), Paint.INK)
	if guard[1]:
		pool.draw_centred(self, Vector2(at.x + 15 + mode.width() + pool.width() / 2, rect.get_center().y), Color(Paint.INK, 0.75))
	return width


## The column beside the stage: what each control does, or the favorites.
func side_column(rect: Rect2) -> void:
	Stage.panel_box(self, rect)
	var inner := rect.grow(-16)
	# A segmented switch between the two.
	var tabs := Rect2(inner.position, Vector2(inner.size.x, 24))
	Paint.box(self, tabs, Paint.color("raised"), 7)
	var half := Vector2(tabs.size.x / 2, tabs.size.y)
	for i in 2:
		var which: String = ["controls", "favorites"][i]
		var part := Rect2(tabs.position + Vector2(half.x * i, 0), half)
		if tab == which:
			Paint.box(self, part.grow(-2), Paint.color("panel"), 6)
		T.new(which.capitalize(), 12, 600 if tab == which else 500).draw_centred(self, part.get_center(), Paint.color("text"))
		hits.append([part, {"kind": "tab", "tab": which}])
	var body := Rect2(inner.position.x, inner.position.y + 38, inner.size.x, inner.size.y - 38)
	if tab == "controls":
		hand(body, scene["hand"])
	else:
		favorites(body, scene["favorites"])


## What every control does now, relabelled as layers change, each lit while
## it is held: the left hand's controls on the left, the right's on the right.
func hand(rect: Rect2, h: Dictionary) -> void:
	Stage.caption(self, Rect2(rect.position, Vector2(rect.size.x, 16)), h["caption"], "What each control does")
	var width := (rect.size.x - 18) / 2
	for side in 2:
		var x := rect.position.x + side * (width + 18)
		var y := rect.position.y + 28
		for entry in h["left" if side == 0 else "right"]:
			var chip := Stage.control_chip(self, Vector2(x + 14, y + 10), entry["mark"], entry["held"], entry["tint"])
			var tx := x + 14 + chip.size.x / 2 + 8
			var used := Paint.paragraph(self, Vector2(tx, y), x + width - tx, entry["text"], 12, Paint.color("text"), 500, 2)
			if entry["key"]:
				T.new(entry["key"], 10, 500, false, false, true).draw(self, Vector2(tx, y + used), Paint.color("faint"))
				used += 13
			y += maxf(20, used) + 7


## Favorite colorations: the tables, which one is played and which is the
## key's own, and the colors pinned to each chord of the key in it.
func favorites(rect: Rect2, f: Dictionary) -> void:
	var x := rect.position.x
	var w := rect.size.x
	var y := rect.position.y
	Stage.caption(self, Rect2(x, y, w, 16), "Tables", "The one played is lit")
	y += 24
	for i in f["tables"].size():
		var table: Dictionary = f["tables"][i]
		var row := Rect2(x, y, w, 32)
		var active: bool = table["active"]
		Paint.box(self, row, Paint.CHORD if active else Paint.color("raised", 0.6), 8)
		hits.append([row, {"kind": "play_table", "index": i}])
		var name := T.new(table["name"], 13, 600)
		name.draw_centred(self, Vector2(x + 10 + name.width() / 2, row.get_center().y), Paint.INK if active else Paint.color("text"))
		if table["default"]:
			var own := T.new("key's own", 9, 700)
			own.draw_centred(self, Vector2(x + 18 + name.width() + own.width() / 2, row.get_center().y),
					Color(Paint.INK, 0.6) if active else Paint.CHORD)
		var pencil := Rect2(row.end.x - 30, row.position.y, 30, 32)
		T.new("✎", 13).draw_centred(self, pencil.get_center(), Color(Paint.INK, 0.7) if active else Paint.color("secondary"))
		hits.append([pencil, {"kind": "rename", "index": i, "name": table["name"], "rect": row.grow(-3)}])
		var count := T.new(str(table["count"]), 11, 500, true)
		count.draw_centred(self, Vector2(pencil.position.x - 4 - count.width() / 2, row.get_center().y),
				Color(Paint.INK, 0.6) if active else Paint.color("faint"))
		y += 36
	button(Vector2(x, y), "New table", false, {"kind": "add_table"}, 11)
	var remove := T.new("Remove", 11, 600).width() + 28
	button(Vector2(rect.end.x - remove, y), "Remove", false, {"kind": "remove_table"}, 11, f["can_remove"])
	y += 34
	# The key's own table: a box to tick.
	var box := Rect2(x, y + 1, 14, 14)
	Paint.box(self, box, Paint.CHORD if f["is_key_default"] else Paint.color("raised"), 3, Paint.color("rule"))
	if f["is_key_default"]:
		T.new("✓", 11, 700).draw_centred(self, box.get_center(), Paint.INK)
	var said := Paint.paragraph(self, Vector2(x + 22, y), w - 22, f["key_default"], 11, Paint.color("text"))
	hits.append([Rect2(x, y, w, maxf(16, said)), {"kind": "set_key_default", "value": 0 if f["is_key_default"] else 1}])
	y += maxf(16, said) + 12
	draw_line(Vector2(x, y), Vector2(rect.end.x, y), Paint.color("rule", 0.6))
	y += 12
	Stage.caption(self, Rect2(x, y, w, 16), f["pinned_caption"], f["pinned_title"])
	y += 24
	var pin := Rect2(x, y, w, 26)
	Paint.box(self, pin, Paint.color("raised", 1.0 if f["can_pin"] else 0.5), 7)
	T.new("📌 " + f["pin"], 12, 600).fitted(w - 12).draw_centred(self, pin.get_center(), Paint.color("text" if f["can_pin"] else "faint"))
	if f["can_pin"]:
		hits.append([pin, {"kind": "pin_played"}])
	y += 34
	for d in f["degrees"].size():
		var degree: Dictionary = f["degrees"][d]
		T.new(degree["numeral"], 11, 700, true).draw(self, Vector2(x, y + 4), Paint.color("secondary"))
		var cx := x + 34
		if degree["pinned"].is_empty():
			T.new("—", 12).draw(self, Vector2(cx, y + 3), Paint.color("faint"))
		for c in degree["pinned"].size():
			var chip_text := T.new(degree["pinned"][c], 12, 600, true)
			var chip := Rect2(cx, y, chip_text.width() + 30, 22)
			if chip.end.x > rect.end.x and cx > x + 34:
				cx = x + 34
				y += 26
				chip.position = Vector2(cx, y)
			Paint.box(self, chip, Paint.color("raised"), 6)
			chip_text.draw(self, Vector2(chip.position.x + 7, chip.get_center().y - chip_text.height() / 2), Paint.color("text"))
			var cross := Rect2(chip.end.x - 18, chip.position.y, 18, 22)
			T.new("✕", 8, 700).draw_centred(self, cross.get_center(), Paint.color("secondary"))
			hits.append([cross, {"kind": "unpin", "index": d, "value": c}])
			cx = chip.end.x + 5
		y += 28
	Paint.paragraph(self, Vector2(x, y + 4), w, f["help"], 11, Paint.color("secondary"))


## What plays, what was felt, and anything just done.
func status_line(rect: Rect2) -> void:
	var mid := rect.get_center().y
	var controller := desk.has_controller()
	var x := rect.position.x
	var icon := T.new("🎮" if controller else "⌨", 13)
	icon.draw_centred(self, Vector2(x + icon.width() / 2, mid), Paint.NEAR if controller else Paint.color("secondary"))
	x += icon.width() + 8
	var name := T.new(desk.input_name(), 12, 600)
	name.draw_centred(self, Vector2(x + name.width() / 2, mid), Paint.color("text"))
	x += name.width() + 14
	if not controller:
		var hint := T.new("No controller: the keyboard plays. Connect an Xbox controller to play from it.", 11)
		hint.draw_centred(self, Vector2(x + hint.width() / 2, mid), Paint.color("secondary"))
		x += hint.width() + 14
	if rumble:
		var felt := T.new("· " + rumble, 11, 600, true)
		felt.draw_centred(self, Vector2(x + felt.width() / 2, mid), Paint.NEAR)
	# What the targets' marks mean, from the right.
	var right := rect.end.x
	for swatch in [["aimed", Paint.CHORD, false], ["borrowed", Paint.color("borrowed", 0.5), true], ["one step away", Paint.color("near", 0.4), false]]:
		var label := T.new(swatch[0], 10)
		right -= label.width()
		label.draw_centred(self, Vector2(right + label.width() / 2, mid), Paint.color("secondary"))
		right -= 16
		var box := Rect2(right, mid - 5, 12, 10)
		Paint.box(self, box, Color(swatch[1], 0 if swatch[2] else 0.6 * swatch[1].a), 3, swatch[1], 1.5, swatch[2])
		right -= 10
	if notice:
		var said := T.new(notice, 11)
		said.draw_centred(self, Vector2(right - 14 - said.width() / 2, mid), Paint.color("secondary"))


## The notes sounding, on a piano's keys: the chords in orange, the line in blue.
func piano(rect: Rect2) -> void:
	var whites := []
	for note in range(PIANO_LOW, PIANO_HIGH + 1):
		if not black(note):
			whites.append(note)
	var width := rect.size.x / whites.size()
	for i in whites.size():
		var note: int = whites[i]
		var key := Rect2(rect.position.x + i * width, rect.position.y, width - 1, rect.size.y)
		Paint.box(self, key, lit(note, Color(0.96, 0.96, 0.96)), 3, Color(0.55, 0.55, 0.55), 0.5)
		if note % 12 == 0:
			T.new("C%d" % (note / 12 - 1), 8, 500).draw_centred(self, Vector2(key.get_center().x, key.end.y - 8), Color(0.45, 0.45, 0.45))
	for note in range(PIANO_LOW, PIANO_HIGH + 1):
		if black(note):
			var before := whites.find(note - 1)
			var key := Rect2(rect.position.x + (before + 1) * width - width * 0.31, rect.position.y, width * 0.62, rect.size.y * 0.6)
			Paint.box(self, key, lit(note, Color(0.12, 0.12, 0.12)), 2)


func lit(note: int, otherwise: Color) -> Color:
	if note in sounding.get("melody", PackedInt32Array()):
		return Paint.MELODY
	if note in sounding.get("chord", PackedInt32Array()):
		return Paint.CHORD
	return otherwise


static func black(note: int) -> bool:
	return note % 12 in [1, 3, 6, 8, 10]


## The menu over the stage: a row for each setting, or the sound library. A
## click outside it closes it.
func menu(whole: Rect2, m: Dictionary) -> void:
	draw_rect(whole, Color(0, 0, 0, 0.45))
	hits.append([whole, {"kind": "toggle_menu"}])
	if m["library"] != null:
		library(whole, m["library"])
		return
	var rows: Array = m["rows"]
	var row_height := 34.0
	var size := Vector2(420, 32 + 28 + rows.size() * (row_height + 4) + 34)
	var rect := Rect2(whole.get_center() - size / 2, size)
	Stage.panel_box(self, rect)
	hits.append([rect, {"kind": "none"}])
	var inner := rect.grow(-16)
	Stage.caption(self, Rect2(inner.position, Vector2(inner.size.x, 16)), "Start", "Menu")
	var y := inner.position.y + 28
	for row in rows:
		var line := Rect2(inner.position.x, y, inner.size.x, row_height)
		var chosen: bool = row["chosen"]
		if chosen:
			Paint.box(self, line, Paint.CHORD, 8)
		var ink := Paint.INK if chosen else Paint.color("text")
		var name := T.new(row["name"], 14, 500)
		name.draw_centred(self, Vector2(line.position.x + 14 + name.width() / 2, line.get_center().y), ink)
		var value := T.new(row["value"], 14, 600, true)
		var arrows: bool = chosen and row["changes"]
		var right := line.end.x - 14
		if arrows:
			var after := T.new("▶", 12)
			after.draw_centred(self, Vector2(right - after.width() / 2, line.get_center().y), Paint.color("faint"))
			right -= after.width() + 6
		value.draw_centred(self, Vector2(right - value.width() / 2, line.get_center().y), ink)
		right -= value.width() + 6
		if arrows:
			var before := T.new("◀", 12)
			before.draw_centred(self, Vector2(right - before.width() / 2, line.get_center().y), Paint.color("faint"))
		y += row_height + 4
	T.new("↑ ↓ choose · ← → change · A open · B close", 11).draw(self, Vector2(inner.position.x, y + 8), Paint.color("secondary"))


## The sound library: a column for each category, its sounds down it. A
## sound is heard as it is reached.
func library(whole: Rect2, l: Dictionary) -> void:
	var categories: Array = l["categories"]
	var column := 140.0
	var longest := 0
	for category in categories:
		longest = maxi(longest, category["sounds"].size())
	var size := Vector2(categories.size() * (column + 10) - 10 + 32, 32 + 28 + 22 + longest * 34 + 34)
	var rect := Rect2(whole.get_center() - size / 2, size)
	Stage.panel_box(self, rect)
	hits.append([rect, {"kind": "none"}])
	var inner := rect.grow(-16)
	Stage.caption(self, Rect2(inner.position, Vector2(inner.size.x, 16)), l["line"], "Sound library")
	for c in categories.size():
		var category: Dictionary = categories[c]
		var x := inner.position.x + c * (column + 10)
		var y := inner.position.y + 28
		T.new(category["name"].to_upper(), 10, 700, true).draw(self, Vector2(x, y), Paint.CHORD if category["lit"] else Paint.color("faint"))
		y += 22
		for sound in category["sounds"]:
			var cell := Rect2(x, y, column, 30)
			var chosen: bool = sound["chosen"]
			Paint.box(self, cell, Paint.CHORD if chosen else Paint.color("raised", 0.9 if category["lit"] else 0.4), 7)
			var name := T.new(sound["name"], 13, 600 if chosen else 400).fitted(column - 20)
			name.draw(self, Vector2(x + 10, cell.get_center().y - name.height() / 2), Paint.INK if chosen else Paint.color("text"))
			y += 34
	T.new("← → category · ↑ ↓ sound, heard as you go · A or B back", 11).draw(self,
			Vector2(inner.position.x, inner.end.y - 14), Paint.color("secondary"))
