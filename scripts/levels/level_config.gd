class_name LevelConfig
extends Resource
## Everything that makes one level different from another: the track, the car
## driven on it, what that car is allowed to spend, and what plays while you
## drive. `main.gd` holds the list and loads one of these at a time.
##
## The car settings here are applied over whatever the car scene's own CarStats
## carries, so CarStats stays the physics of the vehicle -- mass, torque,
## springs -- while these three are the *rules of this level*. Tuning them in the
## HUD saves per level and clears that level's record only.

## Shown in the HUD, so the record on screen can be told apart from the others.
@export var display_name := "Level"
## Key this level's record and tuning are saved under. Changing it orphans them,
## so treat it as permanent once anyone has played the level.
@export var save_id := ""

@export_group("Scenes")
## Instanced as the level. Must contain a TerrainGenerator or TerrainAuthor named
## "Terrain": main.gd reads the spawn point and the finish line off it.
@export var track: PackedScene
## Instanced as the vehicle. Its root must be a Car.
@export var car: PackedScene

@export_group("Car")
## Tank size for this level. Deliberately far beyond what a run could burn: the
## bill is the score, and running dry is not meant to be what ends a run.
@export_range(0.0, 100000.0, 1.0, "or_greater") var fuel_capacity := 100000.0
@export_range(0.0, 0.05, 0.0001) var burn_rate := 0.001
@export_range(0.0, 400.0, 1.0) var max_speed_kmh := 81.0

@export_group("Audio")
## Track name for the HUD's Music field. A bare filename is looked up in
## assets/audio/ -- see MusicPlayer.
@export var music := "default.mp3"

@export_group("Parallax Scenery")
## Procedural scenery recipe for this level.
@export var scenery_config: SceneryConfig
## Multiplies the scenery parallax rates for this level. 1.0 is the normal
## speed; values below 1.0 slow the scenery without changing the depth spacing.
@export_range(0.0, 2.0, 0.05) var parallax_speed_multiplier := 1.0
