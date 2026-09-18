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
## instead drift with the car is parallax and is painted here from camera motion.
##
## Everything is keyed to `backdrop_seed`, so a level gets its own sky for the
## cost of one integer and nothing has to be placed by hand. Like the terrain,
## this runs as @tool: changing an export redraws it in the editor immediately.

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
## Horizontal movement fractions. Lower values read as farther away.
@export_range(0.0, 1.0, 0.01) var distant_parallax := 0.10
@export_range(0.0, 1.0, 0.01) var middle_parallax := 0.25
@export_range(0.0, 1.0, 0.01) var near_parallax := 0.50
## The scenery ground line is deliberately aligned with the starting road
## level. The silhouettes grow upward from this line and the terrain is drawn
## in front of them, so hills remain behind dips and rises in the track.
@export_range(0.25, 0.80, 0.01) var scenery_ground := 0.56
@export var distant_colour := Color(0.10, 0.13, 0.20, 1.0)
@export var middle_colour := Color(0.16, 0.19, 0.25, 1.0)
@export var near_colour := Color(0.20, 0.23, 0.28, 1.0)
@export_range(200.0, 3000.0, 50.0) var scenery_repeat_width := 1200.0
@export_range(3, 20, 1) var scenery_points := 8

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
	# The scenery is drawn in screen space, so camera motion only changes it when
	# the painter is redrawn. Custom drawing is cached until queue_redraw() is
	# called, so repaint once per frame while the camera is moving.
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


## Three silhouette bands. They are screen-space because Backdrop already owns
## the sky; camera motion is converted to a different offset for each depth.
func _paint_scenery(canvas: CanvasItem, size: Vector2) -> void:
	var camera := get_viewport().get_camera_2d()
	var camera_x := camera.global_position.x if camera != null else 0.0
	var ground := size.y * scenery_ground
	var speed_multiplier := _level_parallax_speed_multiplier()
	var environment := _level_scenery_environment()

	if environment == "Hills":
		_paint_hills_scenery(canvas, size, camera_x, ground, speed_multiplier)
	else:
		_paint_generic_scenery(canvas, size, camera_x, ground, speed_multiplier)


func _paint_generic_scenery(canvas: CanvasItem, size: Vector2, camera_x: float, ground: float, speed_multiplier: float) -> void:
	_paint_scenery_band(canvas, size, camera_x, ground, distant_parallax * speed_multiplier, size.y * 0.38, distant_colour, 0)
	_paint_scenery_band(canvas, size, camera_x, ground, middle_parallax * speed_multiplier, size.y * 0.28, middle_colour, 1)
	_paint_scenery_band(canvas, size, camera_x, ground, near_parallax * speed_multiplier, size.y * 0.20, near_colour, 2)


func _level_scenery_environment() -> String:
	if Engine.is_editor_hint():
		return "Generic"
	var main := get_tree().current_scene
	if main == null:
		return "Generic"
	var index_value: Variant = main.get("_level_index")
	var levels_value: Variant = main.get("levels")
	if not index_value is int or not levels_value is Array:
		return "Generic"
	var levels: Array = levels_value
	var index := int(index_value)
	if index < 0 or index >= levels.size():
		return "Generic"
	var config_value: Variant = levels[index]
	if config_value is LevelConfig:
		return config_value.scenery_environment
	return "Generic"


## LevelConfig lives outside the level scene, so at runtime the backdrop finds
## the active config through Main. This keeps the per-level speed setting in the
## .tres resource rather than duplicating it on every level scene.
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


func _paint_hills_scenery(canvas: CanvasItem, size: Vector2, camera_x: float, ground: float, speed_multiplier: float) -> void:
	_paint_hills_mountains(canvas, size, camera_x, ground, distant_parallax * speed_multiplier)
	_paint_hills_rolling_band(canvas, size, camera_x, ground, middle_parallax * speed_multiplier, size.y * 0.29, middle_colour, 1, 0.70)
	_paint_hills_rolling_band(canvas, size, camera_x, ground, near_parallax * speed_multiplier, size.y * 0.17, near_colour, 2, 0.30)


func _paint_hills_mountains(canvas: CanvasItem, size: Vector2, camera_x: float, ground: float, parallax: float) -> void:
	var offset := -fposmod(camera_x * parallax, scenery_repeat_width)
	var x := offset - scenery_repeat_width
	var strip_index := floori(camera_x * parallax / scenery_repeat_width)

	while x < size.x + scenery_repeat_width:
		var rng := RandomNumberGenerator.new()
		rng.seed = backdrop_seed + 500003 + strip_index
		var peak_count := rng.randi_range(1, 3)
		var peaks := []
		for peak_index in peak_count:
			var center := (float(peak_index) + 0.5) / float(peak_count)
			center += rng.randf_range(-0.07, 0.07)
			var peak_height := rng.randf_range(0.62, 1.0)
			var peak_width := rng.randf_range(0.22, 0.34)
			peaks.append([center, peak_height, peak_width])

		var points := PackedVector2Array()
		points.append(Vector2(x, ground))
		var count = max(16, scenery_points * 3)
		for i in count:
			var t := float(i) / float(count - 1)
			var ridge := 0.08
			for peak in peaks:
				var distance = absf(t - peak[0]) / peak[2]
				var shape := clampf(1.0 - distance, 0.0, 1.0)
				# A rounded peak with broad shoulders reads as a distant
				# mountain range rather than a row of triangles.
				shape = shape * shape * (3.0 - 2.0 * shape)
				ridge = maxf(ridge, shape * peak[1])

			var y := ground - size.y * 0.38 * ridge
			points.append(Vector2(x + t * scenery_repeat_width, y))

		points.append(Vector2(x + scenery_repeat_width, ground))
		points.append(Vector2(x + scenery_repeat_width, size.y + 20.0))
		points.append(Vector2(x, size.y + 20.0))
		canvas.draw_colored_polygon(points, distant_colour)

		x += scenery_repeat_width
		strip_index += 1


