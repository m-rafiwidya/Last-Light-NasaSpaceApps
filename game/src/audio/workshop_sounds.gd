extends Node

## A Workshop's sounds (added by Sfx): the bay door (unlatch, drive loop, seal) and the charging
## pad (connect, fully charged, fault). Sfx plays the workshop's ambience itself.

## The door loop fades in / out over this long (s) as the door starts / stops
const DOOR_FADE_TIME: float = 0.3
const DOOR_LOOP_DB: float = 0.0
## Least time (s) between two charger fault sounds
const FAULT_INTERVAL: float = 2.0

var workshop: Workshop
var _door                               # Sfx.Loop
var _door_spot: Node3D
var _door_was: float = 0.0
var _door_moving: bool = false
var _pad_state: ChargingPad.State = ChargingPad.State.IDLE
var _fault_wait: float = 0.0


func _ready() -> void:
	workshop = get_parent() as Workshop
	# The doorway's centre: the bay door's shadow seal fills it
	_door_spot = workshop.get_node_or_null("DoorShadowSeal") as Node3D
	if _door_spot:
		_door = Sfx.make_loop(&"door_loop", _door_spot, DOOR_LOOP_DB)
	_door_was = workshop.door_open
	if workshop.pad:
		_pad_state = workshop.pad.state


func _physics_process(delta: float) -> void:
	_update_door(delta)
	_update_pad(delta)


func _update_door(delta: float) -> void:
	if _door == null:
		return
	var moving: bool = not is_equal_approx(workshop.door_open, _door_was)
	_door_was = workshop.door_open
	if moving and not _door_moving:
		Sfx.play(&"door_start", _door_spot)
	elif not moving and _door_moving:
		Sfx.play(&"door_stop", _door_spot)
	_door_moving = moving
	_door.gain = move_toward(_door.gain, 1.0 if moving else 0.0, delta / DOOR_FADE_TIME)


func _update_pad(delta: float) -> void:
	var pad: ChargingPad = workshop.pad
	if pad == null:
		return
	_fault_wait = maxf(_fault_wait - delta, 0.0)
	var state: ChargingPad.State = pad.state
	if state == _pad_state:
		return
	var docked := [ChargingPad.State.CHARGING, ChargingPad.State.FULL]
	if state in docked and not _pad_state in docked:
		Sfx.play(&"charger_connect", pad)
	if state == ChargingPad.State.FULL and _pad_state == ChargingPad.State.CHARGING:
		Sfx.play(&"charger_full", pad, 0.0, false, false)
	if state == ChargingPad.State.FAULT and _fault_wait <= 0.0:
		_fault_wait = FAULT_INTERVAL
		Sfx.play(&"charger_fault", pad)
	_pad_state = state
