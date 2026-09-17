@tool
class_name ParallaxScenery
extends Node2D
## Procedural background scenery that moves more slowly than the camera.
##
## This is deliberately separate from Backdrop. Backdrop is screen-space and
## holds the stars still; this node lives in world space and creates the sense
## of depth by giving each scenery band its own horizontal parallax rate.
##
## The scenery is deterministic from `scenery_seed`, so a level gets the same
## landscape every time without hand-placing objects along a long track.

@export var scenery_seed := 1337:
	set(value):
		scenery_seed = value
		_queue_redraw()

@export_group("Distant Mountains")
@export_range(0.0, 1.0, 0.01) var distant_parallax := 0.10
@export var distant_colour := Color(0.10, 0.13, 0.20, 1.0)
@export_range(80.0, 500.0, 1.0) var distant_height := 220.0

@export_group("Middle Hills")
@export_range(0.0, 1.0, 0.01) var middle_parallax := 0.25
@export var middle_colour := Color(0.16, 0.19, 0.25, 1.0)
@export_range(50.0, 350.0, 1.0) var middle_height := 130.0

@export_group("Near Silhouettes")
@export_range(0.0, 1.0, 0.01) var near_parallax := 0.50
@export var near_colour := Color(0.20, 0.23, 0.28, 1.0)
@export_range(20.0, 220.0, 1.0) var near_height := 75.0

@export_group("Layout")
## World Y of the visual horizon. Negative values place scenery above the track
## on the usual screen-oriented Godot coordinate system.
@export var horizon_y := -80.0
@export_range(400.0, 3000.0, 50.0) var repeat_width := 1400.0
@export_range(3, 30, 1) var mountain_points := 9

var _last_camera_x := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		_queue_redraw()
		return
	queue_redraw()


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	# The node itself stays attached to the level, but its drawing origin follows
	# the camera by an amount that cancels part of camera movement. A ratio of
	# 0.10 therefore leaves only 10% of camera travel in the distant layer.
	var camera_x := camera.global_position.x
	if not is_equal_approx(camera_x, _last_camera_x):
		_last_camera_x = camera_x
		queue_redraw()


func _draw() -> void:
	var camera := get_viewport().get_camera_2d()
	var camera_x := camera.global_position.x if camera != null else 0.0
	var half_view := 900.0
	if camera != null:
		half_view = get_viewport_rect().size.x / maxf(camera.zoom.x, 0.01)

	_draw_band(camera_x, half_view, distant_parallax, distant_height, distant_colour, 0)
	_draw_band(camera_x, half_view, middle_parallax, middle_height, middle_colour, 1)
	_draw_band(camera_x, half_view, near_parallax, near_height, near_colour, 2)


func _draw_band(camera_x: float, half_view: float, parallax: float, height: float, colour: Color, band: int) -> void:
	var start := camera_x - half_view - repeat_width
	var end := camera_x + half_view + repeat_width
	var first := floorf(start / repeat_width) * repeat_width
	var x := first
	while x < end:
		var seed := scenery_seed + band * 100003 + int(floorf(x / repeat_width))
		var rng := RandomNumberGenerator.new()
		rng.seed = seed

		var points := PackedVector2Array()
		points.append(Vector2(x, horizon_y + height))
		var count := max(3, mountain_points)
		for i in count:
			var t := float(i) / float(count - 1)
			var px := x + t * repeat_width
			var peak := rng.randf_range(0.15, 0.85)
			var local := absf(t - peak)
			var y := horizon_y + height * (0.35 + local * 0.9)
			points.append(Vector2(px, y))
		points.append(Vector2(x + repeat_width, horizon_y + height))
		points.append(Vector2(x + repeat_width, horizon_y + height + 250.0))
		points.append(Vector2(x, horizon_y + height + 250.0))

		# Move the entire generated band by its parallax fraction. Because the
		# terrain/camera are world-space, this is the visible depth cue.
		var offset_x := camera_x * (1.0 - parallax)
		var shifted := PackedVector2Array()
		for point in points:
			shifted.append(Vector2(point.x + offset_x, point.y))
		draw_colored_polygon(shifted, colour)
		x += repeat_width


func _queue_redraw() -> void:
	if is_inside_tree():
		queue_redraw()
