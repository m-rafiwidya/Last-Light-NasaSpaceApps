class_name ChargingPad

extends Node3D

## The workshop's charging / service pad (A02, tools/blender/WORKSHOP_KIT.md 6.1). Sits at the
## pad's origin (the dock point on the floor), axes as the workshop's.
##
## A rover is docked when its origin is within DOCK_ZONE of the dock point, at any heading,
## nearly stopped, with a battery mounted. The charge probe then slides under the contact plate
## to the point below the rover's origin (always inside the belly's clear zone) and rises to
## 20 mm under the belly; while it's up the battery charges (BatteryPart.add_charge). It never
## touches the rover's physics: the probe has no collision.

enum State {IDLE, ON_PAD, ALIGNING, CHARGING, FULL, FAULT}

const DOCK_ZONE: float = 0.4
## Below this speed (m/s) a rover in the zone counts as stopped
const STOPPED_SPEED: float = 0.05
## The rover may drift this far (m) from where the probe met it before the probe drops
const DRIFT_LIMIT: float = 0.05
const PROBE_RISE: float = 0.28
const PROBE_SLIDE_SPEED: float = 0.7
const PROBE_RISE_TIME: float = 0.8
const FAULT_TIME: float = 2.0
## Within this distance (m, horizontal) of the dock point the driven rover gets the dock hint
const HINT_RANGE: float = 3.0

## Charging power (W): a flat 100 Wh battery is full in 3 minutes
@export var charge_power: float = 2000.0

var state: State = State.IDLE
## The rover on the pad (null when none)
var rover: Robot = null
## The probe (charge_probe in ws_pad.glb) and the status light meshes; set by the Workshop
var probe: Node3D = null
var status_meshes: Array[GeometryInstance3D] = []
## The charger's InteractTrigger: its tooltip shows the charge state
var charger_trigger: InteractTrigger = null

var _area: Area3D = null
var _probe_xz: Vector2 = Vector2.ZERO          # probe position under the plate (pad x, z)
var _probe_up: float = 0.0                      # 0 lowered .. 1 raised
var _contact_xz: Vector2 = Vector2.ZERO         # where the probe met the rover
var _fault_time: float = 0.0
var _time: float = 0.0
var _material := StandardMaterial3D.new()


func _ready() -> void:
	add_to_group(&"charging_pad")
	_area = Area3D.new()
	_area.name = "DockArea"
	_area.collision_layer = 0
	_area.collision_mask = 4                    # layer 3: the rovers (and loose parts, ignored)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 1.5, 4.0)
	shape.shape = box
	shape.position = Vector3(0.0, 0.75, 0.0)
	_area.add_child(shape)
	add_child(_area)
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.emission_enabled = true
	for mesh in status_meshes:
		mesh.material_override = _material


## The rover's horizontal offset from the dock point in the pad's frame (x, z)
func offset_of(body: Node3D) -> Vector2:
	var local: Vector3 = to_local(body.global_position)
	return Vector2(local.x, local.z)


func is_in_zone(body: Node3D) -> bool:
	return offset_of(body).length() <= DOCK_ZONE


func charge_fraction() -> float:
	if rover and rover.battery:
		return rover.battery.get_charge_fraction()
	return 0.0


func _find_rover() -> Robot:
	var best: Robot = null
	for body in _area.get_overlapping_bodies():
		if body is Robot and (best == null or offset_of(body).length() < offset_of(best).length()):
			best = body
	return best


