# Moon terrain

Two sites, newest first:
- **Apollo 12 (built, in the Moon level):** decisions and what the build found first, then the
  plan as approved.
- **South pole, LOLA Site01 (built, retired from the level):** the rest of this file, kept as
  history. Its settings file still builds it, byte for byte.

# Apollo 12 terrain

## There is no starter pack

`ASSET_BRIEF.md` describes a `Tandborste-NASA-Moon-Terrain-Starter.zip` (a 257 x 257 crop at
2 m, 36.322 m of relief, float heights and metadata). **It doesn't exist:** the teammate doesn't
have it, and it isn't on this machine. So the brief's starter-pack details (the crop and its span)
don't apply. Used instead: the public product that pack would have come from, the LROC NAC DTM
`NAC_DTM_APOLLO12_E030S3365` (v1.9) and its 2 m orthophoto `NAC_DTM_APOLLO12_M120005333_2M`. The
brief's principles are kept:
- **Exact float heights and scale:** the play tier is the DTM's posts, float32, minus one
  constant, at 2 m.
- **Provenance:** product, version, file hash, pixel window and constant are in `terrain.json`
  `provenance`; the untouched posts are in `play_measured.f32`.
- **Authored changes recorded separately:** in `terrain.json` `authored_changes`.
- **The orthophoto isn't albedo:** it's used only as an approximate brightness pattern.

(The 36.322 m figure matched no 512 m window containing the LM: see section 0 of the plan.)

## Decisions (approved 2026-10-09)

1. **Play area 1 km**, placed to hold the landing site, Surveyor 3 and the whole EVA 2 route.
2. **Sun at the EVA 2 midpoint** (1969-11-20 05:49 UTC, 16.7 degrees), and **the star map aligned
   for that moment**.
3. **No procedural craters** (and no procedural roughness in the heights).
4. Raw downloads live in `tools/terrain/raw/`.
5. The Terrain Detail menu label stays as it is: the settings menu belongs to the UI work.

## As built

- **Play tier:** DTM posts lines 551-1063, samples 1601-2113 (0-based), 513 x 513, centre post
  (807, 1857) at 3.01546 S, 336.57478 E. Heights are the DTM minus -1422.590 m (that post's own
  value), so the centre is 0 and the range is -24.3 to +6.7 m. Posts go at (2 * column, height,
  2 * row) with X east and Z south, float32 (`play.f32`), with no curvature, as the brief asks.
- **What's in it:** the LM at (+100.7, -80.8), the ALSEP at (+9.8, -171.8), Surveyor 3 at
  (+218.8, +22.3), Head crater's floor at (-37, -42), Bench (-138, +136), Surveyor crater's floor
  (+155, +23), Halo about (+180, +176). Sharp is about 450 m west of Surveyor 3 and about 400 m from the
  LM (LROC), roughly (-230, +60); the build didn't pin it down exactly.
- **Slopes** inside the boundary, 4 m baseline: 2.3% over 15 degrees, 0.11% over 25, 0.012%
  over 30, max 32.4.
- **Confidence map over the window:** 7.2% "suspicious" (value 3), the rest correlated (10-14).
  No shadowed, interpolated or edited posts.
- **Authored changes** (`authored_changes`):
  - the base, 46 x 32 m at (-300, +252), graded to its mean plane (0.46 degrees; 813 posts, at
    most 0.215 m);
  - 9619 seeded procedural rocks of 0.1-1.5 m (instances, not in the heightmap; the 1709 of
    0.2 m and up collide).
  - Nothing else touches the measured ground. `test_terrain.gd` checks that the collision is
    `play.f32` bit for bit, and that it equals `play_measured.f32` outside the base.
- **Shading only, never collision:**
  - the regolith shader's sub-metre relief (normals and their small shadows);
  - the procedural albedo mottling;
  - the site brightness map. It's the orthophoto divided by the DTM's Lommel-Seeliger shading
    under the image's own sun (37.9 degrees up at azimuth 273.3, from Horizons at the image time),
    normalised, blurred to 8 m and limited to +-30% (5-95%: 0.96-1.15). It shows Surveyor crater's
    halo, the LM's blast zone and fresh craters' haloes. Shading from relief smaller than the DTM
    resolves stays in it.
