@tool
@abstract
class_name TerrainBase
extends StaticBody2D
## Everything a generated track has in common, whatever it is that decides its
## shape. Subclasses supply a height profile and nothing else:
##
##   TerrainGenerator -- rolling hills from noise, tuned by amplitude and
##                       hill_length. What every level shipped so far uses.
##   TerrainAuthor    -- a list of shapes (flat, slope up, slope down), driven
##                       end to end in the order they are written.
##
## Runs as @tool: changing an export in the inspector rebuilds the collision and
## the visuals immediately. Expects three children -- CollisionPolygon2D,
## Polygon2D and Line2D -- which it fills in.
##
## `gaps` cuts the track into several pieces with nothing but air between them.
## The first piece uses those three children; the rest get their own, created as
## internal children so they never end up saved into the level scene.
##
## The last stretch of every track is held flat as a run-out, with the finish
## line at the near end of it and a wall across the far end. `main.gd` reads that
## line off finish_x(); the wall is what a finished run rolls to a stop against,
## instead of driving off the end of the world.
##
## An optional fourth child, a Path2D named "Edits", is the one place a level may
## be shaped by hand: each of its curve points pins the ground to that height and
## eases back to the generated profile either side of it. The three nodes above
## are *outputs* -- rewritten on every build, which is why nothing dragged onto
## them survives -- and the path is an *input*, read on every build and never
## written to. That is the whole difference, and the reason an edit made there is
## still there next launch.
##
## What a build does, in order: the subclass's profile, then the hand edits over
## it, then the launch ramps over those, then the gaps cut through everything. An
## anchor may flatten a landing, but it may not take away the ramp that throws
## the car at one, and a gap always wins -- nothing puts ground back into a hole.

## Segments the profile takes to ease into or out of a flat stretch, at either
## end of the track. Long enough that the join is a bend the car drives over
## rather than a step it noses into.
const EASE_SEGMENTS := 12

## How far off the straight line between its neighbours a surface point has to
## sit before it is worth keeping, in pixels. The profile is sampled once per
## segment whether the ground is bending or not, so a long straight ramp arrives
## as a row of points that all lie on the same line -- and a polygon made mostly
## of those is what Godot's convex decomposition turns into zero-area slivers,
## which then will not triangulate ("Invalid polygon data, triangulation
## failed."). Dropping them costs nothing: a twentieth of a pixel is well under
## what floating point noise moves a point by over a long descent, let alone
## what anything in the game can see or drive on.
const COLLINEAR_TOLERANCE := 0.05

@export_group("Shape")
@export_range(8.0, 256.0, 1.0) var segment_width := 48.0:
	set(value):
		segment_width = value
		_request_rebuild()
## Leading segments held flat so the car has somewhere to spawn.
@export_range(0, 40, 1) var flat_start_segments := 6:
	set(value):
		flat_start_segments = value
		_request_rebuild()
## Trailing segments held flat so the car has somewhere to pull up after the
## line. The finish line stands at the near end of this run-out and the wall
## across the far end of it, so this is how much room a finished run has to shed
## its speed in: 12 segments at 48 px is 18 m.
@export_range(0, 60, 1) var flat_end_segments := 12:
	set(value):
		flat_end_segments = value
		_request_rebuild()
## The wall closing the far end of the course. Tall enough that a car arriving
## along the run-out cannot get over it; 0 leaves the end open.
@export_range(0.0, 800.0, 8.0) var wall_height := 200.0:
	set(value):
		wall_height = value
		_request_rebuild()
@export_range(8.0, 200.0, 4.0) var wall_thickness := 32.0:
	set(value):
		wall_thickness = value
		_request_rebuild()
