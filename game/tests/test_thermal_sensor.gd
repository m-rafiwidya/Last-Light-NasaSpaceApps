extends SceneTree
## Headless test: the temperature pair (ThermalSensor, plan item D).
##   1. Model: sunlit ground reads hotter under a high sun (78 deg, Courier) than a low one (17 deg,
##      Freighter); shade reads the simulated -150 C.
##   2. Kinds: open ground near IRIS on the sun's side reads SUN; the ground in Kite's own shadow and
##      in IRIS's shadow reads SHADE (with the level's sun).
##   3. Pair: a sun and a shade reading make has_pair(), and pair_completed fires once.
##   4. Turret: without the thermal turret try_read does nothing; with it, in the mast view aimed at
##      Kite's shadow, it records a shade reading.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_thermal_sensor.gd

const TICKS: int = 240
const MAST: int = 1
const SENSOR_SCENE: String = "res://src/field/thermal_sensor.tscn"
const TURRET_SCENE: String = "res://src/robot/socket/arm_tool_thermal_part.tscn"

var GS: Node
var SL: Node
var CS: Node
var failures: int = 0
var level: Node3D
var rover: RigidBody3D
var iris: Node3D
var sensor: Node3D
var pairs: int = 0


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("%s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail else ""])


func _ticks(seconds: float) -> void:
	for i in int(seconds * TICKS):
		await physics_frame


func _ground(at: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 30.0, at + Vector3.DOWN * 30.0, 1)
	var hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if hit else at


## Where the shadow of `point` falls on the ground (along -sun), or `point` if nothing is hit
func _shadow_of(point: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(point, point - sensor._sun_direction() * 60.0, 1)
	var hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if hit else point


func _aim_mast_at(world_point: Vector3) -> void:
	var local: Vector3 = rover.to_local(world_point)
	var cam: Vector3 = rover.to_local(rover.camera.global_position)
	var d: Vector3 = local - cam
	rover.controller.camera_azimuth = atan2(-d.x, -d.z)
	rover.controller.camera_altitude = atan2(d.y, Vector2(d.x, d.z).length())


func _run() -> void:
	await process_frame
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	CS = root.get_node("CampaignState")
	while GS.state != GS.State.MAIN_MENU:
		await physics_frame
	CS.reset()
	load("res://src/save/save_index.gd").start_new_campaign()
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level"):
		await physics_frame
	level = SL.current_scene
	rover = level.get_node("ReadyRover")
	iris = level.get_node("Iris")
	sensor = (load(SENSOR_SCENE) as PackedScene).instantiate()
	level.add_child(sensor)
	sensor.pair_completed.connect(func() -> void: pairs += 1)
	await _ticks(1.0)
	var sun: Vector3 = sensor._sun_direction()
	var flat_sun := Vector3(sun.x, 0.0, sun.z).normalized()

	# 1. Model
	var high: float = sensor.sun_celsius(78.0)
	var low: float = sensor.sun_celsius(17.0)
	_check("model: a high sun reads hotter than a low one", high > low and high > 90.0 and low > -50.0,
		"78 deg %.0f C, 17 deg %.0f C" % [high, low])
	_check("model: the level has a sun above the horizon", sun.y > 0.0, str(sun))

	# 2. Kinds
	var open: Vector3 = _ground(iris.global_position + flat_sun * 12.0)
	_check("kinds: open ground on IRIS's sun side reads SUN", sensor.kind_at(open) == "sun", str(open))
	var iris_shade: Vector3 = _shadow_of(iris.global_position + Vector3.UP * 0.8)
	_check("kinds: IRIS's shadow reads SHADE", sensor.kind_at(iris_shade) == "shade", str(iris_shade))
	rover.global_transform = Transform3D(Basis.IDENTITY, open + Vector3.UP * 0.3)
	rover.linear_velocity = Vector3.ZERO
	await _ticks(2.0)
	var kite_shade: Vector3 = _shadow_of(rover.global_position + Vector3.UP * 0.25)
	_check("kinds: Kite's own shadow reads SHADE", sensor.kind_at(kite_shade) == "shade", str(kite_shade))

	# 3. Pair
	_check("pair: no pair before readings", not sensor.has_pair())
	sensor.record(open)
	_check("pair: one sun reading is not a pair", not sensor.has_pair() and sensor.readings.has("sun"))
	sensor.record(kite_shade)
	_check("pair: sun + shade is a pair, signalled once", sensor.has_pair() and pairs == 1, "%d" % pairs)
	_check("pair: the shade reading is the simulated value", is_equal_approx(sensor.readings["shade"], sensor.SHADE_CELSIUS))
	sensor.record(open)
	_check("pair: another reading doesn't signal again", pairs == 1)

	# 4. Turret
	sensor.readings.clear()
	GS.drive(rover)
	await _ticks(0.5)
	rover.get_node("CameraRig")._switch(MAST)
	_check("turret: without it, try_read does nothing", not sensor.try_read(rover) and sensor.readings.is_empty())
	var socket: Node = rover.find_child("ArmToolSocket", true, false)
	var old: Node = socket.unmount()
	if old:
		old.queue_free()
	var turret: RigidBody3D = (load(TURRET_SCENE) as PackedScene).instantiate()
	level.add_child(turret)
	turret.global_position = socket.global_position
	socket.mount(turret)
	_check("turret: the thermal turret is fitted", sensor.has_turret(rover))
	_aim_mast_at(kite_shade)
	await _ticks(0.3)
	_check("turret: the hint names SHADE", sensor.get_hint(rover).contains("SHADE"), sensor.get_hint(rover))
	_check("turret: aimed at Kite's shadow, try_read records SHADE",
		sensor.try_read(rover) and sensor.readings.has("shade") and not sensor.readings.has("sun"), str(sensor.readings))

	print("RESULT test_thermal_sensor %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
