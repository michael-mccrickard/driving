extends Node2D
## Entry point. Loads one level at a time -- its track, its car, its rules, its
## music -- spawns the car on the terrain and wires the camera and HUD to it.
##
## A run is scored on fuel, not time or distance. The finish line is the near end
## of the terrain's flat run-out, and a run is over the moment *any part* of the
## car is past it -- a nose over the line counts. Past the run-out the terrain
## puts a wall up, so a finished run rolls to a stop against it instead of
## falling off the end; hitting it costs nothing, because the bill was settled
## at the line.
##
## A finished run is deliberately *not* restarted for the player: the bill stays
## on screen next to the standing record until they ask for another go, and only
## then is it banked.
##
## The three moments that end a run -- the line, the dirt, the wall -- are the
## ones that make a noise. They go to the SoundPlayer rather than to the music,
## which has a player of its own so the two can sound at once.

## Sentinel for "no finished run waiting to be banked".
const NO_PENDING := -1.0

## The sounds, named relative to assets/audio/. A folder is picked from at
## random, so the same finish does not sound the same twice; a file is played as
## named. The bed that holds under a finished score is the one clip that loops --
## how long the player looks at their bill is up to them.
const SUCCESS_SOUNDS := "success"
const FAIL_SOUNDS := "fail"
const APPLAUSE_SOUND := "misc/applause.wav"
const WAITING_SOUND := "misc/waiting.mp3"
const IMPACT_SOUND := "misc/impact.wav"

## How long a record-setting run's stats are held back for, in seconds, so the
## flag and the applause have the moment to themselves first.
const RECORD_RESULT_DELAY := 2.0

## Flown from the level's own Finish post while a record-setting run is on show.
## The level's flag goes back up on the restart that banks it, so every level
## starts under the one it was authored with.
const NEW_RECORD_FLAG := preload("res://assets/sprites/new_record_flag.png")

## The levels, in the order NEXT walks them. Kept here rather than in the scene
## so the list is one readable line per level; override it per scene if needed.
@export var levels: Array[LevelConfig] = [
	preload("res://resources/levels/hills.tres"),
	preload("res://resources/levels/dunes.tres"),
	preload("res://resources/levels/high_hills.tres"),
	preload("res://resources/levels/nashville.tres"),
	preload("res://resources/levels/chicago.tres"),
	preload("res://resources/levels/frisco.tres"),
	preload("res://resources/levels/london.tres"),
	preload("res://resources/levels/miami.tres"),
	preload("res://resources/levels/boston.tres"),
	preload("res://resources/levels/dallas.tres"),
	preload("res://resources/levels/chilltown.tres"),
	preload("res://resources/levels/denver.tres"),
	preload("res://resources/levels/indy.tres"),
	preload("res://resources/levels/vegas.tres"),
	preload("res://resources/levels/detroit.tres"),
	preload("res://resources/levels/cleveland.tres"),
	preload("res://resources/levels/cincy.tres"),
]

## Local X on the terrain to drop the car at.
@export var spawn_offset_x := 160.0
## Metres below the lowest ground on the track that counts as falling out of the
## world. Measured off the terrain rather than off the spawn point, because a
## level may legitimately descend a long way below where the car started -- Las
## Vegas drops the best part of a kilometre -- and against the spawn height every
## metre of that reads as a fall. Below the lowest ground there is genuinely
## nothing left to land on, wherever on the track the car went off.
@export var fall_limit_metres := 40.0
## Seconds the car may sit in a state it cannot drive out of -- upside down, or
## out of fuel -- before the run restarts. Without this the player can land on
## the roof or empty the tank and the game simply stops. Set to 0 to require a
## manual reset instead.
@export var auto_recover_seconds := 3.0

@onready var _camera: FollowCamera = $FollowCamera
@onready var _hud: Hud = $Hud
@onready var _music: MusicPlayer = $Music
@onready var _sfx: SoundPlayer = $Sfx

var _level_index := 0
var _terrain: TerrainBase
var _car: Car
var _spawn_point := Vector2.ZERO
## World Y of the lowest ground on the loaded track, read off the terrain once
## per level: the surface is thousands of points long on a track like Las Vegas,
## and it does not move between builds.
var _lowest_ground_y := 0.0
var _finish_x := 0.0
## Near face of the end wall, and whether this run has already hit it. INF on a
## track with no wall, which is what keeps the thud from sounding on one.
var _wall_x := INF
var _wall_hit := false
var _stuck_time := 0.0
## The level's Finish post and the flag it was authored with, so the record flag
## can be run up it and taken down again.
var _finish_sprite: Sprite2D
var _finish_texture: Texture2D
## Fastest the car has been this run, in km/h. Read out with the bill, so like
## the bill it stops at the line: what the rig does rolling into the wall is not
## part of the run.
var _top_speed_kmh := 0.0
## How far the run got, settled at the line for the same reason.
var _finish_distance := 0.0
## Fuel bill of a run that has reached the cliff, held until the restart. A run
## can legitimately finish having spent 0.0, so this needs a sentinel of its own.
var _pending_fuel_used := NO_PENDING
## Whether this run has actually begun moving. Used only for the NEXT button.
var _run_started := false


