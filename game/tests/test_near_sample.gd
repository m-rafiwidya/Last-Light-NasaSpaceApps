extends SceneTree
## Headless test: M2's required near sample (NearSampleSite, plan item S).
##   1. Setup: the level's NearSampleSite faces as IRIS does (it stands clear of IRIS's shadow, on lit ground), the site joins its group, highlights its patch and finds anchor_sample.
##   2. Mission: in m1 nothing happens, even parked at the patch with S-1 on the cargo mount.
##   3. Container: in m2 without S-1 the hint asks for it and nothing happens.
##   4. Position: 6 m out the hint says to come closer.
##   5. Collect: at park_sample, stopped, E while driving fills S-1 (full model) and completes
##      m2.near_sample_collected without completing m2; a second try does nothing.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_near_sample.gd

const TICKS: int = 240

var GS: Node
var SL: Node
var CS: Node
var failures: int = 0
var level: Node3D
var rover: RigidBody3D
var site: Node3D
var cargo: Node
var container: RigidBody3D


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


func _press_e() -> void:
	Input.action_press(&"interact_use")
	await physics_frame
	await physics_frame
	Input.action_release(&"interact_use")
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
	level = SL.current_scene
	rover = level.get_node("ReadyRover")
	cargo = rover.get_node("CargoSocket")
	site = level.get_node("NearSampleSite")
	await _ticks(1.0)

	# 1. Setup
	var park: Vector3 = site.find_child("park_sample", true, false).global_position
	_check("setup: in group near_sample_site, facing as IRIS does", get_first_node_in_group(&"near_sample_site") == site
		and site.global_basis == level.get_node("Iris").global_basis and level.get_node_or_null("SampleSiteNear") == null)
	_check("setup: highlight_node is the patch", site.highlight_node == site.get_node("Site")
		and not site.highlight_node.find_children("*", "MeshInstance3D", true, false).is_empty())
	_check("setup: park_sample is within SAMPLE_RANGE of the patch",
		Vector2(park.x - site.anchor.global_position.x, park.z - site.anchor.global_position.z).length() <= site.SAMPLE_RANGE,
		"%.2f m" % Vector2(park.x - site.anchor.global_position.x, park.z - site.anchor.global_position.z).length())

	# 2. Mission
	container = load("res://src/robot/socket/sample_container_part.tscn").instantiate()
	level.add_child(container)
	container.global_position = cargo.global_position
	cargo.mount(container)
	await _park(park)
	_check("mission: S-1 is on the cargo mount", cargo.part == container)
	_check("mission: refused in m1", CS.current_mission() == "m1" and not site.try_collect(rover)
		and site.get_hint(rover) == "")

	# 3. Container
	CS.start_mission("m2")
	cargo.unmount()
	_check("container: without S-1 the hint asks for it", site.get_hint(rover).contains("S-1"), site.get_hint(rover))
	_check("container: and nothing happens", not site.try_collect(rover))
	cargo.mount(container)
	await _ticks(0.2)

	# 4. Position
	await _park(park + site.global_basis.x * -6.0)
	_check("position: 6 m out the hint says closer", site.get_hint(rover).contains("closer"), site.get_hint(rover))

	# 5. Collect
	await _park(park)
	_check("collect: the hint says In position", site.get_hint(rover).begins_with("In position"),
		"%s, %.2f m, %.2f m/s" % [site.get_hint(rover), site.site_distance(rover), rover.linear_velocity.length()])
	var shown: Array = []
	root.get_node("DialogServer").dialog_played.connect(func(dialog: Resource) -> void: shown.append(dialog.subtitle))
	GS.drive(rover)
	await _ticks(0.1)
	# Subtitles play one at a time (#71), so the cue may wait behind a line already showing
	var is_cue := func(s: String) -> bool: return s.begins_with("Near sample site. Stop")
	for i in 30 * TICKS:
		if shown.any(is_cue):
			break
		await physics_frame
	await _ticks(0.5)
	_check("collect: arriving with S-1 cues the E press once",
		shown.filter(func(s: String) -> bool: return s.begins_with("Near sample site. Stop")).size() == 1, str(shown))
	await _press_e()
	_check("collect: E completes m2.near_sample_collected", CS.is_objective_done("m2.near_sample_collected"))
	_check("collect: m2 itself isn't completed", CS.current_mission() == "m2" and not CS.is_mission_completed("m2"))
	var kit: Node = container.get_node_or_null("Model/Kit")
	_check("collect: S-1 shows the full model", kit != null
		and kit.scene_file_path == "res://res/models/rover_kit/sample_container_full.glb", kit.scene_file_path if kit else "none")
	_check("collect: a second try does nothing", not site.try_collect(rover) and site.get_hint(rover) == "")

	print("RESULT test_near_sample %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
