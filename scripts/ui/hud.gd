class_name Hud
extends CanvasLayer
## Readout and live tuning panel: speed, distance, fuel spent and the stored
## record are read-only, while burn rate and top speed are editable so values
## can be experimented with without restarting.
##
## Two modes decide how much of that is on show -- see Mode. The mode is purely a
## HUD concern: nothing about the car or the scoring changes with it.
##
## The HUD knows nothing about the car. It emits a signal per field and main.gd
## wires those to the Car; main.gd pushes the current values back in every frame.

## Emitted when the player commits a new value in the matching field.
signal burn_rate_set(rate: float)
signal max_speed_set(kmh: float)

## Emitted by the buttons. Like the fields, the HUD only announces the request:
## main.gd puts the car back on the start line, GameState owns the record.
signal restart_requested
signal clear_record_requested
signal next_level_requested

## A level picked out of the menu NEXT hides, as an index into the list the HUD
## was handed by set_levels().
signal level_selected(index: int)

## The music track to play, and whether to play it at all. Both are HUD state
## for the same reason the mode is: main.gd owns the MusicPlayer that acts on it.
signal music_track_set(track: String)
signal music_enabled_set(enabled: bool)
signal mode_changed(authoring: bool)

## AUTHOR is the tuning sandbox: every field on show and editable, including the
## music track and the record wipe. PLAY is the game as played -- the knobs that
## would let you cheat the record are gone, and music is a plain on/off switch.
## The fuel readout is the same in both: the tank is far bigger than any run can
## drink, so the only number worth showing is what the run has spent.
enum Mode {
	AUTHOR,
	PLAY,
}

## Fraction of the tank below which the fuel readout starts warning.
const LOW_FUEL_FRACTION := 0.25

const COLOUR_FUEL_OK := Color(0.85, 0.89, 1, 1)
const COLOUR_FUEL_LOW := Color(1, 0.82, 0.35, 1)
const COLOUR_FUEL_EMPTY := Color(1, 0.42, 0.38, 1)

const COLOUR_RESULT := Color(0.85, 0.89, 1, 1)
const COLOUR_RESULT_BEST := Color(0.55, 0.9, 0.6, 1)

## The level menu's entries, and the one that is loaded.
const COLOUR_LEVEL := Color(0.85, 0.89, 1, 1)
const COLOUR_LEVEL_CURRENT := Color(1, 0.85, 0.35, 1)

const INPUT_FONT_SIZE := 18
const LEVEL_BUTTON_FONT_SIZE := 16

## How tall a column of level buttons is allowed to get before the menu opens a
## second one beside it. The menu stands on NEXT in the bottom corner and grows
## upwards, so a single column runs off the top of the screen once there are
## enough levels; columns are what keep every level reachable however many there
## are. The entries are spread evenly over as many columns as that takes, so
## sixteen levels read as two columns of eight rather than a full column with one
## stray next to it.
const LEVEL_MENU_MAX_ROWS := 12

## The gap between buttons within a column. The gap *between* columns is the
## LevelMenu's own separation, authored in hud.tscn; the columns are built here,
## so theirs has to be set here.
const LEVEL_MENU_ROW_SEPARATION := 4

## MusicToggle is a plain Button, not a CheckButton, so nothing about it shows
## whether the music is on. Dim its icon when it is off.
const MUSIC_OFF_MODULATE := Color(1, 1, 1, 0.4)
const MUSIC_BUTTON_FONT_SIZE := 16

