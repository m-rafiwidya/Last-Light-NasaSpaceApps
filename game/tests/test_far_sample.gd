extends SceneTree
## Headless test (plan v2 R3): M3's optional far sample (far_sample_site.tscn, the near sample's
## script with S-2, M3 and m3.far_sample_collected).
##   1. Setup: placed where the level's SampleSiteFar is, it joins group far_sample_site and
##      highlights its patch; park_sample is in range.
##   2. Silent until missions.json has m3.far_sample_collected (Fahd's F3), even in M3.
##   3. Mission: with the objective, in M2 nothing happens.
##   4. Container: in M3, S-1 isn't the far site's container; the hint asks for S-2.
##   5. Collect: S-2 in the storage box, parked and stopped: try_collect fills it (full model) and
##      completes m3.far_sample_collected without completing M3. A second try does nothing.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_far_sample.gd

const TICKS: int = 240
const OBJECTIVE: String = "m3.far_sample_collected"

var GS: Node
var SL: Node
var CS: Node
var failures: int = 0
var level: Node3D
var rover: RigidBody3D
var site: Node3D


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


func _park(at: Vector3) -> void:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 20.0, at + Vector3.DOWN * 20.0, 1)
	var hit: Dictionary = rover.get_world_3d().direct_space_state.intersect_ray(query)
	var ground: float = (hit["position"] as Vector3).y if hit else at.y
	rover.global_transform = Transform3D(site.global_basis, Vector3(at.x, ground + 0.3, at.z))
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	await _ticks(2.5)
	rover.linear_velocity = Vector3.ZERO
	await _ticks(0.2)


func _part(scene: String) -> RigidBody3D:
	var part: RigidBody3D = (load("res://src/robot/socket/%s.tscn" % scene) as PackedScene).instantiate()
	level.add_child(part)
	return part


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
	var cargo: Node = rover.get_node("CargoSocket")
	var slot: Node = rover.get_node("StorageBox/StorageSlot1")
	site = (load("res://src/field/far_sample_site.tscn") as PackedScene).instantiate()
	level.add_child(site)
	site.global_transform = level.get_node("SampleSiteFar").global_transform
	await _ticks(1.0)

	# 1. Setup
	var park: Vector3 = site.find_child("park_sample", true, false).global_position
	var to_park: float = Vector2(park.x - site.anchor.global_position.x, park.z - site.anchor.global_position.z).length()
	_check("setup: in group far_sample_site", get_first_node_in_group(&"far_sample_site") == site
		and not site.is_in_group(&"near_sample_site"))
	_check("setup: highlight_node is the far patch", site.highlight_node == site.get_node("Site")
		and not site.highlight_node.find_children("*", "MeshInstance3D", true, false).is_empty())
	_check("setup: park_sample is within SAMPLE_RANGE of the patch", to_park <= site.SAMPLE_RANGE, "%.2f m" % to_park)

	# 2. Silent until missions.json has the objective
	var s2: RigidBody3D = _part("sample_container_far_part")
	s2.global_position = slot.global_position
	slot.mount(s2)
	await _park(park)
	if not CS.has_objective(OBJECTIVE):
		CS.start_mission("m3")
		_check("silent: without %s in missions.json nothing happens, even in M3" % OBJECTIVE,
			not site.try_collect(rover) and site.get_hint(rover) == "")
		CS._objective_mission[OBJECTIVE] = "m3"        # until Fahd's F3 adds it
	CS.start_mission("m2")

	# 3. Mission
	_check("mission: refused in M2", not site.try_collect(rover) and site.get_hint(rover) == "")

	# 4. Container
	CS.start_mission("m3")
	slot.unmount().global_position = rover.global_position + Vector3(3.0, 1.0, 0.0)
	var s1: RigidBody3D = _part("sample_container_part")
	s1.global_position = slot.global_position
	slot.mount(s1)
	await _ticks(0.2)
	_check("container: S-1 isn't the far site's container; the hint asks for S-2",
		not site.try_collect(rover) and site.get_hint(rover).contains("S-2"), site.get_hint(rover))
	slot.unmount().global_position = rover.global_position + Vector3(-3.0, 1.0, 0.0)
	s2.global_position = slot.global_position
	slot.mount(s2)
	await _ticks(0.2)

	# 5. Collect
	_check("collect: the hint says In position for the far sample", site.get_hint(rover) .begins_with("In position")
		and site.get_hint(rover).contains("far sample"), site.get_hint(rover))
	_check("collect: try_collect fills S-2 from the storage box", site.try_collect(rover) and CS.is_objective_done(OBJECTIVE))
	_check("collect: M3 itself isn't completed", CS.current_mission() == "m3" and not CS.is_mission_completed("m3"))
	var kit: Node = s2.get_node_or_null("Model/Kit")
	_check("collect: S-2 shows the full model", kit != null
		and kit.scene_file_path == "res://res/models/rover_kit/sample_container_full.glb", kit.scene_file_path if kit else "none")
	_check("collect: a second try does nothing", not site.try_collect(rover) and site.get_hint(rover) == "")

	print("RESULT test_far_sample %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
