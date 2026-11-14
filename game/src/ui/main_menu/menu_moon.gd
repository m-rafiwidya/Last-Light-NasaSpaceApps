class_name MenuMoon

extends Control

## The main menu's 3D Moon, rendered in its own SubViewport (own world, transparent background).
## Large and partly off-screen to the bottom-right like the design (canvas at x 560, disc centre
## (1560, 1000), radius 980 at 1600 x 900; all x 1.2 here). It turns slowly by itself, can be
## dragged (with a little inertia), brightens and grows slightly on hover, and emits
## moon_clicked when clicked without dragging. Only the disc takes the mouse (_has_point).
## Call set_active(false) while the menu is hidden: the SubViewport then stops rendering.
## The SubViewport renders at the Moon's real size on screen (the window's pixels, not the
## 1920 x 1080 base): its container is that many pixels big and scaled back down (_fit_viewport).
## The control is anchored to the screen's bottom-right corner and sized from the screen's height
## (BASE_SIZE x height / 1080, see height_unit()), so at any aspect ratio (16:9, ultrawide, tall)
## the Moon is the same fraction of the screen's height, reaches the right edge and keeps its place
## relative to the bottom-right corner. Layout is recomputed whenever the window changes.

signal moon_clicked

## The control's size on a 1080 px tall screen, and the disc's centre and radius in it (multiply by
## height_unit() for the real ones)
const BASE_SIZE: Vector2 = Vector2(1248.0, 1080.0)
const DESIGN_HEIGHT: float = 1080.0
const DISC_CENTRE: Vector2 = Vector2(1200.0, 1200.0)
const DISC_RADIUS: float = 1176.0
## The point of the Moon facing the camera at the start (the design's view: lat -0.32, lon 0.38)
const START_LAT: float = -0.32
const START_LON: float = 0.38
const MAX_LAT: float = 1.3
## Idle rotation (radians/s), slower while hovered; it resumes this long after a drag
const SPIN: float = 0.035
const SPIN_HOVER: float = 0.015
const IDLE_DELAY: float = 1.2
## Radians turned per disc radius dragged
const DRAG_RATE: float = 1.4
## A press that moves less than this (px) is a click
const CLICK_SLOP: float = 6.0
## How fast the spin left after a drag dies down (1/s)
const INERTIA_DAMPING: float = 3.5
const HOVER_SCALE: float = 1.02
const HOVER_BRIGHTNESS: float = 1.08
const HOVER_TIME: float = 0.5

## Opening sequence: offset from the resting position (in design pixels, not scaled with the
## screen's height), scale (about the bottom-right corner) and brightness factor
var intro_offset: Vector2 = Vector2.ZERO:
	set(value):
		intro_offset = value
		_apply_transform()
var intro_scale: float = 1.0:
	set(value):
		intro_scale = value
		_apply_transform()
var intro_brightness: float = 1.0:
	set(value):
		intro_brightness = value
		_apply_brightness()

## The planet shown (PlanetData id): the Moon, or the last one viewed in the planet explorer
var planet_id: StringName = &"moon"
var lat: float = START_LAT
var lon: float = START_LON

var _hovered: bool = false
var _hover_amount: float = 0.0
var _hover_tween: Tween
var _dragging: bool = false
var _moved: float = 0.0
var _frame_drag: Vector2 = Vector2.ZERO
## Angular velocity (lon, lat per second) carried on after a drag
var _velocity: Vector2 = Vector2.ZERO
var _idle: float = 0.0

@onready var _container: SubViewportContainer = $Container
@onready var _viewport: SubViewport = $Container/Viewport
@onready var _pivot: Node3D = $Container/Viewport/Pivot
@onready var _material: ShaderMaterial = ($Container/Viewport/Pivot/Sphere as MeshInstance3D).material_override


func _ready() -> void:
	pivot_offset = size
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))
	resized.connect(func() -> void: pivot_offset = size)
	resized.connect(_fit_viewport)
	get_tree().root.size_changed.connect(_apply_layout)
	get_tree().root.size_changed.connect(_fit_viewport)
	_apply_layout()
	_fit_viewport()
	_apply_rotation()
	_apply_brightness()


## The screen's height in design units over 1080: 1 on 16:9 and wider windows (the stretch follows
## the height), more on taller ones (the stretch follows the width)
func height_unit() -> float:
	return get_viewport_rect().size.y / DESIGN_HEIGHT


## Disc centre and radius in this control's coordinates now
func disc_centre() -> Vector2:
	return DISC_CENTRE * height_unit()


func disc_radius() -> float:
	return DISC_RADIUS * height_unit()