## Local X ranges with no ground in them, as (start, width) pixel pairs. Each one
## is a break the car has to jump: the track simply ends at the near lip and
## starts again at the far one, and the profile carries on underneath, so a gap
## cut across a crest lands lower than it takes off.
##
## An authored track has a second place to write one down -- a `gap` line in its
## shape list, placed by where it is written rather than by an X measured from
## the start -- and the two lists are added together. _active_gaps() is what the
## build cuts, and is the pair of them.
@export var gaps := PackedVector2Array():
	set(value):
		gaps = value
		_request_rebuild()
## Ground raised into a launch ramp over the run-up to each gap. Without one the
## car simply drives off the lip: a parabola at driving speed falls faster than
## rolling hills do, so nothing on the natural profile is steep enough to throw
## it. Height is how far the lip is lifted above the profile, length is how much
## run-up that is spread over.
@export_range(0.0, 400.0, 5.0) var gap_ramp_height := 70.0:
	set(value):
		gap_ramp_height = value
		_request_rebuild()
@export_range(48.0, 1200.0, 8.0) var gap_ramp_length := 300.0:
	set(value):
		gap_ramp_length = value
		_request_rebuild()
## How far either side of an anchor on the Edits path its edit reaches, for
## anchors whose handles are left where they were dropped. Dragging a point's in
## or out handle sets that side's reach instead, so an edit can ease in over a
## long run-up and still stop dead at the far end.
@export_range(48.0, 4000.0, 8.0) var edit_falloff := 400.0:
	set(value):
		edit_falloff = value
		_request_rebuild()
## How far the solid fill extends below the surface -- measured from the lowest
## point the track reaches, so a course that descends a long way is still solid
## ground under its far end rather than a polygon folded back over itself. The
## bottom is flat and shared by every piece: this is the depth of the deepest
## part of the fill, not a skirt hung under each segment.
@export_range(100.0, 8000.0, 10.0) var fill_depth := 2400.0:
	set(value):
		fill_depth = value
		_request_rebuild()

@export_group("Appearance")
@export var fill_colour := Color(0.20, 0.34, 0.27):
	set(value):
		fill_colour = value
		_request_rebuild()
@export var surface_colour := Color(0.36, 0.72, 0.48):
	set(value):
		surface_colour = value
		_request_rebuild()
@export_range(1.0, 24.0, 0.5) var surface_thickness := 7.0:
	set(value):
		surface_thickness = value
		_request_rebuild()
## The post drawn on the finish line. Without it the line is invisible and the
## run just ends somewhere. Height 0 leaves it undrawn.
@export var finish_colour := Color(0.95, 0.95, 0.98):
	set(value):
		finish_colour = value
		_request_rebuild()
@export_range(0.0, 400.0, 4.0) var finish_post_height := 140.0:
	set(value):
		finish_post_height = value
		_request_rebuild()
## Whether the wall is painted. Turn it off on a level that covers the end of the
## course with art of its own: the wall goes on stopping the car exactly as it
## did, it just stops being drawn. `wall_height` is what removes the wall itself.
@export var wall_visible := true:
	set(value):
		wall_visible = value
		queue_redraw()
@export var wall_colour := Color(0.55, 0.58, 0.62):
	set(value):
		wall_colour = value
		queue_redraw()
## Where the level's art for the finish line and the wall is pinned to the
## track. A Sprite2D named "Finish" or "Wall" next to this node (a sibling, under
## the level root) is moved on every build so that this texel of its texture
## lands on the ground: the foot of the flagpole on the finish line, the bottom
## of the wall's near face on the near face of the wall. Their scale is left as
## the level set it, so the art can be sized by hand and still end up in place
## however the track in front of it is reshaped.
@export var finish_sprite_foot := Vector2(370.0, 992.0):
	set(value):
		finish_sprite_foot = value
		_request_rebuild()
@export var wall_sprite_foot := Vector2(517.0, 905.0):
	set(value):
		wall_sprite_foot = value
		_request_rebuild()

