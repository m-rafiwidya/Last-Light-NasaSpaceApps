#!/usr/bin/env python3
"""Builds the Moon level's terrain from NASA elevation data (see MOON_TERRAIN.md).

    python3 tools/terrain/build_moon_terrain.py [--fetch] [config.json]

Run from the repo root. Needs numpy, scipy and Pillow (no GDAL). Two kinds of site, chosen by the
settings file's `site_type`:
  - "polar_stereographic" (moon_site01.json, the default): LOLA 5 m south pole site DEM, PDS polar
    mosaics for the ring, the sun chosen to keep a permanently shadowed crater dark;
  - "equirectangular" (moon_apollo12.json): an LROC NAC DTM, its play tier taken verbatim (2 m posts,
    float32, minus one constant), SLDEM2015 for the ring, the sun, Earth and the star map's
    orientation from JPL Horizons at one moment.
Steps:
  1. --fetch: downloads the sources into the raw folder (gitignored), resumable, only the rows
     needed of a big mosaic (`range`); every run checks their byte counts and georeferencing.
  2. Exact conversion to game metres: for each output sample (X east-ish, Z south-ish, metres along
     the local tangent plane at the play centre) finds the surface point that projects there, so
     X / Z are true distances and Y includes the Moon's curvature. A verbatim play tier skips this:
     its posts go at (spacing * column, height - constant, spacing * row).
  3. Tiers aligned so each outer tier's cells under the inner tier can be dropped exactly. Outer
     tiers from coarser mosaics are shifted to match the site data where they overlap (the offset is
     reported and checked).
  4. Detail on the play tier (each part switchable): fractal roughness and small craters below the
     data's resolution, rocks (instances, not in the heightmap), protected areas graded flat. What
     changes the measured ground is listed in terrain.json's `authored_changes`.
  5. Horizon maps (16 azimuths) per tier for shadows beyond the sun's shadow cascades; the sun and
     Earth (chosen, or from the ephemeris).
  6. Outputs: heightmaps (.r16, or .f32 for a verbatim tier), horizon PNGs, rocks, a freshness or
     site brightness map, terrain.json (with `provenance`), previews.
"""

import json
import math
import os
import sys
import time
import urllib.request
import zlib
import hashlib

import numpy as np
from PIL import Image
from scipy import ndimage

Image.MAX_IMAGE_PIXELS = None
# numpy's matmul on macOS (Accelerate) reports divide-by-zero / overflow for ordinary finite inputs;
# results are checked for finiteness instead
np.seterr(divide="ignore", over="ignore", invalid="ignore")
R_MOON = 1737400.0
AZIMUTHS = 16
HORIZON_MIN, HORIZON_RANGE = -10.0, 60.0   # degrees encoded 0..255


def log(*args):
	print(time.strftime("%H:%M:%S"), *args, flush=True)


# --- Sources ----------------------------------------------------------------------------------

def source_path(cfg, src):
	"""A source's file in the raw folder: `file` if given (a byte range of a bigger file), else the
	URL's name."""
	return os.path.join(cfg["raw_dir"], src.get("file", os.path.basename(src["url"])))


def fetch(cfg):
	raw = cfg["raw_dir"]
	os.makedirs(raw, exist_ok=True)
	for key, src in cfg["sources"].items():
		path = source_path(cfg, src)
		have = os.path.getsize(path) if os.path.exists(path) else 0
		if have == src["bytes"]:
			continue
		if src["bytes"] > 1_000_000_000:
			sys.exit(f"{key}: {src['bytes']} bytes is over 1 GB; download it by hand after checking")
		# `range`: only bytes [start, end) of the file at the URL (rows of a big mosaic)
		start = src["range"][0] if "range" in src else 0
		headers = {"Range": f"bytes={start + have}-{start + src['bytes'] - 1}"} if have or "range" in src else {}
		log(f"fetching {src['url']} ({have} of {src['bytes']} bytes{', a byte range' if 'range' in src else ''})")
		request = urllib.request.Request(src["url"], headers=headers)
		with urllib.request.urlopen(request, timeout=120) as response, open(path, "ab" if have else "wb") as out:
			if headers and response.status != 206:
				sys.exit(f"{key}: the server ignored the byte range (HTTP {response.status})")
			while chunk := response.read(1 << 20):
				out.write(chunk)
		if "label_url" in src:
			label = path + ".lbl"
			if not os.path.exists(label):
				urllib.request.urlretrieve(src["label_url"], label)


def check_sources(cfg):
	report = {}
	for key, src in cfg["sources"].items():
		path = source_path(cfg, src)
		if not os.path.exists(path):
			sys.exit(f"missing {path}: run with --fetch")
		size = os.path.getsize(path)
		if size != src["bytes"]:
			sys.exit(f"{path}: {size} bytes, expected {src['bytes']}")
		digest = hashlib.sha256()
		with open(path, "rb") as f:
			while chunk := f.read(1 << 22):
				digest.update(chunk)
		report[key] = {"file": os.path.basename(path), "bytes": size, "sha256": digest.hexdigest(), "url": src["url"], "credit": src["credit"]}
		if "range" in src:
			report[key]["byte_range"] = src["range"]
	return report


# --- PDS3 images (LROC NAC DTMs and orthophotos, SLDEM2015) -------------------------------------

def pds3_label(text):
	"""Keyword = value pairs of a PDS3 label (the first value wins for keys repeated in objects,
	units like <KM> dropped)."""
	keys = {}
	for line in text.split("\n"):
		if line.strip() == "END":
			break
		if "=" in line and not line.lstrip().startswith("/*"):
			k, v = line.split("=", 1)
			k = k.strip()
			v = v.split("/*")[0].strip().strip('"')
			if "<" in v:
				v = v.split("<")[0].strip()
			keys.setdefault(k, v)
	return keys


def read_pds3(path, label_path=None):
	"""(label keys, image array) of a PDS3 IMG with an attached label (or `label_path`'s detached
	one, the image then at the start of the file)."""
	with open(label_path or path, "rb") as f:
		head = f.read(65536).decode("latin1")
	keys = pds3_label(head)
	lines, samples = int(keys["LINES"]), int(keys["LINE_SAMPLES"])
	types = {("PC_REAL", "32"): "<f4", ("LSB_INTEGER", "16"): "<i2", ("MSB_UNSIGNED_INTEGER", "8"): "u1"}
	dtype = types[(keys["SAMPLE_TYPE"], keys["SAMPLE_BITS"])]
	offset = 0 if label_path else (int(keys["^IMAGE"].split()[0]) - 1) * int(keys["RECORD_BYTES"])
	data = np.fromfile(path, dtype, count=lines * samples, offset=offset)
	if data.size != lines * samples:
		sys.exit(f"{path}: {data.size} samples, the label says {lines} x {samples}")
	return keys, data.reshape(lines, samples)


class LrocDTM:
	"""LROC NAC DTM (PDS3, float32 metres above the 1737.4 km sphere, equirectangular). Posts are
	pixel centres; line l, sample s (0-based) is at x = (s - SAMPLE_PROJECTION_OFFSET) * scale,
	y = (LINE_PROJECTION_OFFSET - l) * scale from the projection centre."""

	def __init__(self, path):
		keys, z = read_pds3(path)
		if keys["MAP_PROJECTION_TYPE"] != "EQUIRECTANGULAR" or abs(float(keys["A_AXIS_RADIUS"]) * 1000.0 - R_MOON) > 1e-6:
			sys.exit(f"{path}: unexpected projection {keys['MAP_PROJECTION_TYPE']}, radius {keys['A_AXIS_RADIUS']} km")
		self.keys = keys
		self.scale = float(keys["MAP_SCALE"])
		self.loff, self.soff = float(keys["LINE_PROJECTION_OFFSET"]), float(keys["SAMPLE_PROJECTION_OFFSET"])
		self.clat, self.clon = float(keys["CENTER_LATITUDE"]), float(keys["CENTER_LONGITUDE"])
		self.coslat = math.cos(math.radians(self.clat))
		self.raw = z
		self.valid = np.isfinite(z) & (z > -1e30)
		self.z = np.where(self.valid, z, np.nan).astype(np.float64)
		# No-data filled from the nearest post, for smoothing and interpolation only
		idx = ndimage.distance_transform_edt(~self.valid, return_distances=False, return_indices=True)
		self.filled = self.z[tuple(idx)]
		# Weight for blending with a coarser DEM: 1 more than `feather` metres inside the data
		self.inside_m = ndimage.distance_transform_edt(np.pad(self.valid, 1)) [1:-1, 1:-1] * self.scale
		self._coeffs = {}
		self.lines, self.samples = z.shape

	def pixel(self, lon, lat):
		"""(line, sample) of a longitude / latitude (degrees)"""
		s = self.soff + np.radians(lon - self.clon) * R_MOON * self.coslat / self.scale
		l = self.loff - np.radians(lat) * R_MOON / self.scale
		return l, s

	def lon_lat(self, l, s):
		lon = self.clon + np.degrees((s - self.soff) * self.scale / (R_MOON * self.coslat))
		lat = np.degrees((self.loff - l) * self.scale / R_MOON)
		return lon, lat

	def sample(self, lon, lat, smooth_px=0.0):
		key = round(smooth_px, 3)
		if key not in self._coeffs:
			data = self.filled if smooth_px < 0.5 else ndimage.gaussian_filter(self.filled, smooth_px)
			self._coeffs[key] = ndimage.spline_filter(data, order=3)
		l, s = self.pixel(lon, lat)
		return ndimage.map_coordinates(self._coeffs[key], [l, s], order=3, mode="nearest", prefilter=False)

	def weight(self, lon, lat, feather):
		l, s = self.pixel(lon, lat)
		d = ndimage.map_coordinates(self.inside_m, [l, s], order=1, mode="constant", cval=0.0)
		t = np.clip((d - self.scale) / feather, 0.0, 1.0)
		return t * t * (3.0 - 2.0 * t)


