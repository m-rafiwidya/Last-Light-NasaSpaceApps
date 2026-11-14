class_name TrackMap

extends RefCounted

## The textures the ground draws its tyre tracks from (tyre_tracks.gdshaderinc), drawn from a
## TrackLog by TrackRaster:
##   - fine: tiles of fine_tile metres (fine_n texels a side with margins) of height change and
##     compaction, only those with tracks near the camera (within `radius`), at most fine_cap at
##     once (a Texture2DArray) with a page table (which layer holds which tile); a tile that goes
##     out of range is dropped and drawn again from the log when it's needed again;
##   - coarse: the whole area in tiles of COARSE_TILE metres of print coverage, always all there
##     (a mipmapped Texture2DArray): the tracks as darker ground far away.
## Drawing runs on a worker thread, one job at a time (low priority: Jolt runs its physics jobs on
## the same pool, and the workers never touch the RenderingServer); the main thread hands out the
## work and uploads what changed. A segment is drawn into a tile in the order the log made them,
## live or when a tile is drawn again, so a tile comes out the same either way.

const FINE_TILE: float = 8.0
const COARSE_TILE: float = 64.0
## Most segments a job draws into the coarse tiles (the rest wait for the next job)
const COARSE_SEGMENTS_PER_JOB: int = 4000
## Uploads at most this often (s): the prints appear under the wheels that hide them anyway
const FINE_UPLOAD_INTERVAL: float = 1.0 / 30.0
const COARSE_UPLOAD_INTERVAL: float = 0.25

var track_log: TrackLog
var area: Rect2
var fine_n: int
var fine_cap: int
var coarse_n: int
## Fine tiles are kept within this distance (m) of the camera
var radius: float
var fine_texel: float
var coarse_texel: float
var pages_per_side: int
var coarse_per_side: int

## Fine tile (Vector2i) -> {"layer": int, "ready": bool, "pending": PackedInt32Array}
var tiles: Dictionary = {}
## Per fine layer: the tile it holds (or null) and its texels
var layer_tile: Array = []
var fine_data: Array[PackedByteArray] = []
var coarse_data: Array[PackedByteArray] = []
var coarse_pending := PackedInt32Array()
## Fine tiles drawn from the log (each time one comes into range; read by tests)
var rebuilds: int = 0

var fine_texture: Texture2DArray
var coarse_texture: Texture2DArray
var page_texture: ImageTexture
var _page_image: Image
var _gpu: bool = false
var _job: Dictionary = {}
# The fine tiles in the running job (the main thread's own copy: the job's dictionary belongs to the
# worker until it finishes)
var _job_keys: Dictionary = {}
var _job_task: int = -1
var _fine_dirty: Dictionary = {}
var _coarse_dirty: Dictionary = {}
var _pages_dirty: bool = false
var _fine_upload_at: float = 0.0
var _coarse_upload_at: float = 0.0
var _blank_fine: PackedByteArray


## `gpu`: make and upload the textures (not headless)
func _init(log_: TrackLog, area_: Rect2, fine_n_: int, fine_cap_: int, coarse_n_: int, radius_: float, gpu: bool) -> void:
	track_log = log_
	area = area_
	fine_n = fine_n_
	fine_cap = fine_cap_
	coarse_n = coarse_n_
	radius = radius_
	_gpu = gpu
	fine_texel = FINE_TILE / float(fine_n - 2 * TrackRaster.MARGIN)
	coarse_texel = COARSE_TILE / float(coarse_n - 2 * TrackRaster.MARGIN)
	pages_per_side = ceili(area.size.x / FINE_TILE)
	coarse_per_side = ceili(area.size.x / COARSE_TILE)
	_blank_fine = TrackRaster.blank_fine(fine_n)
	for i in fine_cap:
		layer_tile.append(null)
		fine_data.append(_blank_fine)
	for i in coarse_per_side * coarse_per_side:
		coarse_data.append(TrackRaster.blank_coarse(coarse_n))
	_page_image = Image.create_empty(pages_per_side, pages_per_side, false, Image.FORMAT_R8)
	if _gpu:
		_make_textures()
	# Tracks already in the log (the level loaded again): the coarse map from all of them
	for i in track_log.previous.size():
		if track_log.previous[i] >= 0:
			coarse_pending.append(i)


