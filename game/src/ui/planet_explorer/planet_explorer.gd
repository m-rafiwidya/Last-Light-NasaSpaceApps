class_name PlanetExplorer

extends Control

## Planet explorer (docs/ui/UI_SPEC.md "Planet explorer", board Main.dc.html, design x 1.2), opened
## by clicking the main menu's Moon: back button top-left, the planet's name, its globe in the
## middle (PlanetGlobe: drag to turn), prev / next buttons either side and the MOON / EARTH
## tabs at the bottom with the planet's colour under the active one. Sites (PlanetData) are
## SiteMarkers over the globe; pressing one swings the globe to it and opens its tooltip card
## (badge, name, rows, note). A locked planet (PlanetData.is_unlocked) is drawn dark with a lock and
## its hint, and has no markers. Drawn over the main menu's starfield; the menu hides its own items.
## The back button and Esc emit back_requested; the main menu closes this and shows itself again.
## Keyboard / gamepad: the tabs, prev / next, back and the visible markers all take focus.
## The stage (everything but the back button) is laid out at 1920 x 1080 and scaled with the
## screen's height about the screen's centre, never wider than the screen (stage_scale()).

signal back_requested

const OPEN_TIME: float = 0.6
const CLOSE_TIME: float = 0.3
## Changing planet: the globe slides in from 144 px aside, from 92 % size (the board's llInR / llInL)
const SLIDE_TIME: float = 0.55
const SLIDE_OFFSET: float = 144.0
## The globe's resting x on the stage (the board's 480, x 1.2)
const HOLDER_X: float = 576.0
const SLIDE_SCALE: float = 0.92
## Markers on the far side (facing away from the camera, see PlanetGlobe.project) are hidden, as is
## their tooltip; towards the limb they fade out, fully shown from EDGE_FADE in
const MIN_DEPTH: float = 0.02
const EDGE_FADE: float = 0.3
## Design size of the stage, and the width its content needs (prev to next button, with margins)
const DESIGN_SIZE: Vector2 = Vector2(1920.0, 1080.0)
const CONTENT_WIDTH: float = 1200.0
## Tooltip: right of the marker and a little up, flipped to the left when it would pass the
## right edge (the board's x + 28 / x - 328, y - 40, limit 980, x 1.2)
const TIP_OFFSET: Vector2 = Vector2(34.0, -48.0)
const TIP_FLIP: float = 394.0
const TIP_RIGHT_LIMIT: float = 1176.0
const TIP_FADE: float = 0.2
const ROW_KEY_WIDTH: float = 89.0
const ROW_VALUE_WIDTH: float = 211.0
const LOCK_ICON_SIZE: float = 33.6

var is_open: bool = false
var planet_index: int = 0
var selected_id: StringName = &""

var _tabs: Array[PlanetTab] = []
var _markers: Array[SiteMarker] = []
var _tween: Tween
var _slide_tween: Tween
var _tip_tween: Tween
var _tip_shown: bool = false

@onready var _stage: Control = $Stage
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _holder: Control = %Holder
@onready var _globe: PlanetGlobe = %Globe
@onready var _marker_layer: Control = %Markers
@onready var _lock: Control = %Lock
@onready var _lock_icon: Control = %LockIcon
@onready var _hint: Label = %Hint
@onready var _tip: PanelContainer = %Tip
@onready var _badge: Label = %Badge
@onready var _site_name: Label = %SiteName
@onready var _rows: GridContainer = %Rows
@onready var _note: Label = %Note
@onready var _back: BackButton = %Back
@onready var _prev: BackButton = %Prev
@onready var _next: BackButton = %Next


func _ready() -> void:
	_back.pressed.connect(back_requested.emit)
	_prev.pressed.connect(step.bind(-1))
	_next.pressed.connect(step.bind(1))
	_globe.clicked.connect(func(_at: Vector2) -> void: select_site(&""))
	_globe.swiped.connect(step)
	_lock_icon.draw.connect(func() -> void:
		PlanetTab.draw_lock(_lock_icon, _lock_icon.size / 2.0, LOCK_ICON_SIZE,
			get_theme_color(&"muted", &"UIColor"), 1.6 * LOCK_ICON_SIZE / 24.0))
	for planet in PlanetData.PLANETS:
		var tab := PlanetTab.new()
		tab.text = planet.tab
		tab.name = String(planet.id).capitalize()
		tab.planet_color = planet.color
		var sound := ButtonSoundComponent.new()
		tab.add_child(sound)
		tab.pressed.connect(go.bind(planet.id))
		%Tabs.add_child(tab)
		_tabs.append(tab)
	_tip.modulate.a = 0.0
	_stage.pivot_offset = DESIGN_SIZE / 2.0
	get_tree().root.size_changed.connect(_apply_scale)
	_apply_scale()
	_set_interactive(false)
	set_process(false)
	hide()


