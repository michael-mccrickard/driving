class_name Car
extends Node2D
## Side-view (hill-climb style) vehicle.
##
## The chassis and the two wheels are siblings, not parent and children: nesting
## a RigidBody2D under another RigidBody2D makes the child's transform fight the
## physics server. Each wheel is held to the chassis by a pair of joints -- a
## GrooveJoint2D that constrains it to a vertical slot, and a
## DampedSpringJoint2D that is the suspension proper.
##
## Driving is pure torque on the wheels; grip and gravity do the rest. Off the
## ground, the same input rotates the chassis instead so the player can land
## flat.
##
## The car also carries the run's fuel, because it is the throttle that spends
## it: holding throttle drains the tank, and an empty tank cuts the engine. How
## fast it drains depends on how fast the car is going -- see get_burn_multiplier().
## Cost rises with the square of speed, so there is a cheapest cruising speed well
## below top speed, and flooring it is never the efficient answer.
##
## Acceleration is shaped by CarStats.torque_curve rather than being a flat shove:
## motor torque is scaled by the curve sampled at the wheel's share of its spin
## cap, so pull is strongest off the line and fades out as the car approaches top
## speed, instead of running at full torque right up to a hard cut-off.

signal grounded_changed(is_grounded: bool)
signal reset_performed

@export var stats: CarStats

@onready var chassis: RigidBody2D = $Chassis
@onready var wheel_back: RigidBody2D = $WheelBack
@onready var wheel_front: RigidBody2D = $WheelFront

var _bodies: Array[RigidBody2D] = []
var _spawn_transforms: Array[Transform2D] = []
var _is_grounded := false
var _held := false
var _fuel := 0.0
var _wheel_radius := 16.0


func _ready() -> void:
	_bodies = [chassis, wheel_back, wheel_front]
	for body in _bodies:
		_spawn_transforms.append(body.transform)
		# get_contact_count() reports nothing unless monitoring is switched on.
		body.contact_monitor = true
		body.max_contacts_reported = 4
	_apply_stats()
	_wheel_radius = _measure_wheel_radius()
	_fuel = get_fuel_capacity()


func _physics_process(delta: float) -> void:
	# A parked rig is static, so there is nothing to drive -- and nothing should
	# be spent while a finished run's score sits on screen.
	if _held:
		return
	_update_grounded()

	# Throttle is the only input that costs fuel, and an empty tank cuts it
	# outright. Reverse stays live either way, so the player can always brake.
	var throttle := Input.get_action_strength("throttle")
	if _fuel <= 0.0:
		throttle = 0.0
	else:
		_burn_fuel(throttle, delta)

	var drive := throttle - Input.get_action_strength("reverse")
	if _is_grounded:
		_apply_drive(drive)
	else:
		_apply_air_control(drive)

	_apply_handbrake(Input.is_action_pressed("handbrake"))


## Current speed along the ground, in pixels/second.
func get_speed() -> float:
	return chassis.linear_velocity.length()


## Wheel spin ceiling in rad/s -- the knob that actually caps top speed.
func get_max_wheel_speed() -> float:
	return stats.max_wheel_speed if stats else 60.0


## The same cap expressed in km/h, which is the unit the HUD shows and the unit
## the tuning field is edited in. Uses the real wheel radius, so resizing the
## wheels keeps the conversion honest.
func get_max_speed_kmh() -> float:
	return GameState.px_per_sec_to_kmh(get_max_wheel_speed() * _wheel_radius)


## Runtime tuning from the HUD. Writes to the CarStats resource in memory only --
## nothing is persisted back to the .tres.
func set_max_speed_kmh(kmh: float) -> void:
	if stats == null or _wheel_radius <= 0.0:
		return
	var px_per_sec := maxf(kmh, 0.0) / 3.6 * GameState.PIXELS_PER_METRE
	stats.max_wheel_speed = px_per_sec / _wheel_radius


## How close the driven wheels are to their spin cap, 0..1. This is what the
## torque curve is sampled at -- "how near the redline am I", which is relative
## to the cap by definition. Fuel cost deliberately uses absolute speed instead;
## see get_burn_multiplier().
func get_spin_fraction() -> float:
	var max_spin := get_max_wheel_speed()
	if max_spin <= 0.0:
		return 1.0
	var fastest := 0.0
	for wheel in _driven_wheels():
		fastest = maxf(fastest, absf(wheel.angular_velocity))
	return clampf(fastest / max_spin, 0.0, 1.0)


