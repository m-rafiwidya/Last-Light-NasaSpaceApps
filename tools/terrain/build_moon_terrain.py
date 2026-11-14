#!/usr/bin/env python3
"""Builds the Moon level's terrain from NASA LOLA elevation data (see MOON_TERRAIN.md).

    python3 tools/terrain/build_moon_terrain.py [--fetch] [config.json]

Run from the repo root. Needs numpy, scipy and Pillow (no GDAL). Steps:
  1. --fetch: downloads the sources into the raw folder (gitignored), resumable; every run checks
     their byte counts and georeferencing.
  2. Exact conversion to game metres: for each output sample (X east-ish, Z south-ish, metres along
     the local tangent plane at the play centre) finds the surface point that projects there, so
     X / Z are true distances and Y includes the Moon's curvature.
  3. Four tiers (play 0.5 m, near 8 m, mid 128 m, far 512 m), aligned so each outer tier's cells
     under the inner tier can be dropped exactly. Outer tiers from the PDS polar mosaics are shifted
     to match the 5 m site data where they overlap (the offset is reported and checked).
  4. Rover-scale detail on the play tier only below 10 m: fractal roughness, small craters (lunar
     equilibrium density), rocks (instances, not in the heightmap); protected areas graded flat.
  5. Horizon maps (16 azimuths) per tier for shadows beyond the sun's shadow cascades; the sun
     azimuth that keeps the permanently shadowed crater floor dark at the configured elevation
     with the base and the pad lit; Earth's position above the local horizon.
  6. Outputs: 16-bit heightmaps (.r16), horizon PNGs, rocks, an albedo map, terrain.json, previews.
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

def fetch(cfg):
	raw = cfg["raw_dir"]
	os.makedirs(raw, exist_ok=True)
	for key, src in cfg["sources"].items():
		path = os.path.join(raw, os.path.basename(src["url"]))
		have = os.path.getsize(path) if os.path.exists(path) else 0
		if have == src["bytes"]:
			continue
		if src["bytes"] > 1_000_000_000:
			sys.exit(f"{key}: {src['bytes']} bytes is over 1 GB; download it by hand after checking")
		log(f"fetching {src['url']} ({have} of {src['bytes']} bytes)")
		request = urllib.request.Request(src["url"], headers={"Range": f"bytes={have}-"} if have else {})
		with urllib.request.urlopen(request, timeout=120) as response, open(path, "ab" if have else "wb") as out:
			while chunk := response.read(1 << 20):
				out.write(chunk)


def check_sources(cfg):
	report = {}
	for key, src in cfg["sources"].items():
		path = os.path.join(cfg["raw_dir"], os.path.basename(src["url"]))
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
	return report


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


class LocalFrame:
	"""Tangent plane at the play centre: X along the stereographic +x, Z along -y, Y up."""

	def __init__(self, cx, cy, height_at):
		self.up = stereo_to_dir(np.array(cx), np.array(cy))
		ex = stereo_to_dir(np.array(cx + 1.0), np.array(cy)) - self.up
		ey = stereo_to_dir(np.array(cx), np.array(cy + 1.0)) - self.up
		ex -= ex.dot(self.up) * self.up
		ey -= ey.dot(self.up) * self.up
		self.ex = ex / np.linalg.norm(ex)
		self.ez = np.cross(self.ex, self.up)            # X x Y = Z
		if self.ez.dot(ey / np.linalg.norm(ey)) > -0.999:
			sys.exit("local frame: stereographic +y is not world -Z")
		self.h0 = float(height_at(np.array([cx]), np.array([cy]))[0])
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
			sx, sy = dir_to_stereo(d)
			h = height_at(sx, sy)
			s = (R_MOON + h)[..., None] * d - self.origin
			gx, gz = s @ self.ex, s @ self.ez
			tx += X - gx
			tz += Z - gz
		Y = s @ self.up
		if not np.isfinite(Y).all():
			sys.exit("exact conversion: non-finite heights")
		return Y, float(np.max(np.hypot(X - gx, Z - gz)))

	def from_stereo(self, sx, sy, h):
		d = stereo_to_dir(sx, sy)
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
	raw = lambda key: os.path.join(cfg["raw_dir"], os.path.basename(cfg["sources"][key]["url"]))
	os.makedirs(cfg["out_dir"], exist_ok=True)
	os.makedirs(cfg["preview_dir"], exist_ok=True)

	log("reading the site DEM")
	site = SiteDEM(raw("site"))
	cx, cy = cfg["centre_stereographic"]
	frame = LocalFrame(cx, cy, site.sample)
	log(f"play centre: {frame.lat_lon[0]:.4f} N, {frame.lat_lon[1]:.2f} E, {frame.h0:.1f} m above the 1737.4 km sphere")

	calibration = {}
	polar = {}
	for t in cfg["tiers"]:
		if t["source"].startswith("polar") and t["source"] not in polar:
			src = cfg["sources"][t["source"]]
			log(f"reading {t['source']}")
			dem = PolarDEM(raw(t["source"]), src, t["metres_per_pixel"] / src["metres_per_pixel"] / 2.0)
			calibration[t["source"]] = dem.calibrate(site, t["source"])
			polar[t["source"]] = dem

	tiers_out, world_tiers, heights = [], [], {}
	detail = cfg["detail"]
	extras = {}
	for t in cfg["tiers"]:
		spacing, half = t["metres_per_pixel"], t["half_size"]
		n = int(round(2 * half / spacing)) + 1
		axis = -half + np.arange(n) * spacing
		X, Z = np.meshgrid(axis, axis)
		if t["source"] == "site":
			smooth = None if spacing <= site.px else spacing / site.px / 2.0
			fn = (lambda sx, sy: site.sample(sx, sy)) if smooth is None else (lambda sx, sy, s=smooth: site.sample(sx, sy, smooth=s))
		else:
			fn = polar[t["source"]].sample
		log(f"tier {t['name']}: {n} x {n} at {spacing} m (exact conversion)")
		Y, miss = frame.to_world(X, Z, fn)
		log(f"  converged to {miss * 1000:.2f} mm; heights {Y.min():.1f} .. {Y.max():.1f} m")
		if t.get("detail"):
			# No detail on protected ground, and none at the tier's edge (it fades out over the last 22 m,
			# past the boundary), so the play tier meets the smooth ring without a step
			edge = np.maximum(np.abs(X), np.abs(Z))
			protect = np.maximum(protection_mask(X, Z, cfg["protected"]), np.clip((edge - (half - 22.0)) / 12.0, 0.0, 1.0))
			before = Y.copy()
			Y += roughness(n, spacing, detail, rng) * (1.0 - protect)
			craters, fresh, crater_count = add_craters(Y, -half, spacing, detail, rng, protect)
			log(f"  {crater_count} craters {detail['crater_min_diameter']}-{detail['crater_max_diameter']} m")
			extras["grading"] = grade(Y, X, Z, cfg["protected"], before)
			rocks = make_rocks(Y, -half, spacing, detail, rng, protect, craters)
			rocks.tofile(os.path.join(cfg["out_dir"], "rocks.f32"))
			extras["rocks"] = {"file": "rocks.f32", "count": len(rocks), "fields": ["x", "ground_y", "z", "size", "yaw", "shape"],
				"collision_min_size": detail["rock_collision_min_size"], "with_collision": int((rocks[:, 3] >= detail["rock_collision_min_size"]).sum())}
			log(f"  {len(rocks)} rocks, {extras['rocks']['with_collision']} of {detail['rock_collision_min_size']} m and up")
			albedo = np.clip(128 + fresh[::2, ::2] * 127, 0, 255).astype(np.uint8)
			Image.fromarray(albedo, "L").save(os.path.join(cfg["out_dir"], "freshness_play.png"), optimize=True)
			extras["freshness"] = {"file": "freshness_play.png", "metres_per_pixel": spacing * 2, "encoding": "0.5 + 0.5 * freshness"}
			gz, gx = np.gradient(Y, spacing)
			slope = np.degrees(np.arctan(np.hypot(gx, gz)))
			inner = (np.abs(X) <= cfg["boundary_half_size"]) & (np.abs(Z) <= cfg["boundary_half_size"])
			extras["play_slopes"] = {f"over_{s}": round(float((slope[inner] > s).mean() * 100), 3) for s in (15, 25, 30, 40)}
			extras["play_slopes"]["max"] = round(float(slope[inner].max()), 1)
			log(f"  slopes inside the boundary (% over 15/25/30/40): {extras['play_slopes']}")
		heights[t["name"]] = Y
		info = save_r16(os.path.join(cfg["out_dir"], f"{t['name']}.r16"), Y)
		log(f"  r16: {info['scale'] * 1000:.2f} mm per step, worst rounding {info['max_error_m'] * 1000:.2f} mm")
		tiers_out.append({"name": t["name"], "file": f"{t['name']}.r16", "size": n, "metres_per_pixel": spacing,
			"half_size": half, "height_min": info["min"], "height_scale": info["scale"], "source": t["source"]})
		world_tiers.append((half, spacing, Y))

	world = World(world_tiers)

	# Spots: ground heights
	spots = {}
	for name, (x, z) in cfg["spots"].items():
		spots[name] = [x, float(world.height(np.array([float(x)]), np.array([float(z)]))[0]), z]

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
		"centre": {"stereographic_m": cfg["centre_stereographic"], "lat": frame.lat_lon[0], "lon_east": frame.lat_lon[1],
			"height_above_1737400_m": frame.h0},
		"axes": "X = polar stereographic +x, Z = -y (towards longitude 180), Y up; metres along the tangent plane at the centre; heights include the Moon's curvature",
		"height_encoding": "height = height_min + uint16 * height_scale (little-endian, row-major, rows along +Z)",
		"tiers": tiers_out,
		"horizons": {"azimuths_degrees": azimuths, "first_azimuth": azimuths[0], "step_degrees": 360.0 / AZIMUTHS,
			"encoding": f"degrees = {HORIZON_MIN} + byte / 255 * {HORIZON_RANGE}",
			"azimuth_convention": "degrees from -Z towards +X", "channels": "file k holds azimuths 4k..4k+3 in R, G, B, A",
			"tiers": horizon_files},
		"boundary_half_size": cfg["boundary_half_size"], "protected": cfg["protected"], "spots": spots,
		"sun": sun, "earth": earth, "calibration": calibration, "sources": sources, **extras,
	}
	json.dump(meta, open(os.path.join(cfg["out_dir"], "terrain.json"), "w"), indent="\t")
	previews(cfg, heights, world_tiers, play_horizon, spots, sun)
	log("done")


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
		X, Z, _ = frame.from_stereo(sx, sy, np.full(sx.shape, frame.h0))
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
