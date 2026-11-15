extends UIScreen

## HUD shown while the robot is being driven (GameState.IN_GAME_ROBOT).
## The player HUD is shown in IN_GAME_PLAYER instead; both carry a SubtitleStack.


# How long the "no zoom here" hint stays up after a zoom input in a view without zoom, and
# how long it takes to fade out at the end
const ZOOM_HINT_TIME: float = 1.8
const ZOOM_HINT_FADE: float = 0.4

var fade_tween: Tween = null
var tips := TipCard.new()
var _cargo_label: Label = null


func _ready() -> void:
	add_child(BoundaryHint.new(true))
	add_child(DockHint.new())
	add_child(CargoHint.new())
	add_child(ScanHint.new())
	add_child(MissionHint.new())
	tips.avoid = $SubtitleStack
	add_child(tips)
	# CARGO under BATTERY: what the cargo mount holds (IRIS_KIT.md 5.3)
	_cargo_label = Label.new()
	_cargo_label.name = "Cargo"
	_cargo_label.add_theme_font_size_override("font_size", 32)
	_cargo_label.text = "CARGO  --"
	%Battery.get_parent().add_child(_cargo_label)
	%Battery.get_parent().move_child(_cargo_label, %Battery.get_index() + 1)
	hide()
	$CanvasModulate.color = Color(1.0, 1.0, 1.0, 0.0)


func _process(_delta: float) -> void:
	if not visible:
		return
	_update_tips()
	var looking_at_prop: bool = false
	if is_instance_valid(Debug.current_robot):
		%Speed.text = "SPEED  %4.1f m/s%s" % [Debug.current_robot.linear_velocity.length(),
			"  BRAKE" if Debug.current_robot.braking else ""]
		var looking_at = Debug.current_robot.looking_at_object
		if not is_instance_valid(looking_at):
			looking_at = null           # freed since the robot's last physics tick
		looking_at_prop = looking_at is RigidBody3D and Debug.current_robot.pickup_enabled
		var holding: bool = looking_at != null and looking_at == Debug.current_robot.holder.held_object
		%PartTooltip.show_for(looking_at, false, holding)
		_update_battery_label(Debug.current_robot)
		_update_cargo_label(Debug.current_robot)
		_update_arm_label(Debug.current_robot)
		_update_view_label(Debug.current_robot)
	else:
		%View.text = "VIEW  --"
		%ZoomHint.hide()
		%Speed.text = "SPEED  --"
		%Battery.text = "BATTERY  --"
		_cargo_label.text = "CARGO  --"
		%Arm.text = "ARM  --"
		%PartTooltip.hide()
	var aiming: bool = is_instance_valid(Debug.current_robot) and Debug.current_robot.is_aiming()
	%Crosshair.visible = aiming and not looking_at_prop
	%InteractCrosshair.visible = looking_at_prop


## The driving tip, the first time Kite is driven
func _update_tips() -> void:
	var workshop := get_tree().get_first_node_in_group(&"workshop") as Workshop
	if GameState.state != GameState.State.IN_GAME_ROBOT:
		tips.dismiss()
	elif workshop and workshop.rover == GameState.robot:
		tips.offer(&"drive")


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


func _update_cargo_label(robot: Robot) -> void:
	var socket := robot.get_node_or_null("CargoSocket") as HotswapSocket
	_cargo_label.text = "CARGO  " + (socket.part.get_display_name() if socket and socket.part else "empty")


func _update_view_label(robot: Robot) -> void:
	var rig := robot.get_node_or_null("CameraRig") as RoverCamera
	if rig == null:
		%View.text = "VIEW  --"
		%ZoomHint.hide()
		return
	_update_zoom_hint(rig)
	var text: String = "VIEW  " + rig.view_name()
	if rig.view == RoverCamera.View.MAST and rig.mast_zoom() > 1.05:
		text += "  %.1fx" % rig.mast_zoom()
	%View.text = text


# Shown for a moment after a zoom input in a view that has no zoom
func _update_zoom_hint(rig: RoverCamera) -> void:
	var age: float = rig.zoom_refused_age
	if age > ZOOM_HINT_TIME or rig.view == RoverCamera.View.MAST:
		%ZoomHint.hide()
		return
	if rig.is_available(RoverCamera.View.MAST):
		%ZoomHint.text = "No zoom on the %s: only the mast camera zooms (%s to switch)" % [rig.view_name().to_lower(),
			InputBindings.action_text(&"camera_next")]
	else:
		%ZoomHint.text = "No zoom on the %s: zooming needs a mast camera" % rig.view_name().to_lower()
	%ZoomHint.modulate.a = clampf((ZOOM_HINT_TIME - age) / ZOOM_HINT_FADE, 0.0, 1.0)
	if not %ZoomHint.visible:
		AudioManager.play_ui(&"error")   # the refused zoom
	%ZoomHint.show()


func _update_arm_label(robot: Robot) -> void:
	var visuals := robot.get_node_or_null("Visuals") as RoverVisuals
	if visuals == null:
		%Arm.text = "ARM  --"
		return
	var text: String
	if visuals.arm_scripted:
		text = "ARM  delivering cargo"
	elif visuals.cargo_loaded():
		text = "ARM  cargo loaded: automatic only"
	elif not visuals.arm_target.is_empty():
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
