@tool
class_name SceneryConfig
extends Resource
## Complete procedural recipe for the two-band generic parallax scenery.
## Duplicate a .tres resource to give individual levels their own artwork.

@export_group("Colours")
@export var distant_colour := Color(0.10, 0.13, 0.20, 1.0)
@export var middle_colour := Color(0.13, 0.16, 0.22, 1.0)

@export_group("Parallax")
@export_range(0.0, 1.0, 0.01) var distant_parallax := 0.10
@export_range(0.0, 1.0, 0.01) var middle_parallax := 0.25

@export_group("Shape")
@export var scenery_seed := 1337
@export_range(0.25, 0.80, 0.01) var ground := 0.56
@export_range(200.0, 3000.0, 50.0) var repeat_width := 1200.0
@export_range(3, 20, 1) var points := 8
@export_range(0.05, 0.50, 0.01) var peak_min := 0.15
@export_range(0.50, 0.95, 0.01) var peak_max := 0.85
@export_range(0.05, 0.50, 0.01) var width_min := 0.12
@export_range(0.05, 0.50, 0.01) var width_max := 0.30
@export_range(0.10, 1.00, 0.01) var height_min := 0.65
@export_range(0.10, 1.00, 0.01) var height_max := 1.00
@export_range(0.05, 1.00, 0.01) var distant_height := 0.38
@export_range(0.05, 1.00, 0.01) var middle_height := 0.28
