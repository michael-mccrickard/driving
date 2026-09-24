@tool
class_name TerrainAuthor
extends TerrainBase
## Hand-authored terrain: a list of shapes, driven end to end in the order they
## are written. Where TerrainGenerator says "hills about this steep and let the
## seed decide", this says "up 600 px at 18 degrees, 300 flat, then down 900 at
## 24" -- for a track that has to go somewhere in particular.
##
## There are two ways to write that list down, and a track uses whichever one it
## has: `shape_text`, a line per shape in words, or `shapes`, the same list as
## (kind, length, steepness) triples. Text wins where both are filled in, and
## the array is greyed out to say so. Either way what the ground is built from
## is shape_list(), and the shapes themselves mean exactly the same thing.
##
## Everything that is not the shape of the ground is TerrainBase's, and is
## shared with TerrainGenerator: the collision and visuals, the gaps and their
## launch ramps, the Edits path, the spawn pad, the run-out, the finish line and
## the end wall. An authored track is otherwise an ordinary level -- same
## children, same node name, same LevelConfig -- with this script on Terrain.
##
## Three things are worth knowing before authoring one:
##
## The track's *length is derived* from the shapes, so there is no
## segment_count here. flat_start_segments and flat_end_segments still bracket
## it: the spawn pad goes on the front and the run-out on the back, so the
## finish line and the end wall land where they always did and the shape list is
## only the drive between them.
##
## Joins are *rounded*, by corner_blend. Sampled raw, a shape list is a
## piecewise-linear profile with a kink at every join -- the car noses into the
## bottom of each valley and launches off every crest. So the profile is built
## by integrating slope rather than by interpolating height: each shape
## contributes a constant slope, adjacent slopes are eased into one another
## across the join, and the ground that comes out has no corners in it at all.
##
## Rounding costs nothing in height: the ease is symmetrical about the join, so
## the rise borrowed from the shape before it is exactly the rise given back to
## the shape after, and every shape still ends at the height it asked for. What
## the rounding does take off is the point of a crest or the bottom of a
## trough *at* a join -- which is the whole intention. Turn corner_blend down
## for sharper shapes; note that a join can only be rounded as far as its
## shorter neighbour allows, so a run of very short shapes stays jagged however
## high it is set.
##
## Steepness is in *degrees*, so it can be read against the one number that
## matters: much past 30 degrees is a face the car cannot climb.
##
## A flat may also be given the *height it sits at* -- `flat 300 -240`, or a
## FLAT_AT triple -- measured up-positive from the spawn pad, the same way the
## readout reports heights. The flat then starts exactly there rather than
## wherever the shape before it happened to end, and the ground steps up or down
## into it over the one segment before the join: a hard riser, not a ramp, so a
## list of levelled flats is a staircase. A step up much past 30 degrees over
## that segment is a wall the car cannot climb, and is called out on the node;
## a step down is a drop, which is usually the point.

## Local metres, for the configuration warnings. Reached through the script
## rather than the GameState autoload name, because autoloads do not exist in
## the editor and this runs there.
const GameStateScript := preload("res://scripts/autoload/game_state.gd")

## Kinds of shape, and the number that selects one in the x of each entry in
## `shapes`. What the z of an entry means depends on the kind: degrees to the two
## slopes, a height to a levelled flat, and nothing at all to a plain flat.
enum Shape {
	## 0 -- level ground, length only, carrying on from the shape before it.
	FLAT,
	## 1 -- climbs at `steepness` degrees.
	SLOPE_UP,
	## 2 -- drops at `steepness` degrees.
	SLOPE_DOWN,
	## 3 -- level ground held at the height in z, up-positive from the spawn pad,
	## with a step up or down into it. What a staircase is made of.
	FLAT_AT,
}

## The words `shape_text` takes, and the kind each one means. Lower case; the
## parser folds what it reads before looking it up here.
const SHAPE_WORDS := {
	"flat": Shape.FLAT,
	"up": Shape.SLOPE_UP,
	"down": Shape.SLOPE_DOWN,
}

## The steepest face the car can be relied on to climb, in degrees. Not enforced
## -- a level may want a wall -- but anything past it is called out in the scene
## tree, because it is almost always a mistake.
const DRIVABLE_STEEPNESS := 30.0
## Hard ceiling on a shape's steepness. Past this a "slope" is a cliff, and the
## surface polygon starts folding back on itself.
const MAX_STEEPNESS := 80.0
## What an empty shape list falls back to, so a track being authored always has
## ground on it rather than nothing to drive.
const FALLBACK_SEGMENTS := 64

