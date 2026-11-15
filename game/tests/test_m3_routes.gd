extends SceneTree
## Headless test (plan v2 R1): M3's routes against Kite's loadouts. Kite drives from the workshop
## apron along a route to the far logger, loads it, and drives home, during M3 (cold zones live).
## Each run prints what it cost: battery used, the lowest charge, time in cold shade, and how it
## ended (home, battery flat, cold shutdown, stuck).
##
## The plan's target is that the loadout you plan decides whether Kite comes home (EXPECTED below).
## Until the M3 retune (task F1) lands, ENFORCE is false: runs report "target" next to "now" and
## only completability is checked (some loadout gets home on some route). Flip ENFORCE after F1.
##
## Each case also has a cargo service: the Courier's M3 is in daylight; the Freighter arrives late,
## so M3 falls near nightfall (low sun, long shade, night-only cold zones on).
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_m3_routes.gd
##     ... -s res://tests/test_m3_routes.gd -- short light freighter   (one case; service defaults
##                                                                       to courier)
## A full run drives about 14 km; run single cases in parallel processes to save time.

const TICKS: int = 240
const ENFORCE: bool = false
const SPEED: float = 2.4
const STALL_TIME: float = 40.0                 # s without 2 m of progress = stuck
const PARTS: String = "res://src/robot/socket/%s.tscn"
## Loadout -> parts fitted before the trip
const LOADOUTS: Dictionary = {
	"light": {"battery": "battery_light_part", "wheels": "", "thermal": false},
	"standard": {"battery": "battery_part", "wheels": "", "thermal": false},
	"crater": {"battery": "battery_part", "wheels": "wheel_high_grip_part", "thermal": true},
}
const SERVICES: Array[String] = ["courier", "freighter"]
const SERVICE_PREFIX: String = "cargo.service."
## "route loadout service" -> the plan's target ending. Near nightfall both routes are partly in
## shade, so only the build with the thermal kit gets home.
const EXPECTED: Dictionary = {
	"short light courier": "fail", "long light courier": "fail",
	"short standard courier": "fail", "long standard courier": "home",
	"short crater courier": "home", "long crater courier": "home",
	"short light freighter": "fail", "long light freighter": "fail",
	"short standard freighter": "fail", "long standard freighter": "fail",
	"short crater freighter": "home", "long crater freighter": "home",
}

var GS: Node
var SL: Node
var CS: Node
var failures: int = 0
var level: Node3D
var rover: RigidBody3D
var director: Node
var routes: Node
var recovered: bool = false


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("%s  %s%s" % ["PASS" if ok else "FAIL", name, ("  (" + detail + ")") if detail else ""])


func _release_all() -> void:
	for a in ["move_forward", "move_backward", "move_left", "move_right"]:
		Input.action_release(a)


func _part(scene: String) -> Node:
	var part: Node = (load(PARTS % scene) as PackedScene).instantiate()
	level.add_child(part)
	return part


## Takes a part off and parks it out of the way. Not freed: RoverVisuals still remembers the
## last wheel per socket and errors on a freed one.
func _remove(socket: Node) -> void:
	var old: RigidBody3D = socket.unmount()
	if old:
		old.freeze = true
		old.global_position = Vector3(0.0, 500.0 + old.get_index(), 0.0)


func _swap(socket: Node, scene: String) -> void:
	_remove(socket)
	var part: Node3D = _part(scene)
	part.global_position = socket.global_position
	socket.mount(part)


func _fit(loadout: Dictionary) -> void:
	_swap(rover.battery_socket, loadout["battery"])
	if loadout["wheels"]:
		for socket in rover.find_children("*", "HotswapSocket", true, false):
			if socket.part and socket.part.part_type == 0:
				_swap(socket, loadout["wheels"])
	for pair in [["ThermalCoverSocket", "thermal_cover_part"], ["HeaterSocket", "thermal_heater_part"]]:
		var socket: Node = rover.get_node(pair[0])
		if loadout["thermal"]:
			_swap(socket, pair[1])
		else:
			_remove(socket)


func _battery() -> Node:
	return rover.battery_socket.part


