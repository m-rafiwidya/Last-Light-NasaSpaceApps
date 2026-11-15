extends SceneTree
## Headless test (plan v2 R2): the delivery crate as a cargo part Kite carries home.
##   1. The part: CARGO, catalog cargo_crate with a name, in group claw_target, no static collider
##      left from the decor model, a box that fits the cargo mount's capture box.
##   2. Mounting: Kite's cargo mount takes it, Kite's mass grows by the crate's, and taking it off
##      gives it back.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_cargo_crate_part.gd

const TICKS: int = 240
const SCENE: String = "res://src/field/cargo_crate_part.tscn"

var GS: Node
var SL: Node
var CS: Node
var failures: int = 0


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
	var level: Node3D = SL.current_scene
	var rover: RigidBody3D = level.get_node("ReadyRover")
	var cargo: Node = rover.get_node("CargoSocket")
	await _ticks(0.5)

	# 1. The part
	var crate: RigidBody3D = (load(SCENE) as PackedScene).instantiate()
	level.add_child(crate)
	crate.global_position = cargo.global_position + Vector3.UP * 0.5
	await _ticks(0.1)
	_check("part: CARGO, catalog cargo_crate", crate.part_type == 6 and crate.get_catalog_id() == "cargo_crate")
	_check("part: the catalog names it", crate.get_display_name() != "cargo_crate" and not crate.get_display_name().is_empty(),
		crate.get_display_name())
	_check("part: in group claw_target", crate.is_in_group(&"claw_target"))
	_check("part: no static collider left from the decor model", crate.find_children("*", "StaticBody3D", true, false).is_empty())
	var box: Vector3 = (crate.get_node("CollisionShape3D").shape as BoxShape3D).size
	var capture: Vector3 = cargo.capture_size
	_check("part: its box fits the cargo mount's capture box", box.x <= capture.x and box.y <= capture.y and box.z <= capture.z,
		"%s in %s" % [box, capture])

	# 2. Mounting
	var empty_mass: float = rover.mass
	crate.mass = 14.0                        # F2 sets the order's mass
	cargo.mount(crate)
	await _ticks(0.2)
	_check("mount: Kite's cargo mount takes it", cargo.part == crate and crate.is_mounted())
	_check("mount: Kite carries its mass", is_equal_approx(rover.mass, empty_mass + 14.0) and is_equal_approx(rover.cargo_mass, 14.0),
		"%.1f kg (was %.1f)" % [rover.mass, empty_mass])
	var off: Node = cargo.unmount()
	crate.global_position = rover.global_position + rover.global_basis.x * 2.0 + Vector3.UP * 0.3  # out of the capture box
	await _ticks(0.2)
	_check("mount: taking it off gives it back", off == crate and not crate.is_mounted() and cargo.part == null
		and is_equal_approx(rover.mass, empty_mass), "%s, mounted %s, %.1f kg" % [off, crate.is_mounted(), rover.mass])

	print("RESULT test_cargo_crate_part %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
