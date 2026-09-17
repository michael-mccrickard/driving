class_name CarStats
extends Resource
## Every tunable knob for a vehicle, in one saveable resource.
##
## Car.gd pushes these onto the physics nodes in _ready(), so you can duplicate
## default_car.tres, tweak numbers, and swap the resource on a Car instance to
## get a different vehicle without touching the scene tree.

@export_group("Drive")
## Torque applied to each driven wheel at full throttle.
@export_range(0.0, 400000.0, 500.0) var motor_torque := 90000.0
## Wheel spin ceiling, rad/s. This is what actually caps top speed.
@export_range(0.0, 200.0, 1.0) var max_wheel_speed := 45.0
## Shape of the pull as the car speeds up. Sampled at wheel spin / max_wheel_speed
## (0 = stationary, 1 = at the cap) and multiplied into motor_torque, so the car
## eases up to top speed instead of slamming into the cap at full torque. Leave
## unset for the old flat-torque behaviour.
@export var torque_curve: Curve
## Torque applied against the wheel's current spin when braking or reversing
## into forward motion.
@export_range(0.0, 400000.0, 500.0) var brake_torque := 130000.0
## Extra angular damping on the wheels while the handbrake is held.
@export_range(0.0, 50.0, 0.1) var handbrake_damping := 12.0
## Rear wheel is always driven; enable to drive the front one too.
@export var all_wheel_drive := false

@export_group("Fuel")
## Tank size at the start of a run. Fuel is the score, not a health bar: the
## record is the lowest amount a *completed* run ever spent. The default is set
## deliberately far beyond what any run could burn, so the tank never decides
## whether a run finishes -- it only measures what finishing cost.
@export_range(0.0, 100000.0, 1.0, "or_greater") var fuel_capacity := 100000.0
## Fuel burned per millisecond of held throttle. At 0.001 a second of full
## throttle costs one unit, so the bills the record is kept in read as
## "seconds of throttle, weighted by how fast it was held".
@export_range(0.0, 0.05, 0.0001) var fuel_per_millisecond := 0.001
## How much more expensive speed is: the burn rate is multiplied by
## 1 + penalty * (speed / burn_reference_kmh) ^ burn_speed_exponent.
## At the defaults the engine drinks three times as fast at 80 km/h as it does
## at a standstill, and worse still above that.
@export_range(0.0, 10.0, 0.1) var burn_speed_penalty := 2.0
## Speed at which the full penalty applies, in km/h. Deliberately a fixed
## reference rather than max_wheel_speed: tie it to the cap and lowering the cap
## would only make the car slower at the same burn, so there would be no reason
## ever to lift off.
@export_range(1.0, 400.0, 1.0) var burn_reference_kmh := 80.0
## How sharply cost rises with speed. Must be above 1 for slowing down to be
## worth anything -- with a linear rise, fuel per metre is rate*(1/v + k), which
## just falls forever as v grows, so flat out would always be the cheapest way
## round. Squared (drag-like) puts the cheapest cruise at
## burn_reference_kmh / sqrt(burn_speed_penalty), about 57 km/h at the defaults.
@export_range(1.0, 4.0, 0.1) var burn_speed_exponent := 2.0

@export_group("Air Control")
## Torque applied to the chassis for mid-air rotation (throttle = backflip).
@export_range(0.0, 200000.0, 500.0) var air_torque := 40000.0
## Caps how fast the player can spin the chassis in the air, rad/s.
@export_range(0.0, 20.0, 0.1) var max_air_spin := 5.0

@export_group("Suspension")
## Spring constant, in force units per pixel of compression. As a starting
## point, the springs must hold up chassis_mass * gravity between them, so
## roughly (chassis_mass * gravity) / (2 * wanted_sag_in_pixels).
@export_range(1.0, 3000.0, 5.0) var spring_stiffness := 500.0
## Oscillation damping. Too low and the car pogos; too high and it feels rigid.
## Scales with stiffness -- around stiffness / 16 is a reasonable ride.
@export_range(0.0, 300.0, 0.5) var spring_damping := 30.0
## Neutral suspension extension in pixels, measured from the joint anchor. The
## car sags below this under its own weight.
@export_range(0.0, 64.0, 1.0) var spring_rest_length := 22.0

@export_group("Mass & Grip")
@export_range(0.1, 50.0, 0.1) var chassis_mass := 4.0
@export_range(0.1, 20.0, 0.1) var wheel_mass := 0.8
## Tyre friction. Above ~1.0 the wheel bites hard and can climb steeper faces.
@export_range(0.0, 10.0, 0.05) var wheel_friction := 3.0
## Offset from the chassis origin, in pixels. Positive Y (lower) resists flips.
@export var centre_of_mass := Vector2(0.0, 10.0)
