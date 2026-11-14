extends UIScreen

## HUD shown while the robot is being driven (GameState.IN_GAME_ROBOT).
## The player HUD (crosshair, subtitles) is shown in IN_GAME_PLAYER instead.


var fade_tween: Tween = null


func _ready() -> void:
	hide()
	$CanvasModulate.color = Color(1.0, 1.0, 1.0, 0.0)


func _process(_delta: float) -> void:
	if not visible:
		return
	var looking_at_prop: bool = false
	if is_instance_valid(Debug.current_robot):
		%Speed.text = "SPEED  %4.1f m/s" % Debug.current_robot.linear_velocity.length()
		var looking_at = Debug.current_robot.looking_at_object
		looking_at_prop = looking_at is InteractTrigger or looking_at is RigidBody3D
		_update_battery_label(Debug.current_robot)
	else:
		%Speed.text = "SPEED  --"
		%Battery.text = "BATTERY  --"
	%Crosshair.visible = not looking_at_prop
	%InteractCrosshair.visible = looking_at_prop


func _update_battery_label(robot: Robot) -> void:
	var battery: BatteryPart = robot.battery
	if not battery:
		%Battery.text = "BATTERY  none" if robot.require_battery else "BATTERY  --"
		%Battery.modulate = Color(1.0, 0.4, 0.3) if robot.require_battery else Color.WHITE
		return
	var fraction: float = battery.get_charge_fraction()
	%Battery.text = "BATTERY  %3d%%  %4.0f W" % [roundi(fraction * 100.0), robot.electrical_power]
	# Turn red when the battery is low enough that the motor starts to sag
	%Battery.modulate = Color(1.0, 0.4, 0.3) if fraction <= battery.sag_threshold else Color.WHITE


func fade_in():
	show()
	_fade_to(1.0)


func fade_out():
	if visible:
		_fade_to(0.0).tween_callback(hide)


# Kills the previous fade so a quick fade_out -> fade_in can't hide the HUD afterwards
func _fade_to(alpha: float) -> Tween:
	if fade_tween:
		fade_tween.kill()
	fade_tween = create_ui_tween()
	fade_tween.tween_property($CanvasModulate, "color", Color(1.0, 1.0, 1.0, alpha), FADE_DURATION)
	return fade_tween