- **Ring:**
  - near 8 m to +-4 km (the DTM where it has data, feathered over 100 m into SLDEM2015);
  - mid 64 m to +-32.8 km (SLDEM2015, only rows 720-2360 fetched by byte range, 151 MB of the
    tile's 1.4 GB);
  - both with the exact conversion (curvature included). SLDEM2015 against the DTM: offset
    +0.29 m, RMS 1.7-1.9 m. No far tier: the mare's horizon is 2.6 km away.
  - The flat play tier sits 7.5 cm above the curved ring at the middle of its edge and 15 cm at
    the corners; the 2 m skirt hides it.
- **Boundary** at +-500 m, the same system as before. The camera far plane is 50 km.
- **Sun and sky** (JPL Horizons, observer at the play centre, mean-Earth frame like the LROC
  coordinates):
  - the sun 16.72 degrees up at azimuth 90.62; 99.7% of the play area is lit;
  - Earth 61.30 up at 90.24, 1.92 degrees across, 14% lit, longitude 225 E facing the site;
  - the star map rotation is fitted to the sun and Earth (3 arcsec), and checked with Jupiter
    (0.6") and Mars (12");
  - zenith RA 164.8, Dec +3.1; north celestial pole 3.1 degrees up at azimuth 338.9.
- **Preservation:** NASA's 2011 recommendations give a 75 m artifact boundary (the figure stated
  for Apollo 11; the PDF's site table couldn't be extracted here). The test drive keeps at least
  75 m from the LM, the ALSEP and Surveyor 3 (closest 104 m), and the base is over 225 m from all
  three.
- **Pipeline:** `site_type` "equirectangular" in `build_moon_terrain.py`, with:
  - PDS3 readers (`LrocDTM`, `SldemBand`) and byte-range fetching;
  - an `ephemeris` block (Horizons, cached in `raw/`);
  - `site_brightness`;
  - detail switches (`detail.roughness`, `detail.craters`).
  - The polar path was rebuilt into a scratch folder: every heightmap, rock and horizon file was
    identical to what was committed.

### Measured (MacBook Pro M4, 1920x1080, Godot 4.7.2, `tools/measure_moon_fps.gd`)

| | 1 km Apollo 12 | South pole (earlier) |
|---|---|---|
| Load, first (meshes not cached) | 2.68 s from the menu: data and collision 83 ms, 568 chunks in 2.0 s | about 4.5 s |
| Load, later | 0.79-0.82 s (0.5 s of it the loading screen's fade); meshes 0.12-0.15 s | 1-2.5 s |
| Memory over the main menu | +25 MB static, +137 MB video | not measured |
| Chase camera, vsync off | 141-144 fps (7.0 ms), p99 12-14 ms, worst 16-19 ms | 122-146 fps |
| On foot / facing the rover with both lights | 120-136 / 120-137 fps | |
| Triangles drawn per frame (with shadow passes) | about 5.3 M | |

The mast camera phase lost the window's focus in every run (the game caps an unfocused window at
30 fps), so it has no clean number. The memory figures cover the whole level (rover, parts, sky),
not just the terrain.

### Not done yet

- Re-rendering the windowed previews: sky, terrain and helmet light. The tools are retargeted.
- The mission console's site map from the orthophoto. That console belongs to the UI work.
- The Terrain Detail menu labels still say 0.5 m / 1 m.
- Lower star visibility for a sunlit exposure: `star_brightness` is unchanged.

# Apollo 12 switch: the plan as approved

Research done on 2026-10-09, before the build. The decisions above override this plan where they
differ: a 1 km area, positioned as described, and no starter pack.

## 0. The starter pack (it turned out not to exist)

The plan was written expecting `tools/terrain/raw/Tandborste-NASA-Moon-Terrain-Starter.zip`. One
finding from that time still stands:

- **The brief's crop may not contain the landing site.** The brief gives the crop 257 x 257 samples
  at 2 m with a 36.322 m vertical range. In the LROC DTM (v1.9, below), every 257 x 257 window that
  contains the LM has a range of 12.5 to 31.0 m. Windows with a 36.32 m range exist, but the nearest
  is centred about 1.1 km north of the LM.