## Esc goes back, like the back button. In _input, before the GUI and the UIManager see it.
func _input(event: InputEvent) -> void:
	if not is_open or Debug.console_open or get_viewport().is_input_handled():
		return
	if event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		AudioManager.play_ui(&"back")
		back_requested.emit()


## Opens on `planet_id` (the Moon from the main menu); focus goes to its tab
func open(planet_id: StringName = &"moon") -> void:
	if is_open:
		return
	is_open = true
	show()
	_globe.set_active(true)
	set_process(true)
	_set_interactive(true)
	_show_planet(maxi(PlanetData.index_of(planet_id), 0), 0)
	if _tween:
		_tween.kill()
	modulate.a = 0.0
	# Rises 10 px into its anchored place (centred on the screen)
	var rest_y: float = _stage.position.y
	_stage.position.y = rest_y + 10.0
	_tween = _ui_tween()
	_tween.tween_property(self, "modulate:a", 1.0, OPEN_TIME)
	_tween.parallel().tween_property(_stage, "position:y", rest_y, OPEN_TIME)
	_tabs[planet_index].grab_focus()


func close(animate: bool = true) -> void:
	if not is_open and not animate:
		hide()
		return
	is_open = false
	_set_interactive(false)
	if _tween:
		_tween.kill()
	if not animate:
		_finish_close()
		return
	_tween = _ui_tween()
	_tween.tween_property(self, "modulate:a", 0.0, CLOSE_TIME)
	_tween.tween_callback(_finish_close)


func _finish_close() -> void:
	hide()
	set_process(false)
	_globe.set_active(false)
	select_site(&"")


## The stage's scale: the screen's height over 1080, but no wider than the screen
func stage_scale() -> float:
	var screen: Vector2 = get_viewport_rect().size
	return minf(screen.y / DESIGN_SIZE.y, screen.x / CONTENT_WIDTH)


func _apply_scale() -> void:
	_stage.scale = Vector2.ONE * stage_scale()
	# The globe's SubViewport renders at its real on-screen size
	_globe._fit_viewport()


func current_planet() -> Dictionary:
	return PlanetData.PLANETS[planet_index]


## Shows the previous (-1) or next (1) planet, if there is one
func step(delta: int) -> void:
	var index: int = planet_index + delta
	if index >= 0 and index < PlanetData.PLANETS.size():
		go(PlanetData.PLANETS[index].id)


func go(planet_id: StringName) -> void:
	var index: int = PlanetData.index_of(planet_id)
	if index < 0 or index == planet_index:
		return
	_show_planet(index, signi(index - planet_index))


## Shows the planet at `index`; `direction` slides its globe in from the right (1) or left (-1)
func _show_planet(index: int, direction: int) -> void:
	planet_index = index
	var planet: Dictionary = current_planet()
	var unlocked: bool = PlanetData.is_unlocked(planet.id)
	select_site(&"")
	_title.text = planet.title
	_subtitle.visible = unlocked and planet.has("subtitle")
	_subtitle.text = planet.get("subtitle", "")
	_globe.set_planet(planet)
	_globe.locked = not unlocked
	_lock.visible = not unlocked
	_hint.text = planet.lock_hint
	for i in _tabs.size():
		_tabs[i].active = i == index
		_tabs[i].locked = not PlanetData.is_unlocked(PlanetData.PLANETS[i].id)
	_prev.visible = index > 0
	_next.visible = index < PlanetData.PLANETS.size() - 1
	_build_markers(planet.sites if unlocked else [])
	# A hidden prev / next button can't keep the focus
	var focused: Control = get_viewport().gui_get_focus_owner()
	if is_open and (focused == null or not focused.is_visible_in_tree()):
		_tabs[index].grab_focus()
	if _slide_tween:
		_slide_tween.kill()
	_holder.position.x = HOLDER_X
	_holder.scale = Vector2.ONE
	_holder.modulate.a = 1.0
	if direction != 0:
		_holder.position.x += SLIDE_OFFSET * direction
		_holder.scale = Vector2.ONE * SLIDE_SCALE
		_holder.modulate.a = 0.0
		_slide_tween = _ui_tween().set_ease(Tween.EASE_OUT)
		_slide_tween.tween_property(_holder, "position:x", HOLDER_X, SLIDE_TIME)
		_slide_tween.parallel().tween_property(_holder, "scale", Vector2.ONE, SLIDE_TIME)
		_slide_tween.parallel().tween_property(_holder, "modulate:a", 1.0, SLIDE_TIME)


