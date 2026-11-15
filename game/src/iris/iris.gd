class_name Iris

extends Node3D

## IRIS, the research station (A07, tools/blender/IRIS_KIT.md 6): a static scene
## (res/models/iris_kit/iris.glb, from make_iris.py), never a Robot, so it can't be driven, pushed
## or picked up. The mast camera scans it (RoverScanner, group "scan_target"); its diagnostic port
## (a CargoPort) takes the cartridge from a rover's arm (CargoDelivery). The port's status light:
## red blink until the cartridge is in, amber while it's read, then green.
## The station itself is offline (indicator dark, antenna parked) until set_online(true): the
## indicator lights and the antenna turns to its tracking pose.

signal scanned(rover: Robot)
signal cartridge_inserted(cartridge: HotswapPart, rover: Robot)
signal online_changed(online: bool)

const MODEL: PackedScene = preload("res://res/models/iris_kit/iris.glb")
const READ_TIME: float = 3.0
# Dust: the kit materials, lighter, greyer and rougher (ir_dust is the dust itself)
const DUST: Color = Color(0.56, 0.53, 0.48)
const DUST_AMOUNT: float = 0.25
const NOT_DUSTED: Array[String] = ["ws_status", "ws_glass", "ws_screen"]
# The antenna's two poses, (pan, tilt) in degrees, as make_iris.py's ANTENNA_PARKED / _TRACKED:
# the pan about IRIS's up axis, the tilt about its X (+ = up)
const ANTENNA_PARKED := Vector2(0.0, -25.0)
const ANTENNA_TRACKED := Vector2(35.0, 40.0)
const ANTENNA_TIME: float = 3.0
const INDICATOR_ON := Color(0.35, 1.0, 0.45)
const INDICATOR_OFF := Color(0.07, 0.075, 0.07)
# Words on the plates (text_* anchors): [words, plate size (m), cap height (m), handwritten]
const INK := Color(0.11, 0.115, 0.125)
const PEN := Color(0.10, 0.14, 0.32)
const HAND_FONT: Font = preload("res://res/fonts/caveat-latin-500-normal.woff2")
const FONT_SIZE: int = 64
const CAP_RATIO: float = 0.714
const TEXTS: Dictionary = {
	"text_name": ["IRIS", Vector2(0.50, 0.11), 0.07, false],
	"text_panel_title": ["SERVICE PANEL S-1", Vector2(0.38, 0.045), 0.022, false],
	"text_service_label": ["Radio pwr: J1\nSeals checked\n- Evan", Vector2(0.34, 0.13), 0.06, true],
	"text_conn_j1_a": ["J1 RADIO PWR", Vector2(0.18, 0.024), 0.024, true],
	"text_conn_j1_b": ["J1 RADIO PWR", Vector2(0.18, 0.024), 0.024, true],
	"text_conn_j2_a": ["J2 DATA", Vector2(0.18, 0.024), 0.024, true],
	"text_conn_j2_b": ["J2 DATA", Vector2(0.18, 0.024), 0.024, true],
	"text_conn_j3_a": ["J3 HEATER", Vector2(0.18, 0.024), 0.024, true],
	"text_conn_j3_b": ["J3 HEATER", Vector2(0.18, 0.024), 0.024, true],
}

## Starts online (indicator lit, antenna tracking), e.g. after M2
@export var start_online: bool = false

@export var scan_name: String = "IRIS"
@export_multiline var scan_report: String = "IRIS. Research station, silent: no signal on any band. Diagnostic port open on its front bracket."

## M1's scan target on the service panel (IrisServicePanel, child "ServicePanel" on `scan_point`)
@export var panel_scan_name: String = "IRIS service panel"
@export_multiline var panel_scan_report: String = "IRIS service panel S-1. Image recorded: connectors J1 to J3, Evan's labels readable. J1 radio power shows no supply."

## The seated module's turn about up, from the cartridge's pose (see module_seat_transform)
const MODULE_SEAT_TURN: float = PI / 2.0

## What Guidance lights up when IRIS itself is the target (`path:Iris`, M2's "Bring IRIS online"):
## the station's online indicator on the mast (set in _ready)
@export var highlight_node: Node3D

