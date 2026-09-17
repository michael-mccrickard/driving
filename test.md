# Driving

A side-view (hill-climb style) 2D car physics project for **Godot 4.6**.

**The goal is fuel efficiency.** Every run starts with a full tank and ends when
any part of the car is past the **finish line** — a post at the near end of the
flat run-out that closes every track. Past the run-out is a wall, which a
finished run rolls to a stop against instead of driving off the end; hitting it
costs nothing, because the bill was settled back at the line. Holding the
throttle burns fuel, and burns it faster the quicker you are already going;
coasting, braking and rolling downhill are free. The record is the *least* fuel
any completed run has spent, so the game is played by not touching the throttle.

The tank is deliberately bottomless (100,000 units, against a flat-out run's
~104). Running dry is not the fail state — spending more than the record is.

There are twelve levels, walked with the **NEXT** button in the bottom right, or
picked straight off the list a right-click on it opens. Each one owns its track,
its car, its rules and its record — see [Levels](#levels).

Burn rate and top speed are **editable live** in the HUD, so numbers can be
experimented with mid-run without restarting. Both persist between sessions, and
changing either **clears the record**, since a fuel bill only means something
against runs that paid the same rates. The tank is not tunable: it is 100,000 on
every level, and the HUD's fuel readout is the bill, not a gauge.

Open `project.godot` in Godot and press F5, or:

```sh
godot --path . # run
godot --headless res://tests/smoke_test.tscn # physics smoke test, exits 0/1
```

A headless run reads the class cache the editor writes, so after adding a script
with a new `class_name`, run `godot --headless --import` once or the run fails to
parse it.

## Controls

| Action | Keys | Gamepad |
| --- | --- | --- |
| Throttle (and nose-up in the air) | `→` / `D` | A |
| Reverse / brake (nose-down in the air) | `←` / `A` | X |
| Handbrake | `S` / `↓` | B |
| Reset run | `R` | Y |
| Author/Play mode | `Space` | — |
| Pause | `Esc` | Start |

`Space` is the mode toggle, so the handbrake moved off it to `S` / `↓`.

Restarting is also what banks a finished run's score, so `R` (or the button) is
how a completed course is signed off.

The bottom left of the screen carries a **Restart** button (the mouse equivalent
of `R`), a **Reset best** button, which throws the stored record away and greys
itself out until something finishes the course again, and the **music switch**.
Restart is on show in both modes; the other two are one per mode — Reset best in
Author, the music switch in Play.

**Right-clicking NEXT** opens a list of every level above it, so any of them can
be loaded directly rather than walked to. The one on screen is named in yellow.
Picking one closes the list and is a level change like NEXT's own: a finished run
is banked on the way out.

## Levels

A level is a `LevelConfig` resource (`resources/levels/*.tres`): a track scene, a
car scene, the fuel/burn/top-speed the car is given on it, and a music track.
`main.gd` holds the list in `levels` and loads one at a time, instancing the
track as `Level` and the car as `Car` — neither is baked into `main.tscn` any
more. A level scene must contain a terrain named `Terrain` — a `TerrainGenerator`
(rolling hills out of noise) or a `TerrainAuthor` (a written list of slopes and
flats); that is what the spawn point and the finish line are read off. It also carries a
`Backdrop` — see [The backdrop](#the-backdrop).

| `resources/levels/` | Track | Terrain | Noise Seed
| --- | --- | --- |
| `boston.tres` | `boston.tscn` | 620 × 48 px, 385 / 2200 | 1590
| `chicago.tres` | `chicago.tscn` | 500 × 48 px, 284 / 1380, two gaps | 9
| `chilltown.tres` | `chilltown.tscn` | 500 × 30 px, 100 / 1000, four narrow gaps | 8305
| `cullman.tres` | `cullman.tscn` | ??? × ?? px, 499 / 2030, six gaps | 4106
| `dallas.tres` | `dallas.tscn` | 500 × 48 px, 196 / 1400 | 947
| `denver.tres` | `denver.tscn` | **authored** — a written shape list, no noise seed |*
| `dunes.tres` | `dune_run.tscn` | 620 × 48 px, 180 / 2200 dunes | 6421
| `frisco.tres` | `frisco.tscn` | 620 × 48 px, 180 / 2200 | 8888
| `high_country.tres` | `high_country.tscn` | 600 × 48 px, 200 / 1700, two gaps | 7777
| `hills.tres` | `hills.tscn` | 500 × 48 px, 130 / 1400 rollers | 1337
| `indy.tres` | `indy.tscn` | ??? × ?? px, 300 / 1680, 8 gaps | 3497
| `london.tres` | `london.tscn` | 620 × 48 px, 200 / 1700, four gaps | 69
| `miami.tres` | `miami.tscn` | 500 × 30 px, 173 / 870, three gaps | 3232
| `nashville.tres` | `nashville.tscn` | 500 × 30 px, 155 / 1550 | 9876
| `vegas.tres` | `vegas.tscn` | **authored** — All downhill!|*





Every level runs the same car on the same rules — `burn_rate` 0.004, 80 km/h, the
bottomless tank — so their records are comparable to each other. What differs is
the track, the backdrop seed and the music.

Denver is the one **authored** track: `TerrainAuthor` rather than
`TerrainGenerator`, a written list of slopes and flats rather than a noise seed.
See [Terrain](#terrain-and-tuning) and [Authoring.md](Authoring.md).

**NEXT** advances and wraps round at the end. A finished run is banked before the
switch, or its bill would land on a level it was not driven on.

The car settings on a `LevelConfig` are applied over the car scene's own
`CarStats`, so `CarStats` stays the *vehicle* — mass, torque, springs, the torque
curve — while the tank, burn rate and top speed are the *rules of this level*.
(`fuel_capacity` is left at 100,000 on every level shipped; it is a knob for a
level that wants a genuinely limited tank, not part of normal play.)

### Per-level records

`GameState` keeps a record and a tuning pair per level, keyed by
`LevelConfig.save_id`, and `set_level()` swaps the whole working set so the rest
of the game goes on reading `best_fuel_used` as plain state. The save file gets a
section per level:

```ini
[level_hills]
best_fuel_used=40.06
burn_rate=0.004
max_speed_kmh=80.0
```

A save written before levels existed (a bare `[progress]` / `[tuning]` pair) is
adopted by whichever level loads first, since there was only one track then. It
is left untouched on disk until a level claims it, so nothing is dropped if the
game is closed first.

## The backdrop

Every level scene carries a `Backdrop` (`scripts/levels/backdrop.gd`): a
`CanvasLayer` on layer `-100`, drawn behind everything. Because it is a canvas
layer the camera never touches it, so it **does not move as the car drives** —
this is scenery at infinity, not a parallax plane. Anything that should slide
past wants a `Parallax2D` under the level root instead.

For now it draws a field of stars, scattered procedurally from `backdrop_seed`
so each level gets its own sky and nothing has to be placed by hand: denser and
brighter towards the top of the screen, thinning out where the hills come up.
The layer is built to take more than stars — a moon, a horizon glow, a city
skyline — one `_paint_<thing>()` at a time; see
[Authoring.md](Authoring.md#the-backdrop).

## Modes

`Space` toggles the HUD between two modes. Nothing about the car, the physics or
the scoring changes — this is purely what is on show:

| | Author | Play |
| --- | --- | --- |
| burn /ms, max km/h, Music | shown, editable | hidden |
| Reset best | shown | hidden — only an author wipes records |
| Music switch | hidden | shown, next to Restart |
| fuel used, speed, distance, level name, Best, Restart, NEXT (and its level list) | shown | shown |

Author is the tuning sandbox and the mode the game starts in. Play is the game as
played: the knobs that could cheat the record are out of reach. The fuel readout
is not one of the differences — the tank is sized past what any run can drink, so
there is no gauge to read and both modes show the same thing, the bill the run
has run up so far. `Hud.Mode` owns this; `main.gd` only carries the keystroke
over.

## Music

The level names its music track, and loading a level puts that name in the
**Music** field (Author mode); typing over it is a live override until the next
level load. A bare filename is looked up
in `assets/audio/`, so the default is `default.mp3`; anything with a scheme or a
leading slash is taken as a path in its own right. Press Enter to commit.

`MusicPlayer` (`scripts/audio/music_player.gd`, the `Music` node in `main.tscn`)
plays it on a loop from the start of a run until the run is finished — what is
on screen while the bill is being read is scored by the sound effects below
instead. Every restart takes the
track from the top. The loop is forced on the stream at load time, because the
mp3 importer defaults to `loop=false` and a run has no fixed length.

A missing or unreadable file leaves the game silent and logs one warning: a typo
in a text field should not stop anyone driving. In Play mode the field is gone
and the only music control is the **Music** switch beside Restart.

## Sound

`SoundPlayer` (`scripts/audio/sound_player.gd`, the `Sfx` node in `main.tscn`)
is a second `AudioStreamPlayer` beside the music, and only because one player
plays one stream: sharing the music's player would mean every sound effect
stopped the music to be heard. The **Music** switch does not silence it.

Clips are named relative to `assets/audio/` — a folder is picked from at random,
a file is played as named — and `main.gd` names them at the four moments that
have a sound:

| Moment | Sound |
| --- | --- |
| the car crosses the finish line | a clip from `success/` |
| behind it, once it has played | `misc/applause.wav` if the run took the record, else `misc/waiting.mp3` on a loop |
| the car rolls into the end wall | `misc/impact.wav`, cut in over whatever is playing |
| a run is lost — out of the world off a jump, or come to rest on its roof or dry | a clip from `fail/` |

A folder is listed on every pick, so a clip dropped into one while the game is
running joins the rotation, and the pick is never the one that folder gave last
time. Sounds are sequenced rather than mixed: one clip plays and the rest wait
their turn, which is what puts the applause *behind* the fanfare rather than on
top of it. The thud is the exception — it cuts in, and puts the looping bed back
underneath afterwards, since the wall arrives while the finish is still sounding.

The bed and everything queued behind it are lifted by the next run, whether that
is a restart, a lost run or a level change. Asking for a restart by hand is not
a failure and makes no sound. A missing folder or file costs that one sound and
logs one warning, as with the music.

## Layout

```
project.godot            input map, layer names, gravity, 120 Hz physics tick
icon.svg
scenes/
  main.tscn              entry point: camera + HUD + music (level and car are
						 instanced at runtime from the LevelConfig)
  vehicles/car.tscn      chassis, two wheels, four joints
  levels/*.tscn          one per level: terrain + backdrop. Eleven are noise
						 (terrain_generator.gd); denver.tscn is authored
						 (terrain_author.gd)
  ui/hud.tscn            readout, the tuning fields, the finished-run bill,
						 restart/reset buttons (bottom left)
scripts/
  main.gd                loads levels, spawns the car, scores finished runs
  autoload/game_state.gd singleton: unit conversions, per-level record + tuning
  vehicles/car.gd        drive, torque curve, braking, air control, fuel, reset,
						 park
  vehicles/car_stats.gd  CarStats resource -- every tuning knob
  vehicles/wheel_visual.gd
  camera/follow_camera.gd
  levels/terrain_base.gd everything a track has in common: collision and
						 visuals, gaps, ramps, hand edits, run-out, wall, finish
  levels/terrain_generator.gd
						 rolling hills out of noise
  levels/terrain_author.gd
						 a written list of shapes: flat, slope up, slope down
  levels/backdrop.gd     the static sky behind a level -- stars, for now
  levels/level_config.gd one level: track, car, fuel, burn, top speed, music
  ui/hud.gd
  audio/music_player.gd  looping track for the length of a run
  audio/sound_player.gd  the sound effects, on a player of their own
resources/vehicles/default_car.tres
resources/levels/*.tres  one LevelConfig per level, twelve of them
tests/smoke_test.gd      headless physics assertions
```

## How the car is built

The chassis and both wheels are **siblings**, not parent and children — nesting a
`RigidBody2D` under another makes the child's transform fight the physics server.
Each wheel is bound to the chassis by two joints:

- **`GrooveJoint2D`** constrains the wheel to a vertical slot (the travel limit).
- **`DampedSpringJoint2D`** is the suspension spring itself.

Driving is pure torque on the rear wheel; grip, gravity and the springs do the
rest. Off the ground, the same input rotates the chassis instead, so the player
can level out before landing.

### The one trap to know about

`GrooveJoint2D.initial_offset` and `DampedSpringJoint2D.length` are **geometry,
not tuning**. Godot uses them to decide *which point on the wheel body the joint
grabs*: joint origin, plus that distance down the joint's local Y axis. They must
stay equal to the joint-to-wheel-centre distance authored in `car.tscn`
(currently **20 px** — joints sit at chassis-local y=2, wheel centres at y=22).

Set them to anything else and both joints grip a phantom point beside the wheel;
the suspension then collapses *through* its own anchor, the spring direction
inverts, and the car sinks onto its belly and cannot move. `car.gd` deliberately
does not write these two fields from `CarStats` for that reason.

## Acceleration

Motor torque is not a flat shove. It is scaled by `CarStats.torque_curve`, sampled
at the wheel's share of its spin cap (0 = stopped, 1 = at `max_wheel_speed`), so
pull is strongest off the line and fades out as the car approaches top speed
instead of running flat out into a hard cut-off. Each wheel is scaled by its own
spin, so a wheel spinning freely in the air does not rob torque from one that
still has grip. The cap itself stays as a backstop — a hand-edited curve that
never reaches zero would otherwise let the wheel spin up forever.

The curve is a `Curve` resource on `default_car.tres`, so it is editable as an
actual curve in the inspector. Leave it unset for the old flat-torque behaviour.

## Fuel and scoring

`Car` owns the tank, because it is the throttle that spends it:

- Only **throttle** burns fuel, at `fuel_per_millisecond` per millisecond held,
  scaled by how far the input is held (analog triggers burn proportionally, a key
  is always the full rate). Mid-air throttle is nose-up rotation but still costs
  fuel — air time is expensive on purpose.
- **Speed multiplies the cost**, by
  `1 + burn_speed_penalty * (kmh / burn_reference_kmh) ^ burn_speed_exponent`.
- **Reverse and braking are free**, and stay live even on an empty tank, so the
  player can always slow down.
- An **empty tank cuts the throttle entirely**, and `main.gd` then restarts the
  run after `auto_recover_seconds`, since a dead engine is as unrecoverable as
  landing on the roof. With the default tank this is a safety net rather than a
  rule of the game: no run can spend its way through 100,000 units.
- `TerrainGenerator.finish_x()` is the finish line, at the near end of the flat
  run-out that closes every track. The run is finished the moment **any part of
  the car** is past it — `Car.get_front_x()`, the leading edge of the whole rig,
  so a nose over the line counts. `main.gd` locks the fuel bill in at that
  instant. A finished run is never restarted for the player: the bill stays on
  screen beside the record it is up against, and the record only moves when they
  press Restart.
- The rig is deliberately left **driveable** after the line. It has a run-out to
  use up and a wall at `end_x()` to run into, and neither is part of the score:
  the HUD reads out the settled bill rather than what the car goes on spending,
  so a throttle held into the wall costs nothing. The wall is also what keeps a
  finished run in the world — without it the car simply drives off the cliff.
  Its paint and its collision are separate: clearing `wall_visible` on `Terrain`
  hides the drawn rectangle for a level that covers the end of the course with
  its own art, and the car is stopped in exactly the same place.
- `Car.hold()` parks the rig where it is, and is now only reached by a run that
  falls out of the world past `fall_limit_metres`. A finished one parks and waits
  there; an unfinished one restarts.

Records are **per level**, so `best  --` on a new track is not a lost record.

`GameState.report_run_complete()` is deliberately only called on a **finished**
run, and not until the restart that ends it. A partial run always spends less
than a full one, so scoring an abandoned attempt would set an unbeatable record. For the same reason `best_fuel_used`
starts at `NO_RECORD` (-1) rather than 0, and the HUD shows `best  --` until
something crosses the line. `GameState.clear_record()` puts it back to that
state, and unlike a new record it writes through to disk immediately — a record
the player has deliberately wiped must not return on the next launch.

The record is also cleared automatically whenever the burn rate or the top speed
changes (`GameState.report_tuning()`). The score is a fuel bill, and a bill is
only comparable against runs charged the same rates: without this, winding the
burn rate down to nothing would set a record no honest run could ever beat. A
finished run still waiting to be banked is dropped by the same change, for the
same reason — it was run up at the old rates.

### Why the exponent has to be above 1

Fuel per metre is `rate * (1/v + k*v^(e-1))`. With a **linear** rise in cost
(`e = 1`) that collapses to `rate * (1/v + k)`, which just falls forever as speed
grows — flat out would always be the cheapest way round and there would be no
game. Squaring it (drag-like, `e = 2`) puts a genuine minimum at
`burn_reference_kmh / sqrt(burn_speed_penalty)`, about **57 km/h** at the
defaults.

`burn_reference_kmh` is deliberately a fixed speed rather than `max_wheel_speed`.
Tie the penalty to the cap and lowering the cap makes the car slower at exactly
the same burn, so winding the top-speed field down could only ever hurt.

Measured on the default 745 m track:

| Strategy | Result |
| --- | --- |
| Throttle pinned, 81 km/h cap | finishes on 103.9 fuel |
| Throttle pinned, 57 km/h cap | finishes on 100.8 fuel — the best a pinned throttle does |
| Pulse and glide to 70 km/h | finishes on 23.6 fuel |
| Pulse and glide to 45 km/h | finishes on 9.6 fuel |

Holding the throttle down costs an order of magnitude more than lifting off and
coasting does. Nothing stops you finishing flat out — the tank is bottomless and
the wall catches you either way — but the bill is the score, and that is the
whole game.

## Live tuning

Two HUD fields (Author mode only) write straight to the running car:
**burn /ms** (`fuel_per_millisecond`) and **max km/h** (`max_wheel_speed`, via a
km/h conversion that reads the real wheel radius off the collision shape). The
tank is not among them: it is fixed at 100000 for every level, far past what a
run could burn, so what it holds never decides anything.

Edits go to the `CarStats` resource **in memory only** — nothing is written back
to the `.tres`. **Burn rate and top speed are saved per level** to `user://save.cfg`
instead and pushed into the car by `main.gd._apply_saved_tuning()` on launch, so
they survive a restart while the authored `.tres` values stay untouched. That
restore deliberately bypasses the signal handlers: putting back the settings a
record was set with is not a change to them, and routing it through the normal
path would wipe the record on every launch. Fuel is **not** saved — it is run
state, not a setting, and every run starts on a full tank.

The music switch in Play mode is a plain `Button`, not a latching `CheckButton`,
so the on/off state lives on the HUD and each press flips it. The button's icon
is dimmed while the music is off, since nothing else about it would say so.

What gets stored is read back off the car rather than taken from the field, so a
value the car clamped is saved as whatever really took effect. The HUD emits
a signal per field and `main.gd` is the only place those meet the car; the panel
itself knows nothing about vehicles. Values are pushed back into the fields every
frame, so anything the car clamps visibly snaps back, and a field being typed into
is left alone until it loses focus. Press Enter to commit — that also hands the
keyboard back, so the arrow keys drive the car again instead of the text cursor.

The two buttons work the same way: the HUD only emits `restart_requested` and
`clear_record_requested`, and `main.gd` routes them to `_restart_run()` and
`GameState.clear_record()`. They are deliberately `focus_mode = None`, or a
button holding focus after a click would swallow Space to press itself again
instead of switching mode.

## Tuning

Everything else lives in `resources/vehicles/default_car.tres`
(a `CarStats` resource). Duplicate it and assign it to a `Car` node's `stats`
property to make a different vehicle without touching the scene tree.

Two rules of thumb, since the units are pixel-space and not intuitive:

- **Spring stiffness** is force per pixel of compression. The two springs
  together hold up `chassis_mass * gravity`, so sag ≈ `chassis_mass * gravity /
  (2 * stiffness)`. At the defaults (4 × 1400 ÷ 1000) that is ~4 px.
- **Motor torque** must beat `total_mass * gravity * sin(slope) * wheel_radius`.
  Climbing a 30° hill on a 16 px wheel needs ~45,000 — which is why the default
  is 90,000 and not the ~9,000 that "feels" right.

Terrain steepness is `amplitude * TAU / hill_length` on the `Terrain` node.
The defaults (130 / 1400) give roughly 30° faces. Keep `detail_strength` low:
the detail octave runs at 4× the frequency, so it contributes 4× as much to
*slope* as it does to height, and it is what turns pleasant hills into walls.

`TerrainGenerator` is a `@tool` script — edit those values in the inspector and
the track rebuilds live.

For a track that has to go somewhere in particular rather than wherever the seed
takes it, put `TerrainAuthor` on `Terrain` instead. It takes the track as a list
of shapes and drives them end to end, deriving the track's length from them —
either written out a line at a time in `shape_text`:

```
flat 400
up   1200 14
down 2400 18
```

or as `(kind, length, steepness)` triples in `shapes` (`0` flat, `1` up, `2`
down, length in pixels, steepness in degrees). The text field wins where both
are filled in, and greys the array out to say so. `corner_blend` rounds the join between each pair of shapes, so
the ground has no kinks in it for the car to nose into. Everything else on the
node is the same, because everything else is `TerrainBase`'s: gaps, ramps, hand
edits, the spawn pad, the run-out, the wall and the finish line all work
identically on both. See [Authoring.md](Authoring.md).

`Collision`, `Fill` and `Surface` under `Terrain` are *outputs*: the generator
rewrites their points on every build, so nothing drawn onto them by hand
survives. The end wall and the finish post are generated too and have no nodes in
the scene at all — the wall is painted by `Terrain`'s own `_draw()`, so it shows
in the editor viewport as well as in game, and only its collision shape is a
child (a shape counts on a body only when it is a direct child of it). Hand edits go on the optional `Edits` `Path2D` instead, which is read
on every build and never written to. Each of its points pins the ground to that
height and eases back to the generated profile over `edit_falloff` (or over the
point's own handles), which is how a track gets a flat run-out at the finish or a
level landing after a jump without giving up the noise around it. Anchors land on
the 48 px segment grid, so this is for sparse features, not sculpting — see
[Authoring.md](Authoring.md#hand-edits-optional).

## Tests

`tests/smoke_test.gd` runs the real `main.tscn` headlessly and asserts the car
settles upright at a sane ride height, drives forward under throttle, clears
150 m of hills in 20 s, burns fuel only while the throttle is held, refuses to
drive on an empty tank, restarts and clears the record from the HUD buttons,
saves and reloads the tuning, drops the record when the tuning changes but not
when it is merely restored, keeps the fuel bill on screen and hides the knobs in
Play mode, plays music for the length
of a run and survives being pointed at a track that is not there, walks to the
next level with its own car settings, record and drivable terrain,
clears the gaps on the one track that has them and drives the authored track end
to end after checking the ground against the shape list that describes it,
records a score only when the car crosses the finish line
and only once the player restarts, keeps a finished run on the course against the
end wall without adding to its settled bill, drives again afterwards,
auto-recovers from landing on its roof, sounds the finish, the applause, the
waiting bed, the wall and a lost run on a player that leaves the music playing,
and survives a reset with its wheelbase intact. Most of those checks correspond to a bug
that was actually present during setup, so keep them if you retune.

## Not included

No art, menus, level progression, or export presets — this is the physics
skeleton only. `assets/sprites` is an empty placeholder, and
the car and terrain are drawn procedurally so the project runs with zero assets.
