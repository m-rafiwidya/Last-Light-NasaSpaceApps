extends SceneTree
## Headless test: the route flags turn about their pole to face the camera, and the Merah Putih
## easter egg stands by the landing zone.
##   1. Merah Putih: in the Moon level (outside RouteMarkers), red over white, up in M1 while the
##      route flags are still hidden.
##   2. Facing: a flag's pivot turns so its face points at the camera, wherever the camera goes.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_route_flags.gd

var GS: Node
var SL: Node
var failures := 0


func _initialize() -> void:
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-70s %s %s" % [name, "PASS" if ok else "FAIL", detail])


## How far (degrees) the pivot's face (+Z) is off the direction to `cam`, about the vertical
func _facing_error(pivot: Node3D, cam: Camera3D) -> float:
	var to_cam: Vector3 = cam.global_position - pivot.global_position
	var face: Vector3 = pivot.global_basis.z
	return rad_to_deg(absf(Vector2(face.x, face.z).angle_to(Vector2(to_cam.x, to_cam.z))))


func _run() -> void:
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	while GS.state != GS.State.MAIN_MENU:
		await physics_frame
	SL.load_scene("moon_level")
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level"):
		await physics_frame
	var level: Node = SL.current_scene
	for i in 10:
		await process_frame
	var markers: Node3D = level.get_node("RouteMarkers")

	# 1. Merah Putih
	var egg := level.get_node_or_null("MerahPutih") as Node3D
	_check("merah putih: in the level, outside RouteMarkers", egg != null and egg.get_parent() == level)
	if egg == null:
		quit(1)
		return
	var stripes: Array = egg.get_node("FlagPivot").get_children()
	var colors: Array = stripes.map(func(m: MeshInstance3D) -> Color: return (m.mesh as BoxMesh).material.albedo_color)
	_check("merah putih: red over white", stripes.size() == 2 and colors[0].r > 0.7 and colors[0].g < 0.2
		and colors[1].g > 0.9 and stripes[0].position.y > stripes[1].position.y, str(colors))
	var landing: Node3D = level.get_node("LandingZone")
	var dist: float = Vector2(egg.global_position.x - landing.global_position.x, egg.global_position.z - landing.global_position.z).length()
	_check("merah putih: beside the landing zone, standing on the ground", dist < 20.0 and dist > 5.0
		and absf(egg.global_position.y - level.get_node("Terrain").height_at(egg.global_position.x, egg.global_position.z)) < 0.05,
		"%.1f m" % dist)
	_check("merah putih: up in M1 while the route flags are hidden", egg.is_visible_in_tree() and not markers.is_visible_in_tree())

	# 2. Facing (the route flags show from M3)
	root.get_node("CampaignState").start_mission("m3")
	markers._process(0.0)
	_check("facing: the route flags are up in M3", markers.is_visible_in_tree())
	var cam: Camera3D = level.get_viewport().get_camera_3d()
	var route_pivot: Node3D = markers.get_child(0).get_node("FlagPivot")
	var worst := 0.0
	for offset in [Vector3(6.0, 1.5, 0.0), Vector3(0.0, 1.5, 6.0), Vector3(-6.0, 1.5, -2.0)]:
		for pivot in [route_pivot, egg.get_node("FlagPivot")]:
			cam.global_position = pivot.global_position + offset
			markers._process(0.0)
			worst = maxf(worst, _facing_error(pivot, cam))
	_check("facing: route and easter-egg flags turn to face the camera from any side", worst < 1.0, "worst %.2f deg" % worst)

	print("RESULT test_route_flags %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
