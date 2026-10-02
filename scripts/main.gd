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
## Audio is split into three independent layers: Music for level/waiting music,
## NaturalSfx for physical-world sounds such as the end-wall impact, and EventSfx
## for game events such as finish, applause, and restart.

## Sentinel for "no finished run waiting to be banked".
const NO_PENDING := -1.0

## Event sounds, named relative to assets/audio/. A folder is picked from at
## random, so the same finish does not sound the same twice; a file is played as
## named. Restart is played every time the car is spawned into a run.
const SUCCESS_SOUNDS := "success"
const APPLAUSE_SOUND := "misc/applause.wav"
const RESTART_SOUND := "misc/restart.mp3"
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
	preload("res://resources/levels/denver.tres"),
	#preload("res://resources/levels/high_hills.tres"),
	#preload("res://resources/levels/nashville.tres"),
	preload("res://resources/levels/chicago.tres"),
	#preload("res://resources/levels/frisco.tres"),
	preload("res://resources/levels/london.tres"),
	preload("res://resources/levels/indy.tres"),
	#preload("res://resources/levels/miami.tres"),
	#preload("res://resources/levels/boston.tres"),
	#preload("res://resources/levels/dallas.tres"),
	#preload("res://resources/levels/chilltown.tres"),
	preload("res://resources/levels/vegas.tres"),
	#preload("res://resources/levels/detroit.tres"),
	preload("res://resources/levels/cleveland.tres"),
	preload("res://resources/levels/cincy.tres"),
	preload("res://resources/levels/upward_bound.tres"),
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
@onready var _natural_sfx: NaturalSfx = $NaturalSfx
@onready var _event_sfx: EventSfx = $EventSfx

var _level_index := 0
var _terrain: TerrainBase
var _car: Car
var _spawn_point := Vector2.ZERO
var _lowest_ground_y := 0.0
var _finish_x := 0.0
var _wall_x := INF
var _wall_hit := false
var _stuck_time := 0.0
var _finish_sprite: Sprite2D
var _finish_texture: Texture2D
var _top_speed_kmh := 0.0
var _finish_distance := 0.0
var _pending_fuel_used := NO_PENDING
var _run_started := false


