class_name UiSettings

extends RefCounted

## Interface choices kept in user://settings.cfg (section "ui"), not shown in the settings menu:
##   last_planet  the planet last viewed in the planet explorer (PlanetData id), which the main
##                menu's globe shows

static var section := SettingsSection.new("ui", {"last_planet": "moon"})


static func last_planet() -> String:
	return section.get_value("last_planet")


static func set_last_planet(id: StringName) -> void:
	section.set_value("last_planet", String(id))
