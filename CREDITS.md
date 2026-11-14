# Credits

Third-party assets in this repository and where they come from. NASA imagery is used under
NASA's media usage guidelines; no endorsement by NASA or ESA is implied.

## Credits screen

The text of the in-game credits roll (`game/src/ui/credits/`, board `docs/ui/boards/Credits.dc.html`);
the game reads this section from the repository root, so edit it here. Each `###` heading is a
section title of the roll, shown in capitals. Under it, blocks separated by a blank line are
centred entries; a block whose every line reads `NAME | small line` is a list of name rows, any
other block is shown as written, line breaks kept. `CLOSING NOTE` is shown without a title.
Update the team and the special thanks before release.

### A GAME BY

TANDBORSTE | Made for the NASA Space Apps Challenge 2026

### TEAM

FAHD | Institut Teknologi Bandung · Indonesia
RAFI WIDYA PRATAMA | Universiti Malaya · Malaysia
FAIQ | Monash University · Australia
SATINIZE | National University of Singapore · Singapore

### REAL DATA

Apollo 12 site terrain and imagery
NASA Lunar Reconnaissance Orbiter · LROC, Arizona State University

Wider lunar terrain
NASA LOLA · SLDEM2015

Star map
NASA/Goddard Scientific Visualization Studio, Deep Star Maps 2020
Gaia data: ESA/Gaia/DPAC

Earth
NASA Blue Marble

Sun, Earth and sky positions
NASA JPL Horizons

### BUILT WITH

Godot Engine
Blender

### TYPE

Michroma by Vernon Adams
IBM Plex Mono by IBM
SIL Open Font License

### MUSIC AND SOUND

Tandborste

### SPECIAL THANKS

[YOUR SPECIAL THANKS]

### CLOSING NOTE

The Apollo 12 site, Surveyor 3 and the sky are recreated from real NASA data for the second moonwalk of Apollo 12, November 1969. The workshop, ROOK, Kite and their mission are fiction.

## Workshop kit

`game/res/models/workshop_kit/`: original, made by this project's scripts; nothing
third-party (`game/res/models/workshop_kit/PROVENANCE.md`).

## Kite kit

`game/res/models/kite_kit/` and the rover kit's cartridge and cargo mount: original, made by
this project's scripts from its own rover kit; nothing third-party
(`game/res/models/kite_kit/PROVENANCE.md`).

## Astronaut kit

`game/res/models/astronaut_kit/`: original, made by this project's scripts; nothing
third-party (`game/res/models/astronaut_kit/PROVENANCE.md`).

## Decor kit

`game/res/models/decor_kit/` and the tyre-track textures in `game/res/textures/decor/`: original,
made by this project's scripts; nothing third-party (`game/res/models/decor_kit/PROVENANCE.md`).

## History cards

The two photographs on the workshop's history cards (`game/res/textures/decor/`; download,
checksums and processing in its `PROVENANCE.md`):

- **AS12-49-7278**, "Astronaut Alan Bean holds Special Environmental Sample Container",
  19-20 November 1969. Photo: NASA (taken by Charles Conrad Jr.).
  <https://images.nasa.gov/details/as12-49-7278>
- **AS12-48-7136**, "Apollo 12 Mission image - Astronaut Alan L. Bean, lunar module pilot, and
  two U.S. spacecraft" (Conrad at Surveyor 3, Intrepid behind), 20 November 1969. Photo: NASA
  (taken by Alan L. Bean). <https://images.nasa.gov/details/as12-48-7136>

Both are public domain NASA images, cropped square and resized to 1024 x 1024, otherwise
unchanged. Each card prints its credit and NASA ID under the photo.

## Star map

`game/res/textures/sky/starmap_2020_4k.exr`: the Moon level's sky.

- **Deep Star Maps 2020**, NASA/Goddard Space Flight Center Scientific Visualization Studio
  (NASA/GSFC SVS), <https://svs.gsfc.nasa.gov/4851/>
- Gaia DR2: **ESA/Gaia/DPAC**. The map also plots the Hipparcos-2 and Tycho-2 catalogues.

The 4096 x 2048 EXR is unmodified. It was downloaded on 2026-10-08 from the Internet Archive's
capture of the SVS file URL
(`https://svs.gsfc.nasa.gov/vis/a000000/a004800/a004851/starmap_2020_4k.exr`), because SVS
itself was unreachable that day. Its SHA-1, `fe4831347451db67adac635f7df8263468a15a1d`
(base32 `7ZEDCNDUKHNWPLNMMNPX36BGGRUKCWQ5`), matches what the archive recorded for the SVS
file in every capture from 2020 to 2026.