var is_scanned: bool = false
var has_cartridge: bool = false
var is_online: bool = false
var port: CargoPort = null
## The service panel's scan target (M1)
var service_panel: IrisServicePanel = null
## The radio-power module's socket (socket_module) and seat (anchor_module_seated), for M2
var module_socket: Node3D = null
var module_seat: Node3D = null
## The module bay's install point (M2)
var module_cradle: IrisModuleCradle = null
var _reading: float = -1.0
var _reader: Robot = null
var _time: float = 0.0
var _light := StandardMaterial3D.new()
var _indicator := StandardMaterial3D.new()
var _antenna_pan: Node3D = null
var _antenna_tilt: Node3D = null
var _antenna: float = 0.0          # 0 parked .. 1 tracked


func _ready() -> void:
	add_to_group(&"scan_target")
	add_to_group(&"iris")
	var model: Node3D = MODEL.instantiate()
	model.name = "Model"
	add_child(model)
	_dust(model)
	# IRIS's colliders on layer 2 (vehicles): rovers bump into it, but their wheels' ground check
	# (layers 1, 3) and the arm's ground check (layer 1) don't take it for the ground
	for body in model.find_children("*", "StaticBody3D", true, false):
		(body as StaticBody3D).collision_layer = 2
		(body as StaticBody3D).collision_mask = 0
	_light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_light.emission_enabled = true
	(model.find_child("iris_status_light", true, false) as GeometryInstance3D).material_override = _light
	_indicator.emission_enabled = true
	_indicator.roughness = 0.3
	highlight_node = model.find_child("iris_indicator", true, false) as Node3D
	(highlight_node as GeometryInstance3D).material_override = _indicator
	_antenna_pan = model.find_child("iris_antenna_pan", true, false) as Node3D
	_antenna_tilt = model.find_child("iris_antenna", true, false) as Node3D
	module_socket = model.find_child("socket_module", true, false) as Node3D
	module_seat = model.find_child("anchor_module_seated", true, false) as Node3D
	_add_texts(model)
	set_online(start_online, true)
	var socket := model.find_child("socket_cartridge", true, false) as Node3D
	port = CargoPort.new()
	port.name = "CargoPort"
	port.scan_gate = self
	add_child(port)
	port.global_transform = socket.global_transform.orthonormalized()
	port.seat = model.find_child("anchor_cartridge_seated", true, false) as Node3D
	port.cargo_inserted.connect(_on_cargo_inserted)
	_add_service_panel(model)
	_add_module_cradle(model)


## M2's module bay (IrisModuleCradle, child "ModuleCradle") on the module's seat; it restores a
## seated module itself when the campaign says it's installed
func _add_module_cradle(model: Node) -> void:
	if module_seat == null:
		push_error("Iris: no anchor_module_seated in the model")
		return
	module_cradle = IrisModuleCradle.new()
	module_cradle.name = "ModuleCradle"
	module_cradle.highlight_node = model.find_child("iris_module_socket", true, false) as Node3D
	module_cradle.park_marker = model.find_child("park_module", true, false) as Node3D
	add_child(module_cradle)
	module_cradle.global_transform = module_seat_transform()


## The service panel's scan target on `scan_point`, already scanned if M1's scan is done (a
## reloaded level keeps what the campaign says)
func _add_service_panel(model: Node) -> void:
	var anchor := model.find_child("scan_point", true, false) as Node3D
	if anchor == null:
		push_error("Iris: no scan_point in the model")
		return
	service_panel = IrisServicePanel.new()
	service_panel.name = "ServicePanel"
	service_panel.target_id = "iris_panel"
	service_panel.scan_name = panel_scan_name
	service_panel.scan_report = panel_scan_report
	service_panel.is_scanned = CampaignState.is_objective_done("m1.iris_scanned")
	service_panel.highlight_node = model.find_child("iris_service_panel", true, false) as Node3D
	add_child(service_panel)
	service_panel.global_transform = anchor.global_transform.orthonormalized()


## Where a seated radio-power module's origin goes, and how it lies (IRIS_KIT.md 4.1, 6.2.1): the module's
## long side (its X) runs along the socket's long side, which is along IRIS's side (Blender Y, Godot -Z),
## so the module turns 90 degrees about up from the cartridge's pose. The kit's empties don't turn, so the
## turn is here.
func module_seat_transform() -> Transform3D:
	var seat: Transform3D = module_seat.global_transform.orthonormalized()
	seat.basis = seat.basis * Basis(Vector3.UP, MODULE_SEAT_TURN)
	return seat


