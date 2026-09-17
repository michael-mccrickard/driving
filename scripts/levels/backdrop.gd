@tool
class_name Backdrop
extends CanvasLayer
## The sky behind a level: everything drawn behind the track that is not part of
## it. Stars for now, procedurally scattered; a moon, a horizon glow or a city
## skyline belong on this same layer.
##
## It is a CanvasLayer on a negative layer rather than a Node2D, so it is drawn
## in screen space and the camera never touches it: the sky stays put while the
## car drives, which is what scenery at infinity does. Anything that should
## instead drift with the car is parallax and wants a Parallax2D under the level
## root, not this.
##
## Everything is keyed to `backdrop_seed`, so a level gets its own sky for the
## cost of one integer and nothing has to be placed by hand. Like the terrain,
## this runs as @tool: changing an export redraws it in the editor immediately.
##
## To add an element: give it its own export group, write a `_paint_<thing>()`
## that draws into the canvas it is handed, and call it from `_paint()` in
## back-to-front order. Everything is drawn in canvas pixels measured from the
## top left of the screen, so work in fractions of the size passed in rather
## than in absolute coordinates -- the window is not a fixed size.

## Each level should give itself its own, or two levels drive under the same sky.
@export var backdrop_seed := 1337:
	set(value):
		backdrop_seed = value
		_request_repaint()

@export_group("Stars")
@export_range(0, 2000, 1) var star_count := 260:
	set(value):
		star_count = value
		_request_repaint()
@export_range(0.5, 8.0, 0.1) var star_size := 1.8:
	set(value):
		star_size = value
		_request_repaint()
## How much smaller than star_size the smallest stars are, as a fraction of it.
## A field all one size reads as a texture rather than as a sky.
@export_range(0.0, 0.9, 0.05) var star_size_spread := 0.6:
	set(value):
		star_size_spread = value
		_request_repaint()
## Fraction of the screen, from the top, that stars are scattered over. The rest
## is where the ground and the track are, and a star behind the hills is just a
## speck the terrain hides anyway.
@export_range(0.1, 1.0, 0.01) var star_field_height := 0.75:
	set(value):
		star_field_height = value
		_request_repaint()
## Alpha of the faintest stars. The brightest are always fully opaque.
@export_range(0.0, 1.0, 0.05) var star_faintest := 0.25:
	set(value):
		star_faintest = value
		_request_repaint()
@export var star_colour := Color(1.0, 0.98, 0.92):
	set(value):
		star_colour = value
		_request_repaint()

# The CanvasLayer cannot draw, so one Node2D child does all of it. Made in code
# and internal, so it never lands in a level scene and cannot be dragged out of
# shape by hand: the backdrop is generated, not authored.
var _painter: Painter


## The one node that paints. Kept trivial on purpose -- what is drawn is the
## Backdrop's business, so an element added there needs nothing here.
class Painter extends Node2D:
	var backdrop: Backdrop

	func _draw() -> void:
		if backdrop != null:
			backdrop._paint(self)


func _ready() -> void:
	if layer >= 0:
		push_warning("Backdrop should sit on a negative layer, or it draws over the level.")
	_painter = Painter.new()
	_painter.backdrop = self
	add_child(_painter, false, Node.INTERNAL_MODE_BACK)
	# The stretch aspect is "expand", so a wide window really is shown more sky
	# than the design size. Recompose when that changes rather than leaving a
	# bare strip down the side.
	get_viewport().size_changed.connect(_painter.queue_redraw)


## Everything on the layer, painted back to front. This is the running order new
## elements join.
func _paint(canvas: CanvasItem) -> void:
	_paint_stars(canvas, _canvas_size())


## A scatter of stars over the upper part of the screen. Deterministic from the
## seed, so a level's sky is the same every time it loads.
func _paint_stars(canvas: CanvasItem, size: Vector2) -> void:
	if star_count <= 0 or star_size <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = backdrop_seed
	var field := size.y * star_field_height
	for i in star_count:
		# Two rolls, lowest wins: that thins the field out evenly towards the
		# horizon, where an even scatter would read as a flat speckled texture.
		var depth := minf(rng.randf(), rng.randf())
		var at := Vector2(rng.randf() * size.x, depth * field)
		var radius := star_size * (1.0 - rng.randf() * star_size_spread)
		var colour := star_colour
		# Faintest near the horizon as well as smallest, so the two agree.
		colour.a = lerpf(star_faintest, 1.0, rng.randf() * (1.0 - depth))
		canvas.draw_circle(at, radius, colour)


## The canvas the backdrop is composed over, in the pixels the drawing calls use.
## In the editor the viewport is the editor's own, so compose for the size the
## game really runs at; at runtime take the live one, which the stretch aspect
## lets grow wider than that.
func _canvas_size() -> Vector2:
	if not Engine.is_editor_hint():
		var visible := get_viewport().get_visible_rect().size
		if visible.x > 0.0 and visible.y > 0.0:
			return visible
	return Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1280),
		ProjectSettings.get_setting("display/window/size/viewport_height", 720)
	)


func _request_repaint() -> void:
	if _painter != null:
		_painter.queue_redraw()
