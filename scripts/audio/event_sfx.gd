class_name EventSfx
extends AudioStreamPlayer
## Sounds attached to game events: the finish fanfare, applause, and restart.
##
## These are deliberately separate from NaturalSfx so a physical impact can play
## at the same time without interrupting a finish sequence.

const SFX_DIR := "res://assets/audio/"
const CLIP_EXTENSIONS := ["mp3", "wav", "ogg"]

var clip := ""
var _queue: Array[Array] = []
var _last_pick := {}
var _looping := false
var _warned := {}


func _ready() -> void:
	finished.connect(_advance)


## Plays a random clip from a folder, replacing anything currently playing and
## clearing the event queue. Used for the finish fanfare.
func play_random(folder: String, loop := false) -> void:
	play_clip(_pick(folder), loop)


## Plays one named clip immediately and clears anything waiting behind it.
func play_clip(clip_name: String, loop := false) -> void:
	_queue.clear()
	if not _start(clip_name, loop):
		silence()


## Adds a clip to the event sequence. If nothing is playing, it starts now.
func queue_clip(clip_name: String, loop := false) -> void:
	_queue.append([clip_name, loop])
	if clip.is_empty():
		_advance()


## Stops all event sounds and discards queued events.
func silence() -> void:
	_queue.clear()
	clip = ""
	_looping = false
	if playing:
		stop()


func _advance() -> void:
	clip = ""
	_looping = false
	while not _queue.is_empty():
		var next: Array = _queue.pop_front()
		if _start(next[0], next[1]):
			return


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
		_warn("No event sound folder at %s; that cue will be silent." % path)
		return names
	for file in dir.get_files():
		var clip_name := file.trim_suffix(".import").trim_suffix(".remap")
		if CLIP_EXTENSIONS.has(clip_name.get_extension().to_lower()) and not names.has(clip_name):
			names.append(clip_name)
	if names.is_empty():
		_warn("No event sound clips in %s; that cue will be silent." % path)
	names.sort()
	return names


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
		_warn("No event sound at %s; playing silent." % path)
	return stream_in


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