## Online: the indicator lit and the antenna tracking; offline: dark and parked. `instant` skips
## the antenna's turn.
func set_online(online: bool, instant: bool = false) -> void:
	var changed := online != is_online
	is_online = online
	if instant:
		_antenna = 1.0 if online else 0.0
	_pose_antenna()
	_indicator.albedo_color = INDICATOR_ON if online else INDICATOR_OFF
	_indicator.emission = INDICATOR_ON if online else Color.BLACK
	_indicator.emission_energy_multiplier = 3.0 if online else 0.0
	if changed:
		online_changed.emit(online)


## The antenna's (pan, tilt) in degrees now
func antenna_pose() -> Vector2:
	return ANTENNA_PARKED.lerp(ANTENNA_TRACKED, smoothstep(0.0, 1.0, _antenna))


func _pose_antenna() -> void:
	var pose := antenna_pose()
	_antenna_pan.rotation = Vector3(0.0, deg_to_rad(pose.x), 0.0)
	_antenna_tilt.rotation = Vector3(deg_to_rad(pose.y), 0.0, 0.0)


## A Label3D on each text_* anchor, facing out of IRIS's front (the anchor's -Z), sized to its plate
func _add_texts(model: Node) -> void:
	for anchor_name in TEXTS:
		var anchor := model.find_child(anchor_name, true, false) as Node3D
		if anchor == null:
			push_error("Iris: no %s in the model" % anchor_name)
			continue
		var spec: Array = TEXTS[anchor_name]
		var label := Label3D.new()
		label.name = "Text"
		label.text = spec[0]
		label.font_size = FONT_SIZE
		label.outline_size = 0
		label.double_sided = false
		label.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		label.modulate = PEN if spec[3] else INK
		if spec[3]:
			label.font = HAND_FONT
		var font: Font = label.font if label.font else ThemeDB.fallback_font
		var px: Vector2 = font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE)
		var box: Vector2 = spec[1]
		label.pixel_size = minf(spec[2] / (CAP_RATIO * FONT_SIZE), minf(box.x / px.x, box.y / px.y))
		# Turned to face IRIS's front; Evan's writing a little crooked
		var tilt: float = deg_to_rad(-2.0 if spec[3] else 0.0)
		label.transform = Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.BACK, tilt), Vector3.ZERO)
		anchor.add_child(label)


func _dust(model: Node) -> void:
	var dusty: Dictionary = {}
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var m := mesh as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var source := m.mesh.surface_get_material(i) as StandardMaterial3D
			if source == null or source.resource_name in NOT_DUSTED \
					or not (source.resource_name.begins_with("rover_") or source.resource_name.begins_with("ws_")):
				continue
			if not dusty.has(source):
				var copy: StandardMaterial3D = source.duplicate()
				copy.albedo_color = source.albedo_color.lerp(DUST, DUST_AMOUNT)
				copy.roughness = minf(source.roughness + 0.2, 1.0)
				copy.metallic = source.metallic * 0.5
				dusty[source] = copy
			m.set_surface_override_material(i, dusty[source])


## Called by RoverScanner when a rover's mast camera has held on IRIS long enough
func mark_scanned(rover: Robot) -> void:
	if is_scanned:
		return
	is_scanned = true
	scanned.emit(rover)


func _on_cargo_inserted(part: HotswapPart, rover: Robot) -> void:
	_reading = 0.0
	_reader = rover


func _process(delta: float) -> void:
	_time += delta
	var target: float = 1.0 if is_online else 0.0
	if _antenna != target:
		_antenna = move_toward(_antenna, target, delta / ANTENNA_TIME)
		_pose_antenna()
	var color := Color(1.0, 0.15, 0.1)
	var level: float = 1.0 if fmod(_time, 1.0) < 0.5 else 0.15
	if _reading >= 0.0:
		_reading += delta
		color = Color(1.0, 0.65, 0.15)
		level = 0.4 + 0.6 * (0.5 + 0.5 * sin(_time * TAU * 2.0))
		if _reading >= READ_TIME:
			_reading = -1.0
			has_cartridge = true
			cartridge_inserted.emit(port.occupant, _reader)
	elif has_cartridge:
		color = Color(0.25, 1.0, 0.35)
		level = 1.0
	_light.albedo_color = color * level
	_light.emission = color
	_light.emission_energy_multiplier = 2.5 * level
