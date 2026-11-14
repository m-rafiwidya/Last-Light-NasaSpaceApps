class_name Kite

extends Node3D

## Kite, the disabled survey rover (A05, tools/blender/KITE_KIT.md 6): a static scene of the rover
## kit's meshes in a damaged pose (res/models/kite_kit/kite.glb, from make_kite.py), never a
## Robot, so it can't be driven, pushed or picked up. The mast camera scans it (RoverScanner, group
## "scan_target"); its service port (a CargoPort) takes the diagnostic cartridge from a rover's
## arm (CargoDelivery). The port's status light: red blink until the cartridge is in, amber while
## it's read, then green.

signal scanned(rover: Robot)
signal cartridge_inserted(cartridge: HotswapPart, rover: Robot)

const MODEL: PackedScene = preload("res://res/models/kite_kit/kite.glb")
const READ_TIME: float = 3.0
# Dust: Kite's kit materials, lighter, greyer and rougher
const DUST: Color = Color(0.56, 0.53, 0.48)
const DUST_AMOUNT: float = 0.35

@export var scan_name: String = "KITE"
@export_multiline var scan_report: String = "Kite. Survey rover, disabled: drive unit failed, arm lost, rear-left wheel off. Diagnostic port open on its front bracket."

var is_scanned: bool = false
var has_cartridge: bool = false
var port: CargoPort = null
var _reading: float = -1.0
var _reader: Robot = null
var _time: float = 0.0
var _light := StandardMaterial3D.new()


func _ready() -> void:
	add_to_group(&"scan_target")
	add_to_group(&"kite")
	var model: Node3D = MODEL.instantiate()
	model.name = "Model"
	add_child(model)
	_dust(model)
	# Kite's colliders on layer 2 (vehicles): rovers bump into it, but their wheels' ground check
	# (layers 1, 3) and the arm's ground check (layer 1) don't take it for the ground
	for body in model.find_children("*", "StaticBody3D", true, false):
		(body as StaticBody3D).collision_layer = 2
		(body as StaticBody3D).collision_mask = 0
	_light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_light.emission_enabled = true
	var light := model.find_child("kite_status_light", true, false) as GeometryInstance3D
	if light:
		light.material_override = _light
	var socket := model.find_child("socket_cartridge", true, false) as Node3D
	port = CargoPort.new()
	port.name = "CargoPort"
	port.scan_gate = self
	add_child(port)
	port.global_transform = socket.global_transform.orthonormalized()
	port.seat = model.find_child("anchor_cartridge_seated", true, false) as Node3D
	port.cargo_inserted.connect(_on_cargo_inserted)


func _dust(model: Node) -> void:
	var dusty: Dictionary = {}
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var m := mesh as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var source := m.mesh.surface_get_material(i) as StandardMaterial3D
			if source == null or not source.resource_name.begins_with("rover_"):
				continue
			if not dusty.has(source):
				var copy: StandardMaterial3D = source.duplicate()
				copy.albedo_color = source.albedo_color.lerp(DUST, DUST_AMOUNT)
				copy.roughness = minf(source.roughness + 0.2, 1.0)
				copy.metallic = source.metallic * 0.5
				dusty[source] = copy
			m.set_surface_override_material(i, dusty[source])


## Called by RoverScanner when a rover's mast camera has held on Kite long enough
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
