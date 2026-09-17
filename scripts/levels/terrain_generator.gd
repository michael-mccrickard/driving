@tool
class_name TerrainGenerator
extends TerrainBase
## Procedural rolling hills, so the project has something drivable before any
## level art exists. The shape comes out of noise: set roughly how high and how
## long the hills are and drive whatever the seed gives you.
##
## Everything that is not the shape of the ground -- the collision and visuals,
## the gaps and their launch ramps, the hand-edit path, the spawn pad, the
## run-out, the finish line and the end wall -- is TerrainBase's, and is shared
## with TerrainAuthor. Look there for how a build fits together; what is left
## here is the profile and nothing else.

@export_group("Hills")
@export_range(16, 4000, 1) var segment_count := 500:
	set(value):
		segment_count = value
		_request_rebuild()
## Peak-to-centre hill height. Together with hill_length this sets how steep
## the track gets: the steepest slope is about amplitude * TAU / hill_length,
## so 130 over 1400 is roughly a 30 degree face.
@export_range(0.0, 600.0, 1.0) var amplitude := 130.0:
	set(value):
		amplitude = value
		_request_rebuild()
## Distance between hill crests, in pixels. Raise it to flatten the track out
## without losing height.
@export_range(200.0, 6000.0, 10.0) var hill_length := 1400.0:
	set(value):
		hill_length = value
		_request_rebuild()
## Strength of the fine bumps riding on top of the hills, as a fraction of
## amplitude. Keep this low -- the detail octave is four times the frequency,
## so its contribution to *slope* is four times its contribution to height.
@export_range(0.0, 0.5, 0.01) var detail_strength := 0.08:
	set(value):
		detail_strength = value
		_request_rebuild()
@export var noise_seed := 1337:
	set(value):
		noise_seed = value
		_request_rebuild()

# The two octaves and the height the run-out sits at, all three settled once per
# build in _begin_profile() rather than per point.
var _base_noise: FastNoiseLite
var _detail_noise: FastNoiseLite
var _run_out_height := 0.0


func _profile_segments() -> int:
	return segment_count


func _begin_profile() -> void:
	_base_noise = FastNoiseLite.new()
	_base_noise.seed = noise_seed
	_base_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_base_noise.fractal_octaves = 1
	_base_noise.frequency = 1.0 / hill_length

	_detail_noise = FastNoiseLite.new()
	_detail_noise.seed = noise_seed + 1
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_detail_noise.fractal_octaves = 1
	_detail_noise.frequency = 4.0 / hill_length

	# The run-out sits at whatever height the profile happens to have at the
	# finish line, so that height is read off the noise once, up front.
	_run_out_height = _noise_height(_finish_index())


func _profile_height(index: int) -> float:
	var height := _noise_height(index)
	var finish := _finish_index()
	# 0 a dozen segments out from the line, 1 from the line onwards. Eased, so
	# the profile meets the run-out tangentially and the car is not asked to
	# brake over a kink.
	var into_run_out := clampf(
		float(index - (finish - EASE_SEGMENTS)) / float(EASE_SEGMENTS), 0.0, 1.0
	)
	if into_run_out > 0.0:
		height = lerpf(height, _run_out_height, smoothstep(0.0, 1.0, into_run_out))
	return height


## Height of the raw noise at a segment, before the run-out is folded over it.
## The leading segments are pinned flat for the spawn pad and eased out of, so
## that pad does not end in a wall the car cannot climb out of.
func _noise_height(index: int) -> float:
	if index <= flat_start_segments:
		return 0.0
	var x := float(index) * segment_width
	var ramp: float = minf(float(index - flat_start_segments) / float(EASE_SEGMENTS), 1.0)
	var h := _base_noise.get_noise_1d(x) + _detail_noise.get_noise_1d(x) * detail_strength
	return h * amplitude * ramp
