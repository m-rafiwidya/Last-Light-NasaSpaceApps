extends SceneTree
## Headless test: Rafi's field pieces as the Moon level places them, in a real run.
##   1. Placement: NearSampleSite (at IRIS's transform, no SampleSiteNear left), ThermalSensor and Evan's three notes
##      are in the level; the notes sit clear of every collider.
##   2. Kite note: next to Kite on the pad, reachable by the player's ray through its InteractTrigger, reads on E.
##   3. IRIS note: within 3 m of Kite's module stop, outside IRIS's collider; E does nothing before
##      m2.telemetry_received and reads it after.
##   4. Downlink: with the near sample open the Downlink tab warns before Receive telemetry without disabling it;
##      the warning goes once the sample is done.
##   5. Logger note: plays by itself when Kite parks at the logger's stop.
##   6. Thermal: with the turret, E in the mast view reads SUN on open ground and SHADE in Kite's shadow; MissionStats
##      keeps both and the M3 Science section shows them.
##   7. Missions: no "placeholder" step is left, the two field steps resolve, M3 has the shade marker line.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_field_placement.gd

const TICKS: int = 240
const MAST: int = 1
const TURRET_SCENE: String = "res://src/robot/socket/arm_tool_thermal_part.tscn"
const SOLID_MASK: int = 1 | 2 | 4

var GS: Node
var SL: Node
var CS: Node
var DS: Node
var failures: int = 0
var level: Node3D
var rover: RigidBody3D
var shown: Array = []


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


func _press_e() -> void:
	Input.action_press(&"interact_use")
	await physics_frame
	await physics_frame
	Input.action_release(&"interact_use")
	await physics_frame


func _ground(at: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 30.0, at + Vector3.DOWN * 30.0, 1)
	var hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if hit else at


