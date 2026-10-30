## The timeline's bar along the top of Face Chords, drawn from what the core
## says it shows (`TimelineBar` in scene.hpp): what it is doing and the
## mouse's controls, a ruler of bars, a lane to each layer with its chords
## as blocks in time, and what to do next. Every click is an action the core
## performs.
class_name TimelineView

const PAD := 14.0
## The header: its buttons, and the keys beneath the transport's.
const BUTTON := 30.0
const HEADER := BUTTON + 14
const RULER := 14.0
const LANE := 22.0
const LANE_GAP := 4.0
## The lanes' height when there are many, so the stage keeps its room.
const LANE_TIGHT := 16.0
## What to do next: a sentence, and a row of controls beneath it.
const MESSAGE := 16.0
const TIP := 22.0
const GUIDE := MESSAGE + 6 + TIP
const LABEL := 46.0
const T := Paint.Text


static func lane_height(t: Dictionary) -> float:
	return LANE if t["lanes"].size() <= 4 else LANE_TIGHT


## The bar's height for what it shows.
static func height(t: Dictionary) -> float:
	var lanes := maxi(1, t["lanes"].size())
	return PAD * 2 + HEADER + 8 + RULER + lanes * (lane_height(t) + LANE_GAP) - LANE_GAP + 10 + GUIDE


static func draw(canvas: CanvasItem, rect: Rect2, t: Dictionary, hits: Array) -> void:
	Stage.panel_box(canvas, rect)
	var inner := rect.grow(-PAD)
	header(canvas, Rect2(inner.position, Vector2(inner.size.x, HEADER)), t, hits)
	var y := inner.position.y + HEADER + 8
	var track := Rect2(inner.position.x + LABEL, y, inner.size.x - LABEL, inner.end.y - GUIDE - 10 - y)
	var span: float = t["to"] - t["from"]
	var x := func(beats: float) -> float: return track.position.x + track.size.x * (beats - t["from"]) / span
	ruler(canvas, Rect2(track.position, Vector2(track.size.x, RULER)), t, x)
	var lanes_top := y + RULER
	var h := lane_height(t)
	if t["lanes"].is_empty():
		var empty := Rect2(track.position.x, lanes_top, track.size.x, h)
		Paint.box(canvas, empty, Paint.color("raised", 0.35), 6, Paint.color("rule", 0.8), 1, true)
	for i in t["lanes"].size():
		lane(canvas, Rect2(inner.position.x, lanes_top + i * (h + LANE_GAP), inner.size.x, h), t["lanes"][i], x, hits)
	if t["playhead"] != null:
		var px: float = x.call(t["playhead"])
		var bottom := lanes_top + maxi(1, t["lanes"].size()) * (h + LANE_GAP) - LANE_GAP
		# Bright while it plays; dimmer where it paused.
		var ink := Paint.color("text") if t["playing"] else Paint.color("secondary", 0.8)
		canvas.draw_rect(Rect2(px - 1, track.position.y, 2, bottom - track.position.y), ink)
		var top := track.position.y
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(px - 5, top), Vector2(px + 5, top), Vector2(px, top + 6)]), ink)
	guide(canvas, Rect2(inner.position.x, inner.end.y - GUIDE, inner.size.x, GUIDE), t)


## What to do next: the sentence, then each control as its buttons in a key
## cap beside what it does, as far as the row has room for.
static func guide(canvas: CanvasItem, rect: Rect2, t: Dictionary) -> void:
	T.new(t["message"], 12, 500).fitted(rect.size.x, 0.8).draw(canvas, rect.position, Paint.color("text"))
	var x := rect.position.x
	var y := rect.position.y + MESSAGE + 6
	for tip in t["tips"]:
		var keys := T.new(tip[0], 10, 700, true)
		var said := T.new(tip[1], 11, 500)
		var cap := Vector2(keys.width() + 14, TIP)
		var width := cap.x + 6 + said.width()
		if x + width > rect.end.x:
			break
		var shape := Rect2(Vector2(x, y), cap)
		Paint.box(canvas, shape, Paint.color("raised"), 6, Paint.color("rule"))
		keys.draw_centred(canvas, shape.get_center(), Paint.color("text"))
		said.draw_centred(canvas, Vector2(shape.end.x + 6 + said.width() / 2, shape.get_center().y), Paint.color("secondary"))
		x += width + 18


