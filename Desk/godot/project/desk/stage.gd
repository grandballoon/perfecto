## The layout's stage: its panels side by side, each the items the scene
## gives it top to bottom. Items of a fixed height take theirs, and the rest
## (pies, the ring, the diamond, the bar) share what is left. The Mac desk's
## layout views, drawn from the scene.
class_name Stage

const PANEL_PAD := 16.0
const PANEL_GAP := 20.0
const ITEM_GAP := 12.0
const LANE := 58.0
const LANE_GAP := 8.0
const T := Paint.Text


## Draws `panels` across `rect`; what a click can choose goes in `hits`, as
## [rect, action].
static func draw(canvas: CanvasItem, rect: Rect2, panels: Array, hits: Array) -> void:
	var fixed := 0.0
	var flexible := 0
	for panel in panels:
		if panel["max_width"] > 0:
			fixed += panel["max_width"]
		else:
			flexible += 1
	var room := rect.size.x - PANEL_GAP * (panels.size() - 1)
	var share := (room - fixed) / maxi(1, flexible)
	var x := rect.position.x
	for panel in panels:
		var width: float = panel["max_width"] if panel["max_width"] > 0 else share
		if panel["max_width"] > 0 and flexible == 0:
			width = room / panels.size()
		draw_panel(canvas, Rect2(x, rect.position.y, width, rect.size.y), panel["items"], hits)
		x += width + PANEL_GAP


## A panel of the stage: raised a little from the background.
static func panel_box(canvas: CanvasItem, rect: Rect2) -> void:
	Paint.box(canvas, rect, Paint.color("panel"), 14, Paint.color("rule", 0.6))


static func draw_panel(canvas: CanvasItem, rect: Rect2, items: Array, hits: Array) -> void:
	panel_box(canvas, rect)
	var inner := rect.grow(-PANEL_PAD)
	var fixed := 0.0
	var flexible := 0
	for item in items:
		var h := height(item, inner.size.x)
		if h < 0:
			flexible += 1
		else:
			fixed += h
	var share := maxf(0, inner.size.y - fixed - ITEM_GAP * (items.size() - 1)) / maxi(1, flexible)
	var y := inner.position.y
	for item in items:
		var h := height(item, inner.size.x)
		if h < 0:
			h = share
		draw_item(canvas, Rect2(inner.position.x, y, inner.size.x, h), item, hits)
		y += h + ITEM_GAP


## An item's height at `width`, or -1 for one that takes a share of what is left.
static func height(item: Dictionary, width: float) -> float:
	match item["type"]:
		"caption", "facts": return 16
		"note":
			if item["large"]:
				return 34
			return Paint.paragraph(null, Vector2.ZERO, width, item["text"], 11, Color.WHITE, 600 if item["strong"] else 400)
		"triggers": return 14
		"choices": return 22
		"sounding": return 18
		"scale": return 40
		"chips":
			var rows := chip_rows(item, width)
			return rows.size() * (chip_height(item) + 6) - 6 if rows else 0
		"lanes":
			return item["lanes"].size() * (LANE + LANE_GAP) - LANE_GAP
	return -1


static func draw_item(canvas: CanvasItem, rect: Rect2, item: Dictionary, hits: Array) -> void:
	match item["type"]:
		"caption": caption(canvas, rect, item["control"], item["title"], item["aside"], item["aside_tint"])
		"note": note(canvas, rect, item)
		"pie": pie(canvas, square(rect), item)
		"pies":
			var count: int = item["pies"].size()
			var width := (rect.size.x - 12 * (count - 1)) / count
			for i in count:
				pie(canvas, square(Rect2(rect.position.x + i * (width + 12), rect.position.y, width, rect.size.y)), item["pies"][i])
		"ring": ring(canvas, square(rect), item)
		"triggers":
			var bars: Array = item["bars"]
			var width := (rect.size.x - 16 * (bars.size() - 1)) / bars.size()
			for i in bars.size():
				trigger(canvas, Rect2(rect.position.x + i * (width + 16), rect.position.y, width, rect.size.y), bars[i])
		"facts": facts(canvas, rect, item["facts"], item["aside"])
		"choices": choices(canvas, rect, item, hits)
		"sounding": sounding(canvas, rect, item)
		"voices": voices(canvas, rect, item)
		"diamond": diamond(canvas, rect, item)
		"scale": scale(canvas, rect, item["targets"])
		"chips": chips(canvas, rect, item)
		"bar": bar(canvas, rect, item)
		"lanes": lanes(canvas, rect, item["lanes"])