class SldemBand:
	"""Rows `rows` of an SLDEM2015 tile (float32 km above 1737.4 km, simple cylindrical, `res`
	pixels per degree), as downloaded by a byte range, cropped to the longitudes needed."""

	def __init__(self, path, src, lon_range, smooth_px):
		keys = pds3_label(open(path + ".lbl", encoding="latin1").read())
		res = float(keys["MAP_RESOLUTION"])
		samples = int(keys["LINE_SAMPLES"])
		if keys["SAMPLE_TYPE"] != "PC_REAL" or keys["SAMPLE_BITS"] != "32" or abs(float(keys["OFFSET"]) * 1000.0 - R_MOON) > 1e-6:
			sys.exit(f"{path}: unexpected SLDEM2015 format")
		r0, r1 = src["rows"]
		if src["range"] != [r0 * samples * 4, r1 * samples * 4]:
			sys.exit(f"{path}: byte range doesn't match rows {r0}-{r1}")
		self.res, self.r0 = res, r0
		self.loff, self.soff = float(keys["LINE_PROJECTION_OFFSET"]), float(keys["SAMPLE_PROJECTION_OFFSET"])
		self.clat, self.clon = float(keys["CENTER_LATITUDE"]), float(keys["CENTER_LONGITUDE"])
		c0 = max(int(self.soff + (lon_range[0] - self.clon) * res), 0)
		c1 = min(int(self.soff + (lon_range[1] - self.clon) * res) + 2, samples)
		band = np.fromfile(path, "<f4").reshape(r1 - r0, samples)[:, c0:c1].astype(np.float64) * 1000.0
		if not np.isfinite(band).all() or np.abs(band).max() > 20000.0:
			sys.exit(f"{path}: bad values")
		self.c0 = c0
		self.z = ndimage.gaussian_filter(band, smooth_px) if smooth_px > 0.5 else band
		self.shift = 0.0
		self.metres_per_pixel = math.radians(1.0 / res) * R_MOON

	def sample(self, lon, lat):
		l = self.loff - (lat - self.clat) * self.res - self.r0
		s = self.soff + (lon - self.clon) * self.res - self.c0
		if l.min() < 0 or l.max() > self.z.shape[0] - 1:
			sys.exit("SLDEM2015 band: a point outside the downloaded rows")
		return ndimage.map_coordinates(self.z, [l, s], order=1, mode="nearest") + self.shift

	def calibrate(self, dtm, label):
		"""Mean offset and RMS difference to the DTM (smoothed to this mosaic's resolution)."""
		rng = np.random.default_rng(1)
		l = rng.uniform(0, dtm.lines - 1, 40000)
		s = rng.uniform(0, dtm.samples - 1, 40000)
		keep = dtm.inside_m[l.astype(int), s.astype(int)] > 300.0
		lon, lat = dtm.lon_lat(l[keep], s[keep])
		truth = dtm.sample(lon, lat, smooth_px=self.metres_per_pixel / dtm.scale / 2.0)
		self.shift = 0.0
		diff = truth - self.sample(lon, lat)
		self.shift = float(diff.mean())
		rms = float(np.sqrt(np.mean((diff - self.shift) ** 2)))
		log(f"{label}: offset to the DTM {self.shift:+.2f} m, RMS difference {rms:.2f} m over {keep.sum()} points")
		if rms > 15.0 or abs(self.shift) > 50.0:
			sys.exit(f"{label} doesn't match the DTM (RMS {rms:.1f} m, offset {self.shift:.1f} m)")
		return {"offset_to_dtm_m": round(self.shift, 3), "rms_difference_m": round(rms, 3), "points": int(keep.sum())}


class SiteDEM:
	"""PGDA 5 m GeoTIFF: float32, polar stereographic on the 1737.4 km sphere, pixel-registered."""

	def __init__(self, path):
		im = Image.open(path)
		tags = im.tag_v2
		geo = tags[34736]
		if abs(geo[0] + 90.0) > 1e-9 or abs(geo[5] - R_MOON) > 1e-6 or abs(geo[6] - R_MOON) > 1e-6:
			sys.exit(f"{path}: unexpected projection {geo}")
		self.px = tags[33550][0]
		self.x0, self.y0 = tags[33922][3], tags[33922][4]   # top-left corner
		self.z = np.asarray(im, dtype=np.float64)
		if not np.isfinite(self.z).all():
			sys.exit(f"{path}: holes in the data")
		self.coeffs = ndimage.spline_filter(self.z, order=3)
		self.n = self.z.shape[0]

	def extent(self):
		return self.x0, self.x0 + self.n * self.px, self.y0 - self.n * self.px, self.y0

	def sample(self, x, y, smooth=None):
		cols = (x - self.x0) / self.px - 0.5
		rows = (self.y0 - y) / self.px - 0.5
		data = self.coeffs if smooth is None else ndimage.spline_filter(ndimage.gaussian_filter(self.z, smooth), order=3)
		return ndimage.map_coordinates(data, [rows, cols], order=3, mode="nearest", prefilter=False)

	def inside(self, x, y, margin=0.0):
		x0, x1, y0, y1 = self.extent()
		return (x >= x0 + margin) & (x <= x1 - margin) & (y >= y0 + margin) & (y <= y1 - margin)


class PolarDEM:
	"""PDS LOLA polar IMG: int16 LSB * metres_per_dn above the 1737.4 km sphere, polar
	stereographic, `lines` x `lines`, pole at pixel (offset, offset) (0-based centres)."""

	def __init__(self, path, src, smooth_pixels):
		n = src["lines"]
		dn = np.fromfile(path, dtype="<i2").reshape(n, n)
		self.z = dn.astype(np.float32) * src["metres_per_dn"]
		if smooth_pixels > 0.5:
			self.z = ndimage.gaussian_filter(self.z, smooth_pixels)
		self.px = src["metres_per_pixel"]
		self.offset = src["projection_offset"]
		self.n = n
		self.flip_x, self.flip_y = 1.0, 1.0   # set by calibrate()
		self.shift = 0.0

	def sample(self, x, y):
		cols = self.offset + self.flip_x * x / self.px
		rows = self.offset - self.flip_y * y / self.px
		return ndimage.map_coordinates(self.z, [rows, cols], order=1, mode="nearest") + self.shift

	def calibrate(self, site, label):
		"""Picks the axis orientation that matches the site DEM and the mean height offset."""
		rng = np.random.default_rng(1)
		x0, x1, y0, y1 = site.extent()
		x = rng.uniform(x0 + 500, x1 - 500, 20000)
		y = rng.uniform(y0 + 500, y1 - 500, 20000)
		truth = site.sample(x, y, smooth=self.px / site.px / 2.0)
		best = None
		for fx in (1.0, -1.0):
			for fy in (1.0, -1.0):
				self.flip_x, self.flip_y, self.shift = fx, fy, 0.0
				diff = truth - self.sample(x, y)
				rms = float(np.sqrt(np.mean((diff - diff.mean()) ** 2)))
				if best is None or rms < best[0]:
					best = (rms, fx, fy, float(diff.mean()))
		rms, self.flip_x, self.flip_y, self.shift = best
		log(f"{label}: axes x{'+' if self.flip_x > 0 else '-'} y{'+' if self.flip_y > 0 else '-'}, offset to the site data {self.shift:+.2f} m, RMS difference {rms:.2f} m")
		if rms > max(3.0 * self.px, 30.0) or abs(self.shift) > 50.0:
			sys.exit(f"{label} doesn't match the site data (RMS {rms:.1f} m, offset {self.shift:.1f} m)")
		return {"flip_x": self.flip_x, "flip_y": self.flip_y, "offset_to_site_m": round(self.shift, 3), "rms_difference_m": round(rms, 3)}


# --- Geometry ---------------------------------------------------------------------------------

def stereo_to_dir(x, y):
	"""Polar stereographic (south, true scale at the pole; x = rho sin lon, y = rho cos lon) ->
	unit vectors in the Moon's mean-Earth frame (x towards lon 0, z north)."""
	rho = np.hypot(x, y)
	colat = 2.0 * np.arctan(rho / (2.0 * R_MOON))
	lat = -(np.pi / 2.0 - colat)
	lon = np.arctan2(x, y)
	return np.stack([np.cos(lat) * np.cos(lon), np.cos(lat) * np.sin(lon), np.sin(lat)], axis=-1)


