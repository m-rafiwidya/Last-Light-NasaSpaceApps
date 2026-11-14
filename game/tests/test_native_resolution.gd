extends SceneTree
## The UI is drawn at the window's real resolution (not a 1920 x 1080 picture scaled up):
##   1. Project: stretch mode canvas_items on the 1920 x 1080 base (aspect expand), HiDPI allowed,
##      the canvas texture filter linear (with mipmaps where a texture has them).
##   2. Fonts (Michroma, Exo 2, IBM Plex Mono): rasterised per size and oversampled to the screen
##      (no MSDF), light hinting, subpixel positioning, mipmaps for scaled text.
##   3. The main menu's Moon SubViewport renders at the Moon's size on screen in real pixels,
##      its container scaled back down; the HUD crosshairs keep their 8 / 16 px size from their
##      larger rasters.
## Run headless and windowed at a large size (the scale is then not 1):
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_native_resolution.gd
##     Godot --path game -s res://tests/test_native_resolution.gd --resolution 3187x1793

const FONTS: Array[String] = ["res://res/fonts/michroma-latin-400-normal.woff2", "res://res/fonts/exo-2-latin-500-normal.woff2",
	"res://res/fonts/exo-2-latin-600-normal.woff2", "res://res/fonts/IBMPlexMono-Regular.ttf",
	"res://res/fonts/ibm-plex-mono-latin-500-normal.woff2"]

var failures: int = 0


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-62s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _run() -> void:
	var GS: Node = root.get_node("GameState")
	while GS.state != GS.State.MAIN_MENU:
		await process_frame
	for i in 10:
		await process_frame

	# 1. Project
	_check("stretch mode canvas_items", ProjectSettings.get_setting("display/window/stretch/mode") == "canvas_items"
		and root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS)
	_check("1920 x 1080 base, aspect expand", root.content_scale_size == Vector2i(1920, 1080)
		and root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND)
	_check("HiDPI allowed", ProjectSettings.get_setting("display/window/dpi/allow_hidpi") == true)
	# (the setting's own option names: its numbers differ from CanvasItem.TextureFilter's)
	var filter: int = ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter")
	var names: PackedStringArray = []
	for property in ProjectSettings.get_property_list():
		if property["name"] == "rendering/textures/canvas_textures/default_texture_filter":
			names = property["hint_string"].split(",")
	_check("canvas textures filter Linear Mipmap (never Nearest)", filter < names.size() and names[filter] == "Linear Mipmap",
		names[filter] if filter < names.size() else str(filter))
	var scale: float = root.get_final_transform().get_scale().y
	# The headless window is 64 x 64: the size checks need a real window
	var windowed: bool = DisplayServer.get_name() != "headless"
	if windowed:
		_check("the root window is the window's real size", root.size == DisplayServer.window_get_size()
			and is_equal_approx(scale, root.size.y / 1080.0), "%s, %.2f screen px per design px" % [root.size, scale])

	# 2. Fonts
	_check("fonts are oversampled to the screen", ProjectSettings.get_setting("gui/fonts/dynamic_fonts/use_oversampling") == true)
	for path in FONTS:
		var font: FontFile = load(path)
		_check("%s: rasterised, light hinting, subpixel, mipmaps" % path.get_file(), not font.multichannel_signed_distance_field
			and font.hinting == TextServer.HINTING_LIGHT and font.subpixel_positioning != TextServer.SUBPIXEL_POSITIONING_DISABLED
			and font.generate_mipmaps and font.antialiasing != TextServer.FONT_ANTIALIASING_NONE)

	# 3. The Moon's SubViewport, the crosshairs
	var moon: Control = root.find_child("Moon", true, false)
	var viewport: SubViewport = moon.get_node("Container/Viewport")
	var on_screen: Vector2 = moon.size * scale
	if windowed:
		_check("the Moon renders at its on-screen pixel size", Vector2(viewport.size).distance_to(on_screen) <= 1.5,
			"%s for %s on screen" % [viewport.size, on_screen])
	_check("its container is scaled back to the design size", (moon.get_node("Container") as Control).get_global_rect().size
		.distance_to(moon.get_global_rect().size) <= 1.0)
	for hud_path in ["Main/UIManager/HUD/MarginContainer/CenterContainer", "Main/UIManager/RobotHUD/MarginContainer/CenterContainer"]:
		for rect: TextureRect in root.get_node(hud_path).get_children().filter(func(n: Node) -> bool: return n is TextureRect):
			var size: float = rect.texture.get_size().x / 4.0
			_check("%s %s: drawn at its design size from a 4x raster" % [hud_path.get_slice("/", 2), rect.name],
				rect.get_combined_minimum_size() == Vector2(size, size) and rect.texture.get_size().x >= 32.0, str(rect.texture.get_size()))

	print("RESULT test_native_resolution %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