var _surface: PackedVector2Array = PackedVector2Array()
# The gaps this build is cutting: `gaps`, plus whatever else the subclass has to
# add to them. Settled once per build, in _build_surface(), because the ramps and
# the split both walk it per point and neither may see a different list from the
# other.
var _gaps_in_effect := PackedVector2Array()
# Local Y the fill and the collision polygons close at, settled once per build
# in generate() so every piece of a gapped track closes at the same depth.
var _fill_bottom := 0.0
# The hand-edit path, or null on a level that has none. Held between builds only
# so the build loop is not looking it up per point.
var _edits: Path2D
# Everything the generator makes for itself rather than filling in: the second
# and later pieces of ground, the end wall's collision shape, and the finish
# post. Internal, so they are
# invisible to the scene file, and freed outright rather than queued -- a @tool
# rebuild can run several times in a frame and must not leave the old ones
# standing.
var _extra_pieces: Array[Node] = []

var _gap_label_layer: CanvasLayer
var _gap_labels: Array[Label] = []
var _author_mode := false

const GAP_LABEL_FONT_SIZE := 48
const GAP_LABEL_SCREEN_Y_FRACTION := 0.333
const GAP_LABEL_WIDTH := 120.0


# --- What a subclass supplies -------------------------------------------------

## Height of the raw profile at a segment, up-positive, before the hand edits,
## the launch ramps and the gaps are folded over it. Segment `index` sits at
## `index * segment_width` local pixels.
@abstract func _profile_height(index: int) -> float

## How many segments long the track is. Its length in pixels is this times
## segment_width, and the profile is sampled at index 0 through this inclusive.
@abstract func _profile_segments() -> int

## Called once at the top of every build, before the profile is sampled, for
## whatever a subclass needs set up first -- noise instances, a precomputed
## profile. Both _profile_height() and _profile_segments() are called after this
## and may rely on it.
func _begin_profile() -> void:
	pass


## The gaps to cut, which is the `gaps` list on its own unless a subclass has
## somewhere else to write them down -- an authored track has them in its shape
## list as well. Asked once per build, after _begin_profile(), so a subclass that
## works its gaps out while it lays out its profile has them ready by then.
func _active_gaps() -> PackedVector2Array:
	return gaps


# --- The build ---------------------------------------------------------------


func _ready() -> void:
	generate()


## World-space point on the surface at the given local X. Follows the underlying
## profile, so asking about a point inside a gap gives the ground that would have
## been there. Used to place the car and anything else that sits on the ground.
func surface_point_at(local_x: float) -> Vector2:
	if _surface.is_empty():
		generate()
	var index: int = clampi(int(local_x / segment_width), 0, _surface.size() - 1)
	return to_global(_surface[index])


## Local Y the ground closes at underneath: fill_depth below the deepest point
## the surface reaches. Anything wanting to sample the terrain from above wants
## to aim at this rather than at fill_depth, which is a depth and not a
## coordinate.
func fill_bottom() -> float:
	if _surface.is_empty():
		generate()
	return _fill_bottom


## World-space Y of the lowest ground on the track -- the deepest the surface
## ever reaches. Y grows downwards, so this is the largest Y of it. What "the car
## has fallen out of the world" is measured down from: a track may descend as far
## as it likes, and only below the ground it descends to is there nothing left to
## land on.
func lowest_surface_y() -> float:
	if _surface.is_empty():
		generate()
	return to_global(Vector2(0.0, _deepest_surface())).y


## The deepest point of the surface, in local Y -- which grows downwards, so
## this is the largest of them. Held at 0 as a floor, the height the track
## starts at, so a course that only ever climbs closes at exactly fill_depth the
## way it always has.
func _deepest_surface() -> float:
	var deepest := 0.0
	for point in _surface:
		deepest = maxf(deepest, point.y)
	return deepest


## World-space X of the finish line: the near end of the flat run-out. A run is
## over as soon as any part of the car is past this, and the run-out and the wall
## beyond it are what the car then rolls to a stop against.
func finish_x() -> float:
	if _surface.is_empty():
		generate()
	return to_global(_surface[_finish_index()]).x


