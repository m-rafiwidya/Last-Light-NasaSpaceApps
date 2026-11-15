extends SceneTree
## Headless test: M2's module install at IRIS (IrisModuleCradle, simple version without the arm).
##   1. Setup: IRIS has a ModuleCradle on the module seat, in group iris_module_cradle, with the
##      bay's mesh as highlight_node and the park_module marker; empty, IRIS offline.
##   2. Order: in m2 with the module on Kite's cargo mount and Kite parked at the bay, the install
##      is refused until m2.cargo_ordered and m2.module_loaded are done.
##   3. Position: too far from the bay refuses it and the hint says to come closer.
##   4. Install: parked and stopped, the hint says "In position"; try_install seats the module on
##      the seat (within 5 mm), empties the cargo mount, completes m2.module_installed and
##      m2.iris_activated, sets iris_online, and IRIS comes online. A second try does nothing.
##   5. Load: a fresh IRIS with the objective done starts with the module seated.
##   6. No campaign: a fresh IRIS starts empty and allows the install.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_iris_module.gd

const TICKS: int = 240
const MODULE_SCENE: String = "res://src/robot/socket/radio_module_part.tscn"

var GS: Node
var SL: Node
var CS: Node
var failures: int = 0
var level: Node3D
var rover: RigidBody3D
var iris: Node3D
var cradle: Node3D


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


func _place(at: Vector3, facing: Vector3) -> void:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 20.0, at + Vector3.DOWN * 20.0, 1)
	var hit: Dictionary = rover.get_world_3d().direct_space_state.intersect_ray(query)
	var ground: float = (hit["position"] as Vector3).y if hit else at.y
	var yaw: float = atan2(-facing.x, -facing.z)
	rover.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, ground + 0.3, at.z))
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	await _ticks(2.0)


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
	cradle = iris.get_node_or_null("ModuleCradle")
	await _ticks(1.0)

	# 1. Setup
	_check("setup: IRIS has a ModuleCradle", cradle != null and cradle.has_method("try_install"))
	if cradle == null or not cradle.has_method("try_install"):
		_finish()
		return
	_check("setup: the cradle is in group iris_module_cradle",
		get_first_node_in_group(&"iris_module_cradle") == cradle)
	_check("setup: highlight_node is the bay's mesh in IRIS's model",
		cradle.highlight_node != null and cradle.highlight_node.name == "iris_module_socket",
		str(cradle.highlight_node))
	_check("setup: the park_module marker is found", cradle.park_marker != null)
	_check("setup: the cradle sits on the module seat",
		cradle.global_position.distance_to(iris.module_seat_transform().origin) < 0.001)
	_check("setup: the bay starts empty and IRIS offline", not cradle.is_installed() and not iris.is_online)

	# 2. Order
	CS.start_mission("m2")
	var module: RigidBody3D = (load(MODULE_SCENE) as PackedScene).instantiate()
	level.add_child(module)
	module.global_position = rover.global_position + Vector3.UP
	var cargo: Node = rover.get_node("CargoSocket")
	cargo.mount(module)
	_check("order: the module is on Kite's cargo mount", cargo.part == module)
	var facing: Vector3 = iris.global_basis.x
	await _place(cradle.park_marker.global_position, facing)
	_check("order: parked at the bay", cradle.park_distance(rover) <= cradle.PARK_RANGE,
		"%.2f m" % cradle.park_distance(rover))
	_check("order: refused before m2.cargo_ordered and m2.module_loaded",
		not cradle.try_install(rover) and cargo.part == module and not CS.is_objective_done("m2.module_installed"))
	CS.complete_objective("m2.cargo_ordered")
	CS.complete_objective("m2.module_loaded")
	_check("order: allowed after them", cradle.campaign_allows())

	# 3. Position
	await _place(cradle.park_marker.global_position + facing * -4.0, facing)
	_check("position: refused 4 m out", not cradle.try_install(rover) and cargo.part == module)
	_check("position: the hint says to come closer", cradle.get_hint(rover).contains("closer"), cradle.get_hint(rover))

	# 4. Install
	await _place(cradle.park_marker.global_position, facing)
	_check("install: the hint says In position", cradle.get_hint(rover).begins_with("In position"),
		cradle.get_hint(rover))
	_check("install: try_install seats the module", cradle.try_install(rover))
	_check("install: Kite's cargo mount is empty", cargo.part == null)
	_check("install: the module is the cradle's occupant", cradle.occupant == module and module.get_parent() == cradle)
	var seat_error: float = module.global_position.distance_to(iris.module_seat_transform().origin)
	_check("install: the module is on the seat (5 mm)", seat_error < 0.005, "%.4f m" % seat_error)
	_check("install: the module is frozen with no collision",
		module.freeze and module.collision_layer == 0 and module.collision_mask == 0)
	_check("install: m2.module_installed and m2.iris_activated",
		CS.is_objective_done("m2.module_installed") and CS.is_objective_done("m2.iris_activated"))
	_check("install: iris_online is set", CS.has_flag("iris_online"))
	await _ticks(0.5)
	_check("install: IRIS comes online from the flag", iris.is_online)
	_check("install: IRIS's highlight_node is its online indicator",
		iris.highlight_node != null and iris.highlight_node.name == "iris_indicator", str(iris.highlight_node))
	_check("install: the indicator is lit", iris.highlight_node.material_override.emission_energy_multiplier > 0.0)
	await _ticks(iris.ANTENNA_TIME)
	_check("install: the antenna turned to its tracking pose",
		iris.antenna_pose().distance_to(iris.ANTENNA_TRACKED) < 0.5, str(iris.antenna_pose()))
	_check("install: a second try does nothing", not cradle.try_install(rover) and cradle.occupant == module)

	# 5. Load
	var loaded: Node3D = (load("res://src/iris/iris.tscn") as PackedScene).instantiate()
	level.add_child(loaded)
	loaded.global_position = iris.global_position + Vector3(0.0, 0.0, 30.0)
	await _ticks(0.2)
	var loaded_cradle: Node = loaded.get_node("ModuleCradle")
	_check("load: a fresh IRIS starts with the module seated",
		loaded_cradle.is_installed() and loaded_cradle.occupant.get_catalog_id() == "radio_module")
	_check("load: the restored module is on its seat",
		loaded_cradle.occupant.global_position.distance_to(loaded.module_seat_transform().origin) < 0.005)
	loaded.queue_free()

	# 6. No campaign
	CS.reset()
	var fresh: Node3D = (load("res://src/iris/iris.tscn") as PackedScene).instantiate()
	level.add_child(fresh)
	fresh.global_position = iris.global_position + Vector3(0.0, 0.0, -30.0)
	await _ticks(0.2)
	var fresh_cradle: Node = fresh.get_node("ModuleCradle")
	_check("no campaign: a fresh IRIS starts empty", not fresh_cradle.is_installed())
	_check("no campaign: the install is allowed", fresh_cradle.campaign_allows())
	fresh.queue_free()

	_finish()


func _finish() -> void:
	print("RESULT test_iris_module %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
