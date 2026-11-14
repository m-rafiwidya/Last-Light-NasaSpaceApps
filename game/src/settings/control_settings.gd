class_name ControlSettings

extends RefCounted

## Settings > Controls other than the key bindings (InputBindings), kept in user://settings.cfg
## (section "controls") and read where they are used:
##   mouse_sensitivity  mouse look speed of the player's and the rover's cameras (PlayerController,
##                      RobotController): 40 is the speed the game was tuned at, 1 to 100 scale it
##   invert_y           moving the mouse up looks down
##   toggle_crouch      on foot, the crouch key toggles crouching instead of crouching while held

const SENSITIVITY_DEFAULT: float = 40.0

static var section := SettingsSection.new("controls",
	{"mouse_sensitivity": SENSITIVITY_DEFAULT, "invert_y": false, "toggle_crouch": false},
	{"mouse_sensitivity": Vector2(1.0, 100.0)})


## Mouse motion in pixels as the cameras should take it: scaled by the sensitivity, y flipped
## when inverted (PlayerController.px_to_rad turns it into an angle)
static func look_pixels(relative: Vector2) -> Vector2:
	var scale: float = section.get_value("mouse_sensitivity") / SENSITIVITY_DEFAULT
	return Vector2(relative.x, -relative.y if section.get_value("invert_y") else relative.y) * scale


static func toggle_crouch() -> bool:
	return section.get_value("toggle_crouch")
