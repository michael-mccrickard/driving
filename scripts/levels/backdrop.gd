@tool
class_name Backdrop
extends CanvasLayer
## The sky behind a level. Stars and two-band procedural parallax scenery are
## drawn in screen space so the camera does not affect the sky directly.

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
@export_range(0.0, 0.9, 0.05) var star_size_spread := 0.6:
	set(value):
		star_size_spread = value
		_request_repaint()
@export_range(0.1, 1.0, 0.01) var star_field_height := 0.75:
	set(value):
		star_field_height = value
		_request_repaint()
@export_range(0.0, 1.0, 0.05) var star_faintest := 0.25:
	set(value):
		star_faintest = value
		_request_repaint()
@export var star_colour := Color(1.0, 0.98, 0.92):
	set(value):
		star_colour = value
		_request_repaint()

@export_group("Parallax Scenery")
@export var scenery_config: SceneryConfig

var _painter: Painter

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
	get_viewport().size_changed.connect(_painter.queue_redraw)

func _process(_delta: float) -> void:
	if _painter != null:
		_painter.queue_redraw()

func _paint(canvas: CanvasItem) -> void:
	var size := _canvas_size()
	_paint_stars(canvas, size)
	_paint_scenery(canvas, size)

func _paint_stars(canvas: CanvasItem, size: Vector2) -> void:
	if star_count <= 0 or star_size <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = backdrop_seed
	var field := size.y * star_field_height
	for i in star_count:
		var depth := minf(rng.randf(), rng.randf())
		var at := Vector2(rng.randf() * size.x, depth * field)
		var radius := star_size * (1.0 - rng.randf() * star_size_spread)
		var colour := star_colour
		colour.a = lerpf(star_faintest, 1.0, rng.randf() * (1.0 - depth))
		canvas.draw_circle(at, radius, colour)

func _paint_scenery(canvas: CanvasItem, size: Vector2) -> void:
	if scenery_config == null:
		return

	var camera := get_viewport().get_camera_2d()
	var camera_x := 0.0
	if camera != null:
		camera_x = camera.global_position.x

	var speed_multiplier := _level_parallax_speed_multiplier()

	var ground := size.y * scenery_config.ground
	var repeat_width := scenery_config.repeat_width

	_paint_scenery_band(
		canvas,
		size,
		camera_x,
		ground,
		scenery_config.distant_parallax * speed_multiplier,
		size.y * scenery_config.distant_height,
		scenery_config.distant_colour,
		0,
		repeat_width,
		scenery_config.distant_shape
	)
	_paint_scenery_band(
		canvas,
		size,
		camera_x,
		ground,
		scenery_config.middle_parallax * speed_multiplier,
		size.y * scenery_config.middle_height,
		scenery_config.middle_colour,
		1,
		repeat_width,
		scenery_config.middle_shape
	)


func _level_parallax_speed_multiplier() -> float:
	if Engine.is_editor_hint():
		return 1.0
	var main := get_tree().current_scene
	if main == null:
		return 1.0
	var index_value: Variant = main.get("_level_index")
	var levels_value: Variant = main.get("levels")
	if not index_value is int or not levels_value is Array:
		return 1.0
	var levels: Array = levels_value
	var index := int(index_value)
	if index < 0 or index >= levels.size():
		return 1.0
	var config_value: Variant = levels[index]
	if config_value is LevelConfig:
		return maxf(0.0, config_value.parallax_speed_multiplier)
	return 1.0

func _paint_scenery_band(
	canvas: CanvasItem,
	size: Vector2,
	camera_x: float,
	ground: float,
	parallax: float,
	height: float,
	colour: Color,
	band: int,
	repeat_width: float,
	shape_config: SceneryShapeConfig
) -> void:
	if shape_config == null:
		return

	var offset = -fposmod(camera_x * parallax, repeat_width)
	var x = offset - repeat_width
	var strip_index := floori(camera_x * parallax / repeat_width)

	while x < size.x + repeat_width:
		var rng := RandomNumberGenerator.new()
		rng.seed = shape_config.scenery_seed + band * 100003 + strip_index
		var points := PackedVector2Array()
		points.append(Vector2(x, ground))

		var count = max(3, shape_config.points)
		for i in count:
			var t := float(i) / float(count - 1)
			var px = x + t * repeat_width
			var peak := rng.randf_range(shape_config.peak_min, shape_config.peak_max)
			var width := rng.randf_range(shape_config.width_min, shape_config.width_max)
			var distance := absf(t - peak) / width
			var shape := maxf(0.0, 1.0 - distance)
			var y := ground - height * shape * rng.randf_range(shape_config.height_min, shape_config.height_max)
			points.append(Vector2(px, y))

		points.append(Vector2(x + repeat_width, ground))
		points.append(Vector2(x + repeat_width, size.y + 20.0))
		points.append(Vector2(x, size.y + 20.0))
		canvas.draw_colored_polygon(points, colour)
		x += repeat_width
		strip_index += 1

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
