## How the desk draws: its colors, light and dark, its fonts, and the shapes
## everything on screen is made of. The Mac desk's `Theme`, for a canvas.
class_name Paint

## Whether the system is in dark mode, read by `follow_system`.
static var dark := true
static var _fonts := {}

const CHORD := Color(1, 0.62, 0.1)
const MELODY := Color(0.35, 0.68, 1)
## One step from what sounds: the gentle moves.
const NEAR := Color(0.25, 0.78, 0.6)
## A note from outside the key.
const BORROWED := Color(0.66, 0.5, 1)
const INK := Color.BLACK

## The 360's face buttons.
const FACE := {
	"a": Color(0.36, 0.76, 0.24),
	"b": Color(0.92, 0.3, 0.26),
	"x": Color(0.24, 0.52, 0.96),
	"y": Color(0.98, 0.76, 0.14),
}

## Each grey's light and dark form.
const GREYS := {
	"background": [0.95, 0.07],
	"panel": [1.0, 0.115],
	"raised": [0.9, 0.17],
	"rule": [0.8, 0.24],
	"text": [0.1, 0.93],
	"secondary": [0.42, 0.58],
	"faint": [0.62, 0.38],
}


## Reads the system's appearance; true if it changed.
static func follow_system() -> bool:
	var now := DisplayServer.is_dark_mode() if DisplayServer.is_dark_mode_supported() else true
	if now == dark:
		return false
	dark = now
	return true


## A grey by its role, or a tint by its name as the scene gives it.
static func color(name: String, alpha := 1.0) -> Color:
	var c: Color
	if name in GREYS:
		var white: float = GREYS[name][1 if dark else 0]
		c = Color(white, white, white)
	else:
		match name:
			"chord": c = CHORD
			"melody": c = MELODY
			"near": c = NEAR
			"borrowed": c = BORROWED
			_: c = FACE.get(name, CHORD)
	c.a = alpha
	return c


## The system's font at `weight` (400 regular to 800 heavy), rounded for
## the desk's numbers and names, monospaced for keys.
static func font(weight := 400, rounded := false, italic := false, mono := false) -> Font:
	var key := "%d%s%s%s" % [weight, rounded, italic, mono]
	if key not in _fonts:
		var f := SystemFont.new()
		if mono:
			f.font_names = PackedStringArray(["SF Mono", "Menlo", "monospace"])
		elif rounded:
			f.font_names = PackedStringArray([".AppleSystemUIFontRounded", "SF Pro Rounded", ".AppleSystemUIFont", "sans-serif"])
		else:
			f.font_names = PackedStringArray([".AppleSystemUIFont", "SF Pro", "Helvetica Neue", "sans-serif"])
		f.font_weight = weight
		f.font_italic = italic
		_fonts[key] = f
	return _fonts[key]


## A line of text.
class Text:
	var string: String
	var size: int
	var font: Font

	func _init(s: String, px: int, weight := 400, rounded := false, italic := false, mono := false) -> void:
		string = s
		size = px
		font = Paint.font(weight, rounded, italic, mono)

	func width() -> float:
		return font.get_string_size(string, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

	func height() -> float:
		return font.get_height(size)

	## Smaller, down to `least` of its size, until it fits `room`.
	func fitted(room: float, least := 0.6) -> Text:
		var smallest := maxi(6, int(ceil(size * least)))
		while size > smallest and width() > room:
			size -= 1
		return self

	## Draws it with its top left at `at`, or centred on `at.x` if `centred`.
	func draw(canvas: CanvasItem, at: Vector2, tint: Color, centred := false) -> void:
		var x := at.x - width() / 2 if centred else at.x
		canvas.draw_string(font, Vector2(x, at.y + font.get_ascent(size)), string, HORIZONTAL_ALIGNMENT_LEFT, -1, size, tint)

	## Draws it centred on `centre`.
	func draw_centred(canvas: CanvasItem, centre: Vector2, tint: Color) -> void:
		draw(canvas, Vector2(centre.x, centre.y - height() / 2), tint, true)


## Text wrapped to `width`, at most `lines` lines; returns its height.
static func paragraph(canvas: CanvasItem, at: Vector2, width: float, string: String, size: int, tint: Color,
		weight := 400, lines := -1) -> float:
	var f := font(weight)
	if canvas:
		canvas.draw_multiline_string(f, Vector2(at.x, at.y + f.get_ascent(size)), string, HORIZONTAL_ALIGNMENT_LEFT,
				width, size, lines, tint)
	return f.get_multiline_string_size(string, HORIZONTAL_ALIGNMENT_LEFT, width, size, lines).y


## A rounded rectangle, filled and edged; a capsule when `radius` is half its height.
static func box(canvas: CanvasItem, rect: Rect2, fill: Color, radius: float, stroke := Color.TRANSPARENT,
		stroke_width := 1.0, dashed := false) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(int(round(radius)))
	style.anti_aliasing = true
	if stroke.a > 0 and not dashed:
		style.border_color = stroke
		style.set_border_width_all(int(round(stroke_width)))
	canvas.draw_style_box(style, rect)
	if stroke.a > 0 and dashed:
		dash(canvas, rounded_outline(rect.grow(-stroke_width / 2), radius), stroke, stroke_width)


static func capsule(canvas: CanvasItem, rect: Rect2, fill: Color, stroke := Color.TRANSPARENT, stroke_width := 1.0,
		dashed := false) -> void:
	box(canvas, rect, fill, rect.size.y / 2, stroke, stroke_width, dashed)


## The outline of a rounded rectangle, as points round it.
static func rounded_outline(rect: Rect2, radius: float) -> PackedVector2Array:
	var r := minf(radius, minf(rect.size.x, rect.size.y) / 2)
	var points := PackedVector2Array()
	var corners := [
		[rect.position + Vector2(rect.size.x - r, r), -90.0],
		[rect.position + Vector2(rect.size.x - r, rect.size.y - r), 0.0],
		[rect.position + Vector2(r, rect.size.y - r), 90.0],
		[rect.position + Vector2(r, r), 180.0],
	]
	for corner in corners:
		for step in 7:
			var angle := deg_to_rad(corner[1] + step * 15.0)
			points.append(corner[0] + Vector2(cos(angle), sin(angle)) * r)
	points.append(points[0])
	return points


## A dashed line along `points`: 3 drawn, 2 left, as the Mac desk's.
static func dash(canvas: CanvasItem, points: PackedVector2Array, tint: Color, width: float) -> void:
	var on := true
	var left := 3.0
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		var done := 0.0
		while done < length:
			var step := minf(left, length - done)
			var from := a.lerp(b, done / length)
			var to := a.lerp(b, (done + step) / length)
			if on:
				canvas.draw_line(from, to, tint, width, true)
			done += step
			left -= step
			if left <= 0:
				on = not on
				left = 3.0 if on else 2.0


## A point at `bearing` (degrees clockwise from up), `distance` from `centre`.
static func point(centre: Vector2, bearing: float, distance: float) -> Vector2:
	var radians := deg_to_rad(bearing)
	return Vector2(centre.x + distance * sin(radians), centre.y - distance * cos(radians))


## A sector of a ring, centred on `bearing`, `span` degrees wide.
static func sector(centre: Vector2, bearing: float, span: float, inner: float, outer: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := maxi(4, int(span / 3))
	for i in steps + 1:
		points.append(point(centre, bearing - span / 2 + span * i / steps, outer))
	for i in range(steps, -1, -1):
		points.append(point(centre, bearing - span / 2 + span * i / steps, inner))
	return points