## Anchored to the bottom-right corner (anchors in the scene), BASE_SIZE x height_unit() big, moved
## by the opening sequence's offset. Nothing absolute is remembered, so a resize can't leave it behind.
func _apply_layout() -> void:
	var base: Vector2 = BASE_SIZE * height_unit()
	offset_left = -base.x + intro_offset.x
	offset_top = -base.y + intro_offset.y
	offset_right = intro_offset.x
	offset_bottom = intro_offset.y


## Screen pixels per design pixel (the window's stretch); the SubViewport renders that much larger
func screen_scale() -> float:
	return get_viewport().get_final_transform().get_scale().y


func _fit_viewport() -> void:
	var pixels: float = maxf(screen_scale(), 0.25)
	_container.size = (size * pixels).round()
	# Scaled back so it covers the control exactly (the rounding above would leave up to half a pixel)
	_container.scale = size / _container.size


## Renders, turns and shows only while active; the menu turns it off when it hides. Inactive means
## gone: hidden (the sliding sub-screen it sits in is only moved a fixed 1920 px aside, which leaves a
## strip of it on screen on a wider window or while it is scaled up by hover), no SubViewport updates,
## and every drag / hover / inertia / intro state reset so nothing is left half-way.
func set_active(active: bool) -> void:
	visible = active
	_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED)
	set_process(active)
	if not active:
		_dragging = false
		_velocity = Vector2.ZERO
		_frame_drag = Vector2.ZERO
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if _hover_tween:
			_hover_tween.kill()
		_hovered = false
		_set_hover_amount(0.0)


func is_active() -> bool:
	return _viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED


func _has_point(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(point) and point.distance_to(disc_centre()) < disc_radius()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_moved = 0.0
			_velocity = Vector2.ZERO
			mouse_default_cursor_shape = Control.CURSOR_DRAG
		elif _dragging:
			_dragging = false
			_idle = 0.0
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			if _moved < CLICK_SLOP:
				_velocity = Vector2.ZERO
				moon_clicked.emit()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_moved += absf(motion.relative.x) + absf(motion.relative.y)
		var k: float = DRAG_RATE / (disc_radius() * scale.x)
		var turn := Vector2(-motion.relative.x * k, motion.relative.y * k)
		lon += turn.x
		lat = clampf(lat + turn.y, -MAX_LAT, MAX_LAT)
		_frame_drag += turn
		_apply_rotation()
		accept_event()


func _process(delta: float) -> void:
	if _dragging:
		# Smoothed drag speed, kept as the inertia when the button is released
		if delta > 0.0:
			_velocity = _velocity.lerp(_frame_drag / delta, 0.35)
		_frame_drag = Vector2.ZERO
		return
	_idle += delta
	lon += _velocity.x * delta
	lat = clampf(lat + _velocity.y * delta, -MAX_LAT, MAX_LAT)
	_velocity *= exp(-INERTIA_DAMPING * delta)
	if _idle > IDLE_DELAY:
		lon += (SPIN_HOVER if _hovered else SPIN) * delta
	_apply_rotation()


## Shows another planet's colour map on the same globe (size, light, spin and hover unchanged)
func set_planet(id: StringName) -> void:
	var index: int = PlanetData.index_of(id)
	if index < 0 or id == planet_id:
		return
	planet_id = id
	_material.set_shader_parameter(&"albedo_map", load(PlanetData.PLANETS[index].map))


## The facing point (lat, lon) turned towards the camera (+Z)
func _apply_rotation() -> void:
	_pivot.basis = Basis(Vector3.RIGHT, lat) * Basis(Vector3.UP, -lon)


func _set_hovered(hovered: bool) -> void:
	if hovered == _hovered:
		return
	_hovered = hovered
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.set_ignore_time_scale(true)
	_hover_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_hover_tween.set_ease(Tween.EASE_IN_OUT)
	_hover_tween.set_trans(Tween.TRANS_SINE)
	_hover_tween.tween_method(_set_hover_amount, _hover_amount, 1.0 if hovered else 0.0, HOVER_TIME)


func _set_hover_amount(value: float) -> void:
	_hover_amount = value
	_apply_transform()
	_apply_brightness()


func _apply_transform() -> void:
	if not is_node_ready():
		return
	_apply_layout()
	scale = Vector2.ONE * intro_scale * lerpf(1.0, HOVER_SCALE, _hover_amount)


func _apply_brightness() -> void:
	if _material:
		_material.set_shader_parameter(&"brightness",
			intro_brightness * lerpf(1.0, HOVER_BRIGHTNESS, _hover_amount))