## Shows the locks again (after the `unlockall` console command)
func refresh_locks() -> void:
	if is_open:
		_show_planet(planet_index, 0)


func _build_markers(sites: Array) -> void:
	for marker in _markers:
		marker.queue_free()
	_markers.clear()
	for site in sites:
		var marker := SiteMarker.new()
		marker.site = site
		marker.name = String(site.id)
		marker.add_child(ButtonSoundComponent.new())
		marker.pressed.connect(select_site.bind(site.id))
		_marker_layer.add_child(marker)
		_markers.append(marker)
	_place_markers()


func marker(site_id: StringName) -> SiteMarker:
	for m in _markers:
		if m.site.id == site_id:
			return m
	return null


## Opens `site_id`'s tooltip and turns the globe to it; an empty id closes it and lets the globe
## spin again
func select_site(site_id: StringName) -> void:
	var site: Dictionary = {}
	var m: SiteMarker = marker(site_id)
	if m:
		site = m.site
	selected_id = site.get("id", &"")
	for other in _markers:
		other.selected = other == m
	if site.is_empty():
		_globe.stop_turning()
		_globe.spin = true
		_tip.hide()
		_tip_shown = false
		return
	_globe.turn_to(site.lat, site.lon)
	_globe.spin = false
	_fill_tip(site)
	_tip.show()
	_tip.modulate.a = 0.0
	_tip_shown = false
	_place_markers()


func _fill_tip(site: Dictionary) -> void:
	_badge.visible = site.has("badge")
	_badge.text = "● " + site.get("badge", "")
	_site_name.text = site.name
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for row in PlanetData.tooltip_rows(current_planet(), site):
		var key := Label.new()
		key.theme_type_variation = &"LabelTipKey"
		key.text = row[0]
		key.custom_minimum_size.x = ROW_KEY_WIDTH
		var value := Label.new()
		value.theme_type_variation = &"LabelTipValue"
		value.text = row[1]
		value.custom_minimum_size.x = ROW_VALUE_WIDTH
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_rows.add_child(key)
		_rows.add_child(value)
	_note.visible = site.has("note")
	_note.text = site.get("note", "")
	_tip.reset_size()


func _process(_delta: float) -> void:
	_place_markers()


## Moves the markers with the globe (hiding those round the back) and the tooltip with its marker
func _place_markers() -> void:
	for m in _markers:
		var p: Vector3 = _globe.project(m.site.lat, m.site.lon)
		var front: bool = p.z >= MIN_DEPTH
		if m.visible != front:
			if not front and m.has_focus():
				_tabs[planet_index].grab_focus()
			m.visible = front
		m.modulate.a = clampf((p.z - MIN_DEPTH) / (EDGE_FADE - MIN_DEPTH), 0.0, 1.0)
		m.place(_globe.position + Vector2(p.x, p.y))
	var selected: SiteMarker = marker(selected_id)
	if selected == null:
		return
	var at: Vector2 = selected.position + selected.size / 2.0
	var left: float = at.x + TIP_OFFSET.x
	if left + _tip.size.x > TIP_RIGHT_LIMIT:
		left = at.x - TIP_FLIP
	_tip.position = Vector2(left, at.y + TIP_OFFSET.y)
	_fade_tip(selected.visible)


func _fade_tip(shown: bool) -> void:
	if shown == _tip_shown:
		return
	_tip_shown = shown
	if _tip_tween:
		_tip_tween.kill()
	_tip_tween = _ui_tween()
	_tip_tween.tween_property(_tip, "modulate:a", 1.0 if shown else 0.0, TIP_FADE)


func _set_interactive(on: bool) -> void:
	mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED if on else Control.MOUSE_BEHAVIOR_DISABLED
	focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED if on else Control.FOCUS_BEHAVIOR_DISABLED


func _ui_tween() -> Tween:
	var tween: Tween = create_tween()
	tween.set_ignore_time_scale(true)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	return tween