func _make_textures() -> void:
	var fine_images: Array[Image] = []
	for i in fine_cap:
		fine_images.append(Image.create_from_data(fine_n, fine_n, false, Image.FORMAT_RG8, fine_data[i]))
	fine_texture = Texture2DArray.new()
	fine_texture.create_from_images(fine_images)
	var coarse_images: Array[Image] = []
	for data in coarse_data:
		coarse_images.append(_coarse_image(data))
	coarse_texture = Texture2DArray.new()
	coarse_texture.create_from_images(coarse_images)
	page_texture = ImageTexture.create_from_image(_page_image)


func _coarse_image(data: PackedByteArray) -> Image:
	var image := Image.create_from_data(coarse_n, coarse_n, false, Image.FORMAT_R8, data)
	image.generate_mipmaps()
	return image


## Video memory the textures take (bytes, mipmaps included)
func texture_bytes() -> int:
	var coarse_mips: float = 4.0 / 3.0
	return fine_cap * fine_n * fine_n * 2 + int(coarse_data.size() * coarse_n * coarse_n * coarse_mips) + pages_per_side * pages_per_side


## Fine tile at a world position (x, z)
func tile_at(x: float, z: float) -> Vector2i:
	return Vector2i(floori((x - area.position.x) / FINE_TILE), floori((z - area.position.y) / FINE_TILE))


## World position of a fine tile's texel 0 centre
func fine_origin(key: Vector2i) -> Vector2:
	var corner: Vector2 = area.position + Vector2(key) * FINE_TILE
	return corner - Vector2.ONE * (TrackRaster.MARGIN - 0.5) * fine_texel


func coarse_origin(layer: int) -> Vector2:
	var key := Vector2i(layer % coarse_per_side, layer / coarse_per_side)
	var corner: Vector2 = area.position + Vector2(key) * COARSE_TILE
	return corner - Vector2.ONE * (TrackRaster.MARGIN - 0.5) * coarse_texel


## A new segment in the log: drawn into the fine tiles held now (or being drawn) and the coarse map
func on_segment(index: int) -> void:
	for key in track_log.tiles_of(index):
		if tiles.has(key):
			tiles[key]["pending"].append(index)
	coarse_pending.append(index)


## Keeps the fine tiles with tracks within `radius` of `focus` (x, z), nearest first, dropping the
## farthest others when out of layers
func update_residency(focus: Vector2) -> void:
	var wanted: Array = []
	var reach: float = radius + FINE_TILE * 0.71
	for key in track_log.tile_segments:
		var centre: Vector2 = area.position + (Vector2(key) + Vector2(0.5, 0.5)) * FINE_TILE
		var d: float = centre.distance_to(focus)
		if d < reach:
			wanted.append([d, key])
	wanted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var wanted_keys: Dictionary = {}
	for w in wanted:
		wanted_keys[w[1]] = true
	for w in wanted:
		var key: Vector2i = w[1]
		if tiles.has(key):
			continue
		var layer: int = layer_tile.find(null)
		if layer < 0:
			layer = _evictable_layer(wanted_keys, focus)
			if layer < 0:
				break
		layer_tile[layer] = key
		tiles[key] = {"layer": layer, "ready": false, "pending": PackedInt32Array()}


# The held tile farthest from `focus` that isn't wanted, isn't being drawn and isn't in a job
func _evictable_layer(wanted_keys: Dictionary, focus: Vector2) -> int:
	var best: int = -1
	var best_d: float = -1.0
	for layer in fine_cap:
		var key = layer_tile[layer]
		if key == null or wanted_keys.has(key) or not tiles[key]["ready"] or _in_job(key):
			continue
		var d: float = (area.position + (Vector2(key) + Vector2(0.5, 0.5)) * FINE_TILE).distance_to(focus)
		if d > best_d:
			best_d = d
			best = layer
	if best >= 0:
		_set_page(layer_tile[best], 0)
		tiles.erase(layer_tile[best])
		layer_tile[best] = null
		fine_data[best] = _blank_fine
	return best