## 1. Source data and loading the heights

**Original product:** LROC NAC DTM `NAC_DTM_APOLLO12_E030S3365` (PDS volume LROLRC_2001, v1.9,
Henriksen et al. 2017, doi:10.1016/j.icarus.2016.05.012). Stereo images M120005333 and M120012135
(L/R), taken on 2010-02-05.

| | |
|---|---|
| Format | PDS3 IMG, float32 little-endian (`PC_REAL`), 2468 x 1367 samples, 13,504,896 bytes |
| Projection | equirectangular, true scale at 3.0 S, sphere 1737.4 km, 2.000 m/px |
| Extent | 2.962-3.052 S, 336.452-336.615 E: **4.94 x 2.73 km** |
| Heights | metres above the 1737.4 km sphere: -1461.2 to -1406.9 m. The DTM gives -1422.0 at the LM and -1432.5 at Surveyor 3; LROC's list gives -1422 and -1433 |
| Accuracy | tied to 19 LOLA tracks with 1.31 m RMS; SOCET SET precision 0.8 m |
| No data | 4.33% (outside the stereo overlap, at the edges); none within 1.1 km of the LM |
| Confidence map (`_CONF`) | 0 no data, 3 suspicious, 10-14 correlated (no 1/2/4/15 here). Within 256 m of the LM: 6.9% suspicious, 1.0% value 10, the rest 11-14 |
| Orthophotos | the two image pairs at 0.5 m (9873 x 5465, int16, 103 MB each) and at 2 m |

**Loading (reusing `build_moon_terrain.py`):**
1. **Verify the pack.** Read the pack's float binary and metadata as they are. Find the crop's
   pixel window in the PDS DTM by exact match, and check that the heights equal the DTM minus the
   pack's stated constant, to float rounding. Record the pack's file names, sha256 hashes, the
   window, the constant and the product IDs in `terrain.json` under `provenance`. Report whether the
   LM and Surveyor 3 are inside the crop.
2. **Play tier as the brief says.** Sample (column c, row r) goes at `(2c, h[r,c], 2r)`: X east,
   Z south, rows along +Z, the same axes the game uses now. No resampling, no height scaling, no
   curvature correction (the heights are local metres on purpose).
   - Store it as **float32** (`play.f32`), not 16-bit, so the values stay exact (1 MB for 1 km).
   - Mesh triangles keep Jolt's diagonal, so the measured mesh is the collision mesh (`test_terrain`
     check 2).
   - If the play area is larger than the crop (section 8), the extra samples come from the same PDS
     DTM with the same constant subtracted. Inside the crop's footprint they must equal the pack's
     floats, which proves it's one pipeline, not two.
3. **Code changes.** Add a projection type (equirectangular next to the existing polar
   stereographic) for `LocalFrame` and the ring conversion. Add readers for the pack and for PDS
   float IMGs. `fetch` learns byte ranges (section 2). New settings file
   `tools/terrain/moon_apollo12.json`, output in `game/res/terrain/moon_apollo12/`.

**Detail: what's measured, what's shading, what collides.** `terrain.json` gets an `authored_changes`
list, and the README and CREDITS repeat it.

| Layer | Source | Visible | Collision | Status |
|---|---|---|---|---|
| Measured surface | the pack's 2 m floats (plus the PDS DTM past the crop) | yes | **yes** | NASA-derived, unmodified |
| Sub-metre relief in `regolith.gdshader` (normals and small shadows) | procedural | yes | **no** | shading only |
| Albedo mottling, crater freshness | procedural, plus the orthophoto (section 3) | yes | no | shading only |
| Rocks of 0.2 m and up | procedural instances, seeded | yes | **yes**, convex | authored, listed with their seed |
| Graded workshop and pad footprints | flattened to their mean plane | yes | **yes** | authored; the area and largest height change are recorded |
| Small craters and roughness below the DTM's resolution | procedural | — | — | **not added by default**; only with approval, as a separate delta file listed as authored |

The DTM resolves craters down to about 6-10 m (3-5 posts). Driving on 2 m facets is smooth, and the
shader relief supplies the look up close. The current "rover-scale detail in the heightmap" step
(LOLA section 2.4) stays in the code but is switched off for this site.