func _ready() -> void:
	# The HUD's editable fields are deliberately ignorant of the car; this is the
	# only place the two are joined up. Everything goes through a handler here
	# rather than straight to the car, because the car is replaced on every level
	# change and a direct connection would be left pointing at a freed node.
	_hud.burn_rate_set.connect(_on_burn_rate_set)
	_hud.max_speed_set.connect(_on_max_speed_set)
	# Mouse equivalents of the reset_car action and, for the record, of deleting
	# the save file.
	_hud.restart_requested.connect(_restart_run)
	_hud.clear_record_requested.connect(GameState.clear_record)
	_hud.next_level_requested.connect(next_level)
	# The HUD holds no levels of its own, so it is handed the names for the menu
	# behind NEXT and hands back an index into this same list.
	_hud.set_levels(_level_names())
	_hud.level_selected.connect(jump_to_level)
	_hud.music_track_set.connect(_music.set_track)
	_hud.music_enabled_set.connect(_music.set_enabled)
	_music.set_enabled(_hud.is_music_enabled())

	load_level(0)


## Quitting is a way out of a run like any other, and the only one that is not a
## restart or a level change, so it has to settle the bill too: a finished run
## still parked on screen when the window closes has earned its record.
## GameState saves on this notification as well, but it cannot do this part
## itself -- the pending bill lives here and has never been reported to it.
## _bank_pending_run() writes through, so the order the two are notified in does
## not matter.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_CRASH:
		_bank_pending_run()


## Tears down whatever is loaded and builds the level at `index`, wrapping round
## the ends of the list. Everything a level owns is applied here: its track, its
## car, what that car may spend, its music, and the record those runs count
## towards.
func load_level(index: int) -> void:
	if levels.is_empty():
		push_error("main.gd has no levels to load.")
		return
	_level_index = posmod(index, levels.size())
	var config := levels[_level_index]
	# Do this first: the record and tuning below are read per level.
	GameState.set_level(config.save_id)

	_car = null
	_terrain = null
	for old: Node in [get_node_or_null("Level"), get_node_or_null("Car")]:
		if old != null:
			# Out of the tree before the replacement goes in, or the new node
			# lands under a renamed path.
			remove_child(old)
			old.queue_free()

	var track := config.track.instantiate()
	track.name = "Level"
	add_child(track)
	# Taken before the terrain check below can bail out, so that no failed load
	# leaves the post of the level just torn down behind. Not every track need
	# have one, so this is allowed to come back null; it is only ever a flag to
	# swap.
	_finish_sprite = track.get_node_or_null("Finish") as Sprite2D
	_finish_texture = _finish_sprite.texture if _finish_sprite != null else null
	_terrain = track.get_node_or_null("Terrain") as TerrainBase
	if _terrain != null:
		_terrain.visible = true
	if _terrain == null:
		push_error(
			"Level %s has no terrain: Terrain must be a TerrainGenerator or a TerrainAuthor."
			% config.save_id
		)
		return

	# Added after the track, so the car draws over it.
	_car = config.car.instantiate() as Car
	_car.name = "Car"
	add_child(_car)

	# The level's rules go on before last session's tuning, which overrides them.
	_car.set_fuel_capacity(config.fuel_capacity)
	_car.set_burn_rate(config.burn_rate)
	_car.set_max_speed_kmh(config.max_speed_kmh)
	_apply_saved_tuning()

	_spawn_point = _terrain.surface_point_at(spawn_offset_x) + Vector2(0.0, -80.0)
	_lowest_ground_y = _terrain.lowest_surface_y()
	_finish_x = _terrain.finish_x()
	_wall_x = _terrain.wall_x()
	_wall_hit = false
	_drop_pending_run()
	_stuck_time = 0.0
	_top_speed_kmh = 0.0
	# Whatever the last level was still saying about itself has nothing to do
	# with this one.
	_sfx.silence()
	_car.reset_to(_spawn_point)
	_camera.target = _car.chassis
	_camera.reset_smoothing()

	_hud.set_current_level(_level_index)
	_run_started = false
	_hud.set_next_visible(true)
	# The level names the track; the field is where it can be overridden by hand.
	_hud.set_music_track(config.music)
	_music.set_track(config.music)
	_music.begin_run()