## The transport on the left, round buttons with the symbols every player
## knows (back to start, play or pause, record) and the controller's way to
## each beneath; then what it is doing; and the other controls on the right.
static func header(canvas: CanvasItem, rect: Rect2, t: Dictionary, hits: Array) -> void:
	var right := rect.end.x
	var x := rect.position.x
	var controls: Array = t["controls"]
	for control in controls:
		if control["icon"] != "none":
			x += transport(canvas, Vector2(x, rect.position.y), control, hits) + 10
	for i in range(controls.size() - 1, -1, -1):
		var control: Dictionary = controls[i]
		if control["icon"] != "none":
			continue
		var label := T.new(control["label"], 11, 600)
		var keys := T.new(control["keys"], 8, 700, true)
		var width := maxf(label.width(), keys.width()) + 18
		var shape := Rect2(right - width, rect.position.y, width, BUTTON)
		var lit: bool = control["lit"]
		var enabled: bool = control["enabled"]
		Paint.box(canvas, shape, Paint.CHORD if lit else Paint.color("raised", 1.0 if enabled else 0.45), 7)
		var ink := Paint.INK if lit else Paint.color("text" if enabled else "faint")
		label.draw_centred(canvas, Vector2(shape.get_center().x, shape.position.y + 10), ink)
		keys.draw_centred(canvas, Vector2(shape.get_center().x, shape.end.y - 7), Color(ink, 0.6))
		if enabled:
			hits.append([shape, control["action"]])
		right -= width + 6
	var mid := rect.position.y + BUTTON / 2
	x += 6
	var title := T.new("Timeline", 12, 600)
	title.draw(canvas, Vector2(x, mid - title.height() / 2), Paint.color("text"))
	x += title.width() + 14
	var status := T.new(t["status"], 12, 600, true).fitted(right - 12 - x)
	status.draw(canvas, Vector2(x, mid - status.height() / 2), Paint.color(t["status_tint"]))


## A transport button: its symbol in a circle, play the largest, and its
## keys beneath. Returns its width.
static func transport(canvas: CanvasItem, at: Vector2, control: Dictionary, hits: Array) -> float:
	var icon: String = control["icon"]
	var big := icon == "play" or icon == "pause"
	var diameter := BUTTON if big else BUTTON - 6
	var keys := T.new(control["keys"], 8, 700, true)
	var width := maxf(diameter, keys.width())
	var centre := Vector2(at.x + width / 2, at.y + BUTTON / 2)
	var enabled: bool = control["enabled"]
	var lit: bool = control["lit"]
	var recording := icon == "record" or icon == "stop_recording"
	var red: Color = Paint.FACE["b"]
	var fill: Color
	var ink: Color
	if big:
		fill = Paint.NEAR if enabled else Paint.color("raised", 0.45)
		ink = Paint.INK if enabled else Paint.color("faint")
	elif lit:
		fill = red
		ink = Color.WHITE
	else:
		fill = Paint.color("raised", 1.0 if enabled else 0.45)
		ink = (red if recording else Paint.color("text")) if enabled else Paint.color("faint")
	canvas.draw_circle(centre, diameter / 2, fill, true, -1, true)
	symbol(canvas, icon, centre, diameter * 0.36, ink)
	keys.draw_centred(canvas, Vector2(centre.x, at.y + BUTTON + 7), Paint.color("secondary" if enabled else "faint"))
	if enabled:
		hits.append([Rect2(centre - Vector2(diameter, diameter) / 2, Vector2(diameter, diameter)), control["action"]])
	return width


## The transport's symbols, drawn as shapes so every font shows them alike,
## each fitting a circle of `r` about `c`.
static func symbol(canvas: CanvasItem, icon: String, c: Vector2, r: float, ink: Color) -> void:
	match icon:
		"play":
			# A triangle sits a little right of the middle, to look centred.
			var o := c + Vector2(r * 0.15, 0)
			canvas.draw_colored_polygon(PackedVector2Array([o + Vector2(-r * 0.7, -r), o + Vector2(r, 0), o + Vector2(-r * 0.7, r)]), ink)
		"pause":
			var bar := Vector2(r * 0.55, r * 1.9)
			canvas.draw_rect(Rect2(c + Vector2(-r * 0.8, -bar.y / 2), bar), ink)
			canvas.draw_rect(Rect2(c + Vector2(r * 0.25, -bar.y / 2), bar), ink)
		"record":
			canvas.draw_circle(c, r * 0.8, ink, true, -1, true)
		"stop_recording":
			canvas.draw_rect(Rect2(c - Vector2(r, r) * 0.75, Vector2(r, r) * 1.5), ink)
		"rewind":
			canvas.draw_rect(Rect2(c + Vector2(-r * 0.85, -r * 0.8), Vector2(r * 0.28, r * 1.6)), ink)
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.8, -r * 0.8), c + Vector2(r * 0.8, r * 0.8), c + Vector2(-r * 0.45, 0)]), ink)


