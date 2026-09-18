@tool
class_name SceneryConfig
extends Resource
## Procedural scenery recipe for a level. The Backdrop owns the drawing code;
## this resource owns the artwork parameters so they can be tuned in the
## Inspector without changing the drawing script.

@export_enum("Generic", "Hills", "Cincy", "Desert", "City", "Coastal")
var environment := "Generic"

@export_group("Colours")
@export var distant_colour := Color(0.10, 0.13, 0.20, 1.0)
@export var middle_colour := Color(0.13, 0.16, 0.22, 1.0)
@export var near_colour := Color(0.20, 0.23, 0.28, 1.0)

@export_group("Hills - Distant Mountains")
@export_range(1, 8, 1) var mountain_min_peaks := 1
@export_range(1, 8, 1) var mountain_max_peaks := 3
@export_range(0.0, 1.0, 0.01) var mountain_min_height := 0.62
@export_range(0.0, 1.0, 0.01) var mountain_max_height := 1.0
@export_range(0.05, 0.50, 0.01) var mountain_min_width := 0.22
@export_range(0.05, 0.50, 0.01) var mountain_max_width := 0.34
@export_range(0.0, 0.25, 0.01) var mountain_center_jitter := 0.07
@export_range(0.0, 1.0, 0.01) var mountain_base_ridge := 0.08
@export_range(0.05, 0.80, 0.01) var mountain_screen_height := 0.38

@export_group("Hills - Middle Rolling Hills")
@export_range(0.05, 0.60, 0.01) var middle_height := 0.31
@export_range(0.0, 1.50, 0.01) var middle_variation := 0.85
@export_range(3, 20, 1) var middle_control_points := 8
@export_range(0, 5, 1) var middle_smoothing_passes := 2
@export_range(0.0, 1.0, 0.01) var middle_min_value := 0.28
@export_range(0.0, 1.0, 0.01) var middle_max_value := 0.82

@export_group("Hills - Near Hills")
@export_range(0.05, 0.50, 0.01) var near_height := 0.17
@export_range(0.0, 1.50, 0.01) var near_variation := 0.30
@export_range(3, 20, 1) var near_control_points := 8
@export_range(0, 5, 1) var near_smoothing_passes := 2
@export_range(0.0, 1.0, 0.01) var near_min_value := 0.28
@export_range(0.0, 1.0, 0.01) var near_max_value := 0.82

@export_group("Hills - Trees")
@export_range(0, 20, 1) var tree_min_count := 3
@export_range(0, 20, 1) var tree_max_count := 6
@export_range(0.0, 1.0, 0.01) var tree_base_height_fraction := 0.30
@export_range(0.01, 0.20, 0.005) var tree_min_height := 0.035
@export_range(0.01, 0.20, 0.005) var tree_max_height := 0.065
@export_range(0.10, 1.50, 0.05) var tree_min_width_fraction := 0.45
@export_range(0.10, 1.50, 0.05) var tree_max_width_fraction := 0.70
@export_range(0.0, 1.0, 0.01) var tree_contrast := 0.35
@export_range(0.0, 0.50, 0.01) var tree_min_position := 0.06
@export_range(0.50, 1.0, 0.01) var tree_max_position := 0.94
