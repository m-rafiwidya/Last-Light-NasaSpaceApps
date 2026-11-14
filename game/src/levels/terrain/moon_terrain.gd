class_name MoonTerrain

extends Node3D

## Real lunar terrain from the terrain pipeline (tools/terrain/build_moon_terrain.py, data in
## `data_dir`, described by its terrain.json): tiers of heightmaps, finest first, aligned so each
## outer tier leaves out the cells under the inner one. The Moon level uses the Apollo 12 site: the
## play tier is the LROC NAC DTM's 2 m posts verbatim (float32), then 8 m and 64 m tiers out to
## 33 km. (The south pole site's data, moon_site01, had 16-bit tiers at 0.5 / 8 / 128 / 512 m.)
## - Collision: the play tier as one HeightMapShape3D on layer 1, built in _ready (before the first
##   physics step, so nothing falls through); rocks of 0.2 m and up as convex shapes.
## - Meshes: 64 x 64-cell chunks with automatic LODs, with skirts at each tier's outer edge;
##   triangles split like Jolt's heightfield, from (1,0) to (0,1), so what you see is what the
##   wheels stand on. Not built headless. Low-priority worker tasks only compute the arrays and
##   LODs (cached in user://, written to a temporary file and renamed, so an interrupted write
##   leaves nothing half-done); the main thread turns them into meshes, MESHES_PER_FRAME a frame.
##   The workers must not touch the RenderingServer or take every thread: Jolt runs its physics
##   jobs on the same pool, and the main thread waiting in the physics step for them while the
##   workers waited on the main thread hung the loading screen.
## - Boundary: walls on layer 7 (Boundary) at `boundary_half_size`, survey stakes every 25 m,
##   distance_to_boundary() for the HUDs, and a zone far below that brings back anything lost.
## GraphicsSettings.terrain_detail LOW turns off the regolith relief's own shadows; on a 16-bit
## play tier finer than 1 m (moon_site01) it also uses every other sample for mesh and collision.
## A measured float32 tier is never thinned: the wheels stand on the measured 2 m posts at either
## setting.
## The level waits for content_ready before the player spawns (SceneLoader).

signal content_ready

const BOUNDARY_LAYER: int = 7
## Render layer of the ground's meshes (only that layer): a local light can leave the ground out
## of its shadow casters (the workshop's bay light, under whose floor the ground can't be seen)
const RENDER_LAYER: int = 10
const CHUNK_CELLS: int = 64
## Skirt depth (m) at each tier's outer edge, hiding cracks where it meets the coarser tier
const SKIRT_DEPTH: Dictionary = {"play": 2.0, "near": 40.0, "mid": 400.0, "far": 0.0}
## Bump when the mesh building or its cache format changes
const CACHE_VERSION: int = 2
## Chunks turned into meshes per frame on the main thread
const MESHES_PER_FRAME: int = 48
const STAKE_SPACING: float = 25.0

@export_dir var data_dir: String = "res://res/terrain/moon_apollo12"
@export var material_shader: Shader = preload("res://src/levels/terrain/regolith.gdshader")
## Builds the meshes even without a display (tests of the visual mesh)
@export var build_meshes_headless: bool = false

var meta: Dictionary = {}
## Per tier: name, size, spacing, half, heights (PackedFloat32Array, row-major, rows along +Z)
var tiers: Array[Dictionary] = []
var boundary_half_size: float = 500.0
var is_content_ready: bool = false
var materials: Dictionary = {}   # tier name -> ShaderMaterial
var build_seconds: float = 0.0
## How long _ready took to read the data and build the collision (ms)
var data_ms: int = 0
var chunk_count: int = 0

var _pending_meshes: Array = []   # [tier index, chunk i, chunk j, chunk arrays (build_chunk_arrays)]
var _mutex := Mutex.new()
var _build_started: int = 0


