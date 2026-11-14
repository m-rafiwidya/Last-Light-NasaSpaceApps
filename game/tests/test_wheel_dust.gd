extends SceneTree
## Headless test of the wheels' dust (WheelDust), Moon level then test level. What it sprays and
## when; the particles themselves need a window (tools/render_dust_previews.gd).
##   - every rover has one, six emitters, flying under the level's gravity (1.62 / 9.8), each
##     grain living longer than the longest flight at it;
##   - every frame of the whole run, for every rover: no wheel sprays unless it is in contact,
##     loaded and on dusty ground (so nothing airborne, nothing off the workshop floor), and each
##     emitter's hub is the wheel's (its radius from the contact point, within 3 cm while driving);
##   - parked: nothing; driving at 30%: all six spray; full throttle: more; the rate grows with the
##     tread's speed and with slip;
##   - airborne (dropped from 2 m while driving): nothing until it lands;
##   - driving in the workshop's bay: nothing;
##   - Low: 40% of the grains; Off: no dust and no collision field.
## Prints one line per check and PASS / FAIL.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_wheel_dust.gd

const TICKS: int = 240
# RunningGear.WheelState / WheelProperty (this script compiles before the game's autoloads exist,
# so it can't name the rover's classes)
const ANGULAR_VELOCITY: int = 0
const LOAD: int = 1
const IN_CONTACT: int = 3
const CONTACT_POINT: int = 4
const GROUND_BODY: int = 8
const EFFECTIVE_RADIUS: int = 4
const DUSTY_GROUP: StringName = &"dusty_ground"

var WD: GDScript

var GS: Node
var SL: Node
var failures: int = 0
var level: Node
# Per-frame invariant counts (all rovers of the current level)
var frames: int = 0
var spray_off_ground: int = 0
var hub_off: int = 0
var worst_hub: float = 0.0
var checking: bool = false
var rovers: Array = []
# What the test is doing (for the worst emitter offset)
var phase: String = ""
var worst_hub_phase: String = ""
var worst_landing_hub: float = 0.0


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	var checker_script := GDScript.new()
	checker_script.source_code = "extends Node\nvar callback: Callable\nfunc _process(_delta: float) -> void:\n\tcallback.call()\n"
	checker_script.reload()
	var checker := Node.new()
	checker.set_script(checker_script)
	checker.set("callback", _check_frame)
	checker.process_priority = 1000
	root.add_child.call_deferred(checker)
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-62s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _ticks(seconds: float) -> void:
	for i in int(seconds * TICKS):
		await physics_frame


func _load(level_id: String) -> void:
	SL.load_scene(level_id)
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == level_id and SL.current_scene):
		await physics_frame
	level = SL.current_scene
	rovers = _rovers()
	await _ticks(0.5)


func _dust(rover: Node) -> Node:
	return rover.get_node_or_null("WheelDust")


func _check_frame() -> void:
	if not checking or level == null or not is_instance_valid(level):
		return
	frames += 1
	for rover in rovers:
		var dust := _dust(rover)
		if dust == null or dust.rates.is_empty():
			continue
		for wheel in dust.rates:
			var state: Dictionary = rover.running_gear.wheel_states[wheel]
			if dust.rates[wheel] <= 0.0:
				continue
			var ground: Object = state[GROUND_BODY]
			var dusty: bool = is_instance_valid(ground) and ground is Node and (ground as Node).is_in_group(DUSTY_GROUP)
			if not (state[IN_CONTACT] and (state[LOAD] as Vector3).length() > 0.0 and dusty):
				spray_off_ground += 1
				continue
			var hub: Vector3 = (dust.emitters[wheel].process_material as ShaderMaterial).get_shader_parameter("hub_position")
			var contact: Vector3 = rover.global_position + state[CONTACT_POINT]
			var radius: float = rover.running_gear.wheel_properties[wheel][EFFECTIVE_RADIUS]
			var off: float = absf(hub.distance_to(contact) - radius)
			# Landing from the drop: the visible wheel (where the grains start) is where the ground
			# check finds it after the step, the contact point is from before it; reported, not checked
			if phase.ends_with("airborne"):
				worst_landing_hub = maxf(worst_landing_hub, off)
				continue
			if off > worst_hub:
				worst_hub = off
				worst_hub_phase = "%s, %s, %.2f m/s" % [phase, rover.name, rover.linear_velocity.length()]
			if off > 0.03:
				hub_off += 1


func _rovers() -> Array:
	return level.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n.get("running_gear") != null and n is RigidBody3D)