func next_level() -> void:
	jump_to_level(_level_index + 1)


## Leaving the level for another, whether by NEXT or by the menu behind it. Bank
## first: the bill was run up on the level being left, and GameState is about to
## be pointing at the next one.
func jump_to_level(index: int) -> void:
	_bank_pending_run()
	load_level(index)


## The level names, in the order NEXT walks them, for the HUD's menu.
func _level_names() -> PackedStringArray:
	var names := PackedStringArray()
	for config: LevelConfig in levels:
		names.append(config.display_name)
	return names


## Puts last session's burn rate and top speed back into the car. Deliberately
## not routed through the handlers below: restoring the settings a record was set
## with is not a change to them, and counting it as one would wipe that record on
## every launch.
func _apply_saved_tuning() -> void:
	if not GameState.has_tuning():
		return
	_car.set_burn_rate(GameState.burn_rate)
	_car.set_max_speed_kmh(GameState.max_speed_kmh)


## Both of these settings persist and both invalidate the record, so they go to
## GameState as well as to the car. What gets stored is read back off the car,
## not taken from the field, so a value the car clamped is saved as what really
## took effect. The tank is not tunable at all: it is sized past what any run can
## drink, so what it holds never decides anything and reset_to() refills it.
func _on_burn_rate_set(rate: float) -> void:
	_car.set_burn_rate(rate)
	_store_tuning()


func _on_max_speed_set(kmh: float) -> void:
	_car.set_max_speed_kmh(kmh)
	_store_tuning()


func _store_tuning() -> void:
	if not GameState.report_tuning(_car.get_burn_rate(), _car.get_max_speed_kmh()):
		return
	# The tuning change just cleared the record, and a bill run up at the old
	# rates is no more comparable than the record was. Throw it away rather than
	# let it set a record it never earned.
	_drop_pending_run()


func _process(delta: float) -> void:
	# Nothing to drive: a level failed to load and said so at the time.
	if _car == null:
		return
	var distance := _distance_travelled()
	if not has_pending_run():
		_top_speed_kmh = maxf(_top_speed_kmh, _car.get_speed_kmh())
	_hud.set_speed(_car.get_speed())
	_hud.set_distance(distance)
	# The bill is settled at the line, so a finished run reads out what it was
	# billed rather than what the car goes on spending rolling into the wall.
	var used := _pending_fuel_used if has_pending_run() else _car.get_fuel_used()
	_hud.set_fuel(_car.get_fuel(), used, _car.get_fuel_fraction())
	_hud.set_tuning(_car.get_burn_rate(), _car.get_max_speed_kmh())

	# Do not hide NEXT merely because the car starts rolling. A level can
	# move slightly from gravity or physics settling while the player is still
	# deciding what to do. The run is considered started when the player actually
	# presses the accelerator (throttle).
	if not has_pending_run() and not _run_started and Input.get_action_strength("throttle") > 0.0:
		_run_started = true
		_hud.set_next_visible(false)

	if not has_pending_run() and _car.get_front_x() > _finish_x:
		_finish_run()

	# The wall is part of the same body as the ground, so there is no contact to
	# listen for that would tell the two apart; where the car is says it plainly
	# enough. Latched, because a car parked against the wall is still touching it.
	if not _wall_hit and _car.get_front_x() >= _wall_x:
		_wall_hit = true
		_sfx.interject(IMPACT_SOUND)

	if _car.chassis.global_position.y > fall_limit_y():
		# Out of the world -- either off the end of the run-out or out of a gap.
		# An unfinished run starts again; a finished one parks instead, so the
		# score has something to sit next to rather than a car falling for ever.
		if has_pending_run():
			_car.hold()
		else:
			_fail_run()
		return

	_update_stall_recovery(delta)


## World Y the car is out of the world past: fall_limit_metres below the lowest
## ground the loaded track has. Worked out per call rather than cached with the
## ground, so the export above still takes effect the moment it is changed in the
## inspector.
func fall_limit_y() -> float:
	return _lowest_ground_y + fall_limit_metres * GameState.PIXELS_PER_METRE


## Whether a finished run is waiting for the restart that banks it.
func has_pending_run() -> bool:
	return _pending_fuel_used >= 0.0