func _ready() -> void:
	_hud.burn_rate_set.connect(_on_burn_rate_set)
	_hud.max_speed_set.connect(_on_max_speed_set)
	_hud.restart_requested.connect(_restart_run)
	_hud.clear_record_requested.connect(GameState.clear_record)
	_hud.next_level_requested.connect(next_level)
	_hud.set_levels(_level_names())
	_hud.set_music_tracks(_music_tracks())
	_hud.level_selected.connect(jump_to_level)
	_hud.music_track_set.connect(_music.set_track)
	_hud.music_enabled_set.connect(_music.set_enabled)
	_hud.mode_changed.connect(_on_hud_mode_changed)
	_music.set_enabled(_hud.is_music_enabled())

	load_level(0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_CRASH:
		_bank_pending_run()


func load_level(index: int) -> void:
	if levels.is_empty():
		push_error("main.gd has no levels to load.")
		return
	_level_index = posmod(index, levels.size())
	var config := levels[_level_index]
	GameState.set_level(config.save_id)

	_car = null
	_terrain = null
	for old: Node in [get_node_or_null("Level"), get_node_or_null("Car")]:
		if old != null:
			remove_child(old)
			old.queue_free()

	var track := config.track.instantiate()
	track.name = "Level"
	add_child(track)
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

	_car = config.car.instantiate() as Car
	_car.name = "Car"
	add_child(_car)

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

	_music.end_run()
	_event_sfx.silence()
	_natural_sfx.silence()
	_car.reset_to(_spawn_point)
	_camera.target = _car.chassis
	_camera.reset_smoothing()
	# The car's own node stays where it was spawned; the chassis is what drives.
	_terrain.set_gap_indicator_target(_car.chassis)

	_hud.set_current_level(_level_index)
	_terrain.set_author_mode(_hud.is_author_mode())
	_run_started = false
	_hud.set_next_visible(true)
	_hud.set_music_track(config.music)
	_music.set_track(config.music)
	_music.begin_run()
	_event_sfx.play_clip(RESTART_SOUND)


func next_level() -> void:
	jump_to_level(_level_index + 1)


func jump_to_level(index: int) -> void:
	_bank_pending_run()
	load_level(index)


func _level_names() -> PackedStringArray:
	var names := PackedStringArray()
	for config: LevelConfig in levels:
		names.append(config.display_name)
	return names


func _music_tracks() -> PackedStringArray:
	var tracks := PackedStringArray()
	for config: LevelConfig in levels:
		if not tracks.has(config.music):
			tracks.append(config.music)
	return tracks


func _apply_saved_tuning() -> void:
	if not GameState.has_tuning():
		return
	_car.set_burn_rate(GameState.burn_rate)
	_car.set_max_speed_kmh(GameState.max_speed_kmh)


func _on_burn_rate_set(rate: float) -> void:
	_car.set_burn_rate(rate)
	_store_tuning()


func _on_max_speed_set(kmh: float) -> void:
	_car.set_max_speed_kmh(kmh)
	_store_tuning()


func _store_tuning() -> void:
	if not GameState.report_tuning(_car.get_burn_rate(), _car.get_max_speed_kmh()):
		return
	_drop_pending_run()


func _process(delta: float) -> void:
	if _car == null:
		return
	var distance := _distance_travelled()
	if not has_pending_run():
		_top_speed_kmh = maxf(_top_speed_kmh, _car.get_speed_kmh())
	_hud.set_speed(_car.get_speed())
	_hud.set_distance(distance)
	var used := _pending_fuel_used if has_pending_run() else _car.get_fuel_used()
	_hud.set_fuel(_car.get_fuel(), used, _car.get_fuel_fraction())
	_hud.set_tuning(_car.get_burn_rate(), _car.get_max_speed_kmh())

	if not has_pending_run() and not _run_started and Input.get_action_strength("throttle") > 0.0:
		_run_started = true
		_hud.set_next_visible(false)

	if not has_pending_run() and _car.get_front_x() > _finish_x:
		_finish_run()

	if not _wall_hit and _car.get_front_x() >= _wall_x:
		_wall_hit = true
		_natural_sfx.play_clip(IMPACT_SOUND)

	if _car.chassis.global_position.y > fall_limit_y():
		if has_pending_run():
			_car.hold()
		else:
			_fail_run()
		return

	_update_stall_recovery(delta)


func fall_limit_y() -> float:
	return _lowest_ground_y + fall_limit_metres * GameState.PIXELS_PER_METRE


func has_pending_run() -> bool:
	return _pending_fuel_used >= 0.0


func _finish_run() -> void:
	_pending_fuel_used = _car.get_fuel_used()
	_hud.set_next_visible(true)
	_finish_distance = _distance_travelled()
	var record := GameState.beats_record(_pending_fuel_used)
	_music.begin_waiting()
	_event_sfx.play_random(SUCCESS_SOUNDS)

	var fuel_used := _pending_fuel_used
	var standing_record := GameState.best_fuel_used
	var top_speed := _top_speed_kmh
	var distance := _finish_distance
	if record:
		_event_sfx.queue_clip(APPLAUSE_SOUND)
		_fly_flag(NEW_RECORD_FLAG)
		await get_tree().create_timer(RECORD_RESULT_DELAY).timeout
		if not has_pending_run():
			return
	_hud.show_run_result(fuel_used, record, standing_record, top_speed, distance)


func _update_stall_recovery(delta: float) -> void:
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
		_hud.toggle_mode()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		get_tree().paused = not get_tree().paused
		get_viewport().set_input_as_handled()


func _fail_run() -> void:
	_restart_run()


func _restart_run() -> void:
	_bank_pending_run()
	_run_started = false
	_hud.set_next_visible(true)
	_stuck_time = 0.0
	_top_speed_kmh = 0.0
	_wall_hit = false
	_event_sfx.silence()
	_natural_sfx.silence()
	_car.reset_to(_spawn_point)
	_camera.reset_smoothing()
	_music.begin_run()
	_event_sfx.play_clip(RESTART_SOUND)


func _bank_pending_run() -> void:
	if has_pending_run():
		GameState.report_run_complete(_pending_fuel_used)
		GameState.save_game()
	_drop_pending_run()


func _drop_pending_run() -> void:
	_pending_fuel_used = NO_PENDING
	_hud.clear_run_result()
	_fly_flag(_finish_texture)


func _distance_travelled() -> float:
	return GameState.px_to_m(_car.chassis.global_position.x - _spawn_point.x)


func _fly_flag(texture: Texture2D) -> void:
	if _finish_sprite == null:
		return
	_finish_sprite.texture = texture


func _on_hud_mode_changed(authoring: bool) -> void:
	if _terrain != null:
		_terrain.set_author_mode(authoring)