@export_group("Shapes")
## What the shape list below adds up to, filled in on every build. Editor-only
## and read-only -- it is a readout, not a setting, and is never saved into the
## level. The numbers that decide whether a shape list is any good are all
## things the list knows and the viewport does not show.
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY)
var readout := ""
## The track written out, one shape per line:
##
##   flat 300
##   up   600 16
##   down 900 20
##   up   500        # no steepness given -> default_steepness
##   flat 300 -240   # a flat 240 px below the pad, stepped down into
##
## The words are `flat`, `up` and `down`; then a length in pixels; then a second
## value, which is a steepness in degrees on the two slopes and the height it
## sits at on a `flat`. Blank lines and anything after a `#` are ignored.
##
## While there is anything here this is the *input*, and `shapes` below is an
## output filled in from it -- greyed out in the inspector, the same way
## Collision, Fill and Surface are outputs of the build. Clear this field and the
## array goes back to being the thing you edit. A line that will not parse is
## skipped and named in the scene tree rather than guessed at.
@export_multiline var shape_text := "":
	set(value):
		var was_authoritative := _text_is_authoritative()
		shape_text = value
		# Only when the field falls empty or stops being empty, which is when the
		# array below changes between editable and read-only. Deliberately not on
		# every keystroke: rebuilding the inspector mid-edit takes the text field
		# out from under whoever is typing into it.
		if was_authoritative != _text_is_authoritative():
			notify_property_list_changed()
		_request_rebuild()
## The track, shape by shape, as (kind, length, value) triples:
##
##   kind      0 Flat, 1 SlopeUp, 2 SlopeDown, 3 FlatAt
##   length    horizontal run in pixels, rounded up to a whole segment_width
##   value     on the two slopes, degrees from horizontal, where 0 reads as
##             "use default_steepness"; on FlatAt, the height the flat sits at,
##             up-positive from the spawn pad; ignored by Flat
##
## So Vector3(1, 600, 18) is "climb for 600 px at 18 degrees", and
## Vector3(3, 300, -240) is "300 px of flat 240 px below the pad", stepped into.
## Length is the run, not the distance travelled up the face, which is what keeps
## the shapes laid out on the same segment grid as everything else. What the list
## adds up to is in `readout` above; anything undrivable in it is called out on
## the node in the scene tree.
##
## Written into from `shape_text` when there is anything in that field, and read
## only as far as the inspector is concerned while there is.
@export var shapes := PackedVector3Array([
	Vector3(0, 300, 0),
	Vector3(1, 600, 16),
	Vector3(0, 200, 0),
	Vector3(2, 900, 20),
	Vector3(1, 500, 24),
]):
	set(value):
		shapes = value
		_request_rebuild()
## Steepness for any shape that leaves its own at 0 -- the same "0 means the
## level default" reading the Edits path gives a handle left where it was
## dropped.
@export_range(0.0, 80.0, 0.5) var default_steepness := 18.0:
	set(value):
		default_steepness = value
		_request_rebuild()
## How much of each join between two shapes is rounded off, in pixels. 0 gives
## the shapes exactly as written, corners and all; the default takes the points
## off without softening the run either side of them. Clamped per join to half
## of the shorter shape it sits between, so a long blend across short shapes
## rounds them rather than swallowing them.
@export_range(0.0, 1200.0, 8.0) var corner_blend := 150.0:
	set(value):
		corner_blend = value
		_request_rebuild()

# The shape list actually in effect: `shape_text` parsed, or `shapes` verbatim
# when that field is empty. Everything below works off this rather than off
# either export, so the two sources cannot disagree about what got built.
var _shapes := PackedVector3Array()
# Which line of `shape_text` each of those shapes came from, so a complaint can
# name the line rather than an index into a list nobody typed. Empty when the
# array is the source.
var _shape_lines := PackedInt32Array()
# What would not parse, in the order it was read.
var _parse_errors := PackedStringArray()
# The shape list as (segment_count, slope, level) runs, with the spawn pad on
# the front and the run-out on the back, and the height at every segment
# integrated out of it. `level` is the height a levelled flat is pinned to, or
# NAN on a run that simply carries on from the one before it. Both settled once
# per build, in _begin_profile().
var _runs: Array[Vector3] = []
var _heights := PackedFloat32Array()
# The rise of the step into each levelled flat, in pixels, keyed by the shape's
# place in the list -- positive up. Only what the profile turned out to need, so
# it is known after the heights are integrated and not before.
var _risers: Dictionary[int, float] = {}


