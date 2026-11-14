class_name TrackRaster

extends RefCounted

## Draws tyre prints into track tiles: pure functions of their inputs (no nodes, no RenderingServer),
## so TrackMap runs them on a worker thread, and a tile rebuilt from the log comes out byte for byte
## as it was drawn live.
##
## A tile is a square of n x n texels covering `tile` metres plus one margin texel on each side (so
## neighbouring tiles agree at their edges and filtering never crosses into the next one): texel
## (i, j) is centred at origin + ((i - MARGIN + 0.5) * texel, (j - MARGIN + 0.5) * texel), with
## texel = tile / (n - 2 * MARGIN).
##   - Fine tiles: two bytes a texel. R the ground's height change (HEIGHT_MIN..HEIGHT_MAX, UNDISTURBED
##     where nothing drove), G how compacted it is (0 untouched, 255 a full print).
##   - Coarse tiles: one byte a texel, the share of it a print covers (far away the tracks are only
##     darker ground).
## A segment is 8 floats: x0, z0, s0, x1, z1, s1, depth, lug. s is the distance (m) along the wheel's
## own forward direction, so the grouser prints keep their place and shape however the path is cut
## into segments (and point the other way when the wheel turns the other way); depth 0..1 scales
## the print (load and slip); lug 0..1 how sharp its grouser prints are (a spinning wheel smears them).

const MARGIN: int = 1
const SEGMENT_FLOATS: int = 8
## Height change range (m) a byte covers, and the byte for untouched ground
const HEIGHT_MIN: float = -0.032
const HEIGHT_MAX: float = 0.016
const UNDISTURBED: int = 170   # round(-HEIGHT_MIN / (HEIGHT_MAX - HEIGHT_MIN) * 255)
## The print: the tread is 0.24 m wide (ROVER_KIT.md 3.1). Pressed BASE_DEPTH deep, its grousers
## LUG_DEPTH deeper, one every LUG_PITCH along the track (the decor's tread texture: 0.10 m), each a
## chevron (CHEVRON m along per m across), LUG_SHARE of the pitch wide; soil pushed out into a berm
## BERM wide and BERM_HEIGHT high on each side
const HALF_WIDTH: float = 0.12
const BASE_DEPTH: float = 0.010
const LUG_DEPTH: float = 0.008
const LUG_PITCH: float = 0.10
const LUG_SHARE: float = 0.3
const CHEVRON: float = 0.5
const BERM: float = 0.04
const BERM_HEIGHT: float = 0.004
## Half the width of the print's wall (m): from the full print to untouched ground over 2 * EDGE
const EDGE: float = 0.015


static func height_to_byte(h: float) -> int:
	return clampi(roundi((h - HEIGHT_MIN) / (HEIGHT_MAX - HEIGHT_MIN) * 255.0), 0, 255)


static func byte_to_height(b: int) -> float:
	return HEIGHT_MIN + b / 255.0 * (HEIGHT_MAX - HEIGHT_MIN)