func _ready() -> void:
	add_to_group(&"loading_content")
	add_to_group(&"play_boundary")
	var started: int = Time.get_ticks_msec()
	meta = JSON.parse_string(FileAccess.get_file_as_string(data_dir.path_join("terrain.json")))
	boundary_half_size = meta["boundary_half_size"]
	_load_tiers()
	_build_collision()
	_build_boundary()
	_build_lost_zone()
	var rocks := RockField.new()
	rocks.name = "Rocks"
	add_child(rocks)
	rocks.build(self, data_dir.path_join(meta["rocks"]["file"]), meta["rocks"]["collision_min_size"], not _visual())
	if _visual():
		_make_materials()
		rocks.set_material(materials["play"])
		_build_stakes()
		_start_meshes()
	else:
		_finish()
	data_ms = Time.get_ticks_msec() - started
	print("MoonTerrain: data and collision in %d ms" % data_ms)


func _visual() -> bool:
	return build_meshes_headless or DisplayServer.get_name() != "headless"


func is_ready_to_play() -> bool:
	return is_content_ready


# --- Data ---------------------------------------------------------------------------------------

func _load_tiers() -> void:
	var low: bool = GraphicsSettings.get_terrain_detail() == GraphicsSettings.TerrainDetail.LOW
	for t in meta["tiers"]:
		var measured: bool = t.get("format", "uint16") == "float32"
		var heights: PackedFloat32Array = _read_f32(t) if measured else _read_r16(t)
		var size: int = t["size"]
		var spacing: float = t["metres_per_pixel"]
		if low and t["name"] == "play" and not measured and spacing < 1.0:
			heights = _every_other(heights, size)
			size = (size - 1) / 2 + 1
			spacing *= 2.0
		tiers.append({"name": t["name"], "size": size, "spacing": spacing, "half": float(t["half_size"]), "heights": heights})


# A float32 tier's heights, as stored
func _read_f32(t: Dictionary) -> PackedFloat32Array:
	var heights: PackedFloat32Array = FileAccess.get_file_as_bytes(data_dir.path_join(t["file"])).to_float32_array()
	if heights.size() != t["size"] * t["size"]:
		push_error("MoonTerrain: %s has %d heights, expected %d" % [t["file"], heights.size(), t["size"] * t["size"]])
	return heights


# Decodes a tier's uint16 heights, cached as float32 in user:// after the first time
func _read_r16(t: Dictionary) -> PackedFloat32Array:
	var source: String = data_dir.path_join(t["file"])
	var cache: String = "user://terrain_cache/%s_%s_%d.f32" % [meta["name"], t["name"], hash(meta["generated"])]
	if FileAccess.file_exists(cache):
		return FileAccess.get_file_as_bytes(cache).to_float32_array()
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source)
	var count: int = t["size"] * t["size"]
	var lo: float = t["height_min"]
	var scale: float = t["height_scale"]
	var out := PackedFloat32Array()
	out.resize(count)
	var pairs: PackedInt32Array = bytes.slice(0, (count / 2) * 4).to_int32_array()
	for i in pairs.size():
		var v: int = pairs[i]
		out[2 * i] = lo + (v & 0xFFFF) * scale
		out[2 * i + 1] = lo + ((v >> 16) & 0xFFFF) * scale
	if count % 2 == 1:
		out[count - 1] = lo + bytes.decode_u16((count - 1) * 2) * scale
	DirAccess.make_dir_recursive_absolute("user://terrain_cache")
	var f := FileAccess.open(cache + ".tmp", FileAccess.WRITE)
	if f:
		f.store_buffer(out.to_byte_array())
		f.close()
		DirAccess.rename_absolute(cache + ".tmp", cache)
	return out


func _every_other(heights: PackedFloat32Array, size: int) -> PackedFloat32Array:
	var n: int = (size - 1) / 2 + 1
	var out := PackedFloat32Array()
	out.resize(n * n)
	for i in n:
		for j in n:
			out[i * n + j] = heights[(2 * i) * size + 2 * j]
	return out