func _park(at: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	rover.global_transform = Transform3D(basis, _ground(at) + Vector3.UP * 0.3)
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	await _ticks(2.5)
	rover.linear_velocity = Vector3.ZERO
	await _ticks(0.2)


## True when a small sphere just above `at` touches a solid collider (world, IRIS, vehicles)
func _blocked(at: Vector3) -> bool:
	var shape := SphereShape3D.new()
	shape.radius = 0.15
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.25)
	query.collision_mask = SOLID_MASK
	var hits: Array = level.get_world_3d().direct_space_state.intersect_shape(query, 4)
	return not hits.is_empty()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


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
	DS = root.get_node("DialogServer")
	while GS.state != GS.State.MAIN_MENU:
		await physics_frame
	CS.reset()
	load("res://src/save/save_index.gd").start_new_campaign()
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level"):
		await physics_frame
	level = SL.current_scene
	rover = level.get_node("ReadyRover")
	await _ticks(1.0)
	DS.stop_all()
	DS.dialog_played.connect(func(dialog: Resource) -> void: shown.append(dialog))
	var iris: Node3D = level.get_node("Iris")
	var kite_note: Node3D = level.get_node("EvanNoteKite")
	var iris_note: Node3D = level.get_node("EvanNoteIris")
	var logger_note: Node3D = level.get_node("EvanNoteLogger")
	var sensor: Node3D = level.get_node("ThermalSensor")
	var site: Node3D = level.get_node("NearSampleSite")

	# 1. Placement
	_check("placement: the near sample site faces as IRIS does, SampleSiteNear is gone",
		site.global_basis == iris.global_basis and level.get_node_or_null("SampleSiteNear") == null
		and site.is_in_group(&"near_sample_site"))
	# Lit ground: IRIS's body shadows the ground west of it for ~6 m under the level sun (16.7 degrees
	# up in the east), which covered the old patch. The patch's centre and corners now see the sun, the
	# post marks it (within 5 m) and the patch lies on the pad-to-IRIS approach (within 3 m of the line)
	var sun_dir: Vector3 = (level.get_node("WorldEnvironment") as LunarSky).sun_direction()
	var patch: Node3D = site.find_child("anchor_sample", true, false)
	var lit_points := 0
	for corner in [Vector3.ZERO, Vector3(0.9, 0, 0.9), Vector3(-0.9, 0, 0.9), Vector3(0.9, 0, -0.9), Vector3(-0.9, 0, -0.9)]:
		var from: Vector3 = patch.global_position + corner + Vector3.UP * 0.4
		var sun_query := PhysicsRayQueryParameters3D.create(from, from + sun_dir * 150.0, 1 | 2 | 4)
		lit_points += 1 if level.get_world_3d().direct_space_state.intersect_ray(sun_query).is_empty() else 0
	var pad: Vector2 = Vector2(level.get_node("ReadyRover").global_position.x, level.get_node("ReadyRover").global_position.z)
	var iris_xz := Vector2(iris.global_position.x, iris.global_position.z)
	var patch_xz := Vector2(patch.global_position.x, patch.global_position.z)
	var line_off: float = absf((patch_xz - pad).cross((iris_xz - pad).normalized()))
	var post_dist: float = level.get_node("SampleSitePost").global_position.distance_to(patch.global_position)
	# The post is solid: it stands beside the approach, not on it
	var post_xz := Vector2(level.get_node("SampleSitePost").global_position.x, level.get_node("SampleSitePost").global_position.z)
	var post_off: float = absf((post_xz - pad).cross((iris_xz - pad).normalized()))
	_check("placement: the near sample patch is in sunlight, on the pad-to-IRIS approach, its post beside it",
		lit_points == 5 and line_off < 3.0 and post_dist < 5.0 and post_off > 1.5 and patch.global_position.distance_to(iris.global_position) > 5.0,
		"lit %d/5, %.1f m off the approach, post %.1f m away and %.1f m off the approach" % [lit_points, line_off, post_dist, post_off])
	_check("placement: the thermal sensor is at the level root and in its group",
		sensor.get_parent() == level and sensor.is_in_group(&"thermal_sensor"))
	_check("placement: the three notes are clear of every collider",
		not _blocked(kite_note.global_position) and not _blocked(iris_note.global_position) and not _blocked(logger_note.global_position))

	# 2. Kite note
	var kite_d: float = _flat(kite_note.global_position, rover.global_position)
	_check("kite note: beside Kite, outside its 1.5 m wheel box", kite_d > 1.3 and kite_d < 3.0, "%.2f m" % kite_d)
	var away: Vector3 = (kite_note.global_position - rover.global_position) * Vector3(1.0, 0.0, 1.0)
	var eye: Vector3 = kite_note.global_position + away.normalized() * 0.8 + Vector3.UP * 1.5
	var aim: Vector3 = kite_note.get_node("InteractTrigger").global_position + Vector3.UP * 0.15
	var ray := PhysicsRayQueryParameters3D.create(eye, aim, GS.player.raycast.collision_mask)
	ray.collide_with_areas = true
	var hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(ray)
	_check("kite note: the player's ray from a step away reaches its trigger",
		hit and hit["collider"] == kite_note.get_node("InteractTrigger"), str(hit.get("collider")))
	hit["collider"].interact(GS.player)
	_check("kite note: E reads it on foot", kite_note.is_showing() and shown.back().subtitle.begins_with("KITE — STORAGE CHECK"))
	kite_note.toggle()

	# 3. IRIS note
	var park: Vector3 = iris.module_cradle.park_marker.global_position
	var iris_d: float = _flat(iris_note.global_position, park)
	_check("iris note: within 3 m of Kite's module stop, not on top of it", iris_d <= 3.0 and iris_d > 1.2, "%.2f m" % iris_d)
	_check("iris note: hidden before m2.telemetry_received", not iris_note.visible)
	CS.start_mission("m2")
	await _park(park, iris.global_basis)
	GS.drive(rover)
	await _ticks(0.3)
	await _press_e()
	_check("iris note: E near it does nothing before the telemetry", not iris_note.is_showing() and not iris_note.was_read)

	# 4. Downlink note
	for objective in ["m2.cargo_ordered", "m2.module_loaded", "m2.module_installed", "m2.iris_activated", "m2.kite_docked"]:
		CS.complete_objective(objective)
	GS.change_state_to(GS.State.MISSION_CONSOLE)
	var console: Node = root.get_node("Main").find_child("MissionConsole", true, false)
	console.select_section(console.Section.DOWNLINK)
	var text: String = console.get_node("%Description").text
	var warning: String = "near sample has not been collected"
	_check("downlink: the warning shows before Receive telemetry", text.contains(warning) and text.contains("ends M2"), text)
	_check("downlink: it comes before the ready text and does not block the button",
		text.find(warning) < text.find("ready") or not text.contains("ready"), "")
	_check("downlink: Receive telemetry stays enabled", not console.get_node("%Action").disabled)
	CS.complete_objective("m2.near_sample_collected")
	console.select_section(console.Section.DOWNLINK)
	_check("downlink: no warning once the sample is done", not console.get_node("%Description").text.contains(warning))

	# 5. IRIS note after the telemetry
	CS.complete_objective("m2.telemetry_received")
	GS.drive(rover)
	await _ticks(0.3)
	_check("iris note: visible after it", iris_note.visible)
	await _press_e()
	_check("iris note: E near it reads it", iris_note.is_showing() and shown.back().subtitle.begins_with("IRIS — FINAL FIELD CHECK"))
	iris_note.toggle()

	# 6. Logger note
	var far: Node3D = level.get_node("SampleSiteFar")
	var logger_park: Vector3 = far.find_child("park_logger", true, false).global_position
	var logger_d: float = _flat(logger_note.global_position, logger_park)
	_check("logger note: beside the logger, clear of Kite's stop", logger_d > 1.3 and logger_d <= 6.0
		and _flat(logger_note.global_position, level.get_node("FarLogger").global_position) < 2.0, "%.2f m" % logger_d)
	await _park(logger_park)
	await _ticks(0.3)
	_check("logger note: plays by itself when Kite parks at the logger", logger_note.was_read
		and shown.back().subtitle.contains("second label underneath"))
	DS.stop_all()

	# 7. Thermal readings in a real run
	CS.start_mission("m3")
	var stats: Dictionary = CS.mission_stats("m3")
	var sun: Vector3 = sensor._sun_direction()
	var flat_sun := Vector3(sun.x, 0.0, sun.z).normalized()
	await _park(iris.global_position + flat_sun * 12.0)
	var socket: Node = rover.find_child("ArmToolSocket", true, false)
	var old: Node = socket.unmount()
	if old:
		old.queue_free()
	var turret: RigidBody3D = (load(TURRET_SCENE) as PackedScene).instantiate()
	level.add_child(turret)
	turret.global_position = socket.global_position
	socket.mount(turret)
	GS.drive(rover)
	await _ticks(0.5)
	rover.get_node("CameraRig")._switch(MAST)
	var open: Vector3 = _ground(rover.global_position + flat_sun * 3.0)
	_aim_mast_at(open)
	await _ticks(0.3)
	_check("thermal: the hint says SUN on open ground", sensor.get_hint(rover).contains("SUN"), sensor.get_hint(rover))
	await _press_e()
	_check("thermal: E reads SUN", sensor.readings.has("sun") and not sensor.readings.has("shade"), str(sensor.readings))
	var kite_shade: Vector3 = Vector3.ZERO
	var query := PhysicsRayQueryParameters3D.create(rover.global_position + Vector3.UP * 0.25,
		rover.global_position + Vector3.UP * 0.25 - sun * 60.0, 1)
	var shade_hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(query)
	kite_shade = shade_hit["position"] if shade_hit else rover.global_position
	_aim_mast_at(kite_shade)
	await _ticks(0.3)
	_check("thermal: the hint says SHADE in Kite's shadow", sensor.get_hint(rover).contains("SHADE"), sensor.get_hint(rover))
	await _press_e()
	_check("thermal: E reads SHADE and the pair completes", sensor.has_pair(), str(sensor.readings))
	_check("thermal: MissionStats keeps both readings", is_equal_approx(float(stats.get("thermal_sun", INF)), sensor.readings["sun"])
		and is_equal_approx(float(stats.get("thermal_shade", INF)), sensor.readings["shade"]), str(stats))
	var MR: GDScript = load("res://src/ui/mission_console/mission_report.gd")
	var science: Dictionary = MR.sections("m3")[1]
	var expected: String = "Ground temperature: sun %+d °C, shade %+d °C" % [roundi(sensor.readings["sun"]), roundi(sensor.readings["shade"])]
	_check("thermal: the M3 Science section shows them", str(science["body"]).contains(expected), str(science["body"]))
	_check("thermal: a missing reading says so", MR.ground_temperature({"thermal_sun": 100.0}).contains("shade not measured"))

	# 8. Missions
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://res/story/missions.json"))
	var placeholders: int = 0
	for mission in data["missions"]:
		for objective in mission.get("guidance", {}):
			for step in mission["guidance"][objective]:
				placeholders += 1 if step.has("placeholder") else 0
	_check("missions: no placeholder step is left", placeholders == 0 and not JSON.stringify(data["missions"]).contains("placeholder"))
	var guidance: Node = level.get_node("Guidance")
	var m2: Dictionary = data["missions"][1]["guidance"]
	var iris_target: String = m2["m2.iris_activated"][0]["target"]
	var sample_target: String = m2["m2.near_sample_collected"][0]["target"]
	_check("missions: m2.iris_activated targets path:Iris", iris_target == "path:Iris" and guidance.resolve(iris_target) == iris, iris_target)
	_check("missions: m2.near_sample_collected targets group:near_sample_site",
		sample_target == "group:near_sample_site" and guidance.resolve(sample_target) == site, sample_target)
	_check("missions: M3 has the shade marker checklist line",
		CS.mission_checklist("m3") == PackedStringArray(["Check the shade marker before the return climb"]))

	print("RESULT test_field_placement %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