## A fresh fine tile: untouched ground
static func blank_fine(n: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(n * n * 2)
	for k in range(0, data.size(), 2):
		data[k] = UNDISTURBED
	return data


static func blank_coarse(n: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(n * n)
	return data


## The world rectangle (x, z, width, depth) a segment can change: its ends, the print and berm
## either side, and a texel of `texel` beyond
static func segment_bounds(seg: PackedFloat32Array, k: int, texel: float) -> Rect2:
	var reach: float = HALF_WIDTH + EDGE + BERM + texel
	var x0: float = minf(seg[k], seg[k + 3]) - reach
	var z0: float = minf(seg[k + 1], seg[k + 4]) - reach
	var x1: float = maxf(seg[k], seg[k + 3]) + reach
	var z1: float = maxf(seg[k + 1], seg[k + 4]) + reach
	return Rect2(x0, z0, x1 - x0, z1 - z0)


## The texels of row z whose centres x satisfy lo <= a * x + b <= hi, intersected with [i0, i1]:
## returns [first, last] (first > last: none)
static func _span(a: float, b: float, lo: float, hi: float, x_of_0: float, texel: float, i0: int, i1: int) -> Vector2i:
	if absf(a) < 1e-9:
		return Vector2i(i0, i1) if b >= lo and b <= hi else Vector2i(1, 0)
	var xa: float = (lo - b) / a
	var xb: float = (hi - b) / a
	if xa > xb:
		var swap: float = xa
		xa = xb
		xb = swap
	return Vector2i(maxi(i0, ceili((xa - x_of_0) / texel)), mini(i1, floori((xb - x_of_0) / texel)))


## Draws segment k of `seg` into fine tile `data` (n x n, texel 0 centred at `origin`)
static func stamp_fine(data: PackedByteArray, n: int, origin: Vector2, texel: float, seg: PackedFloat32Array, k: int) -> void:
	var x0: float = seg[k]
	var z0: float = seg[k + 1]
	var dx: float = seg[k + 3] - x0
	var dz: float = seg[k + 4] - z0
	var length: float = sqrt(dx * dx + dz * dz)
	if length < 1e-5:
		return
	var ux: float = dx / length
	var uz: float = dz / length
	var s0: float = seg[k + 2]
	var ds_dt: float = (seg[k + 5] - s0) / length
	var depth: float = seg[k + 6]
	var lug: float = seg[k + 7]
	var reach: float = HALF_WIDTH + EDGE + BERM
	var ext: float = texel   # past each end, so consecutive segments leave no gap
	var j_first: int = maxi(0, ceili((minf(z0, z0 + dz) - reach - ext - origin.y) / texel))
	var j_last: int = mini(n - 1, floori((maxf(z0, z0 + dz) + reach + ext - origin.y) / texel))
	var base: float = BASE_DEPTH * depth
	var lug_depth: float = LUG_DEPTH * depth * lug
	var berm_height: float = BERM_HEIGHT * depth
	var range_scale: float = 255.0 / (HEIGHT_MAX - HEIGHT_MIN)
	for j in range(j_first, j_last + 1):
		var z: float = origin.y + j * texel
		var rz: float = z - z0
		# Along the segment: t = ux * (x - x0) + uz * rz, across: c = -uz * (x - x0) + ux * rz
		var along: Vector2i = _span(ux, -ux * x0 + uz * rz, -ext, length + ext, origin.x, texel, 0, n - 1)
		var across: Vector2i = _span(-uz, uz * x0 + ux * rz, -reach, reach, origin.x, texel, along.x, along.y)
		for i in range(across.x, across.y + 1):
			var rx: float = origin.x + i * texel - x0
			var t: float = ux * rx + uz * rz
			var c: float = absf(-uz * rx + ux * rz)
			var at: int = (j * n + i) * 2
			var old_h: float = HEIGHT_MIN + data[at] / range_scale
			var old_c: int = data[at + 1]
			if c < HALF_WIDTH + EDGE:
				# The print, its wall EDGE wide; the grousers stop short of it (they would notch it)
				var alpha: float = clampf((HALF_WIDTH + EDGE - c) / (2.0 * EDGE), 0.0, 1.0)
				var s: float = s0 + clampf(t, 0.0, length) * ds_dt
				var phase: float = fposmod((s + c * CHEVRON) / LUG_PITCH, 1.0)
				var groove: float = (smoothstep(0.0, 0.08, phase) - smoothstep(LUG_SHARE, LUG_SHARE + 0.08, phase)) \
					* smoothstep(HALF_WIDTH, HALF_WIDTH - 0.03, c)
				var h: float = -(base + lug_depth * groove)
				data[at] = clampi(roundi((lerpf(old_h, h, alpha) - HEIGHT_MIN) * range_scale), 0, 255)
				data[at + 1] = maxi(old_c, roundi(alpha * 255.0))
			elif old_c < 128:
				# The berm: loose soil pushed out beside the print (not over an older print)
				var b: float = berm_height * sin(PI * clampf((c - HALF_WIDTH - EDGE) / BERM, 0.0, 1.0))
				if b > old_h:
					data[at] = clampi(roundi((b - HEIGHT_MIN) * range_scale), 0, 255)


## Draws segment k of `seg` into coarse tile `data` (n x n): the print's coverage of each texel
static func stamp_coarse(data: PackedByteArray, n: int, origin: Vector2, texel: float, seg: PackedFloat32Array, k: int) -> void:
	var x0: float = seg[k]
	var z0: float = seg[k + 1]
	var dx: float = seg[k + 3] - x0
	var dz: float = seg[k + 4] - z0
	var length: float = sqrt(dx * dx + dz * dz)
	if length < 1e-5:
		return
	var ux: float = dx / length
	var uz: float = dz / length
	var reach: float = HALF_WIDTH + 0.5 * texel
	var ext: float = 0.5 * texel
	var j_first: int = maxi(0, ceili((minf(z0, z0 + dz) - reach - ext - origin.y) / texel))
	var j_last: int = mini(n - 1, floori((maxf(z0, z0 + dz) + reach + ext - origin.y) / texel))
	for j in range(j_first, j_last + 1):
		var rz: float = origin.y + j * texel - z0
		var along: Vector2i = _span(ux, -ux * x0 + uz * rz, -ext, length + ext, origin.x, texel, 0, n - 1)
		var across: Vector2i = _span(-uz, uz * x0 + ux * rz, -reach, reach, origin.x, texel, along.x, along.y)
		for i in range(across.x, across.y + 1):
			var rx: float = origin.x + i * texel - x0
			var c: float = absf(-uz * rx + ux * rz)
			var cover: int = roundi(clampf((HALF_WIDTH - c) / texel + 0.5, 0.0, 1.0) * 255.0)
			var at: int = j * n + i
			if cover > data[at]:
				data[at] = cover