## 2. Ring to the horizon, and the boundary

From 2 m up on a flat mare the horizon is only about **2.6 km** away, and ground 30 km out is hidden
unless it stands over 260 m high. Nearby mare relief stays within tens of metres. Lansberg's rim is
about 125 km away, under 4.5 km of curvature. So the skyline is close, and this ring is much smaller
than the south pole's.

| Tier | Source | Spacing | Reach from the play centre |
|---|---|---|---|
| play | the pack plus the PDS DTM (section 1) | 2 m | 512 m or 1 km square (section 8) |
| near | the same NAC DTM | 8 m | to the DTM's edges, which are uneven around the LM: 1.1 km E, 1.2 km S, 1.5 km N, 3.8 km W |
| mid | **SLDEM2015** (LOLA plus Kaguya TC, NASA GSFC LOLA team, PDS), 512 px/deg (59 m) | 64 m | +-32 km |
| far | the same | 512 m | only if the build's horizon check shows it ever sets the skyline; dropped otherwise |

- **SLDEM2015:** tile `sldem2015_512_30s_00s_315_360_float.img` (1,415,577,600 bytes, float32 km
  above 1737.4 km, simple cylindrical). That breaks the 1 GB rule, but the server accepts byte
  ranges and rows are 92,160 bytes, so `fetch` downloads only rows 1029-2053 (+-1 degree of
  latitude, **94 MB**), checks the byte count and records sha256. LDEM_512 (LOLA only) has gaps
  between tracks at the equator, so SLDEM2015 is the better choice.
- **Joins:** the near tier uses the DTM wherever it has data and SLDEM2015 elsewhere, with a 100 m
  feather. SLDEM2015 is calibrated to the DTM (offset and RMS, with failure limits, the same way
  `PolarDEM.calibrate` works).
- **Curvature:** ring tiers get the exact conversion (LOLA section 2.2) in the equirectangular
  projection. The play tier stays flat as delivered, so at its edge it sits 2 cm (512 m) or 7.5 cm
  (1 km) above the curved ring. The skirt hides this, and it's recorded.
- **Boundary:** the same system as now: walls on layer 7, survey stakes, the HUD warning within
  20 m, `LostZone`. `boundary_half_size` becomes 240 m (512 m area) or 500 m (1 km). Past the wall
  the ground is still the measured 2 m surface out to the play tier's edge, then the 8 m DTM.
- **Camera far plane:** 200 km becomes about 40 km.

## 3. Surface: procedural, orthophoto, or a mix

The orthophotos were taken with the sun **37-38 degrees up in the west** (azimuth 273; Horizons, at
the image times). At that height almost nothing casts a shadow: only slopes over 53 degrees facing
east would, and the mare has none over 33 degrees at 4 m. What's baked in is mostly **shading**:
east-facing slopes darker, west-facing slopes brighter, and small boulders and pits that the DTM
can't resolve.

| Option | Pros | Cons |
|---|---|---|
| A. Procedural regolith only (as now) | consistent under any sun | loses the real site's look: Surveyor crater's halo, the LM's blast zone, the tracks |
| B. Orthophoto as the colour, sun matched to it (37 degrees from the west) | the real image, its shading consistent with the light | not the Apollo 12 sun; the image isn't albedo (brief) |
| **C. Mix (recommended)** | real brightness patterns under the Apollo 12 sun | the albedo is approximate |

How C works: divide the 0.5 m orthophoto by the DTM's own shading under the image's sun, blur the
result to about 8 m, and use it as a gentle multiplier on the procedural albedo. Procedural detail
stays below that scale. Shading from slopes smaller than the DTM resolves remains in it, so the
records call it "approximate, not calibrated albedo", as the brief asks. The unmodified orthophoto is
also used **as a site image**: the mission console's map and the historical card. The brief says to
use the matching source crop for the surface image; C does, through the normalisation.

## 4. Sun, Earth and stars for this site

Horizons, observer at the LM (336.5781 E, 3.0128 S, -1.422 km), airless apparent az/el (azimuth from
north towards east; the game's convention, degrees from -Z towards +X with -Z north, gives the same
numbers). EVA values are interpolated from the 2-hour table.

