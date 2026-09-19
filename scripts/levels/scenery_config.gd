@tool
class_name SceneryConfig
extends Resource
## Complete procedural recipe for the two-band generic parallax scenery.
## Duplicate a .tres resource to give individual levels their own artwork.

@export_group("Colours")
## Colour of the more distant scenery layer.
@export var distant_colour := Color(0.10, 0.13, 0.20, 1.0)
## Colour of the middle scenery layer.
@export var middle_colour := Color(0.13, 0.16, 0.22, 1.0)

@export_group("Parallax")
## How much the distant layer moves relative to the camera. Smaller values make it appear farther away.
@export_range(0.0, 1.0, 0.01) var distant_parallax := 0.10
## How much the middle layer moves relative to the camera. Larger values make it appear closer.
@export_range(0.0, 1.0, 0.01) var middle_parallax := 0.25

@export_group("Shape")
## Seed used to generate the repeatable scenery shapes. Different seeds produce different scenery.
@export var scenery_seed := 1337
## Vertical position of the base of both scenery layers, as a fraction of the screen height.
@export_range(0.25, 0.80, 0.01) var ground := 0.56
## Width of one repeating section of generated scenery, in pixels.
@export_range(200.0, 3000.0, 50.0) var repeat_width := 1200.0
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
## Height of the distant layer's scenery, as a fraction of the screen height.
@export_range(0.05, 1.00, 0.01) var distant_height := 0.38
## Height of the middle layer's scenery, as a fraction of the screen height.
@export_range(0.05, 1.00, 0.01) var middle_height := 0.28
