class_name SoundPlayer
extends AudioStreamPlayer
## The noises a run makes: the fanfare at the finish line, the crunch of a run
## lost in the dirt, the thud of the end wall, and whatever holds under the
## score afterwards.
##
## A player of its own, beside the Music node rather than under it, because one
## AudioStreamPlayer plays one stream at a time: sharing the music's player would
## mean every sound effect stopped the music to be heard. These two know nothing
## about each other, which is exactly what lets them sound together.
##
## Clips are named relative to assets/audio/ -- either a folder to pick from at
## random ("success") or one file ("misc/impact.wav"). A folder is listed on
## every pick rather than cached, so a clip dropped in while the game is running
## joins the rotation, the same way a music track does.
##
## Sounds are sequenced, not mixed: one clip plays and the rest wait their turn.
## That is what lets the fanfare at the line be followed by the bed that holds
## under the score. Nothing here is allowed to be fatal -- a missing folder or an
## unreadable file leaves the game quiet and says so once.

## Bare names are looked up here, so a cue can be named in one short string.
## A path with a scheme or a leading slash is taken as given.
const SFX_DIR := "res://assets/audio/"

## What counts as a clip when a folder is listed, so the .import files sitting
## beside the audio are not offered up as sounds in their own right.
const CLIP_EXTENSIONS := ["mp3", "wav", "ogg"]

## The clip playing right now, by the name it was asked for, or "" when quiet.
## Read-only from outside; the calls below are how it changes.
var clip := ""

# The clips waiting their turn, in order, each as [name, loop].
var _queue: Array[Array] = []
# Last pick per folder, so the same clip does not come up twice running.
var _last_pick := {}
# Whether the clip playing now holds until something stops it.
var _looping := false
# Warnings already pushed, so a missing file does not fill the log with one
# line per run.
var _warned := {}


func _ready() -> void:
	finished.connect(_advance)


## Plays a random clip from a folder under assets/audio/, cutting off whatever
## is playing and dropping whatever was queued behind it. The moments this marks
## -- a run finished, a run lost -- each replace the last one outright.
func play_random(folder: String, loop := false) -> void:
	play_clip(_pick(folder), loop)


## Plays one named clip, on the same terms.
func play_clip(clip_name: String, loop := false) -> void:
	_queue.clear()
	if not _start(clip_name, loop):
		silence()


## Puts a clip behind whatever is playing, or plays it now if nothing is.
func queue_clip(clip_name: String, loop := false) -> void:
	_queue.append([clip_name, loop])
	if clip.is_empty():
		_advance()


## Cuts a clip in over whatever is playing, for something that happens *while*
## the run's own sounds are still going -- the wall arrives a second or two after
## the line. A bed holding underneath is put back afterwards, from the top: it is
## a bed, and where it had got to is not the point. A one-shot part-way through
## is not put back -- it has had its moment, and the newer news is louder.
func interject(clip_name: String) -> void:
	var bed := clip if _looping else ""
	if not _start(clip_name, false):
		return
	if not bed.is_empty():
		_queue.push_front([bed, true])


## Everything off. A new run starts from silence, and this is also what lifts the
## bed from under a score that has been read.
func silence() -> void:
	_queue.clear()
	clip = ""
	_looping = false
	if playing:
		stop()


## The queue, one clip at a time: called when a clip ends, and to start the first
## one. A clip that will not load is stepped over rather than left stalling the
## queue behind it.
func _advance() -> void:
	clip = ""
	_looping = false
	while not _queue.is_empty():
		var next: Array = _queue.pop_front()
		if _start(next[0], next[1]):
			return


## Puts a clip on the player and starts it, reporting whether there was anything
## to start. Nothing that is playing is stopped until the replacement has loaded,
## so a name with a typo in it costs the sound it named and nothing else.
func _start(clip_name: String, loop: bool) -> bool:
	var stream_in := _load_clip(clip_name)
	if stream_in == null:
		return false
	_set_loop(stream_in, loop)
	if playing:
		stop()
	stream = stream_in
	clip = clip_name
	_looping = loop
	play()
	return true


## A clip from the folder, as a name this class can be handed back. Never the one
## the folder gave last time: with six fanfares to choose from, hearing the same
## one twice running reads as a bug in the game rather than as a coin landing the
## same way twice.
func _pick(folder: String) -> String:
	var names := _clips_in(folder)
	if names.is_empty():
		return ""
	var last: String = _last_pick.get(folder, "")
	var choices := Array(names)
	if choices.size() > 1:
		choices.erase(last)
	var pick: String = choices[randi() % choices.size()]
	_last_pick[folder] = pick
	return folder.path_join(pick)


func _clips_in(folder: String) -> PackedStringArray:
	var names := PackedStringArray()
	var path := SFX_DIR + folder
	var dir := DirAccess.open(path)
	if dir == null:
		_warn("No sound folder at %s; that cue will be silent." % path)
		return names
	for file in dir.get_files():
		# The editor lists the .import beside every asset, and an exported project
		# lists a .remap; both name the file that is actually loaded, so trim the
		# suffix off and let the duplicate fall out.
		var clip_name := file.trim_suffix(".import").trim_suffix(".remap")
		if CLIP_EXTENSIONS.has(clip_name.get_extension().to_lower()) and not names.has(clip_name):
			names.append(clip_name)
	if names.is_empty():
		_warn("No sound clips in %s; that cue will be silent." % path)
	# Listed order is whatever the filesystem hands over; sorted, so the same
	# folder gives the same set of choices on every machine.
	names.sort()
	return names


## Loads a clip by name. Same two routes as the music: an asset the editor has
## imported comes back through the resource cache with its import settings on
## it, and anything else is decoded straight off disk, so a file dropped in while
## the game is running still plays.
func _load_clip(clip_name: String) -> AudioStream:
	if clip_name.is_empty():
		return null
	var path := clip_name
	if not (clip_name.contains("://") or clip_name.begins_with("/")):
		path = SFX_DIR + clip_name

	var stream_in: AudioStream = null
	if ResourceLoader.exists(path):
		stream_in = load(path) as AudioStream
	elif FileAccess.file_exists(path) and path.get_extension().to_lower() == "mp3":
		stream_in = AudioStreamMP3.load_from_file(path)

	if stream_in == null:
		_warn("No sound at %s; playing silent." % path)
	return stream_in


## The importers default every clip to loop = false, which is right for all of
## these but the bed, so the flag is set per play rather than per file. A WAV
## spells it differently from everything else.
func _set_loop(stream_in: AudioStream, loop: bool) -> void:
	if stream_in is AudioStreamWAV:
		stream_in.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	elif "loop" in stream_in:
		stream_in.set("loop", loop)


func _warn(message: String) -> void:
	if _warned.has(message):
		return
	_warned[message] = true
	push_warning(message)
