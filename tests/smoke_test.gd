extends Node
## Headless smoke test for the vehicle rig.
##
## Run with:
##   godot --headless res://tests/smoke_test.tscn
## Exits with code 0 when every check passes, 1 otherwise.

const MAIN := preload("res://scenes/main.tscn")

var _failures: PackedStringArray = []
var _saved_file: PackedByteArray = []


func _ready() -> void:
	# Headless runs share the player's save file, and the checks below both set
	# records and write tuning. Everything they touch is put back before quitting.
	_snapshot_save()

	var main := MAIN.instantiate()
	add_child(main)
	var car: Car = main.get_node("Car")

	await _settle(car)
	await _drive(car)
	await _climbs_terrain(main, car)
	_torque_tapers_with_speed(car)
	await _burns_fuel(main, car)
	await _burn_scales_with_speed(main, car)
	await _empty_tank_cuts_throttle(main, car)
	await _hud_fields_reach_the_car(main, car)
	await _hud_buttons_reach_the_game(main, car)
	await _play_mode_hides_the_tuning(main, car)
	await _music_follows_the_run(main, car)
	_tank_outlasts_a_run(car)
	_tuning_survives_a_save()
	_tuning_change_clears_the_record(main)
	_saved_tuning_reaches_the_car(main, car)
	await _finishing_records_the_run(main, car)
	await _tuning_change_drops_a_pending_run(main, car)
	await _quitting_banks_a_pending_run(main, car)
	await _sound_effects_follow_the_run(main, car)
	await _auto_recovers(main, car)
	await _reset(car)
	# Last: it swaps the car and the track out from under everything above.
	await _next_level_switches_everything(main)
	await _the_gaps_can_be_jumped(main)
	await _the_authored_track_is_what_was_written(main)
	_a_levelled_flat_steps_the_ground()
	await _a_long_descent_is_not_a_fall(main)

	_restore_save()
	# The audio server holds the stream for a moment after a stop, and tearing the
	# tree down before it lets go is reported as a leaked resource at exit.
	var music: MusicPlayer = main.get_node("Music")
	music.end_run()
	music.stream = null
	var sfx: SoundPlayer = main.get_node("Sfx")
	sfx.silence()
	sfx.stream = null
	await _wait(0.25)

	if _failures.is_empty():
		print("smoke test: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL  " + failure)
		quit(1)


func _settle(car: Car) -> void:
	await _wait(2.0)
	_check(car.is_grounded(), "car should be resting on the terrain after 2s")
	_check(not car.is_flipped(), "car should settle upright")
	_check(
		absf(car.chassis.rotation) < 0.6,
		"chassis should be near level, was %.2f rad" % car.chassis.rotation
	)
	_check(
		car.get_speed() < 40.0,
		"car should be nearly still before input, was %.1f px/s" % car.get_speed()
	)
	# Suspension must actually hold the chassis off the wheels' resting line.
	var ride_height := car.wheel_back.global_position.y - car.chassis.global_position.y
	_check(
		ride_height > 8.0 and ride_height < 40.0,
		"suspension ride height out of range: %.1f px" % ride_height
	)


