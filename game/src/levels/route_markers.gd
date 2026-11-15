class_name RouteMarkers

extends Node3D

## The M3 routes from the workshop apron to the far-rim logger (x, z waypoints, the logger last),
## marked by a staked flag at every waypoint but the last, and a signpost for each route near the
## apron. Authored game objects; the lines follow the DTM (see SCIENCE_AND_DATA.md).

const TITLES: Dictionary = {"short": "Short route (through Head crater)", "long": "Long route (north loop round Head)"}
const COLORS: Dictionary = {"short": Color(1.0, 0.62, 0.12), "long": Color(0.25, 0.75, 1.0)}
## Worse of the round trip at the 3.6 m/s cap and at 1.8 m/s (the pace range_estimate() assumes;
## tests/test_m3_routes.gd's driver, 14 Nov 2026), standard wheels, the logger back, plus the heater in
## the dusk shade (4.3 Wh short, 3 Wh long). Grip wheels with the thermal kit add up to GRIP_EXTRA_WH.
## energy_wh() adds SAFETY_MARGIN (+10%), so the forecast never says "enough" when it isn't.
const ENERGY_WH: Dictionary = {"short": 58.7, "long": 66.2}
const GRIP_EXTRA_WH: float = 12.0
## The heater in the nightfall shade (Wh per round trip), measured with tests/test_m3_routes.gd on the
## 70 Wh battery (15 Nov 2026): the forecast adds it to the distance when a late order puts the route in shade
const HEATER_WH: Dictionary = {"short": 7.0, "long": 11.0}
const SAFETY_MARGIN: float = 1.1
const POLE_HEIGHT: float = 2.4
const SIGN_DISTANCE: float = 18.0
## Each route's signpost stands this far to its own side of the line from the apron (short left,
## long right) and the long one is taller, so the two labels read apart from the pad and the outpost
const SIGN_SIDE: float = 4.5
const SIGN_SIDES: Dictionary = {"short": -1.0, "long": 1.0}
const SIGN_EXTRA_HEIGHT: Dictionary = {"short": 0.0, "long": 0.8}

@export var terrain_path: NodePath = ^"../Terrain"
@export var workshop_path: NodePath = ^"../Workshop"
@export var short_route: PackedVector2Array
@export var long_route: PackedVector2Array


func route(id: String) -> PackedVector2Array:
	return short_route if id == "short" else long_route


## Where both routes start: in front of the workshop's door, on the apron
## Easter egg: Indonesia's Merah Putih (red over white) on a stake beside the cargo landing zone,
## always up whatever the mission, unlike the route flags
const MERAH_PUTIH_AT := Vector2(9.0, 350.0)
const MERAH := Color(0.81, 0.07, 0.15)
const PUTIH := Color(0.96, 0.96, 0.94)

## Every flag's pivot at its pole top; _process turns them to face the camera about the pole
var _flag_pivots: Array[Node3D] = []


func start() -> Vector2:
	var workshop: Node3D = get_node_or_null(workshop_path)
	var apron: Vector3 = workshop.to_global(Vector3(1.5, 0.0, -12.0)) if workshop else Vector3.ZERO
	return Vector2(apron.x, apron.z)


static func energy_wh(id: String, grip: bool = false) -> float:
	if not ENERGY_WH.has(id):
		return 0.0
	return (float(ENERGY_WH[id]) + (GRIP_EXTRA_WH if grip else 0.0)) * SAFETY_MARGIN


## Metres from the apron to the logger and back along the waypoints
func round_trip(id: String) -> float:
	var metres: float = 0.0
	var last: Vector2 = start()
	for p in route(id):
		metres += last.distance_to(p)
		last = p
	return 2.0 * metres


func _ready() -> void:
	var terrain: MoonTerrain = get_node(terrain_path)
	add_to_group(&"route_markers")
	for id in TITLES:
		var points: PackedVector2Array = route(id)
		for i in points.size() - 1:
			add_child(_stake(terrain, points[i], [COLORS[id]], ""))
		var from: Vector2 = start()
		var along: Vector2 = (points[0] - from).normalized()
		var sign_at: Vector2 = from + along * SIGN_DISTANCE + along.orthogonal() * SIGN_SIDE * SIGN_SIDES[id]
		add_child(_stake(terrain, sign_at, [COLORS[id]], TITLES[id].to_upper(), SIGN_EXTRA_HEIGHT[id]))
	var merah_putih: Node3D = _stake(terrain, MERAH_PUTIH_AT, [MERAH, PUTIH], "")
	merah_putih.name = "MerahPutih"
	get_parent().add_child.call_deferred(merah_putih)       # outside this node, so M3's gate doesn't hide it
	_update_visibility()


## The routes are only marked from M3 (and in free play), or once the delivered cargo opens M3's
## route forecast in the console
func should_show() -> bool:
	var mission := CampaignState.current_mission()
	return mission == MissionDirector.COLD_MISSION or CampaignState.is_mission_completed(MissionDirector.COLD_MISSION) \
		or not CargoPlan.delivered_service().is_empty()


func _update_visibility() -> void:
	var show_markers: bool = should_show()
	if show_markers != visible:
		visible = show_markers


func _process(_delta: float) -> void:
	_update_visibility()
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	for pivot in _flag_pivots:
		if is_instance_valid(pivot) and pivot.is_visible_in_tree():
			var to_cam: Vector3 = cam.global_position - pivot.global_position
			pivot.rotation.y = atan2(to_cam.x, to_cam.z)


## A pole with a flag of `stripes` (colours, top to bottom) and an optional label; the caller adds it.
## Positions are world ones: this node and the level root sit at the origin.
func _stake(terrain: MoonTerrain, at: Vector2, stripes: Array, text: String, extra_height: float = 0.0) -> Node3D:
	var stake := Node3D.new()
	stake.name = "Stake"
	stake.position = Vector3(at.x, terrain.height_at(at.x, at.y), at.y)
	var color: Color = stripes[0]
	var pole := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.035
	cylinder.bottom_radius = 0.035
	cylinder.height = POLE_HEIGHT + extra_height
	cylinder.radial_segments = 6
	var pole_material := StandardMaterial3D.new()
	pole_material.albedo_color = Color(0.85, 0.85, 0.82)
	cylinder.material = pole_material
	pole.mesh = cylinder
	pole.position.y = (POLE_HEIGHT + extra_height) * 0.5
	stake.add_child(pole)
	var pivot := Node3D.new()
	pivot.name = "FlagPivot"
	pivot.position.y = POLE_HEIGHT + extra_height - 0.2
	stake.add_child(pivot)
	_flag_pivots.append(pivot)
	var stripe_height: float = 0.32 / stripes.size()
	for i in stripes.size():
		var flag := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.5, stripe_height, 0.02)
		var flag_material := StandardMaterial3D.new()
		flag_material.albedo_color = stripes[i]
		flag_material.emission_enabled = true
		flag_material.emission = stripes[i]
		flag_material.emission_energy_multiplier = 0.4
		box.material = flag_material
		flag.mesh = box
		flag.position = Vector3(0.27, 0.16 - stripe_height * (i + 0.5), 0.0)
		pivot.add_child(flag)
	if text:
		var label := Label3D.new()
		label.text = text
		label.font_size = 48
		label.pixel_size = 0.004
		label.modulate = color
		label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		label.position.y = POLE_HEIGHT + extra_height + 0.35
		stake.add_child(label)
	return stake
