extends UIScreen

## HUD shown while the robot is being driven (GameState.IN_GAME_ROBOT).
## The player HUD is shown in IN_GAME_PLAYER instead; both carry a SubtitleStack.


# How long the "no zoom here" hint stays up after a zoom input in a view without zoom, and
# how long it takes to fade out at the end
const ZOOM_HINT_TIME: float = 1.8
const ZOOM_HINT_FADE: float = 0.4
## Viewport width under which the stats block goes compact
const COMPACT_BELOW: float = 1400.0

var fade_tween: Tween = null
var tips := TipCard.new()


func _ready() -> void:
	add_child(BoundaryHint.new(true))
	add_child(DockHint.new())
	add_child(CargoHint.new())
	add_child(ScanHint.new())
	add_child(MissionHint.new())
	tips.avoid = $SubtitleStack
	add_child(tips)
	$SubtitleStack.keep_out.assign([%Stats])
	get_viewport().size_changed.connect(_fit_stats)
	_fit_stats()
	%PartTooltip.avoid = $SubtitleStack
	hide()
	$CanvasModulate.color = Color(1.0, 1.0, 1.0, 0.0)


func _process(_delta: float) -> void:
	if not visible:
		return
	_update_tips()
	var looking_at_prop: bool = false
	if is_instance_valid(Debug.current_robot):
		var robot: Robot = Debug.current_robot
		%Speed.text = "%.1f m/s%s" % [robot.linear_velocity.length(), "  ·  brake" if robot.braking else ""]
		var looking_at = robot.looking_at_object
		if not is_instance_valid(looking_at):
			looking_at = null           # freed since the robot's last physics tick
		looking_at_prop = looking_at is RigidBody3D and robot.pickup_enabled
		var holding: bool = looking_at != null and looking_at == robot.holder.held_object
		%PartTooltip.show_for(looking_at, false, holding)
		_update_battery_label(robot)
		_update_cargo_label(robot)
		_set_row(%Heater, %HeaterCaption, "%.0f W" % robot.heater_power if robot.heater_power > 0.0 else "")
		_update_arm_label(robot)
		_update_view_label(robot)
	else:
		%View.text = "--"
		%ZoomHint.hide()
		%Speed.text = "--"
		_set_battery("--", "", 0.0, false)
		%Cargo.text = "--"
		%Mass.text = "--"
		_set_row(%Heater, %HeaterCaption, "")
		%Arm.text = "--"
		%PartTooltip.hide()
	var aiming: bool = is_instance_valid(Debug.current_robot) and Debug.current_robot.is_aiming()
	%Crosshair.visible = aiming and not looking_at_prop
	%InteractCrosshair.visible = looking_at_prop


## A narrower stats block on narrow screens, so the subtitles fit beside it
func _fit_stats() -> void:
	var compact: bool = get_viewport().get_visible_rect().size.x < COMPACT_BELOW
	%Stats.custom_minimum_size.x = 280.0 if compact else 360.0
	%BatteryBar.compact = compact
	for caption in %Stats.get_node("Rows").get_children():
		if caption.name.ends_with("Caption"):
			caption.custom_minimum_size.x = 80.0 if compact else 108.0


func _set_row(value: Label, caption: Label, text: String) -> void:
	value.text = text
	value.visible = text != ""
	caption.visible = value.visible


## Red only for a real warning
func _set_warn(label: Label, warn: bool, normal: StringName = &"LabelHudValue") -> void:
	label.theme_type_variation = &"LabelHudValueWarn" if warn else normal


func _set_battery(text: String, power: String, fraction: float, low: bool) -> void:
	%Battery.text = text
	%Power.text = power
	%BatteryBar.fraction = fraction
	%BatteryBar.low = low
	_set_warn(%Battery, low, &"LabelHudValueStrong")


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
		_set_battery("No battery" if robot.require_battery else "--", "", 0.0, robot.require_battery)
		return
	var fraction: float = battery.get_charge_fraction()
	# Red when the battery is low enough that the motor starts to sag
	_set_battery("%d%%" % roundi(fraction * 100.0), "%.0f W" % (robot.electrical_power + robot.electronics_power
		+ robot.heater_power), fraction, fraction <= battery.sag_threshold)


func _update_cargo_label(robot: Robot) -> void:
	var socket := robot.get_node_or_null("CargoSocket") as HotswapSocket
	%Cargo.text = "%s  %.1f kg" % [socket.part.get_display_name(), socket.part.mass] if socket and socket.part else "Empty"
	var extra: float = robot.mass - Robot.REFERENCE_MASS
	%Mass.text = "%.0f kg%s" % [robot.mass, "  (%+.0f kg)" % extra if absf(extra) >= 0.5 else ""]


func _update_view_label(robot: Robot) -> void:
	var rig := robot.get_node_or_null("CameraRig") as RoverCamera
	if rig == null:
		%View.text = "--"
		%ZoomHint.hide()
		return
	_update_zoom_hint(rig)
	var text: String = rig.view_name()
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
		%Arm.text = "--"
		return
	var text: String
	if visuals.arm_scripted:
		text = "Delivering cargo"
	elif visuals.cargo_loaded():
		text = "Cargo loaded: automatic only"
	elif not visuals.arm_target.is_empty():
		text = "Deploying" if visuals.arm_deployed else "Stowing"
	elif not visuals.arm_deployed:
		text = "Stowed"
	else:
		var index: int = robot.controller.arm_joint - 1
		var joint: String = RoverVisuals.ARM_JOINT_NAMES[index]
		text = "%s %s  %+.0f" % [joint, RoverVisuals.ARM_JOINT_LABELS[index], visuals.arm_joints[joint]]
	if visuals.arm_blocked:
		text += "  (ground)"
	%Arm.text = text
	_set_warn(%Arm, visuals.arm_blocked)


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