## The bars' numbers, and a tick at each beat.
static func ruler(canvas: CanvasItem, rect: Rect2, t: Dictionary, x: Callable) -> void:
	var per: int = t["beats_per_bar"]
	for beat in range(int(t["from"]), int(t["to"])):
		var bx: float = x.call(float(beat))
		if beat % per == 0:
			canvas.draw_rect(Rect2(bx, rect.position.y + 2, 1, rect.size.y - 2), Paint.color("rule"))
			T.new(str(beat / per + 1), 9, 700, true).draw(canvas, Vector2(bx + 3, rect.position.y), Paint.color("faint"))
		else:
			canvas.draw_rect(Rect2(bx, rect.end.y - 4, 1, 4), Paint.color("rule", 0.6))


## A layer: its number (a click chooses it) and its mute, its loop marked
## over its chords, which a click chooses (with Shift, stretches to).
static func lane(canvas: CanvasItem, rect: Rect2, l: Dictionary, x: Callable, hits: Array) -> void:
	var chosen: bool = l["chosen"]
	var muted: bool = l["muted"]
	var label := Rect2(rect.position, Vector2(22, rect.size.y))
	Paint.box(canvas, label, Paint.CHORD if chosen else Paint.color("raised"), 5)
	var number: String = ("● " if l["recording"] else "") + l["name"]
	T.new(number, 10, 700, true).draw_centred(canvas, label.get_center(), Paint.INK if chosen else Paint.color("text"))
	hits.append([label, {"kind": "timeline_choose_lane", "index": l["id"]}])
	var mute := Rect2(rect.position.x + 24, rect.position.y, 18, rect.size.y)
	Paint.box(canvas, mute, Paint.color("text") if muted else Color.TRANSPARENT, 5, Paint.color("rule"))
	T.new("M", 9, 800, true).draw_centred(canvas, mute.get_center(), Paint.color("panel") if muted else Paint.color("secondary"))
	hits.append([mute, {"kind": "timeline_mute_lane", "index": l["id"]}])

	var body := Rect2(rect.position.x + LABEL, rect.position.y, rect.size.x - LABEL, rect.size.y)
	Paint.box(canvas, body, Paint.color("raised", 0.5 if chosen else 0.3), 5)
	hits.append([body, {"kind": "timeline_deselect"}])
	if l["loop"] != null:
		var from: float = maxf(body.position.x, x.call(l["loop"][0]))
		var to: float = minf(body.end.x, x.call(l["loop"][1]))
		if to > from:
			var band := Rect2(from, body.position.y, to - from, body.size.y)
			Paint.box(canvas, band, Paint.color("near", 0.12), 5, Paint.color("near", 0.8), 1.5)
			T.new("⟲", 9, 700).draw(canvas, Vector2(band.position.x + 3, band.position.y), Paint.NEAR)
	var opacity := 0.35 if muted else 1.0
	for block in l["blocks"]:
		var from: float = maxf(body.position.x, x.call(block["from"]))
		var to: float = minf(body.end.x, x.call(block["to"]))
		if to <= from:
			continue
		var shape := Rect2(from + 1, body.position.y + 2, maxf(2, to - from - 2), body.size.y - 4)
		var tint := Paint.MELODY if block["channel"] == 1 else Paint.CHORD
		var heard: bool = block["heard"]
		var picked: bool = block["chosen"]
		var echo: bool = block["echo"]
		var left_out: bool = block["left_out"]
		var fill := Color(tint, (0.15 if echo or left_out else (1.0 if heard else 0.4)) * opacity)
		var edge := Paint.color("text") if picked else (Color(tint, 0.5 * opacity) if left_out else Color.TRANSPARENT)
		Paint.box(canvas, shape, fill, 4, edge, 2 if picked else 1, left_out)
		var name := T.new(block["name"], 10, 600, true)
		if name.width() <= shape.size.x - 6:
			var ink := Paint.INK if heard and not echo else Paint.color("faint" if echo or left_out else "text", opacity)
			name.draw(canvas, Vector2(shape.position.x + 4, shape.get_center().y - name.height() / 2), ink)
		if block["id"] != 0:
			hits.append([shape, {"kind": "timeline_select", "index": l["id"], "value": block["id"]}])
