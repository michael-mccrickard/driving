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
## A flat may also be given the *step up or down into it* -- `flat 300 -240`, or
## a FLAT_STEP triple -- measured from wherever the shape before it ended, the
## same way a slope's rise is. The ground takes that step over the one segment
## before the join and then holds level: a hard riser, not a ramp, so a list of
## stepped flats is a staircase. A step up much past 30 degrees over that segment
## is a wall the car cannot climb, and is called out on the node; a step down is
## a drop, which is usually the point.
##
## `gap 2000` cuts a *hole* where the list has got to, as wide as it asks for.
## The ground under it carries on level at the height the shape before it ended,
## so both lips sit at that height and the shape after the gap picks up from
## there; the joins at the lips are left unrounded, so the car takes off at
## exactly the angle the shape before was driving at. It is the same hole an
## entry in TerrainBase's `gaps` cuts -- the two lists are added together, and a
## gap line gets the level's launch ramp like any other -- except that it is
## placed by where it is written rather than by an X counted from the start of
## the track, so the shapes before it can be rewritten without it having to be
## moved.

## Local metres, for the configuration warnings. Reached through the script
## rather than the GameState autoload name, because autoloads do not exist in
## the editor and this runs there.
const GameStateScript := preload("res://scripts/autoload/game_state.gd")

## Kinds of shape, and the number that selects one in the x of each entry in
## `shapes`. What the z of an entry means depends on the kind: degrees to the two
## slopes, a step to a stepped flat, and nothing at all to a plain flat or a gap.
enum Shape {
	## 0 -- level ground, length only, carrying on from the shape before it.
	FLAT,
	## 1 -- climbs at `steepness` degrees.
	SLOPE_UP,
	## 2 -- drops at `steepness` degrees.
	SLOPE_DOWN,
	## 3 -- level ground, stepped up or down into by the rise in z from wherever
	## the shape before it ended. What a staircase is made of.
	FLAT_STEP,
	## 4 -- a hole in the track, as wide as the length says, with the ground under
	## it level at the height the shape before it ended. `gap 2000` in the text.
	GAP,
}