## Ground height (m) at world x, z: bilinear on the finest tier that covers the point (the play
## tier's triangles may differ by a few mm from this between samples)
func height_at(x: float, z: float) -> float:
	for t in tiers:
		var half: float = t["half"]
		if absf(x) <= half and absf(z) <= half:
			var size: int = t["size"]
			var fx: float = clampf((x + half) / t["spacing"], 0.0, size - 1.001)
			var fz: float = clampf((z + half) / t["spacing"], 0.0, size - 1.001)
			var i: int = int(fz)
			var j: int = int(fx)
			var h: PackedFloat32Array = t["heights"]
			var a: float = h[i * size + j]
			var b: float = h[i * size + j + 1]
			var c: float = h[(i + 1) * size + j]
			var d: float = h[(i + 1) * size + j + 1]
			return lerpf(lerpf(a, b, fx - j), lerpf(c, d, fx - j), fz - i)
	return 0.0


## Metres from `position` to the boundary walls (negative outside)
func distance_to_boundary(position: Vector3) -> float:
	return boundary_half_size - maxf(absf(position.x), absf(position.z))


# --- Collision, boundary ------------------------------------------------------------------------

func _build_collision() -> void:
	var play: Dictionary = tiers[0]
	var body := StaticBody3D.new()
	body.name = "Ground"
	# The wheels throw dust from it (WheelDust)
	body.add_to_group(WheelDust.DUSTY_GROUP)
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var heightmap := HeightMapShape3D.new()
	heightmap.map_width = play["size"]
	heightmap.map_depth = play["size"]
	heightmap.map_data = play["heights"]
	shape.shape = heightmap
	shape.scale = Vector3(play["spacing"], 1.0, play["spacing"])
	body.add_child(shape)
	add_child(body)


func _build_boundary() -> void:
	var body := StaticBody3D.new()
	body.name = "Boundary"
	body.collision_layer = 1 << (BOUNDARY_LAYER - 1)
	body.collision_mask = 0
	var half: float = boundary_half_size
	var height: float = 4000.0
	for side in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(4.0, height, 2.0 * half + 8.0) if side.x != 0.0 else Vector3(2.0 * half + 8.0, height, 4.0)
		shape.shape = box
		shape.position = side * (half + 2.0)
		body.add_child(shape)
	add_child(body)


# Anything that gets below the terrain (it shouldn't) comes back: loose parts to the parts pile,
# rovers and the player to their spots
func _build_lost_zone() -> void:
	var area := Area3D.new()
	area.name = "LostZone"
	area.collision_layer = 0
	area.collision_mask = 0xFFFFF & ~(1 << (BOUNDARY_LAYER - 1))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000.0, 400.0, 4000.0)
	shape.shape = box
	area.add_child(shape)
	area.position = Vector3(0.0, -3000.0, 0.0)
	add_child(area)
	area.body_entered.connect(_on_lost_body)


func _on_lost_body(body: Node3D) -> void:
	var spots: Dictionary = meta["spots"]
	var spot: Array = spots["parts_pile"]
	if body is Player:
		spot = spots["player_spawn"]
	elif body is Robot:
		spot = spots["rover_parking"]
	var target := Vector3(spot[0], spot[1] + 2.0, spot[2])
	# The level's own spots win: the player's spawn, a rover's workshop dock
	var spawn := get_parent().get_node_or_null("SpawnPoint") as Node3D
	if body is Player and spawn:
		target = spawn.global_position + Vector3(0.0, 0.5, 0.0)
	elif body is Robot:
		for workshop in get_tree().get_nodes_in_group(&"workshop"):
			if workshop.rover == body:
				target = workshop.get_dock_transform().origin + Vector3(0.0, 0.3, 0.0)
	(func() -> void:
		body.global_position = target
		if body is RigidBody3D:
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
	).call_deferred()