| Moment (UTC) | Sun elevation | Sun azimuth |
|---|---|---|
| Landing, 1969-11-19 06:54 | **5.1** | 91.2 |
| EVA 1, 11:32-15:28 | 7.5-9.5 | 91.0 |
| EVA 2, 1969-11-20 03:54-07:44 (Surveyor 3 visit) | **15.8-17.7** | 90.6 |
| Liftoff, 14:26 | 21.1 | 90.5 |
| Orthophotos, 2010-02-05 10:34 / 12:28 | 37.9 / 36.9 | 273.3 / 273.2 |

- **Earth during the stay:** azimuth 87.3-91.1 (east, behind the rising sun), **61.3-61.4 degrees
  up**, 1.93 degrees across. At landing it was 56 degrees from the sun and 22% lit, a thick crescent.
  `LunarSky` already lights Earth with the `Sun` light, so its phase follows.
- **Options:** landing (5.1 degrees, shadows 11 times as long as the object), EVA 1 (about 8.5),
  **EVA 2's midpoint (16.7, recommended)**, or the orthophoto sun (only with surface option B). EVA 2
  keeps strong directional shadows, about 3.3 times the object's length, and a readable workshop
  exterior. It's the moment the crew walked to Surveyor 3. The sun is from the east, so shadows
  point west. All the Apollo 12 options are lunar morning; a real low *evening* sun at this site
  would need a different date.
- **Star map: align it.** `LunarSky.world_to_equatorial()` assumes the south pole (south ecliptic
  pole overhead). It gets replaced by a rotation stored in `terrain.json`. The pipeline fits it from
  Horizons' ICRF RA/Dec plus az/el for the sun and Earth at the chosen moment. Tested at landing, it
  puts the sun and Earth within 4.6 arcsec and predicts Jupiter (1.7") and Mars (10.9"), which
  weren't used in the fit. The NASA SVS star map is in the same ICRF/J2000 frame, so no precession
  correction is needed. At landing the zenith is RA 153.0, Dec +7.5, and the celestial north pole is
  7.5 degrees up at azimuth 340.7. The README names the moment the sky shows instead of claiming a
  general alignment. Horizons replies are cached in `raw/`, so rebuilds work offline.
- **Pipeline:** `choose_sun` (permanently shadowed crater) and `choose_earth` (libration range) give
  way to an `ephemeris` block in the settings file (one UTC moment). Horizon maps stay; their first
  azimuth is still the sun's.
- **Exposure and fill:** `exposure_for_elevation` / `fill_for_elevation` were tuned at 1.5-9
  degrees. They need checking in renders at 16.7.

## 5. Surveyor 3

LROC coordinates (Wagner et al. 2016 list): LM 3.0128 S, 336.5781 E; Surveyor 3 3.0162 S,
336.5820 E. **Surveyor 3 is 157 m from the LM: 118 m east, 103 m south**, on the inner east wall of
Surveyor crater (about 200 m across, LM on its north-west rim). It's inside a 512 m square centred on
the LM (138 m from its east edge) and inside 1 km. Whether it's inside the **starter crop** waits on
the zip (section 0). The ALSEP central station is 128 m north-west of the LM.

Preservation: R7 points to NASA's 2011 recommendations for Apollo sites. The workshop, the pad and
the routes go outside the boundaries those set around the LM and Surveyor 3 (exact radii to be
checked). The historic hardware isn't modelled now; markers are optional.

## 6. What depends on the south pole site, and what replaces it

