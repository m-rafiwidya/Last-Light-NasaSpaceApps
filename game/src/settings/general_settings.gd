class_name GeneralSettings

extends RefCounted

## Settings > General, kept in user://settings.cfg (section "general") and applied at once:
##   subtitles      the HUD's DialogServer lines (spoken lines, scan reports, refused mounts) shown
##   subtitle_size  their text size, percent of the normal 24 px
##   show_tooltips  the part tooltip next to the crosshair (player and robot HUD)
##   show_fps       the FPS counter in the top-right corner (FpsCounter)
## Listen to `section.changed` to follow a change.

const SUBTITLE_SIZE_MIN: float = 50.0
const SUBTITLE_SIZE_MAX: float = 200.0

static var section := SettingsSection.new("general",
	{"subtitles": true, "subtitle_size": 100.0, "show_tooltips": true, "show_fps": false},
	{"subtitle_size": Vector2(SUBTITLE_SIZE_MIN, SUBTITLE_SIZE_MAX)})


static func subtitles() -> bool:
	return section.get_value("subtitles")


## Subtitle text size as a factor of the normal size (0.5 to 2)
static func subtitle_scale() -> float:
	return section.get_value("subtitle_size") / 100.0


static func show_tooltips() -> bool:
	return section.get_value("show_tooltips")


static func show_fps() -> bool:
	return section.get_value("show_fps")