## The largest square in `rect`, centred.
static func square(rect: Rect2) -> Rect2:
	var side := minf(rect.size.x, rect.size.y)
	return Rect2(rect.get_center() - Vector2(side, side) / 2, Vector2(side, side))


# The items.

## A small heading over a part of the stage: what plays it and what it is.
static func caption(canvas: CanvasItem, rect: Rect2, control: String, title: String, aside := "", aside_tint := "faint") -> void:
	var mark := T.new(control.to_upper(), 10, 700, true)
	mark.draw(canvas, Vector2(rect.position.x, rect.position.y + 1), Paint.color("secondary"))
	var x := rect.position.x + mark.width() + 6
	var said := T.new(aside, 10, 700, true)
	var room := rect.end.x - x - (said.width() + 10.0 if aside else 0.0)
	T.new(title, 12, 600).fitted(room, 0.8).draw(canvas, Vector2(x, rect.position.y), Paint.color("text"))
	if aside:
		said.draw(canvas, Vector2(rect.end.x - said.width(), rect.position.y + 1), Paint.color(aside_tint))


static func note(canvas: CanvasItem, rect: Rect2, item: Dictionary) -> void:
	if item["large"]:
		T.new(item["text"], 26, 700, true).fitted(rect.size.x).draw_centred(canvas, rect.get_center(), Paint.color(item["tint"]))
	else:
		Paint.paragraph(canvas, rect.position, rect.size.x, item["text"], 11, Paint.color(item["tint"]), 600 if item["strong"] else 400)


## A stick's pie: its targets round a circle, each named by what it would
## sound, and the stick's own place as a dot.
static func pie(canvas: CanvasItem, rect: Rect2, item: Dictionary) -> void:
	var middle := rect.get_center()
	var radius := rect.size.x / 2
	var accent := Paint.color(item["accent"])
	var outer = item["outer"]
	var compact: bool = item["compact"]
	canvas.draw_circle(middle, radius, Paint.color("raised", 0.5))
	canvas.draw_arc(middle, radius * 0.18, 0, TAU, 64, Paint.color("rule"), 1, true)
	for target in item["targets"]:
		if target:
			canvas.draw_line(Paint.point(middle, target["bearing"], radius * 0.2), Paint.point(middle, target["bearing"], radius * 0.5),
					accent if target["aimed"] else Paint.color("rule"), 2 if target["aimed"] else 1, true)
	stick_dot(canvas, item["stick"], middle, radius, accent)
	if item["title"] or item["detail"]:
		var title := T.new(item["title"], 15 if compact else 20, 700, true)
		var detail := T.new(item["detail"], 10 if compact else 11, 500)
		var top := middle.y - (title.height() + detail.height() + 2) / 2
		title.draw(canvas, Vector2(middle.x, top), Paint.color("text"), true)
		detail.draw(canvas, Vector2(middle.x, top + title.height() + 2), Paint.color("secondary"), true)
	for target in item["targets"]:
		if target:
			target_label(canvas, Paint.point(middle, target["bearing"], radius * (0.72 if outer == null else 0.56)), target,
					accent, compact or outer != null, 0.4 if target["hidden"] else 1.0)
	if outer != null:
		for target in outer:
			if target:
				target_label(canvas, Paint.point(middle, target["bearing"], radius * 0.9), target, accent, true,
						0.35 if target["hidden"] else 0.9)


## Where a stick is, as a dot inside its pie.
static func stick_dot(canvas: CanvasItem, stick: Vector2, middle: Vector2, radius: float, accent: Color) -> void:
	var at := middle + Vector2(stick.x, -stick.y) * radius * 0.94
	canvas.draw_line(middle, at, Color(accent, 0.35), 2, true)
	canvas.draw_circle(middle if at == middle else at, 6, Color(accent, 0.9 if stick.length() > 0.05 else 0.25))


