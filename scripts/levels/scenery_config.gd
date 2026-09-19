@tool
class_name SceneryConfig
extends Resource
## Procedural recipe for the two-band generic parallax scenery.
## Duplicate a .tres resource to give individual levels their own artwork.

@export_group("Colours")
@export var distant_colour := Color(0.10, 0.13, 0.20, 1.0)
@export var middle_colour := Color(0.13, 0.16, 0.22, 1.0)

@export_group("Parallax")
@export_range(0.0, 1.0, 0.01) var distant_parallax := 0.10
@export_range(0.0, 1.0, 0.01) var middle_parallax := 0.25
@export_range(200.0, 3000.0, 50.0) var repeat_width := 1200.0
@export_range(3, 20, 1) var points := 8