## The shapes that built the ground, whichever field they were written in. Worth
## asking for rather than reading `shapes`, which is empty on a track authored as
## text.
func shape_list() -> PackedVector3Array:
	if _heights.is_empty():
		_rebuild_profile()
	return _shapes


## Whether the text field is the one in charge. Anything at all in it counts:
## a field holding only a comment is still someone authoring in text, and
## reading it as "no shapes" would silently hand the track back to the array.
func _text_is_authoritative() -> bool:
	return not shape_text.strip_edges().is_empty()


## Greys the array out in the inspector while the text field is in use, so there
## is never a question of which of the two built the ground in the viewport.
func _validate_property(property: Dictionary) -> void:
	if property.name == "shapes" and _text_is_authoritative():
		property.usage |= PROPERTY_USAGE_READ_ONLY


func _profile_segments() -> int:
	if _heights.is_empty():
		_rebuild_profile()
	return _heights.size() - 1


func _begin_profile() -> void:
	_rebuild_profile()


func _profile_height(index: int) -> float:
	if _heights.is_empty():
		_rebuild_profile()
	return _heights[clampi(index, 0, _heights.size() - 1)]


## Turns the shape list into a height per segment. Heights are integrated from
## the slope rather than interpolated between the shapes' end points, which is
## what makes the rounding at the joins possible: blend the *slopes* and the
## ground that comes out is continuous by construction, with no kink anywhere
## and no face steeper than the shape it came from asked for.
##
## A levelled flat is the one thing that is *not* integrated: it names the height
## it sits at, so the join it starts on is set to that height outright and the
## integration carries on from there. That leaves the segment before the join as
## the riser -- the step of a staircase, and the only discontinuity a shape list
## can produce.
func _rebuild_profile() -> void:
	_resolve_shapes()
	_runs = _collect_runs()
	_risers.clear()
	var segments := 0
	for run in _runs:
		segments += int(run.x)
	_heights = PackedFloat32Array()
	_heights.resize(segments + 1)
	var index := 0
	var height := 0.0
	_heights[0] = height
	for run_index in _runs.size():
		var run := _runs[run_index]
		if _is_levelled(run):
			# Nothing before the first point to step off, so a track opening on a
			# levelled flat simply starts there.
			var shape_index := _shape_of_run(run_index)
			if index > 0 and shape_index >= 0:
				_risers[shape_index] = run.z - height
			height = run.z
			_heights[index] = height
		for _i in int(run.x):
			# Taken at the segment's centre, so a join is rounded symmetrically
			# about the point the two shapes meet at.
			height += _slope_at((float(index) + 0.5) * segment_width) * segment_width
			_heights[index + 1] = height
			index += 1
	readout = _describe(segments)


## The one-line summary shown on the node: how long the track is, how far it
## climbs and drops, and where it leaves the car relative to the spawn pad.
func _describe(segments: int) -> String:
	return "%d shapes%s, %.0f m, %.1f m to %.1f m, finishing %.1f m up" % [
		_shapes.size(),
		" from text" if _text_is_authoritative() else "",
		GameStateScript.px_to_m(float(segments) * segment_width),
		GameStateScript.px_to_m(_lowest()),
		GameStateScript.px_to_m(_highest()),
		GameStateScript.px_to_m(_heights[segments]),
	]


func _lowest() -> float:
	var lowest := 0.0
	for height in _heights:
		lowest = minf(lowest, height)
	return lowest


func _highest() -> float:
	var highest := 0.0
	for height in _heights:
		highest = maxf(highest, height)
	return highest


## Settles which of the two fields is the track, once per build. The text field
## wins whenever there is anything in it; otherwise the array is taken as
## written.
func _resolve_shapes() -> void:
	_shape_lines = PackedInt32Array()
	_parse_errors = PackedStringArray()
	if not _text_is_authoritative():
		_shapes = shapes
		return
	_shapes = _parse_shape_text()
	# In the editor the complaints are on the node in the scene tree, where they
	# can be read beside the ground they failed to make. A running game has no
	# scene tree to look at, so there they go to the log instead.
	if not _parse_errors.is_empty() and not Engine.is_editor_hint():
		push_warning("%s: %s" % [name, ", ".join(_parse_errors)])


