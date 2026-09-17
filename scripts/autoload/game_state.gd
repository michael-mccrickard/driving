extends Node
## Autoloaded singleton holding cross-scene state and shared unit conversions.

## World scale. Every "metre" of game distance is this many pixels, which keeps
## the exported tuning values in CarStats readable as real-world-ish numbers.
const PIXELS_PER_METRE := 32.0

const SAVE_PATH := "user://save.cfg"

## One save section per level, keyed by LevelConfig.save_id.
const LEVEL_PREFIX := "level_"

## Sentinel for "no completed run on record yet". The record is a *minimum*, so
## 0.0 cannot double as the empty value the way a best distance could -- it would
## be an unbeatable score.
const NO_RECORD := -1.0

## Sentinel for "nothing saved yet" on the persisted tuning values. Both are
## meaningless at zero or below, so the same trick as NO_RECORD works.
const NO_TUNING := -1.0

signal best_fuel_used_changed(fuel: float)

## Everything below is *the active level's*. A record and the tuning it was set
## with belong to one track -- a bill run up on another says nothing about it --
## so set_level() swaps the whole working set and the rest of the game carries on
## reading it as plain state.
var level_id := ""

## Least fuel any completed run has spent, or NO_RECORD if none has finished.
var best_fuel_used := NO_RECORD

## Last session's tuning, or NO_TUNING while the values authored in the
## LevelConfig still stand. Fuel deliberately does not persist: it is run state,
## not a setting, and every run starts on a full tank by definition.
var burn_rate := NO_TUNING
var max_speed_kmh := NO_TUNING

# save_id -> the three values above, for every level ever played.
var _levels := {}
# A save written before levels existed, waiting for a level to adopt it.
var _legacy := {}
var _dirty := false


func _ready() -> void:
	load_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_CRASH:
		save_game()


## Points the record and the tuning at a level. The only place the working set
## changes wholesale, so everything else can keep reading it as plain state.
func set_level(id: String) -> void:
	if id == level_id:
		return
	_store_active()
	level_id = id
	if not _levels.has(id) and not _legacy.is_empty():
		# A save from before there were levels. There was only one track then, so
		# its record and tuning belong to whichever level comes up first.
		_levels[id] = _legacy
		_legacy = {}
		_dirty = true
	var data: Dictionary = _levels.get(id, {})
	best_fuel_used = data.get("best_fuel_used", NO_RECORD)
	burn_rate = data.get("burn_rate", NO_TUNING)
	max_speed_kmh = data.get("max_speed_kmh", NO_TUNING)
	best_fuel_used_changed.emit(best_fuel_used)


## Folds the working set back into the level it belongs to. Called before the
## active level changes and before every write, so the two never disagree.
func _store_active() -> void:
	if level_id.is_empty():
		return
	_levels[level_id] = {
		"best_fuel_used": best_fuel_used,
		"burn_rate": burn_rate,
		"max_speed_kmh": max_speed_kmh,
	}


func has_record() -> bool:
	return best_fuel_used >= 0.0


func has_tuning() -> bool:
	return burn_rate >= 0.0 and max_speed_kmh >= 0.0


## Stores the tuning runs are being driven with and, if it really changed,
## *throws the record away*, returning true in that case. The record is a fuel
## bill, and a bill only means something against runs that paid the same rates:
## winding the burn rate down would otherwise set a record no honest run could
## ever beat.
##
## Call this with the values the car ended up holding rather than the ones the
## player typed, so a clamped edit stores what actually took effect. Unchanged
## values are a no-op, which is what lets a re-push of the current tuning happen
## without costing the record that was set with it.
func report_tuning(rate: float, kmh: float) -> bool:
	if is_equal_approx(rate, burn_rate) and is_equal_approx(kmh, max_speed_kmh):
		return false
	burn_rate = rate
	max_speed_kmh = kmh
	_dirty = true
	clear_record()
	# clear_record() writes through, but only when there was a record to clear,
	# so the new tuning still needs a flush of its own.
	save_game()
	return true


## Whether a fuel bill would take the record. Split out from
## report_run_complete() so a finished run can be *shown* against the standing
## record before it is banked.
func beats_record(fuel_used: float) -> bool:
	return not has_record() or fuel_used < best_fuel_used


## Records a *finished* run's fuel bill. Only call this once the course was
## actually completed: an abandoned run always spends less than a full one, so
## scoring a partial attempt would poison the record permanently. Defers the disk
## write to save_game().
func report_run_complete(fuel_used: float) -> void:
	if not beats_record(fuel_used):
		return
	best_fuel_used = fuel_used
	_dirty = true
	best_fuel_used_changed.emit(best_fuel_used)


## Throws the stored record away, putting the HUD back to "best --". Written
## through immediately rather than left for save_game(): a record the player has
## deliberately wiped must not come back from disk on the next launch.
func clear_record() -> void:
	if not has_record():
		return
	best_fuel_used = NO_RECORD
	_dirty = true
	best_fuel_used_changed.emit(best_fuel_used)
	save_game()


func save_game() -> void:
	if not _dirty:
		return
	_store_active()
	var cfg := ConfigFile.new()
	for id: String in _levels:
		var data: Dictionary = _levels[id]
		var section := LEVEL_PREFIX + id
		cfg.set_value(section, "best_fuel_used", data.get("best_fuel_used", NO_RECORD))
		cfg.set_value(section, "burn_rate", data.get("burn_rate", NO_TUNING))
		cfg.set_value(section, "max_speed_kmh", data.get("max_speed_kmh", NO_TUNING))
	if not _legacy.is_empty():
		# No level has claimed it yet, so write it back where it was rather than
		# dropping a record on the floor.
		cfg.set_value("progress", "best_fuel_used", _legacy.get("best_fuel_used", NO_RECORD))
		cfg.set_value("tuning", "burn_rate", _legacy.get("burn_rate", NO_TUNING))
		cfg.set_value("tuning", "max_speed_kmh", _legacy.get("max_speed_kmh", NO_TUNING))
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("Could not write %s (error %d)" % [SAVE_PATH, err])
		return
	_dirty = false


func load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	_levels.clear()
	_legacy.clear()
	for section: String in cfg.get_sections():
		if not section.begins_with(LEVEL_PREFIX):
			continue
		_levels[section.trim_prefix(LEVEL_PREFIX)] = {
			"best_fuel_used": float(cfg.get_value(section, "best_fuel_used", NO_RECORD)),
			"burn_rate": float(cfg.get_value(section, "burn_rate", NO_TUNING)),
			"max_speed_kmh": float(cfg.get_value(section, "max_speed_kmh", NO_TUNING)),
		}
	if cfg.has_section("progress"):
		_legacy = {
			"best_fuel_used": float(cfg.get_value("progress", "best_fuel_used", NO_RECORD)),
			"burn_rate": float(cfg.get_value("tuning", "burn_rate", NO_TUNING)),
			"max_speed_kmh": float(cfg.get_value("tuning", "max_speed_kmh", NO_TUNING)),
		}
	# Re-read whatever level is loaded, so a reload mid-session takes effect.
	var active := level_id
	level_id = ""
	set_level(active)


static func px_to_m(pixels: float) -> float:
	return pixels / PIXELS_PER_METRE


## Pixels/second -> km/h.
static func px_per_sec_to_kmh(speed: float) -> float:
	return px_to_m(speed) * 3.6