| Depends on the pole | Replacement |
|---|---|
| `test_terrain.gd` check 3: permanently shadowed crater floor dark, base and pad lit | the sun at the configured moment: base and pad lit, and the lit share of the play area equals the pipeline's value |
| `test_terrain.gd` check 5: the drive into the shadowed crater, `ROUTE` | base, then past the LM's preservation boundary, Surveyor crater's rim, down to the Surveyor 3 viewpoint and out, then Head crater's rim. Same wheel checks |
| `test_terrain.gd` checks 1-2, 4: layout, mesh = collision at base / pad / crater, boundary | same checks at the new spots and boundary size |
| `test_moon_sky.gd`: south ecliptic pole overhead, Canopus 75.8 up, ecliptic on the horizon, north celestial pole -66.56 | sun, Earth and Jupiter drawn at their Horizons directions (within 0.1 degree); north celestial pole at the computed az/el; "sun where the pipeline chose it" reads the new `terrain.json` |
| `moon_level.tscn`: sun 2.1 / 200, `earth_direction`, spawn / base / pad / rover / pile positions, `camera_far` | from the new `terrain.json` and a new flat-spot survey |
| `LunarSky`: south-pole basis, `forward_ecliptic_longitude`, the "1.5 degrees max" sun comments | the stored rotation |
| `tools/render_sky_previews.gd` (Canopus check, `ROVER_AT`), `render_terrain_previews.gd` (`BASE`, `CRATER`), `render_helmet_light.gd` (`CRATER`) | new spots; the sky check uses a bright star the new rotation puts in view |
| Terrain Detail setting: Low = every other 0.5 m sample | 2 m data has nothing to halve: Low keeps the measured mesh and collision and only turns off the relief's shadows, which it already does. The menu row lives in `settings_sub_menu.gd` (UI); any label change gets coordinated with the session working on UI |
| Hard shadows (chosen against penumbra through the crater rim at 2.1 degrees) | keep for now; re-check at 16.7 |
| README Moon sections, `CREDITS.md` (LOLA / PGDA) | LROC NAC DTM, orthophotos, SLDEM2015, Horizons |

These don't depend on the site and only need re-running: `test_rover_landing`, `test_level_gravity`
and `test_parking` (they build their own floors), `test_level_switch`, `test_wheel_contact`,
`test_straight_line`.

## 7. The south pole terrain

Agreed: **keep the pipeline code and this history, and remove the data from the Moon level.**
- The polar path keeps working: `moon_site01.json` stays as a second settings file and a regression
  check on the generalised code.
- `game/res/terrain/moon_site01/` (17 MB) is deleted from the game. It rebuilds exactly from the
  settings file, the seed and the raw files. The raw files (about 760 MB, gitignored, local only) can
  go whenever you like.
- I see no reason to keep the data in the level. No other scene or test uses it once section 6 is
  done.

## 8. 512 m or 1 km at the same 2 m spacing

**Yes, the original DTM covers far more:** 4.94 x 2.73 km, about 51 times the crop's area, with no
data gaps within 1.1 km of the LM. A 1 km square centred on the LM fits with 600 m to spare on the
nearest (east) edge.

Measured on the DTM, squares centred on the LM (slopes over a 4 m baseline):

| | 512 m (257 x 257) | 1 km (513 x 513) |
|---|---|---|
| Relief | 21.4 m | 31.6 m |
| Slopes over 15 / 25 / 30 degrees | 3.1% / 0.23% / 0.03%, max 32.4 | 2.4% / 0.10% / 0.01%, max 32.4 |
| "Suspicious" confidence | 6.9% | 7.3% |
| LM, ALSEP, Surveyor 3, Surveyor crater (200 m), Block (on its rim), Halo (south of it) | yes | yes |
| Head crater (about 100 m, centre 134 m W) | yes, close to the west edge | yes |
| Bench crater (about 68 m, centre 227 m W / 211 m S) | cut by the edge | yes |
| Sharp crater (EVA 2's farthest point, about 400 m SW) | no | yes: **the whole EVA 2 traverse** (1.3 km loop) |
| Other craters in the square | none of 40 m or more whole | a 150 m crater 353 m east, an 80 m one 487 m south-south-east |
| A 450 m subdued crater centred 520 m W / 262 m N (possibly Middle Crescent, EVA 1's farthest stop; not confirmed) | no | mostly outside; reaching it means moving the centre about 250 m west |
| Play-tier samples / triangles | 66k / 131k | 263k / 525k |
| Height data (float32) | 0.26 MB | 1.05 MB |
| Mesh memory with LODs (*estimate*) | about 3 MB | about 13 MB |
| First load, play tier (*estimate*) | well under 1 s | about 1 s |
| Frame rate (*estimate*) | no difference expected | no difference expected |

Crater positions are from the DTM; diameters come from the hillshade and published values. The names
follow NASA's descriptions (Head west, Bench and Sharp south-west, Halo south, Block on Surveyor's
north-east rim). An exact traverse-map check is still to do, since the NASA traverse PDF didn't
download.

How the estimates were scaled: today's play tier is 2049 x 2049 (4.2M samples, about 150 MB of baked
meshes, first load 4.5 s). Both options are 16 times (512 m) or 4 times (1 km) smaller. On the M4,
0.5 m and 1 m ground already ran at the same speed (LOLA section 7: the cost isn't in the terrain's
triangles). Both get measured with `measure_moon_fps.gd` before you decide.