@onready var _level_label: Label = %LevelLabel
# Parked: these three are hidden in hud.tscn for now, in both modes. They are
# still written to every frame, so unhiding them in the editor is all it takes to
# have them back -- nothing here gates them.
@onready var _speed_label: Label = %SpeedLabel
@onready var _distance_label: Label = %DistanceLabel
@onready var _best_label: Label = %BestLabel
@onready var _fuel_name: Label = %FuelName
@onready var _fuel_value: Label = %FuelValue
@onready var _burn_rate_name: Label = %BurnRateName
@onready var _burn_rate_input: SpinBox = %BurnRateInput
@onready var _max_speed_name: Label = %MaxSpeedName
@onready var _max_speed_input: SpinBox = %MaxSpeedInput
@onready var _music_name: Label = %MusicName
@onready var _music_input: LineEdit = %MusicInput
@onready var _music_toggle: Button = %MusicToggle
@onready var _music_menu: VBoxContainer = %MusicMenu
@onready var _music_tracks: VBoxContainer = %MusicTracks
@onready var _music_enabled_button: CheckButton = %MusicEnabled
@onready var _result_panel: PanelContainer = %ResultPanel
@onready var _fuel_line: Label = %FuelLine
@onready var _record_line: Label = %RecordLine
@onready var _speed_line: Label = %SpeedLine
@onready var _distance_line: Label = %DistanceLine
@onready var _restart_button: Button = %RestartButton
@onready var _clear_record_button: Button = %ClearRecordButton
@onready var _next_button: Button = %NextButton
@onready var _level_menu: HBoxContainer = %LevelMenu

var mode := Mode.PLAY

# Must start equal to the colour authored on FuelValue in hud.tscn.
var _fuel_colour := COLOUR_FUEL_OK

# MusicToggle presses rather than latches, so the on/off state lives here.
# Starts on: a run opens with its track playing.
var _music_enabled := true
var _music_tracks_list := PackedStringArray()
var _music_track_buttons: Array[Button] = []
var _current_music_track := ""

# The level menu: the names it was built from, and which of them is loaded.
var _level_names := PackedStringArray()
var _current_level := -1
# The menu's buttons in level order, kept because the menu itself is a row of
# columns and no longer holds one button per child.
var _level_buttons: Array[Button] = []


func _ready() -> void:
	GameState.best_fuel_used_changed.connect(set_best_fuel_used)
	set_best_fuel_used(GameState.best_fuel_used)

	# The buttons are focus_mode = None in hud.tscn on purpose: a button that kept
	# focus after a click would swallow Space (the mode toggle) to press itself
	# again.
	_restart_button.pressed.connect(restart_requested.emit)
	_clear_record_button.pressed.connect(clear_record_requested.emit)
	_next_button.pressed.connect(next_level_requested.emit)
	# A Button only presses on the left mouse button, so the right one is free to
	# mean something else here: the level menu, stacked above NEXT.
	_next_button.gui_input.connect(_on_next_button_gui_input)

	# A plain Button only reports the press, so the switch is flipped by hand.
	_music_toggle.pressed.connect(_on_music_toggle_pressed)
	_music_enabled_button.toggled.connect(_on_music_enabled_toggled)
	_music_enabled_button.button_pressed = _music_enabled
	_paint_music_toggle()
	_music_input.add_theme_font_size_override("font_size", INPUT_FONT_SIZE)
	_music_input.text_submitted.connect(_on_music_submitted)

	_burn_rate_input.value_changed.connect(burn_rate_set.emit)
	_max_speed_input.value_changed.connect(max_speed_set.emit)

	for spin: SpinBox in [_burn_rate_input, _max_speed_input]:
		# A SpinBox styles its own LineEdit, so theme overrides have to go on the
		# inner control -- setting them on the SpinBox does nothing.
		var field := spin.get_line_edit()
		field.add_theme_font_size_override("font_size", INPUT_FONT_SIZE)
		# Enter commits and hands the keyboard back to the game. Without this the
		# arrow keys keep driving the text cursor instead of the car.
		field.text_submitted.connect(_on_field_submitted.bind(field))

	set_mode(mode)


func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	var authoring := mode == Mode.AUTHOR
	for node: Control in [
		_burn_rate_name, _burn_rate_input, _max_speed_name, _max_speed_input,
		_music_name, _music_input,
		# Wiping the record is an authoring act; a player only sets records.
		_clear_record_button,
	]:
		node.visible = authoring
	# The fuel readout is deliberately not in that list: the tank cannot run dry,
	# so the bill is the same number in both modes. Music is the one control that
	# swaps rather than vanishes -- a track name to author with, a switch to play
	# with.
	_music_toggle.visible = not authoring
	mode_changed.emit(authoring)


func is_author_mode() -> bool:
	return mode == Mode.AUTHOR


func toggle_mode() -> void:
	set_mode(Mode.PLAY if mode == Mode.AUTHOR else Mode.AUTHOR)