## Earth

`game/res/textures/sky/earth_blue_marble_1024.jpg`: Earth in the Moon level's sky.

- **Blue Marble: Next Generation**, NASA Earth Observatory (Reto Stöckli, NASA Goddard Space
  Flight Center), December 2004 with topography and bathymetry
  (`world.topo.bathy.200412.3x5400x2700.jpg`), <https://visibleearth.nasa.gov/images/73909>

Downscaled from 5400 x 2700 to 1024 x 512.

## Main menu Moon

`game/res/textures/moon/lroc_color_4k.jpg`: the colour map on the main menu's 3D Moon.

- **CGI Moon Kit**, `lroc_color_16bit_srgb_4k.tif` (2025 colour map, 4096 x 2048), NASA's
  Scientific Visualization Studio, from Lunar Reconnaissance Orbiter Camera
  (LROC) WAC data, NASA/GSFC/Arizona State University, <https://svs.gsfc.nasa.gov/4720>.
  Public domain.

Converted from 16-bit to 8-bit and saved as a quality-90 JPEG (macOS `sips`), otherwise
unchanged. The source TIFF is not committed (`.gitignore`).

## Moon terrain

`game/res/terrain/moon_apollo12/`: the Moon level's ground at the Apollo 12 landing site, made by
`tools/terrain/build_moon_terrain.py` (see `tools/terrain/MOON_TERRAIN.md`). The play area is
the LROC NAC DTM's 2 m posts unchanged (float32, one constant subtracted), except for a graded
46 x 32 m base; the rest is converted to metres in a local frame with the Moon's curvature and
resampled. Authored additions (rocks, the graded base) are listed in `terrain.json`
(`authored_changes`); the untouched posts are kept in `play_measured.f32`.

- **LROC NAC DTM of the Apollo 12 landing site**, `NAC_DTM_APOLLO12_E030S3365` (v1.9, 2 m/post),
  its confidence map `NAC_DTM_APOLLO12_CONF` and the orthophoto
  `NAC_DTM_APOLLO12_M120005333_2M`, NASA/GSFC/Arizona State University, LRO-L-LROC-5-RDR-V1.0
  (volume LROLRC_2001), <https://data.lroc.im-ldi.com/lroc/view_rdr/NAC_DTM_APOLLO12>;
  Henriksen, M. R., et al. (2017), Extracting accurate and precise topography from LROC narrow
  angle camera stereo observations, Icarus 283, 122-137, doi:10.1016/j.icarus.2016.05.012.
  The orthophoto is used only as an approximate brightness pattern (divided by the DTM's
  shading, blurred), not as albedo.
- **SLDEM2015** (LOLA and SELENE Terrain Camera, 512 pixels/degree), tile
  `sldem2015_512_30s_00s_315_360_float` (rows 720-2360 only), NASA Planetary Data System
  Geosciences Node, <https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data/sldem2015/>;
  Barker, M. K., et al. (2016), A new lunar digital elevation model from the Lunar Orbiter Laser
  Altimeter and SELENE Terrain Camera, Icarus 273, 346-355, doi:10.1016/j.icarus.2015.07.039
- **LROC coordinates of lunar anthropogenic features** (28 July 2016) for the LM, the ALSEP and
  Surveyor 3, LROC Science Operations Team, Arizona State University,
  <https://www.lroc.asu.edu/data/support/downloads/2016_LROC_Coordinates_of_Human_Features.pdf>
- **JPL Horizons** (NASA/JPL Solar System Dynamics) for the sun, Earth and the star map's
  orientation seen from the site at 1969-11-20 05:49 UTC, <https://ssd.jpl.nasa.gov/horizons/>

Every source file's URL, byte count (and byte range) and SHA-256 are recorded in `terrain.json`
(`sources`), the DTM window and constant in `provenance`.

The south pole site that the level used before (`moon_site01`, removed from the game; its
pipeline settings remain) came from the LOLA 5 m/pixel south pole landing site DEMs (NASA GSFC
PGDA product 78; Barker et al. 2021, doi:10.1016/j.pss.2020.105119), the LOLA permanently
shadowed regions map (PGDA product 90) and the LOLA gridded data records `LDEM_875S_20M` and
`LDEM_85S_40M` (NASA PDS Geosciences Node).