func _place(rover: Node, xform: Transform3D) -> void:
	for a in ["move_forward", "move_backward", "move_left", "move_right"]:
		Input.action_release(a)
	rover.global_transform = xform
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	for wheel in rover.running_gear.wheel_states:
		rover.running_gear.wheel_states[wheel][ANGULAR_VELOCITY] = 0.0


# Mean spray over the wheels and frames for `seconds`; [mean, wheels that sprayed]
func _spray_for(dust: Node, seconds: float) -> Array:
	var total: float = 0.0
	var count: int = 0
	var sprayed: Dictionary = {}
	for i in int(seconds * TICKS):
		await process_frame
		for wheel in dust.rates:
			total += dust.rates[wheel]
			count += 1
			if dust.rates[wheel] > 0.0:
				sprayed[wheel] = true
	return [total / maxf(count, 1), sprayed.size()]


func _common(tag: String, rover: Node, g: float) -> void:
	var dust := _dust(rover)
	_check(tag + "the rover has its dust, six emitters", dust != null and dust.emitters.size() == 6)
	if dust == null:
		return
	var gravity: Vector3 = (dust.emitters[0].process_material as ShaderMaterial).get_shader_parameter("gravity")
	_check(tag + "grains fly under the level's gravity", gravity.is_equal_approx(Vector3(0.0, -g, 0.0)), "%s" % gravity)
	var longest: float = 2.0 * WD.SPEED_CAP / g
	_check(tag + "grains live past the longest flight", dust.lifetime > longest and dust.emitters[0].lifetime == dust.lifetime,
		"%.2f s (longest flight %.2f s), %d slots a wheel" % [dust.lifetime, longest, dust.emitters[0].amount])
	_check(tag + "a collision field the grains land on", level.get_node_or_null("DustGround") is GPUParticlesCollisionHeightField3D)