func _build_stakes() -> void:
	var half: float = boundary_half_size
	var transforms: Array[Transform3D] = []
	var count_side: int = int(2.0 * half / STAKE_SPACING)
	for k in count_side:
		var t: float = -half + k * STAKE_SPACING
		for p in [Vector2(t, -half), Vector2(half, t), Vector2(-t, half), Vector2(-half, -t)]:
			transforms.append(Transform3D(Basis.IDENTITY, Vector3(p.x, height_at(p.x, p.y), p.y)))
	var pole := CylinderMesh.new()
	pole.top_radius = 0.025
	pole.bottom_radius = 0.025
	pole.height = 1.5
	pole.radial_segments = 6
	var pole_material := StandardMaterial3D.new()
	pole_material.albedo_color = Color(0.85, 0.85, 0.82)
	pole.material = pole_material
	var flag := BoxMesh.new()
	flag.size = Vector3(0.06, 0.25, 0.06)
	var flag_material := StandardMaterial3D.new()
	flag_material.albedo_color = Color(1.0, 0.45, 0.1)
	flag.material = flag_material
	for part in [[pole, 0.75], [flag, 1.45]]:
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = part[0]
		multimesh.instance_count = transforms.size()
		for i in transforms.size():
			multimesh.set_instance_transform(i, transforms[i].translated(Vector3(0.0, part[1], 0.0)))
		var instance := MultiMeshInstance3D.new()
		instance.name = "Stakes"
		instance.multimesh = multimesh
		add_child(instance)


# --- Materials ----------------------------------------------------------------------------------

func _make_materials() -> void:
	var horizons: Dictionary = meta["horizons"]
	var low: bool = GraphicsSettings.get_terrain_detail() == GraphicsSettings.TerrainDetail.LOW
	for t in tiers:
		var m := ShaderMaterial.new()
		m.shader = material_shader
		# Low is for weaker GPUs: no shadows from the regolith's detail relief, only its normals
		m.set_shader_parameter("detail_shadows", not low)
		var h: Dictionary = horizons["tiers"][t["name"]]
		for k in h["files"].size():
			m.set_shader_parameter("horizon_%d" % k, load(data_dir.path_join(h["files"][k])))
		m.set_shader_parameter("horizon_half", float(h["half_size"]))
		m.set_shader_parameter("horizon_size", float(h["size"]))
		m.set_shader_parameter("horizon_first_azimuth", float(horizons["first_azimuth"]))
		if t["name"] == "play" and meta.has("freshness"):
			m.set_shader_parameter("freshness", load(data_dir.path_join(meta["freshness"]["file"])))
			m.set_shader_parameter("use_freshness", true)
			m.set_shader_parameter("freshness_half", t["half"])
		# The orthophoto's brightness pattern (shading-normalised, approximate, not albedo)
		if t["name"] == "play" and meta.has("site_brightness"):
			var b: Dictionary = meta["site_brightness"]
			m.set_shader_parameter("site_brightness", load(data_dir.path_join(b["file"])))
			m.set_shader_parameter("use_site_brightness", true)
			m.set_shader_parameter("site_brightness_half", float(b["half_size"]))
			m.set_shader_parameter("site_brightness_range", float(b["range"]))
		materials[t["name"]] = m
	var sky := get_parent().get_node_or_null("WorldEnvironment") as LunarSky
	if sky:
		sky.sun_changed.connect(_update_sun.bind(sky))
		_update_sun(sky)


func _update_sun(sky: LunarSky) -> void:
	for m in materials.values():
		m.set_shader_parameter("sun_direction", sky.sun_direction())
		if sky.sun:
			m.set_shader_parameter("sun_radius", deg_to_rad(maxf(sky.sun.light_angular_distance, 0.53)) * 0.5)


# --- Meshes -------------------------------------------------------------------------------------

func _cache_dir() -> String:
	return "user://terrain_cache/%s_meshes_%d_v%d_%d" % [meta["name"], hash(meta["generated"]), CACHE_VERSION,
		GraphicsSettings.get_terrain_detail()]


func _start_meshes() -> void:
	_build_started = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(_cache_dir())
	var jobs: Array = []
	for ti in tiers.size():
		var cells: int = tiers[ti]["size"] - 1
		for ci in ceili(cells / float(CHUNK_CELLS)):
			for cj in ceili(cells / float(CHUNK_CELLS)):
				if not _chunk_fully_inside_inner(ti, ci, cj):
					jobs.append([ti, ci, cj])
	chunk_count = jobs.size()
	var task := WorkerThreadPool.add_group_task(func(k: int) -> void:
		var job: Array = jobs[k]
		var chunk: Dictionary = _load_or_build_chunk(job[0], job[1], job[2])
		_mutex.lock()
		_pending_meshes.append([job[0], job[1], job[2], chunk])
		_mutex.unlock()
	, jobs.size(), -1, false, "MoonTerrain chunks")
	_wait_for_meshes(task)