## Drives through world waypoints (x, z). Returns "" on arrival, else why it stopped.
func _drive(points: Array, stats: Dictionary) -> String:
	var best: float = INF
	var since: float = 0.0
	for i in points.size():
		var target: Vector2 = points[i]
		var last: bool = i == points.size() - 1
		best = INF
		since = 0.0
		while true:
			await physics_frame
			stats["time"] += 1.0 / TICKS
			var battery: Node = _battery()
			stats["min_charge"] = minf(stats["min_charge"], battery.get_charge_fraction())
			stats["cold"] = maxf(stats["cold"], director.cold_time)
			if recovered:
				_release_all()
				return "cold shutdown" if director.cold_time > 0.0 else "recovered"
			if battery.charge <= 0.0:
				_release_all()
				return "battery flat"
			var forward: Vector3 = -rover.global_basis.z
			var v: float = rover.linear_velocity.dot(forward)
			var to := Vector2(target.x - rover.global_position.x, target.y - rover.global_position.z)
			var passed: bool = Vector2(forward.x, forward.z).dot(to) < 0.0 and to.length() < 2.0
			if (not last and (to.length() < 1.5 or passed)) or (last and to.length() < 1.5):
				break
			if to.length() < best - 2.0:
				best = to.length()
				since = 0.0
			else:
				since += 1.0 / TICKS
				if since > STALL_TIME:
					_release_all()
					return "stuck"
			var heading := Vector2(forward.x, forward.z).normalized()
			var steer: float = clampf(heading.angle_to(to.normalized()) / 0.25, -1.0, 1.0)
			_release_all()
			if v > SPEED + 0.15:
				Input.action_press("move_backward", clampf((v - SPEED) * 0.6, 0.05, 0.6))
			elif v < SPEED:
				Input.action_press("move_forward", clampf(0.06 + (SPEED - v) * 0.3, 0.05, 0.5))
			if steer > 0.05:
				Input.action_press("move_right", steer)
			elif steer < -0.05:
				Input.action_press("move_left", -steer)
	_release_all()
	return ""


## One trip: apron -> route -> logger -> back the same way -> apron. Returns its stats.
func _trip(route_id: String, loadout_id: String) -> Dictionary:
	var start: Vector2 = routes.start()
	var points: Array = Array(routes.route(route_id))
	_fit(LOADOUTS[loadout_id])
	_battery().charge = _battery().capacity
	var first: Vector2 = points[0]
	var at := Vector3(start.x, 0.0, start.y)
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 50.0, at + Vector3.DOWN * 50.0, 1)
	var hit: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(query)
	var look := Vector3(first.x - start.x, 0.0, first.y - start.y).normalized()
	rover.global_transform = Transform3D(Basis.looking_at(look), (hit["position"] if hit else at) + Vector3.UP * 0.4)
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	director.cold_time = 0.0
	recovered = false
	for i in TICKS:
		await physics_frame
	var stats: Dictionary = {"time": 0.0, "min_charge": 1.0, "cold": 0.0, "end": "", "where": "",
		"metres": routes.round_trip(route_id), "wh": 0.0}
	var full: float = _battery().charge
	var end: String = await _drive(points, stats)
	if end.is_empty():
		var logger: Node = level.get_node_or_null("FarLogger")
		var cargo: Node = rover.get_node("CargoSocket")
		if logger and cargo.part == null:
			cargo.mount(logger)               # the logger's 1.6 kg rides home
		var back: Array = points.duplicate()
		back.reverse()
		back.append(start)
		end = await _drive(back.slice(1), stats)
	stats["end"] = "home" if end.is_empty() else end
	stats["where"] = "(%.0f, %.0f)" % [rover.global_position.x, rover.global_position.z]
	stats["wh"] = full - _battery().charge
	return stats


## Records `id` as the service that delivered M2's cargo (as CargoPlan does) and shows its M3 sun,
## so the cold zones and their shade follow it
func _set_service(id: String) -> void:
	for other in SERVICES:
		if CS.has_item(SERVICE_PREFIX + other):
			CS.remove_item(SERVICE_PREFIX + other)
	CS.add_item(SERVICE_PREFIX + id)
	director.apply_mission_sun()


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
	var cutscenes: Node = level.find_child("Cutscenes", true, false)
	if cutscenes and cutscenes.is_playing():
		cutscenes.skip()
	rover = level.get_node("ReadyRover")
	director = level.get_node("MissionDirector")
	routes = level.get_node("RouteMarkers")
	director.recovery_started.connect(func(_r: Node) -> void: recovered = true)
	CS.start_mission("m3")
	while GS.state != GS.State.IN_GAME_PLAYER:
		await physics_frame
	GS.drive(rover)
	await physics_frame

	var args: PackedStringArray = OS.get_cmdline_user_args()
	var cases: Array = []
	if args.size() >= 2:
		cases.append([args[0], args[1], args[2] if args.size() >= 3 else "courier"])
	else:
		for sv in SERVICES:
			for r in ["short", "long"]:
				for l in LOADOUTS:
					cases.append([r, l, sv])
	var any_home: bool = false
	for c in cases:
		var key: String = "%s %s %s" % c
		_set_service(c[2])
		var s: Dictionary = await _trip(c[0], c[1])
		any_home = any_home or s["end"] == "home"
		var detail: String = "%s at %s · %.0f m planned · %.0f s · %.1f Wh used · lowest %d%% · cold %.0f s · target %s" % [
			s["end"], s["where"], s["metres"], s["time"], s["wh"], roundi(s["min_charge"] * 100.0), s["cold"], EXPECTED[key]]
		var matches: bool = (s["end"] == "home") == (EXPECTED[key] == "home")
		if ENFORCE:
			_check("route %s" % key, matches, detail)
		else:
			print("ROUTE %-25s %s%s" % [key, detail, "" if matches else "  <- differs from target"])
	if args.size() < 2:
		_check("completable: some loadout gets home on some route", any_home)

	print("RESULT test_m3_routes %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
