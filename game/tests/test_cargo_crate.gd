extends SceneTree
## Headless test: the M2 delivery crate (CargoCrate, workflow.md "Crate contract").
##   1. Before the delivery: the crate is in group cargo_crate, hidden, without collision, empty.
##   2. Delivery: CargoPlan.deliver (courier, radio module) makes it appear, open its lid and lay
##      out one radio-power module, which settles inside; the label names the service; Guidance's
##      `group:cargo_crate` finds it and its highlight_node has meshes.
##   3. Rack: with the crate in the level, the workshop rack shows no radio-power module.
##   4. Load: a crate made after the delivery starts open and filled; with the module mounted on
##      Kite, or seated in IRIS's module bay, it lays out none, so there's never two.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_cargo_crate.gd

const TICKS: int = 240
const CRATE_SCENE: String = "res://src/field/cargo_crate.tscn"

var GS: Node
var SL: Node
var CS: Node
var failures: int = 0
var level: Node3D
var workshop: Node3D
var rover: RigidBody3D
var iris: Node3D


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


func _crate_at(offset: Vector3) -> Node3D:
	var crate: Node3D = (load(CRATE_SCENE) as PackedScene).instantiate()
	level.add_child(crate)
	var spot: Vector3 = workshop.pad.global_position + offset
	crate.global_position = Vector3(spot.x, workshop.pad.global_position.y, spot.z)
	return crate


func _modules_in(container: Node) -> int:
	var count: int = 0
	for part in container.find_children("*", "RigidBody3D", true, false):
		if part.has_method("get_catalog_id") and part.get_catalog_id() == "radio_module":
			count += 1
	return count


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
	workshop = level.get_node("Workshop")
	rover = level.get_node("ReadyRover")
	iris = level.get_node("Iris")
	await _ticks(1.0)
	var plan: Script = load("res://src/levels/cargo_plan.gd")

	# 1. Before the delivery
	var crate: Node3D = _crate_at(Vector3(2.0, 0.0, 1.5))
	await _ticks(0.2)
	_check("before: the crate is in group cargo_crate", crate.is_in_group(&"cargo_crate"))
	_check("before: hidden", not crate.visible)
	var layers: int = 0
	for body in crate.find_children("*", "StaticBody3D", true, false):
		layers |= body.collision_layer
	_check("before: no collision", layers == 0)
	_check("before: empty and closed", crate.contents.is_empty() and not crate.is_open)

	# 2. Delivery
	CS.start_mission("m2")
	_check("delivery: CargoPlan.deliver(courier, radio module)", plan.deliver("courier", ["radio_module"]))
	await _ticks(2.5)
	_check("delivery: the crate appears", crate.visible)
	layers = 0
	for body in crate.find_children("*", "StaticBody3D", true, false):
		layers |= body.collision_layer
	_check("delivery: with collision", layers == 1)
	var lid: float = crate.get_node("Look/LidHinge").rotation_degrees.x
	_check("delivery: the lid opened", crate.is_open and absf(lid - crate.LID_OPEN_DEG) < 0.5, "%.1f deg" % lid)
	_check("delivery: one radio-power module laid out",
		crate.contents.size() == 1 and _modules_in(crate) == 1, str(crate.contents))
	if not crate.contents.is_empty():
		var local: Vector3 = crate.to_local(crate.contents[0].global_position)
		var half: Vector3 = crate.SIZE / 2.0
		_check("delivery: the module settled inside the crate",
			absf(local.x) < half.x and absf(local.z) < half.z and local.y > 0.0 and local.y < crate.SIZE.y,
			str(local))
	_check("delivery: the label names the service", crate.get_node("Label").text.contains("COURIER"),
		crate.get_node("Label").text)
	var guidance: Node = get_first_node_in_group(&"guidance")
	_check("delivery: Guidance resolves group:cargo_crate",
		guidance != null and guidance.resolve("group:cargo_crate") == crate)
	_check("delivery: highlight_node has meshes", crate.highlight_node != null
		and not crate.highlight_node.find_children("*", "MeshInstance3D", true, false).is_empty())

	# 3. Rack
	workshop.account_rack()
	await _ticks(0.2)
	_check("rack: no radio-power module on the rack", _modules_in(workshop.rack_stock) == 0,
		"%d" % _modules_in(workshop.rack_stock))

	# 4. Load
	var module: RigidBody3D = crate.contents[0] if not crate.contents.is_empty() else null
	var cargo: Node = rover.get_node("CargoSocket")
	if module:
		module.reparent(level, true)      # out of the crate, so freeing the crate keeps it
		module.freeze = true
	crate.queue_free()
	await _ticks(0.1)
	var reloaded: Node3D = _crate_at(Vector3(2.0, 0.0, -1.5))
	await _ticks(0.5)
	_check("load: a crate made after the delivery starts open and filled",
		reloaded.visible and reloaded.is_open and reloaded.contents.size() == 1)
	reloaded.queue_free()
	if module:
		module.freeze = false
		cargo.mount(module)
	_check("load: the module is on Kite's cargo mount", module != null and cargo.part == module)
	await _ticks(0.1)
	var with_kite: Node3D = _crate_at(Vector3(-2.0, 0.0, 1.5))
	await _ticks(0.5)
	_check("load: module on Kite, the crate lays out none", with_kite.is_open and with_kite.contents.is_empty(),
		str(with_kite.contents))
	with_kite.queue_free()
	if module:
		cargo.unmount()
		var bay: Node3D = iris.get_node("ModuleCradle")
		module.reparent(bay, false)
		module.transform = Transform3D.IDENTITY
		module.freeze = true
	await _ticks(0.1)
	var with_iris: Node3D = _crate_at(Vector3(-2.0, 0.0, -1.5))
	await _ticks(0.5)
	_check("load: module in IRIS's bay, the crate lays out none", with_iris.contents.is_empty(),
		str(with_iris.contents))
	with_iris.queue_free()

	print("RESULT test_cargo_crate %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