## World-space X of the last surface point: the far end of the run-out, and where
## the wall stands. Past it there is no ground left.
func end_x() -> float:
	if _surface.is_empty():
		generate()
	return to_global(_surface[_surface.size() - 1]).x


## World-space X of the near face of the end wall -- the face a finished run
## rolls into. INF on a track that has asked for no wall, so a caller comparing
## against it simply never fires.
func wall_x() -> float:
	if wall_height <= 0.0:
		return INF
	if _surface.is_empty():
		generate()
	var last := _surface[_surface.size() - 1]
	return to_global(Vector2(last.x - wall_thickness, last.y)).x


func generate() -> void:
	_watch_edits()
	_surface = _build_surface()
	_fill_bottom = _deepest_surface() + fill_depth
	var pieces := _split_at_gaps(_surface)
	# The polygons are built from the straightened pieces; _surface itself keeps
	# its point per segment, because surface_point_at() indexes straight into it.
	for i in pieces.size():
		pieces[i] = _drop_collinear(pieces[i])
	_clear_extra_pieces()
	_apply_collision(pieces[0], get_node_or_null("Collision") as CollisionPolygon2D)
	_apply_visuals(
		pieces[0], get_node_or_null("Fill") as Polygon2D, get_node_or_null("Surface") as Line2D
	)
	for i in range(1, pieces.size()):
		_build_extra_piece(pieces[i])
	_build_end_wall()
	_build_finish_marker()
	_place_end_sprites()
	_build_gap_labels()
	# The wall's paint is this node's own rather than a child's, so a rebuild has
	# to ask for the repaint that puts it back.
	queue_redraw()
	# Whatever a subclass has to say about the shape it was handed is said about
	# the track that was just built from it.
	update_configuration_warnings()


func _build_surface() -> PackedVector2Array:
	_begin_profile()
	# After the profile and before anything is sampled: the subclass has just laid
	# out the shape it is building, which is where an authored track's own gaps are
	# written down.
	_gaps_in_effect = _active_gaps()
	var points := PackedVector2Array()
	for i in _profile_segments() + 1:
		var x := float(i) * segment_width
		# Profile, then the hand edits over it, then the launch ramps over those:
		# an anchor may flatten a landing, but it may not take away the ramp that
		# throws the car at one, and a gap below still wins over both.
		var height := _edit_height(x, _profile_height(i))
		points.append(Vector2(x, -(height + _ramp_lift(x))))
	return points


## Splits the profile into the runs of ground that survive the gaps. Always
## returns at least one piece: gaps that swallow the whole track are ignored
## rather than leaving a level with nothing to drive on.
func _split_at_gaps(surface: PackedVector2Array) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array] = []
	if _gaps_in_effect.is_empty():
		pieces.append(surface)
		return pieces
	var piece := PackedVector2Array()
	for point in surface:
		if _is_gap(point.x):
			# A single point is a hairline, not ground; drop it.
			if piece.size() >= 2:
				pieces.append(piece)
			piece = PackedVector2Array()
			continue
		piece.append(point)
	if piece.size() >= 2:
		pieces.append(piece)
	if pieces.is_empty():
		push_warning("%s: gaps cover the whole track; ignoring them." % name)
		pieces.append(surface)
	return pieces


