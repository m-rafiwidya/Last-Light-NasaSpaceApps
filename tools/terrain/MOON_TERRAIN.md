# Moon terrain plan

Replace the Moon level's flat 512 m placeholder (`game/src/levels/moon_level.tscn`, `Ground`) with real
lunar south pole terrain: a 1 km x 1 km play area at real scale (1 unit = 1 m), a coarser ring of real
terrain out to the horizon, and a boundary. **Status: built** (decisions and findings first; the original plan
follows). Everything was measured on this machine (MacBook Pro M4, 16 GB, Godot 4.7.2) unless it
says otherwise.

## Decisions (approved) and what the build found

1. **Site: Site01 Connecting ridge.** Shackleton is not visible from the base: towards it (azimuth
   71 from the play centre, rim 11.7-32.7 km away) the skyline is the local ridge 1.3 km away, 7
   degrees up. The ring includes the whole crater anyway (the 128 m tier reaches 32.8 km; its far
   rim is at 31.6 km).
2. **Play area at 0.5 m**, in 64-cell chunks with automatic LODs; **Low (1 m)** is a graphics
   setting (Settings > Video > Terrain Detail, saved in user://settings.cfg; also
   `-- terrain_detail=low`). Low uses every other sample for both mesh and collision, so the wheels
   always stand on what is drawn.
3. **Sun 9 degrees up, azimuth 39.** Only azimuths 32 to 45 keep all of the 7.9 ha permanently
   shadowed crater's floor dark with the base and pad lit; 39 has the most margin (the floor's
   lowest horizon 9.49 degrees against 9.27 for the top of the sun, the base and pad's highest
   4.6-5.6 against 8.73). The ground to the north-east is higher, so at this sun only 35% of the
   play area is in direct sunlight (95% at the old azimuth 160). Earth from this site sits near
   longitude 0's direction: azimuth -3.5, 0.1 degrees up, 2.5 degrees above the skyline seen from
   the base, 43 degrees from the sun, so a 14% crescent.
4. **Parked rover creep: fixed first** (commit "Parked rover and loose parts hold still on
   slopes"): tyre static friction, Coulomb rolling resistance, an automatic brake; loose parts get
   regolith rolling resistance.
5. **The 1-second stall: found and fixed.** macOS (Metal) blocks for up to a second per frame
   waiting for a frame buffer while the window can't be shown, only with vsync on; the game now
   renders without vsync, capped at 30 fps, while unfocused.

### As built (differences from the plan below)

- **Tiers:** play 0.5 m to +-512 m (2049 x 2049), near 8 m to +-4096 m, mid 128 m to +-32768 m
  (from LDEM_875S_20M), far 512 m to +-131072 m (from LDEM_85S_40M); each a multiple of the next
  one's spacing, so an outer tier leaves out exactly the cells under the inner one; skirts (2, 40,
  400 m) hide the joins. The PDS mosaics match the 5 m data: offsets +0.31 m / +1.07 m, RMS 1.9 m
  / 10 m. The procedural detail fades out over the play tier's last 22 m (past the boundary).
- **Detail:** RMS slope 3 degrees below 10 m, craters 1.5-20 m with depth ratio 0.04-0.11 (36609
  of them), 9427 rocks (1668 of 0.2 m and up with collision). Inside the boundary 2.8% of the
  ground is over 25 degrees, 0.63% over 30, 0.014% over 40 (max 51 at 0.5 m).
- **Horizon maps** start at the sun's azimuth, so the sun's own direction needs no interpolation.
- **Camera far plane** 200 km on the Moon (`RoverLevel.camera_far`); near planes grow to far / 10^7
  (2 cm here): with 1 mm Godot's light culler failed every frame.
- **Loading:** meshes are built by low-priority worker tasks that only compute arrays (no
  RenderingServer calls, never every thread: Jolt runs its jobs on the same pool; the first
  version deadlocked the loading screen), turned into meshes on the main thread and cached in
  user://. First load 4.5 s, later 1-2.5 s. SceneLoader gives up waiting after 120 s.