## Fills the menu a right-click on NEXT opens, in the order NEXT walks them.
## The HUD knows nothing about levels: it is handed the names and reports a pick
## back as an index into them.
func set_levels(names: PackedStringArray) -> void:
	_level_names = names
	_level_buttons.clear()
	for old: Node in _level_menu.get_children():
		_level_menu.remove_child(old)
		old.queue_free()
	if names.is_empty():
		return
	# Filled down one column and on to the next, so reading the menu left to right
	# and top to bottom is the order NEXT walks.
	var columns := ceili(float(names.size()) / LEVEL_MENU_MAX_ROWS)
	var rows := ceili(float(names.size()) / columns)
	var column: VBoxContainer = null
	for i in names.size():
		if i % rows == 0:
			column = VBoxContainer.new()
			column.add_theme_constant_override("separation", LEVEL_MENU_ROW_SEPARATION)
			# Columns are top-aligned, so a last column with a gap in it leaves that
			# gap down by NEXT rather than a ragged top edge.
			column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			_level_menu.add_child(column)
		var button := Button.new()
		button.text = names[i]
		# Same reason as the buttons authored in hud.tscn: a button holding focus
		# would swallow Space, the mode toggle.
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", LEVEL_BUTTON_FONT_SIZE)
		button.pressed.connect(_on_level_pressed.bind(i))
		column.add_child(button)
		_level_buttons.append(button)
	_paint_level_buttons()


## Which level's numbers are on screen: names it in the readout and marks it in
## the menu. The record is per level, so without this the best line would
## silently change meaning on the way to the next one.
## Shows or hides NEXT without changing the level menu itself.
func set_next_visible(visible: bool) -> void:
	_next_button.visible = visible
	if not visible:
		_level_menu.visible = false


func set_current_level(index: int) -> void:
	_current_level = index
	if index >= 0 and index < _level_names.size():
		_level_label.text = _level_names[index]
	_paint_level_buttons()


## Pushes the level's track into the Music field. Typing over it is a live
## override; loading a level puts the level's own track back.
func set_music_tracks(tracks: PackedStringArray) -> void:
	_music_tracks_list = tracks
	_music_track_buttons.clear()
	for old: Node in _music_tracks.get_children():
		_music_tracks.remove_child(old)
		old.queue_free()
	for track in tracks:
		var button := Button.new()
		button.text = track
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(170, 30)
		button.add_theme_font_size_override("font_size", MUSIC_BUTTON_FONT_SIZE)
		button.pressed.connect(_on_music_track_pressed.bind(track))
		_music_tracks.add_child(button)
		_music_track_buttons.append(button)
	_paint_music_track_buttons()


func set_music_track(track: String) -> void:
	_music_input.text = track
	_current_music_track = track
	_paint_music_track_buttons()


func set_speed(pixels_per_second: float) -> void:
	_speed_label.text = "%3d km/h" % roundi(GameState.px_per_sec_to_kmh(pixels_per_second))


## The fuel readout is what the run has spent so far, which is the number the
## record is kept in. `remaining` and `fraction` (remaining/capacity) are passed
## alongside it only to drive the warning colours, so those thresholds hold for
## whatever tank size CarStats is carrying -- a level small enough to run dry
## still says so, even though the stock tank never can.
func set_fuel(remaining: float, used: float, fraction: float) -> void:
	# The fuel plaque names the row, so FuelName is left to carry the one thing a
	# plaque cannot: the warning that the throttle has stopped answering.
	_fuel_name.visible = remaining <= 0.0
	if remaining <= 0.0:
		_set_fuel_colour(COLOUR_FUEL_EMPTY)
	else:
		_set_fuel_colour(COLOUR_FUEL_LOW if fraction <= LOW_FUEL_FRACTION else COLOUR_FUEL_OK)
	_fuel_value.text = "%.1f" % used


## Pushes the car's current tuning back into the fields. Called every frame, so
## a value the car clamped visibly snaps back to what actually took effect.
func set_tuning(burn_rate: float, max_speed_kmh: float) -> void:
	_show(_burn_rate_input, burn_rate)
	_show(_max_speed_input, max_speed_kmh)


func set_distance(metres: float) -> void:
	_distance_label.text = "%.1f m" % metres


