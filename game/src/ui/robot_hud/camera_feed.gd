class_name RoverFeedOverlay

extends Control

## Makes each rover camera view look like a camera feed (RobotHUD's first child, so the rest
## of the HUD draws over it untouched). Chase stays a plain game view.
##   MAST       viewfinder corner brackets, "MASTCAM", a blinking REC dot and a zoom bar
##   HAZ_FRONT  black and white, slight fisheye, vignette, grain; "FRONT HAZCAM"
##   HAZ_REAR   the same; "REAR HAZCAM"
##   TOOL       warm macro look: edges blurred (plus the camera's own depth of field, set by
##              RoverCamera), vignette; "ARM TOOL CAM  MACRO"
## The image treatment is Filter (camera_feed.gdshader over the 3D view); the marks are drawn
## on Marks, above it, so the filter doesn't distort them.

const FONT_SIZE: int = 26
const INK: Color = Color(1.0, 1.0, 1.0, 0.85)
const DIM: Color = Color(1.0, 1.0, 1.0, 0.5)
const SHADOW: Color = Color(0.0, 0.0, 0.0, 0.5)
const REC_RED: Color = Color(1.0, 0.25, 0.2, 0.95)
# Viewfinder brackets: distance from the screen edges, arm length, line width
const BRACKET_INSET: float = 20.0
const BRACKET_ARM: float = 48.0
const BRACKET_WIDTH: float = 3.0
# Where the labels start (top left, inside the brackets) and the zoom bar (top centre)
const LABEL_POSITION: Vector2 = Vector2(64.0, 76.0)
const ZOOM_BAR_WIDTH: float = 260.0
const ZOOM_BAR_Y: float = 66.0
# REC dot: on for REC_ON of every REC_PERIOD seconds
const REC_PERIOD: float = 1.0
const REC_ON: float = 0.6

# Shader settings per view, in SHADER_PARAMETERS order
const SHADER_PARAMETERS: Array[String] = ["desaturate", "contrast", "tint", "fisheye", "vignette",
	"edge_blur", "grain"]
const LOOKS: Dictionary = {
	RoverCamera.View.MAST: [0.0, 1.0, Color(1.0, 1.0, 1.0), 0.0, 0.25, 0.0, 0.025],
	RoverCamera.View.HAZ_FRONT: [1.0, 1.15, Color(1.0, 1.0, 1.0), 0.18, 0.6, 0.0, 0.06],
	RoverCamera.View.HAZ_REAR: [1.0, 1.15, Color(1.0, 1.0, 1.0), 0.18, 0.6, 0.0, 0.06],
	RoverCamera.View.TOOL: [0.0, 1.05, Color(1.05, 1.0, 0.92), 0.0, 0.5, 3.0, 0.03],
}
const LABELS: Dictionary = {
	RoverCamera.View.HAZ_FRONT: "FRONT HAZCAM",
	RoverCamera.View.HAZ_REAR: "REAR HAZCAM",
	RoverCamera.View.TOOL: "ARM TOOL CAM",
}

var filter := ColorRect.new()
var marks := Control.new()
var _view: int = -1
var _zoom: float = 1.0


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	var shader_material := ShaderMaterial.new()
	shader_material.shader = preload("res://src/ui/robot_hud/camera_feed.gdshader")
	filter.material = shader_material
	for child: Control in [filter, marks]:
		child.set_anchors_preset(PRESET_FULL_RECT)
		child.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(child)
	marks.draw.connect(_draw_marks)
	hide()


func _process(_delta: float) -> void:
	var robot = Debug.current_robot
	var rig: RoverCamera = robot.get_node_or_null("CameraRig") as RoverCamera if is_instance_valid(robot) else null
	var view: int = rig.view if rig else RoverCamera.View.CHASE
	visible = LOOKS.has(view)
	if not visible:
		_view = view
		return
	if view != _view:
		_view = view
		var look: Array = LOOKS[view]
		for i in look.size():
			(filter.material as ShaderMaterial).set_shader_parameter(SHADER_PARAMETERS[i], look[i])
	_zoom = rig.mast_zoom()
	# The REC dot blinks and the zoom bar moves
	marks.queue_redraw()


func _draw_marks() -> void:
	var font: Font = get_theme_default_font()
	match _view:
		RoverCamera.View.MAST:
			_draw_brackets()
			if fmod(Time.get_ticks_msec() / 1000.0, REC_PERIOD) < REC_ON:
				marks.draw_circle(LABEL_POSITION + Vector2(9.0, -9.0), 9.0, REC_RED)
			_text(font, LABEL_POSITION + Vector2(28.0, 0.0), "REC", REC_RED)
			_text(font, LABEL_POSITION + Vector2(110.0, 0.0), "MASTCAM", INK)
			_draw_zoom_bar(font)
		RoverCamera.View.TOOL:
			var width: float = _text(font, LABEL_POSITION, LABELS[_view], INK)
			_text(font, LABEL_POSITION + Vector2(width + 24.0, 0.0), "MACRO", DIM)
		_:
			_text(font, LABEL_POSITION, LABELS[_view], INK)


# A corner bracket in each corner of the screen
func _draw_brackets() -> void:
	var rect := Rect2(Vector2.ONE * BRACKET_INSET, marks.size - Vector2.ONE * 2.0 * BRACKET_INSET)
	for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		var point: Vector2 = rect.position + rect.size * corner
		var inward: Vector2 = Vector2.ONE - 2.0 * corner
		var points := PackedVector2Array([point + Vector2(0.0, inward.y * BRACKET_ARM), point,
			point + Vector2(inward.x * BRACKET_ARM, 0.0)])
		marks.draw_polyline(points, SHADOW, BRACKET_WIDTH + 2.0)
		marks.draw_polyline(points, INK, BRACKET_WIDTH)


# W ---|----- T  2.3x: the mast zoom on a log scale from none to the narrowest field of view
func _draw_zoom_bar(font: Font) -> void:
	var max_zoom: float = (tan(deg_to_rad(VideoSettings.fov()) / 2.0)
		/ tan(deg_to_rad(RoverCamera.MAST_FOV_MIN) / 2.0))
	var left := Vector2((marks.size.x - ZOOM_BAR_WIDTH) / 2.0, ZOOM_BAR_Y)
	var right := left + Vector2(ZOOM_BAR_WIDTH, 0.0)
	var fraction: float = clampf(log(_zoom) / log(max_zoom), 0.0, 1.0)
	var mark: Vector2 = left.lerp(right, fraction)
	marks.draw_line(left, right, SHADOW, 4.0)
	marks.draw_line(left, right, DIM, 2.0)
	marks.draw_line(left, mark, INK, 4.0)
	marks.draw_line(mark + Vector2(0.0, -9.0), mark + Vector2(0.0, 9.0), INK, 3.0)
	_text(font, left + Vector2(-40.0, 9.0), "W", DIM)
	_text(font, right + Vector2(12.0, 9.0), "T", DIM)
	_text(font, right + Vector2(42.0, 9.0), "%.1fx" % _zoom, INK)


# Text with a soft shadow at a baseline position; returns its width
func _text(font: Font, at: Vector2, text: String, colour: Color) -> float:
	marks.draw_string(font, at + Vector2(2.0, 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, SHADOW)
	marks.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, colour)
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
