class_name RouteMarkers

extends Node3D

## The M3 routes from the workshop apron to the far-rim logger (x, z waypoints, the logger last),
## marked by a staked flag at every waypoint but the last, and a signpost for each route near the
## apron. Authored game objects; the lines follow the DTM (see SCIENCE_AND_DATA.md).

const TITLES: Dictionary = {"short": "Short route (through Head crater)", "long": "Long route (north loop round Head)"}
const COLORS: Dictionary = {"short": Color(1.0, 0.62, 0.12), "long": Color(0.25, 0.75, 1.0)}
const POLE_HEIGHT: float = 2.4
const SIGN_DISTANCE: float = 18.0

@export var terrain_path: NodePath = ^"../Terrain"
@export var workshop_path: NodePath = ^"../Workshop"
@export var short_route: PackedVector2Array
@export var long_route: PackedVector2Array


func route(id: String) -> PackedVector2Array:
	return short_route if id == "short" else long_route


## Where both routes start: in front of the workshop's door, on the apron
func start() -> Vector2:
	var workshop: Node3D = get_node_or_null(workshop_path)
	var apron: Vector3 = workshop.to_global(Vector3(1.5, 0.0, -12.0)) if workshop else Vector3.ZERO
	return Vector2(apron.x, apron.z)


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
			_stake(terrain, points[i], COLORS[id], "")
		var from: Vector2 = start()
		var sign_at: Vector2 = from + (points[0] - from).normalized() * SIGN_DISTANCE
		_stake(terrain, sign_at, COLORS[id], TITLES[id].to_upper())


func _stake(terrain: MoonTerrain, at: Vector2, color: Color, text: String) -> void:
	var stake := Node3D.new()
	stake.name = "Stake"
	add_child(stake)
	stake.global_position = Vector3(at.x, terrain.height_at(at.x, at.y), at.y)
	var pole := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.035
	cylinder.bottom_radius = 0.035
	cylinder.height = POLE_HEIGHT
	cylinder.radial_segments = 6
	var pole_material := StandardMaterial3D.new()
	pole_material.albedo_color = Color(0.85, 0.85, 0.82)
	cylinder.material = pole_material
	pole.mesh = cylinder
	pole.position.y = POLE_HEIGHT * 0.5
	stake.add_child(pole)
	var flag := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.32, 0.02)
	var flag_material := StandardMaterial3D.new()
	flag_material.albedo_color = color
	flag_material.emission_enabled = true
	flag_material.emission = color
	flag_material.emission_energy_multiplier = 0.4
	box.material = flag_material
	flag.mesh = box
	flag.position = Vector3(0.27, POLE_HEIGHT - 0.2, 0.0)
	stake.add_child(flag)
	if text:
		var label := Label3D.new()
		label.text = text
		label.font_size = 48
		label.pixel_size = 0.004
		label.modulate = color
		label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		label.position.y = POLE_HEIGHT + 0.35
		stake.add_child(label)
