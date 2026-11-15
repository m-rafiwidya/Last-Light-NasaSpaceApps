class_name RoverCamera

extends Node

## Places the rover's camera (the Robot's Pivot -> Camera3D) for the current view. C cycles
## the views, skipping any whose part isn't mounted; each view keeps its own mouse look.
## Runs after RoverVisuals, which poses the mast head and arm first.
##   CHASE      behind and above the rover, following its heading; mouse look orbits it
##              (its field of view scales with Settings > Video > Field Of View)
##   MAST       on the mast head (needs a mast camera): mouse look pans / tilts the head and
##              pitches the camera to +-90 degrees; the only view that zooms (wheel, trackpad
##              scroll / pinch, = / -). Unzoomed it has the Field Of View setting (VideoSettings).
##   HAZ_FRONT  between the front hazard camera pair under the chassis, looking out and down
##   HAZ_REAR   the same at the rear
##   TOOL       on the tool turret's camera (needs a tool turret), looking out of its lens
## The hazard and tool cameras are fixed lenses: Field Of View doesn't change them. Brightness
## (VideoSettings.exposure_multiplier) is also put on the tool view's own camera attributes.

enum View { CHASE, MAST, HAZ_FRONT, HAZ_REAR, TOOL }

const VIEW_NAMES: Array[String] = ["Chase camera", "Mast camera", "Front hazard camera",
	"Rear hazard camera", "Arm tool camera"]

# Mast camera zoom: vertical field of view from MAST_FOV_MAX (no zoom; the Field Of View setting
# replaces it, mast_fov_widest) down to MAST_FOV_MIN (5.7x magnification at 90), scaled by
# MAST_ZOOM_STEP per wheel notch and eased towards
const MAST_FOV_MAX: float = 90.0
const MAST_FOV_MIN: float = 20.0
const MAST_ZOOM_STEP: float = 0.8
const MAST_ZOOM_RATE: float = 12.0

# Chase camera: distance and default height angle, how far mouse look can raise / lower it,
# how fast it follows the rover's heading, and how close a wall may pull it in. Every part
# of the rover is within 1.4 m of the look target, so CHASE_MIN_DISTANCE keeps it outside.
const CHASE_DISTANCE: float = 3.2
const CHASE_MIN_DISTANCE: float = 1.8
const CHASE_TARGET_HEIGHT: float = 0.6
const CHASE_ELEVATION: float = deg_to_rad(20.0)
const CHASE_ELEVATION_RANGE: Vector2 = Vector2(deg_to_rad(3.0), deg_to_rad(65.0))
const CHASE_FOLLOW_RATE: float = 4.0
const CHASE_FOV: float = 70.0

# Hazard cameras (rover space): midway between each pair of lenses on the chassis
# (ROVER_KIT.md 3.3, hazcams at z 0.175 under the front / rear edge), 12 mm out from the
# chassis faces (27 mm from the nearest surface), looking out and 20 degrees down, wide angle
const HAZ_POSITION: Vector3 = Vector3(0.0, 0.175, -0.462)
const HAZ_DOWN: float = deg_to_rad(20.0)
const HAZ_FOV: float = 100.0

# Tool turret camera (arm_tool model space, Godot axes): the camera tool points out from the
# hub axis at 126 degrees (ROVER_KIT.md 3.3); the view starts just outside its lens (0.0605
# out) and looks along it. Its neighbouring tools are behind that plane.
const TOOL_HUB_CENTRE: Vector3 = Vector3(0.0, 0.0, -0.025)
const TOOL_CAMERA_ANGLE: float = deg_to_rad(126.0)
const TOOL_CAMERA_OUT: float = 0.072
const TOOL_FOV: float = 60.0
# Its macro look: sharp up close, blurred from TOOL_DOF_FAR on (RoverFeedOverlay adds the rest)
const TOOL_DOF_FAR: float = 0.8
const TOOL_DOF_TRANSITION: float = 1.5
const TOOL_DOF_AMOUNT: float = 0.08