func _paint_hills_rolling_band(canvas: CanvasItem, size: Vector2, camera_x: float, ground: float, parallax: float, height: float, colour: Color, band: int, variation: float) -> void:
	var offset := -fposmod(camera_x * parallax, scenery_repeat_width)
	var x := offset - scenery_repeat_width
	var strip_index := floori(camera_x * parallax / scenery_repeat_width)

	while x < size.x + scenery_repeat_width:
		var rng := RandomNumberGenerator.new()
		rng.seed = backdrop_seed + 600001 + band * 100003 + strip_index
		var control_count := 8
		var values := []
		for i in control_count:
			values.append(rng.randf_range(0.18, 0.82))

		for _pass in 2:
			var smoothed := []
			smoothed.append(values[0])
			for i in range(1, control_count - 1):
				smoothed.append((values[i - 1] + values[i] * 2.0 + values[i + 1]) / 4.0)
			smoothed.append(values[control_count - 1])
			values = smoothed

		var points := PackedVector2Array()
		points.append(Vector2(x, ground))
		var count = max(12, scenery_points * 2)
		for i in count:
			var t := float(i) / float(count - 1)
			var position := t * float(control_count - 1)
			var index := clampi(floori(position), 0, control_count - 2)
			var blend := position - float(index)
			# Ease between control points so the hills have broad, natural shoulders.
			blend = blend * blend * (3.0 - 2.0 * blend)
			var value := lerpf(values[index], values[index + 1], blend)
			var y := ground - height * value * variation
			points.append(Vector2(x + t * scenery_repeat_width, y))

		points.append(Vector2(x + scenery_repeat_width, ground))
		points.append(Vector2(x + scenery_repeat_width, size.y + 20.0))
		points.append(Vector2(x, size.y + 20.0))
		canvas.draw_colored_polygon(points, colour)

		if band == 2:
			_paint_hills_trees(canvas, size, x, ground, height, values, rng, control_count)

		x += scenery_repeat_width
		strip_index += 1


func _paint_hills_trees(canvas: CanvasItem, size: Vector2, x: float, ground: float, height: float, values: Array, rng: RandomNumberGenerator, control_count: int) -> void:
	var tree_colour := near_colour.lerp(Color(0.0, 0.0, 0.0, 1.0), 0.35)
	var tree_count := rng.randi_range(3, 6)

	for tree_index in tree_count:
		var t := rng.randf_range(0.06, 0.94)
		var position := t * float(control_count - 1)
		var index := clampi(floori(position), 0, control_count - 2)
		var blend := position - float(index)
		var value := lerpf(values[index], values[index + 1], blend)
		var base_y := ground - height * value * 0.30
		var tree_height := rng.randf_range(size.y * 0.035, size.y * 0.065)
		var tree_width := tree_height * rng.randf_range(0.45, 0.70)
		var tree_x := x + t * scenery_repeat_width

		canvas.draw_rect(Rect2(tree_x - tree_width * 0.10, base_y - tree_height * 0.28, tree_width * 0.20, tree_height * 0.30), tree_colour)
		var top := base_y - tree_height
		var lower := PackedVector2Array([
			Vector2(tree_x, top),
			Vector2(tree_x - tree_width * 0.42, base_y - tree_height * 0.38),
			Vector2(tree_x + tree_width * 0.42, base_y - tree_height * 0.38)
		])
		var upper := PackedVector2Array([
			Vector2(tree_x, top - tree_height * 0.18),
			Vector2(tree_x - tree_width * 0.32, base_y - tree_height * 0.58),
			Vector2(tree_x + tree_width * 0.32, base_y - tree_height * 0.58)
		])
		canvas.draw_colored_polygon(lower, tree_colour)
		canvas.draw_colored_polygon(upper, tree_colour)


func _paint_scenery_band(
	canvas: CanvasItem,
	size: Vector2,
	camera_x: float,
	ground: float,
	parallax: float,
	height: float,
	colour: Color,
	band: int
) -> void:
	var offset = -fposmod(camera_x * parallax, scenery_repeat_width)
	var x = offset - scenery_repeat_width
	var strip_index := floori(camera_x * parallax / scenery_repeat_width)

	while x < size.x + scenery_repeat_width:
		var rng := RandomNumberGenerator.new()
		rng.seed = backdrop_seed + band * 100003 + strip_index
		var points := PackedVector2Array()
		points.append(Vector2(x, ground))

		var count = max(3, scenery_points)
		for i in count:
			var t := float(i) / float(count - 1)
			var px = x + t * scenery_repeat_width
			var peak := rng.randf_range(0.15, 0.85)
			var width := rng.randf_range(0.12, 0.30)
			var distance := absf(t - peak) / width
			var shape := maxf(0.0, 1.0 - distance)
			var y := ground - height * shape * rng.randf_range(0.65, 1.0)
			points.append(Vector2(px, y))

		points.append(Vector2(x + scenery_repeat_width, ground))
		points.append(Vector2(x + scenery_repeat_width, size.y + 20.0))
		points.append(Vector2(x, size.y + 20.0))
		canvas.draw_colored_polygon(points, colour)
		x += scenery_repeat_width
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
