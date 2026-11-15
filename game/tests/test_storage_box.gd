extends SceneTree
## Headless test (plan v2 G2): Kite's storage box, two deck slots for small parts.
##   1. The box: StorageBox with StorageSlot1/2, named "Storage box", listing what fits.
##   2. Small parts: a sample container dropped into a slot is mounted; the scoop fits too.
##   3. Big parts are refused: the radio module, the far logger and the delivery crate.
##   4. Together: S-1 in the box while the logger rides the cargo mount; Kite carries both.
##   5. Saves: KiteSave keeps what's in the box and puts it back.
##   6. Near sample: S-1 in the box counts at the site (no cargo mount needed).
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_storage_box.gd

const TICKS: int = 240
const PARTS: String = "res://src/robot/socket/%s.tscn"

var GS: Node
var SL: Node
var CS: Node
var failures: int = 0
var level: Node3D
var rover: RigidBody3D


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


func _part(scene: String) -> RigidBody3D:
	var part: RigidBody3D = (load(scene) as PackedScene).instantiate()
	level.add_child(part)
	part.global_position = rover.global_position + Vector3(3.0, 1.0, 0.0)
	return part


## Drops `part` just above `socket`'s capture box and lets physics run
func _drop_into(part: RigidBody3D, socket: Node3D) -> void:
	part.global_transform = Transform3D(rover.global_basis, socket.global_position + Vector3.UP * 0.05)
	part.linear_velocity = Vector3.ZERO
	await _ticks(0.5)


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
	await _ticks(0.5)

	# 1. The box
	var box: Node3D = rover.get_node_or_null("StorageBox")
	var slot1: Node = rover.get_node_or_null("StorageBox/StorageSlot1")
	var slot2: Node = rover.get_node_or_null("StorageBox/StorageSlot2")
	_check("box: StorageBox with two slots", box != null and slot1 != null and slot2 != null)
	_check("box: named, and lists what fits", slot1.socket_name == "Storage box" and slot1.get_accepted_name().contains("Sample container"),
		slot1.get_accepted_name())

	# 2. Small parts
	var s1: RigidBody3D = _part(PARTS % "sample_container_part")
	await _drop_into(s1, slot1)
	_check("small: a sample container dropped into a slot is mounted", slot1.part == s1 and s1.is_mounted())
	var scoop: RigidBody3D = _part(PARTS % "sample_scoop_part")
	_check("small: the scoop fits too", slot2.can_accept(scoop))
	scoop.queue_free()

	# 3. Big parts are refused
	for scene in [PARTS % "radio_module_part", PARTS % "field_logger_part", "res://src/field/cargo_crate_part.tscn"]:
		var big: RigidBody3D = _part(scene)
		_check("big: the box refuses %s" % big.get_catalog_id(), not slot2.can_accept(big) and not slot2.accepts_type(big))
		big.queue_free()

	# 4. Together
	var empty_mass: float = rover.mass - s1.mass
	var logger: RigidBody3D = level.get_node("FarLogger")
	var cargo: Node = rover.get_node("CargoSocket")
	cargo.mount(logger)
	await _ticks(0.2)
	_check("together: S-1 in the box and the logger on the cargo mount", slot1.part == s1 and cargo.part == logger)
	_check("together: Kite carries both", is_equal_approx(rover.mass, empty_mass + s1.mass + logger.mass),
		"%.1f kg" % rover.mass)

	# 5. Saves
	var KiteSave: GDScript = load("res://src/save/kite_save.gd")
	var saved: Dictionary = KiteSave.capture(rover)
	_check("save: the box slot is saved with S-1", saved["sockets"].get("StorageSlot1") is Dictionary
		and str(saved["sockets"]["StorageSlot1"]["scene"]).ends_with("sample_container_part.tscn"), str(saved["sockets"].get("StorageSlot1")))
	var off: Node = slot1.unmount()
	off.global_position = rover.global_position + Vector3(4.0, 1.0, 0.0)
	await _ticks(0.2)
	KiteSave.apply(rover, saved)
	await _ticks(0.3)
	_check("save: loading puts a sample container back in the box", slot1.part != null
		and slot1.part.get_catalog_id() == "sample_container", str(slot1.part))

	# 6. Near sample: S-1 in the box counts
	cargo.unmount().global_position = rover.global_position + Vector3(-4.0, 1.0, 0.0)
	var site: Node3D = (load("res://src/field/near_sample_site.tscn") as PackedScene).instantiate()
	level.add_child(site)
	site.global_position += rover.global_position - site.anchor.global_position
	CS.start_mission("m2")
	rover.linear_velocity = Vector3.ZERO
	await _ticks(0.3)
	_check("sample: S-1 in the box is enough at the near site", cargo.part == null and site.can_collect(rover),
		site.get_hint(rover))

	print("RESULT test_storage_box %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