const NEAR: float = 0.005

var view: View = View.MAST
## Mast camera field of view (degrees): where it is easing to, and now
var mast_fov_target: float = MAST_FOV_MAX
var mast_fov: float = MAST_FOV_MAX
## The mast camera's field of view unzoomed: Settings > Video > Field Of View
var mast_fov_widest: float = MAST_FOV_MAX
## Seconds (game time) since the last zoom input in a view without zoom, for the HUD's hint
var zoom_refused_age: float = INF

var _tool_attributes := CameraAttributesPractical.new()
var _look: Dictionary = {}           # View -> Vector2(azimuth, altitude) while not current
var _chase_heading: float = 0.0
var _chase_started: bool = false

@onready var robot: Robot = get_parent() as Robot
@onready var visuals: RoverVisuals = robot.get_node("Visuals") as RoverVisuals


func _ready() -> void:
	process_physics_priority = 20
	_tool_attributes.dof_blur_far_enabled = true
	_tool_attributes.dof_blur_far_distance = TOOL_DOF_FAR
	_tool_attributes.dof_blur_far_transition = TOOL_DOF_TRANSITION
	_tool_attributes.dof_blur_amount = TOOL_DOF_AMOUNT
	robot.controller.camera_next.connect(next_view)
	robot.controller.zoom.connect(_on_zoom)
	_follow_fov_setting()


func is_available(candidate: View) -> bool:
	match candidate:
		View.MAST:
			return visuals.has_mast_camera
		View.TOOL:
			var socket := robot.find_child("ArmToolSocket", true, false) as HotswapSocket
			return socket != null and socket.part != null
	return true


## Switches to the next view that has its part mounted.
func next_view() -> void:
	var candidate: int = view
	for i in View.size():
		candidate = (candidate + 1) % View.size()
		if is_available(candidate):
			break
	_switch(candidate)


func view_name() -> String:
	return VIEW_NAMES[view]


## Mast camera magnification relative to the unzoomed field of view (1.0 = no zoom)
func mast_zoom() -> float:
	return tan(deg_to_rad(mast_fov_widest) / 2.0) / tan(deg_to_rad(mast_fov) / 2.0)


func _switch(new_view: View) -> void:
	if new_view == view:
		return
	var controller := robot.controller
	_look[view] = Vector2(controller.camera_azimuth, controller.camera_altitude)
	view = new_view
	var restored: Vector2 = _look.get(view, Vector2.ZERO)
	controller.camera_azimuth = restored.x
	controller.camera_altitude = restored.y
	controller.altitude_limit = (CHASE_ELEVATION_RANGE.y - CHASE_ELEVATION) if view == View.CHASE else RoverVisuals.CAMERA_PITCH_LIMIT
	_chase_started = false
	# Picking up / holding aims with the mast camera
	if view != View.MAST:
		robot.holder.release()


func _on_zoom(steps: float) -> void:
	var claw := robot.get_node_or_null("ManualClaw") as ManualClaw
	if claw and claw.active:
		return                                   # the wheel sets the claw's height
	if view == View.MAST:
		mast_fov_target = clampf(mast_fov_target * pow(MAST_ZOOM_STEP, steps), MAST_FOV_MIN, mast_fov_widest)
	else:
		zoom_refused_age = 0.0


