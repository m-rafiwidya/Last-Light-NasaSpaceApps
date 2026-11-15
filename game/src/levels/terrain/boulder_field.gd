class_name BoulderField

extends Node3D

## An authored boulder field (not in the DTM: its 2 m posts can't resolve boulders): `count`
## rocks of `min_size` to `max_size` m in a disc of `radius` around this node, sizes weighted to
## the small end, with gaps of at least `gap` m between them. Along the `lane` (a RouteMarkers
## route) rocks bigger than `lane_max_size` are kept `lane_half_width` m away, so the marked line
## through the field is passable and a straight line across it is not. Drawn and collided as
## RockField rocks, so they look like the pipeline's own.

@export var terrain_path: NodePath = ^"../Terrain"
@export var radius: float = 28.0
@export var count: int = 110
@export var min_size: float = 0.3
@export var max_size: float = 3.0
@export var gap: float = 1.8
@export var lane_from: NodePath = ^"../RouteMarkers"
@export var lane: String = "short"
@export var lane_half_width: float = 3.0
@export var lane_max_size: float = 0.4
@export var random_seed: int = 20261112

var rocks: RockField = null
## x, ground y, z, size, yaw, shape per rock (as rocks.f32)
var values := PackedFloat32Array()


func _ready() -> void:
	var terrain: MoonTerrain = get_node(terrain_path)
	var markers: Node = get_node_or_null(lane_from)
	var path: PackedVector2Array = markers.route(lane) if markers else PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var placed: Array[Vector3] = []   # x, z, size
	var tries: int = 0
	while placed.size() < count and tries < count * 200:
		tries += 1
		var angle: float = rng.randf() * TAU
		var p: Vector2 = Vector2(global_position.x, global_position.z) + Vector2.from_angle(angle) * radius * sqrt(rng.randf())
		var size: float = min_size + (max_size - min_size) * pow(rng.randf(), 2.5)
		if size > lane_max_size and _distance_to_path(p, path) < lane_half_width + size * 0.5:
			continue
		var clear: bool = true
		for other in placed:
			if p.distance_to(Vector2(other.x, other.y)) < (size + other.z) * 0.5 + gap:
				clear = false
				break
		if clear:
			placed.append(Vector3(p.x, p.y, size))
	for r in placed:
		values.append_array([r.x, terrain.height_at(r.x, r.y), r.y, r.z, rng.randf() * TAU, float(rng.randi() % RockField.SHAPES)])
	rocks = RockField.new()
	rocks.name = "Rocks"
	add_child(rocks)
	rocks.global_transform = Transform3D.IDENTITY
	rocks.build_values(values, 0.0, not terrain._visual())
	if terrain.materials.has("rocks"):
		rocks.set_material(terrain.materials["rocks"])


static func _distance_to_path(p: Vector2, path: PackedVector2Array) -> float:
	var best: float = INF
	for i in path.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, path[i], path[i + 1])))
	return best


func largest() -> float:
	var out: float = 0.0
	for i in values.size() / 6:
		out = maxf(out, values[i * 6 + 3])
	return out
