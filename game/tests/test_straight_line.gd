extends SceneTree
## Headless regression test: full throttle with no steering on flat ground must go straight.
## A fresh assembled rover on a 2 km flat ground, under Earth (9.8) and Moon (1.62) gravity,
## facing four directions, drives 12 s at full throttle; its heading may wander less than 1
## degree. (From e97bd34 to the tread-contact fix the tyre forces acted at whichever end of
## the tread the wheel's cylinder cast reported, and it drifted 38 degrees.)
## Prints one line per run and PASS / FAIL.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_straight_line.gd

const TICKS: int = 240
const SECONDS: float = 12.0
const MAX_DRIFT_DEG: float = 1.0
const GRAVITIES: Array[float] = [9.8, 1.62]
const HEADINGS_DEG: Array[float] = [0.0, 90.0, 180.0, 315.0]

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000.0, 1.0, 2000.0)
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(ground)
	for g in GRAVITIES:
		PhysicsServer3D.area_set_param(root.get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, g)
		for heading in HEADINGS_DEG:
			await _drive(g, heading)
	print("RESULT %s" % ("ALL PASS" if failures == 0 else "%d RUNS FAILED" % failures))
	quit()


func _drive(g: float, heading_deg: float) -> void:
	var GS: Node = root.get_node("GameState")
	var robot: RigidBody3D = load("res://src/robot/robot.tscn").instantiate()
	var controller: Node = load("res://src/robot/robot_controller.gd").new()
	root.add_child(controller)
	robot.controller = controller
	robot.start_assembled = true
	robot.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(heading_deg)), Vector3(0.0, 0.5, 0.0))
	root.add_child(robot)
	GS.robot = robot
	GS.change_state_to(GS.State.IN_GAME_ROBOT)
	await _ticks(2 * TICKS)   # settle

	var start_heading: float = robot.global_rotation.y
	var drift := 0.0
	Input.action_press("move_forward")
	for i in int(SECONDS * TICKS):
		await physics_frame
		drift = maxf(drift, absf(angle_difference(start_heading, robot.global_rotation.y)))
	Input.action_release("move_forward")
	var speed: float = robot.linear_velocity.dot(-robot.global_basis.z)
	var ok: bool = rad_to_deg(drift) < MAX_DRIFT_DEG
	if not ok:
		failures += 1
	print("RESULT g %-5.2f heading %5.0f deg   %s  drift %.3f deg, speed %.2f m/s after %.0f s" % [
		g, heading_deg, "PASS" if ok else "FAIL", rad_to_deg(drift), speed, SECONDS])

	GS.robot = null
	robot.queue_free()
	controller.queue_free()
	await _ticks(2)