- **Tests:** the test drive holds about 2.4 m/s (`-- drive_speed=5` for 5 m/s). At 4-6 m/s
  downhill the rover leaves the ground over crater rims and lands at 2-3 m/s. With Earth's
  suspension that went past its 0.30 m of travel (wheels up to 28 cm in the ground); the Moon
  level's own suspension (`rover_suspension`, README Level gravity) takes it, checked by
  `tests/test_rover_landing.gd`.

---

## 1. Data and site

### 1.1 Source: LOLA 5 m/px south pole site DEMs (NASA GSFC PGDA)

NASA Goddard's Planetary Geodesy Data Archive publishes LOLA elevation maps at **5 m/pixel** for the
south pole landing-site regions:
[product 78](https://pgda.gsfc.nasa.gov/products/78), files at
<https://pgda.gsfc.nasa.gov/data/LOLA_5mpp/>. Reference: Barker et al. (2021), *Improved LOLA elevation
maps for south pole landing sites*, Planetary & Space Science 203, 105119,
doi:10.1016/j.pss.2020.105119.

Per site: `_surf.tif` (heights), `_slp.tif` (slope), `_ldec.tif` (LOLA shots per pixel),
`_toterr.tif` / `_slperr.tif` (uncertainties), point clouds and 100 Monte Carlo clones. Every GeoTIFF
is float32, 5 m/px, **south polar stereographic on a 1737.4 km sphere, true scale at the pole**
(GeoKeys: origin -90, scale 1, semi-axes 1737400 m), pixel-registered. **Heights are metres above
that 1737.4 km sphere** (README: "surface height Z (meters)"; the GeoTIFF's sphere and the values,
-523 to +1959 m at Site01, match the convention of the PDS 20 m product, whose label defines height
as radius minus 1737.4 km; the pipeline's overlap check (2.1) confirms it numerically before anything
is built).

| Site | `_surf.tif` bytes | Pixels | Notes |
|---|---|---|---|
| Site01 Connecting ridge | 40,980,810 | 3200 x 3200 (16 x 16 km) | **recommended** |
| Site04 Shackleton rim | 40,980,806 | 3200 x 3200 | runner-up |
| Site07 Peak near Shackleton | 40,980,808 | 3200 x 3200 | |
| Site11 de Gerlache rim | 40,980,806 | 3200 x 3200 | |
| Site20 Leibnitz beta plateau | 40,980,802 | 3200 x 3200 | 85.4 S, no shadowed crater near flat ground |
| Site23 Malapert massif | 70,586,804 | 4200 x 4200 | 86 S, same |

The other products of a site are the same size as its `_surf.tif` (point clouds 24-61 MB). All six
`_surf.tif` files are downloaded (in `tools/terrain/raw/`, 276 MB, gitignored); each matches the
server's byte count. Nothing over 1 GB was downloaded. PGDA's pole-wide mosaics are 2.7 GB (20 m) and
5.1 GB (10 m), so I left them alone; the play area doesn't need them.

### 1.2 How the site was chosen

`site_survey` (to become part of the pipeline, section 2) ran over all six tiles:
- **flat ground:** 100 m windows where 95% of the 5 m slopes are under 5 degrees;
- **permanent shadow (proxy):** horizon maps on a 40 m grid, 72 azimuths, with the Moon's curvature;
  a pixel whose horizon is above the highest sun at its latitude (1.54 degrees axial tilt + distance
  from the pole + 0.27 sun radius) in every direction never sees the sun. Only horizons inside the
  16 km tile are known, so this finds real shadow but misses some (Shackleton's floor, whose far rim
  is off the tile);
- **sunlit:** share of azimuths with a horizon under 0.5 degrees.

Then checked against NASA's own permanent-shadow map,
[PGDA product 90](https://pgda.gsfc.nasa.gov/products/90) `LPSR_80S_20MPP_ADJ.TIF` (20 m/px,
154,221,202 bytes, byte count verified, read tile by tile).

### 1.3 Recommended: Site01, Connecting ridge

The ridge between Shackleton and de Gerlache, one of the six regions PGDA mapped for landing sites.

| | |
|---|---|
| Play-square centre | stereographic x -13347.5 m, y -13552.5 m = **89.3727 S, 224.56 E**; Site01 pixel (row 1910, col 1130); 1668.6 m above the sphere |
| Square | 1024 x 1024 m, grid-aligned (+X = stereographic +x, +Z = stereographic -y) |
| Base | flat 100 m patch at x -250, z -350 (m from the square centre): mean slope 2.5, p95 4.8, max 7.5 degrees, 3.8 m of relief; near the highest ground in the square |
| Permanently shadowed crater | **7.9 ha**, about 320 m across, centred x +192, z +384 (NASA map; my proxy: 7.2 ha at +180, +366); floor 110-130 m below the base, walls under 31 degrees at 5 m: the rover can drive in and out |
| Other shadowed patches in the square | 1.8, 0.5, 0.4 and 0.4 ha (NASA map); all match the proxy within about 30 m |
| Slopes (5 m baseline) | 51% under 10, 84% under 15, 99.7% under 25 degrees; max 31.3 |
| Relief | 223 m (1588 to 1812 m) |

Why this one: a sunlit ridge with a 100 m flat base and a real permanently shadowed crater that the
rover can reach and climb out of, all inside the play area.

**Runner-up, Site04 Shackleton rim:** the square centred 300 m west of a flat patch right on the rim
(89.770 S, 206.17 E): 99.4% under 25 degrees, max 32.8. From the base you look into Shackleton (21 km
across, 4 km deep, permanently shadowed), the most famous view at the pole. But the crater wall is
over 35 degrees, so the shadowed ground is out of reach: a view, not a destination.

Previews (scratch, not committed): survey maps with hillshade, slope classes and shadow for each tile,
and 1.6 km close-ups of both candidates. They become pipeline outputs (section 2.5).

---

## 2. Pipeline: `tools/terrain/build_moon_terrain.py`

Python 3 with numpy, scipy and Pillow (all already installed here; no GDAL). Pillow reads the float32
GeoTIFFs and their geo tags; the big tiled TIFFs are read tile by tile (deflate + floating-point
predictor). Run from the repo root; settings in `tools/terrain/moon_site01.json` (site file, centre,
size, spacing, seed, protected areas).

### 2.1 Fetch and verify (`--fetch`)

Downloads into `tools/terrain/raw/` (gitignored), never over 1 GB, resumable. Checks each file's
byte count against the server's, its georeferencing tags (projection, 1737400 m sphere, pixel size,
extent) and value range. Ring DEMs (2.3) are taken from the **NASA PDS Geosciences Node**
(pds-geosciences.wustl.edu); the same files are on the LOLA team's archive (imbrium.mit.edu) with
identical byte counts. Neither PGDA nor PDS publish checksums for these, so the pipeline also compares
heights where datasets overlap (5 m site tile vs 20 m mosaic: the mean offset and RMS difference are
reported and the build fails above a set limit).