## Reads `shape_text` into shapes. One shape per line, `flat`/`up`/`down` then a
## length then an optional steepness; `#` starts a comment. A line that will not
## parse is skipped and complained about rather than guessed at -- a track with
## one shape missing and a note saying which is easier to fix than a track with
## a shape nobody asked for in it.
func _parse_shape_text() -> PackedVector3Array:
	var parsed := PackedVector3Array()
	var lines := shape_text.split("\n")
	for i in lines.size():
		var line: String = lines[i]
		var comment := line.find("#")
		if comment >= 0:
			line = line.substr(0, comment)
		var words := line.replace("\t", " ").split(" ", false)
		if words.is_empty():
			continue
		var number := i + 1

		var word: String = words[0].to_lower()
		if not SHAPE_WORDS.has(word):
			_parse_errors.append(
				"Line %d: '%s' is not one of flat, up, down." % [number, words[0]]
			)
			continue
		var kind: int = SHAPE_WORDS[word]
		if words.size() < 2:
			_parse_errors.append("Line %d: %s needs a length in pixels." % [number, word])
			continue
		if not words[1].is_valid_float():
			_parse_errors.append(
				"Line %d: '%s' is not a length in pixels." % [number, words[1]]
			)
			continue
		if words.size() > 3:
			_parse_errors.append("Line %d: '%s' is one value too many." % [number, words[3]])
			continue

		var value := 0.0
		if words.size() > 2:
			if not words[2].is_valid_float():
				_parse_errors.append(
					"Line %d: '%s' is not a %s." % [
						number,
						words[2],
						"height in pixels" if kind == Shape.FLAT else "steepness in degrees",
					]
				)
				continue
			value = words[2].to_float()
			# A flat given a second value is a flat that says where it sits, which
			# is a different shape from one that carries on where the last left off.
			if kind == Shape.FLAT:
				kind = Shape.FLAT_AT

		parsed.append(Vector3(kind, words[1].to_float(), value))
		_shape_lines.append(number)
	return parsed


## How to name one shape in a complaint: the line it was written on when the
## track came from text, or its place in the array when it did not.
func _shape_label(index: int) -> String:
	if index < _shape_lines.size():
		return "Line %d" % _shape_lines[index]
	return "Shape %d" % index


## The shape list as runs of segments at a constant slope, bracketed by the
## spawn pad and the run-out. Lengths are quantized up to whole segments -- a
## shape shorter than segment_width cannot be expressed, the same way an Edits
## anchor cannot express a feature narrower than one -- and empty runs are left
## out rather than kept as joins between nothing and nothing.
func _collect_runs() -> Array[Vector3]:
	var runs: Array[Vector3] = []
	if flat_start_segments > 0:
		runs.append(Vector3(flat_start_segments, 0.0, NAN))
	for shape in _shapes:
		runs.append(Vector3(_shape_segments(shape), _shape_slope(shape), _shape_level(shape)))
	if flat_end_segments > 0:
		runs.append(Vector3(flat_end_segments, 0.0, NAN))
	if runs.is_empty():
		push_warning("%s: no shapes and no flats; falling back to a flat pad." % name)
		runs.append(Vector3(FALLBACK_SEGMENTS, 0.0, NAN))
	return runs


## Which shape a run came from, or -1 for the spawn pad and the run-out, which
## bracket the list rather than being part of it.
func _shape_of_run(run_index: int) -> int:
	var shape_index := run_index - (1 if flat_start_segments > 0 else 0)
	if shape_index < 0 or shape_index >= _shapes.size():
		return -1
	return shape_index


## Whether a run is pinned to a height of its own rather than carrying on from
## the run before it.
func _is_levelled(run: Vector3) -> bool:
	return not is_nan(run.z)


## Segments one shape covers. At least one: a shape asking for less than that
## would otherwise vanish, taking its join with it.
func _shape_segments(shape: Vector3) -> int:
	return maxi(1, ceili(maxf(shape.y, 0.0) / segment_width))


## Rise over run for one shape, up-positive. Both kinds of flat are level, and an
## unrecognised kind reads as flat too, with the complaint left to the scene tree
## rather than pushed once per build.
func _shape_slope(shape: Vector3) -> float:
	var kind := _shape_kind(shape)
	# Only the two slopes read z as a steepness: on a levelled flat it is the
	# height the shape sits at, which is the profile's business, not the slope's.
	if kind != Shape.SLOPE_UP and kind != Shape.SLOPE_DOWN:
		return 0.0
	var steepness := clampf(shape.z if shape.z > 0.0 else default_steepness, 0.0, MAX_STEEPNESS)
	return tan(deg_to_rad(steepness)) * (1.0 if kind == Shape.SLOPE_UP else -1.0)