Gameplay: at 2 m/s on foot, 512 m takes 4 minutes to cross; 1 km takes 8. A 512 m area holds the
first-milestone workshop and pad easily. 1 km also leaves room for the second sortie's IRIS station
some distance away, and every place the Apollo 12 crew walked except EVA 1's farthest stop.
**Recommendation: 1 km**, if the team doesn't need the play area to be the 512 m crop itself. It's
the same NASA data at the same spacing and still costs a quarter of today's terrain. **The size
won't change without your approval.**

## 9. Order of work, once approved

1. Put the zip in `raw/`. Verify it against the PDS DTM (section 1, step 1) and report the crop's
   position, its constant, and whether the LM and Surveyor 3 are inside.
2. Pipeline: projection type, readers, byte-range fetch, ephemeris block and star rotation, the
   `authored_changes` / `provenance` records, previews. Build `moon_apollo12`. Rebuild `moon_site01`
   to check the polar path still matches.
3. Game: `MoonTerrain` reads `play.f32` and the new tiers; `LunarSky` uses the stored rotation; new
   positions in `moon_level.tscn`; delete `moon_site01` data.
4. Surface option C, plus the console map image.
5. Tests and tools from section 6; frame-rate and loading measurements for both sizes (section 8);
   README, CREDITS.

---

# History: south pole terrain plan (LOLA Site01)

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
3. **Sun 2.1 degrees up, azimuth 200; Earth 6 degrees up** (replaces 9 degrees at azimuth 39,
   below). 2.1 is the real sun's highest at this site (1.54 degrees of axial tilt plus 0.63 from
   the pole, highest towards azimuth 225), so the permanently shadowed crater stays dark for the
   real reason: its floor's lowest horizon is 2.92 degrees against 2.37 for the top of the sun, no
   point of any shadowed patch in the play area sees it, the base and pad's highest horizon is
   0.8, and 77% of the play area is in direct sunlight. Earth from this site sits near longitude
   0's direction: azimuth -3.5; at 6 degrees up (the top of its libration from here, -7.1 to 6.2)
   it is 8.4 degrees above the skyline seen from the base, 155 degrees from the sun, so 95% lit.
   Both are pinned in `moon_site01.json` (`sun.azimuth`, `earth.elevation`); without them the
   pipeline picks the azimuth with the most margin and puts Earth 2.5 degrees over the skyline,
   and with them it checks the floor stays dark, the base and pad lit and Earth clear of the
   skyline. With a sun this low about half the ground near you is in the small shadows of the
   sub-metre relief (the regolith shader carries this pipeline's roughness spectrum on below the
   mesh: game README, Moon terrain).

   *Before:* 9 degrees up at azimuth 39, for visibility. At that height only azimuths 32 to 45
   kept all of the 7.9 ha floor dark with the base and pad lit (the floor's lowest horizon 9.49
   against 9.27 for the top of the sun); the higher ground to the north-east left only 35% of the
   play area in sunlight, and Earth, 0.1 degrees up and 43 degrees from the sun, was a 14% crescent
   on the skyline.
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
  After a rebuild, reimport them (`Godot --headless --path game --import`): the game doesn't
  reimport changed PNGs, and old maps with a new `terrain.json` shade the wrong terrain.
- **Sun at 2.1 degrees** (decision 3): the sun light casts hard shadows. Godot's soft shadows widen
  with the caster's distance past what the nearest cascade covers, and with the sun's real 0.53
  degrees 70% of the sunlight came through the crater's rim onto parts on its floor.
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
  the ridge). The level uses azimuth -3.5 at 6 degrees up (decision 3).

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
