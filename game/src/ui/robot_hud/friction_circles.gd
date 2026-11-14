extends Control

## Debug traction display: one friction circle per wheel.
##
## Each circle is the tyre's grip limit (friction coefficient * wheel grip * vertical load). The
## dot is the force the ground currently puts on that wheel, drawn in the wheel's own
## frame: up = driving force (accelerating), down = braking, sideways = cornering.
## Dot on the rim = the tyre is at its limit, outside = sliding. A fading trail shows
## where the dot has been, the arc around each circle shows how much grip is in use,
## and the side bar shows the wheel's load relative to its static share of the weight.

# Indexed by RunningGear.Wheel (FRONT_LEFT, FRONT_RIGHT, REAR_LEFT, REAR_RIGHT, MIDDLE_LEFT, MIDDLE_RIGHT)
const WHEEL_NAMES: Array[String] = ["FL", "FR", "RL", "RR", "ML", "MR"]
# Display row per wheel: front, middle, rear. Left wheels (even values) go in the left column.
const WHEEL_ROWS: Array[int] = [0, 0, 2, 2, 1, 1]

const RADIUS: float = 44.0
const HEADER_HEIGHT: float = 26.0
const COLUMN_X: Array[float] = [62.0, 226.0]
const ROW_Y: Array[float] = [HEADER_HEIGHT + 40.0, HEADER_HEIGHT + 180.0, HEADER_HEIGHT + 320.0]
const TRAIL_LENGTH: int = 28
# Dot is allowed to leave the circle a bit so over-the-limit slip is visible
const MAX_DISPLAY_RATIO: float = 1.3
const SMOOTHING: float = 28.0
const VELOCITY_SCALE: float = 8.0
const VELOCITY_MAX_LENGTH: float = 34.0

const COLOR_GRIP_OK := Color(0.35, 0.92, 0.78)
const COLOR_GRIP_EDGE := Color(1.0, 0.82, 0.28)
const COLOR_GRIP_LOST := Color(1.0, 0.3, 0.26)
const COLOR_GUIDE := Color(1.0, 1.0, 1.0, 0.10)
const COLOR_TEXT := Color(0.82, 0.88, 0.95, 0.9)
const COLOR_TEXT_DIM := Color(0.82, 0.88, 0.95, 0.5)

var _normalized_force: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var _trails: Array = [[], [], [], [], [], []]
var _load: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _in_contact: Array[bool] = [false, false, false, false, false, false]
var _steer_angle: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _local_velocity: Vector3 = Vector3.ZERO
var _static_load: float = 1.0
var _has_data: bool = false

var _panel_style: StyleBoxFlat
var _chassis_style: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Color(0.03, 0.05, 0.08, 0.55)
	_panel_style.border_color = Color(0.55, 0.8, 1.0, 0.35)
	_panel_style.set_border_width_all(1)
	_panel_style.set_corner_radius_all(10)
	_panel_style.anti_aliasing = true

	_chassis_style = StyleBoxFlat.new()
	_chassis_style.bg_color = Color(1.0, 1.0, 1.0, 0.04)
	_chassis_style.border_color = Color(1.0, 1.0, 1.0, 0.25)
	_chassis_style.set_border_width_all(2)
	_chassis_style.set_corner_radius_all(12)
	_chassis_style.anti_aliasing = true


func _process(delta: float) -> void:
	var layer: CanvasLayer = get_canvas_layer_node()
	if layer and not layer.visible:
		return

	_update_data(delta)
	queue_redraw()


