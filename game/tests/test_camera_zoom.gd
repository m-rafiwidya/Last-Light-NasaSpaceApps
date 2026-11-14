extends SceneTree
## Headless test: drives the assembled rover in the test level and sends real input events
## through Input.parse_input_event, as the OS would:
##   - mouse wheel up / down: one zoom step (20% field of view) each
##   - trackpad two-finger scroll (InputEventPanGesture, what macOS sends) and pinch
##     (InputEventMagnifyGesture): fractional steps, the same direction as the wheel
##   - the = / - keys held: smooth zoom while held, nothing after release
##   - zoom stops at the mast camera's limits
##   - in the front hazard view zoom changes nothing and the HUD shows the "no zoom" hint
## Prints one line per check and PASS / FAIL.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_camera_zoom.gd

# RoverCamera's values (class names that reach the autoloads can't be used here: this script
# compiles before they exist)
const FOV_MAX: float = 90.0
const FOV_MIN: float = 20.0
const VIEW_MAST: int = 1
const VIEW_HAZ_FRONT: int = 2

var level: Node
var rover: RigidBody3D
var rig: Node
var hud: Node
var GS: Node
var t := 0.0
var step := 0
var step_t := 0.0
var failures := 0


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("RESULT %-34s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _check_fov(name: String, expected: float) -> void:
	var got: float = rig.mast_fov_target
	_check(name, absf(got - expected) < 0.5, "fov target %.1f, expected %.1f" % [got, expected])


func _wheel(button: MouseButton) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.factor = 1.0
		Input.parse_input_event(event)


func _key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func _pan(delta_y: float) -> void:
	var event := InputEventPanGesture.new()
	event.delta = Vector2(0.0, delta_y)
	Input.parse_input_event(event)


func _pinch(factor: float) -> void:
	var event := InputEventMagnifyGesture.new()
	event.factor = factor
	Input.parse_input_event(event)


func _reset_zoom() -> void:
	rig.mast_fov_target = FOV_MAX


# Each step sends input, then the next one checks it (events are flushed on the next frame).
# Returns how long to wait before the next step.
func _run_step() -> float:
	match step:
		0:
			_check("starts in the mast view", rig.view == VIEW_MAST, "view %s" % rig.view_name())
			_reset_zoom()
			_wheel(MOUSE_BUTTON_WHEEL_UP)
		1:
			_check_fov("wheel up zooms in one step", FOV_MAX * 0.8)
			_wheel(MOUSE_BUTTON_WHEEL_DOWN)
		2:
			_check_fov("wheel down zooms out one step", FOV_MAX)
			_pan(-2.0)
		3:
			_check_fov("trackpad scroll up zooms in", FOV_MAX * 0.8)
			_pan(2.0)
		4:
			_check_fov("trackpad scroll down zooms out", FOV_MAX)
			_pinch(1.25)
		5:
			_check_fov("pinch out zooms in", FOV_MAX * pow(0.8, 4.5 * log(1.25)))
			_pinch(0.8)
		6:
			_check_fov("pinch in zooms out", FOV_MAX)
			_key(KEY_EQUAL, true)
			return 0.5
		7:
			# 4 steps per second for 0.5 s, give or take a tick or two
			var got: float = rig.mast_fov_target
			_check("= held zooms in smoothly", got < FOV_MAX * pow(0.8, 1.8) and got > FOV_MAX * pow(0.8, 2.2), "fov target %.1f after 0.5 s" % got)
			_key(KEY_EQUAL, false)
			set_meta("after_release", got)
		8:
			var held: float = get_meta("after_release")
			_check("= released stops zooming", absf(rig.mast_fov_target - held) < 0.5, "fov target %.1f, was %.1f" % [rig.mast_fov_target, held])
			_key(KEY_MINUS, true)
			return 1.0
		9:
			_key(KEY_MINUS, false)
			_check_fov("- held zooms out to the widest", FOV_MAX)
			for i in 12:
				_wheel(MOUSE_BUTTON_WHEEL_UP)
		10:
			_check_fov("zoom stops at the narrowest", FOV_MIN)
			_reset_zoom()
			rig._switch(VIEW_HAZ_FRONT)
		11:
			_wheel(MOUSE_BUTTON_WHEEL_UP)
			_pan(-2.0)
		12:
			_check_fov("no zoom in the hazard view", FOV_MAX)
			_check("hazard view records refused zoom", rig.zoom_refused_age < 0.5, "zoom_refused_age %.2f s" % rig.zoom_refused_age)
			var hint := hud.get_node("%ZoomHint") as Label
			_check("HUD shows the no-zoom hint", hint.is_visible_in_tree(), "\"%s\"" % hint.text)
			return 2.5
		13:
			var hint := hud.get_node("%ZoomHint") as Label
			_check("no-zoom hint goes away", not hint.visible, "")
			rig._switch(VIEW_MAST)
			_check("back in the mast view, hint stays hidden", rig.view == VIEW_MAST, "")
			return -1.0
	return 0.05


func _physics_process(delta: float) -> bool:
	GS = root.get_node("GameState")
	var SL = root.get_node("SceneLoader")
	if GS.state == GS.State.MAIN_MENU and not has_meta("requested"):
		set_meta("requested", true)
		SL.load_scene("test_level")
	if level == null:
		if GS.state == GS.State.IN_GAME_PLAYER and SL.current_scene:
			level = SL.current_scene
			rover = level.get_node("ReadyRover")
			rig = rover.get_node("CameraRig")
			hud = root.find_child("RobotHUD", true, false)
		return false
	t += delta
	if t < 1.0:
		return false
	if not has_meta("driving"):
		set_meta("driving", true)
		GS.drive(rover)
		step_t = -0.5   # let the HUD fade in and the controller accept input
		return false
	step_t += delta
	if step_t < 0.0:
		return false
	var wait: float = _run_step()
	if wait < 0.0:
		print("RESULT %s" % ("ALL PASS" if failures == 0 else "%d CHECKS FAILED" % failures))
		return true
	step += 1
	step_t = -wait
	return false