func _physics_process(delta: float) -> void:
	_time += delta
	rover = _find_rover()
	var target_xz := Vector2.ZERO
	var raise := false
	_fault_time = maxf(_fault_time - delta, 0.0)
	if rover == null:
		state = State.IDLE
	else:
		var offset := offset_of(rover)
		var stopped: bool = rover.linear_velocity.length() < STOPPED_SPEED
		var in_zone: bool = offset.length() <= DOCK_ZONE
		if state in [State.CHARGING, State.FULL] and (offset - _contact_xz).length() > DRIFT_LIMIT:
			_fault_time = FAULT_TIME                # it moved off the probe
		if not in_zone or not stopped:
			state = State.ON_PAD
		elif rover.battery == null or _fault_time > 0.0:
			state = State.FAULT
		else:
			target_xz = offset
			if _probe_xz.distance_to(offset) > 0.005:
				state = State.ALIGNING              # slide under the belly first
			else:
				raise = true
				if _probe_up >= 1.0:
					if state != State.CHARGING and state != State.FULL:
						_contact_xz = offset
					var full: bool = rover.battery.get_charge_fraction() >= 0.999
					state = State.FULL if full else State.CHARGING
					if not full:
						rover.battery.add_charge(charge_power * delta / 3600.0)
				else:
					state = State.ALIGNING
	# The probe only slides while it's down
	if raise:
		_probe_up = minf(_probe_up + delta / PROBE_RISE_TIME, 1.0)
	else:
		_probe_up = maxf(_probe_up - delta / PROBE_RISE_TIME, 0.0)
	if _probe_up <= 0.0:
		_probe_xz = _probe_xz.move_toward(target_xz, PROBE_SLIDE_SPEED * delta)
	if probe:
		probe.position = Vector3(_probe_xz.x, PROBE_RISE * smoothstep(0.0, 1.0, _probe_up), _probe_xz.y)
	_update_lights()
	if charger_trigger:
		charger_trigger.tooltip = "Charger: " + get_status_text()


## Height of the probe's top above the floor (m)
func probe_height() -> float:
	return probe.position.y if probe else 0.0


func get_status_text() -> String:
	match state:
		State.IDLE:
			return "pad empty"
		State.ON_PAD:
			return "rover on the pad, not docked"
		State.ALIGNING:
			return "connecting"
		State.CHARGING:
			return "charging %d%%" % floori(charge_fraction() * 100.0)
		State.FULL:
			return "charged 100%"
		State.FAULT:
			return "no battery" if rover and rover.battery == null else "rover moved, reconnecting"
	return ""


## What the driven rover's HUD should say about this pad ("" for nothing)
func get_dock_hint(driven: Robot) -> String:
	if driven == null or offset_of(driven).length() > HINT_RANGE:
		return ""
	if driven.battery == null:
		return "No battery to charge"
	if driven == rover:
		match state:
			State.CHARGING:
				return "Charging %d%%" % floori(charge_fraction() * 100.0)
			State.FULL:
				return "Charged 100%"
			State.ALIGNING:
				return "Connecting the charger"
			State.FAULT:
				return "Hold still: reconnecting"
	var to_dock: Vector3 = global_position - driven.global_position
	to_dock.y = 0.0
	if to_dock.length() <= DOCK_ZONE:
		return "Stop here to charge"
	var forward: Vector3 = -driven.global_basis.z
	var right: Vector3 = driven.global_basis.x
	var ahead: float = to_dock.dot(forward)
	var side: float = to_dock.dot(right)
	var parts: PackedStringArray = []
	if absf(ahead) >= 0.05:
		parts.append("%.1f m %s" % [absf(ahead), "ahead" if ahead > 0.0 else "behind"])
	if absf(side) >= 0.05:
		parts.append("%.1f m to the %s" % [absf(side), "right" if side > 0.0 else "left"])
	return "Charging pad: " + ", ".join(parts)


func _update_lights() -> void:
	var color := Color(0.8, 0.8, 0.8)
	var level: float = 0.4
	match state:
		State.ON_PAD, State.ALIGNING:
			color = Color(1.0, 0.65, 0.15)
			level = 1.0 if fmod(_time, 1.0) < 0.5 else 0.15
		State.CHARGING:
			color = Color(0.25, 1.0, 0.35)
			level = 0.35 + 0.65 * (0.5 + 0.5 * sin(_time * TAU * 0.5))
		State.FULL:
			color = Color(0.25, 1.0, 0.35)
			level = 1.0
		State.FAULT:
			color = Color(1.0, 0.15, 0.1)
			level = 1.0 if fmod(_time, 0.25) < 0.125 else 0.1
	_material.albedo_color = color * level
	_material.emission = color
	_material.emission_energy_multiplier = 2.0 * level