func _in_job(key: Vector2i) -> bool:
	return _job_keys.has(key)


# The page table's entry for a fine tile: its layer + 1, 0 for none
func _set_page(key: Vector2i, value: int) -> void:
	if key.x >= 0 and key.y >= 0 and key.x < pages_per_side and key.y < pages_per_side:
		_page_image.set_pixel(key.x, key.y, Color8(value, 0, 0))
		_pages_dirty = true


## Hands out work and takes in finished work; call every frame
func process(now: float) -> void:
	if _job_task >= 0 and WorkerThreadPool.is_task_completed(_job_task):
		WorkerThreadPool.wait_for_task_completion(_job_task)
		_job_task = -1
		_finish_job()
	if _job_task < 0:
		_start_job()
	if _gpu:
		_upload(now)


## Finishes all the work there is (tests, and before reading the tiles)
func flush() -> void:
	while true:
		if _job_task >= 0:
			WorkerThreadPool.wait_for_task_completion(_job_task)
			_job_task = -1
			_finish_job()
		if not _start_job():
			break
	if _gpu:
		_upload(INF)


func busy() -> bool:
	return _job_task >= 0


# Gathers pending work into a job and starts it on a worker; false if there was none
func _start_job() -> bool:
	var fine_tasks: Array = []
	var rebuilt: bool = false
	for key in tiles:
		var tile: Dictionary = tiles[key]
		var segs := PackedFloat32Array()
		var data: PackedByteArray
		if not tile["ready"]:
			if rebuilt:
				continue
			# Drawn again from the log: every segment it has so far, oldest first; later ones wait
			# in pending
			rebuilt = true
			data = _blank_fine
			for index in track_log.tile_segments.get(key, PackedInt32Array()):
				track_log.write_segment(index, segs)
			tile["pending"] = PackedInt32Array()
		else:
			if tile["pending"].is_empty():
				continue
			data = fine_data[tile["layer"]]
			for index in tile["pending"]:
				track_log.write_segment(index, segs)
			tile["pending"] = PackedInt32Array()
		fine_tasks.append({"key": key, "layer": tile["layer"], "data": data, "segs": segs,
			"origin": fine_origin(key), "rebuild": not tile["ready"]})
	var coarse_segs := PackedFloat32Array()
	var take: int = mini(coarse_pending.size(), COARSE_SEGMENTS_PER_JOB)
	for k in take:
		track_log.write_segment(coarse_pending[k], coarse_segs)
	coarse_pending = coarse_pending.slice(take)
	if fine_tasks.is_empty() and coarse_segs.is_empty():
		return false
	_job_keys.clear()
	for task in fine_tasks:
		_job_keys[task["key"]] = true
	_job = {"fine": fine_tasks, "coarse_segs": coarse_segs, "coarse": coarse_data.duplicate(), "coarse_changed": {},
		"fine_n": fine_n, "fine_texel": fine_texel, "coarse_n": coarse_n, "coarse_texel": coarse_texel,
		"area": area, "coarse_per_side": coarse_per_side}
	_job_task = WorkerThreadPool.add_task(_run_job.bind(_job), false, "TyreTracks")
	return true


