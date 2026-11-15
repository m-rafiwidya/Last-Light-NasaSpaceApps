class_name UiSettings

extends RefCounted

## Interface choices kept in user://settings.cfg (section "ui"), not shown in the settings menu:
##   last_planet        the planet last viewed in the planet explorer (PlanetData id), which the main
##                      menu's globe shows
##   campaign_finished  a campaign's ending has played (profile-wide: a new campaign keeps it); it
##                      unlocks Earth and the main menu's CREDITS
## A script run keeps these in a test file, not the player's.

const TEST_PATH: String = "user://settings_test_ui.cfg"

static var section := _make_section()


static func _make_section() -> SettingsSection:
	var made := SettingsSection.new("ui", {"last_planet": "moon", "campaign_finished": false})
	if SettingsSection._is_script_run():
		made.path = TEST_PATH
	return made


static func last_planet() -> String:
	return section.get_value("last_planet")


static func set_last_planet(id: StringName) -> void:
	section.set_value("last_planet", String(id))


static func campaign_finished() -> bool:
	return section.get_value("campaign_finished")


static func set_campaign_finished(finished: bool = true) -> void:
	section.set_value("campaign_finished", finished)
