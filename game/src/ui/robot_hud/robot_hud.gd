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
		_update_arm_label(Debug.current_robot)
		_update_view_label(Debug.current_robot)
	else:
		%View.text = "VIEW  --"
		%Speed.text = "SPEED  --"
		%Battery.text = "BATTERY  --"
		%Arm.text = "ARM  --"
	var aiming: bool = is_instance_valid(Debug.current_robot) and Debug.current_robot.is_aiming()
	%Crosshair.visible = aiming and not looking_at_prop
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


func _update_view_label(robot: Robot) -> void:
	var rig := robot.get_node_or_null("CameraRig") as RoverCamera
	if rig == null:
		%View.text = "VIEW  --"
		return
	var text: String = "VIEW  " + rig.view_name()
	if rig.view == RoverCamera.View.MAST and rig.mast_zoom() > 1.05:
		text += "  %.1fx" % rig.mast_zoom()
	%View.text = text


func _update_arm_label(robot: Robot) -> void:
	var visuals := robot.get_node_or_null("Visuals") as RoverVisuals
	if visuals == null:
		%Arm.text = "ARM  --"
		return
	var text: String
	if not visuals.arm_target.is_empty():
		text = "ARM  deploying" if visuals.arm_deployed else "ARM  stowing"
	elif not visuals.arm_deployed:
		text = "ARM  stowed"
	else:
		var index: int = robot.controller.arm_joint - 1
		var joint: String = RoverVisuals.ARM_JOINT_NAMES[index]
		text = "ARM  %s %s  %+.0f" % [joint, RoverVisuals.ARM_JOINT_LABELS[index], visuals.arm_joints[joint]]
	if visuals.arm_blocked:
		text += "  (ground)"
	%Arm.text = text
	%Arm.modulate = Color(1.0, 0.4, 0.3) if visuals.arm_blocked else Color.WHITE


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