# On the worker: draws the job's segments into its own copies of the tiles (packed arrays are
# shared, not copied, when passed or assigned: drawing into the main thread's would change tiles it
# is uploading, and drawing into the blank tile every tile starts from)
static func _run_job(job: Dictionary) -> void:
	for task in job["fine"]:
		var data: PackedByteArray = task["data"].duplicate()
		var segs: PackedFloat32Array = task["segs"]
		for k in range(0, segs.size(), TrackRaster.SEGMENT_FLOATS):
			TrackRaster.stamp_fine(data, job["fine_n"], task["origin"], job["fine_texel"], segs, k)
		task["data"] = data
	var segs: PackedFloat32Array = job["coarse_segs"]
	var per_side: int = job["coarse_per_side"]
	var a: Rect2 = job["area"]
	var texel: float = job["coarse_texel"]
	var coarse: Array = job["coarse"]
	var changed: Dictionary = job["coarse_changed"]
	for k in range(0, segs.size(), TrackRaster.SEGMENT_FLOATS):
		var bounds: Rect2 = TrackRaster.segment_bounds(segs, k, texel)
		var first := Vector2i(floori((bounds.position.x - a.position.x) / COARSE_TILE), floori((bounds.position.y - a.position.y) / COARSE_TILE))
		var last := Vector2i(floori((bounds.end.x - a.position.x) / COARSE_TILE), floori((bounds.end.y - a.position.y) / COARSE_TILE))
		for tz in range(maxi(first.y, 0), mini(last.y, per_side - 1) + 1):
			for tx in range(maxi(first.x, 0), mini(last.x, per_side - 1) + 1):
				var layer: int = tz * per_side + tx
				if not changed.has(layer):
					coarse[layer] = coarse[layer].duplicate()
					changed[layer] = true
				var corner: Vector2 = a.position + Vector2(tx, tz) * COARSE_TILE
				var origin: Vector2 = corner - Vector2.ONE * (TrackRaster.MARGIN - 0.5) * texel
				TrackRaster.stamp_coarse(coarse[layer], job["coarse_n"], origin, texel, segs, k)


# On the main thread: takes the job's results
func _finish_job() -> void:
	for task in _job["fine"]:
		var key: Vector2i = task["key"]
		if not tiles.has(key) or tiles[key]["layer"] != task["layer"]:
			continue   # dropped meanwhile
		fine_data[task["layer"]] = task["data"]
		_fine_dirty[task["layer"]] = true
		if task["rebuild"]:
			tiles[key]["ready"] = true
			rebuilds += 1
			_set_page(key, task["layer"] + 1)
	for layer in _job["coarse_changed"]:
		coarse_data[layer] = _job["coarse"][layer]
		_coarse_dirty[layer] = true
	_job = {}
	_job_keys.clear()


func _upload(now: float) -> void:
	if _pages_dirty:
		page_texture.update(_page_image)
		_pages_dirty = false
	if not _fine_dirty.is_empty() and now >= _fine_upload_at:
		for layer in _fine_dirty:
			fine_texture.update_layer(Image.create_from_data(fine_n, fine_n, false, Image.FORMAT_RG8, fine_data[layer]), layer)
		_fine_dirty.clear()
		_fine_upload_at = now + FINE_UPLOAD_INTERVAL
	if not _coarse_dirty.is_empty() and now >= _coarse_upload_at:
		for layer in _coarse_dirty:
			coarse_texture.update_layer(_coarse_image(coarse_data[layer]), layer)
		_coarse_dirty.clear()
		_coarse_upload_at = now + COARSE_UPLOAD_INTERVAL


## Fine texel bytes (R height, G compaction) at world (x, z), or [] if that tile isn't drawn (tests)
func fine_texel_at(x: float, z: float) -> PackedByteArray:
	var key: Vector2i = tile_at(x, z)
	if not tiles.has(key) or not tiles[key]["ready"]:
		return PackedByteArray()
	var o: Vector2 = fine_origin(key)
	var i: int = roundi((x - o.x) / fine_texel)
	var j: int = roundi((z - o.y) / fine_texel)
	var at: int = (j * fine_n + i) * 2
	var data: PackedByteArray = fine_data[tiles[key]["layer"]]
	return data.slice(at, at + 2)


## Coarse coverage byte at world (x, z)
func coarse_at(x: float, z: float) -> int:
	var tx: int = floori((x - area.position.x) / COARSE_TILE)
	var tz: int = floori((z - area.position.y) / COARSE_TILE)
	if tx < 0 or tz < 0 or tx >= coarse_per_side or tz >= coarse_per_side:
		return 0
	var layer: int = tz * coarse_per_side + tx
	var o: Vector2 = coarse_origin(layer)
	var i: int = roundi((x - o.x) / coarse_texel)
	var j: int = roundi((z - o.y) / coarse_texel)
	return coarse_data[layer][j * coarse_n + i]
