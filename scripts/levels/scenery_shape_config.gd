@tool
class_name SceneryShapeConfig
extends Resource
## Procedural recipe for the shape of one scenery layer.
## A single resource can be shared by both layers, or each layer can have its own.

@export_group("Generation")
## Seed used to generate the repeatable scenery shapes. Different seeds produce different scenery.
@export var scenery_seed := 1337
## Number of shape points used to define each repeating section. More points create more individual peaks.
@export_range(3, 20, 1) var points := 8
## Minimum horizontal position of a peak within each section, as a fraction of the section width.
@export_range(0.05, 0.50, 0.01) var peak_min := 0.15
## Maximum horizontal position of a peak within each section, as a fraction of the section width.
@export_range(0.50, 0.95, 0.01) var peak_max := 0.85
## Minimum width of each peak, as a fraction of the section width.
@export_range(0.05, 0.50, 0.01) var width_min := 0.12
## Maximum width of each peak, as a fraction of the section width.
@export_range(0.05, 0.50, 0.01) var width_max := 0.30
## Minimum height multiplier for an individual peak.
@export_range(0.10, 1.00, 0.01) var height_min := 0.65
## Maximum height multiplier for an individual peak.
@export_range(0.10, 1.00, 0.01) var height_max := 1.00