func _drive(car: Car) -> void:
	var start_x := car.chassis.global_position.x
	Input.action_press("throttle")
	# Average the wheel spin across the run: sampling one instant catches the
	# wheel mid-bounce over rough ground and says nothing about drive direction.
	var spin_total := 0.0
	var samples := 0
	for i in int(3.0 * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
		spin_total += car.wheel_back.angular_velocity
		samples += 1
	Input.action_release("throttle")

	var travelled := car.chassis.global_position.x - start_x
	var mean_spin := spin_total / float(samples)
	_check(travelled > 200.0, "throttle should drive the car forward, moved %.1f px" % travelled)
	_check(mean_spin > 1.0, "driven wheel should average forward spin, was %.2f rad/s" % mean_spin)

	# Coast so the reset check starts from a known state.
	await _wait(1.0)


## The car must have enough torque to actually get up the generated hills --
## the first tuning pass had it stall permanently a few metres in.
func _climbs_terrain(main: Node2D, car: Car) -> void:
	main._restart_run()
	await _wait(0.5)
	var start_x := car.chassis.global_position.x
	Input.action_press("throttle")
	await _wait(20.0)
	Input.action_release("throttle")
	var metres := GameState.px_to_m(car.chassis.global_position.x - start_x)
	_check(metres > 150.0, "20s of throttle should cover the hills, went %.1f m" % metres)


## Fuel is the score, so the burn rate has to track held throttle and nothing
## else -- coasting in particular must be free.
func _burns_fuel(main: Node2D, car: Car) -> void:
	main._restart_run()
	await _wait(0.5)
	_check(
		is_equal_approx(car.get_fuel(), car.get_fuel_capacity()),
		"restarting a run should refill the tank, was %.2f" % car.get_fuel()
	)

	Input.action_press("throttle")
	await _wait(2.0)
	Input.action_release("throttle")

	# Pulling away from rest, the multiplier climbs from 1.0 towards its ceiling,
	# so the spend has to land between the base rate and the flat-out rate.
	var used := car.get_fuel_used()
	var base := 2.0 * 1000.0 * car.stats.fuel_per_millisecond
	var ceiling := base * (1.0 + car.stats.burn_speed_penalty)
	_check(
		used > base,
		"accelerating should cost more than the base rate: %.2f vs %.2f" % [used, base]
	)
	_check(
		used < ceiling,
		"2s of throttle should stay under the flat-out rate: %.2f vs %.2f" % [used, ceiling]
	)

	await _wait(1.0)
	_check(
		is_equal_approx(car.get_fuel_used(), used),
		"coasting must be free, but spend went %.2f -> %.2f" % [used, car.get_fuel_used()]
	)


## Torque has to fall away near the spin cap. Without the taper the car runs at
## full torque right up to the cut-off and hits top speed like a wall.
func _torque_tapers_with_speed(car: Car) -> void:
	_check(car.stats.torque_curve != null, "default_car.tres should ship a torque curve")
	var off_the_line := car.get_torque_scale(0.0)
	var mid := car.get_torque_scale(0.5)
	var at_cap := car.get_torque_scale(1.0)
	_check(off_the_line > 0.9, "torque should be near full off the line, was %.2f" % off_the_line)
	_check(at_cap < 0.1, "torque should be spent at the cap, was %.2f" % at_cap)
	_check(mid > at_cap, "torque should fall with speed: %.2f at half, %.2f at the cap" % [mid, at_cap])


## Speed is what makes a run expensive, so the same throttle input has to cost
## more the faster the car is already going.
func _burn_scales_with_speed(main: Node2D, car: Car) -> void:
	main._restart_run()
	await _wait(1.0)
	var at_rest := car.get_burn_multiplier()
	_check(
		is_equal_approx(at_rest, 1.0),
		"a stationary car should burn at the base rate, multiplier was %.2f" % at_rest
	)

	# Shove the whole rig along rather than waiting to build speed over the hills,
	# which would depend on the terrain seed. The springs and the ground bleed
	# some of it straight back off, so never assume the speed that was asked for:
	# measure what the car actually has and score against that.
	var fast := await _burn_at(car, car.stats.burn_reference_kmh)
	var slow := await _burn_at(car, car.stats.burn_reference_kmh / 4.0)
	_check(fast.x > slow.x * 1.3, "test setup: needed two clearly different speeds, got %.0f and %.0f km/h" % [fast.x, slow.x])
	_check(
		fast.y > at_rest,
		"speed should raise the burn rate: %.2f at rest, %.2f at %.0f km/h" % [at_rest, fast.y, fast.x]
	)

	var expected: float = 1.0 + car.stats.burn_speed_penalty * pow(
		fast.x / car.stats.burn_reference_kmh, car.stats.burn_speed_exponent)
	_check(
		absf(fast.y - expected) < 0.01,
		"burn multiplier at %.0f km/h should be %.2f, was %.2f" % [fast.x, expected, fast.y]
	)

	# The whole point of the exponent: cost has to climb faster than speed does,
	# or crawling is never worth it and flat out is always the cheapest line.
	var speed_ratio := fast.x / slow.x
	var cost_ratio := (fast.y - 1.0) / maxf(slow.y - 1.0, 0.0001)
	_check(
		cost_ratio > speed_ratio * 1.05,
		"cost must rise faster than speed: %.1fx the speed for only %.1fx the penalty" % [speed_ratio, cost_ratio]
	)


## Drives the whole rig to roughly the given speed and returns the speed it
## really reached alongside the burn multiplier there, as (km/h, multiplier).
func _burn_at(car: Car, kmh: float) -> Vector2:
	var velocity := Vector2(kmh / 3.6 * GameState.PIXELS_PER_METRE, 0.0)
	for body in [car.chassis, car.wheel_back, car.wheel_front]:
		body.linear_velocity = velocity
	await get_tree().physics_frame
	return Vector2(car.get_speed_kmh(), car.get_burn_multiplier())


## The tuning fields are only worth having if editing one really moves the value
## it names, so drive the real SpinBoxes and watch the car change.
func _hud_fields_reach_the_car(main: Node2D, car: Car) -> void:
	var hud: Hud = main.get_node("Hud")
	var burn_rate: float = car.get_burn_rate()
	var top_speed: float = car.get_max_speed_kmh()

	# Setting .value emits value_changed, which is the same path a typed edit
	# takes, so this exercises the HUD signal and main.gd's wiring too.
	hud.get_node("%BurnRateInput").value = 0.004
	_check(
		is_equal_approx(car.get_burn_rate(), 0.004),
		"burn rate field should reach the car, car has %.4f" % car.get_burn_rate()
	)

	hud.get_node("%MaxSpeedInput").value = 40.0
	_check(
		absf(car.get_max_speed_kmh() - 40.0) < 0.5,
		"max speed field should reach the car, car has %.1f km/h" % car.get_max_speed_kmh()
	)
	# 40 km/h over a 16 px wheel: 40 / 3.6 * 32 px/s, divided by the radius.
	var expected_spin := 40.0 / 3.6 * GameState.PIXELS_PER_METRE / 16.0
	_check(
		absf(car.stats.max_wheel_speed - expected_spin) < 0.1,
		"max speed should convert to %.2f rad/s, stats hold %.2f" % [expected_spin, car.stats.max_wheel_speed]
	)

	car.set_burn_rate(burn_rate)
	car.set_max_speed_kmh(top_speed)
	await _wait(0.1)


## The two buttons are the mouse route to a restart and to wiping the record, so
## press the real Buttons and watch the game state move.
func _hud_buttons_reach_the_game(main: Node2D, car: Car) -> void:
	var hud: Hud = main.get_node("Hud")

	main._restart_run()
	await _wait(0.5)
	var spawn_x: float = main._spawn_point.x
	Input.action_press("throttle")
	await _wait(2.0)
	Input.action_release("throttle")
	_check(car.get_fuel_used() > 0.0, "test setup: the car should have spent fuel by now")
	_check(
		absf(car.chassis.global_position.x - spawn_x) > 80.0,
		"test setup: the car should have left the spawn point"
	)

	hud.get_node("%RestartButton").pressed.emit()
	await _wait(0.1)
	_check(
		is_equal_approx(car.get_fuel(), car.get_fuel_capacity()),
		"the restart button should refill the tank, car has %.2f" % car.get_fuel()
	)
	_check(
		absf(car.chassis.global_position.x - spawn_x) < 80.0,
		"the restart button should put the car back on the start line"
	)

	var clear_button: Button = hud.get_node("%ClearRecordButton")
	_stub_record(42.0)
	_check(not clear_button.disabled, "the reset button should be live once a record exists")
	clear_button.pressed.emit()
	_check(
		not GameState.has_record(),
		"the reset button should clear the record, it is %.2f" % GameState.best_fuel_used
	)
	_check(clear_button.disabled, "the reset button should grey out with no record to clear")


## Play mode is what a player sees: no knobs that could cheat the record. The
## fuel readout is the bill either way, so it has to survive the switch intact.
func _play_mode_hides_the_tuning(main: Node2D, car: Car) -> void:
	var hud: Hud = main.get_node("Hud")
	var fuel_name: Label = hud.get_node("%FuelName")
	var fuel_value: Label = hud.get_node("%FuelValue")
	_check(hud.mode == Hud.Mode.AUTHOR, "the HUD should start in Author mode")

	main._restart_run()
	Input.action_press("throttle")
	await _wait(2.0)
	Input.action_release("throttle")
	var used := car.get_fuel_used()
	_check(used > 0.0, "test setup: the car should have spent fuel")
	await _wait(0.1)
	_check(fuel_value.visible, "Author should show the fuel bill")
	_check(
		absf(float(fuel_value.text) - used) < 1.0,
		"Author should read out fuel spent, label says '%s' of %.1f" % [fuel_value.text, used]
	)
	# The tank cannot run dry, so the warning it carries stays out of the way.
	_check(not fuel_name.visible, "the OUT OF FUEL warning should be hidden on a full tank")
	for control: Control in [
		hud.get_node("%BurnRateInput"), hud.get_node("%MaxSpeedInput"),
		hud.get_node("%MusicInput"), hud.get_node("%ClearRecordButton"),
	]:
		_check(control.visible, "Author should show every control, %s is hidden" % control.name)
	_check(not hud.get_node("%MusicToggle").visible, "Author should not show the music switch")

	hud.toggle_mode()
	await _wait(0.1)
	_check(hud.mode == Hud.Mode.PLAY, "the toggle should reach Play mode")
	_check(fuel_value.visible, "Play should keep the fuel bill on screen")
	_check(
		absf(float(fuel_value.text) - used) < 1.0,
		"Play should read out fuel spent, label says '%s' of %.1f" % [fuel_value.text, used]
	)
	for control: Control in [
		hud.get_node("%BurnRateName"), hud.get_node("%BurnRateInput"),
		hud.get_node("%MaxSpeedName"), hud.get_node("%MaxSpeedInput"),
		hud.get_node("%MusicName"), hud.get_node("%MusicInput"),
		# Only an author gets to throw the record away.
		hud.get_node("%ClearRecordButton"),
	]:
		_check(not control.visible, "Play should hide %s" % control.name)
	# Restart stays: a run is only banked by restarting.
	_check(hud.get_node("%RestartButton").visible, "Play should keep the Restart button")
	_check(hud.get_node("%MusicToggle").visible, "Play should show the music switch")

	hud.toggle_mode()
	await _wait(0.1)
	_check(hud.mode == Hud.Mode.AUTHOR, "the toggle should come back to Author mode")
	_check(hud.get_node("%MaxSpeedInput").visible, "Author should show the tuning controls again")
	_check(fuel_value.visible, "Author should still show the fuel bill")


## Music runs for the length of a run and stops when the run does, and both HUD
## controls that name or silence it have to reach the player.
func _music_follows_the_run(main: Node2D, car: Car) -> void:
	var hud: Hud = main.get_node("Hud")
	var music: MusicPlayer = main.get_node("Music")
	var toggle: Button = hud.get_node("%MusicToggle")
	var track: String = hud.get_music_track()

	main._restart_run()
	await _wait(0.2)
	_check(music.playing, "music should be playing from the start of a run")
	_check(
		music.stream != null and music.stream.get("loop"),
		"the track should be set to loop, a run has no fixed length"
	)

	# The switch is the whole of the Play-mode music UI. It is a plain Button, so
	# each press flips the state the HUD is keeping for it.
	_check(hud.is_music_enabled(), "the music switch should start out on")
	toggle.pressed.emit()
	_check(not hud.is_music_enabled(), "a press should switch the music off")
	_check(not music.playing, "the music switch should stop the track")
	toggle.pressed.emit()
	_check(hud.is_music_enabled(), "a second press should switch it back on")
	_check(music.playing, "the music switch should start it again")

	main._finish_run()
	_check(not music.playing, "finishing a run should stop the music")
	main._restart_run()
	await _wait(0.2)
	_check(music.playing, "restarting should start the track over")

	# A typo in the field must not take the game down with it.
	music.set_track("no-such-track.mp3")
	_check(not music.playing, "a missing track should just leave the game silent")
	music.set_track(track)
	_check(music.playing, "naming a real track again should bring it back")


## The tank is deliberately far bigger than any run could burn, so that running
## dry never decides whether a run finishes.
func _tank_outlasts_a_run(car: Car) -> void:
	_check(
		car.get_fuel_capacity() >= 10000.0,
		"the tank should be effectively bottomless, was %.0f" % car.get_fuel_capacity()
	)


## The two settings that persist have to make the round trip through the config
## file, or last session's tuning silently reverts to whatever CarStats holds.
func _tuning_survives_a_save() -> void:
	GameState.report_tuning(0.0031, 55.0)
	GameState.save_game()
	GameState.burn_rate = GameState.NO_TUNING
	GameState.max_speed_kmh = GameState.NO_TUNING

	GameState.load_game()
	_check(GameState.has_tuning(), "saved tuning should load back")
	_check(
		is_equal_approx(GameState.burn_rate, 0.0031),
		"burn rate should survive a save/load, came back %.4f" % GameState.burn_rate
	)
	_check(
		is_equal_approx(GameState.max_speed_kmh, 55.0),
		"top speed should survive a save/load, came back %.1f" % GameState.max_speed_kmh
	)


## A record is a fuel bill, so it only means anything at the tuning it was set
## with: editing either persisted field has to throw it away.
func _tuning_change_clears_the_record(main: Node2D) -> void:
	var hud: Hud = main.get_node("Hud")

	_stub_record(20.0)
	hud.get_node("%BurnRateInput").value = 0.0021
	_check(
		not GameState.has_record(),
		"changing the burn rate should clear the record, it is %.2f" % GameState.best_fuel_used
	)
	_check(
		is_equal_approx(GameState.burn_rate, 0.0021),
		"the new burn rate should be stored, GameState holds %.4f" % GameState.burn_rate
	)

	_stub_record(20.0)
	hud.get_node("%MaxSpeedInput").value = 64.0
	_check(
		not GameState.has_record(),
		"changing the top speed should clear the record, it is %.2f" % GameState.best_fuel_used
	)
	_check(
		absf(GameState.max_speed_kmh - 64.0) < 0.5,
		"the new top speed should be stored, GameState holds %.1f" % GameState.max_speed_kmh
	)

	# Re-reporting the tuning already in force is not a change, and must not cost
	# the record. This is what makes the startup restore below safe.
	_stub_record(20.0)
	main._store_tuning()
	_check(GameState.has_record(), "re-reporting unchanged tuning must not clear the record")


## What a fresh launch does. The stored values have to reach the car, and doing
## so must not count as changing them -- otherwise the record would never
## survive the launch after the one that set it.
func _saved_tuning_reaches_the_car(main: Node2D, car: Car) -> void:
	_stub_record(20.0)
	GameState.burn_rate = 0.0026
	GameState.max_speed_kmh = 72.0

	main._apply_saved_tuning()
	_check(
		is_equal_approx(car.get_burn_rate(), 0.0026),
		"saved burn rate should reach the car, car has %.4f" % car.get_burn_rate()
	)
	_check(
		absf(car.get_max_speed_kmh() - 72.0) < 0.5,
		"saved top speed should reach the car, car has %.1f km/h" % car.get_max_speed_kmh()
	)
	_check(GameState.has_record(), "restoring saved tuning must not clear the record")


## Plants a record to be knocked down, whatever the previous check left behind.
func _stub_record(fuel: float) -> void:
	GameState.best_fuel_used = GameState.NO_RECORD
	GameState.report_run_complete(fuel)


## An empty tank must actually cut the engine, or the fuel budget means nothing.
func _empty_tank_cuts_throttle(main: Node2D, car: Car) -> void:
	var recover: float = main.auto_recover_seconds
	# Stall recovery exists precisely to rescue an empty tank, which would refill
	# it out from under this check.
	main.auto_recover_seconds = 0.0
	main._restart_run()
	await _wait(1.0)

	# Drained on the flat spawn pad, so anything but a few px of drift is drive.
	car.set_fuel(0.0)
	var start_x := car.chassis.global_position.x
	Input.action_press("throttle")
	await _wait(3.0)
	Input.action_release("throttle")

	var moved := absf(car.chassis.global_position.x - start_x)
	_check(moved < 40.0, "throttle on an empty tank should not drive, moved %.1f px" % moved)
	_check(is_zero_approx(car.get_fuel()), "an empty tank should not go negative")

	main.auto_recover_seconds = recover


## Only getting the car past the finish line records a score, and even then not
## until the player restarts. A partial run always spends less fuel than a full one, so
## the first half of this is what keeps the record from being poisoned by an
## abandoned attempt; the second is the pause that lets the bill be read against
## the record it is about to replace.
func _finishing_records_the_run(main: Node2D, car: Car) -> void:
	var recover: float = main.auto_recover_seconds
	main.auto_recover_seconds = 0.0
	# Start from a clean slate so a stored record cannot beat the score under test.
	GameState.best_fuel_used = GameState.NO_RECORD

	main._restart_run()
	await _wait(0.5)
	Input.action_press("throttle")
	await _wait(1.0)
	Input.action_release("throttle")
	_check(
		not GameState.has_record(),
		"an unfinished run must not be recorded, record is %.2f" % GameState.best_fuel_used
	)

	# Driving the whole 750 m track would cost ~100s of headless physics, so put
	# the car straight down on the run-out instead.
	var spent := 12.5
	var hud: Hud = main.get_node("Hud")
	var terrain: TerrainBase = main.get_node("Level/Terrain")
	await _finish_past_the_line(main, car, spent)
	_check(main.has_pending_run(), "crossing the line should finish the run")
	_check(
		not GameState.has_record(),
		"finishing must not bank the bill on its own, record is %.2f" % GameState.best_fuel_used
	)
	# This run takes the record, so its stats are held back for the applause while
	# the flag goes up at once.
	var finish: Sprite2D = main.get_node("Level/Finish")
	_check(
		finish.texture == main.NEW_RECORD_FLAG,
		"a record should run the record flag up the finish post at the line"
	)
	_check(
		not hud.get_node("%ResultPanel").visible,
		"a record's stats should wait for the applause rather than land on the line"
	)
	await _wait(main.RECORD_RESULT_DELAY + 0.5)
	_check(hud.get_node("%ResultPanel").visible, "the finished bill should be on screen")

	# The wall is what keeps a finished run in the world, so drive at it: the car
	# has to still be on the track afterwards, and never parked, since parking is
	# now only what happens to something that has fallen out of the world.
	Input.action_press("throttle")
	await _wait(4.0)
	Input.action_release("throttle")
	_check(
		car.chassis.global_position.x < terrain.end_x(),
		"the end wall should keep a finished run on the course, car is at %.0f of %.0f" % [
			car.chassis.global_position.x, terrain.end_x()]
	)
	_check(not car.is_held(), "a run stopped by the wall is still in the world, not parked")

	# Hitting the wall is free because the bill was settled at the line: the car
	# goes on spending, and none of it reaches the score.
	_check(
		car.get_fuel_used() > spent,
		"test setup: the car should still be burning past the line, spent %.2f" % car.get_fuel_used()
	)
	_check(
		absf(main._pending_fuel_used - spent) < 0.01,
		"the bill is settled at the line, but it reads %.2f against %.2f" % [
			main._pending_fuel_used, spent]
	)

	main._restart_run()
	await _wait(0.5)
	_check(
		absf(GameState.best_fuel_used - spent) < 1.0,
		"restarting should bank %.1f fuel, record is %.2f" % [spent, GameState.best_fuel_used]
	)
	_check(not main.has_pending_run(), "the banked run should no longer be pending")
	_check(not hud.get_node("%ResultPanel").visible, "restarting should clear the bill")
	_check(
		finish.texture != main.NEW_RECORD_FLAG,
		"restarting should put the level's own flag back on the finish post"
	)
	_check(
		absf(car.chassis.global_position.x - main._spawn_point.x) < 80.0,
		"restarting should put the car back on the start line"
	)

	# Releasing the parked rig matters as much as parking it: a car that stays
	# frozen after the restart cannot be driven at all.
	_check(not car.is_held(), "restarting should release the parked car")
	var start_x := car.chassis.global_position.x
	Input.action_press("throttle")
	await _wait(2.0)
	Input.action_release("throttle")
	_check(
		car.chassis.global_position.x - start_x > 100.0,
		"the car should drive again after a parked run, moved %.1f px" % (car.chassis.global_position.x - start_x)
	)

	main.auto_recover_seconds = recover


## A bill run up at the old tuning is no more comparable than the record the
## change just cleared, so a pending run has to go with it.
func _tuning_change_drops_a_pending_run(main: Node2D, car: Car) -> void:
	var recover: float = main.auto_recover_seconds
	main.auto_recover_seconds = 0.0
	GameState.best_fuel_used = GameState.NO_RECORD

	main._restart_run()
	await _wait(0.5)
	await _finish_past_the_line(main, car, 5.0)
	_check(main.has_pending_run(), "test setup: the run should be finished and pending")

	main.get_node("Hud").get_node("%BurnRateInput").value = 0.0043
	_check(not main.has_pending_run(), "changing the tuning should drop the pending run")

	main._restart_run()
	await _wait(0.1)
	_check(
		not GameState.has_record(),
		"a dropped run must not be banked, record is %.2f" % GameState.best_fuel_used
	)

	main.auto_recover_seconds = recover


## Restarting and NEXT are not the only ways out of a run -- closing the window
## is one too, and a bill still parked on screen when it happens has been earned.
## Notified from the root so the autoload and main.gd get it in the same order
## the engine would send it.
func _quitting_banks_a_pending_run(main: Node2D, car: Car) -> void:
	var recover: float = main.auto_recover_seconds
	main.auto_recover_seconds = 0.0
	GameState.best_fuel_used = GameState.NO_RECORD

	main._restart_run()
	await _wait(0.5)
	var spent := 7.5
	await _finish_past_the_line(main, car, spent)
	_check(main.has_pending_run(), "test setup: the run should be finished and pending")

	get_tree().get_root().propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	_check(not main.has_pending_run(), "quitting should settle the pending run")
	_check(
		absf(GameState.best_fuel_used - spent) < 1.0,
		"quitting should bank %.1f fuel, record is %.2f" % [spent, GameState.best_fuel_used]
	)

	# The whole point of banking on the way out is that it outlives the shutdown,
	# so check the disk rather than just the singleton.
	GameState.best_fuel_used = GameState.NO_RECORD
	GameState.load_game()
	_check(
		absf(GameState.best_fuel_used - spent) < 1.0,
		"a run banked on quit should load back, came back %.2f" % GameState.best_fuel_used
	)

	main.auto_recover_seconds = recover


## Puts the car down on the run-out past the finish line and bills it `spent`
## fuel, so main.gd calls the run finished on the next frame. Driving the whole
## track for every one of these would cost minutes of headless physics, and what
## they are about is what a finished run does, not how it got there.
func _finish_past_the_line(main: Node2D, car: Car, spent: float, settle := 0.5) -> void:
	var terrain: TerrainBase = main.get_node("Level/Terrain")
	car.reset_to(terrain.surface_point_at(main._finish_x + 200.0) + Vector2(0.0, -80.0))
	# reset_to() refills the tank, so bill the run after the drop, not before.
	car.set_fuel(car.get_fuel_capacity() - spent)
	await _wait(settle)


## Every way a run can end makes a noise, and for two of them the noise is the
## only feedback there is. They also have to sound *over* the music rather than
## instead of it, which is the whole reason they have a player of their own.
func _sound_effects_follow_the_run(main: Node2D, car: Car) -> void:
	var recover: float = main.auto_recover_seconds
	main.auto_recover_seconds = 0.0
	var sfx: SoundPlayer = main.get_node("Sfx")
	var music: MusicPlayer = main.get_node("Music")

	main._restart_run()
	await _wait(0.5)
	_check(sfx.clip.is_empty(), "a fresh run should start silent, playing '%s'" % sfx.clip)

	# Nothing on record, so this run takes it, and the applause is what should be
	# waiting behind the fanfare.
	GameState.best_fuel_used = GameState.NO_RECORD
	await _finish_past_the_line(main, car, 6.0, 0.15)
	_check(
		sfx.clip.begins_with(main.SUCCESS_SOUNDS + "/"),
		"crossing the line should play a success clip, played '%s'" % sfx.clip
	)
	_check(
		sfx._queue.size() == 1 and sfx._queue[0][0] == main.APPLAUSE_SOUND,
		"a record should put the applause behind the fanfare, queued %s" % [sfx._queue]
	)
	# Driven by hand rather than by waiting the clip out: what is under test is
	# the hand-off, not how long a fanfare happens to be.
	sfx._advance()
	_check(
		sfx.clip == main.APPLAUSE_SOUND and sfx._queue.is_empty(),
		"the applause should follow the fanfare, playing '%s'" % sfx.clip
	)

	# The wall is the one sound that lands while the run is still making others.
	Input.action_press("throttle")
	var ticks := 0
	while not main._wall_hit and ticks < 8 * Engine.physics_ticks_per_second:
		await get_tree().physics_frame
		ticks += 1
	Input.action_release("throttle")
	_check(main._wall_hit, "the car should have driven into the end wall by now")
	_check(
		sfx.clip == main.IMPACT_SOUND,
		"hitting the wall should thud, playing '%s'" % sfx.clip
	)

	# A run that does not take the record gets the bed instead, which holds --
	# and a thud over it has to put it back rather than leave the score in
	# silence.
	main._restart_run()
	_stub_record(0.5)
	await _finish_past_the_line(main, car, 6.0, 0.15)
	_check(
		sfx._queue.size() == 1 and sfx._queue[0][0] == main.WAITING_SOUND,
		"a run that misses the record should queue the bed, queued %s" % [sfx._queue]
	)
	sfx._advance()
	_check(
		sfx.clip == main.WAITING_SOUND and sfx._looping,
		"the bed should hold under the score, playing '%s'" % sfx.clip
	)
	sfx.interject(main.IMPACT_SOUND)
	_check(sfx.clip == main.IMPACT_SOUND, "a thud should cut in over the bed")
	_check(
		sfx._queue.size() == 1 and sfx._queue[0][0] == main.WAITING_SOUND,
		"the bed should be put back after the thud, queued %s" % [sfx._queue]
	)

	# Falling out of the world is a run lost, and losing one is not the same as
	# asking for another go: it says so, over the music the restart brings back.
	main._restart_run()
	await _wait(0.5)
	_check(sfx.clip.is_empty(), "restarting should lift the bed, playing '%s'" % sfx.clip)
	car.reset_to(Vector2(
		main._spawn_point.x, main.fall_limit_y() + 5.0 * GameState.PIXELS_PER_METRE
	))
	await _wait(0.2)
	_check(
		sfx.clip.begins_with(main.FAIL_SOUNDS + "/"),
		"falling out of the world should play a fail clip, played '%s'" % sfx.clip
	)
	_check(music.playing, "a sound effect must sound over the music, not instead of it")
	_check(
		absf(car.chassis.global_position.x - main._spawn_point.x) < 80.0,
		"a lost run should be back on the start line"
	)

	# Asking for a restart is not a failure, and must not be reported as one.
	main._restart_run()
	await _wait(0.1)
	_check(sfx.clip.is_empty(), "a restart by hand should be silent, playing '%s'" % sfx.clip)

	main.auto_recover_seconds = recover


## Upside down and stationary is otherwise unrecoverable, so main.gd restarts
## the run for the player.
func _auto_recovers(main: Node2D, car: Car) -> void:
	main._restart_run()
	await _wait(0.5)
	var spawn_x := car.chassis.global_position.x
	# Drop the car in on its roof.
	car.reset_to(car.chassis.global_position + Vector2(0, -100.0))
	car.chassis.rotation = PI
	await _wait(1.0)
	_check(car.is_flipped(), "test setup: car should be upside down")
	await _wait(main.auto_recover_seconds + 2.0)
	_check(not car.is_flipped(), "car should auto-recover from resting upside down")
	_check(
		absf(car.chassis.global_position.x - spawn_x) < 80.0,
		"auto-recovery should return the car to the spawn point"
	)


func _reset(car: Car) -> void:
	var before := car.chassis.global_position
	car.reset_to(Vector2(before.x + 500.0, before.y - 300.0))
	await _wait(0.1)
	_check(
		car.chassis.global_position.distance_to(Vector2(before.x + 500.0, before.y - 300.0)) < 60.0,
		"reset_to should teleport the chassis to the target"
	)
	var wheel_gap := car.wheel_front.global_position.distance_to(car.wheel_back.global_position)
	_check(
		absf(wheel_gap - 68.0) < 12.0,
		"wheels should keep their spacing through a reset, gap was %.1f px" % wheel_gap
	)


## Snapshots the save file itself rather than the values in it, so the checks
## below cannot leave the player's records in a shape that depends on what the
## save format happened to look like when they were written.
## Each level carries its own track, car settings, music and record, and NEXT is
## the way between them.
func _next_level_switches_everything(main: Node2D) -> void:
	var hud: Hud = main.get_node("Hud")
	_check(main.levels.size() >= 2, "there should be more than one level to walk")
	var first: LevelConfig = main.levels[0]
	var second: LevelConfig = main.levels[1]
	_check(first.save_id != second.save_id, "levels must not share a save id")

	var first_car: Car = main.get_node("Car")
	var first_finish: float = main._finish_x
	# Blank slate: whatever the player has already set on these levels is none of
	# this check's business, and _restore_save() puts the real thing back.
	GameState._levels.clear()
	GameState._legacy.clear()
	GameState.best_fuel_used = GameState.NO_RECORD
	GameState.report_run_complete(11.0)

	hud.get_node("%NextButton").pressed.emit()
	await _wait(0.5)
	var car: Car = main.get_node("Car")
	_check(GameState.level_id == second.save_id, "NEXT should make the next level active")
	_check(
		hud.get_node("%LevelLabel").text == second.display_name,
		"the HUD should name the level whose record it is showing"
	)
	_check(not GameState.has_record(), "an unplayed level should start with no record")
	_check(
		absf(main._finish_x - first_finish) > 1.0,
		"the second level should be a different track, both finish at %.0f" % first_finish
	)
	_check(car != first_car and not is_instance_valid(first_car), "the old car should be gone")
	_check(
		is_equal_approx(car.get_burn_rate(), second.burn_rate)
		and absf(car.get_max_speed_kmh() - second.max_speed_kmh) < 0.5
		and is_equal_approx(car.get_fuel_capacity(), second.fuel_capacity),
		"the level's own car settings should be applied"
	)
	_check(
		hud.get_node("%MusicInput").text == second.music,
		"the level should name its own music track"
	)

	# The track has to be drivable, not just generated.
	var start_x := car.chassis.global_position.x
	Input.action_press("throttle")
	await _wait(8.0)
	Input.action_release("throttle")
	var metres := GameState.px_to_m(car.chassis.global_position.x - start_x)
	_check(metres > 50.0, "the second level should be drivable, went %.1f m in 8s" % metres)

	GameState.report_run_complete(3.0)
	# The rest of the way round, however many levels that is.
	for i in main.levels.size() - 1:
		hud.get_node("%NextButton").pressed.emit()
		await _wait(0.3)
	_check(GameState.level_id == first.save_id, "NEXT should wrap round to the first level")
	_check(
		absf(GameState.best_fuel_used - 11.0) < 0.01,
		"coming back should bring the first level's record with it, got %.2f" % GameState.best_fuel_used
	)

	# Both records have to reach the disk, under their own level.
	GameState._dirty = true
	GameState.save_game()
	GameState.load_game()
	_check(
		absf(GameState.best_fuel_used - 11.0) < 0.01,
		"the active level's record should survive a reload, got %.2f" % GameState.best_fuel_used
	)
	main.load_level(1)
	_check(
		absf(GameState.best_fuel_used - 3.0) < 0.01,
		"the other level's record should survive too, got %.2f" % GameState.best_fuel_used
	)
	main.load_level(0)


## A break in the ground is only a jump if the car can get over it at speed --
## and only a break if there is really nothing there. Both are properties of the
## terrain and the car together, so the only honest check is to drive it.
func _the_gaps_can_be_jumped(main: Node2D) -> void:
	var index := -1
	for i in main.levels.size():
		# Instanced only to read the terrain's exports, so it never enters the tree.
		var probe: Node = main.levels[i].track.instantiate()
		var has_gaps: bool = not (probe.get_node("Terrain") as TerrainBase).gaps.is_empty()
		probe.free()
		if has_gaps:
			index = i
			break
	_check(index >= 0, "one level should have gaps in it")
	if index < 0:
		return

	main.load_level(index)
	await _wait(0.5)
	var car: Car = main.get_node("Car")
	var terrain: TerrainBase = main.get_node("Level/Terrain")

	# One more piece of ground than there are breaks between them, plus the end
	# wall, which is a shape on the same body.
	var shapes := 0
	for child in terrain.get_children(true):
		if child is CollisionPolygon2D:
			shapes += 1
	var expected: int = terrain.gaps.size() + 1 + (1 if terrain.wall_height > 0.0 else 0)
	_check(
		shapes == expected,
		"%d gaps should leave %d collision shapes, found %d" % [
			terrain.gaps.size(), expected, shapes]
	)

	for gap in terrain.gaps:
		_check(_has_ground(main, terrain, gap.x + gap.y * 0.5) == false, "a gap should be empty")
		_check(_has_ground(main, terrain, gap.x - 60.0), "there should be ground to launch from")
		_check(_has_ground(main, terrain, gap.x + gap.y + 60.0), "there should be ground to land on")

	# The ramps are sized for a car that commits: pinned throttle gets across.
	Input.action_press("throttle")
	var ticks := 0
	var limit := 90 * Engine.physics_ticks_per_second
	while not main.has_pending_run() and ticks < limit:
		await get_tree().physics_frame
		ticks += 1
	Input.action_release("throttle")
	_check(
		main.has_pending_run(),
		"a pinned throttle should clear the breaks and finish, stopped at %.0f of %.0f px" % [
			car.chassis.global_position.x, main._finish_x]
	)

	main.load_level(0)


## An authored track is a promise: the shapes say where the ground goes, and the
## ground has to go there. Length, net height and steepness are all things the
## shape list states outright, so they can be checked against it rather than
## against a number pasted in here -- edit Denver's shapes and this still holds.
##
## The interesting one is the height. Joins are rounded by corner_blend, and the
## rounding is symmetrical about the join, so the rise it borrows from the shape
## before is exactly the rise it gives back to the shape after: a blended track
## has to finish at the same height as an unblended one. That is what the second
## check is really testing.
func _the_authored_track_is_what_was_written(main: Node2D) -> void:
	var index := -1
	for i in main.levels.size():
		# Instanced only to read the terrain's exports, so it never enters the tree.
		var probe: Node = main.levels[i].track.instantiate()
		var authored: bool = probe.get_node("Terrain") is TerrainAuthor
		probe.free()
		if authored:
			index = i
			break
	_check(index >= 0, "one level should be an authored track")
	if index < 0:
		return

	main.load_level(index)
	await _wait(0.5)
	var car: Car = main.get_node("Car")
	var terrain: TerrainAuthor = main.get_node("Level/Terrain")
	var shapes := terrain.shape_list()
	_check(not shapes.is_empty(), "an authored track should have shapes in it")
	# Steepness is advisory: Denver deliberately steps a staircase of descents past
	# the angle the car is good for, and the node says so about each one. What a
	# shipped track must not have on it is the warnings that mean a mistake -- a
	# line that would not parse, a kind that is not one of the five, a shape too
	# short to exist.
	var faults := PackedStringArray()
	for warning in terrain._get_configuration_warnings():
		if not warning.contains("may not be drivable"):
			faults.append(warning)
	_check(
		faults.is_empty(),
		"an authored track should ship with nothing wrong with it: %s" % ", ".join(faults)
	)

	# What the shape list adds up to, worked out from the list itself: lengths
	# rounded up to whole segments, rise as run * tan(steepness), bracketed by
	# the spawn pad and the run-out.
	var expected_segments: int = terrain.flat_start_segments
	var expected_height := 0.0
	var steepest := 0.0
	# Segments that are the step into a stepped flat rather than a face any shape
	# asked for. A riser is a discontinuity on purpose, so the steepness and the
	# kink below step over it rather than reporting it as a fault.
	var risers := PackedInt32Array()
	# The segment either side of a gap, where the slope changes at a lip rather
	# than over a rounded join. The faces themselves are still checked; it is only
	# the kink at the lip that is allowed to be a corner.
	var lips := PackedInt32Array()
	for shape in shapes:
		var kind := int(roundf(shape.x))
		# A gap takes at least two segments, because what it cuts away is the ground
		# between its lips; everything else takes at least one.
		var least: int = 2 if kind == TerrainAuthor.Shape.GAP else 1
		var segments: int = maxi(least, ceili(maxf(shape.y, 0.0) / terrain.segment_width))
		var run: float = float(segments) * terrain.segment_width
		var steepness: float = shape.z if shape.z > 0.0 else terrain.default_steepness
		match kind:
			TerrainAuthor.Shape.SLOPE_UP:
				expected_height += run * tan(deg_to_rad(steepness))
				steepest = maxf(steepest, steepness)
			TerrainAuthor.Shape.SLOPE_DOWN:
				expected_height -= run * tan(deg_to_rad(steepness))
				steepest = maxf(steepest, steepness)
			TerrainAuthor.Shape.FLAT_STEP:
				# A stepped flat jumps by the rise it names, whatever the shape before
				# it was doing, and the segment before the join is the riser.
				expected_height += shape.z
				if not is_zero_approx(shape.z):
					risers.append(expected_segments - 1)
			TerrainAuthor.Shape.GAP:
				# Level ground at the height the list is already at, with the ground
				# over it taken away. The profile under it is what is sampled here.
				lips.append(expected_segments - 1)
				lips.append(expected_segments + segments - 1)
		expected_segments += segments
	expected_segments += terrain.flat_end_segments

	var origin_x: float = terrain.to_global(Vector2.ZERO).x
	_check(
		is_equal_approx(terrain.end_x() - origin_x, float(expected_segments) * terrain.segment_width),
		"%d shapes should make %d segments of track, made %.0f px of it" % [
			shapes.size(),
			expected_segments,
			terrain.end_x() - origin_x
		]
	)

	var heights := PackedFloat32Array()
	for i in expected_segments + 1:
		heights.append(-terrain.to_local(
			terrain.surface_point_at(float(i) * terrain.segment_width)
		).y)
	_check(
		absf(heights[heights.size() - 1] - expected_height) < 1.0,
		"the run-out should sit %.1f px up, as the shapes ask; it sits %.1f" % [
			expected_height, heights[heights.size() - 1]]
	)

	# No face steeper than the steepest shape asked for, and no kink between two
	# segments that the car would nose into rather than drive over -- which is
	# the whole job of corner_blend, and is worth 48 degrees at Denver's tightest
	# V without it.
	var sampled := 0.0
	var kink := 0.0
	for i in expected_segments:
		if risers.has(i):
			continue
		var slope: float = (heights[i + 1] - heights[i]) / terrain.segment_width
		sampled = maxf(sampled, absf(slope))
		if i > 0 and not risers.has(i - 1) and not lips.has(i - 1):
			var previous: float = (heights[i] - heights[i - 1]) / terrain.segment_width
			kink = maxf(kink, absf(slope - previous))
	_check(
		rad_to_deg(atan(sampled)) <= steepest + 0.5,
		"no face should beat the %.0f degrees authored, found %.1f" % [
			steepest, rad_to_deg(atan(sampled))]
	)
	_check(
		rad_to_deg(atan(kink)) < 20.0,
		"corner_blend should keep the joins under 20 degrees, worst was %.1f" % rad_to_deg(atan(kink))
	)

	# And, as ever, the only honest check: drive it.
	Input.action_press("throttle")
	var ticks := 0
	var limit := 90 * Engine.physics_ticks_per_second
	while not main.has_pending_run() and ticks < limit:
		await get_tree().physics_frame
		ticks += 1
	Input.action_release("throttle")
	_check(
		main.has_pending_run(),
		"a pinned throttle should climb the authored track and finish, stopped at %.0f of %.0f px"
			% [car.chassis.global_position.x, main._finish_x]
	)

	main.load_level(0)


## A flat may name the height it sits at, and a list of those is a staircase:
## each flat sits exactly where it says, whatever the shape before it was doing,
## and the ground steps into it over one segment rather than ramping into it.
##
## Built here rather than driven, because no shipped level is a staircase yet:
## what is being checked is the ground the shapes describe, and a terrain with
## three children is the whole of what that takes.
func _a_levelled_flat_steps_the_ground() -> void:
	var terrain := TerrainAuthor.new()
	terrain.name = "Stairs"
	# The three outputs, by the names the build looks them up under.
	var collision := CollisionPolygon2D.new()
	collision.name = "Collision"
	terrain.add_child(collision)
	var fill := Polygon2D.new()
	fill.name = "Fill"
	terrain.add_child(fill)
	var surface := Line2D.new()
	surface.name = "Surface"
	terrain.add_child(surface)
	terrain.flat_start_segments = 2
	terrain.flat_end_segments = 2
	# Four segments each at the default 48 px, so every step has a plateau and a
	# riser rather than being all riser.
	terrain.shape_text = "flat 192\nflat 192 -96\nflat 192 -192\n"
	add_child(terrain)

	var heights := PackedFloat32Array()
	for i in 16:
		heights.append(-terrain.to_local(
			terrain.surface_point_at(float(i) * terrain.segment_width)
		).y)
	_check(
		terrain._get_configuration_warnings().is_empty(),
		"a staircase of levelled flats should read clean: %s"
			% ", ".join(terrain._get_configuration_warnings())
	)
	_check(
		is_zero_approx(heights[5]) and absf(heights[6] + 96.0) < 1.0,
		"the first step should drop 96 px over one segment, went %.1f to %.1f"
			% [heights[5], heights[6]]
	)
	_check(
		absf(heights[9] + 96.0) < 1.0 and absf(heights[10] + 192.0) < 1.0,
		"the second flat should sit flat at -96 and step to -192, sat %.1f to %.1f"
			% [heights[9], heights[10]]
	)
	_check(
		absf(heights[15] + 192.0) < 1.0,
		"the run-out should stay at the last step's -192 px, sat at %.1f" % heights[15]
	)

	# And a step the wrong way is a wall one segment wide, which the node says so
	# about rather than leaving it to be found on the hill.
	terrain.shape_text = "flat 192\nflat 192 288\n"
	var climbed := terrain._get_configuration_warnings()
	_check(
		climbed.size() == 1 and climbed[0].contains("the car can climb"),
		"a 288 px step up should be called out as unclimbable, said: %s" % ", ".join(climbed)
	)

	terrain.free()


## A track may descend as far as it likes and none of it is a fall: the limit is
## measured below the lowest ground on the course, not below the start line. Las
## Vegas is the level this is about -- it drops far enough that, measured from the
## spawn point, most of the way down read as out of the world and the run was lost
## for driving the track as authored.
func _a_long_descent_is_not_a_fall(main: Node2D) -> void:
	# The level that descends furthest below its own start, found by loading each
	# one: how deep a track goes is not something an export states.
	var index := -1
	var descent := 0.0
	for i in main.levels.size():
		main.load_level(i)
		var drop: float = main._lowest_ground_y - main._spawn_point.y
		if drop > descent:
			descent = drop
			index = i
	var limit = main.fall_limit_metres * GameState.PIXELS_PER_METRE
	_check(
		descent > limit,
		"one level should descend past the fall limit, deepest drops %.0f px of %.0f" % [
			descent, limit]
	)
	if index < 0:
		return

	main.load_level(index)
	await _wait(0.5)
	var car: Car = main.get_node("Car")
	var terrain: TerrainBase = main.get_node("Level/Terrain")

	# The bottom of the course, sampled off the surface itself, and the deepest
	# point of it that is still short of the line -- a car parked past that has
	# finished, which is a different thing from having fallen.
	var origin_x: float = terrain.to_global(Vector2.ZERO).x
	var segments := int((terrain.end_x() - origin_x) / terrain.segment_width)
	var deepest := -INF
	var lowest_before_the_line := Vector2(origin_x, -INF)
	for i in segments + 1:
		var point: Vector2 = terrain.surface_point_at(float(i) * terrain.segment_width)
		deepest = maxf(deepest, point.y)
		if point.x < main._finish_x and point.y > lowest_before_the_line.y:
			lowest_before_the_line = point
	_check(
		absf(terrain.lowest_surface_y() - deepest) < 1.0,
		"lowest_surface_y() should be the deepest the surface reaches: %.0f px, not %.0f" % [
			deepest, terrain.lowest_surface_y()]
	)
	_check(
		lowest_before_the_line.y > main._spawn_point.y + limit,
		"test setup: the bottom of the descent should be past the old spawn-relative limit"
	)

	# On the ground down there, where the old rule had the car out of the world.
	car.reset_to(lowest_before_the_line + Vector2(0.0, -80.0))
	await _wait(1.0)
	_check(
		car.chassis.global_position.y < main.fall_limit_y(),
		"ground at the bottom of a descent should be above the fall limit, %.0f px against %.0f" % [
			car.chassis.global_position.y, main.fall_limit_y()]
	)
	_check(
		absf(car.chassis.global_position.x - lowest_before_the_line.x) < 200.0,
		"a car driving the bottom of a descent should not have been restarted as a fall"
	)

	# Below that ground there really is nothing left, and that is still a fall.
	car.reset_to(Vector2(lowest_before_the_line.x, main.fall_limit_y() + 5.0 * GameState.PIXELS_PER_METRE))
	await _wait(0.3)
	_check(
		absf(car.chassis.global_position.x - main._spawn_point.x) < 80.0,
		"falling past the lowest ground should still be a lost run"
	)

	main.load_level(0)


## Is there anything solid under this local X on the terrain?
func _has_ground(main: Node2D, terrain: TerrainBase, local_x: float) -> bool:
	var from := terrain.to_global(Vector2(local_x, -3000.0))
	var to := terrain.to_global(Vector2(local_x, terrain.fill_bottom()))
	var query := PhysicsRayQueryParameters2D.create(from, to)
	return not main.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _snapshot_save() -> void:
	_saved_file = FileAccess.get_file_as_bytes(GameState.SAVE_PATH)


func _restore_save() -> void:
	if _saved_file.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
	else:
		var file := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
		if file != null:
			file.store_buffer(_saved_file)
			file.close()
	GameState.load_game()
	# Nothing left to flush: the file on disk is already what the player had.
	GameState._dirty = false


func _wait(seconds: float) -> void:
	var ticks := int(seconds * Engine.physics_ticks_per_second)
	for i in ticks:
		await get_tree().physics_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func quit(code: int) -> void:
	get_tree().quit(code)