func _physics_process(delta: float) -> void:
	zoom_refused_age += delta
	_follow_fov_setting()
	if not is_available(view):
		# The mast camera or tool turret was taken out (or never mounted): the chase view
		# always works and shows the whole rover
		_switch(View.CHASE)
	var fov: float = HAZ_FOV
	var look_scale: float = 1.0
	match view:
		View.MAST:
			robot.pivot.global_transform = visuals.mast_camera_transform
			mast_fov = lerpf(mast_fov, mast_fov_target, 1.0 - exp(-MAST_ZOOM_RATE * delta))
			fov = mast_fov
			# Same screen distance turns the view by the same fraction of the field of view
			look_scale = mast_fov / mast_fov_widest
		View.CHASE:
			robot.pivot.global_transform = _chase_transform(delta)
			fov = CHASE_FOV * VideoSettings.fov() / VideoSettings.FOV_DEFAULT
		View.HAZ_FRONT:
			robot.pivot.global_transform = robot.global_transform * Transform3D(Basis(Vector3.RIGHT, -HAZ_DOWN), HAZ_POSITION)
		View.HAZ_REAR:
			robot.pivot.global_transform = robot.global_transform * Transform3D(
				Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, -HAZ_DOWN), HAZ_POSITION * Vector3(1.0, 1.0, -1.0))
		View.TOOL:
			robot.pivot.global_transform = _tool_transform()
			fov = TOOL_FOV
	robot.camera.fov = fov
	_tool_attributes.exposure_multiplier = VideoSettings.exposure_multiplier()
	var attributes: CameraAttributes = _tool_attributes if view == View.TOOL else null
	if robot.camera.attributes != attributes:
		robot.camera.attributes = attributes
	robot.camera.near = maxf(NEAR, robot.min_camera_near)
	robot.controller.look_scale = look_scale


# A new Field Of View setting scales the mast camera's zoom with it (the same magnification)
func _follow_fov_setting() -> void:
	var widest: float = VideoSettings.fov()
	if widest == mast_fov_widest:
		return
	var ratio: float = widest / mast_fov_widest
	mast_fov_widest = widest
	mast_fov_target = clampf(mast_fov_target * ratio, MAST_FOV_MIN, widest)
	mast_fov = clampf(mast_fov * ratio, MAST_FOV_MIN, widest)


# Behind and above the look target, following the rover's heading (smoothed, upright even if
# the rover rolls); mouse look orbits (azimuth) and raises / lowers it (altitude). A wall in
# between pulls it in, but not closer than CHASE_MIN_DISTANCE.
func _chase_transform(delta: float) -> Transform3D:
	var forward: Vector3 = -robot.global_basis.z
	var heading: float = atan2(-forward.x, -forward.z) if Vector2(forward.x, forward.z).length() > 0.05 else _chase_heading
	if not _chase_started:
		_chase_heading = heading
		_chase_started = true
	_chase_heading = lerp_angle(_chase_heading, heading, 1.0 - exp(-CHASE_FOLLOW_RATE * delta))
	var yaw: float = _chase_heading + robot.controller.camera_azimuth
	var elevation: float = clampf(CHASE_ELEVATION + robot.controller.camera_altitude,
		CHASE_ELEVATION_RANGE.x, CHASE_ELEVATION_RANGE.y)
	var target: Vector3 = robot.global_position + Vector3.UP * CHASE_TARGET_HEIGHT
	var direction: Vector3 = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -elevation) * Vector3.BACK
	var distance: float = CHASE_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(target, target + direction * CHASE_DISTANCE, 1)
	var hit: Dictionary = robot.get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		distance = maxf(target.distance_to(hit["position"]) - 0.2, CHASE_MIN_DISTANCE)
	var position: Vector3 = target + direction * distance
	return Transform3D(Basis.looking_at(target - position, Vector3.UP), position)


# Out of the tool turret's camera lens; turns with the arm and the turret (J5)
func _tool_transform() -> Transform3D:
	var socket := robot.find_child("ArmToolSocket", true, false) as HotswapSocket
	var model := socket.part.get_node("Model") as Node3D
	var out := Vector3(cos(TOOL_CAMERA_ANGLE), sin(TOOL_CAMERA_ANGLE), 0.0)
	var local := Transform3D(Basis.looking_at(out, Vector3.FORWARD), TOOL_HUB_CENTRE + out * TOOL_CAMERA_OUT)
	return model.global_transform * local
