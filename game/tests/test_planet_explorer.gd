extends SceneTree
## Planet explorer: boots to the main menu, clicks the Moon and checks the explorer (opens on the
## Moon with its tab focused, the menu's items and Moon fade out and stop rendering), the Moon's
## site markers (they sit on the rendered sphere, hide round the back, a press opens the tooltip
## with rows, COORDS and the Apollo 12 badge and swings the globe to the site, a click on the empty
## disc closes it), dragging the globe, prev / next and the tabs (keyboard too), the locks (
## Earth locked with their hints and no markers; `unlockall` unlocks them, Earth shows the team
## with no COORDS), and Esc / the back button returning to the menu with PLAY focused.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_planet_explorer.gd

var GS: Node
var failures: int = 0
var _had_settings: bool = false
var _saved_settings: String = ""


func _initialize() -> void:
	# [ui] last_planet is written to the real settings file: put it back when done
	_had_settings = FileAccess.file_exists(SettingsSection.PATH)
	if _had_settings:
		_saved_settings = FileAccess.get_file_as_string(SettingsSection.PATH)
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-58s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _seconds(s: float) -> void:
	await create_timer(s, true, false, true).timeout


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
	await process_frame
	await process_frame


func _mouse_button(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	Input.parse_input_event(event)


func _mouse_move(at: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = relative
	Input.parse_input_event(event)


## A point in `control`'s coordinates, in window coordinates (what input events use)
func _window_point(control: Control, local: Vector2) -> Vector2:
	return root.get_final_transform() * (control.get_global_transform() * local)


func _run() -> void:
	GS = root.get_node("GameState")
	var start: int = Time.get_ticks_msec()
	while GS.state != GS.State.MAIN_MENU and Time.get_ticks_msec() - start < 60000:
		await process_frame
	if GS.state != GS.State.MAIN_MENU:
		_check("the main menu comes up", false)
		_restore_settings()
		quit(1)
		return
	var menu: Node = root.get_node("Main/UIManager/MainMenu")
	var loading := root.get_node("Main/UIManager/LoadingScreen") as CanvasLayer
	await _seconds(0.3)
	await _key(KEY_SPACE)
	while loading.visible:
		await process_frame
	await _seconds(0.3)
	var moon: MenuMoon = menu.find_child("Moon", true, false)
	var play: Button = menu.find_child("Play", true, false)
	var explorer: Node = menu.find_child("PlanetExplorer", true, false)
	var sub: Control = menu.get_node("MainMenuSubScreen")
	var globe: PlanetGlobe = explorer.find_child("Globe", true, false)
	var tip: Control = explorer.find_child("Tip", true, false)
	_check("explorer closed at first", not explorer.is_open and not explorer.visible and not globe.is_active())
	PlanetData.unlock_all = false
	_check("Earth is locked before any campaign ending", not PlanetData.is_unlocked(&"earth"))
	UiSettings.set_campaign_finished()
	UiSettings.section.read_saved = true
	UiSettings.section.reload()
	_check("a finished campaign unlocks Earth and survives a reload of the saved setting",
		UiSettings.campaign_finished() and PlanetData.is_unlocked(&"earth"))
	UiSettings.set_campaign_finished(false)
	UiSettings.section.read_saved = false
	_check("Earth is locked again once the setting is cleared", not PlanetData.is_unlocked(&"earth"))

	# Clicking the Moon (a real click on its disc) opens the explorer on the Moon
	var moon_centre: Vector2 = _window_point(moon, Vector2(700.0, 700.0))
	_mouse_button(moon_centre, true)
	_mouse_button(moon_centre, false)
	await process_frame
	await process_frame
	_check("clicking the Moon opens the explorer", explorer.is_open and explorer.visible and menu.is_explorer_open())
	_check("it opens on the Moon, title THE MOON", explorer.current_planet().id == &"moon"
		and explorer.find_child("Title", true, false).text == "THE MOON")
	var tabs: Array = explorer.find_child("Tabs", true, false).get_children()
	_check("two tabs MOON / EARTH", tabs.map(func(t: Button) -> String: return t.text) == ["MOON", "EARTH"])
	_check("the MOON tab is active and focused", tabs[0].active and tabs[0].has_focus())
	_check("Earth is locked, the Moon isn't", not tabs[0].locked and tabs[1].locked)
	_check("the globe renders", globe.is_active())
	_check("PLAY takes no focus behind it", play.focus_behavior_recursive == Control.FOCUS_BEHAVIOR_DISABLED
		or sub.focus_behavior_recursive == Control.FOCUS_BEHAVIOR_DISABLED)
	_check("no previous planet button on the Moon", not explorer.find_child("Prev", true, false).visible
		and explorer.find_child("Next", true, false).visible)
	await _seconds(0.8)
	_check("the menu's items and Moon faded out, the Moon stopped rendering",
		is_zero_approx(sub.modulate.a) and not moon.is_active())

	# Markers: the board's six Apollo sites, on the rendered sphere
	_check("six Moon markers", explorer._markers.size() == 6)
	var a12: SiteMarker = explorer.marker(&"a12")
	globe.lat = 0.0
	globe.lon = deg_to_rad(-23.0)
	globe._apply_rotation()
	await process_frame
	# The rendered sphere fills the globe control: the mesh's radius and the camera's height match
	var camera: Camera3D = globe.get_node("Container/Viewport/Camera")
	var sphere: SphereMesh = (globe.get_node("Container/Viewport/Pivot/Sphere") as MeshInstance3D).mesh
	_check("sphere mesh radius 1, camera 2 units high", is_equal_approx(sphere.radius, PlanetGlobe.SPHERE_RADIUS)
		and is_equal_approx(sphere.height, 2.0 * PlanetGlobe.SPHERE_RADIUS)
		and is_equal_approx(camera.size, 2.0 * PlanetGlobe.SPHERE_RADIUS), "radius %s, camera %s" % [sphere.radius, camera.size])
	var limb: Vector2 = globe.get_node("Container").get_transform() * camera.unproject_position(
		Vector3(PlanetGlobe.SPHERE_RADIUS, 0.0, 0.0))
	_check("the rendered limb is DISC_RADIUS from the centre", absf(limb.distance_to(globe.disc_centre())
		- PlanetGlobe.DISC_RADIUS) < 1.0, str(limb))
	# At any window size: the globe is 640 design px (768 at 1080) times the screen's height, centred
	# like the board, and every shown marker's screen position lies on the globe's on-screen disc
	var original_size: Vector2i = root.size
	for window_size: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(1920, 1200), Vector2i(2560, 1080)]:
		root.size = window_size
		await process_frame
		await process_frame
		explorer._place_markers()
		var label: String = "%dx%d" % [window_size.x, window_size.y]
		var screen: Vector2 = root.get_visible_rect().size
		var to_screen: Transform2D = globe.get_global_transform_with_canvas()
		var centre: Vector2 = to_screen * globe.disc_centre()
		var radius: float = PlanetGlobe.DISC_RADIUS * to_screen.get_scale().x
		var expected: float = 384.0 * minf(screen.y / 1080.0, screen.x / explorer.CONTENT_WIDTH)
		_check("%s: globe radius %.0f (768 px at 1080)" % [label, expected], absf(radius - expected) < 0.5, "%.1f" % radius)
		_check("%s: globe centred like the board" % label, absf(centre.x - screen.x / 2.0) < 0.5
			and absf(centre.y - (screen.y / 2.0 + 48.0 * radius / 384.0)) < 0.5, "%s in %s" % [centre, screen])
		var shown: int = 0
		var off: float = 0.0
		for m: SiteMarker in explorer._markers:
			if m.visible:
				shown += 1
				var at: Vector2 = m.get_global_transform_with_canvas() * (m.size / 2.0)
				off = maxf(off, at.distance_to(centre) - radius)
		_check("%s: every shown marker lies on the globe's disc" % label, shown > 0 and off <= 0.0,
			"%d shown, worst %.1f px outside" % [shown, off])
	root.size = original_size
	await process_frame
	await process_frame
	explorer._place_markers()
	_check("Apollo 12 faces us: its marker is shown", a12.visible)
	globe.lon = deg_to_rad(-23.0 + 180.0)
	globe._apply_rotation()
	explorer._place_markers()
	_check("round the back: its marker is hidden", not a12.visible)
	globe.lon = deg_to_rad(-23.4 + 85.0)
	globe._apply_rotation()
	explorer._place_markers()
	_check("near the limb: shown but faded", a12.visible and a12.modulate.a > 0.0 and a12.modulate.a < 1.0,
		"alpha %.2f" % a12.modulate.a)

	# Pressing a marker opens its tooltip and swings the globe to it
	a12.pressed.emit()
	await _seconds(2.0)
	_check("Apollo 12 selected, its ring drawn", explorer.selected_id == &"a12" and a12.selected)
	_check("the globe turned to it and stopped spinning", globe.project(-3.012, -23.422).z > 0.99 and not globe.spin)
	_check("the tooltip is shown next to it", tip.visible and is_equal_approx(tip.modulate.a, 1.0)
		and tip.position.x > a12.position.x)
	var badge: Label = explorer.find_child("Badge", true, false)
	_check("badge: WHERE LAST LIGHT TAKES PLACE", badge.visible and badge.text.ends_with("WHERE LAST LIGHT TAKES PLACE"))
	var rows: Array = explorer.find_child("Rows", true, false).get_children().map(func(l: Label) -> String: return l.text)
	_check("rows: LANDED / CREW / REGION / COORDS", rows == ["LANDED", "19 Nov 1969", "CREW", "Pete Conrad, Alan Bean",
		"REGION", "Oceanus Procellarum", "COORDS", "3.01°S  23.42°W"], str(rows))
	_check("the note is shown", explorer.find_child("Note", true, false).visible)
	explorer.marker(&"a11").pressed.emit()
	await process_frame
	_check("another site: Apollo 11, no badge", explorer.selected_id == &"a11" and not badge.visible and not a12.selected)

	# A click on the empty disc closes the tooltip; a drag turns the globe
	var disc: Vector2 = _window_point(globe, globe.disc_centre() + Vector2(0.0, 250.0))
	_mouse_button(disc, true)
	_mouse_button(disc, false)
	await process_frame
	_check("a click on the empty globe closes the tooltip", explorer.selected_id == &"" and not tip.visible and globe.spin)
	var lon_before: float = globe.lon
	var drag: Vector2 = root.get_final_transform().basis_xform(Vector2(150.0, 0.0))
	_mouse_button(disc, true)
	_mouse_move(disc + drag, drag)
	await process_frame
	_mouse_button(disc + drag, false)
	await process_frame
	_check("dragging turns the globe", globe.lon < lon_before - 0.3, "%.2f -> %.2f" % [lon_before, globe.lon])

	# Keyboard: Enter on the focused next button shows Earth, locked; next hides and the focus moves to the tab
	var next: Button = explorer.find_child("Next", true, false)
	next.grab_focus()
	await _key(KEY_ENTER)
	await _seconds(0.7)
	_check("Enter on next: EARTH, its tab active", explorer.current_planet().id == &"earth"
		and explorer.find_child("Title", true, false).text == "EARTH" and tabs[1].active and not tabs[0].active)
	_check("Earth locked: lock and hint, dark globe, no markers", explorer.find_child("Lock", true, false).visible
		and explorer.find_child("Hint", true, false).text == "FINISH THE GAME" and globe.locked
		and explorer._markers.is_empty())
	_check("no next on Earth, prev shown, focus moved to the EARTH tab", not next.visible
		and explorer.find_child("Prev", true, false).visible and tabs[1].has_focus())
	_check("no team subtitle while Earth is locked", not explorer.find_child("Subtitle", true, false).visible)
	await _key(KEY_LEFT)
	_check("left from EARTH focuses MOON", tabs[0].has_focus())
	await _key(KEY_ENTER)
	_check("Enter on the MOON tab shows the Moon", explorer.current_planet().id == &"moon")

	# unlockall: Earth opens up
	root.get_node("Debug").parse_command("unlockall")
	await process_frame
	_check("unlockall: Earth unlocked", not tabs[1].locked)
	tabs[1].pressed.emit()
	await _seconds(0.7)
	_check("Earth: three team markers and the subtitle", explorer._markers.size() == 3
		and explorer.find_child("Subtitle", true, false).visible and explorer.selected_id == &"")
	explorer.marker(&"fahd").pressed.emit()
	await process_frame
	rows = explorer.find_child("Rows", true, false).get_children().map(func(l: Label) -> String: return l.text)
	_check("Earth sites have no COORDS row", not "COORDS" in rows and "Bandung, Indonesia" in rows, str(rows))
	explorer.marker(&"faiq").pressed.emit()
	await process_frame
	await process_frame
	var site_name: Label = explorer.find_child("SiteName", true, false)
	_check("a long name wraps inside the card", site_name.text == "FAIQ HAIDAR DZIKRULLAH SATRIAWAN"
		and site_name.get_line_count() > 1 and site_name.size.x <= tip.size.x
		and site_name.get_visible_line_count() == site_name.get_line_count(),
		"%d lines, %.0f of %.0f" % [site_name.get_line_count(), site_name.size.x, tip.size.x])

	# Esc goes back to the menu
	await _key(KEY_ESCAPE)
	await _seconds(0.6)
	_check("Esc closes the explorer", not explorer.is_open and not explorer.visible and not globe.is_active())
	_check("the menu is back: PLAY focused, the Moon renders", play.has_focus() and moon.is_active()
		and is_equal_approx(sub.modulate.a, 1.0) and not menu.is_popup_open())
	# The menu globe now shows the planet last viewed (Earth), saved for the next launch
	_check("the menu globe shows Earth", moon.planet_id == &"earth" and UiSettings.last_planet() == "earth")
	_check("the menu globe has Earth's blue rim glow, the Moon none", moon._glow.visible
		and (moon._glow.texture.gradient.colors[2] as Color).is_equal_approx(PlanetData.PLANETS[1].atmosphere)
		and (moon._glow.texture.gradient.colors[2] as Color).b > (moon._glow.texture.gradient.colors[2] as Color).r)
	_check("the menu globe's texture is Earth's", (moon._material.get_shader_parameter(&"albedo_map") as Texture2D).resource_path
		== PlanetData.PLANETS[1].map)
	# Clicking it opens the explorer on that planet; the back button closes it too
	moon.moon_clicked.emit()
	await process_frame
	_check("opens on Earth", explorer.is_open and explorer.current_planet().id == &"earth")
	tabs[0].pressed.emit()
	await process_frame
	explorer.find_child("Back", true, false).pressed.emit()
	await _seconds(0.6)
	_check("the Moon has no glow", not moon._glow.visible)
	_check("the back button returns to the menu, showing the Moon again", not explorer.is_open and play.has_focus()
		and moon.planet_id == &"moon" and UiSettings.last_planet() == "moon")
	# Earth viewed, then it locks again: the menu falls back to the Moon
	moon.moon_clicked.emit()
	await process_frame
	tabs[1].pressed.emit()
	await process_frame
	explorer.find_child("Back", true, false).pressed.emit()
	await _seconds(0.6)
	_check("Earth viewed: the menu globe is Earth", moon.planet_id == &"earth" and UiSettings.last_planet() == "earth")
	PlanetData.unlock_all = false
	_check("Earth locked again: the menu falls back to the Moon", PlanetData.menu_planet() == &"moon")
	menu.fade_in()
	_check("fade_in applies the fallback", moon.planet_id == &"moon")

	PlanetData.unlock_all = false
	print("DONE %d failures" % failures)
	_restore_settings()
	quit(1 if failures else 0)


func _restore_settings() -> void:
	if _had_settings:
		var file := FileAccess.open(SettingsSection.PATH, FileAccess.WRITE)
		file.store_string(_saved_settings)
		file.close()
	elif FileAccess.file_exists(SettingsSection.PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SettingsSection.PATH))
