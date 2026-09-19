@tool
class_name SceneryShapeConfig
extends Resource
## Procedural recipe for the shape of one scenery layer.
## A single resource can be shared by both layers, or each layer can have its own.

@export_group("Generation")
## Seed used to generate the repeatable scenery shapes. Different seeds produce different scenery.
@export var scenery_seed := 1337:
	set(value):
		scenery_seed = value
		emit_changed()
## Number of shape points used to define each repeating section. More points create more individual peaks.
@export_range(3, 20, 1) var points := 8:
	set(value):
		points = value
		emit_changed()
## Minimum horizontal position of a peak within each section, as a fraction of the section width.
@export_range(0.05, 0.50, 0.01) var peak_min := 0.15:
	set(value):
		peak_min = value
		emit_changed()
## Maximum horizontal position of a peak within each section, as a fraction of the section width.
@export_range(0.50, 0.95, 0.01) var peak_max := 0.85:
	set(value):
		peak_max = value
		emit_changed()
## Minimum width of each peak, as a fraction of the section width.
@export_range(0.05, 0.50, 0.01) var width_min := 0.12:
	set(value):
		width_min = value
		emit_changed()
## Maximum width of each peak, as a fraction of the section width.
@export_range(0.05, 0.50, 0.01) var width_max := 0.30:
	set(value):
		width_max = value
		emit_changed()
## Minimum height multiplier for an individual peak.
@export_range(0.10, 1.00, 0.01) var height_min := 0.65:
	set(value):
		height_min = value
		emit_changed()
## Maximum height multiplier for an individual peak.
@export_range(0.10, 1.00, 0.01) var height_max := 1.00:
	set(value):
		height_max = value
		emit_changed()