## The height a shape holds its ground at, or NAN for one that carries on from
## wherever the shape before it ended. Only a levelled flat has one.
func _shape_level(shape: Vector3) -> float:
	return shape.z if _shape_kind(shape) == Shape.FLAT_AT else NAN


func _shape_kind(shape: Vector3) -> int:
	return int(roundf(shape.x))


## Slope of the ground at a local X, with the joins between shapes rounded off.
## Inside a join's reach this eases from the slope before it to the slope after
## it -- half way through at exactly the point the two shapes meet -- and
## outside one it is simply the shape's own slope.
func _slope_at(local_x: float) -> float:
	var start := 0.0
	for i in _runs.size():
		var run := _runs[i]
		var end := start + run.x * segment_width
		if local_x < end or i == _runs.size() - 1:
			var reach_in := _joint_reach(i)
			if reach_in > 0.0 and local_x < start + reach_in:
				return lerpf(
					_runs[i - 1].y,
					run.y,
					smoothstep(0.0, 1.0, 0.5 + (local_x - start) / (2.0 * reach_in))
				)
			var reach_out := _joint_reach(i + 1)
			if reach_out > 0.0 and local_x > end - reach_out:
				return lerpf(
					run.y,
					_runs[i + 1].y,
					smoothstep(0.0, 1.0, (local_x - (end - reach_out)) / (2.0 * reach_out))
				)
			return run.y
		start = end
	return 0.0


## How far either side of the join between run `index - 1` and run `index` the
## rounding reaches. Never more than half of the shorter of the two, so the
## reaches of neighbouring joins cannot overlap and a shape between two others
## keeps some of its own slope. 0 where there is no join to round: the ends of
## the track, two shapes that already share a slope, and the step into a levelled
## flat.
func _joint_reach(index: int) -> float:
	if index <= 0 or index >= _runs.size():
		return 0.0
	var before := _runs[index - 1]
	var after := _runs[index]
	# A levelled flat begins at the height it names, so this join is a riser and
	# there is no corner to take off: rounding a step would only smear it either
	# side of the join it belongs to, and leave the flat sitting off its height.
	if _is_levelled(after):
		return 0.0
	if is_equal_approx(before.y, after.y):
		return 0.0
	return minf(
		corner_blend * 0.5,
		minf(before.x, after.x) * segment_width * 0.5
	)


## Anything in the shape list that will not drive, shown on the node in the
## scene tree. Problems only -- what the list adds up to is the `readout` field
## above, so a warning on the node goes on meaning something is wrong with it.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if _heights.is_empty():
		_rebuild_profile()

	warnings.append_array(_parse_errors)
	for i in _shapes.size():
		var shape := _shapes[i]
		var kind := _shape_kind(shape)
		if kind < Shape.FLAT or kind > Shape.FLAT_AT:
			warnings.append(
				("%s: kind %d is not one of 0 Flat, 1 SlopeUp, 2 SlopeDown, 3 FlatAt;"
					+ " treated as Flat.")
				% [_shape_label(i), kind]
			)
		if shape.y < segment_width:
			warnings.append(
				"%s: length %.0f px is under one segment (%.0f px), so it is held at one."
				% [_shape_label(i), shape.y, segment_width]
			)
		if kind == Shape.SLOPE_UP or kind == Shape.SLOPE_DOWN:
			var steepness: float = shape.z if shape.z > 0.0 else default_steepness
			if steepness > DRIVABLE_STEEPNESS:
				warnings.append(
					("%s: %.0f degrees is past the %.0f the car is good for;"
						+ " the hill or descent may not be drivable.")
					% [_shape_label(i), steepness, DRIVABLE_STEEPNESS]
				)
		# A step *down* into a levelled flat is a drop, which is what stairs are
		# for. A step up is a wall one segment wide, and the car has to be able to
		# climb it like any other face.
		if kind == Shape.FLAT_AT and _risers.get(i, 0.0) > 0.0:
			var rise: float = _risers[i]
			var riser_steepness := rad_to_deg(atan(rise / segment_width))
			if riser_steepness > DRIVABLE_STEEPNESS:
				warnings.append(
					("%s: the %.0f px step up to %.0f is %.0f degrees over one segment,"
						+ " past the %.0f the car can climb.")
					% [
						_shape_label(i),
						rise,
						shape.z,
						riser_steepness,
						DRIVABLE_STEEPNESS,
					]
				)

	return warnings