## Fraction of motor_torque still on tap at the given speed fraction. Falls back
## to flat full torque when no curve is assigned.
func get_torque_scale(speed_fraction: float) -> float:
	if stats == null or stats.torque_curve == null:
		return 1.0
	return maxf(stats.torque_curve.sample_baked(clampf(speed_fraction, 0.0, 1.0)), 0.0)


## Tank size, with a fallback so the car still runs without a CarStats assigned.
func get_fuel_capacity() -> float:
	return stats.fuel_capacity if stats else 100.0


## Level configuration: how big the tank is on this track. The level applies it
## before the run starts, and reset_to() then fills to the new size.
func set_fuel_capacity(capacity: float) -> void:
	if stats == null:
		return
	stats.fuel_capacity = maxf(capacity, 0.0)
	_fuel = minf(_fuel, stats.fuel_capacity)


## Fuel left in the tank.
func get_fuel() -> float:
	return _fuel


## Fuel spent since the last reset. This is the score the game is played for.
func get_fuel_used() -> float:
	return get_fuel_capacity() - _fuel


## Tank level as 0..1, for readouts that want a proportion rather than a total.
func get_fuel_fraction() -> float:
	var capacity := get_fuel_capacity()
	return _fuel / capacity if capacity > 0.0 else 0.0


func has_fuel() -> bool:
	return _fuel > 0.0


## Overrides the tank level, clamped to the tank. Driven by the HUD's fuel field,
## and handy for tests and any future pickup; reset_to() refills to capacity
## regardless.
func set_fuel(amount: float) -> void:
	_fuel = clampf(amount, 0.0, get_fuel_capacity())


## Base fuel cost of a millisecond at full throttle, before the speed multiplier.
func get_burn_rate() -> float:
	return stats.fuel_per_millisecond if stats else 0.001


## Runtime tuning from the HUD, in-memory only. See set_max_speed_kmh().
func set_burn_rate(rate: float) -> void:
	if stats:
		stats.fuel_per_millisecond = maxf(rate, 0.0)


## Current speed in km/h -- the same number the HUD prints, so the burn
## multiplier below can be read straight off the readout.
func get_speed_kmh() -> float:
	return GameState.px_per_sec_to_kmh(get_speed())


## What the current speed does to the burn rate: 1.0 at rest, rising to
## 1 + burn_speed_penalty at burn_reference_kmh and beyond it above that.
##
## Measured against a fixed reference speed rather than against max_wheel_speed,
## so that winding the top speed down genuinely saves fuel instead of just making
## the same journey slower.
func get_burn_multiplier() -> float:
	if stats == null:
		return 1.0
	var ratio := maxf(get_speed_kmh() / maxf(stats.burn_reference_kmh, 1.0), 0.0)
	return 1.0 + stats.burn_speed_penalty * pow(ratio, stats.burn_speed_exponent)


## World X of the leading edge of the whole rig -- "any part of the car", which
## is what the finish line is judged on. Whichever body is furthest along wins,
## plus the wheel radius: upright and pointing forward that is the front tyre,
## which reaches further than the chassis does from its own centre.
func get_front_x() -> float:
	var front := -INF
	for body in _bodies:
		front = maxf(front, body.global_position.x)
	return front + _wheel_radius


func is_grounded() -> bool:
	return _is_grounded


## True once the chassis is more than 90 degrees from upright.
func is_flipped() -> bool:
	return chassis.global_transform.y.dot(Vector2.DOWN) < 0.0


## Parks the whole rig where it is, so a run that has driven off the end of the
## track does not fall for ever while its score sits on screen. Idempotent --
## main.gd calls it every frame the car is out of the world. reset_to() releases
## it again.
func hold() -> void:
	if _held:
		return
	_held = true
	for body in _bodies:
		body.linear_velocity = Vector2.ZERO
		body.angular_velocity = 0.0
		body.freeze = true


func is_held() -> bool:
	return _held


## Teleports the whole rig back to a point, upright, motionless and with a full
## tank. Preserves the wheels' offsets relative to the chassis so the joints do
## not snap.
func reset_to(target: Vector2) -> void:
	_fuel = get_fuel_capacity()
	_held = false
	for i in _bodies.size():
		var body := _bodies[i]
		var spawn := _spawn_transforms[i]
		# Unfreeze first: a frozen body is a static one, and writing velocities
		# to a static body does nothing.
		body.freeze = false
		body.linear_velocity = Vector2.ZERO
		body.angular_velocity = 0.0
		body.rotation = 0.0
		# Writing global_transform on a physics body is only safe because we
		# zero the velocities in the same frame; do not do this per-frame.
		body.global_transform = Transform2D(0.0, target + spawn.origin)
		PhysicsServer2D.body_set_state(
			body.get_rid(),
			PhysicsServer2D.BODY_STATE_TRANSFORM,
			body.global_transform
		)
	reset_performed.emit()