## A target's label: its chord, and what it is, in a capsule centred on `at`.
static func target_label(canvas: CanvasItem, at: Vector2, target: Dictionary, accent: Color, compact: bool, opacity := 1.0) -> void:
	var aimed: bool = target["aimed"]
	var borrowed: bool = target["fit"] == "borrowed"
	if target["fit"] == "tense" and not aimed:
		opacity *= 0.75
	var name := T.new(target["name"], 12 if compact else 14, 600, true, borrowed)
	var detail := T.new(target["detail"], 9 if compact else 10, 500)
	var has_detail: bool = target["detail"] != ""
	var size := Vector2(maxf(name.width(), detail.width() if has_detail else 0.0) + 16,
			name.height() + (detail.height() + 1 if has_detail else 0.0) + 8)
	var rect := Rect2(at - size / 2, size)
	var fill := Paint.color("panel")
	if aimed:
		fill = accent
	elif target["near"]:
		fill = Paint.color("near", 0.18)
	var border := Paint.color("rule")
	if target["kept"]:
		border = accent
	elif borrowed:
		border = Paint.color("borrowed")
	elif target["near"]:
		border = Paint.color("near", 0.7)
	fill.a *= opacity
	border.a *= opacity
	Paint.capsule(canvas, rect, fill, border, 2 if target["kept"] else 1, borrowed)
	var ink := Paint.INK if aimed else Paint.color("text")
	ink.a *= opacity
	name.draw(canvas, Vector2(at.x, rect.position.y + 4), ink, true)
	if has_detail:
		var faint := Color(Paint.INK, 0.65) if aimed else Paint.color("secondary")
		faint.a *= opacity
		detail.draw(canvas, Vector2(at.x, rect.position.y + 5 + name.height()), faint, true)


## The color ring: three bands of seven sectors, darker anticlockwise and
## brighter clockwise, the modes named round the outside, the key's own
## marked, and the gap where the darkest and brightest would meet.
static func ring(canvas: CanvasItem, rect: Rect2, item: Dictionary) -> void:
	var middle := rect.get_center()
	# Room round the outside for the modes' names.
	var outer := rect.size.x / 2 - 26
	var inner := outer * 0.3
	var bands: Array = item["bands"]
	var band := (outer - inner) / maxi(1, bands.size())
	var span: float = item["span"]
	for i in bands.size():
		var from := inner + band * i
		for cell in bands[i]:
			var shape := Paint.sector(middle, cell["bearing"], span, from + 1, from + band - 1)
			var opacity := 0.35 if cell["hidden"] else 1.0
			var fill := Paint.color("panel")
			if cell["hidden"]:
				fill = Paint.color("raised", 0.3)
			elif cell["aimed"]:
				fill = Paint.CHORD
			elif cell["near"]:
				fill = Paint.color("near", 0.22)
			elif cell["fit"] == "borrowed":
				fill = Paint.color("borrowed", 0.1)
			fill.a *= opacity
			canvas.draw_colored_polygon(shape, fill)
			var stroke := Paint.color("rule")
			if cell["kept"]:
				stroke = Paint.CHORD
			elif cell["fit"] == "borrowed":
				stroke = Paint.color("borrowed", 0.7)
			stroke.a *= opacity
			var closed := shape.duplicate()
			closed.append(shape[0])
			if cell["fit"] == "borrowed":
				Paint.dash(canvas, closed, stroke, 1)
			else:
				canvas.draw_polyline(closed, stroke, 2.5 if cell["kept"] else 1.0, true)
	# The key's own mode: its sector edged on the outside.
	for sector in item["sectors"]:
		if sector["own"]:
			canvas.draw_colored_polygon(Paint.sector(middle, sector["bearing"], span - 2, outer + 2, outer + 5), Paint.CHORD)
	canvas.draw_circle(middle, inner - 2, Paint.color("raised", 0.6))
	stick_dot(canvas, item["stick"], middle, outer, Paint.CHORD)
	var title := T.new(item["title"], 15, 700, true)
	var detail := T.new(item["detail"], 10, 500)
	var top := middle.y - (title.height() + detail.height() + 1) / 2
	title.draw(canvas, Vector2(middle.x, top), Paint.color("text"), true)
	detail.draw(canvas, Vector2(middle.x, top + title.height() + 1), Paint.color("secondary"), true)
	for i in bands.size():
		for cell in bands[i]:
			if cell["hidden"]:
				continue
			T.new(cell["name"], 11 if i == 0 else 10, 600, true, cell["fit"] == "borrowed").fitted(band * 1.6) \
					.draw_centred(canvas, Paint.point(middle, cell["bearing"], inner + band * (i + 0.5)),
							Paint.INK if cell["aimed"] else Paint.color("text"))
	# The modes, named round the outside.
	for sector in item["sectors"]:
		var at := Paint.point(middle, sector["bearing"], outer + 16)
		var tint := Paint.CHORD if sector["own"] else Paint.color("secondary")
		var mode := T.new(sector["mode"], 10, 700 if sector["own"] else 500)
		if sector["own"]:
			var own := T.new("key's own", 8, 600)
			mode.draw(canvas, Vector2(at.x, at.y - (mode.height() + own.height()) / 2), tint, true)
			own.draw(canvas, Vector2(at.x, at.y - (mode.height() + own.height()) / 2 + mode.height()), tint, true)
		else:
			mode.draw_centred(canvas, at, tint)
	# The gap: where the ring ends, brightest on one side, darkest on the other.
	var gap := Paint.point(middle, item["gap"], inner + (outer - inner) * 0.55)
	var ends := T.new("ring ends", 9, 700, true)
	var modes := T.new(item["gap_modes"], 8, 500)
	ends.draw(canvas, Vector2(gap.x, gap.y - (ends.height() + modes.height()) / 2), Paint.color("faint"), true)
	modes.draw(canvas, Vector2(gap.x, gap.y - (ends.height() + modes.height()) / 2 + ends.height()), Paint.color("faint"), true)