func _update_data(delta: float) -> void:
	var robot: Robot = Debug.current_robot
	_has_data = is_instance_valid(robot) and not robot.running_gear.wheel_properties.is_empty()
	if not _has_data:
		return

	var gear: RunningGear = robot.running_gear
	var inverse_basis: Basis = robot.global_basis.orthonormalized().inverse()
	var up: Vector3 = robot.global_basis.y.normalized()
	var blend: float = 1.0 - exp(-SMOOTHING * delta)

	_static_load = maxf(robot.mass * float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) / float(RunningGear.Wheel.size()), 1.0)
	_local_velocity = inverse_basis * robot.linear_velocity

	for wheel in RunningGear.Wheel.values():
		var state: Dictionary = gear.wheel_states[wheel]

		var steer_angle: float = gear.get_steer_angle(wheel, robot.controller.steer)
		_steer_angle[wheel] = lerp_angle(_steer_angle[wheel], steer_angle, blend)

		var in_contact: bool = state[RunningGear.WheelState.IN_CONTACT]
		_in_contact[wheel] = in_contact

		var wheel_load: float = maxf(state[RunningGear.WheelState.LOAD].dot(up), 0.0)
		_load[wheel] = lerpf(_load[wheel], wheel_load, blend)

		var target: Vector2 = Vector2.ZERO
		if in_contact and wheel_load > 1.0:
			var force: Vector3 = inverse_basis * state[RunningGear.WheelState.FORCE]
			var forward: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, steer_angle)
			var right: Vector3 = forward.rotated(Vector3.UP, -PI / 2.0)
			var longitudinal: float = force.dot(forward) / (gear.get_longitudinal_friction(wheel) * wheel_load)
			var lateral: float = force.dot(right) / (gear.get_lateral_friction(wheel) * wheel_load)
			# Screen space: +x right, -y forward (driving force points up)
			target = Vector2(lateral, -longitudinal)

		_normalized_force[wheel] = _normalized_force[wheel].lerp(target, blend)

		var trail: Array = _trails[wheel]
		trail.push_back(_normalized_force[wheel])
		if trail.size() > TRAIL_LENGTH:
			trail.pop_front()


func _draw() -> void:
	draw_style_box(_panel_style, Rect2(Vector2.ZERO, size))

	var font: Font = get_theme_default_font()
	draw_string(font, Vector2(14.0, 18.0), "TRACTION", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, COLOR_TEXT)
	draw_string(font, Vector2(size.x - 14.0 - 120.0, 18.0), "GRIP USED", HORIZONTAL_ALIGNMENT_RIGHT, 120.0, 11, COLOR_TEXT_DIM)

	var center_x: float = size.x / 2.0
	_draw_chassis(center_x)

	if not _has_data:
		draw_string(font, Vector2(0.0, size.y / 2.0), "NO ROBOT", HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, COLOR_TEXT_DIM)
		return

	for wheel in RunningGear.Wheel.values():
		_draw_wheel_circle(wheel, font)