### 2.2 Exact conversion to game metres

For each output grid point (east e, south s in metres from the play centre):
1. tangent-plane point -> direction from the Moon's centre (local east/north/up frame at the centre);
2. direction -> latitude/longitude -> polar stereographic x, y (sphere 1737.4 km, true scale at the pole);
3. sample the DEM there (bicubic), giving height h above the sphere;
4. surface point P = (1737400 + h) * direction; its tangent-plane coordinates (e', s') and height
   y = (P - P0) . up, where P0 is the surface point at the play centre;
5. correct the direction by (e - e', s - s') and repeat until it moves less than 1 mm (2-3 passes).

So x/z are true metres along the ground, and y includes the Moon's curvature: 7 cm at the play
square's edge, 18 m at 8 km, 720 m at 50 km. The projection's scale error (1.0003 at 26 km from the
pole, 30 cm per km) is gone with it.

### 2.3 Data at three ranges

| Range from play centre | Source | Output spacing |
|---|---|---|
| play square, 1024 m | Site01 5 m tile | 0.5 m (decision 3) |
| ring to the tile edge, about 6-10 km | Site01 5 m tile | 10 m |
| far ring to about 130 km (the horizon from 1.8 km up reaches 80 km, distant massifs beyond) | `ldem_875s_20m.img` (115,034,112 bytes, int16 x 0.5 m above 1737.4 km, 7584 x 7584, 20 m/px), then `ldem_85s_40m.img` (115,034,112 bytes, 40 m/px) beyond 76 km | 50 m, then 200 m |