## The same run of ground with the points that only repeat a straight line taken
## out of it. The ends are always kept, so the piece still spans exactly what it
## did and the fill still closes underneath the same two X positions.
func _drop_collinear(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var kept := PackedVector2Array()
	kept.append(points[0])
	for i in range(1, points.size() - 1):
		# Measured from the last point kept rather than from the neighbour that was
		# just dropped, so a run of points is straightened against the line it is
		# actually being replaced by.
		var from := kept[kept.size() - 1]
		var span := points[i + 1] - from
		var length := span.length()
		if length > 0.0 and absf(span.cross(points[i] - from)) / length <= COLLINEAR_TOLERANCE:
			continue
		kept.append(points[i])
	kept.append(points[points.size() - 1])
	return kept


func _is_gap(local_x: float) -> bool:
	for gap in _gaps_in_effect:
		if local_x >= gap.x and local_x <= gap.x + gap.y:
			return true
	return false


func _build_extra_piece(piece: PackedVector2Array) -> void:
	# A CollisionPolygon2D only counts as a shape when it is a direct child of the
	# body, so these go on self rather than in a tidy container.
	var shape := CollisionPolygon2D.new()
	_add_extra_piece(shape)
	_apply_collision(piece, shape)

	var fill := Polygon2D.new()
	_add_extra_piece(fill)
	var line := Line2D.new()
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_add_extra_piece(line)
	_apply_visuals(piece, fill, line)


## The wall across the far end of the run-out, painted by the body itself rather
## than by another generated child. A child is built once, in _ready(), which the
## editor does not run again when a script is reloaded or when the scene was
## already open -- so a wall made of child nodes can be there in game and missing
## from the viewport. _draw() has no such dependency: the editor repaints the
## node and the wall is simply there, and generate() asks for a repaint whenever
## the shape of it changes.
##
## Drawn before the Fill and Surface children, which are drawn after their
## parent, so the skirt buried below the surface is hidden by the ground it is
## sunk into rather than painted over it.
##
## Only the paint is behind `wall_visible`. The collision shape is built in
## generate() regardless, so a level that hides the wall behind its own art loses
## nothing but the grey rectangle.
func _draw() -> void:
	if not wall_visible:
		return
	var wall := _wall_polygon()
	if not wall.is_empty():
		draw_colored_polygon(wall, wall_colour)


## The collision half of that wall. Without a wall a run carries on off the cliff
## the moment it has finished and the player watches a completed run fall out of
## the world; hitting it costs nothing, because the bill was settled back at the
## line, so it is a backstop rather than a hazard.
##
## This half does have to be a child: a shape only counts on a body when it is a
## direct child of it. Being part of the terrain body, it needs no collision
## setup of its own.
func _build_end_wall() -> void:
	var wall := _wall_polygon()
	if wall.is_empty():
		return
	var shape := CollisionPolygon2D.new()
	shape.polygon = wall
	_add_extra_piece(shape)


## The wall as a local-space rectangle, or empty on a track that has asked for no
## wall. Both halves of it are cut from this, so the shape the car hits and the
## shape on screen cannot drift apart.
func _wall_polygon() -> PackedVector2Array:
	if wall_height <= 0.0 or _surface.size() < 2:
		return PackedVector2Array()
	var last := _surface[_surface.size() - 1]
	var near_x := last.x - wall_thickness
	# Footed on the lower of the two points it stands between, and buried by its
	# own thickness below that, so it cannot leave a gap under itself on a track
	# whose run-out has been turned off.
	var foot := maxf(last.y, _surface[_surface.size() - 2].y) + wall_thickness
	return PackedVector2Array([
		Vector2(near_x, last.y - wall_height),
		Vector2(last.x, last.y - wall_height),
		Vector2(last.x, foot),
		Vector2(near_x, foot),
	])


## A post standing on the finish line, so the player can see what they are
## driving at. Built last and so drawn over the ground and the wall, and internal
## like the extra pieces it is cleared alongside.
func _build_finish_marker() -> void:
	if finish_post_height <= 0.0:
		return
	var foot := _surface[_finish_index()]
	var post := Line2D.new()
	post.points = PackedVector2Array([foot, foot - Vector2(0.0, finish_post_height)])
	post.default_color = finish_colour
	post.width = surface_thickness
	post.begin_cap_mode = Line2D.LINE_CAP_ROUND
	post.end_cap_mode = Line2D.LINE_CAP_ROUND
	_add_extra_piece(post)


## Stands the level's Finish and Wall art where the finish post and the wall
## were just built. Either may be missing; a level without them keeps the plain
## post and grey wall, which the art is otherwise drawn over.
func _place_end_sprites() -> void:
	var level := get_parent()
	if level == null or _surface.size() < 2:
		return
	_pin_sprite(
		level.get_node_or_null("Finish") as Sprite2D, _surface[_finish_index()], finish_sprite_foot
	)
	if wall_height > 0.0:
		var last := _surface[_surface.size() - 1]
		_pin_sprite(
			level.get_node_or_null("Wall") as Sprite2D,
			Vector2(last.x - wall_thickness, last.y),
			wall_sprite_foot
		)


## Moves `sprite` so the given texel of its texture sits on `local_point` of the
## track. Through both transforms, so neither the sprite's scale nor where the
## terrain sits in the level throws it off.
func _pin_sprite(sprite: Sprite2D, local_point: Vector2, texel: Vector2) -> void:
	if sprite == null or sprite.texture == null:
		return
	var in_sprite := texel + sprite.offset
	if sprite.centered:
		in_sprite -= sprite.texture.get_size() * 0.5
	sprite.global_position = to_global(local_point) - sprite.global_transform.basis_xform(in_sprite)


func _add_extra_piece(node: Node) -> void:
	add_child(node, false, Node.INTERNAL_MODE_BACK)
	_extra_pieces.append(node)


func _clear_extra_pieces() -> void:
	for node in _extra_pieces:
		if is_instance_valid(node):
			node.free()
	_extra_pieces.clear()


## The surface point the finish line stands on. Held clear of the spawn pad and
## its easing, so a level asking for more run-out than it has track still leaves
## somewhere to start from rather than finishing behind the start line.
func _finish_index() -> int:
	var segments := _profile_segments()
	var earliest := mini(flat_start_segments + EASE_SEGMENTS, segments)
	return clampi(segments - flat_end_segments, earliest, segments)


## Picks up the optional Edits child and rebuilds whenever one of its points is
## dragged. Looked up on every build rather than once at _ready(), so a path
## added to a level that is already open is noticed by the next rebuild instead
## of needing the scene reloaded.
func _watch_edits() -> void:
	_edits = get_node_or_null("Edits") as Path2D
	if _edits == null or _edits.curve == null:
		return
	if not _edits.curve.changed.is_connected(_request_rebuild):
		_edits.curve.changed.connect(_request_rebuild)


## Folds the hand-authored anchors over the profile the subclass produced. Each
## point on the Edits path pins the ground to its own height and eases back to
## the generated shape over its falloff, so a flat run-out or a lowered shelf can
## be dropped anywhere without giving up the track around it.
##
## Anchors are sampled at the same X positions as everything else, so a feature
## narrower than a segment or two cannot be expressed. Sparse edits -- a landing,
## a pad, a levelled finish -- are what this is for.
func _edit_height(local_x: float, profile: float) -> float:
	if _edits == null or _edits.curve == null:
		return profile
	var curve := _edits.curve
	var height := profile
	for i in curve.point_count:
		# Through the path's own transform, so dragging the node moves the whole
		# set of anchors with it rather than silently disagreeing with them.
		var point: Vector2 = _edits.position + curve.get_point_position(i)
		var offset := local_x - point.x
		var radius := _handle_reach(
			curve.get_point_out(i) if offset >= 0.0 else curve.get_point_in(i)
		)
		if absf(offset) >= radius:
			continue
		# 1 at the anchor, 0 at the rim, and flat at both ends, so the edit meets
		# the generated ground tangentially rather than in a step the car noses
		# into.
		var weight := smoothstep(0.0, 1.0, 1.0 - absf(offset) / radius)
		# Y grows downwards on the path; heights here grow upwards.
		height = lerpf(height, -point.y, weight)
	return height


## How far an anchor reaches on one side. A handle left where it was dropped is
## no reach at all, which would make the point do nothing, so that reads as "use
## the level's edit_falloff" instead.
func _handle_reach(handle: Vector2) -> float:
	var reach := absf(handle.x)
	return reach if reach > 1.0 else edit_falloff


## How far the launch ramp lifts the ground at this X. Squared rather than eased,
## so the ramp is steepest exactly at the lip and the car leaves it pointing up.
func _ramp_lift(local_x: float) -> float:
	if gap_ramp_height <= 0.0:
		return 0.0
	var lift := 0.0
	for gap in _gaps_in_effect:
		var into_ramp := local_x - (gap.x - gap_ramp_length)
		if into_ramp <= 0.0 or local_x > gap.x:
			continue
		var t := into_ramp / gap_ramp_length
		lift = maxf(lift, gap_ramp_height * t * t)
	return lift


func _apply_collision(surface: PackedVector2Array, shape: CollisionPolygon2D) -> void:
	if shape == null:
		push_warning("%s expects a CollisionPolygon2D child named 'Collision'." % name)
		return
	var polygon := PackedVector2Array(surface)
	# Close the loop underneath so the polygon is solid, not a hairline.
	polygon.append(Vector2(surface[surface.size() - 1].x, _fill_bottom))
	polygon.append(Vector2(surface[0].x, _fill_bottom))
	shape.polygon = polygon


func _apply_visuals(surface: PackedVector2Array, fill: Polygon2D, line: Line2D) -> void:
	if fill != null:
		var polygon := PackedVector2Array(surface)
		polygon.append(Vector2(surface[surface.size() - 1].x, _fill_bottom))
		polygon.append(Vector2(surface[0].x, _fill_bottom))
		fill.polygon = polygon
		fill.color = fill_colour

	if line != null:
		line.points = surface
		line.default_color = surface_colour
		line.width = surface_thickness


func _request_rebuild() -> void:
	if is_node_ready():
		generate()


func set_author_mode(authoring: bool) -> void:
	_author_mode = authoring
	if _author_mode:
		_build_gap_labels()
	else:
		_clear_gap_labels()


func _build_gap_labels() -> void:
	_clear_gap_labels()
	if not _author_mode or _gaps_in_effect.is_empty():
		return
	if _gap_label_layer == null:
		_gap_label_layer = CanvasLayer.new()
		_gap_label_layer.name = "GapLabels"
		_gap_label_layer.layer = 100
		add_child(_gap_label_layer)
	for i in _gaps_in_effect.size():
		var label := Label.new()
		label.text = "G%d" % i
		label.add_theme_font_size_override("font_size", GAP_LABEL_FONT_SIZE)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.size = Vector2(GAP_LABEL_WIDTH, GAP_LABEL_FONT_SIZE + 12.0)
		_gap_label_layer.add_child(label)
		_gap_labels.append(label)
	_update_gap_labels()


func _clear_gap_labels() -> void:
	for label in _gap_labels:
		if is_instance_valid(label):
			label.free()
	_gap_labels.clear()


func _process(_delta: float) -> void:
	if _author_mode and not _gap_labels.is_empty():
		_update_gap_labels()


func _update_gap_labels() -> void:
	if _gap_labels.is_empty():
		return
	var viewport_size := get_viewport_rect().size
	var screen_y := viewport_size.y * GAP_LABEL_SCREEN_Y_FRACTION
	var canvas_transform := get_viewport().get_canvas_transform()
	for i in mini(_gap_labels.size(), _gaps_in_effect.size()):
		var gap := _gaps_in_effect[i]
		var center := to_global(Vector2(gap.x + gap.y * 0.5, 0.0))
		var screen_position := canvas_transform * center
		var label := _gap_labels[i]
		label.position = Vector2(screen_position.x - GAP_LABEL_WIDTH * 0.5, screen_y)