func _wait_for_meshes(task: int) -> void:
	var added: int = 0
	while added < chunk_count:
		added += _flush_meshes(MESHES_PER_FRAME)
		await get_tree().process_frame
	WorkerThreadPool.wait_for_group_task_completion(task)
	build_seconds = (Time.get_ticks_msec() - _build_started) / 1000.0
	print("MoonTerrain: %d chunks in %.1f s" % [chunk_count, build_seconds])
	_finish()


# Turns up to `limit` finished chunks into MeshInstance3Ds; returns how many were taken
func _flush_meshes(limit: int) -> int:
	_mutex.lock()
	var ready: Array = _pending_meshes.slice(0, limit)
	_pending_meshes = _pending_meshes.slice(limit)
	_mutex.unlock()
	for entry in ready:
		if entry[3].is_empty():
			continue
		var t: Dictionary = tiers[entry[0]]
		var instance := MeshInstance3D.new()
		instance.name = "%s_%d_%d" % [t["name"], entry[1], entry[2]]
		instance.mesh = mesh_from_chunk(entry[3])
		instance.material_override = materials[t["name"]]
		instance.layers = 1 << (RENDER_LAYER - 1)
		# The play area is what the wheels' dust lands on (WheelDust's collision field)
		if entry[0] == 0:
			instance.layers |= 1 << (WheelDust.GROUND_RENDER_LAYER - 1)
		# The sun's cascades only reach 500 m: beyond the near tier the horizon map shades instead
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if entry[0] <= 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
	return ready.size()


func _finish() -> void:
	is_content_ready = true
	content_ready.emit()


# Worker thread: the chunk's arrays from the cache, or built and cached. No RenderingServer here.
func _load_or_build_chunk(ti: int, ci: int, cj: int) -> Dictionary:
	var path: String = _cache_dir().path_join("%d_%d_%d.bin" % [ti, ci, cj])
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var cached = f.get_var()
			if cached is Dictionary and cached.has("arrays"):
				return cached
	var chunk: Dictionary = build_chunk_arrays(ti, ci, cj)
	var temporary: String = path + ".tmp%d" % OS.get_thread_caller_id()
	var out := FileAccess.open(temporary, FileAccess.WRITE)
	if out:
		out.store_var(chunk)
		out.close()
		DirAccess.rename_absolute(temporary, path)
	return chunk


## A chunk's mesh, with its LODs (main thread)
static func mesh_from_chunk(chunk: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, chunk["arrays"], [], chunk["lods"])
	return mesh


# Inner tier's square, in this tier's cell indices: cells fully inside it are left out
func _inner_cells(ti: int) -> Rect2i:
	if ti == 0:
		return Rect2i()
	var t: Dictionary = tiers[ti]
	var inner: float = tiers[ti - 1]["half"]
	var a: int = int(round((t["half"] - inner) / t["spacing"]))
	var b: int = int(round((t["half"] + inner) / t["spacing"]))
	return Rect2i(a, a, b - a, b - a)


func _chunk_fully_inside_inner(ti: int, ci: int, cj: int) -> bool:
	var inner: Rect2i = _inner_cells(ti)
	var chunk := Rect2i(cj * CHUNK_CELLS, ci * CHUNK_CELLS, CHUNK_CELLS, CHUNK_CELLS)
	return inner.size.x > 0 and inner.encloses(chunk)


## One chunk's mesh (rows ci, columns cj of 64 cells), with LODs, built now (main thread). For tests.
func build_chunk(ti: int, ci: int, cj: int) -> Mesh:
	var chunk: Dictionary = build_chunk_arrays(ti, ci, cj)
	return null if chunk.is_empty() else mesh_from_chunk(chunk)


