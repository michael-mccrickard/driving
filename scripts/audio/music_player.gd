class_name MusicPlayer
extends AudioStreamPlayer
## Plays one looping track for the length of a run.
##
## The track is named by the HUD's Music field rather than assigned in the
## editor, so it can be swapped without touching the scene. Music runs from the
## start of a run until the car crosses the finish line -- the silence is part of
## reading the score.
##
## Nothing here is allowed to be fatal: a missing or unreadable file leaves the
## game silent and says so once, because a typo in a text field should not stop
## anyone driving.

## Bare filenames are looked up here, so the field can stay short. A path with a
## scheme or a leading slash is taken as given.
const TRACK_DIR := "res://assets/audio/"

var track := ""
var enabled := true

var _running := false
# Paths already complained about, so a bad name does not fill the log with one
# warning per restart.
var _warned := {}


## The file to play, as typed. Takes effect immediately if a run is under way.
func set_track(new_track: String) -> void:
	var trimmed := new_track.strip_edges()
	if trimmed == track:
		return
	track = trimmed
	stream = null
	_refresh()


func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	_refresh()


## Starts the track from the top. Every run gets the same opening bar, which is
## also the cue that the last one is over.
func begin_run() -> void:
	_running = true
	if playing:
		stop()
	_refresh()


func end_run() -> void:
	_running = false
	_refresh()


func _refresh() -> void:
	if not (_running and enabled):
		if playing:
			stop()
		return
	if playing:
		return
	if stream == null:
		stream = _load_track()
	if stream == null:
		return
	play()


func _load_track() -> AudioStream:
	if track.is_empty():
		return null
	var path := track if track.contains("://") or track.begins_with("/") else TRACK_DIR + track

	# An asset the editor has imported comes back through the resource cache with
	# its import settings applied; anything else is decoded straight off disk, so
	# a file dropped in while the game is running still plays.
	var stream_in: AudioStream = null
	if ResourceLoader.exists(path):
		stream_in = load(path) as AudioStream
	elif FileAccess.file_exists(path) and path.get_extension().to_lower() == "mp3":
		stream_in = AudioStreamMP3.load_from_file(path)

	if stream_in == null:
		if not _warned.has(path):
			_warned[path] = true
			push_warning("No music track at %s; playing silent." % path)
		return null
	# The mp3 importer defaults to loop = false, and a run has no fixed length,
	# so the loop is set here rather than left to whoever added the file.
	if "loop" in stream_in:
		stream_in.set("loop", true)
	return stream_in
