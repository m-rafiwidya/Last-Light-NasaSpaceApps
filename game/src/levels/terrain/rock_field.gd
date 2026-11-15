class_name RockField

extends Node3D

## The terrain pipeline's rocks (rocks.f32: x, ground y, z, size, yaw, shape per rock): six
## procedural rock shapes (noise-displaced, flattened spheres), drawn as one MultiMesh per shape,
## and rocks of `collision_min_size` and up as convex shapes on layer 1, so wheels climb them.
## Each rock is sunk a third of its height into the ground.

const SHAPES: int = 6
const FLATTEN: float = 0.6

var meshes: Array[ArrayMesh] = []
var count: int = 0
var with_collision: int = 0
var _instances: Array[MultiMeshInstance3D] = []


## `data`: path of rocks.f32. `collision_only`: no visuals (headless)
func build(terrain: Node3D, data: String, collision_min_size: float, collision_only: bool) -> void:
	build_values(FileAccess.get_file_as_bytes(data).to_float32_array(), collision_min_size, collision_only)


## `values`: six floats per rock, as in rocks.f32
func build_values(values: PackedFloat32Array, collision_min_size: float, collision_only: bool) -> void:
	count = values.size() / 6
	for s in SHAPES:
		meshes.append(_rock_mesh(s))
	var per_shape: Array = []
	per_shape.resize(SHAPES)
	for s in SHAPES:
		per_shape[s] = []
	var body := StaticBody3D.new()
	body.name = "RockCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var shapes: Array[ConvexPolygonShape3D] = []
	for s in SHAPES:
		var convex := ConvexPolygonShape3D.new()
		convex.points = meshes[s].surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		shapes.append(convex)
	for r in count:
		var size: float = values[r * 6 + 3]
		var shape_index: int = int(values[r * 6 + 5]) % SHAPES
		var basis := Basis(Vector3.UP, values[r * 6 + 4]).scaled(Vector3.ONE * size)
		var origin := Vector3(values[r * 6], values[r * 6 + 1] + size * FLATTEN * 0.5 * (1.0 - 2.0 / 3.0), values[r * 6 + 2])
		var transform := Transform3D(basis, origin)
		per_shape[shape_index].append(transform)
		if size >= collision_min_size:
			var shape := CollisionShape3D.new()
			shape.shape = shapes[shape_index]
			shape.transform = transform
			body.add_child(shape)
			with_collision += 1
	add_child(body)
	if collision_only:
		return
	for s in SHAPES:
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = meshes[s]
		multimesh.instance_count = per_shape[s].size()
		for i in per_shape[s].size():
			multimesh.set_instance_transform(i, per_shape[s][i])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		# Small things: no need to draw them far away
		instance.visibility_range_end = 250.0
		# Part of the ground: on its render layer (MoonTerrain.RENDER_LAYER)
		instance.layers = 1 << (MoonTerrain.RENDER_LAYER - 1)
		add_child(instance)
		_instances.append(instance)


func set_material(material: Material) -> void:
	for instance in _instances:
		instance.material_override = material


# A unit-sized rock (about 1 m across, FLATTEN as tall): an icosphere pushed in and out by noise
func _rock_mesh(seed_value: int) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = 7919 * (seed_value + 1)
	noise.frequency = 1.6
	noise.fractal_octaves = 3
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var arrays: Array = sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var v: Vector3 = verts[i]
		var bump: float = 1.0 + 0.35 * noise.get_noise_3dv(v * 2.0)
		verts[i] = Vector3(v.x * bump, v.y * bump * FLATTEN, v.z * bump)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = null
	arrays[Mesh.ARRAY_TANGENT] = null
	var tool := SurfaceTool.new()
	tool.create_from_arrays(arrays)
	tool.generate_normals()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tool.commit_to_arrays())
	return mesh