## A bar showing how far a trigger is pulled, with its steps marked.
static func trigger(canvas: CanvasItem, rect: Rect2, bar: Dictionary) -> void:
	T.new(bar["name"], 11, 700, true).draw(canvas, rect.position, Paint.color("secondary"))
	var track := Rect2(rect.position.x + 30, rect.get_center().y - 3, rect.size.x - 30, 6)
	Paint.capsule(canvas, track, Paint.color("raised"))
	var value: float = bar["value"]
	if value > 0:
		Paint.capsule(canvas, Rect2(track.position, Vector2(maxf(6, track.size.x * value), 6)), Paint.color(bar["tint"]))
	for edge in bar["edges"]:
		canvas.draw_rect(Rect2(track.position.x + track.size.x * edge - 1, track.position.y, 2, 6), Paint.color("panel"))


## Named values in a row, and a word at the end.
static func facts(canvas: CanvasItem, rect: Rect2, pairs: Array, aside := "") -> void:
	var x := rect.position.x
	for pair in pairs:
		x = fact(canvas, Vector2(x, rect.position.y), pair[0], pair[1]) + 14
	if aside:
		var said := T.new(aside, 10, 400)
		said.draw(canvas, Vector2(rect.end.x - said.width(), rect.position.y + 2), Paint.color("faint"))


## A setting's name and value; returns where it ends.
static func fact(canvas: CanvasItem, at: Vector2, name: String, value: String) -> float:
	var label := T.new(name.to_upper(), 9, 700, true)
	label.draw(canvas, at + Vector2(0, 3), Paint.color("faint"))
	var said := T.new(value, 12, 600)
	said.draw(canvas, at + Vector2(label.width() + 5, 0), Paint.color("text"))
	return at.x + label.width() + 5 + said.width()


## A row of choices, the one chosen lit, between the controls that move
## through them.
static func choices(canvas: CanvasItem, rect: Rect2, item: Dictionary, hits: Array) -> void:
	var x := rect.position.x
	var mid := rect.get_center().y
	if item["before"]:
		var before := T.new(item["before"], 10, 800, true)
		before.draw_centred(canvas, Vector2(x + before.width() / 2, mid), Paint.color("secondary"))
		x += before.width() + 6
	for i in item["names"].size():
		var label := T.new(item["names"][i], 11 if item["action"] else 12, 600)
		var chip := Rect2(x, mid - 11, label.width() + 20, 22)
		var chosen: bool = i == item["chosen"]
		Paint.capsule(canvas, chip, Paint.CHORD if chosen else Paint.color("raised"))
		label.draw_centred(canvas, chip.get_center(), Paint.INK if chosen else Paint.color("text"))
		if item["action"]:
			hits.append([chip, {"kind": item["action"], "index": i}])
		x += chip.size.x + 4
	if item["after"]:
		var after := T.new(item["after"], 10, 800, true)
		after.draw_centred(canvas, Vector2(x + 2 + after.width() / 2, mid), Paint.color("secondary"))


## What a line of chords is sounding, named.
static func sounding(canvas: CanvasItem, rect: Rect2, item: Dictionary) -> void:
	var on: bool = item["sounding"]
	var mid := rect.get_center().y
	canvas.draw_circle(Vector2(rect.position.x + 4, mid), 4, Paint.CHORD if on else Paint.color("rule"))
	var said := T.new(item["text"], 13, 600 if on else 400)
	said.draw(canvas, Vector2(rect.position.x + 14, mid - said.height() / 2), Paint.color("text" if on else "secondary"))
	if item["arpeggio"]:
		var arp := T.new(item["arpeggio"], 11, 500)
		arp.draw(canvas, Vector2(rect.end.x - arp.width(), mid - arp.height() / 2), Paint.MELODY)