def dir_to_stereo(d):
	lat = np.arcsin(np.clip(d[..., 2], -1.0, 1.0))
	lon = np.arctan2(d[..., 1], d[..., 0])
	rho = 2.0 * R_MOON * np.tan((np.pi / 2.0 + lat) / 2.0)
	return rho * np.sin(lon), rho * np.cos(lon)


def lonlat_to_dir(lon, lat):
	"""Longitude east, latitude (degrees) -> unit vectors in the Moon's mean-Earth frame."""
	lo, la = np.radians(lon), np.radians(lat)
	return np.stack([np.cos(la) * np.cos(lo), np.cos(la) * np.sin(lo), np.sin(la)], axis=-1)


def dir_to_lonlat(d):
	lat = np.degrees(np.arcsin(np.clip(d[..., 2], -1.0, 1.0)))
	lon = np.degrees(np.arctan2(d[..., 1], d[..., 0])) % 360.0
	return lon, lat


class Projection:
	"""Map coordinates <-> directions: polar stereographic (x, y in m) or longitude / latitude
	(degrees, for equirectangular sources). `step` is a small map-coordinate step for the frame's
	axes."""

	def __init__(self, kind):
		self.kind = kind
		if kind == "polar_stereographic":
			self.to_dir, self.from_dir, self.step = stereo_to_dir, dir_to_stereo, 1.0
		else:
			self.to_dir, self.from_dir, self.step = lonlat_to_dir, dir_to_lonlat, 1e-5


class LocalFrame:
	"""Tangent plane at the play centre, Y up. Polar stereographic: X along the stereographic +x,
	Z along -y. Longitude / latitude: X east, Z south. `cx`, `cy` in the projection's map
	coordinates; `h0` overrides the centre's height (a verbatim tier's constant)."""

	def __init__(self, cx, cy, height_at, proj=None, h0=None):
		self.proj = proj or Projection("polar_stereographic")
		to_dir, step = self.proj.to_dir, self.proj.step
		self.up = to_dir(np.array(cx), np.array(cy))
		ex = to_dir(np.array(cx + step), np.array(cy)) - self.up
		ey = to_dir(np.array(cx), np.array(cy + step)) - self.up
		ex -= ex.dot(self.up) * self.up
		ey -= ey.dot(self.up) * self.up
		self.ex = ex / np.linalg.norm(ex)
		self.ez = np.cross(self.ex, self.up)            # X x Y = Z
		if self.ez.dot(ey / np.linalg.norm(ey)) > -0.999:
			sys.exit("local frame: the map's +y is not world -Z")
		self.h0 = float(height_at(np.array([cx]), np.array([cy]))[0]) if h0 is None else float(h0)
		self.origin = (R_MOON + self.h0) * self.up
		lat = math.degrees(math.asin(self.up[2]))
		lon = math.degrees(math.atan2(self.up[1], self.up[0])) % 360.0
		self.lat_lon = (lat, lon)

	def to_world(self, X, Z, height_at, iterations=4):
		"""Surface heights (Y) at tangent-plane positions X, Z (arrays), and how far the found
		points ended up from the asked positions (m)."""
		tx, tz = X.astype(np.float64).copy(), Z.astype(np.float64).copy()
		for _ in range(iterations):
			p = self.origin + tx[..., None] * self.ex + tz[..., None] * self.ez
			d = p / np.linalg.norm(p, axis=-1, keepdims=True)
			sx, sy = self.proj.from_dir(d)
			h = height_at(sx, sy)
			s = (R_MOON + h)[..., None] * d - self.origin
			gx, gz = s @ self.ex, s @ self.ez
			tx += X - gx
			tz += Z - gz
		Y = s @ self.up
		if not np.isfinite(Y).all():
			sys.exit("exact conversion: non-finite heights")
		return Y, float(np.max(np.hypot(X - gx, Z - gz)))

	def from_map(self, sx, sy, h):
		d = self.proj.to_dir(sx, sy)
		s = (R_MOON + h)[..., None] * d - self.origin
		return s @ self.ex, s @ self.ez, s @ self.up


# --- Detail -----------------------------------------------------------------------------------

def roughness(n, spacing, cfg, rng):
	"""Fractal noise with a power spectrum for Hurst exponent H, only below max_wavelength, scaled
	to the given RMS slope at the grid spacing."""
	size = 1 << int(math.ceil(math.log2(n)))
	k = np.fft.fftfreq(size, d=spacing)
	kx, ky = np.meshgrid(k, k)
	kk = np.hypot(kx, ky)
	kk[0, 0] = 1.0
	amp = kk ** (-(1.0 + cfg["roughness_hurst"]))
	# Smoothly off above the max wavelength (real shape stays the LOLA data's)
	kmin = 1.0 / cfg["roughness_max_wavelength"]
	amp *= np.clip((kk - kmin * 0.5) / (kmin * 0.5), 0.0, 1.0)
	amp[0, 0] = 0.0
	phase = rng.uniform(0.0, 2.0 * np.pi, (size, size))
	field = np.real(np.fft.ifft2(amp * np.exp(1j * phase)))[:n, :n]
	gz, gx = np.gradient(field, spacing)
	rms_slope = np.sqrt(np.mean(gx ** 2 + gz ** 2))
	return field * math.tan(math.radians(cfg["roughness_rms_slope_degrees"])) / rms_slope


def protection_mask(X, Z, areas):
	"""1 inside protected areas, 0 outside, smooth over each area's blend distance."""
	m = np.zeros_like(X)
	for a in areas:
		dx = np.abs(X - a["centre"][0]) - a["size"][0] / 2.0
		dz = np.abs(Z - a["centre"][1]) - a["size"][1] / 2.0
		outside = np.hypot(np.maximum(dx, 0), np.maximum(dz, 0))
		t = np.clip(1.0 - outside / a["blend"], 0.0, 1.0)
		m = np.maximum(m, t * t * (3 - 2 * t))
	return m


def add_craters(h, X0, spacing, cfg, rng, protect):
	"""Bowl craters with raised rims and fading ejecta, sizes from the lunar equilibrium density
	N(>D) = c / D^2 per m^2 (D in m). Returns the crater list and a freshness map (0..1)."""
	n = h.shape[0]
	area = ((n - 1) * spacing) ** 2
	dmin, dmax = cfg["crater_min_diameter"], cfg["crater_max_diameter"]
	count = int(cfg["crater_density_coefficient"] * area * (dmin ** -2 - dmax ** -2))
	u = rng.uniform(0.0, 1.0, count)
	diameters = dmin / np.sqrt(1.0 - u * (1.0 - (dmin / dmax) ** 2))
	order = np.argsort(-diameters)                 # big first, small ones on top
	diameters = diameters[order]
	cx = rng.uniform(X0, X0 + (n - 1) * spacing, count)
	cz = rng.uniform(X0, X0 + (n - 1) * spacing, count)
	dr_lo, dr_hi = cfg["crater_depth_ratio"]
	depth_ratio = rng.uniform(dr_lo, dr_hi, count)
	fresh = np.zeros_like(h)
	craters = []
	for D, x, z, dr in zip(diameters, cx, cz, depth_ratio):
		R = D / 2.0
		reach = 2.5 * R
		i0 = max(int((z - reach - X0) / spacing), 0); i1 = min(int((z + reach - X0) / spacing) + 2, n)
		j0 = max(int((x - reach - X0) / spacing), 0); j1 = min(int((x + reach - X0) / spacing) + 2, n)
		if i0 >= i1 or j0 >= j1:
			continue
		zz = X0 + np.arange(i0, i1) * spacing
		xx = X0 + np.arange(j0, j1) * spacing
		r = np.hypot(xx[None, :] - x, zz[:, None] - z) / R
		rim = 0.035 * D * dr / dr_hi
		profile = np.where(r < 1.0, dr * D * (r * r - 1.0) + rim,
			np.where(r < 2.5, rim * (r ** -3 - 2.5 ** -3) / (1 - 2.5 ** -3), 0.0))
		keep = 1.0 - protect[i0:i1, j0:j1]
		h[i0:i1, j0:j1] += profile * keep
		freshness = (dr - dr_lo) / (dr_hi - dr_lo)
		if freshness > 0.6:
			glow = np.clip(1.0 - np.abs(r - 1.2) / 1.2, 0.0, 1.0) * (freshness - 0.6) / 0.4
			fresh[i0:i1, j0:j1] = np.maximum(fresh[i0:i1, j0:j1], glow * keep)
		if D > 6.0:
			craters.append((x, z, D, dr))
	return craters, fresh, count


def grade(h, X, Z, areas, before_detail):
	"""Each protected area graded to the plane fitted to its (pre-detail) ground."""
	info = []
	for a in areas:
		inner = (np.abs(X - a["centre"][0]) <= a["size"][0] / 2) & (np.abs(Z - a["centre"][1]) <= a["size"][1] / 2)
		A = np.stack([X[inner], Z[inner], np.ones(inner.sum())], axis=1)
		coef, *_ = np.linalg.lstsq(A, before_detail[inner], rcond=None)
		plane = coef[0] * X + coef[1] * Z + coef[2]
		w = protection_mask(X, Z, [a])
		h[:] = h * (1.0 - w) + plane * w
		slope = math.degrees(math.atan(math.hypot(coef[0], coef[1])))
		info.append({"name": a["name"], "plane_slope_degrees": round(slope, 2)})
		log(f"  graded {a['name']}: plane slope {slope:.2f} deg")
	return info


