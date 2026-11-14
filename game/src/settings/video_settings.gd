class_name VideoSettings

extends RefCounted

## Settings > Video other than the window mode (DisplaySettings) and the two options used when a
## level loads (GraphicsSettings), kept in user://settings.cfg (section "video"), applied at once:
##   resolution        the window's size while windowed, an index into RESOLUTIONS (-1: as the
##                     project opens it). Fullscreen ignores it; going back to windowed applies it.
##   vsync             vsync on / off (Main drops vsync while the window is unfocused, see there)
##   frame_rate_limit  Engine.max_fps, an index into FRAME_RATE_LIMITS (0 there = unlimited)
##   fov               vertical field of view (degrees) of the player's camera and of the rover's
##                     mast camera unzoomed; the rover's chase view scales with it (RoverCamera).
##                     The hazard and arm tool cameras are fixed lenses and keep theirs.
##   brightness        the 3D picture's exposure (CameraAttributes.exposure_multiplier of every
##                     WorldEnvironment, and of the rover's tool camera, RoverCamera): 50 is as
##                     designed, 0 half, 100 twice. The UI is drawn on canvas layers after the 3D
##                     picture, so it never changes.
##   quality           Quality Preset (QUALITY_PRESETS): the 3D render scale (FSR below native),
##                     MSAA and shadow filtering at once, and Terrain Detail and Dust and Tracks
##                     (GraphicsSettings, next level load). The UI is always drawn at the window's
##                     full resolution (stretch mode canvas_items); only the 3D picture is scaled.
## Main applies them at launch (apply_saved) and keeps the brightness on every WorldEnvironment
## that enters the tree (track_environments). Listen to `section.changed` to follow a change.

enum Quality { LOW, MEDIUM, HIGH, ULTRA }

const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
const RESOLUTION_NAMES: Array[String] = ["1280x720", "1600x900", "1920x1080", "2560x1440"]
## The project's window size, shown while no resolution was picked and the window has another size
const DEFAULT_RESOLUTION: int = 2
const FRAME_RATE_LIMITS: Array[int] = [30, 60, 120, 144, 0]
const FRAME_RATE_NAMES: Array[String] = ["30", "60", "120", "144", "Unlimited"]
const FOV_MIN: float = 60.0
const FOV_MAX: float = 120.0
## The field of view the cameras were designed for (RoverCamera scales its chase view from it)
const FOV_DEFAULT: float = 90.0
const QUALITY_NAMES: Array[String] = ["Low", "Medium", "High", "Ultra"]
## Per Quality: the root viewport's 3D render scale and its upscaler (FSR 1 below native), MSAA,
## the soft shadow filter (directional and positional lights), the directional shadow atlas size,
## and the GraphicsSettings it sets. HIGH is the game as built (Godot's defaults) at native size.
const QUALITY_PRESETS: Array[Dictionary] = [
	{"scale_3d": 0.5, "msaa": Viewport.MSAA_DISABLED, "shadow_filter": RenderingServer.SHADOW_QUALITY_HARD, "shadow_atlas": 2048,
		"terrain_detail": GraphicsSettings.TerrainDetail.LOW, "surface_effects": GraphicsSettings.SurfaceEffects.OFF},
	{"scale_3d": 0.75, "msaa": Viewport.MSAA_DISABLED, "shadow_filter": RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, "shadow_atlas": 4096,
		"terrain_detail": GraphicsSettings.TerrainDetail.LOW, "surface_effects": GraphicsSettings.SurfaceEffects.LOW},
	{"scale_3d": 1.0, "msaa": Viewport.MSAA_DISABLED, "shadow_filter": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "shadow_atlas": 4096,
		"terrain_detail": GraphicsSettings.TerrainDetail.HIGH, "surface_effects": GraphicsSettings.SurfaceEffects.HIGH},
	{"scale_3d": 1.0, "msaa": Viewport.MSAA_4X, "shadow_filter": RenderingServer.SHADOW_QUALITY_SOFT_HIGH, "shadow_atlas": 8192,
		"terrain_detail": GraphicsSettings.TerrainDetail.HIGH, "surface_effects": GraphicsSettings.SurfaceEffects.HIGH},
]

static var section := SettingsSection.new("video",
	{"resolution": -1, "vsync": true, "frame_rate_limit": FRAME_RATE_LIMITS.size() - 1, "fov": FOV_DEFAULT,
		"brightness": 50.0, "quality": Quality.HIGH},
	{"resolution": Vector2(-1, RESOLUTIONS.size() - 1), "frame_rate_limit": Vector2(0, FRAME_RATE_LIMITS.size() - 1),
		"fov": Vector2(FOV_MIN, FOV_MAX), "brightness": Vector2(0.0, 100.0), "quality": Vector2(0, Quality.size() - 1)})