## The voices: the bass's moves upright beside the upper voices' pie.
static func voices(canvas: CanvasItem, rect: Rect2, item: Dictionary) -> void:
	var column := Rect2(rect.position, Vector2(104, rect.size.y))
	var targets: Array = item["bass"]
	var rows := 5
	var row := 30.0
	var top := column.get_center().y - (16 + rows * row) / 2
	caption(canvas, Rect2(column.position.x, top, column.size.x, 16), "Left stick", "Bass")
	var y := top + 22
	# Up two at the top, then up one, the stick, down one and down two.
	for index in [1, 0, -1, 2, 3]:
		var centre := Vector2(column.get_center().x, y + row / 2)
		if index < 0:
			var lean: float = item["left"].y
			canvas.draw_circle(centre + Vector2(0, -lean * 8), 5, Color(Paint.CHORD, 0.9 if absf(lean) > 0.3 else 0.25))
		elif targets[index]:
			target_label(canvas, centre, targets[index], Paint.CHORD, true, 0.4 if targets[index]["hidden"] else 1.0)
		else:
			T.new("—", 11).draw_centred(canvas, centre, Paint.color("faint"))
		y += row
	pie(canvas, square(Rect2(rect.position.x + 118, rect.position.y, rect.size.x - 118, rect.size.y)), item["upper"])


## The four face buttons, where they are on the controller, each with the
## chord it would strike now.
static func diamond(canvas: CanvasItem, rect: Rect2, item: Dictionary) -> void:
	var middle := rect.get_center()
	var distance := minf(rect.size.x, rect.size.y) * 0.33
	for petal in item["petals"]:
		var at := Paint.point(middle, petal["target"]["bearing"], distance)
		var chip_rect := control_chip(canvas, at + Vector2(0, -22), petal["button"], petal["held"], petal["tint"], 1.3)
		target_label(canvas, at + Vector2(0, chip_rect.size.y / 2 + 6), petal["target"], Paint.color(petal["tint"]), false)


## A control's own mark, centred on `at`: a face button round in its color,
## the rest in grey. Returns where it was drawn.
static func control_chip(canvas: CanvasItem, at: Vector2, mark: String, held: bool, tint, scale := 1.0) -> Rect2:
	var label := T.new(mark, int(10 * scale), 800, true)
	var round: bool = tint != null
	var size := Vector2(maxf(22 * scale, label.width() + (0.0 if round else 8 * scale)), 20 * scale)
	var rect := Rect2(at - size / 2, size)
	var color := Paint.color(tint) if round else Color.TRANSPARENT
	var fill := (color if round else Paint.CHORD) if held else Paint.color("raised")
	var edge := Color(color if round else Paint.color("rule"), 0 if held else 0.6)
	Paint.box(canvas, rect, fill, (10 if round else 5) * scale, edge)
	label.draw_centred(canvas, rect.get_center(), Paint.INK if held else (color if round else Paint.color("text")))
	return rect


## The modes from darker to brighter, the one the triggers are at lit.
static func scale(canvas: CanvasItem, rect: Rect2, targets: Array) -> void:
	var width := (rect.size.x - 4 * (targets.size() - 1)) / maxi(1, targets.size())
	for i in targets.size():
		var target: Dictionary = targets[i]
		var cell := Rect2(rect.position.x + i * (width + 4), rect.position.y, width, rect.size.y)
		var aimed: bool = target["aimed"]
		Paint.box(canvas, cell, Paint.CHORD if aimed else Paint.color("raised", 0.6), 8)
		var ink := Paint.INK if aimed else Paint.color("text")
		var name := T.new(target["name"], 12, 600, true).fitted(width - 6, 0.7)
		var detail := T.new(target["detail"], 9, 500).fitted(width - 6, 0.7)
		var top := cell.get_center().y - (name.height() + detail.height() + 2) / 2
		name.draw(canvas, Vector2(cell.get_center().x, top), ink, true)
		detail.draw(canvas, Vector2(cell.get_center().x, top + name.height() + 2), Color(ink, 0.7), true)


static func chip_height(item: Dictionary) -> float:
	return 30.0 if item["columns"] > 0 else 26.0


## The chips laid in rows: as many columns as asked, or as fit at 64 wide.
static func chip_rows(item: Dictionary, width: float) -> Array:
	var columns: int = item["columns"] if item["columns"] > 0 else maxi(1, int((width + 6) / 70))
	var rows := []
	for i in item["chips"].size():
		if i % columns == 0:
			rows.append([])
		rows[-1].append(item["chips"][i])
	return rows


