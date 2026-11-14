class_name TrackLog

extends RefCounted

## Every tyre print made in one level during this run of the game: nothing erases tracks on the
## Moon, so the log only grows, and it outlives the level (for_level keeps one log per level scene
## for the session, so driving back into a level brings its tracks back). TrackMap draws its
## textures from it, so a track tile can be dropped and drawn again whenever it's needed.
##
## Points: each wheel's run of contacts with the ground, a point every TyreTracks.POINT_SPACING;
## a run starts afresh after the wheel leaves the ground. The wheels' points are interleaved, so
## each point keeps the index of its wheel's point before it: segment i joins point previous[i] to
## point i (for every i that doesn't start a run). The fine-tile index lists, per fine tile, the
## segments that can change it.

## Floats a point: x, z, s, depth, lug (TrackRaster)
const POINT_FLOATS: int = 5

static var _logs: Dictionary = {}

var points := PackedFloat32Array()
## Per point, its wheel's point before it (-1: it starts a run)
var previous := PackedInt32Array()
## Fine tile (Vector2i) -> PackedInt32Array of segment indices, in the order they were made
var tile_segments: Dictionary = {}
## Size (m) of the fine tiles the index is for
var tile_size: float = 8.0
## World position of fine tile (0, 0)'s corner
var origin := Vector2.ZERO


## The session's log for a level (by its scene file), made on first use
static func for_level(key: String, area_origin: Vector2, fine_tile: float) -> TrackLog:
	if not _logs.has(key):
		var track_log := TrackLog.new()
		track_log.origin = area_origin
		track_log.tile_size = fine_tile
		_logs[key] = track_log
	return _logs[key]


## Forgets every level's tracks (tests)
static func clear_all() -> void:
	_logs.clear()


func point_count() -> int:
	return previous.size()


func segment_count() -> int:
	return previous.size() - previous.count(-1)


## Adds a point after the wheel's point `after` (-1: it starts a run); returns its index (a
## segment's index, unless it starts a run)
func add_point(x: float, z: float, s: float, depth: float, lug: float, after: int) -> int:
	points.append_array(PackedFloat32Array([x, z, s, depth, lug]))
	previous.append(after)
	var index: int = previous.size() - 1
	if after >= 0:
		for key in tiles_of(index):
			if not tile_segments.has(key):
				tile_segments[key] = PackedInt32Array()
			tile_segments[key].append(index)
	return index


## Appends segment `index` to `out` (TrackRaster's 8 floats: the two ends' x, z, s, then the
## depth and lug, the mean of its ends')
func write_segment(index: int, out: PackedFloat32Array) -> void:
	var a: int = previous[index] * POINT_FLOATS
	var b: int = index * POINT_FLOATS
	out.append_array(PackedFloat32Array([points[a], points[a + 1], points[a + 2], points[b], points[b + 1], points[b + 2],
		0.5 * (points[a + 3] + points[b + 3]), 0.5 * (points[a + 4] + points[b + 4])]))


## The fine tiles segment `index` can change (5 cm to spare: a fine tile's margin texel and the
## texel drawn past each end, at either setting)
func tiles_of(index: int) -> Array[Vector2i]:
	var seg := PackedFloat32Array()
	write_segment(index, seg)
	var bounds: Rect2 = TrackRaster.segment_bounds(seg, 0, 0.05)
	var first := Vector2i(floori((bounds.position.x - origin.x) / tile_size), floori((bounds.position.y - origin.y) / tile_size))
	var last := Vector2i(floori((bounds.end.x - origin.x) / tile_size), floori((bounds.end.y - origin.y) / tile_size))
	var out: Array[Vector2i] = []
	for tz in range(first.y, last.y + 1):
		for tx in range(first.x, last.x + 1):
			out.append(Vector2i(tx, tz))
	return out


## Bytes the log holds (points, run flags and the tile index)
func memory_bytes() -> int:
	var total: int = points.size() * 4 + previous.size() * 4
	for key in tile_segments:
		total += tile_segments[key].size() * 4
	return total
