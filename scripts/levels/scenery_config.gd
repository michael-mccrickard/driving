@tool
class_name SceneryConfig
extends Resource
## Complete procedural recipe for the two-band generic parallax scenery.
## Duplicate a .tres resource to give individual levels their own artwork.

@export_group("General")
## Vertical position of the base of both scenery layers, as a fraction of the screen height.
@export_range(0.25, 0.80, 0.01) var ground := 0.56
## Width of one repeating section of generated scenery, in pixels.
@export_range(200.0, 3000.0, 50.0) var repeat_width := 1200.0

@export_group("Distant Layer")
## Colour of the more distant scenery layer.
@export var distant_colour := Color(0.10, 0.13, 0.20, 1.0)
## How much the distant layer moves relative to the camera. Smaller values make it appear farther away.
@export_range(0.0, 1.0, 0.01) var distant_parallax := 0.10
## Height of the distant layer's scenery, as a fraction of the screen height.
@export_range(0.05, 1.00, 0.01) var distant_height := 0.38
## Shape recipe used to generate the distant layer.
@export var distant_shape: SceneryShapeConfig

@export_group("Middle Layer")
## Colour of the middle scenery layer.
@export var middle_colour := Color(0.13, 0.16, 0.22, 1.0)
## How much the middle layer moves relative to the camera. Larger values make it appear closer.
@export_range(0.0, 1.0, 0.01) var middle_parallax := 0.25
## Height of the middle layer's scenery, as a fraction of the screen height.
@export_range(0.05, 1.00, 0.01) var middle_height := 0.28
## Shape recipe used to generate the middle layer.
@export var middle_shape: SceneryShapeConfig