### 2.4 Rover-scale detail on top of the real shape

The LOLA 5 m grid is really about 10-20 m effective resolution (track spacing), so detail is added
only below about 10 m, and never moves the real shape:
- **gentle bumps:** fractal noise (Hurst exponent about 0.9, as for lunar roughness at metre scale),
  band-limited to under 10 m, a few cm RMS at 1 m;
- **small craters, 1 to 20 m across:** placed with the lunar equilibrium density (cumulative
  N(>D) = 0.079 D^-2 per km^2, D in km: about 800 over 10 m per km^2), bowl depth 0.1-0.2 D (older ones
  shallower), raised rim 0.04 D, fading ejecta; walls kept under 30 degrees in the play area;
- **rocks:** not in the heightmap (a 0.5 m grid can't hold them); placed as instances by Godot from a
  committed list (2.5), power-law sizes, more of them on crater rims;
- **protected areas:** the landing pad and the base spots (6.3) are graded to their mean plane (max
  2 degrees), blended over 10 m, with no craters or rocks.

Deterministic: a fixed seed in the settings file.

### 2.5 Outputs (committed, each under 50 MB) in `game/res/terrain/moon_site01/`

| File | Contents | Size |
|---|---|---|
| `play.r16` | 2049 x 2049 little-endian uint16, 0.5 m/px | 8.4 MB |
| `ring.r16` | 10 m/px, about 1600 x 1600 | 5.1 MB |
| `far.r16` | 50 m and 200 m tiers | about 10 MB |
| `terrain.json` | per file: size, metres per pixel, origin, `height = offset + value * scale` (play: about 3.5 mm per step), the site centre (lat/lon, stereographic x/y), source files with byte counts, settings and seed | small |
| `horizon.png` | play area at 2 m, 16 azimuths of horizon elevation (for distant shadows, 3.4) | about 4 MB |
| `rocks.json` | position, size, rotation, seed per rock | small |
| `previews/` | hillshade, slope classes (15/25/40 degrees), shadow, base layout | small |

16-bit raw rather than 16-bit PNG or EXR: Godot's `Image` has no 16-bit integer format (a 16-bit
PNG would lose precision), and EXR loading isn't in exported games by default (to be confirmed when
building; raw needs no loader either way). `.r16` and `.json` go in the export filter as non-resource files. `tools/terrain/raw/`
is already in `.gitignore`.

---

## 3. The map edge

### 3.1 Ring

Concentric meshes outside the play square from `ring.r16` and `far.r16`, same conversion (curvature
included, which is what makes the horizon fall away naturally). Each tier overlaps the next by one
cell and hangs a 2 m skirt under its inner edge, so there are no cracks; the ring is pushed 3 m down
under the play square so the play mesh always wins. The rover and player cameras' far plane goes from
500 m to about 150 km (Godot 4.7 uses reverse depth, so precision holds); the sun's shadow cascades
stay at 500 m.

