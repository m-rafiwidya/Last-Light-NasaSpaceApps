class_name Dialog

extends Resource

## Optional voice line. Played by DialogServer; if it is longer than the text's reading time,
## the line stays on screen until the audio finishes.
@export var audio_stream: AudioStream
## Who is talking. Leave empty for narration / unattributed lines.
@export var speaker: String
@export_multiline var subtitle: String
## Shortest time (seconds) this line stays on screen, even if the text is very short or empty.
@export_range(0.0, 30.0, 0.1, "or_greater") var min_duration: float = 1.0
## Set on lines that can fire again (alerts, cues): DialogServer drops it within REPEAT_COOLDOWN of its last play
@export var repeat_id: String = ""


## Text as shown in the UI: "Speaker: subtitle", or just the subtitle when there is no speaker.
func get_display_text() -> String:
	if speaker.is_empty():
		return subtitle
	return "%s: %s" % [speaker, subtitle]