## The car's nose has crossed the line. Lock the fuel bill in the instant that
## happens, but hold it back rather than banking it: the record on screen is
## still the one the player was racing, and _restart_run() is where the two are
## settled. The rig is deliberately left driveable -- it has a run-out to use up
## and a wall to run into, and neither is part of the score.
##
## A record is announced in two beats: the flag and the applause at the line,
## then the stats RECORD_RESULT_DELAY later. Anything else puts its stats up at
## once -- there is no fanfare to wait out.
func _finish_run() -> void:
	_pending_fuel_used = _car.get_fuel_used()
	_hud.set_next_visible(true)
	_finish_distance = _distance_travelled()
	var record := GameState.beats_record(_pending_fuel_used)
	_music.end_run()
	# The fanfare goes where the music was, and behind it whatever should hold
	# under the score: applause for a record, otherwise the waiting bed, which
	# loops because there is no telling how long the bill is looked at for.
	_sfx.play_random(SUCCESS_SOUNDS)
	# Everything the bill is read against is taken now, before the wait below can
	# let any of it move: the record in particular is still the one the run was
	# raced, because _bank_pending_run() has not replaced it with this bill yet.
	var fuel_used := _pending_fuel_used
	var standing_record := GameState.best_fuel_used
	var top_speed := _top_speed_kmh
	var distance := _finish_distance
	if record:
		_sfx.queue_clip(APPLAUSE_SOUND)
		# The flag goes up the instant the line is crossed -- it is the news, and
		# the applause is the rest of it. The stats are held back so they land
		# after that moment rather than over the top of it.
		_fly_flag(NEW_RECORD_FLAG)
		await get_tree().create_timer(RECORD_RESULT_DELAY).timeout
		# Restarted, or gone to another level, while the applause played. That
		# run has been dropped; putting its stats up now would be a ghost.
		if not has_pending_run():
			return
	else:
		_sfx.queue_clip(WAITING_SOUND, true)
	_hud.show_run_result(fuel_used, record, standing_record, top_speed, distance)


## Two states the player cannot drive out of: resting upside down (the wheels
## never touch the ground, so no input does anything) and an empty tank. Restart
## the run once the car has clearly come to rest in either.
func _update_stall_recovery(delta: float) -> void:
	# A finished run is never recovered from. It is over, and an empty tank at the
	# end of one is a result, not a stall.
	if auto_recover_seconds <= 0.0 or has_pending_run():
		return
	var stalled := _car.is_flipped() or not _car.has_fuel()
	if stalled and _car.get_speed() < 25.0:
		_stuck_time += delta
		if _stuck_time >= auto_recover_seconds:
			_fail_run()
	else:
		_stuck_time = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_car"):
		_restart_run()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_mode"):
		# Author/Play is a HUD-only distinction, so the HUD owns the state and
		# main.gd only carries the keystroke to it.
		_hud.toggle_mode()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		get_tree().paused = not get_tree().paused
		get_viewport().set_input_as_handled()


## A run lost rather than left: the car has gone out of the world off a jump it
## did not make, or come to rest in something it cannot drive out of -- on its
## roof, or with the tank empty. The restart is the same one the player can ask
## for by hand; the difference is that this one is a failure, and gets said out
## loud. Restarted first, because that is what clears the last run's sounds, and
## the crunch belongs to this one.
func _fail_run() -> void:
	_restart_run()
	_sfx.play_random(FAIL_SOUNDS)


func _restart_run() -> void:
	_bank_pending_run()
	_run_started = false
	_hud.set_next_visible(true)
	_stuck_time = 0.0
	_top_speed_kmh = 0.0
	_wall_hit = false
	_sfx.silence()
	# reset_to() refills the tank and releases the parked rig, so the next run
	# starts from full and can move again.
	_car.reset_to(_spawn_point)
	_camera.reset_smoothing()
	_music.begin_run()


## A finished run's bill is settled against the record on the way out of the run
## rather than at the finish line, so that the record stays readable beside it
## until the player has had their look.
func _bank_pending_run() -> void:
	if has_pending_run():
		GameState.report_run_complete(_pending_fuel_used)
		GameState.save_game()
	_drop_pending_run()


func _drop_pending_run() -> void:
	_pending_fuel_used = NO_PENDING
	_hud.clear_run_result()
	# Whatever was on the post, the level's own flag is what the next run drives
	# towards -- including a restart of the level that just set the record.
	_fly_flag(_finish_texture)


## How far this run has come, in metres off the start line.
func _distance_travelled() -> float:
	return GameState.px_to_m(_car.chassis.global_position.x - _spawn_point.x)


## Puts a flag on the level's Finish post. Levels are free not to have one.
func _fly_flag(texture: Texture2D) -> void:
	if _finish_sprite == null:
		return
	_finish_sprite.texture = texture
