@tool
extends Node2D
## Draws a wheel procedurally so the project runs with no art assets.
##
## Lives as a child of the wheel RigidBody2D, so it inherits the body's rotation
## and the spokes read as visible spin. Replace with a Sprite2D when you have
## real art.

@export var radius := 16.0:
	set(value):
		radius = value
		queue_redraw()
@export var tyre_colour := Color(0.11, 0.12, 0.18):
	set(value):
		tyre_colour = value
		queue_redraw()
@export var rim_colour := Color(0.72, 0.76, 0.86):
	set(value):
		rim_colour = value
		queue_redraw()
@export_range(3, 12, 1) var spokes := 5:
	set(value):
		spokes = value
		queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, tyre_colour)
	draw_arc(Vector2.ZERO, radius - 1.0, 0.0, TAU, 32, rim_colour * 0.6, 2.0, true)
	for i in spokes:
		var angle := TAU * float(i) / float(spokes)
		var dir := Vector2.RIGHT.rotated(angle)
		draw_line(dir * (radius * 0.25), dir * (radius * 0.72), rim_colour, 2.5, true)
	draw_circle(Vector2.ZERO, radius * 0.28, rim_colour)
