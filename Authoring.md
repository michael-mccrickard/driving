# Authoring levels

How to add a track to the game. Everything here assumes the existing car
(`scenes/vehicles/car.tscn`) is being reused, so no vehicle work is involved.

A level is **three edits**:

1. a **track scene** — `scenes/levels/<name>.tscn`, copied from an existing one;
2. a **level config** — `resources/levels/<name>.tres`, copied from an existing
   one, pointing at that scene;
3. one line in the `levels` array in `scripts/main.gd`.

Nothing else needs touching. `main.gd` instances the track as `Level` and the car
as `Car` at runtime, reads the spawn point and the finish line off the terrain,
applies the level's car rules, and points the HUD and `GameState` at it.

---

## 1. The track scene

Copy the closest existing track and edit it. In the Godot editor: select the file
in the FileSystem dock and `Ctrl+D`. On disk, `cp` is equally safe — these scenes
reference only a script path, so there is nothing UID-shaped to break.

| Copy this | If you want |
| --- | --- |
| `scenes/levels/hills.tscn` | plain rolling hills, no gaps |
| `scenes/levels/dune_run.tscn` | longer, lazier swells |
| `scenes/levels/high_country.tscn` | a track with **jumps** in it |
| `scenes/levels/denver.tscn` | a track shaped **by hand**, shape by shape — see [Authored tracks](#authored-tracks-terrainauthor) |

Then, in the copy:

- **Rename the root node** (`Hills` → `SaltFlats`, or whatever). Cosmetic —
  `main.gd` renames it to `Level` on instancing — but a scene tree full of nodes
  called `Hills` gets confusing fast.
- **Leave everything else named exactly as it is.** The structure is contractual:

```
Root (Node2D)
├── Backdrop (CanvasLayer, script = backdrop.gd, layer = -100)
└── Terrain (StaticBody2D, script = terrain_generator.gd, layer 1, mask 0)
    ├── Collision (CollisionPolygon2D)
    ├── Fill      (Polygon2D)
    ├── Surface   (Line2D)
    └── Edits     (Path2D) -- optional, hand edits; see below
```

The script on `Terrain` is the one choice in that tree. `terrain_generator.gd`
gives rolling hills out of noise and is what every level so far uses;
`terrain_author.gd` takes a written list of slopes and flats instead — see
[Authored tracks](#authored-tracks-terrainauthor). Both extend `terrain_base.gd`,
which is everything else on the node, so the tree, the child names and all the
exports below except the shape of the ground itself are identical either way.

`main.gd` looks up `Terrain` by name and errors out if it is missing or is not a
`TerrainGenerator`. The generator looks up its own children by name and warns if
`Collision` is absent. `Collision`, `Fill` and `Surface` are left empty in the
scene file on purpose — they are **outputs**, and the generator fills in their
points every time it builds, so anything drawn onto them by hand is gone by the
next rebuild. `Edits` is the opposite: an **input**, read on every build and
never written to. That is the only place a track is shaped by hand.

Now tune the exports on **`Terrain`**. `TerrainGenerator` is a `@tool` script, so
in the editor the track rebuilds the instant you change one.

### Shape

`segment_count`, `amplitude`, `hill_length`, `detail_strength` and `noise_seed`
are `TerrainGenerator`'s — an authored track has a shape list where those would
be, and everything else in this table.

| Export | What it does |
| --- | --- |
| `segment_count`, `segment_width` | Track length is `segment_count * segment_width` px. Divide by 32 for metres. 500 × 48 = 750 m; 600 × 48 = 900 m. |
| `amplitude`, `hill_length` | Peak-to-centre height, and crest-to-crest distance. Steepest face ≈ `amplitude * TAU / hill_length`. 130 / 1400 ≈ 30°. |
| `detail_strength` | Fine bumps as a fraction of `amplitude`. **Keep it under ~0.08.** The detail octave runs at 4× the frequency, so it contributes 4× as much to *slope* as it does to height — this is the knob that turns hills into walls. |
| `flat_start_segments` | Leading segments held flat for the spawn pad. Must cover `main.gd`'s `spawn_offset_x` (160 px): at 48 px segments, 6 is the floor, and 6 is what every existing track uses. |
| `flat_end_segments` | Trailing segments held flat as the **run-out**, with the finish line at its near end and the wall across its far end. This is how much room a finished run has to shed its speed in: 12 × 48 px = 18 m. 0 puts the line hard against the wall. |
| `wall_height`, `wall_thickness` | The wall closing the course. It only has to be tall enough that a car coming along the run-out cannot get over it — 200 px is well clear. 0 leaves the end open, which means a finished run drives off the cliff. To cover it with art instead, keep the height and clear `wall_visible` (Appearance) — do **not** zero the height, or there is nothing behind the sprite to stop the car. |
| `noise_seed` | Give each level its own. Two levels sharing a seed *and* a shape are the same track twice. |
| `fill_depth` | How far the solid ground extends below the **lowest point the track reaches**, so it follows a descending course down rather than being a fixed depth below the start. The default 2400 is deep enough for anything; it is worth turning down only on a level whose art needs to show what is under the ground. |

### Appearance

`finish_colour` and `finish_post_height` are the post drawn on the finish line —
the only thing telling the player where the line is. A height of 0 leaves it
undrawn, which is worth doing only on a level that marks the line some other way.
`wall_colour` and `wall_visible` are the end wall's paint. Clearing `wall_visible`
hides the grey rectangle and changes nothing else: the collision shape is built
either way, so a level that covers the end of the course with its own sprite
still stops the car exactly where it did.

Neither has a node in the scene. The post is a generated child like the gap
pieces; the **wall is painted by `Terrain`'s own `_draw()`**, deliberately, so
that it appears in the editor viewport as reliably as it does in game — a
generated child is built once in `_ready()`, which the editor does not run again
after a script reload or on a scene that was already open. Only the wall's
collision shape is a child, because a shape counts on a body only when it is a
direct child of it.

`fill_colour`, `surface_colour` and `surface_thickness` on `Terrain` are the real
values — the generator writes them into the `Fill`, `Surface` children on every
build. The colours you see stored on those child nodes in the `.tscn` are just
what the editor last wrote there; keep them in sync if you like tidy diffs, but
they have no effect at runtime.

### Gaps (optional)

`gaps` is a `PackedVector2Array` of **(start_x, width)** pairs in local pixels —
runs of track with nothing under them. `high_country.tscn` has two:

```
gaps = PackedVector2Array(5716, 332, 17908, 332)
gap_ramp_height = 140.0
gap_ramp_length = 288.0
```

Each pair becomes a break: the ground stops at the near lip and starts again at
the far one, with the underlying profile carrying on in phase underneath — so a
gap cut across a crest lands *lower* than it takes off.

Three things to get right:

- **Always give a gap a ramp.** `gap_ramp_height` lifts the ground over the
  `gap_ramp_length` of run-up before each lip, squared so it is steepest exactly
  at the edge and the car leaves pointing up. Without one the car just drives off
  the lip — a parabola at driving speed falls faster than rolling hills do, so
  nothing on the natural profile is steep enough to throw it. The ramp settings
  are global to the level, not per gap.
- **Keep gaps inside the track**, clear of the flat start and clear of the end.
  Gaps that swallow the whole profile are ignored with a warning.
- **A gap has to be clearable at a pinned throttle**, or the smoke test hangs on
  it and fails — see [Tests](#5-check-it) below. 332 px behind a 140/288 ramp is
  the known-good starting point; widen from there and drive it.

### Authored tracks (TerrainAuthor)

Noise gives a track that is *like* something. When a track has to be a
particular thing — climb out of the start, level off, drop into a long descent,
kick up at the end — put `terrain_author.gd` on `Terrain` instead of
`terrain_generator.gd` and write the shapes down.

There are **two fields** to write that list in, and a track uses whichever one it
has. They mean exactly the same thing; the difference is only what it is like to
type.

#### As text — `shape_text`

One shape per line: a word, a length in pixels, and for the two slopes a
steepness in degrees.

```
# out of the pad
flat 400
up   1200 14
flat 300

# into the descent
down 2400 18
up   700 24        # steepness omitted -> default_steepness
down 700
```

- The words are **`flat`**, **`up`** and **`down`**. Case does not matter.
- Blank lines are skipped, and anything after a `#` is a comment. Tabs and runs
  of spaces line the columns up however you like.
- A steepness on a `flat` is ignored, and the node says so rather than leaving
  you to wonder.
- **A line that will not parse is skipped and named**, by line number, in the
  scene tree — `Line 4: 'slope' is not one of flat, up, down.` The rest of the
  track still builds, so one typo does not cost you the level.

While there is anything in this field it is the **input**, and `shapes` below is
an **output** filled in from it — greyed out in the inspector, the same way
`Collision`, `Fill` and `Surface` are outputs of the build. Empty the field and
the array goes back to being the thing you edit. The two cannot disagree about
what got built: `readout` says which one is in effect.

#### As triples — `shapes`

The same list as a `PackedVector3Array` of **(kind, length, steepness)**:

| | |
| --- | --- |
| **kind** | `0` Flat, `1` SlopeUp, `2` SlopeDown |
| **length** | horizontal run in pixels — the run, not the distance up the face — rounded **up** to a whole `segment_width` |
| **steepness** | degrees from horizontal. Ignored by Flat; `0` means "use `default_steepness`" |

```
shapes = PackedVector3Array(0, 300, 0, 1, 600, 16, 0, 200, 0, 2, 900, 20, 1, 500, 24)
default_steepness = 18.0
corner_blend = 150.0
```

That reads as: 300 px of flat, climb 600 at 16°, 200 flat, drop 900 at 20°, then
kick up 500 at 24° — `flat 300 / up 600 16 / flat 200 / down 900 20 / up 500 24`
written the other way. Five shapes, 73 segments, 109 m of track, running between
4.5 m below the spawn pad and 5.6 m above it and finishing 2.6 m up. Those
numbers are not arithmetic you have to do: the node's **`readout`** field says
them, and updates on every rebuild.

Editing 20 rows of x/y/z in the inspector is the reason `shape_text` exists.
Reach for the array when a track only needs two or three shapes, or when
something else is generating the numbers.

`scenes/levels/denver.tscn` is the worked example, and the track the smoke test
drives to check that an authored list really produces the ground it describes.
Copy it and start rewriting the list.

- **Track length is derived** from the shapes, so there is no `segment_count`.
  `flat_start_segments` and `flat_end_segments` still bracket the list — spawn
  pad on the front, run-out on the back — so the finish line, the post and the
  end wall land exactly where they do on a noise track, and the shape list is
  only the drive between them.
- **Joins are rounded**, by `corner_blend` (px). Sampled raw, a shape list has a
  kink at every join: the car noses into each valley floor and launches off each
  crest. The profile is built by integrating slope rather than interpolating
  height, so blending eases one shape's slope into the next across the join and
  the ground comes out with no corners in it at all.
- **Rounding does not cost you height.** The ease is symmetrical about the join,
  so the rise borrowed before it is exactly the rise given back after it, and
  every shape still ends at the height it asked for. What it takes off is the
  point of the crest or the bottom of the trough *at* a join, which is the
  intention.
- **A join can only be rounded as far as its shorter neighbour allows** — half
  its length, so neighbouring joins never fight over the same ground. A run of
  100 px shapes stays jagged however high `corner_blend` goes; that is a sign the
  shapes are too short, not that the blend is too low.
- **Steepness is in degrees**, which is the number worth knowing: much past 30°
  is a face the car cannot climb. The node says so in the scene tree, per shape,
  rather than leaving you to find it on the hill.
- **Lengths under one segment** (48 px) are held at one segment and called out.
  Shapes are laid out on the same grid as everything else, the same way `Edits`
  anchors are.
- **Everything else works unchanged**: `gaps` and their ramps, the `Edits` path,
  the wall, the colours, `fill_depth`. Composition order is shapes, then hand
  edits, then gap ramps, then gaps — so an anchor can still flatten a landing on
  an authored track, and a gap still wins over both.
- `gaps` is still **absolute local X**, while shapes are relative lengths. Place
  them by driving the track and reading positions off the viewport rather than by
  adding the lengths up, and re-check them after inserting a shape earlier in the
  list — everything downstream of the insertion has moved.
- **Descending a long way is fine.** `fill_depth` is measured from the lowest
  point the track reaches, not from the height it starts at, so a course that
  drops 100 m has solid ground under its far end without touching the setting.

Steepness in degrees converts to torque the same way as anything else: a 30°
face on a 16 px wheel is the ~45,000 the `motor_torque` note in `README.md`
talks about. If a slope will not climb, that is where to look before blaming the
shape list.

### The backdrop

`Backdrop` is the sky: a `CanvasLayer` on layer `-100`, so it is drawn behind
everything and, being a canvas layer, **does not move with the camera**. It is
scenery at infinity — the stars stay put while the car drives. Anything that
should slide past as you drive is parallax and wants a `Parallax2D` under the
root instead; this is not that layer.

It is procedural like the terrain and runs as `@tool`, so it redraws in the
editor as you change it.

| Export | What it does |
| --- | --- |
| `backdrop_seed` | **Give each level its own**, or two levels drive under the same sky. |
| `star_count`, `star_size`, `star_size_spread` | How many, how big, and how much they vary. All one size reads as a texture rather than as a sky. |
| `star_field_height` | Fraction of the screen, from the top, stars are scattered over. Below that is where the hills are and a star there is just a speck the terrain hides. |
| `star_faintest`, `star_colour` | Alpha of the dimmest stars, and the colour they are all tinted. |

Stars are the only element so far. To add another — a moon, a horizon glow, a
skyline — put its exports in a group of its own in `scripts/levels/backdrop.gd`,
write a `_paint_<thing>()` beside `_paint_stars()`, and call it from `_paint()`
in back-to-front order. Draw in fractions of the size `_paint()` hands you
rather than in absolute pixels: the stretch aspect is `expand`, so a wide window
really is shown more sky than the 1280 × 720 design size.

### Hand edits (optional)

For the things noise will not give you on request — a level run-out at the
finish, a flat landing after a jump, a shelf where you want one — drag points
onto the **`Edits`** `Path2D` under `Terrain`. Every track scene ships with an
empty one, so copying an existing track brings it along.

Each point is an **anchor**: the ground is pinned to that point's height and
eased back to the generated profile either side of it. Select `Edits` in the 2D
viewport and use Godot's own path tools — the generator rebuilds the instant a
point moves, so you shape the track by dragging it and watching.

- **Reach** is `edit_falloff` on `Terrain` (400 px by default), or, per side, the
  length of that point's `in` / `out` handle if you drag it out. Short reach
  makes a sharp step; long reach makes a slow bend into the new height.
- **X is quantized to the segment grid** (48 px), because anchors are sampled at
  the same X positions as everything else. Features narrower than a segment or
  two cannot be expressed — this is for sparse edits, not sculpting.
- **Order of composition** is noise, then anchors, then gap ramps, then gaps.
  An anchor can flatten a landing but cannot take away the ramp that throws the
  car at one, and a gap always wins: no anchor puts ground back into a hole.
- **The path never renders in game** — it is an editor-only node. Leave it at
  position (0, 0) unless you mean to move every anchor at once, and unrotated:
  only its position is read.
- **Editing a track invalidates what its records meant**, the same way retuning
  it does; nothing clears them for you.

If you add the `Edits` node to a track that has not got one while the scene is
open, nudge any export on `Terrain` once. The generator picks the path up on its
next build, and adding a node is not one.

---

## 2. The level config

Copy `resources/levels/hills.tres` to `resources/levels/<save_id>.tres`. This is
a `LevelConfig` (`scripts/levels/level_config.gd`) — the track, the car, what the
car may spend on this level, and the music.

```ini
[gd_resource type="Resource" script_class="LevelConfig" load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/levels/level_config.gd" id="1_config"]
[ext_resource type="PackedScene" path="res://scenes/levels/salt_flats.tscn" id="2_track"]
[ext_resource type="PackedScene" path="res://scenes/vehicles/car.tscn" id="3_car"]

[resource]
script = ExtResource("1_config")
display_name = "Salt Flats"
save_id = "salt_flats"
track = ExtResource("2_track")
car = ExtResource("3_car")
fuel_capacity = 100000.0
burn_rate = 0.001
max_speed_kmh = 81.0
music = "default.mp3"
```

Change `path` on the `2_track` line to the new scene, and:

- **`display_name`** — what the HUD shows, so the record on screen can be told
  apart from the others.
- **`save_id`** — the key this level's record and tuning are saved under, as
  `[level_<save_id>]` in `user://save.cfg`. **Must be unique**, and treat it as
  permanent once anyone has played the level: changing it orphans their record.
  Lowercase, no spaces.
- **`car`** — leave it pointing at `scenes/vehicles/car.tscn`.
- **`fuel_capacity` / `burn_rate` / `max_speed_kmh`** — the *rules of this level*,
  applied over the car scene's own `CarStats` at load. `CarStats` stays the
  vehicle (mass, torque, springs, torque curve); these three are what the level
  gets to say about it. Unless the level is deliberately about a different engine,
  copy the defaults above — a record only means anything against runs charged the
  same rates, and levels that share rates are comparable to each other.
  Keep `fuel_capacity` bottomless (100,000 against a flat-out run's ~104): running
  dry is not meant to be what ends a run, and the smoke test asserts ≥ 10,000.
- **`music`** — a bare filename is looked up in `assets/audio/`
  (`default.mp3`, `dunes.mp3`, `track3.mp3` are there now). Anything with a
  scheme or a leading slash is taken as a full path. A missing file leaves the
  game silent and logs one warning, so a typo here cannot stop anyone driving.
  New mp3s can be dropped into `assets/audio/` and named here without an editor
  import pass — unimported mp3s are decoded straight off disk.

If you hand-edit the `.tres` rather than using the editor, keep `load_steps`
equal to the number of `ext_resource` lines plus one.

---

## 3. Register it

`main.gd` holds the list, one readable line per level:

```gdscript
@export var levels: Array[LevelConfig] = [
	preload("res://resources/levels/hills.tres"),
	preload("res://resources/levels/dunes.tres"),
	preload("res://resources/levels/high_country.tres"),
	preload("res://resources/levels/salt_flats.tres"),
]
```

This is the order **NEXT** walks, wrapping round at the end. Two notes:

- **Append rather than insert.** The smoke test reads `levels[0]` and `levels[1]`
  directly and expects them to be two distinct, drivable tracks; it also drives
  the *first* level that has gaps in it. Putting a new level at the front changes
  what those checks are testing.
- `levels` is an `@export`, but `main.tscn` does not override it, so editing this
  array is the whole job. If you ever set the array on the `Main` node in the
  inspector, the scene value wins from then on and edits here stop taking effect.

Adding a level costs nothing in the save file: an unplayed level simply has no
`[level_...]` section and shows `best  --` until something crosses its line.

---

## 4. What you get for free

Worth knowing so you do not go looking for the wiring:

- **Spawn point** — `main.gd` drops the car on the surface at `spawn_offset_x`
  (160 px), 80 px up. That is why the flat start pad has to cover it.
- **Finish line** — `TerrainGenerator.finish_x()`, the near end of the flat
  run-out, with a post drawn on it. The run is over as soon as **any part of the
  car** is past it (`Car.get_front_x()`), and the fuel bill is locked in at that
  instant. There is no finish-line node to place.
- **The end wall** — generated at `end_x()`, across the far end of the run-out.
  The car is left driveable after the line and rolls to a stop against it;
  hitting it costs nothing, and the HUD goes on showing the settled bill rather
  than what the car spends afterwards. Nothing to place here either.
- **Falling out of the world** — anything below `fall_limit_metres` (40 m) under
  the spawn height restarts an unfinished run.
- **Stall recovery** — resting upside down or out of fuel restarts the run after
  `auto_recover_seconds`.
- **Record and tuning** — kept per `save_id` by `GameState`, swapped wholesale on
  load. Nothing per-level to add.

And one thing that is *not* free: **a player's saved tuning overrides the config.**
`_apply_saved_tuning()` runs after the level's `burn_rate` / `max_speed_kmh` are
applied, so once someone has edited those fields on this level, the stored values
win on every subsequent load. Authored values are the starting point, not a
guarantee.

---

## 5. Check it

```sh
godot --path .                                  # drive it: NEXT round to the new level
godot --headless res://tests/smoke_test.tscn    # exits 0/1
```

If the scene and resource were added with the editor closed, one
`godot --headless --import` first is a safe habit.

Drive the whole track at least once, on a pinned throttle, before calling it
done. The things that only show up that way:

- a face the car cannot climb (`detail_strength` too high, or
  `amplitude / hill_length` past ~30°);
- a gap it cannot clear (raise `gap_ramp_height`, or narrow the gap);
- a spawn pad that ends in a step the car noses into;
- a run-out the car can get *over* the wall from — arriving off a jump rather
  than along the flat. Raise `wall_height`, or give the run-out another segment
  or two so the car has landed before it gets there.

Then check the run is worth scoring: pinned throttle should finish, but cost an
order of magnitude more than pulse-and-glide does. A track that is cheapest flat
out is not a level of this game.

The smoke test's level checks — `_next_level_switches_everything`,
`_the_gaps_can_be_jumped` and `_the_authored_track_is_what_was_written` — will
exercise a new track automatically if it lands at index 0 or 1, is the first
level with gaps, or is the first authored one. Appending keeps it out of their
way, so a new level does not silently change what they assert.

The authored check works entirely off the shape list it finds, so editing
Denver's shapes cannot break it: it re-derives the length, the net height and the
steepest face from the exports, asserts the built ground matches all three, that
`corner_blend` has kept the joins under 20°, that the node has no configuration
warnings, and then drives the whole thing at a pinned throttle.

---

## Checklist

- [ ] `scenes/levels/<name>.tscn` — root renamed, `Backdrop` and `Terrain` + its
	  children named exactly as before, exports tuned, own `noise_seed` **and**
	  own `backdrop_seed`, any hand edits dropped onto `Edits`
- [ ] On an authored track: no warnings left on `Terrain` in the scene tree, and
	  the `readout` length is the track you meant to build — and, if the shapes
	  were written as text, nothing left in `shapes` pretending otherwise
- [ ] Run-out driven: the car crosses the line and the wall holds it on the
	  course
- [ ] `resources/levels/<save_id>.tres` — `track` repointed, `display_name` set,
	  **unique** `save_id`, `car` left on `car.tscn`, rules copied from `hills.tres`
	  unless the level is deliberately different, `music` named
- [ ] `preload(...)` line **appended** to `levels` in `scripts/main.gd`
- [ ] Driven end to end, and the gaps (if any) cleared at a pinned throttle
- [ ] `godot --headless res://tests/smoke_test.tscn` exits 0
- [ ] `README.md` updated — the level table, the count in the intro, and the
	  `scenes/levels/` and `resources/levels/` lines in Layout
