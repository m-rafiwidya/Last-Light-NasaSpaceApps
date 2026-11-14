extends SceneTree
## Headless test: M3's logger recovery (FieldLoggerPickup, simple version without the arm).
##   1. Setup: a FieldLoggerPickup in the Moon level finds FarLogger and joins its group.
##   2. Mission: in m1 the logger can't be loaded, even parked beside it.
##   3. Position: in m3, 5 m away refuses it and the hint says to come closer.
##   4. Load: beside it and stopped, the hint says "In position"; try_load mounts FarLogger on Kite's
##      cargo mount and MissionDirector completes m3.logger_recovered. A second try does nothing.
##   5. Load from a save: with m3.logger_recovered done, a logger still lying in the level is
##      removed; one mounted on Kite stays.
##   6. No campaign: loading is allowed.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_field_logger.gd

const TICKS: int = 240
const PICKUP_SCENE: String = "res://src/field/field_logger_pickup.tscn"
const LOGGER_SCENE: String = "res://src/robot/socket/field_logger_part.tscn"

var GS: Node
var SL: Node
var CS: Node
var failures: int = 0
var level: Node3D
var rover: RigidBody3D
var logger: RigidBody3D
var pickup: Node3D
var cargo: Node


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


## Kite beside the logger: its origin `away` m to the logger's side, facing along the slope's
## contour, so the cargo mount (near the origin) ends up about `away` m from the logger
func _park_beside(away: float) -> void:
	var at: Vector3 = logger.global_position + Vector3(away, 0.0, 0.0)
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 20.0, at + Vector3.DOWN * 20.0, 1)
	var hit: Dictionary = rover.get_world_3d().direct_space_state.intersect_ray(query)
	var ground: float = (hit["position"] as Vector3).y if hit else at.y
	rover.global_transform = Transform3D(Basis.IDENTITY, Vector3(at.x, ground + 0.3, at.z))
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	await _ticks(2.5)
	rover.linear_velocity = Vector3.ZERO
	await _ticks(0.2)


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
	logger = level.get_node("FarLogger")
	cargo = rover.get_node("CargoSocket")
	pickup = (load(PICKUP_SCENE) as PackedScene).instantiate()
	level.add_child(pickup)
	await _ticks(1.0)

	# 1. Setup
	_check("setup: the pickup finds FarLogger", pickup.logger == logger)
	_check("setup: the pickup is in group field_logger_pickup",
		get_first_node_in_group(&"field_logger_pickup") == pickup)

	# 2. Mission
	await _park_beside(1.0)
	_check("mission: parked beside the logger", pickup.pickup_distance(rover) <= pickup.PICKUP_RANGE,
		"%.2f m" % pickup.pickup_distance(rover))
	_check("mission: refused in m1", CS.current_mission() == "m1" and not pickup.try_load(rover)
		and cargo.part == null and pickup.get_hint(rover) == "")

	# 3. Position
	CS.start_mission("m3")
	await _park_beside(5.0)
	_check("position: refused 5 m out", not pickup.try_load(rover) and cargo.part == null)
	_check("position: the hint says to come closer", pickup.get_hint(rover).contains("closer"), pickup.get_hint(rover))

	# 4. Load
	await _park_beside(1.0)
	_check("load: the hint says In position", pickup.get_hint(rover).begins_with("In position"),
		"%s, %.2f m, %.2f m/s" % [pickup.get_hint(rover), pickup.pickup_distance(rover), rover.linear_velocity.length()])
	_check("load: try_load mounts the logger", pickup.try_load(rover))
	await _ticks(0.2)
	_check("load: FarLogger is on Kite's cargo mount", cargo.part == logger and logger.is_mounted())
	_check("load: m3.logger_recovered (MissionDirector)", CS.is_objective_done("m3.logger_recovered"))
	_check("load: a second try does nothing", not pickup.try_load(rover) and pickup.get_hint(rover) == "")

	# 5. Load from a save
	var lying: RigidBody3D = (load(LOGGER_SCENE) as PackedScene).instantiate()
	lying.name = "LyingLogger"
	level.add_child(lying)
	lying.global_position = logger.global_position + Vector3(0.0, 0.0, 40.0)
	var restored: Node3D = (load(PICKUP_SCENE) as PackedScene).instantiate()
	restored.logger_path = ^"../LyingLogger"
	level.add_child(restored)
	await _ticks(0.2)
	_check("save: with the objective done, the logger lying in the level is removed",
		not is_instance_valid(lying) and restored.logger == null)
	restored.queue_free()
	var kept: Node3D = (load(PICKUP_SCENE) as PackedScene).instantiate()
	level.add_child(kept)
	await _ticks(0.2)
	_check("save: the logger mounted on Kite stays", is_instance_valid(logger) and cargo.part == logger)
	kept.queue_free()

	# 6. No campaign
	CS.reset()
	_check("no campaign: loading is allowed", pickup.campaign_allows())

	print("RESULT test_field_logger %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
