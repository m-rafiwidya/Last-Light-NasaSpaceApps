class_name GraphicsSettings

extends RefCounted

## Graphics settings that are really applied (the rest of the settings menu is still dummies),
## kept in user://settings.cfg. Read when a level loads.

enum TerrainDetail {
	HIGH,   ## the Moon terrain's play area as stored (Apollo 12: the measured 2 m posts), with the regolith relief's own shadows
	LOW,    ## no relief shadows; a 16-bit play tier finer than 1 m (the old south pole data) also at every other sample. A measured tier is never thinned
}

## The wheels' dust and tyre tracks (WheelDust; TyreTracks)
enum SurfaceEffects {
	HIGH,   ## full dust rate, the finer dust collision field
	LOW,    ## 40% of the dust, a coarser collision field (weaker computers)
	OFF,    ## no dust, no tracks
}

const PATH: String = "user://settings.cfg"
const TERRAIN_DETAIL_NAMES: Array[String] = ["High (fine ground shadows)", "Low (no fine ground shadows, weaker computers)"]
const SURFACE_EFFECTS_NAMES: Array[String] = ["High", "Low (weaker computers)", "Off"]

static var terrain_detail: TerrainDetail = TerrainDetail.HIGH
static var surface_effects: SurfaceEffects = SurfaceEffects.HIGH
static var _loaded: bool = false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		terrain_detail = clampi(config.get_value("graphics", "terrain_detail", TerrainDetail.HIGH), 0, TerrainDetail.size() - 1) as TerrainDetail
		surface_effects = clampi(config.get_value("graphics", "surface_effects", SurfaceEffects.HIGH), 0, SurfaceEffects.size() - 1) as SurfaceEffects
	# `-- terrain_detail=low`, `-- surface_effects=off` etc. on the command line (tests, frame-rate
	# runs) win for this run
	for arg in OS.get_cmdline_user_args():
		if arg == "terrain_detail=low":
			terrain_detail = TerrainDetail.LOW
		elif arg == "terrain_detail=high":
			terrain_detail = TerrainDetail.HIGH
		elif arg.begins_with("surface_effects="):
			var index: int = ["high", "low", "off"].find(arg.get_slice("=", 1))
			if index >= 0:
				surface_effects = index as SurfaceEffects


static func get_terrain_detail() -> TerrainDetail:
	load_settings()
	return terrain_detail


static func set_terrain_detail(value: TerrainDetail) -> void:
	load_settings()
	terrain_detail = value
	_save("terrain_detail", int(value))


static func get_surface_effects() -> SurfaceEffects:
	load_settings()
	return surface_effects


static func set_surface_effects(value: SurfaceEffects) -> void:
	load_settings()
	surface_effects = value
	_save("surface_effects", int(value))


static func _save(key: String, value: int) -> void:
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value("graphics", key, value)
	config.save(PATH)