### 3.2 Boundary

- **Walls on their own layer:** four invisible walls at the square's edge, on a new collision layer 7
  "Boundary". The player and rover bodies add it to their masks; the wheels' ground check
  (`RunningGear` `ground_mask`, layers 1 and 3) doesn't, so a wheel next to a wall never mistakes it
  for ground. The wall top is 50 m above the highest terrain (jumps reach 1.2 m).
- **Warning first:** within 20 m of the edge the HUD says the boundary is near; survey stakes every
  50 m along the line make it visible in the world.
- **Thrown things:** a coarse `HeightMapShape3D` (10 m) under the ring catches anything thrown over
  the wall; a kill plane 3 km below respawns anything that still falls.

### 3.3 Spawn and test layout

Existing tests use the Moon's flat ground (`test_level_gravity.gd` at fixed coordinates, ramp at
-180, 0, 0). They will build their own flat floor away from the terrain instead (a large
`StaticBody3D` box 5 km below the level), so their measurements stay comparable.

### 3.4 Shadows beyond 500 m

The cascades only reach 500 m, so the shadow a distant rim casts would be missing (for example, the
crater floor seen from the base 500 m away would be lit). The pipeline bakes `horizon.png`
(horizon elevation per 2 m texel, 16 azimuths) and the terrain shader darkens the sun's light when it
is below the horizon at the sun's azimuth (soft over the sun's 0.5 degree disc). Near the camera the
cascades take over, so close shadows stay sharp.

---

## 4. Godot 4.7: Terrain3D vs built-in

Both were tried against the same 1 km of Site01 (1 m spacing).

| | Terrain3D 1.0.2 (May 2026) | Built-in meshes + `HeightMapShape3D` |
|---|---|---|
| Godot 4.7 support | releases say "4.4-4.6+"; the 1.0.2 notes: "I don't know about 4.7". Loads on 4.7.2, prints a deprecation warning (`instance_reset_physics_interpolation`), and **crashed (signal 11, inside `libterrain`) with `region_size = 1024`**, headless and windowed; worked at the default 256 | engine features |
| Rover wheel queries (2000 random points) | rays within 0.2 mm (max 9.7 mm), cylinder `cast_motion` + `get_rest_info` stops 1.9 cm median above the ground, 13.8 us/query | identical: 0.2 mm (max 13 mm), 1.9 cm, 13.9 us/query (Terrain3D also uses `HeightMapShape3D` underneath) |
| Headless tests | works (with a camera and a data directory set) | works |
| Collision away from the camera | needs `collision_mode` full, not dynamic (dynamic only builds around the camera, so parked rovers and the parts pile would fall through) | always |
| Ring to the horizon | one vertex spacing per terrain, so the 10-200 m ring is a separate mesh anyway | same code as the play area |
| Repo / platforms | 42 MB release zip with native binaries per platform | nothing extra |
| Editor sculpting, texture painting | yes | no (not needed: data-driven) |

**Recommendation: built-in.** Same physics, no unsupported plugin with a crash on 4.7.2, one code
path for play area and ring, nothing native to ship. Terrain3D's clipmap would use less memory; if
load time or memory hurt (section 7), a small GPU clipmap of our own is the upgrade path. Terrain3D's
frame rate was not measured in the game, because it was ruled out on compatibility first.

### 4.1 How the built-in version is built

- **Visual:** the play area in 64 x 64-cell chunks (32 m at 0.5 m) with Godot's automatic mesh LOD
  (`ImporterMesh.generate_lods`), normals from the heights; the ring in 64-cell chunks at its spacing.
  Built on a worker thread during the loading screen and cached in `user://` (keyed by the data's
  hash). Baked meshes are about 150 MB, too big to commit.
- **Triangles must match the collision:** Jolt's heightfield splits each cell from (1,0) to (0,1).
  Measured: that diagonal is within 0.1 mm of the physics; the other one is up to 2.5 cm off, which
  would fail `test_wheel_contact.gd`'s 1 cm wheel-in-ground check. The prototype used the wrong one.
