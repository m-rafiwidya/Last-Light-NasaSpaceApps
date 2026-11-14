class_name PlayerController

extends Node


signal crouch(value: bool)
signal interact(value: bool)
signal primary(value: bool)
signal secondary(value: bool)
## L (the `lights` action, the rover's headlights while driving): helmet light on / off
signal lights_toggle


const SENS: float = 20.8 / 2.0
const DPI: float = 1000


var move_direction: Vector3 = Vector3.ZERO
var request_jump: bool = false
var is_sprinting: bool = false
var is_crouching: bool = false
var crouching_changed: bool = false
var is_interacting: bool = false
var interacting_changed: bool = false
var interact_primary: bool = false
var primary_changed: bool = false
var interact_secondary: bool = false
var secondary_changed: bool = false

var camera_azimuth: float = 0.0
var camera_altitude: float = 0.0

var queued_rotation: Quaternion = Quaternion.IDENTITY

var was_input_enabled: bool = false
# Toggle Crouch: crouched by the last press
var _crouch_toggled: bool = false


## Mouse pixels to radians (Source-style: SENS centimetres per 360 degrees at DPI).
## Shared with RobotController.
static func px_to_rad(pixels: float) -> float:
	return pixels / (DPI / 2.54) / SENS * PI * 2.0


## Player input is only accepted while the game is in the IN_GAME_PLAYER state
## (not while driving the robot, in menus, the mission console, loading screens, etc.)
## and the debug console is closed.
func is_input_enabled() -> bool:
	return GameState.state == GameState.State.IN_GAME_PLAYER and not Debug.console_open


func _unhandled_input(event: InputEvent) -> void:
	if not is_input_enabled():
		return

	if event is InputEventMouseMotion:
		# TODO: This supports object rerotation for precise fenaggling 
		#if Input.is_action_pressed("interact_secondary"):
			#var new_basis := Basis.IDENTITY
			##new_basis = new_basis.rotated(camera.transform.basis.x, px_to_rad(event.relative.y))
			##new_basis = new_basis.rotated(camera.transform.basis.y, px_to_rad(event.relative.x))
			##held_object_original_orientation = new_basis.get_rotation_quaternion() * held_object_original_orientation
		#else:
			# Sensitivity and Invert Y Axis (Settings > Controls)
			var look: Vector2 = ControlSettings.look_pixels(event.relative)
			var vertical_input = -px_to_rad(look.y)
			var horizontal_input = -px_to_rad(look.x)
			
			camera_altitude = clamp(camera_altitude + vertical_input, -PI / 2, PI / 2)
			camera_azimuth = fmod(camera_azimuth + horizontal_input, 2.0*PI)


# TODO: Maybe try to put everything inside unhandled input? idk if thats better;
func _physics_process(_delta: float) -> void:
	if not is_input_enabled():
		was_input_enabled = false
		_process_locked_input()
		return
	# Treat the first tick after unlocking as locked too, so a press that started
	# while locked (e.g. clicking a UI button to close a screen) isn't read as a
	# fresh gameplay press.
	if not was_input_enabled:
		was_input_enabled = true
		_process_locked_input()
		return

	var input_forward: float = (
		Input.get_action_strength("move_forward") - Input.get_action_strength("move_backward")
	)
	var input_right: float = (
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	)
	
	move_direction = (
		Vector3.FORWARD * input_forward
		 + Vector3.RIGHT * input_right
	).normalized()

	is_sprinting = Input.is_action_pressed("move_sprint")
	
	if Input.is_action_just_pressed("move_jump"):
		request_jump = true
	elif Input.is_action_just_released("move_jump"):
		request_jump = false
	
	# Toggle Crouch (Settings > Controls): a press crouches or stands up, the release does nothing
	if ControlSettings.toggle_crouch():
		if Input.is_action_just_pressed("move_crouch"):
			_crouch_toggled = not _crouch_toggled
			crouch.emit(_crouch_toggled)
	else:
		_crouch_toggled = false
		if Input.is_action_just_pressed("move_crouch"):
			crouch.emit(true)
		if Input.is_action_just_released("move_crouch"):
			crouch.emit(false)
	
	if Input.is_action_just_pressed("interact_use"):
		interact.emit(true)
	elif Input.is_action_just_released("interact_use"):
		interact.emit(false)
			
	if Input.is_action_just_pressed("interact_primary"):
		primary.emit(true)
	elif Input.is_action_just_released("interact_primary"):
		primary.emit(false)
	
	if Input.is_action_just_pressed("lights"):
		lights_toggle.emit()

	if Input.is_action_just_pressed("interact_secondary"):
		secondary.emit(true)
	elif Input.is_action_just_released("interact_secondary"):
		secondary.emit(false)


## While input is locked, clear any continuous intent and only let key/button
## releases through, so the player can't get stuck crouching or rotating if a
## key was released during the lock. Presses are ignored.
func _process_locked_input() -> void:
	move_direction = Vector3.ZERO
	is_sprinting = false
	request_jump = false

	if Input.is_action_just_released("move_crouch") and not _crouch_toggled:
		crouch.emit(false)
	if Input.is_action_just_released("interact_use"):
		interact.emit(false)
	if Input.is_action_just_released("interact_primary"):
		primary.emit(false)
	if Input.is_action_just_released("interact_secondary"):
		secondary.emit(false)