## The burn rate is authored per millisecond, so scale the frame's delta up into
## milliseconds. Analog triggers burn in proportion to how far they are held; a
## key is always full strength, and so always the full rate.
func _burn_fuel(throttle: float, delta: float) -> void:
	if is_zero_approx(throttle):
		return
	var spent := throttle * get_burn_rate() * get_burn_multiplier() * delta * 1000.0
	_fuel = maxf(_fuel - spent, 0.0)


## Read off the collision shape rather than hard-coded, so the km/h conversion
## follows the wheels if they are ever resized.
func _measure_wheel_radius() -> float:
	var shape := wheel_back.get_node_or_null("Collision") as CollisionShape2D
	if shape == null:
		return 16.0
	var circle := shape.shape as CircleShape2D
	return circle.radius if circle != null else 16.0


func _apply_stats() -> void:
	if stats == null:
		push_warning("Car has no CarStats assigned; using scene defaults.")
		return

	chassis.mass = stats.chassis_mass
	chassis.center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
	chassis.center_of_mass = stats.centre_of_mass

	for wheel in [wheel_back, wheel_front]:
		wheel.mass = stats.wheel_mass
		if wheel.physics_material_override != null:
			wheel.physics_material_override.friction = stats.wheel_friction

	# Only rest_length/stiffness/damping are tuning. DampedSpringJoint2D.length
	# and GrooveJoint2D.initial_offset are *geometry*: Godot uses them to decide
	# which point on the wheel the joint grabs (joint origin + length down the
	# joint's local Y). They must stay equal to the joint-to-wheel-centre
	# distance set in car.tscn, or the joints grip a phantom point beside the
	# wheel and the suspension collapses through its own anchor.
	for spring in [$SpringBack, $SpringFront] as Array[DampedSpringJoint2D]:
		spring.stiffness = stats.spring_stiffness
		spring.damping = stats.spring_damping
		spring.rest_length = stats.spring_rest_length


func _driven_wheels() -> Array:
	if stats != null and stats.all_wheel_drive:
		return [wheel_back, wheel_front]
	return [wheel_back]


func _apply_drive(drive: float) -> void:
	var motor: float = stats.motor_torque if stats else 9000.0
	var brake: float = stats.brake_torque if stats else 14000.0
	var max_spin := get_max_wheel_speed()

	for wheel in _driven_wheels():
		if is_zero_approx(drive):
			continue
		# Input opposing the current spin brakes; input with it accelerates,
		# up to the spin ceiling that defines top speed.
		var opposing := signf(drive) != signf(wheel.angular_velocity)
		if opposing and not is_zero_approx(wheel.angular_velocity):
			wheel.apply_torque(drive * brake)
			continue
		# The cap stays as a hard backstop -- a hand-edited curve that never
		# reaches zero would otherwise let the wheel spin up forever.
		if absf(wheel.angular_velocity) >= max_spin:
			continue
		# Each wheel is scaled by its own spin, so a wheel spinning freely in the
		# air does not rob torque from one that still has grip.
		var fraction := absf(wheel.angular_velocity) / max_spin if max_spin > 0.0 else 1.0
		wheel.apply_torque(drive * motor * get_torque_scale(fraction))


func _apply_air_control(drive: float) -> void:
	var torque: float = stats.air_torque if stats else 16000.0
	var max_spin: float = stats.max_air_spin if stats else 5.0
	if is_zero_approx(drive):
		return
	# Throttle rotates the nose up (backflip), reverse rotates it down.
	if absf(chassis.angular_velocity) < max_spin or signf(drive) != signf(chassis.angular_velocity):
		chassis.apply_torque(-drive * torque)


func _apply_handbrake(pressed: bool) -> void:
	var damping: float = stats.handbrake_damping if stats else 12.0
	for wheel in [wheel_back, wheel_front]:
		wheel.angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
		wheel.angular_damp = damping if pressed else 0.0


func _update_grounded() -> void:
	var grounded := wheel_back.get_contact_count() > 0 or wheel_front.get_contact_count() > 0
	if grounded == _is_grounded:
		return
	_is_grounded = grounded
	grounded_changed.emit(_is_grounded)