func _draw_chassis(center_x: float) -> void:
	var top: float = ROW_Y[0] - 14.0
	var bottom: float = ROW_Y[2] + 14.0
	var half_width: float = 26.0
	draw_style_box(_chassis_style, Rect2(center_x - half_width, top, half_width * 2.0, bottom - top))

	# Forward arrow
	var arrow_tip := Vector2(center_x, top + 12.0)
	draw_colored_polygon(
		PackedVector2Array([arrow_tip, arrow_tip + Vector2(-8.0, 14.0), arrow_tip + Vector2(8.0, 14.0)]),
		Color(1.0, 1.0, 1.0, 0.35)
	)

	# Wheels at the chassis corners, rotated by their steering angle
	for wheel in RunningGear.Wheel.values():
		var pos := Vector2(center_x + (-half_width if wheel % 2 == 0 else half_width), ROW_Y[WHEEL_ROWS[wheel]])
		var angle: float = -_steer_angle[wheel] if _has_data else 0.0
		draw_set_transform(pos, angle, Vector2.ONE)
		var tint: Color = _grip_color(_normalized_force[wheel].length()) if _has_data and _in_contact[wheel] else Color(1.0, 1.0, 1.0, 0.25)
		draw_rect(Rect2(Vector2(-4.0, -11.0), Vector2(8.0, 22.0)), tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Chassis-frame velocity
	if _has_data:
		var center := Vector2(center_x, (top + bottom) / 2.0 + 6.0)
		var velocity := Vector2(_local_velocity.x, _local_velocity.z) * VELOCITY_SCALE
		velocity = velocity.limit_length(VELOCITY_MAX_LENGTH)
		var velocity_color := Color(0.45, 0.75, 1.0)
		draw_line(center, center + velocity, Color(velocity_color, 0.9), 3.0, true)
		draw_circle(center + velocity, 3.5, velocity_color)
		draw_circle(center, 2.0, Color(1.0, 1.0, 1.0, 0.5))


func _draw_wheel_circle(wheel: int, font: Font) -> void:
	var center := Vector2(COLUMN_X[wheel % 2], ROW_Y[WHEEL_ROWS[wheel]])
	var contact: bool = _in_contact[wheel]
	var displayed: Vector2 = _normalized_force[wheel]
	var utilisation: float = displayed.length()
	var color: Color = _grip_color(utilisation) if contact else Color(0.6, 0.65, 0.7)
	var alpha: float = 1.0 if contact else 0.45

	# Backdrop and guides
	draw_circle(center, RADIUS, Color(0.0, 0.0, 0.0, 0.35))
	draw_arc(center, RADIUS * 0.5, 0.0, TAU, 48, COLOR_GUIDE, 1.0, true)
	draw_line(center + Vector2(-RADIUS, 0.0), center + Vector2(RADIUS, 0.0), COLOR_GUIDE, 1.0)
	draw_line(center + Vector2(0.0, -RADIUS), center + Vector2(0.0, RADIUS), COLOR_GUIDE, 1.0)

	# Grip limit
	draw_arc(center, RADIUS, 0.0, TAU, 72, Color(color, 0.85 * alpha), 2.0, true)

	# Utilisation gauge around the circle
	draw_arc(center, RADIUS + 6.0, 0.0, TAU, 72, Color(1.0, 1.0, 1.0, 0.07), 3.0, true)
	var gauge: float = clampf(utilisation, 0.0, 1.0)
	if gauge > 0.01:
		draw_arc(center, RADIUS + 6.0, -PI / 2.0, -PI / 2.0 + TAU * gauge, 72, Color(color, alpha), 3.0, true)

	# Trail
	var trail: Array = _trails[wheel]
	if contact and trail.size() > 1:
		var points := PackedVector2Array()
		var colors := PackedColorArray()
		for i in trail.size():
			points.push_back(center + _clamp_display(trail[i]) * RADIUS)
			colors.push_back(Color(color, 0.5 * float(i) / float(trail.size())))
		draw_polyline_colors(points, colors, 2.5, true)

	# Force vector and dot
	var dot: Vector2 = center + _clamp_display(displayed) * RADIUS
	if contact:
		draw_line(center, dot, Color(color, 0.55), 2.0, true)
		draw_circle(dot, 10.0, Color(color, 0.18))
		draw_circle(dot, 6.0, color)
		draw_circle(dot, 2.2, Color(1.0, 1.0, 1.0, 0.9))
	else:
		draw_string(font, center + Vector2(-RADIUS, 4.0), "AIRBORNE", HORIZONTAL_ALIGNMENT_CENTER, RADIUS * 2.0, 11, COLOR_TEXT_DIM)

	draw_circle(center, 2.0, Color(1.0, 1.0, 1.0, 0.35))

	# Wheel name, grip percentage and load
	var label_width: float = RADIUS * 2.0
	draw_string(font, Vector2(center.x - RADIUS, center.y - RADIUS - 12.0), WHEEL_NAMES[wheel], HORIZONTAL_ALIGNMENT_LEFT, label_width, 13, COLOR_TEXT)
	draw_string(font, Vector2(center.x - RADIUS, center.y - RADIUS - 12.0), "%3d%%" % roundi(utilisation * 100.0), HORIZONTAL_ALIGNMENT_RIGHT, label_width, 13, Color(color, alpha))
	draw_string(font, Vector2(center.x - RADIUS, center.y + RADIUS + 22.0), "%d N" % roundi(_load[wheel]), HORIZONTAL_ALIGNMENT_CENTER, label_width, 11, COLOR_TEXT_DIM)

	_draw_load_bar(wheel, center)


## Vertical bar on the outer side of the circle. The tick marks the wheel's static
## share of the robot's weight; the bar tops out at twice that.
func _draw_load_bar(wheel: int, center: Vector2) -> void:
	var bar_height: float = RADIUS * 2.0
	var bar_x: float = center.x - RADIUS - 24.0 if wheel % 2 == 0 else center.x + RADIUS + 20.0
	var top: float = center.y - RADIUS
	var ratio: float = clampf(_load[wheel] / (_static_load * 2.0), 0.0, 1.0)

	draw_rect(Rect2(bar_x, top, 4.0, bar_height), Color(1.0, 1.0, 1.0, 0.08))
	var fill: float = bar_height * ratio
	draw_rect(Rect2(bar_x, top + bar_height - fill, 4.0, fill), Color(0.45, 0.75, 1.0, 0.85))
	var tick_y: float = top + bar_height * 0.5
	draw_line(Vector2(bar_x - 3.0, tick_y), Vector2(bar_x + 7.0, tick_y), Color(1.0, 1.0, 1.0, 0.5), 1.0)


func _clamp_display(value: Vector2) -> Vector2:
	return value.limit_length(MAX_DISPLAY_RATIO)


func _grip_color(utilisation: float) -> Color:
	if utilisation < 0.6:
		return COLOR_GRIP_OK.lerp(COLOR_GRIP_EDGE, utilisation / 0.6)
	return COLOR_GRIP_EDGE.lerp(COLOR_GRIP_LOST, clampf((utilisation - 0.6) / 0.5, 0.0, 1.0))