## One chunk's surface arrays and LOD index arrays ({"arrays", "lods": {size: indices}}), or {} if
## it has no cells. Safe on worker threads (ImporterMesh only, no RenderingServer).
func build_chunk_arrays(ti: int, ci: int, cj: int) -> Dictionary:
	var t: Dictionary = tiers[ti]
	var size: int = t["size"]
	var spacing: float = t["spacing"]
	var half: float = t["half"]
	var h: PackedFloat32Array = t["heights"]
	var i0: int = ci * CHUNK_CELLS
	var j0: int = cj * CHUNK_CELLS
	var rows: int = mini(CHUNK_CELLS, size - 1 - i0)
	var cols: int = mini(CHUNK_CELLS, size - 1 - j0)
	if rows <= 0 or cols <= 0:
		return {}
	var inner: Rect2i = _inner_cells(ti)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var stride: int = cols + 1
	verts.resize((rows + 1) * stride)
	normals.resize((rows + 1) * stride)
	for a in rows + 1:
		var i: int = i0 + a
		for b in cols + 1:
			var j: int = j0 + b
			verts[a * stride + b] = Vector3(-half + j * spacing, h[i * size + j], -half + i * spacing)
			var hl: float = h[i * size + maxi(j - 1, 0)]
			var hr: float = h[i * size + mini(j + 1, size - 1)]
			var hu: float = h[maxi(i - 1, 0) * size + j]
			var hd: float = h[mini(i + 1, size - 1) * size + j]
			var dx: float = spacing * (mini(j + 1, size - 1) - maxi(j - 1, 0))
			var dz: float = spacing * (mini(i + 1, size - 1) - maxi(i - 1, 0))
			normals[a * stride + b] = Vector3((hl - hr) / dx, 1.0, (hu - hd) / dz).normalized()
	for a in rows:
		for b in cols:
			if inner.size.x > 0 and inner.has_point(Vector2i(j0 + b, i0 + a)):
				continue
			var p00: int = a * stride + b
			var p01: int = p00 + 1
			var p10: int = p00 + stride
			var p11: int = p10 + 1
			# Split from (1,0) to (0,1), as Jolt's heightfield
			indices.append_array([p00, p01, p10, p01, p11, p10])
	if indices.is_empty():
		return {}
	var skirt: float = SKIRT_DEPTH[t["name"]]
	if skirt > 0.0:
		_add_skirts(verts, normals, indices, rows, cols, i0, j0, size, skirt)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	importer.generate_lods(25.0, 60.0, [])
	var lods: Dictionary = {}
	for l in importer.get_surface_lod_count(0):
		lods[importer.get_surface_lod_size(0, l)] = importer.get_surface_lod_indices(0, l)
	return {"arrays": importer.get_surface_arrays(0), "lods": lods}


# Vertical strips hanging from the tier's outer edge (only on chunks at that edge)
func _add_skirts(verts: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array,
		rows: int, cols: int, i0: int, j0: int, size: int, depth: float) -> void:
	var stride: int = cols + 1
	var edges: Array = []   # [vertex indices along the edge, outward normal, reverse winding]
	if i0 == 0:
		edges.append([range(0, cols + 1), Vector3(0, 0, -1), false])
	if i0 + rows == size - 1:
		edges.append([range(rows * stride, rows * stride + cols + 1), Vector3(0, 0, 1), true])
	if j0 == 0:
		edges.append([range(0, (rows + 1) * stride, stride), Vector3(-1, 0, 0), true])
	if j0 + cols == size - 1:
		edges.append([range(cols, (rows + 1) * stride, stride), Vector3(1, 0, 0), false])
	for edge in edges:
		var top: Array = edge[0]
		var start: int = verts.size()
		for k in top:
			verts.append(verts[k] - Vector3(0.0, depth, 0.0))
			normals.append(edge[1])
		for k in top.size() - 1:
			var a: int = top[k]
			var b: int = top[k + 1]
			var c: int = start + k
			var d: int = start + k + 1
			if edge[2]:
				indices.append_array([a, c, b, b, c, d])
			else:
				indices.append_array([a, b, c, b, d, c])
