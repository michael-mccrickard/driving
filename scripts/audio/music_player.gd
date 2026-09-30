class_name MusicPlayer
extends AudioStreamPlayer
## Plays the current level music, or the waiting music after the finish.
##
## Both belong to the same background-music layer, so switching from a level track
## to waiting.mp3 never competes with the event sounds or the natural sounds.

const TRACK_DIR := "res://assets/audio/"
const WAITING_TRACK := "misc/waiting.mp3"

var track := ""
var enabled := true
var _running := false
var _waiting := false
var _warned := {}


## The level track to play. Takes effect immediately if a run is under way.
func set_track(new_track: String) -> void:
	var trimmed := new_track.strip_edges()
	if trimmed == track and not _waiting:
		if _running and enabled:
			stop()
			stream = null
			_refresh()
		return
	track = trimmed
	_waiting = false
	stream = null
	_refresh()


func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	_refresh()


## Starts the level track from the beginning for a new run.
func begin_run() -> void:
	_running = true
	_waiting = false
	if playing:
		stop()
	stream = null
	_refresh()


## Switches the same music player to the looping waiting track. Event sounds can
## play independently over it, including the new-record applause.
func begin_waiting() -> void:
	_running = true
	_waiting = true
	if playing:
		stop()
	stream = null
	_refresh()


## Stops the background-music layer completely.
func end_run() -> void:
	_running = false
	_waiting = false
	_refresh()


func _refresh() -> void:
	if not (_running and enabled):
		if playing:
			stop()
		return
	if playing:
		return
	if stream == null:
		stream = _load_track(WAITING_TRACK if _waiting else track)
	if stream == null:
		return
	play()


func _load_track(track_name: String) -> AudioStream:
	if track_name.is_empty():
		return null
	var path := track_name if track_name.contains("://") or track_name.begins_with("/") else TRACK_DIR + track_name

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
	if "loop" in stream_in:
		stream_in.set("loop", true)
	return stream_in
