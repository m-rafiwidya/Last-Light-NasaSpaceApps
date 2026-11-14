class_name GraphicsSettings

extends RefCounted

## Graphics settings that are really applied (the rest of the settings menu is still dummies),
## kept in user://settings.cfg. Read when a level loads.

enum TerrainDetail {
	HIGH,   ## the Moon terrain's play area as stored (Apollo 12: the measured 2 m posts), with the regolith relief's own shadows
	LOW,    ## no relief shadows; a 16-bit play tier finer than 1 m (the old south pole data) also at every other sample. A measured tier is never thinned
}
# (TERRAIN_DETAIL_NAMES, the menu's labels, still name the south pole's 0.5 / 1 m: the settings
# menu belongs to the UI work, to be updated there)

const PATH: String = "user://settings.cfg"
const TERRAIN_DETAIL_NAMES: Array[String] = ["High (0.5 m ground)", "Low (1 m ground, weaker computers)"]

static var terrain_detail: TerrainDetail = TerrainDetail.HIGH
static var _loaded: bool = false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		terrain_detail = clampi(config.get_value("graphics", "terrain_detail", TerrainDetail.HIGH), 0, TerrainDetail.size() - 1) as TerrainDetail
	# `-- terrain_detail=low` on the command line (tests, frame-rate runs) wins for this run
	for arg in OS.get_cmdline_user_args():
		if arg == "terrain_detail=low":
			terrain_detail = TerrainDetail.LOW
		elif arg == "terrain_detail=high":
			terrain_detail = TerrainDetail.HIGH


static func get_terrain_detail() -> TerrainDetail:
	load_settings()
	return terrain_detail


static func set_terrain_detail(value: TerrainDetail) -> void:
	load_settings()
	terrain_detail = value
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value("graphics", "terrain_detail", int(value))
	config.save(PATH)