func _drive_checks(tag: String, rover: Node, start: Transform3D) -> void:
	var dust := _dust(rover)
	GS.drive(rover)
	_place(rover, start)
	await _ticks(3.0)
	var parked: Array = await _spray_for(dust, 2.0)
	_check(tag + "parked: no dust", parked[1] == 0, "mean %.3f" % parked[0])

	Input.action_press("move_forward", 0.3)
	await _ticks(2.0)
	phase = tag + "30%"
	var cruise: Array = await _spray_for(dust, 2.0)
	var cruise_speed: float = rover.linear_velocity.length()
	_check(tag + "30%: all six wheels spray", cruise[1] == 6, "%d wheels, mean %.2f at %.2f m/s" % [cruise[1], cruise[0], cruise_speed])
	Input.action_release("move_forward")
	await _ticks(4.0)

	# From a standstill at full throttle: as it passes the 30% speed it slips more, so it throws more
	_place(rover, start)
	await _ticks(2.0)
	phase = tag + "full throttle"
	Input.action_press("move_forward", 1.0)
	var passing: Array = []
	for i in int(6.0 * TICKS):
		await process_frame
		if absf(rover.linear_velocity.length() - cruise_speed) < 0.15:
			var sum: float = 0.0
			for wheel in dust.rates:
				sum += dust.rates[wheel] / 6.0
			passing.append(sum)
		elif rover.linear_velocity.length() > cruise_speed + 0.15:
			break
	var at_cruise: float = 0.0
	for r in passing:
		at_cruise += r / maxf(passing.size(), 1)
	_check(tag + "full throttle: more dust at the 30% speed (slip)", passing.size() > 0 and at_cruise > cruise[0],
		"mean %.2f passing %.2f m/s (30%%: %.2f)" % [at_cruise, cruise_speed, cruise[0]])
	await _ticks(3.0)
	var fast: Array = await _spray_for(dust, 1.0)
	_check(tag + "full throttle: more dust at full speed", fast[0] > cruise[0], "mean %.2f at %.2f m/s (30%%: %.2f)" % [fast[0], rover.linear_velocity.length(), cruise[0]])
	Input.action_release("move_forward")
	await _ticks(5.0)


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	while GS.state != GS.State.MAIN_MENU:
		await physics_frame
	WD = load("res://src/effects/wheel_dust/wheel_dust.gd")

	# The rate itself
	_check("rate: none at a standstill", WD.spray_rate(0.0, 0.0, 1.0) == 0.0 and WD.spray_rate(0.1, 0.0, 1.0) == 0.0)
	_check("rate: grows with the tread's speed", WD.spray_rate(1.0, 0.0, 1.0) < WD.spray_rate(2.5, 0.0, 1.0))
	_check("rate: grows with slip", WD.spray_rate(1.0, 0.0, 1.0) < WD.spray_rate(1.0, 0.5, 1.0))
	_check("rate: none without load", WD.spray_rate(2.0, 1.0, 0.0) == 0.0)
	_check("Low: 40% of the grains", is_equal_approx(WD.new(true).max_rate, 0.4 * WD.new(false).max_rate))

	# --- Moon ---
	await _load("moon_level")
	checking = true
	var rover: Node = level.get_node("ReadyRover")
	var workshop: Node3D = level.get_node("Workshop")
	_common("Moon: ", rover, 1.62)
	_check("Moon: the terrain is dusty ground", level.get_node("Terrain/Ground").is_in_group(DUSTY_GROUP))
	# Open ground 30 m out from the door (the apron has the decor's crates), facing away from it
	var out: Vector3 = workshop.to_global(Vector3(0.0, 0.0, -30.0))
	out.y = level.get_node("Terrain").height_at(out.x, out.z) + 0.3
	var apron := Transform3D(workshop.global_basis, out)
	await _drive_checks("Moon: ", rover, apron)

	# Driving in the bay: the workshop's floor isn't dust
	var dust := _dust(rover)
	phase = "Moon: bay"
	_place(rover, workshop.get_dock_transform().translated(Vector3.UP * 0.05))
	await _ticks(2.0)
	Input.action_press("move_backward", 0.25)
	var bay: Array = await _spray_for(dust, 1.5)
	Input.action_release("move_backward")
	var moved: bool = rover.linear_velocity.length() > 0.2
	_check("Moon: driving in the bay: no dust", bay[1] == 0 and moved, "%d wheels sprayed, %.2f m/s" % [bay[1], rover.linear_velocity.length()])
	await _ticks(2.0)

	# Airborne: driving, then 2 m up; nothing until a wheel is down again
	_place(rover, apron)
	await _ticks(2.0)
	Input.action_press("move_forward", 0.5)
	await _ticks(2.0)
	var up: Vector3 = rover.global_position + Vector3.UP * 2.0
	rover.global_position = up
	phase = "Moon: airborne"
	# The wheel states are the next physics step's
	await physics_frame
	await physics_frame
	var airborne_frames: int = 0
	var airborne_spray: int = 0
	for i in TICKS * 3:
		await process_frame
		var any_contact: bool = false
		for wheel in rover.running_gear.wheel_states:
			if rover.running_gear.wheel_states[wheel][IN_CONTACT]:
				any_contact = true
		if any_contact:
			break
		airborne_frames += 1
		for wheel in dust.rates:
			if dust.rates[wheel] > 0.0:
				airborne_spray += 1
	Input.action_release("move_forward")
	_check("Moon: airborne: no dust", airborne_frames > 50 and airborne_spray == 0, "%d frames in the air, %d wheel-frames sprayed" % [airborne_frames, airborne_spray])
	await _ticks(3.0)

	# --- Test level ---
	await _load("test_level")
	rover = level.get_node("ReadyRover")
	_common("Test level: ", rover, 9.8)
	var floor_node: Node = level.get_node("NavigationRegion3D/CSGBox3D")
	_check("Test level: the floor is dusty ground, on the dust's render layer", floor_node.is_in_group(DUSTY_GROUP)
		and (floor_node.layers & (1 << (WD.GROUND_RENDER_LAYER - 1))) != 0)
	var with_dust: int = rovers.filter(func(r: Node) -> bool: return _dust(r) != null).size()
	_check("Test level: every rover has dust", with_dust == rovers.size(), "%d of %d" % [with_dust, rovers.size()])
	await _drive_checks("Test level: ", rover, Transform3D(Basis.IDENTITY, Vector3(30.0, 0.3, 40.0)))
	checking = false

	_check("every frame: dust only from loaded wheels on dusty ground", spray_off_ground == 0, "%d wheel-frames off it in %d frames" % [spray_off_ground, frames])
	print("INFO landing from the 2 m drop: an emitter up to %.1f mm off its wheel's radius over the step's contact point" % (worst_landing_hub * 1000.0))
	_check("every frame driving: emitters at their wheels", hub_off == 0, "worst %.1f mm from the wheel's radius over its contact (%s)" % [worst_hub * 1000.0, worst_hub_phase])

	# --- Off ---
	GraphicsSettings.surface_effects = GraphicsSettings.SurfaceEffects.OFF
	await _load("moon_level")
	_check("Off: no dust, no collision field", _dust(level.get_node("ReadyRover")) == null and level.get_node_or_null("DustGround") == null)
	GraphicsSettings.surface_effects = GraphicsSettings.SurfaceEffects.HIGH

	print("DONE %d failures" % failures)
	quit(1 if failures else 0)