- **Collision:** one `HeightMapShape3D` of 2049 x 2049 (2^11 + 1) scaled to 0.5 m on layer 1 (1025 x
  1025 at 1 m also tested), plus the coarse ring catcher (3.2).
- **Tests:** `test_wheel_contact.gd`'s invariants (no wheel airborne within 5 mm of something to
  stand on, none in contact inside the terrain, no wheel mesh over 1 cm in the ground) become a helper
  that a new `test_terrain_drive.gd` reuses on scripted drives over the real terrain: the base, a 25
  degree slope, into and out of the shadowed crater, along the boundary wall (it must stop the rover
  and the player).

---

## 5. Regolith material (procedural, no photos)

One spatial shader on the terrain, world-space coordinates, no textures:
- **Albedo:** grey about 0.12-0.18 (south pole highlands), mottled by noise at about 100 m, 5 m and
  0.5 m; slightly brighter on steep slopes (fresh material) and around small fresh craters (from a
  crater mask the pipeline writes alongside the heights). No colour beyond a hint of warm grey.
- **Detail normals:** noise normal perturbation at decimetre and centimetre scales, faded out with
  distance (no visible tiling: several octaves, rotated).
- **Lighting:** specular off (as the placeholder ground now); a Lommel-Seeliger style diffuse term
  with a mild opposition surge in a custom `light()` (regolith doesn't darken towards grazing light
  the way Lambert does, and it brightens when the sun is behind you); the horizon shadow from 3.4.
- **Rocks:** a few procedural rock meshes made with the rover kit's Blender tooling
  (`tools/blender/scripts/`) and the same shader; rocks of 0.1 m and up get convex collision on layer
  1, so wheels drive over them.

---

## 6. Rover limits and the base layout

### 6.1 Steepest slope (measured: Moon level, 1.62 m/s^2, traction control on)

Long ramps per slope; full throttle from a standstill 2 m up the slope, climbing 8 m:

| Slope | Climbs 8 m in | Speed mid-climb | Roll-back at start | Across the slope at 30% (8 s) |
|---|---|---|---|---|
| 15 | 8.6 s | 5.0 m/s | 0 | 15.0 m across, 0.3 m down |
| 25 | 8.4 s | 3.2 m/s | 0.02 m | 14.7 m, 0.7 m down |
| 30 | 9.2 s | 2.5 m/s | 0.04 m | 14.3 m, 1.2 m down |
| 35 | 11.3 s | 1.8 m/s | 0.07 m | 13.7 m, 2.1 m down |
| 40 | 19.8 s | 1.0 m/s | 0.22 m | 12.7 m, 3.5 m down |
| 45 | **fails** (slides back to the bottom) | | | 12.7 m, 7.4 m down |

**The sim climbs up to 40 degrees.** That's more than a real rover on loose regolith (the Apollo LRV
was rated for 25; slopes over about 35 degrees are past regolith's angle of repose and rare). Design
rule: keep the base area and its routes under 15, treat 25-40 as hard but drivable, over 40 as
impassable. No rollover in any cross-slope run (tilt off the slope stayed under 1 degree).

### 6.2 Flag: a parked rover creeps downhill

No throttle, measured over 30 s: **1.8 m at 2 degrees, 4.6 m at 5, 9.2 m at 10**. The tyre model has
no static friction (README section 15.3, "a stationary robot can creep slowly on a slope"); on real
terrain a parked rover will wander off the base. A parking brake (hold the wheels when stopped with no
throttle) is a prerequisite.

### 6.3 Flat spots (play coordinates: x east, z south, metres from the square's centre)

From the 1 m crop (bicubic from 5 m), before procedural detail; the spots are then protected (2.4):