## The words `shape_text` takes, and the kind each one means. Lower case; the
## parser folds what it reads before looking it up here.
const SHAPE_WORDS := {
	"flat": Shape.FLAT,
	"up": Shape.SLOPE_UP,
	"down": Shape.SLOPE_DOWN,
	"gap": Shape.GAP,
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
##   flat 300 -240   # a flat stepped 240 px down from where the last shape left
##   gap  400        # 400 px of nothing to jump, at the height it left off at
##
## The words are `flat`, `up`, `down` and `gap`; then a length in pixels; then,
## on everything but a gap, a second value -- a steepness in degrees on the two
## slopes, and the step up or down into it on a `flat`. Blank lines and anything
## after a `#` are ignored.
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
##   kind      0 Flat, 1 SlopeUp, 2 SlopeDown, 3 FlatStep, 4 Gap
##   length    horizontal run in pixels, rounded up to a whole segment_width
##   value     on the two slopes, degrees from horizontal, where 0 reads as
##             "use default_steepness"; on FlatStep, how far up or down the step
##             into it goes; ignored by Flat and Gap
##
## So Vector3(1, 600, 18) is "climb for 600 px at 18 degrees", and
## Vector3(3, 300, -240) is "step 240 px down, then 300 px of flat".
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
# The holes the `gap` shapes in that list turned into, as the (start, width)
# pairs TerrainBase cuts with. Worked out while the profile is laid out, because
# where a gap sits is the X the shapes before it happen to add up to.
var _shape_gaps := PackedVector2Array()
# Which line of `shape_text` each of those shapes came from, so a complaint can
# name the line rather than an index into a list nobody typed. Empty when the
# array is the source.
var _shape_lines := PackedInt32Array()
# What would not parse, in the order it was read.
var _parse_errors := PackedStringArray()
# The shape list as (segment_count, slope, step) runs, with the spawn pad on
# the front and the run-out on the back, and the height at every segment
# integrated out of it. `step` is the rise a stepped flat begins with, or NAN on
# a run that simply carries on from the one before it. Both settled once per
# build, in _begin_profile().
var _runs: Array[Vector3] = []
var _heights := PackedFloat32Array()
# The rise of the step into each stepped flat, in pixels, keyed by the shape's
# place in the list -- positive up. Only the steps the profile actually took: a
# stepped flat at the very start of a track has nothing to step off, and so is
# not in here at all.
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
## A stepped flat is the one thing that is *not* integrated: it jumps by the rise
## it names, so the join it starts on is moved by that much outright and the
## integration carries on from there. That leaves the segment before the join as
## the riser -- the step of a staircase, and the only discontinuity a shape list
## can produce.
##
## Laying the runs out is also where the `gap` shapes turn into the holes the
## build cuts, because it is the first point at which the X each of them starts
## at is known.
func _rebuild_profile() -> void:
	_resolve_shapes()
	_runs = _collect_runs()
	_risers.clear()
	_shape_gaps = PackedVector2Array()
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
		if _is_gap_run(run_index):
			_shape_gaps.append(_gap_span(index, int(run.x)))
		if _is_stepped(run):
			height += run.z
			# A track opening on a stepped flat has nothing before the first point to
			# step off: it simply starts that far up or down instead.
			var shape_index := _shape_of_run(run_index)
			if index > 0 and shape_index >= 0:
				_risers[shape_index] = run.z
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
	return "%d shapes%s%s, %.0f m, %.1f m to %.1f m, finishing %.1f m up" % [
		_shapes.size(),
		" from text" if _text_is_authoritative() else "",
		# Said out loud because a gap written in the list does not show up in the
		# `gaps` field, which is the only other place gaps are ever read off.
		(", %d gaps" % _shape_gaps.size()) if not _shape_gaps.is_empty() else "",
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


## Reads `shape_text` into shapes. One shape per line, `flat`/`up`/`down`/`gap`
## then a length then an optional second value; `#` starts a comment. A line that
## will not parse is skipped and complained about rather than guessed at -- a track with
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
				"Line %d: '%s' is not one of flat, up, down, gap." % [number, words[0]]
			)
			continue
		var kind: int = SHAPE_WORDS[word]
		if words.size() < 2:
			_parse_errors.append(
				"Line %d: %s needs a %s in pixels."
				% [number, word, "width" if kind == Shape.GAP else "length"]
			)
			continue
		if not words[1].is_valid_float():
			_parse_errors.append(
				"Line %d: '%s' is not a %s in pixels."
				% [number, words[1], "width" if kind == Shape.GAP else "length"]
			)
			continue
		# A gap is a width and nothing else: there is no slope to a hole, and the
		# height it sits at is whatever the shape before it left off at.
		var most := 2 if kind == Shape.GAP else 3
		if words.size() > most:
			_parse_errors.append("Line %d: '%s' is one value too many." % [number, words[most]])
			continue

		var value := 0.0
		if words.size() > 2:
			if not words[2].is_valid_float():
				_parse_errors.append(
					"Line %d: '%s' is not a %s." % [
						number,
						words[2],
						("step up or down in pixels" if kind == Shape.FLAT
							else "steepness in degrees"),
					]
				)
				continue
			value = words[2].to_float()
			# A flat given a second value is a flat that steps into place, which is a
			# different shape from one that carries on where the last left off.
			if kind == Shape.FLAT:
				kind = Shape.FLAT_STEP

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
		runs.append(Vector3(_shape_segments(shape), _shape_slope(shape), _shape_step(shape)))
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


## Whether a run begins with a step up or down rather than carrying on from the
## height the run before it ended at.
func _is_stepped(run: Vector3) -> bool:
	return not is_nan(run.z)


## Whether a run is a hole rather than ground. The run is laid out and integrated
## like any other flat -- the profile carries on underneath a gap, the same way it
## does under one cut by `gaps` -- and it is only the ground over it that is taken
## away, in _gap_span().
func _is_gap_run(run_index: int) -> bool:
	var shape_index := _shape_of_run(run_index)
	return shape_index >= 0 and _shape_kind(_shapes[shape_index]) == Shape.GAP


## The (start, width) pair that cuts one gap run out of the track. The run's own
## end points are its lips and stay as ground, so what is taken away is the
## segments between them: the pair is inset half a segment at each end, which
## covers every one of those and neither lip however a sampled X falls.
func _gap_span(start_index: int, segments: int) -> Vector2:
	var half := segment_width * 0.5
	return Vector2(
		float(start_index) * segment_width + half, float(segments - 1) * segment_width
	)


## The gaps the build cuts: the level's own, and the ones its `gap` shapes turned
## into. The two are the same thing by the time TerrainBase sees them, and are
## numbered in that order by the labels author mode puts over them.
func _active_gaps() -> PackedVector2Array:
	if _heights.is_empty():
		_rebuild_profile()
	if _shape_gaps.is_empty():
		return gaps
	var both := PackedVector2Array(gaps)
	both.append_array(_shape_gaps)
	return both


## Segments one shape covers. At least one: a shape asking for less than that
## would otherwise vanish, taking its join with it. A gap takes at least two,
## because what is cut away is the ground *between* its lips and a one-segment
## gap has none.
func _shape_segments(shape: Vector3) -> int:
	var least := 2 if _shape_kind(shape) == Shape.GAP else 1
	return maxi(least, ceili(maxf(shape.y, 0.0) / segment_width))


## Rise over run for one shape, up-positive. Both kinds of flat are level, a gap
## is level ground with the ground taken off it, and an unrecognised kind reads as
## flat too, with the complaint left to the scene tree rather than pushed once per
## build.
func _shape_slope(shape: Vector3) -> float:
	var kind := _shape_kind(shape)
	# Only the two slopes read z as a steepness: on a stepped flat it is the rise
	# into it, which is the profile's business, not the slope's.
	if kind != Shape.SLOPE_UP and kind != Shape.SLOPE_DOWN:
		return 0.0
	var steepness := clampf(shape.z if shape.z > 0.0 else default_steepness, 0.0, MAX_STEEPNESS)
	return tan(deg_to_rad(steepness)) * (1.0 if kind == Shape.SLOPE_UP else -1.0)


## The step a shape begins with, or NAN for one that carries on from wherever the
## shape before it ended. Only a stepped flat has one.
func _shape_step(shape: Vector3) -> float:
	return shape.z if _shape_kind(shape) == Shape.FLAT_STEP else NAN


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
## the track, two shapes that already share a slope, the step into a stepped
## flat, and either lip of a gap.
func _joint_reach(index: int) -> float:
	if index <= 0 or index >= _runs.size():
		return 0.0
	var before := _runs[index - 1]
	var after := _runs[index]
	# A stepped flat begins with its step, so this join is a riser and there is no
	# corner to take off: rounding a step would only smear it either side of the
	# join it belongs to, and leave the flat sitting off its height.
	if _is_stepped(after):
		return 0.0
	# A lip is not a corner either. Easing a slope into the flat ground under a gap
	# would tilt the last stretch the car drives before it takes off, and the first
	# it lands on -- the two places a jump is decided -- to round ground that has
	# been cut away.
	if _is_gap_run(index - 1) or _is_gap_run(index):
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
		if kind < Shape.FLAT or kind > Shape.GAP:
			warnings.append(
				("%s: kind %d is not one of 0 Flat, 1 SlopeUp, 2 SlopeDown, 3 FlatStep,"
					+ " 4 Gap; treated as Flat.")
				% [_shape_label(i), kind]
			)
		if kind == Shape.GAP:
			# Two segments, not one: the lips are ground, so a gap only starts taking
			# anything away at the segment between them.
			if shape.y < segment_width * 2.0:
				warnings.append(
					("%s: a gap of %.0f px is under the two segments (%.0f px) it takes"
						+ " to cut one, so it is held at two.")
					% [_shape_label(i), shape.y, segment_width * 2.0]
				)
		elif shape.y < segment_width:
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
		# A step *down* into a stepped flat is a drop, which is what stairs are for.
		# A step up is a wall one segment wide, and the car has to be able to climb
		# it like any other face.
		if kind == Shape.FLAT_STEP and _risers.get(i, 0.0) > 0.0:
			var rise: float = _risers[i]
			var riser_steepness := rad_to_deg(atan(rise / segment_width))
			if riser_steepness > DRIVABLE_STEEPNESS:
				warnings.append(
					("%s: the %.0f px step up is %.0f degrees over one segment,"
						+ " past the %.0f the car can climb.")
					% [
						_shape_label(i),
						rise,
						riser_steepness,
						DRIVABLE_STEEPNESS,
					]
				)

	return warnings