static func fov() -> float:
	return section.get_value("fov")


## Exposure factor for the brightness: 2 ^ ((brightness - 50) / 50)
static func exposure_multiplier() -> float:
	return pow(2.0, (float(section.get_value("brightness")) - 50.0) / 50.0)


## The resolution the menu shows: the one picked, else the window's if it is in the list, else
## the project's
static func resolution_index() -> int:
	var index: int = section.get_value("resolution")
	if index >= 0:
		return index
	var found: int = RESOLUTIONS.find(DisplayServer.window_get_size())
	return found if found >= 0 else DEFAULT_RESOLUTION


## Height in pixels of `viewport`'s 3D picture: the window's real size (canvas_items stretch) times
## its 3D render scale
static func render_height_3d(viewport: Viewport) -> float:
	var height: float = viewport.get_visible_rect().size.y * viewport.get_final_transform().get_scale().y
	return height * viewport.scaling_3d_scale


## Whether Terrain Detail and Dust and Tracks are still what the quality preset set (the menu
## shows "Custom" otherwise)
static func quality_matches_graphics() -> bool:
	var preset: Dictionary = QUALITY_PRESETS[section.get_value("quality")]
	return (GraphicsSettings.get_terrain_detail() == preset["terrain_detail"]
		and GraphicsSettings.get_surface_effects() == preset["surface_effects"])


## Sets, saves and applies one value
static func set_value(key: String, value: Variant) -> void:
	if section.set_value(key, value):
		_apply(key)


## Sets the quality preset, and with it Terrain Detail and Dust and Tracks
static func set_quality(quality: Quality) -> void:
	var preset: Dictionary = QUALITY_PRESETS[quality]
	GraphicsSettings.set_terrain_detail(preset["terrain_detail"])
	GraphicsSettings.set_surface_effects(preset["surface_effects"])
	# Announced even when the preset itself stays (Terrain Detail / Dust and Tracks changed back)
	if not section.set_value("quality", int(quality)):
		section.changed.emit("quality")
	_apply_quality()


## Applies everything saved (at launch)
static func apply_saved() -> void:
	for key in section.defaults:
		_apply(key)


## Keeps the brightness on every WorldEnvironment in `tree`, now and as they enter it
static func track_environments(tree: SceneTree) -> void:
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	_apply_brightness()


static func _apply(key: String) -> void:
	match key:
		"resolution":
			apply_resolution()
		"vsync":
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if section.get_value("vsync") else DisplayServer.VSYNC_DISABLED)
		"frame_rate_limit":
			Engine.max_fps = FRAME_RATE_LIMITS[section.get_value("frame_rate_limit")]
		"brightness":
			_apply_brightness()
		"quality":
			_apply_quality()


## The picked resolution, centred on the window's screen and no bigger than it; only while
## windowed (DisplaySettings calls this when the window goes back to windowed)
static func apply_resolution() -> void:
	var index: int = section.get_value("resolution")
	if index < 0 or DisplayServer.get_name() == "headless":
		return
	var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	if mode != DisplayServer.WINDOW_MODE_WINDOWED and mode != DisplayServer.WINDOW_MODE_MAXIMIZED:
		return
	if mode == DisplayServer.WINDOW_MODE_MAXIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var size: Vector2i = RESOLUTIONS[index].min(usable.size)
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)


static func _apply_quality() -> void:
	var preset: Dictionary = QUALITY_PRESETS[section.get_value("quality")]
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		var scale: float = preset["scale_3d"]
		tree.root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
		tree.root.scaling_3d_scale = scale
		tree.root.msaa_3d = preset["msaa"]
	RenderingServer.directional_soft_shadow_filter_set_quality(preset["shadow_filter"])
	RenderingServer.positional_soft_shadow_filter_set_quality(preset["shadow_filter"])
	RenderingServer.directional_shadow_atlas_set_size(preset["shadow_atlas"], true)


static func _apply_brightness() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for node in tree.root.find_children("*", "WorldEnvironment", true, false):
		_brighten(node as WorldEnvironment)


static func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment:
		_brighten(node)


static func _brighten(world: WorldEnvironment) -> void:
	if world.camera_attributes == null:
		world.camera_attributes = CameraAttributesPractical.new()
	world.camera_attributes.exposure_multiplier = exposure_multiplier()