static func chips(canvas: CanvasItem, rect: Rect2, item: Dictionary) -> void:
	var rows := chip_rows(item, rect.size.x)
	var columns: int = item["columns"] if item["columns"] > 0 else maxi(1, int((rect.size.x + 6) / 70))
	var width := (rect.size.x - 6 * (columns - 1)) / columns
	var h := chip_height(item)
	for r in rows.size():
		for c in rows[r].size():
			var chip: Dictionary = rows[r][c]
			var cell := Rect2(rect.position.x + c * (width + 6), rect.position.y + r * (h + 6), width, h)
			var fill := Paint.CHORD if chip["lit"] else Paint.color("raised", 0.4 if chip["empty"] else 0.8)
			Paint.box(canvas, cell, fill, 7)
			var ink := Paint.INK if chip["lit"] else Paint.color("faint" if chip["empty"] else "text")
			T.new(chip["text"], 12, 400 if chip["empty"] else 600, true).fitted(width - 8, 0.7).draw_centred(canvas, cell.get_center(), ink)


## The Trautonium's bar, upright: the key's notes marked along it, and the
## pitch the line is at.
static func bar(canvas: CanvasItem, rect: Rect2, item: Dictionary) -> void:
	var width := minf(200, rect.size.x)
	var body := Rect2(rect.get_center().x - width / 2, rect.position.y, width, rect.size.y)
	Paint.box(canvas, body, Paint.color("raised", 0.6), 10)
	for mark in item["marks"]:
		var y: float = body.end.y - body.size.y * mark["place"]
		canvas.draw_rect(Rect2(body.position.x, y, width, 2 if mark["tonic"] else 1), Paint.color("rule"))
	if item["pitch"] != null:
		var y: float = body.end.y - body.size.y * item["pitch"]
		Paint.capsule(canvas, Rect2(body.position.x, y - 3, width, 6), Paint.MELODY)


## The arranger's four bars, a lane to each: its grid, its chords, the chord
## being written, the cursor and the playhead.
static func lanes(canvas: CanvasItem, rect: Rect2, all: Array) -> void:
	var y := rect.position.y
	for lane in all:
		T.new(str(lane["number"]), 11, 700, true).draw_centred(canvas, Vector2(rect.position.x + 7, y + LANE / 2), Paint.color("faint"))
		var body := Rect2(rect.position.x + 22, y, rect.size.x - 22, LANE)
		var x := func(place: float) -> float: return body.position.x + body.size.x * place
		Paint.box(canvas, body, Paint.color("raised", 0.35), 8)
		# The grid's lines, faint, and the beats', stronger.
		for line in lane["lines"]:
			if line["beat"]:
				canvas.draw_rect(Rect2(x.call(line["place"]), y, 1, LANE), Paint.color("rule", 0.9))
			else:
				canvas.draw_rect(Rect2(x.call(line["place"]), y + LANE * 0.65, 1, LANE * 0.35), Paint.color("rule", 0.35))
		for block in lane["blocks"]:
			var from: float = x.call(block["from"])
			var shape := Rect2(from + 1, y + 4, maxf(2, x.call(block["to"]) - from - 2), LANE - 8)
			var heard: bool = block["heard"]
			Paint.box(canvas, shape, Paint.CHORD if heard else Paint.color("panel"), 6, Paint.CHORD if heard else Paint.color("rule"))
			if block["name"]:
				var name := T.new(block["name"], 13, 600, true).fitted(shape.size.x - 16)
				if name.width() <= shape.size.x - 8:
					name.draw(canvas, Vector2(shape.position.x + 8, shape.get_center().y - name.height() / 2),
							Paint.INK if heard else Paint.color("text"))
		if lane["writing"] != null:
			var from: float = x.call(lane["writing"][0])
			var shape := Rect2(from, y + 4, maxf(3, x.call(lane["writing"][1]) - from), LANE - 8)
			Paint.box(canvas, shape, Paint.color("chord", 0.35), 6, Paint.CHORD, 2)
		if lane["cursor"] != null:
			Paint.capsule(canvas, Rect2(x.call(lane["cursor"]) - 1.5, y - 3, 3, LANE + 6), Paint.CHORD)
		if lane["playhead"] != null:
			canvas.draw_rect(Rect2(x.call(lane["playhead"]) - 1, y, 2, LANE), Paint.color("text"))
		y += LANE + LANE_GAP