func set_best_fuel_used(fuel: float) -> void:
	# GameState.NO_RECORD, i.e. nothing has reached the finish line yet. There is
	# then nothing for the reset button to clear, so grey it out.
	_clear_record_button.disabled = fuel < 0.0
	if fuel < 0.0:
		_best_label.text = "Best  --"
		return
	_best_label.text = "Best  %.1f fuel" % fuel


## Shows what a run that has just crossed the line did: what it spent, how that
## reads against the standing record, and the two numbers the record says nothing
## about. It stays up until the player restarts, which is the point: `best` is
## still the record they were racing, so the two can be read side by side.
## `is_best` says the bill will take that record once the restart banks it.
##
## `best` is the record as it stands *before* this run is banked, or
## GameState.NO_RECORD on a track nothing has finished yet -- so a first finish
## is a record with nothing to compare against, and says so.
func show_run_result(
	fuel_used: float, is_best: bool, best: float, max_speed_kmh: float, distance: float
) -> void:
	_fuel_line.text = "Fuel Consumed: %s" % _fuel_text(fuel_used)
	if is_best and best < 0.0:
		_record_line.text = "New record: %s.  The first one on this level." % _fuel_text(fuel_used)
	elif is_best:
		_record_line.text = "New record: %s.  The old record was: %s" % [
			_fuel_text(fuel_used), _fuel_text(best)
		]
	else:
		_record_line.text = "You were %s above the record." % _fuel_text(fuel_used - best)
	_record_line.add_theme_color_override(
		"font_color", COLOUR_RESULT_BEST if is_best else COLOUR_RESULT
	)
	_speed_line.text = "Maximum Speed: %d km/h" % roundi(max_speed_kmh)
	_distance_line.text = "Distance Traveled: %.1f m" % distance
	_result_panel.visible = true


func clear_run_result() -> void:
	_result_panel.visible = false


## Fuel is billed in gallons wherever it is spelled out in words.
func _fuel_text(fuel: float) -> String:
	return "%.1f g" % fuel


## Right-click opens and closes the menu; left-click is the button's own
## business, so NEXT still just advances.
func _on_next_button_gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_RIGHT or not click.pressed:
		return
	_level_menu.visible = not _level_menu.visible
	_next_button.accept_event()


func _on_level_pressed(index: int) -> void:
	# The pick is made; leaving the menu up over the new level's track is noise.
	_level_menu.visible = false
	level_selected.emit(index)


## Yellow marks the level that is loaded. The hover and pressed colours are set
## alongside it, or the mark would disappear under the mouse that is about to
## click it.
func _paint_level_buttons() -> void:
	for i in _level_buttons.size():
		var button := _level_buttons[i]
		var colour := COLOUR_LEVEL_CURRENT if i == _current_level else COLOUR_LEVEL
		for role: String in [
			"font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color",
		]:
			button.add_theme_color_override(role, colour)


## Writes a live value into a field without disturbing an edit in progress, and
## without the write bouncing straight back out as a value_changed signal.
func _show(spin: SpinBox, value: float) -> void:
	if spin.get_line_edit().has_focus():
		return
	spin.set_value_no_signal(value)


func _on_field_submitted(_text: String, field: LineEdit) -> void:
	field.release_focus()


## Which track main.gd should be playing, and whether it should be.
func get_music_track() -> String:
	return _music_input.text


func is_music_enabled() -> bool:
	return _music_enabled


func _on_music_toggle_pressed() -> void:
	_music_enabled = not _music_enabled
	_paint_music_toggle()
	music_enabled_set.emit(_music_enabled)


func _paint_music_toggle() -> void:
	_music_toggle.modulate = Color.WHITE if _music_enabled else MUSIC_OFF_MODULATE


func _on_music_submitted(track: String) -> void:
	_music_input.release_focus()
	music_track_set.emit(track)


## Driven every frame, so skip the theme writes unless the warning band changed.
func _set_fuel_colour(colour: Color) -> void:
	if colour == _fuel_colour:
		return
	_fuel_colour = colour
	_fuel_name.add_theme_color_override("font_color", colour)
	_fuel_value.add_theme_color_override("font_color", colour)
