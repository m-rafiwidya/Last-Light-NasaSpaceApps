extends Node3D

## A Robot's sounds (added by Sfx): wheels rolling on the ground, suspension bumps, power up /
## down, the battery-low alert, and grab / drop / throw for its holder. Its motor whir is the
## Robot's EngineSound; this hands it to Sfx as a loop. While this rover is driven, the motor,
## the wheels and the bumps are the main layer, which nothing ducks.

## Wheel ground speed (m/s) at which the rolling loop plays at full level
const ROLL_FULL_SPEED: float = 2.5
const ROLL_DB: float = 0.0
## Rolling pitch at standstill / full speed (non-tonal, so it may follow the speed)
const ROLL_PITCH: Vector2 = Vector2(0.8, 1.2)
const ROLL_RESPONSE: float = 10.0
## A bump: a wheel touches down again while the chassis comes down at least this fast (m/s) along
## its up axis (a landing, a rock); full level from BUMP_FULL_SPEED. (The soft, heavily damped
## suspension spreads the stop itself over half a second, too slow to hear as a thump.)
const BUMP_MIN_SPEED: float = 0.5
const BUMP_FULL_SPEED: float = 3.0
const BUMP_COOLDOWN: float = 0.25
## A jump in position bigger than this in one step is a reset (F), not a bump
const TELEPORT_DISTANCE: float = 0.5
## The battery-low alert re-arms once the charge is this far back above the sag threshold
const BATTERY_REARM: float = 0.02

var robot: Robot
var _rolling                            # Sfx.Loop
var _engine                             # Sfx.Loop (the EngineSound)
var _roll_level: float = 0.0
var _in_contact: Dictionary = {}         # wheel -> on the ground last step
var _previous_position: Vector3 = Vector3.ZERO
var _bump_cooldown: float = 0.0
var _powered: bool = false
var _low_armed: bool = true


func _ready() -> void:
	robot = get_parent() as Robot
	Sfx.watch_holder(robot.holder)
	_rolling = Sfx.make_loop(&"rolling_loop", robot, ROLL_DB)
	var engine_sound := robot.get_node_or_null("EngineSound")
	if engine_sound:
		_engine = Sfx.adopt_loop(engine_sound)
	_previous_position = robot.global_position
	_powered = _is_powered()


func is_main() -> bool:
	return robot.is_driven() and GameState.state == GameState.State.IN_GAME_ROBOT


func _physics_process(delta: float) -> void:
	var main: bool = is_main()
	_update_rolling(delta, main)
	_update_bump(delta, main)
	_update_power()
	_update_battery_alert(main)


func _update_rolling(delta: float, main: bool) -> void:
	var gear: RunningGear = robot.running_gear
	var speed: float = 0.0
	var touching: int = 0
	for wheel in gear.wheel_states:
		if gear.wheel_states[wheel][RunningGear.WheelState.IN_CONTACT]:
			touching += 1
			speed += absf(gear.wheel_states[wheel][RunningGear.WheelState.ANGULAR_VELOCITY]) \
					* gear.wheel_properties[wheel][RunningGear.WheelProperty.EFFECTIVE_RADIUS]
	var fraction: float = clampf(speed / maxi(touching, 1) / ROLL_FULL_SPEED, 0.0, 1.0)
	_roll_level = lerpf(_roll_level, fraction, 1.0 - exp(-ROLL_RESPONSE * delta))
	_rolling.gain = pow(_roll_level, 0.6) if _roll_level > 0.01 else 0.0
	_rolling.main = main
	_rolling.player.pitch_scale = lerpf(ROLL_PITCH.x, ROLL_PITCH.y, _roll_level)
	if _engine:
		var engine_sound = _engine.player
		_engine.audible = engine_sound.loudness * engine_sound.volume
		_engine.main = main


func _update_bump(delta: float, main: bool) -> void:
	var falling: float = -robot.linear_velocity.dot(robot.global_basis.y)
	var position: Vector3 = robot.global_position
	var teleported: bool = position.distance_to(_previous_position) > TELEPORT_DISTANCE
	_previous_position = position
	_bump_cooldown = maxf(_bump_cooldown - delta, 0.0)
	var touched_down: bool = false
	var states: Dictionary = robot.running_gear.wheel_states
	for wheel in states:
		var contact: bool = states[wheel][RunningGear.WheelState.IN_CONTACT]
		if contact and not _in_contact.get(wheel, true):
			touched_down = true
		_in_contact[wheel] = contact
	if teleported or not touched_down or falling < BUMP_MIN_SPEED or _bump_cooldown > 0.0:
		return
	_bump_cooldown = BUMP_COOLDOWN
	var level: float = clampf(remap(falling, BUMP_MIN_SPEED, BUMP_FULL_SPEED, 0.0, 1.0), 0.0, 1.0)
	Sfx.play(&"bump", robot, lerpf(-14.0, 0.0, level), main)


func _is_powered() -> bool:
	return robot.require_battery and robot.battery != null and not robot.battery.is_empty()


func _update_power() -> void:
	var powered: bool = _is_powered()
	if powered != _powered:
		Sfx.play(&"power_up" if powered else &"power_down", robot, 0.0, false, false)
	_powered = powered


func _update_battery_alert(main: bool) -> void:
	var battery: BatteryPart = robot.battery
	if battery == null:
		_low_armed = true
		return
	var fraction: float = battery.get_charge_fraction()
	if fraction > battery.sag_threshold + BATTERY_REARM:
		_low_armed = true
	elif fraction <= battery.sag_threshold and _low_armed and not battery.is_empty():
		_low_armed = false
		if main:
			Sfx.play(&"battery_low", null, 0.0, false, false)
