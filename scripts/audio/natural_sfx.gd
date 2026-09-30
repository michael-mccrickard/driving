class_name NaturalSfx
extends AudioStreamPlayer
## Sounds that belong to the physical world rather than to a game event.
##
## This player is deliberately independent of EventSfx. A wall impact must never
## interrupt a finish fanfare or applause, and a finish event must never suppress
## a physical impact.

const SFX_DIR := "res://assets/audio/"

var _warned := {}


## Plays one named natural sound immediately, replacing any natural sound already
## playing. At present the only natural sound is the end-wall impact.
func play_clip(clip_name: String) -> void:
	var stream_in := _load_clip(clip_name)
	if stream_in == null:
		return
	if playing:
		stop()
	stream = stream_in
	play()


func silence() -> void:
	if playing:
		stop()


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

	if stream_in == null and not _warned.has(path):
		_warned[path] = true
		push_warning("No natural sound at %s; playing silent." % path)
	return stream_in