def make_rocks(h, X0, spacing, cfg, rng, protect, craters):
	n = h.shape[0]
	area = ((n - 1) * spacing) ** 2
	smin, smax = cfg["rock_sizes"]
	a = cfg["rock_size_exponent"]
	count = int(cfg["rock_density_over_10cm"] * area * ((smin / 0.1) ** -a - (smax / 0.1) ** -a))
	u = rng.uniform(0.0, 1.0, count)
	sizes = smin * (1.0 - u * (1.0 - (smin / smax) ** a)) ** (-1.0 / a)
	pos = rng.uniform(X0, X0 + (n - 1) * spacing, (count, 2))
	# Half of them around crater rims (ejecta blocks)
	if craters:
		c = np.array(craters)
		pick = rng.integers(0, len(c), count // 2)
		ang = rng.uniform(0, 2 * np.pi, count // 2)
		rad = c[pick, 2] / 2.0 * rng.uniform(0.9, 2.0, count // 2)
		pos[: count // 2, 0] = c[pick, 0] + np.cos(ang) * rad
		pos[: count // 2, 1] = c[pick, 1] + np.sin(ang) * rad
	ci = np.clip(((pos[:, 1] - X0) / spacing).astype(int), 0, n - 1)
	cj = np.clip(((pos[:, 0] - X0) / spacing).astype(int), 0, n - 1)
	keep = (protect[ci, cj] < 0.01) & (np.abs(pos[:, 0]) < X0 * -0.98) & (np.abs(pos[:, 1]) < X0 * -0.98)
	pos, sizes = pos[keep], sizes[keep]
	y = ndimage.map_coordinates(h, [(pos[:, 1] - X0) / spacing, (pos[:, 0] - X0) / spacing], order=1)
	yaw = rng.uniform(0.0, 2.0 * np.pi, len(sizes))
	shape = rng.integers(0, 6, len(sizes))
	# x, y (ground), z, size, yaw, shape variant
	return np.stack([pos[:, 0], y, pos[:, 1], sizes, yaw, shape], axis=1).astype(np.float32)


# --- Horizons ---------------------------------------------------------------------------------

class World:
	"""Heights anywhere from the finest tier that covers the point."""

	def __init__(self, tiers):
		self.tiers = tiers   # finest first: (half, spacing, heights)

	def height(self, X, Z):
		out = np.full(X.shape, np.nan)
		todo = np.ones(X.shape, bool)
		for half, spacing, hgt in self.tiers:
			inside = todo & (np.abs(X) <= half) & (np.abs(Z) <= half)
			if inside.any():
				n = hgt.shape[0]
				cols = np.clip((X[inside] + half) / spacing, 0, n - 1)
				rows = np.clip((Z[inside] + half) / spacing, 0, n - 1)
				out[inside] = ndimage.map_coordinates(hgt, [rows, cols], order=1, mode="nearest")
				todo &= ~inside
		out[todo] = -1e6
		return out


def horizon_angles(world, X, Z, Y, azimuths_deg, start, max_distance=150000.0, ratio=1.04):
	"""Elevation (degrees) of the horizon from each point (X, Z, Y + 1 cm) towards each azimuth
	(degrees from -Z towards +X), over the given heights (curvature is already in them)."""
	dists = [start]
	while dists[-1] < max_distance:
		dists.append(dists[-1] * ratio + start * 0.5)
	out = np.empty((len(azimuths_deg),) + X.shape, np.float32)
	eye = Y + 0.01
	for k, az in enumerate(azimuths_deg):
		a = math.radians(az)
		dx, dz = math.sin(a), -math.cos(a)
		best = np.full(X.shape, -90.0)
		for d in dists:
			hh = world.height(X + dx * d, Z + dz * d)
			best = np.maximum(best, np.degrees(np.arctan2(hh - eye, d)))
		out[k] = best
	return out


# --- Output -----------------------------------------------------------------------------------

def save_r16(path, h):
	lo, hi = float(h.min()), float(h.max())
	scale = (hi - lo) / 65535.0 if hi > lo else 1.0
	v = np.round((h - lo) / scale).astype("<u2")
	v.tofile(path)
	return {"min": lo, "scale": scale, "size": h.shape[0], "max_error_m": float(np.max(np.abs(v * scale + lo - h)))}


def save_horizons(prefix, angles):
	files = []
	enc = np.clip(np.round((angles - HORIZON_MIN) / HORIZON_RANGE * 255.0), 0, 255).astype(np.uint8)
	for p in range(AZIMUTHS // 4):
		rgba = np.stack([enc[p * 4 + c] for c in range(4)], axis=-1)
		path = f"{prefix}_{p}.png"
		Image.fromarray(rgba, "RGBA").save(path, optimize=True)
		files.append(os.path.basename(path))
	return files


def hillshade(h, spacing, sun_az=135.0, sun_el=35.0):
	gz, gx = np.gradient(h, spacing)
	a, e = math.radians(sun_az), math.radians(sun_el)
	l = np.array([math.sin(a) * math.cos(e), math.sin(e), -math.cos(a) * math.cos(e)])
	n = np.stack([-gx, np.ones_like(h), -gz], -1)
	n /= np.linalg.norm(n, axis=-1, keepdims=True)
	return np.clip(n @ l, 0, 1)


# --- Main -------------------------------------------------------------------------------------

def main():
	args = [a for a in sys.argv[1:] if not a.startswith("--")]
	cfg_path = args[0] if args else "tools/terrain/moon_site01.json"
	cfg = json.load(open(cfg_path))
	rng = np.random.default_rng(cfg["seed"])
	if "--fetch" in sys.argv:
		fetch(cfg)
	sources = check_sources(cfg)
	raw = lambda key: source_path(cfg, cfg["sources"][key])
	os.makedirs(cfg["out_dir"], exist_ok=True)
	os.makedirs(cfg["preview_dir"], exist_ok=True)
	site_type = cfg.get("site_type", "polar_stereographic")

	calibration, extras, provenance = {}, {}, {}
	authored = []          # changes to the measured ground (terrain.json `authored_changes`)
	if site_type == "polar_stereographic":
		log("reading the site DEM")
		site = SiteDEM(raw("site"))
		cx, cy = cfg["centre_stereographic"]
		frame = LocalFrame(cx, cy, site.sample)
		polar = {}
		for t in cfg["tiers"]:
			if t["source"].startswith("polar") and t["source"] not in polar:
				src = cfg["sources"][t["source"]]
				log(f"reading {t['source']}")
				dem = PolarDEM(raw(t["source"]), src, t["metres_per_pixel"] / src["metres_per_pixel"] / 2.0)
				calibration[t["source"]] = dem.calibrate(site, t["source"])
				polar[t["source"]] = dem

		def tier_function(t):
			spacing = t["metres_per_pixel"]
			if t["source"] == "site":
				smooth = None if spacing <= site.px else spacing / site.px / 2.0
				return (lambda sx, sy: site.sample(sx, sy)) if smooth is None else (lambda sx, sy, s=smooth: site.sample(sx, sy, smooth=s))
			return polar[t["source"]].sample
		centre = {"stereographic_m": cfg["centre_stereographic"]}
		axes = "X = polar stereographic +x, Z = -y (towards longitude 180), Y up; metres along the tangent plane at the centre; heights include the Moon's curvature"
	else:
		log("reading the NAC DTM")
		dtm = LrocDTM(raw("dtm"))
		r0, c0 = cfg["play_centre_post"]
		if not dtm.valid[r0, c0]:
			sys.exit("the play centre post has no data")
		clon, clat = dtm.lon_lat(float(r0), float(c0))
		frame = LocalFrame(clon, clat, None, proj=Projection("equirectangular"), h0=float(dtm.raw[r0, c0]))
		sldem = {}
		reach = max(t["half_size"] for t in cfg["tiers"]) * 1.5
		lon_range = (clon - math.degrees(reach / (R_MOON * math.cos(math.radians(clat)))), clon + math.degrees(reach / (R_MOON * math.cos(math.radians(clat)))))
		for t in cfg["tiers"]:
			if "sldem" in t["source"]:
				src = cfg["sources"]["sldem"]
				log(f"reading SLDEM2015 rows {src['rows'][0]}-{src['rows'][1]} for {t['name']}")
				band = SldemBand(raw("sldem"), src, lon_range, 0.0)
				smooth = t["metres_per_pixel"] / band.metres_per_pixel / 2.0
				if smooth > 0.5:
					band.z = ndimage.gaussian_filter(band.z, smooth)
				calibration[f"sldem_{t['name']}"] = band.calibrate(dtm, f"SLDEM2015 ({t['name']})")
				sldem[t["name"]] = band
		feather = cfg.get("dtm_feather_m", 100.0)

		def tier_function(t):
			band = sldem.get(t["name"])
			if t["source"] == "sldem":
				return band.sample
			smooth = t["metres_per_pixel"] / dtm.scale / 2.0

			def blended(lon, lat):
				w = dtm.weight(lon, lat, feather)
				return w * dtm.sample(lon, lat, smooth) + (1.0 - w) * band.sample(lon, lat)
			return blended
		centre = {"dtm_post": [r0, c0]}
		axes = "X east, Z south (rows along +Z), Y up, metres. The verbatim play tier: NAC DTM posts at (2 * column, height - constant, 2 * row) from the centre post, no curvature (as delivered); outer tiers: metres along the tangent plane at the centre, heights include the Moon's curvature"
	log(f"play centre: {frame.lat_lon[0]:.5f} N, {frame.lat_lon[1]:.5f} E, {frame.h0:.3f} m above the 1737.4 km sphere")
	centre.update({"lat": frame.lat_lon[0], "lon_east": frame.lat_lon[1], "height_above_1737400_m": frame.h0})

	tiers_out, world_tiers, heights = [], [], {}
	detail = cfg["detail"]
	for t in cfg["tiers"]:
		spacing, half = t["metres_per_pixel"], t["half_size"]
		n = int(round(2 * half / spacing)) + 1
		axis = -half + np.arange(n) * spacing
		X, Z = np.meshgrid(axis, axis)
		if t["source"] == "dtm_verbatim":
			if abs(spacing - dtm.scale) > 1e-6:
				sys.exit(f"tier {t['name']}: a verbatim tier must use the DTM's {dtm.scale} m")
			k = (n - 1) // 2
			if r0 - k < 0 or c0 - k < 0 or r0 + k >= dtm.lines or c0 + k >= dtm.samples:
				sys.exit(f"tier {t['name']}: outside the DTM")
			window = dtm.raw[r0 - k:r0 + k + 1, c0 - k:c0 + k + 1]
			if not dtm.valid[r0 - k:r0 + k + 1, c0 - k:c0 + k + 1].all():
				sys.exit(f"tier {t['name']}: no-data posts inside")
			Y = window.astype(np.float64) - frame.h0
			measured = Y.astype("<f4")
			measured.tofile(os.path.join(cfg["out_dir"], f"{t['name']}_measured.f32"))
			provenance = {
				"product_id": dtm.keys["PRODUCT_ID"], "product_version": dtm.keys["PRODUCT_VERSION_ID"],
				"file": sources["dtm"]["file"], "sha256": sources["dtm"]["sha256"],
				"window": {"first_line": r0 - k, "first_sample": c0 - k, "lines": n, "samples": n, "centre_post": [r0, c0], "zero_based": True},
				"constant_subtracted_m": frame.h0,
				"placement": f"post (line first_line + i, sample first_sample + j) at X = {spacing:g} * (j - {k}), Z = {spacing:g} * (i - {k}), Y = height - constant_subtracted_m; float32",
				"measured_file": f"{t['name']}_measured.f32",
				"note": "The starter pack named in game/docs/ASSET_BRIEF.md doesn't exist; this window of the public PDS product is used instead (MOON_TERRAIN.md).",
			}
			if "conf" in cfg["sources"]:
				# The DTM's confidence map over the window (0 no data, 1 shadowed, 2 saturated, 3 suspicious,
				# 4 interpolated, 10-14 correlated, 15 edited: the product's readme)
				_, conf = read_pds3(raw("conf"))
				w = conf[r0 - k:r0 + k + 1, c0 - k:c0 + k + 1]
				values, counts = np.unique(w, return_counts=True)
				provenance["confidence_percent"] = {int(v): round(float(c) / w.size * 100.0, 2) for v, c in zip(values, counts)}
				log(f"  confidence map over the window (%): {provenance['confidence_percent']}")
			log(f"tier {t['name']}: {n} x {n} DTM posts verbatim from line {r0 - k}, sample {c0 - k}; heights {Y.min():.2f} .. {Y.max():.2f} m")
		else:
			log(f"tier {t['name']}: {n} x {n} at {spacing} m (exact conversion)")
			Y, miss = frame.to_world(X, Z, tier_function(t))
			log(f"  converged to {miss * 1000:.2f} mm; heights {Y.min():.1f} .. {Y.max():.1f} m")
		if t.get("detail"):
			# No detail on protected ground, and none at the tier's edge (it fades out over the last 22 m,
			# past the boundary), so the play tier meets the smooth ring without a step
			edge = np.maximum(np.abs(X), np.abs(Z))
			protect = np.maximum(protection_mask(X, Z, cfg["protected"]), np.clip((edge - (half - 22.0)) / 12.0, 0.0, 1.0))
			before = Y.copy()
			if detail.get("roughness", True):
				Y += roughness(n, spacing, detail, rng) * (1.0 - protect)
				authored.append({"change": "fractal roughness below the data's resolution", "collision": True, "seed": cfg["seed"]})
			craters, fresh = [], None
			if detail.get("craters", True):
				craters, fresh, crater_count = add_craters(Y, -half, spacing, detail, rng, protect)
				log(f"  {crater_count} craters {detail['crater_min_diameter']}-{detail['crater_max_diameter']} m")
				authored.append({"change": f"{crater_count} procedural craters {detail['crater_min_diameter']}-{detail['crater_max_diameter']} m", "collision": True, "seed": cfg["seed"]})
			graded = Y.copy()
			extras["grading"] = grade(Y, X, Z, cfg["protected"], before)
			for a, g in zip(cfg["protected"], extras["grading"]):
				change = np.abs(Y - graded) * (protection_mask(X, Z, [a]) > 0.0)
				touched = change > 1e-6
				g["max_change_m"] = round(float(change.max()), 3)
				authored.append({"change": f"{a['name']} graded to its mean plane ({g['plane_slope_degrees']} deg)", "collision": True,
					"area_m": a["size"], "centre": a["centre"], "blend_m": a["blend"], "max_height_change_m": g["max_change_m"],
					"posts_changed": int(touched.sum())})
			rocks = make_rocks(Y, -half, spacing, detail, rng, protect, craters)
			rocks.tofile(os.path.join(cfg["out_dir"], "rocks.f32"))
			extras["rocks"] = {"file": "rocks.f32", "count": len(rocks), "fields": ["x", "ground_y", "z", "size", "yaw", "shape"],
				"collision_min_size": detail["rock_collision_min_size"], "with_collision": int((rocks[:, 3] >= detail["rock_collision_min_size"]).sum())}
			authored.append({"change": f"{len(rocks)} procedural rocks {detail['rock_sizes'][0]}-{detail['rock_sizes'][1]} m (instances, not in the heightmap)",
				"collision": f"convex, {extras['rocks']['with_collision']} of {detail['rock_collision_min_size']} m and up", "seed": cfg["seed"]})
			log(f"  {len(rocks)} rocks, {extras['rocks']['with_collision']} of {detail['rock_collision_min_size']} m and up")
			if fresh is not None:
				albedo = np.clip(128 + fresh[::2, ::2] * 127, 0, 255).astype(np.uint8)
				Image.fromarray(albedo, "L").save(os.path.join(cfg["out_dir"], "freshness_play.png"), optimize=True)
				extras["freshness"] = {"file": "freshness_play.png", "metres_per_pixel": spacing * 2, "encoding": "0.5 + 0.5 * freshness"}
			if t["source"] == "dtm_verbatim":
				# Outside the graded areas the play tier is the measured surface, bit for bit
				outside = protection_mask(X, Z, cfg["protected"]) == 0.0
				if not detail.get("roughness", True) and not detail.get("craters", True) and not np.array_equal(Y.astype("<f4")[outside], measured[outside]):
					sys.exit("play tier: changed outside the graded areas")
			gz, gx = np.gradient(Y, spacing)
			slope = np.degrees(np.arctan(np.hypot(gx, gz)))
			inner = (np.abs(X) <= cfg["boundary_half_size"]) & (np.abs(Z) <= cfg["boundary_half_size"])
			extras["play_slopes"] = {f"over_{s}": round(float((slope[inner] > s).mean() * 100), 3) for s in (15, 25, 30, 40)}
			extras["play_slopes"]["max"] = round(float(slope[inner].max()), 1)
			extras["play_slopes"]["baseline_m"] = 2 * spacing
			log(f"  slopes inside the boundary (% over 15/25/30/40): {extras['play_slopes']}")
		heights[t["name"]] = Y
		entry = {"name": t["name"], "size": n, "metres_per_pixel": spacing, "half_size": half, "source": t["source"]}
		if t["source"] == "dtm_verbatim":
			Y.astype("<f4").tofile(os.path.join(cfg["out_dir"], f"{t['name']}.f32"))
			entry.update({"file": f"{t['name']}.f32", "format": "float32"})
		else:
			info = save_r16(os.path.join(cfg["out_dir"], f"{t['name']}.r16"), Y)
			log(f"  r16: {info['scale'] * 1000:.2f} mm per step, worst rounding {info['max_error_m'] * 1000:.2f} mm")
			entry.update({"file": f"{t['name']}.r16", "format": "uint16", "height_min": info["min"], "height_scale": info["scale"]})
		tiers_out.append(entry)
		world_tiers.append((half, spacing, Y))

	world = World(world_tiers)

	# Spots: ground heights
	spots = {}
	for name, (x, z) in cfg["spots"].items():
		spots[name] = [x, float(world.height(np.array([float(x)]), np.array([float(z)]))[0]), z]

	if "ephemeris" in cfg:
		sun, earth, sky = ephemeris(cfg, frame)
		sun.update(sunlight_checks(cfg, world, sun))
		extras["sky"] = sky
		artifacts = {}
		for name, a in cfg.get("artifacts", {}).items():
			l, s = dtm.pixel(np.array(a["lon"]), np.array(a["lat"]))
			x, z = float((s - c0) * dtm.scale), float((l - r0) * dtm.scale)
			artifacts[name] = {**a, "position": [round(x, 2), float(world.height(np.array([x]), np.array([z]))[0]), round(z, 2)]}
			log(f"  {name}: x {x:+.1f}, z {z:+.1f}")
		extras["artifacts"] = artifacts
		if "ortho" in cfg["sources"]:
			extras["site_brightness"] = site_brightness(cfg, raw("ortho"), dtm, (r0, c0), cfg["tiers"][0], frame)
	else:
		# Sun azimuth: the big permanently shadowed crater floors dark, base and pad lit
		sun = choose_sun(cfg, frame, world, raw("psr"))
		earth = choose_earth(cfg, world, spots, sun)

	# Horizon maps, starting at the sun's azimuth so its own direction needs no interpolation
	azimuths = [(sun["azimuth"] + i * 360.0 / AZIMUTHS) % 360.0 for i in range(AZIMUTHS)]
	horizon_files = {}
	for t, (half, spacing, Y) in zip(cfg["tiers"], world_tiers):
		step = t["horizon_step"]
		Xs, Zs = np.meshgrid(-half + np.arange(0, Y.shape[0], step) * spacing, -half + np.arange(0, Y.shape[0], step) * spacing)
		Ys = Y[::step, ::step]
		log(f"horizons for {t['name']}: {Xs.shape[0]} x {Xs.shape[1]} at {spacing * step} m, {AZIMUTHS} azimuths")
		ang = horizon_angles(world, Xs, Zs, Ys, azimuths, start=spacing * step)
		horizon_files[t["name"]] = {"files": save_horizons(os.path.join(cfg["out_dir"], f"horizon_{t['name']}"), ang),
			"metres_per_pixel": spacing * step, "size": Xs.shape[0], "half_size": half}
		if t["name"] == "play":
			play_horizon = (Xs, Zs, Ys, ang)

	meta = {
		"name": cfg["name"], "description": cfg["description"], "generated": time.strftime("%Y-%m-%d %H:%M"),
		"generator": "tools/terrain/build_moon_terrain.py " + os.path.basename(cfg_path), "seed": cfg["seed"],
		"site_type": site_type, "centre": centre, "axes": axes,
		"height_encoding": "uint16 tiers: height = height_min + uint16 * height_scale; float32 tiers: height; little-endian, row-major, rows along +Z",
		"tiers": tiers_out,
		"horizons": {"azimuths_degrees": azimuths, "first_azimuth": azimuths[0], "step_degrees": 360.0 / AZIMUTHS,
			"encoding": f"degrees = {HORIZON_MIN} + byte / 255 * {HORIZON_RANGE}",
			"azimuth_convention": "degrees from -Z towards +X", "channels": "file k holds azimuths 4k..4k+3 in R, G, B, A",
			"tiers": horizon_files},
		"boundary_half_size": cfg["boundary_half_size"], "protected": cfg["protected"], "spots": spots,
		"sun": sun, "earth": earth, "calibration": calibration, "sources": sources,
		"provenance": provenance, "authored_changes": authored, **extras,
	}
	json.dump(meta, open(os.path.join(cfg["out_dir"], "terrain.json"), "w"), indent="\t")
	previews(cfg, heights, world_tiers, play_horizon, spots, sun)
	log("done")


# --- Ephemeris (JPL Horizons) ---------------------------------------------------------------------

HORIZONS_API = "https://ssd.jpl.nasa.gov/api/horizons.api"


def horizons(cfg, command, utc, lon, lat, alt_km):
	"""One row of a Horizons observer table for `command` seen from (lon, lat, alt) on the Moon at
	`utc` ("YYYY-MM-DD HH:MM"): ICRF RA/Dec, airless apparent azimuth / elevation, illuminated %,
	angular diameter (arcsec), sub-observer longitude / latitude. Replies are cached in raw/."""
	import datetime
	import urllib.parse
	stop = (datetime.datetime.strptime(utc, "%Y-%m-%d %H:%M") + datetime.timedelta(minutes=1)).strftime("%Y-%m-%d %H:%M")
	params = {"format": "text", "COMMAND": f"'{command}'", "CENTER": "'coord@301'", "COORD_TYPE": "'GEODETIC'",
		"SITE_COORD": f"'{lon:.6f},{lat:.6f},{alt_km:.4f}'", "EPHEM_TYPE": "'OBSERVER'", "QUANTITIES": "'1,4,10,13,14'",
		"START_TIME": f"'{utc}'", "STOP_TIME": f"'{stop}'", "STEP_SIZE": "'1 m'", "ANG_FORMAT": "'DEG'",
		"APPARENT": "'AIRLESS'", "CSV_FORMAT": "'YES'", "EXTRA_PREC": "'YES'"}
	url = HORIZONS_API + "?" + urllib.parse.urlencode(params)
	cache = os.path.join(cfg["raw_dir"], f"horizons_{hashlib.sha1(url.encode()).hexdigest()[:12]}.txt")
	if not os.path.exists(cache):
		log(f"asking JPL Horizons for {command} at {utc} UTC")
		with urllib.request.urlopen(url, timeout=60) as response:
			text = response.read().decode()
		with open(cache, "w") as f:
			f.write(text)
	text = open(cache).read()
	if "$$SOE" not in text:
		sys.exit(f"Horizons: no ephemeris in {cache}")
	lines = text.split("\n")
	soe = lines.index("$$SOE")
	header = [h.strip() for h in next(l for l in reversed(lines[:soe]) if "Date__" in l).split(",")]
	row = [v.strip() for v in lines[soe + 1].split(",")]
	col = lambda prefix: float(row[next(i for i, h in enumerate(header) if h.startswith(prefix))])
	if "Center pole/equ : MEAN_ME" not in text:
		sys.exit("Horizons: the site isn't in the Moon's mean-Earth frame")
	return {"ra": col("R.A."), "dec": col("DEC"), "azimuth": col("Azimuth") % 360.0, "elevation": col("Elevation"),
		"illuminated": col("Illu%") / 100.0, "diameter_arcsec": col("Ang-diam"), "sub_lon": col("ObsSub-LON"), "sub_lat": col("ObsSub-LAT"),
		"cache": os.path.basename(cache)}


def world_direction(azimuth, elevation):
	a, e = math.radians(azimuth), math.radians(elevation)
	return np.array([math.sin(a) * math.cos(e), math.sin(e), -math.cos(a) * math.cos(e)])


def equatorial_direction(ra, dec):
	a, d = math.radians(ra), math.radians(dec)
	return np.array([math.cos(d) * math.cos(a), math.cos(d) * math.sin(a), math.sin(d)])


def ephemeris(cfg, frame):
	"""The sun, Earth and the sky's orientation at the settings file's moment, from Horizons seen
	from the play centre. The orientation (equatorial = M @ world) is the rotation that best maps
	the sun's and Earth's ICRF directions onto their az / el; other bodies check it."""
	e = cfg["ephemeris"]
	lat, lon = frame.lat_lon
	at = lambda body: horizons(cfg, body, e["utc"], lon, lat, frame.h0 / 1000.0)
	sun_h, earth_h = at("10"), at("399")
	checks = {b: at(b) for b in e.get("check_bodies", [])}
	fit = {"sun": sun_h, "earth": earth_h}
	A = np.array([equatorial_direction(b["ra"], b["dec"]) for b in fit.values()])
	B = np.array([world_direction(b["azimuth"], b["elevation"]) for b in fit.values()])
	U, _, Vt = np.linalg.svd(A.T @ B)
	d = np.sign(np.linalg.det(Vt.T @ U.T))
	world_from_eq = Vt.T @ np.diag([1.0, 1.0, d]) @ U.T
	residual = {}
	for name, b in {**fit, **{f"check {k}": v for k, v in checks.items()}}.items():
		p = world_from_eq @ equatorial_direction(b["ra"], b["dec"])
		residual[name] = round(math.degrees(math.acos(min(1.0, float(p @ world_direction(b["azimuth"], b["elevation"]))))) * 3600.0, 1)
	log(f"sky orientation at {e['utc']} UTC: residuals (arcsec) {residual}")
	if max(residual.values()) > 60.0:
		sys.exit("sky orientation: a body is over 1 arcminute off")
	M = world_from_eq.T
	zen = M @ np.array([0.0, 1.0, 0.0])
	ncp = world_from_eq @ np.array([0.0, 0.0, 1.0])
	sun = {"elevation": round(sun_h["elevation"], 4), "azimuth": round(sun_h["azimuth"], 4), "utc": e["utc"], "moment": e.get("moment", ""),
		"source": "JPL Horizons, airless apparent az / el from the play centre", "horizons_cache": sun_h["cache"]}
	sdir = world_direction(sun_h["azimuth"], sun_h["elevation"])
	edir = world_direction(earth_h["azimuth"], earth_h["elevation"])
	earth = {"azimuth": round(earth_h["azimuth"], 4), "elevation": round(earth_h["elevation"], 4), "direction": [float(v) for v in edir],
		"angular_diameter_degrees": round(earth_h["diameter_arcsec"] / 3600.0, 4), "lit_fraction": round(earth_h["illuminated"], 4),
		"facing_longitude_east": round(earth_h["sub_lon"], 3), "facing_latitude": round(earth_h["sub_lat"], 3),
		"sun_separation_degrees": round(math.degrees(math.acos(float(sdir @ edir))), 2), "horizons_cache": earth_h["cache"]}
	log(f"sun {sun['elevation']:.2f} deg up at azimuth {sun['azimuth']:.2f}; Earth {earth['elevation']:.2f} up at {earth['azimuth']:.2f}, {earth['lit_fraction'] * 100:.0f}% lit, {earth['angular_diameter_degrees']:.3f} deg across")
	sky = {"utc": e["utc"], "world_to_equatorial": [[float(v) for v in r] for r in M],
		"convention": "equatorial = M @ world (rows); equatorial: x towards RA 0h, z the north celestial pole (ICRF / J2000, as the NASA SVS star map); world: X east, Y up, Z south",
		"fit_bodies": ["sun", "earth"], "residual_arcsec": residual,
		"zenith_ra_dec": [round(math.degrees(math.atan2(zen[1], zen[0])) % 360.0, 3), round(math.degrees(math.asin(zen[2])), 3)],
		"north_celestial_pole_az_el": [round(math.degrees(math.atan2(ncp[0], -ncp[2])) % 360.0, 3), round(math.degrees(math.asin(ncp[1])), 3)],
		"checks": {k: {"ra": v["ra"], "dec": v["dec"], "azimuth": v["azimuth"], "elevation": v["elevation"]} for k, v in checks.items()},
		"sun_ra_dec": [sun_h["ra"], sun_h["dec"]], "earth_ra_dec": [earth_h["ra"], earth_h["dec"]]}
	return sun, earth, sky


def sunlight_checks(cfg, world, sun):
	"""How much of the play area the sun lights, and the protected areas' highest horizon towards it."""
	half = cfg["boundary_half_size"]
	ax = np.arange(-half + 8, half, 16.0)
	AX, AZ = np.meshgrid(ax, ax)
	AX, AZ = AX.ravel(), AZ.ravel()
	lit = float((horizon_angles(world, AX, AZ, world.height(AX, AZ) + 0.05, [sun["azimuth"]], start=4.0)[0] < sun["elevation"]).mean())
	highest = -90.0
	for a in cfg["protected"]:
		xs = np.arange(a["centre"][0] - a["size"][0] / 2, a["centre"][0] + a["size"][0] / 2 + 0.1, 4.0)
		zs = np.arange(a["centre"][1] - a["size"][1] / 2, a["centre"][1] + a["size"][1] / 2 + 0.1, 4.0)
		gx, gz = np.meshgrid(xs, zs)
		gx, gz = gx.ravel(), gz.ravel()
		highest = max(highest, float(horizon_angles(world, gx, gz, world.height(gx, gz) + 1.0, [sun["azimuth"]], start=2.0)[0].max()))
	log(f"sun: {lit * 100:.0f}% of the play area in sunlight; protected areas' highest horizon towards it {highest:.2f} deg")
	if highest > sun["elevation"] - 0.27:
		sys.exit("sun: the base isn't fully lit")
	return {"play_area_lit_fraction": round(lit, 3), "base_highest_horizon_degrees": round(highest, 2)}


def site_brightness(cfg, path, dtm, centre_post, tier, frame):
	"""An approximate brightness pattern from the orthophoto (not albedo): the image divided by the
	DTM's own shading under the image's sun, normalised to its median, blurred to `blur_m`, limited
	to +-`range`, fading to neutral over the tier's last 30 m. Encoded as 8-bit,
	brightness = 1 + range * (byte / 127.5 - 1)."""
	s = cfg["site_brightness"]
	keys, img = read_pds3(path)
	for k in ("LINE_PROJECTION_OFFSET", "SAMPLE_PROJECTION_OFFSET", "MAP_SCALE", "LINES", "LINE_SAMPLES"):
		if keys[k] != dtm.keys[k]:
			sys.exit(f"orthophoto: {k} differs from the DTM's")
	start = keys["START_TIME"].replace("T", " ")[:16]
	lat, lon = frame.lat_lon
	sun_h = horizons(cfg, "10", start, lon, lat, frame.h0 / 1000.0)
	r0, c0 = centre_post
	n = int(round(2 * tier["half_size"] / tier["metres_per_pixel"])) + 1
	k = (n - 1) // 2
	win = img[r0 - k:r0 + k + 1, c0 - k:c0 + k + 1].astype(np.float64)
	valid = win > float(keys.get("CORE_NULL", -32768))
	h = dtm.filled[r0 - k:r0 + k + 1, c0 - k:c0 + k + 1]
	gz, gx = np.gradient(h, dtm.scale)
	nrm = np.stack([-gx, np.ones_like(h), -gz], -1)
	nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
	mu0 = np.clip(nrm @ world_direction(sun_h["azimuth"], sun_h["elevation"]), 0.0, None)
	mu = nrm[..., 1]                       # looking straight down
	shading = mu0 / (mu0 + mu)
	ok = valid & (shading > 0.05)
	ratio = np.where(ok, win / np.where(ok, shading, 1.0), 0.0)
	ratio /= np.median(ratio[ok])
	sigma = s["blur_m"] / 2.355 / dtm.scale
	weight = ndimage.gaussian_filter(ok.astype(np.float64), sigma)
	ratio = np.where(weight > 0.05, ndimage.gaussian_filter(ratio, sigma) / np.maximum(weight, 1e-6), 1.0)
	X = (np.arange(n) - k) * dtm.scale
	edge = np.maximum(np.abs(X)[None, :], np.abs(X)[:, None])
	fade = np.clip((tier["half_size"] - edge) / 30.0, 0.0, 1.0)
	r = s["range"]
	b = 1.0 + (np.clip(ratio, 1.0 - r, 1.0 + r) - 1.0) * fade
	enc = np.clip(np.round((b - 1.0) / r * 127.5 + 127.5), 0, 255).astype(np.uint8)
	Image.fromarray(enc, "L").save(os.path.join(cfg["out_dir"], "site_brightness_play.png"), optimize=True)
	log(f"site brightness: orthophoto sun {sun_h['elevation']:.1f} deg at {sun_h['azimuth']:.1f}; spread (5-95%) {np.percentile(b, 5):.2f} .. {np.percentile(b, 95):.2f}")
	return {"file": "site_brightness_play.png", "metres_per_pixel": dtm.scale, "half_size": tier["half_size"],
		"encoding": f"brightness = 1 + {r} * (byte / 127.5 - 1)", "range": r, "blur_m": s["blur_m"],
		"orthophoto": keys["PRODUCT_ID"], "image_time": keys["START_TIME"],
		"orthophoto_sun": {"azimuth": round(sun_h["azimuth"], 2), "elevation": round(sun_h["elevation"], 2), "horizons_cache": sun_h["cache"]},
		"note": "Approximate brightness pattern, not albedo: the orthophoto divided by the DTM's Lommel-Seeliger shading under the image's own sun, then blurred. Shading by relief smaller than the DTM resolves stays in it. Shading only, never collision."}


def psr_patches(cfg, frame, path):
	"""The official permanently shadowed region map around the play area, as local points."""
	im = Image.open(path)
	t = im.tag_v2
	W = im.size[0]
	tw, th = t[322], t[323]
	offs, counts = t[324], t[325]
	x0, y0 = t[33922][3], t[33922][4]
	px = t[33550][0]
	cx, cy = cfg["centre_stereographic"]
	col, row = int((cx - x0) / px), int((y0 - cy) / px)
	half = int(cfg["boundary_half_size"] / px) + 2
	crop = np.zeros((2 * half, 2 * half), np.float32)
	across = (W + tw - 1) // tw
	with open(path, "rb") as f:
		for ty in range((row - half) // th, (row + half - 1) // th + 1):
			for tx in range((col - half) // tw, (col + half - 1) // tw + 1):
				k = ty * across + tx
				f.seek(offs[k])
				b = np.frombuffer(zlib.decompress(f.read(counts[k])), np.uint8).reshape(th, 4 * tw).copy()
				b = np.cumsum(b, axis=1, dtype=np.uint8).reshape(th, 4, tw).transpose(0, 2, 1)[:, :, ::-1]
				a = np.ascontiguousarray(b).view("<f4").reshape(th, tw)
				for r in range(th):
					gr = ty * th + r
					if row - half <= gr < row + half:
						lo, hi = max(tx * tw, col - half), min(tx * tw + tw, col + half)
						if lo < hi:
							crop[gr - (row - half), lo - (col - half):hi - (col - half)] = a[r, lo - tx * tw:hi - tx * tw]
	lab, n = ndimage.label(crop > 0)
	patches = []
	for k in range(1, n + 1):
		ii, jj = np.nonzero(lab == k)
		sx = x0 + (col - half + jj + 0.5) * px
		sy = y0 - (row - half + ii + 0.5) * px
		X, Z, _ = frame.from_map(sx, sy, np.full(sx.shape, frame.h0))
		inside = (np.abs(X) < cfg["boundary_half_size"]) & (np.abs(Z) < cfg["boundary_half_size"])
		if inside.sum() == 0:
			continue
		patches.append({"hectares": len(ii) * px * px / 1e4, "X": X[inside], "Z": Z[inside]})
	return sorted(patches, key=lambda p: -p["hectares"])


def choose_sun(cfg, frame, world, psr_path):
	s = cfg["sun"]
	el = s["elevation"]
	patches = psr_patches(cfg, frame, psr_path)
	big = [p for p in patches if p["hectares"] >= s["keep_dark_psr_min_hectares"]]
	log(f"PSR patches inside the boundary: {[round(p['hectares'], 1) for p in patches]} ha; keeping dark: {[round(p['hectares'], 1) for p in big]}")
	# Floor points (every 5 m inside each kept patch) and the base / pad
	floor_x = np.concatenate([p["X"] for p in big]); floor_z = np.concatenate([p["Z"] for p in big])
	floor_y = world.height(floor_x, floor_z)
	lit_pts = []
	for a in cfg["protected"]:
		xs = np.arange(a["centre"][0] - a["size"][0] / 2, a["centre"][0] + a["size"][0] / 2 + 0.1, 5.0)
		zs = np.arange(a["centre"][1] - a["size"][1] / 2, a["centre"][1] + a["size"][1] / 2 + 0.1, 5.0)
		gx, gz = np.meshgrid(xs, zs)
		lit_pts.append((gx.ravel(), gz.ravel()))
	lx = np.concatenate([p[0] for p in lit_pts]); lz = np.concatenate([p[1] for p in lit_pts])
	ly = world.height(lx, lz) + 1.0       # a metre up: what stands on the ground
	az_list = np.arange(0.0, 360.0, 1.0)
	floor_h = horizon_angles(world, floor_x, floor_z, floor_y, az_list, start=2.0)
	base_h = horizon_angles(world, lx, lz, ly, az_list, start=2.0)
	sun_radius = 0.27
	rows = []
	for k, az in enumerate(az_list):
		floor_margin = float(np.min(floor_h[k])) - (el + sun_radius)     # > 0: all of the floor dark
		base_margin = (el - sun_radius) - float(np.max(base_h[k]))       # > 0: all of base and pad lit
		rows.append((min(floor_margin, base_margin), az, floor_margin, base_margin, float((floor_h[k] < el + sun_radius).mean())))
	ok = [r for r in rows if r[2] > s["margin_degrees"] and r[3] > s["margin_degrees"]]
	if not ok:
		sys.exit(f"sun at {el} deg: no azimuth keeps the floor dark and the base lit")
	best = max(ok)
	if "azimuth" in s:
		# A chosen azimuth (the settings file's) instead of the one with the most margin: it must still work
		chosen = [r for r in rows if r[1] == float(s["azimuth"])]
		if not chosen or chosen[0] not in ok:
			sys.exit(f"sun at {el} deg, azimuth {s['azimuth']}: the floor isn't dark or the base and pad aren't lit")
		best = chosen[0]
	# How much of the play area the chosen sun lights (every 16 m, at the ground)
	ax = np.arange(-cfg["boundary_half_size"] + 8, cfg["boundary_half_size"], 16.0)
	AX, AZ = np.meshgrid(ax, ax)
	AX, AZ = AX.ravel(), AZ.ravel()
	lit_area = float((horizon_angles(world, AX, AZ, world.height(AX, AZ) + 0.05, [best[1]], start=16.0)[0] < el).mean())
	# Every permanently shadowed patch, not just the big ones: the share of their points the top of the sun reaches
	all_x = np.concatenate([p["X"] for p in patches]); all_z = np.concatenate([p["Z"] for p in patches])
	all_h = horizon_angles(world, all_x, all_z, world.height(all_x, all_z), [best[1]], start=2.0)[0]
	all_lit = float((all_h < el + sun_radius).mean())
	log(f"sun at {el} deg: {len(ok)} azimuths keep the floor dark and the base lit (margin {s['margin_degrees']} deg); {'chosen' if 'azimuth' in s else 'best'} {best[1]:.0f}: floor horizon at least {best[2] + el + sun_radius:.2f} deg, base horizon at most {el - sun_radius - best[3]:.1f} deg; {lit_area * 100:.0f}% of the play area in sunlight; {all_lit * 100:.1f}% of all shadowed patches' points see the sun")
	good = [r[1] for r in ok]
	return {"elevation": el, "azimuth": best[1], "floor_margin_degrees": round(best[2], 2), "base_margin_degrees": round(best[3], 2),
		"azimuths_that_work": runs(good), "kept_dark_psr_hectares": [round(p["hectares"], 2) for p in big],
		"all_psr_hectares": [round(p["hectares"], 2) for p in patches],
		"floor_lit_fraction_at_best": round(best[4], 4), "all_psr_lit_fraction": round(all_lit, 4), "play_area_lit_fraction": round(lit_area, 3)}


def runs(values):
	out = []
	for v in values:
		if out and v - out[-1][1] <= 1.0:
			out[-1][1] = v
		else:
			out.append([v, v])
	return out


def choose_earth(cfg, world, spots, sun):
	e = cfg["earth"]
	base = spots["rover_parking"]
	az = np.arange(e["azimuth_range"][0], e["azimuth_range"][1] + 0.01, 0.5)
	hz = horizon_angles(world, np.array([float(base[0])]), np.array([float(base[2])]), np.array([base[1] + 1.0]), az % 360.0, start=2.0)[:, 0]
	best = int(np.argmin(hz))
	elevation = min(e["elevation_range"][1], float(hz[best]) + e["clearance_degrees"] + 1.0)
	if "elevation" in e:
		# A chosen height within the libration range (the settings file's), clear of the skyline
		elevation = float(e["elevation"])
		if not e["elevation_range"][0] <= elevation <= e["elevation_range"][1] or elevation - float(hz[best]) < e["clearance_degrees"]:
			sys.exit(f"Earth at {elevation} deg: outside the libration range or under the skyline ({float(hz[best]):.1f} deg)")
	visible = elevation - float(hz[best])
	a, el = math.radians(az[best]), math.radians(elevation)
	direction = [math.sin(a) * math.cos(el), math.sin(el), -math.cos(a) * math.cos(el)]
	sa, se = math.radians(sun["azimuth"]), math.radians(sun["elevation"])
	sdir = [math.sin(sa) * math.cos(se), math.sin(se), -math.cos(sa) * math.cos(se)]
	separation = math.degrees(math.acos(max(-1.0, min(1.0, sum(p * q for p, q in zip(direction, sdir))))))
	lit = (1.0 + math.cos(math.radians(180.0 - separation))) / 2.0
	log(f"Earth: azimuth {az[best]:.1f}, elevation {elevation:.1f} deg ({visible:.1f} deg above the horizon from the rover parking); {separation:.0f} deg from the sun: {lit * 100:.0f}% lit")
	return {"azimuth": float(az[best]), "elevation": elevation, "direction": direction, "horizon_degrees": float(hz[best]),
		"sun_separation_degrees": round(separation, 1), "lit_fraction": round(lit, 3),
		"horizon_by_azimuth": {f"{a:.1f}": round(float(h), 2) for a, h in zip(az, hz)}}


def previews(cfg, heights, world_tiers, play_horizon, spots, sun):
	out = cfg["preview_dir"]
	h = heights["play"]
	spacing = cfg["tiers"][0]["metres_per_pixel"]
	shade = hillshade(h, spacing, sun_az=sun["azimuth"], sun_el=35.0)
	img = (np.stack([shade] * 3, -1) * 220 + 20)
	gz, gx = np.gradient(h, spacing)
	slope = np.degrees(np.arctan(np.hypot(gx, gz)))
	for lim, col in ((15, (255, 200, 0)), (25, (255, 110, 0)), (40, (230, 0, 0))):
		m = slope > lim
		img[m] = img[m] * 0.5 + np.array(col) * 0.5
	Image.fromarray(img.astype(np.uint8)[::2, ::2]).save(os.path.join(out, "play_slopes.png"), optimize=True)
	# Lit by the chosen sun, with the horizon maps
	Xs, Zs, Ys, ang = play_horizon
	k = 0.0   # the horizon maps start at the sun's azimuth
	k0 = int(math.floor(k)) % AZIMUTHS
	k1 = (k0 + 1) % AZIMUTHS
	f = k - math.floor(k)
	horizon = ang[k0] * (1 - f) + ang[k1] * f
	lit = np.clip((sun["elevation"] - horizon) / 0.53 + 0.5, 0, 1)
	sh = hillshade(Ys, Xs[0, 1] - Xs[0, 0], sun_az=sun["azimuth"], sun_el=sun["elevation"]) * lit
	Image.fromarray((np.clip(sh * 2.5, 0, 1) * 255).astype(np.uint8)).save(os.path.join(out, "play_sunlit.png"), optimize=True)
	for half, sp, Y in world_tiers[1:]:
		pass
	near = world_tiers[1][2]
	ns = hillshade(near, world_tiers[1][1])
	Image.fromarray((ns * 230 + 20).astype(np.uint8)).save(os.path.join(out, "near_hillshade.png"), optimize=True)
	log(f"previews in {out}")


if __name__ == "__main__":
	main()
