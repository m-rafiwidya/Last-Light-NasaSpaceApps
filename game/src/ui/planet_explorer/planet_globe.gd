class_name PlanetGlobe

extends Control

## The planet explorer's globe: the main menu Moon's idea (MenuMoon) for any planet, a real sphere
## in its own SubViewport with the planet's colour map (menu_moon.gdshader), centred in a
## SIZE x SIZE control (the board's 640 px canvas, x 1.2). Drag on the disc turns it; it turns
## slowly by itself after IDLE_DELAY unless `spin` is off, and turn_to() swings it to face a point.
## A press that doesn't move emits `clicked`; a locked globe doesn't turn, and a horizontal drag
## on it (or off the disc) of SWIPE_DISTANCE emits `swiped` (-1 previous, 1 next planet).
## project() gives where a lat / lon is on screen, for the site markers drawn over it.

signal clicked(at: Vector2)
signal swiped(direction: int)

const SIZE: float = 768.0
## Disc radius: the board's canvas radius 266 of 580, shown at 640 px, x 1.2
const DISC_RADIUS: float = 352.0
const MAX_LAT: float = 1.3
const SPIN: float = 0.06
const IDLE_DELAY: float = 1.2
const DRAG_RATE: float = 1.4
const CLICK_SLOP: float = 6.0
const SWIPE_DISTANCE: float = 96.0
## How fast turn_to() closes the gap (1/s)
const TURN_RATE: float = 3.5
## Locked planets are drawn this bright, with a pale ring instead of the atmosphere
const LOCKED_BRIGHTNESS: float = 0.07
const LOCKED_GLOW: Color = Color(0.925, 0.914, 0.89, 0.12)
## The glow ring: from 0.96 R to 1.08 R, brightest a third of the way out (the board's gradient)
const GLOW_INNER: float = 0.96
const GLOW_OUTER: float = 1.08
const GLOW_PEAK: float = 0.35

var lat: float = 0.0
var lon: float = 0.0
## Turns by itself while idle
var spin: bool = true
var locked: bool = false:
	set(value):
		locked = value
		_apply_look()

var _atmosphere: Color = Color(0, 0, 0, 0)
var _target: Vector2 = Vector2.ZERO
var _has_target: bool = false
var _dragging: bool = false
var _rotating: bool = false
var _moved: float = 0.0
var _drag_x: float = 0.0
var _idle: float = 0.0

@onready var _container: SubViewportContainer = $Container
@onready var _viewport: SubViewport = $Container/Viewport
@onready var _pivot: Node3D = $Container/Viewport/Pivot
@onready var _material: ShaderMaterial = ($Container/Viewport/Pivot/Sphere as MeshInstance3D).material_override
@onready var _glow: TextureRect = $Glow


func _ready() -> void:
	resized.connect(_fit_viewport)
	get_tree().root.size_changed.connect(_fit_viewport)
	_fit_viewport()
	_apply_rotation()
	set_active(false)


func disc_centre() -> Vector2:
	return size / 2.0


## Shows `planet` (a PlanetData.PLANETS entry) facing its starting view
func set_planet(planet: Dictionary) -> void:
	_material.set_shader_parameter(&"albedo_map", load(planet.map))
	_atmosphere = planet.atmosphere
	lat = planet.view.x
	lon = planet.view.y
	_has_target = false
	_idle = 0.0
	_apply_rotation()
	_apply_look()


## Swings the globe until (lat, lon) in degrees faces the camera
func turn_to(lat_deg: float, lon_deg: float) -> void:
	_target = Vector2(deg_to_rad(lat_deg), deg_to_rad(lon_deg))
	_has_target = true


func stop_turning() -> void:
	_has_target = false


## Where (lat, lon) in degrees is: x, y in this control, z towards the viewer (1 = disc centre,
## below 0 = far side)
func project(lat_deg: float, lon_deg: float) -> Vector3:
	var la: float = deg_to_rad(lat_deg)
	var lo: float = deg_to_rad(lon_deg)
	var w: Vector3 = _basis() * Vector3(cos(la) * sin(lo), sin(la), cos(la) * cos(lo))
	var c: Vector2 = disc_centre()
	return Vector3(c.x + w.x * DISC_RADIUS, c.y - w.y * DISC_RADIUS, w.z)


## Renders and turns only while the explorer is open
func set_active(active: bool) -> void:
	_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED)
	set_process(active)
	_dragging = false
	mouse_default_cursor_shape = Control.CURSOR_ARROW


func is_active() -> bool:
	return _viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED


func _fit_viewport() -> void:
	var pixels: float = maxf(get_viewport().get_final_transform().get_scale().y, 0.25)
	_container.size = (size * pixels).round()
	_container.scale = size / _container.size


func _on_disc(point: Vector2) -> bool:
	return point.distance_to(disc_centre()) < DISC_RADIUS


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var button := event as InputEventMouseButton
		if button.pressed:
			_dragging = true
			_rotating = not locked and _on_disc(button.position)
			_moved = 0.0
			_drag_x = 0.0
			if _rotating:
				_has_target = false
				mouse_default_cursor_shape = Control.CURSOR_DRAG
		elif _dragging:
			_dragging = false
			_idle = 0.0
			mouse_default_cursor_shape = Control.CURSOR_ARROW
			if not _rotating and absf(_drag_x) > SWIPE_DISTANCE:
				swiped.emit(-1 if _drag_x > 0.0 else 1)
			elif _moved < CLICK_SLOP:
				clicked.emit(button.position)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_moved += absf(motion.relative.x) + absf(motion.relative.y)
		_drag_x += motion.relative.x
		if _rotating:
			var k: float = DRAG_RATE / DISC_RADIUS
			lon -= motion.relative.x * k
			lat = clampf(lat + motion.relative.y * k, -MAX_LAT, MAX_LAT)
			_apply_rotation()
		accept_event()


func _process(delta: float) -> void:
	if _dragging and _rotating:
		return
	_idle += delta
	if _has_target:
		var k: float = minf(1.0, delta * TURN_RATE)
		lon += wrapf(_target.y - lon, -PI, PI) * k
		lat += (_target.x - lat) * k
	elif spin and _idle > IDLE_DELAY:
		lon += SPIN * delta
	_apply_rotation()


## The facing point (lat, lon) turned towards the camera (+Z), as MenuMoon
func _basis() -> Basis:
	return Basis(Vector3.RIGHT, lat) * Basis(Vector3.UP, -lon)


func _apply_rotation() -> void:
	_pivot.basis = _basis()


func _apply_look() -> void:
	if not is_node_ready():
		return
	_material.set_shader_parameter(&"brightness", LOCKED_BRIGHTNESS if locked else 1.0)
	var color: Color = LOCKED_GLOW if locked else _atmosphere
	_glow.visible = color.a > 0.0
	var gradient := (_glow.texture as GradientTexture2D).gradient
	var inner: float = GLOW_INNER / GLOW_OUTER
	gradient.offsets = PackedFloat32Array([0.0, inner, inner + (1.0 - inner) * GLOW_PEAK, 1.0])
	gradient.colors = PackedColorArray([Color(color, 0.0), Color(color, 0.0), color, Color(color, 0.0)])