| Use | Size | Centre x, z | Ground | Max / mean slope | Relief |
|---|---|---|---|---|---|
| Landing pad | 100 m | -246, -357 | +49.8 m | 9.3 / 2.7 | 3.8 m (graded flat) |
| Player spawn | 6 m | -335, -286 | +50.1 m | 0.8 / 0.5 | 0.06 m |
| Rover parking | 10 m | -351, -300 | +50.2 m | 1.8 / 1.1 | 0.20 m |
| Parts pile | 14 m | -328, -302 | +49.9 m | 2.0 / 1.6 | 0.46 m |

Heights are relative to the square's centre. Spawn, rover and pile sit together just west of the pad
(about 100 m from its middle; real pads sit kilometres from a base because of plume ejecta, so this is
a compromise for a 1 km map).

### 6.4 Flags near the base

- **Too steep:** one spot over 40 degrees in the whole square, at x -22, z -65 (42.2 degrees at 1 m,
  a few m^2, 370 m from the pad); 0.1% of the square is over 30, 0.6% over 25. Within 300 m of the
  pad, 0.09% is over 25. The 5 m data smooths: real slopes at 1 m are steeper, and procedural craters
  must keep their walls under 30 near the base.
- **Sun vs permanent shadow:** for the crater floor (heights from the 1 m crop), the fraction in
  direct sun: sun at 1.5 degrees, 0% at azimuths 0, 100, 160 and 220; at 9 degrees, **10% at azimuth
  160 (the level's current sun)**, 0-1% at 0, 100 and 220. See decision 2.
- **Earth:** from this site Earth is towards longitude 0, which is stereographic +y, so the game's -Z
  (azimuth 0), within the libration range of about 7 degrees in elevation (often low, sometimes below
  the ridge). `RoverLevel.earth_direction` should move from azimuth 45 to about 0 to match the site.

---

## 7. Frame rate (measured)

A scratch prototype built the real Site01 terrain inside the Moon level (built-in meshes and LOD,
`HeightMapShape3D`, flat grey material, the ring at 10 m out to the 16 km tile's edge, camera far plane
20 km), then the assembled rover circled at full throttle with headlights on, 10 s per view after 2 s
of warm-up, 1920x1080:

| Play area | Triangles (LOD 0, play + ring) | Build in GDScript | Vsync off: chase / mast | Vsync on |
|---|---|---|---|---|
| 1 m | 2.1 M + 5.1 M = 7.2 M | 4.3 s | 252 / 234 fps, p99 6.9 ms | at the display's cap, p99 under 11.3 ms |
| 0.5 m | 8.4 M + 5.1 M = 13.5 M | 7.9 s | 175 / 165 fps, p99 8.9 ms | at the cap, p99 under 8.9 ms |

The window ran on a display capping at 145-165 Hz during these runs (earlier work measured 120 on the
built-in panel); either way there is headroom. The far ring (2.3) and the procedural material will
cost more; the target is unchanged: steady at the display's rate with vsync, p99 under 12 ms. Build
time is why meshes are built on a worker thread and cached (4.1).

**Open issue:** one vsync run of four (1 m terrain) had a single 1.03 s frame at the start of the
chase phase, the same signature seen once before (with the 8192 shadow atlas). Not reproduced in the
other runs; to be chased with the final build (shader pipeline compile or the Metal drawable
timeout are the suspects).

---

## 8. Order of work, once approved

1. Parking brake (6.2), with a test.
2. Pipeline: fetch/verify, conversion, detail, outputs, previews (sections 1-2); commit the outputs.
3. Terrain node in the Moon level: chunked meshes on a worker thread, collision, ring, boundary
   (3-4); move the tests' flat ground away (3.3); `test_terrain_drive.gd`.
4. Material and horizon shadows (3.4, 5); rocks.
5. Base layout (6.3), sun and Earth for the site (decision 2, 6.4); previews from the chase and
   mast cameras; frame rate check against section 7; README.
