## The timeline's bar along the top of Face Chords, drawn from what the core
## says it shows (`TimelineBar` in scene.hpp): what it is doing and the
## mouse's controls, a ruler of bars, a lane to each layer with its chords
## as blocks in time, and what to do next. Every click is an action the core
## performs.
class_name TimelineView

const PAD := 14.0
const HEADER := 24.0
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
		canvas.draw_rect(Rect2(px - 1, track.position.y, 2, bottom - track.position.y), Paint.color("text"))
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


## What it is doing on the left, and a button for each control on the right,
## each with the controller's way to it beneath.
static func header(canvas: CanvasItem, rect: Rect2, t: Dictionary, hits: Array) -> void:
	var right := rect.end.x
	var controls: Array = t["controls"]
	for i in range(controls.size() - 1, -1, -1):
		var control: Dictionary = controls[i]
		var label := T.new(control["label"], 11, 600)
		var keys := T.new(control["keys"], 8, 700, true)
		var width := maxf(label.width(), keys.width()) + 18
		var shape := Rect2(right - width, rect.position.y - 2, width, rect.size.y + 4)
		var lit: bool = control["lit"]
		var enabled: bool = control["enabled"]
		Paint.box(canvas, shape, Paint.CHORD if lit else Paint.color("raised", 1.0 if enabled else 0.45), 7)
		var ink := Paint.INK if lit else Paint.color("text" if enabled else "faint")
		label.draw_centred(canvas, Vector2(shape.get_center().x, shape.position.y + 9), ink)
		keys.draw_centred(canvas, Vector2(shape.get_center().x, shape.end.y - 6), Color(ink, 0.6))
		if enabled:
			hits.append([shape, control["action"]])
		right -= width + 6
	var mid := rect.get_center().y
	var mark := T.new("RT", 10, 700, true)
	mark.draw(canvas, Vector2(rect.position.x, mid - mark.height() / 2), Paint.color("secondary"))
	var x := rect.position.x + mark.width() + 6
	var title := T.new("Timeline", 12, 600)
	title.draw(canvas, Vector2(x, mid - title.height() / 2), Paint.color("text"))
	x += title.width() + 14
	var status := T.new(t["status"], 12, 600, true).fitted(right - 12 - x)
	status.draw(canvas, Vector2(x, mid - status.height() / 2), Paint.color(t["status_tint"]))


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
