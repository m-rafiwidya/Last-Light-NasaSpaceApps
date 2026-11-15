# Credits

Third-party assets in this repository and where they come from. NASA imagery is used under
NASA's media usage guidelines; no endorsement by NASA or ESA is implied.

## Credits screen

The in-game credits roll (team, real data sources, type, special thanks) is written in
`game/res/credits.md`, which the game reads (an exported build includes it); edit it there. The
asset sections below stay the full provenance record. The roll's last section, **Godot Engine
licence**, is not in that file: `CreditsData.engine_section()` builds it at run time from
`Engine.get_license_text()` and `Engine.get_copyright_info()` (Godot's licence and the copyright
holders and licence of every third-party component in the engine).

## Engine and tools

- **Godot Engine** 4.7, <https://godotengine.org>. MIT licence; the licence text and the
  third-party notices are in the credits roll (see above).
- **Blender** 5.2, <https://www.blender.org>. Runs the generator scripts in `tools/blender/scripts/`;
  the models it exports are this project's own.

## AI tools

- **Claude Opus 5.5 and Claude Sonnet 5.5** (Anthropic), used through Claude Code: the code (the game's
  GDScript, the build tools, the terrain pipeline), the Blender scripts that build every 3D model, and
  the music composition (`game/music/`). Commits made with it carry a `Co-Authored-By: Claude` line.
- **Images:** Claude Code, through the Blender generator scripts and the render scripts (for example
  `game/tools/render_mission_images.gd`). No separate image generator was used. The title logo was
  drawn by Claude (next section).
- **Sound effects:** Claude Code's synthesis scripts (`game/music/`), plus the Kenney CC0 samples and
  the GeneralUser GS soundfont (see Sound and music above), which `game/music/samples/SOURCES.md`
  lists.
- **Voices:** ElevenLabs text to speech (`game/res/audio/voice/`), reading lines the team wrote.

## Early base code

The first version of the player controller, the dialogue system, the mission console and the first
rover with its part system (October 2026) was written by a former teammate who withdrew before
judging. It is used and built on with his permission; his commits remain in the git history.

## Title logo

`game/res/ui/astronaut_logo.svg` (the same file as `docs/ui/assets/astronaut-logo.svg`): an
**AI-generated silhouette** drawn as SVG by Claude, based on NASA's photograph of Bruce McCandless II,
STS-41-B, 1984 (public domain; NASA image S84-27017). The photograph is not in this
repository. No endorsement by NASA is implied.

## Reference images

`tools/blender/reference/curiosity.jpg`: NASA/JPL-Caltech artist's concept of Curiosity (public
domain), modelling reference only, not shipped. <https://science.nasa.gov/mission/msl-curiosity/>

## Fonts

All four are under the SIL Open Font License, Version 1.1 (<https://openfontlicense.org>); the full
licence is next to each font file in `game/res/fonts/` (`LICENSE-*.txt`) and `docs/ui/assets/fonts/`.
The credits roll prints the copyright lines and the licence name.

- **Michroma** by Vernon Adams. Copyright 2011 The Michroma Project Authors,
  <https://github.com/googlefonts/Michroma-font>. Titles and headings.
- **Exo 2** by Natanael Gama. Copyright 2013 The Exo 2 Project Authors,
  <https://github.com/googlefonts/Exo-2.0>. UI text.
- **IBM Plex Mono** by IBM. Copyright 2017 IBM Corp. All rights reserved, <https://github.com/IBM/plex>.
  Readouts and the console.
- **Caveat** (Evan's handwriting). Copyright 2014 The Caveat Project Authors,
  <https://github.com/googlefonts/caveat>.

## Sound and music

Details in `game/music/samples/SOURCES.md`; nothing here is copied into the game as is.

- **Impact Sounds** 1.0 by Kenney (2019-12-19), <https://kenney.nl/assets/impact-sounds>. Creative
  Commons Zero (CC0 1.0), no credit required (`game/music/samples/kenney_impact/License.txt`). 30
  files, slowed, filtered and mixed by `game/music/sfx_sounds.py` into the footsteps, landings and
  impacts in `game/res/audio/sfx/`.
- **GeneralUser GS** 2.0.3 soundfont by S. Christian Collins, <https://www.schristiancollins.com>.
  Free for private and commercial use (`game/music/soundfonts/LICENSE.txt`); the author notes that
  he cannot be sure of the origin of every sample inside it. Only the felt piano of
  `game/res/audio/music/deep_space_memory.ogg` is rendered from it, then heavily processed. The
  `.sf2` itself is not in the repository.
- Everything else (the other music voices, UI sounds, ambience, engine and door loops) is
  synthesised by this project's scripts with no samples.

## Workshop kit

`game/res/models/workshop_kit/`: original, made by this project's scripts; nothing
third-party (`game/res/models/workshop_kit/PROVENANCE.md`).

## IRIS kit

`game/res/models/iris_kit/` and the rover kit's cartridge and cargo mount: original, made by
this project's scripts (IRIS, its port and module socket, the rover kit parts); nothing third-party
(`game/res/models/iris_kit/PROVENANCE.md`). Evan's handwriting on IRIS is **Caveat**, Copyright 2014 The Caveat Project Authors, SIL Open Font License 1.1 (`game/res/fonts/LICENSE-caveat.txt`).

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

## Planet explorer

`game/res/textures/planets/`: the colour maps on the main menu's planet explorer globes (the Moon
uses `lroc_color_4k.jpg` above). Both are equirectangular, 4096 x 2048, centred on 0° longitude,
made by resampling the sources below with Python (Pillow) and saved as quality-90 JPEGs; the
sources are not committed.

- `mars_viking_color_4k.jpg`: **Mars Viking Global Color Mosaic 925m**
  (`Mars_Viking_ClrMosaic_global_925m.tif`, 23059 x 11530, simple cylindrical, planetocentric,
  east-positive), USGS Astrogeology Science Center, from NASA Viking Orbiter images,
  <https://astrogeology.usgs.gov/search/map/mars_viking_global_color_mosaic_925m>, downloaded from
  <https://planetarymaps.usgs.gov/mosaic/Mars_Viking_ClrMosaic_global_925m.tif> (MD5 matches the
  published `.md5`). Box-filtered down. Public domain.
- `earth_blue_marble_4k.jpg`: **Blue Marble: Next Generation**, December 2004 with topography and
  bathymetry (`world.topo.bathy.200412.3x5400x2700.jpg`), NASA Earth Observatory (Reto Stöckli,
  NASA Goddard Space Flight Center), <https://visibleearth.nasa.gov/images/73909>. Lanczos-resampled
  from 5400 x 2700. Public domain.

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
- **Gazetteer of Planetary Nomenclature**, Head crater (3.01° S, 23.43° W, 120 m), USGS
  Astrogeology Science Center for the IAU, <https://planetarynames.wr.usgs.gov/Feature/2396>. Shown
  on the Data Sources screen; the short M3 route crosses the crater.

Every source file's URL, byte count (and byte range) and SHA-256 are recorded in `terrain.json`
(`sources`), the DTM window and constant in `provenance`.

The south pole site that the level used before (`moon_site01`, removed from the game; its
pipeline settings remain) came from the LOLA 5 m/pixel south pole landing site DEMs (NASA GSFC
PGDA product 78; Barker et al. 2021, doi:10.1016/j.pss.2020.105119), the LOLA permanently
shadowed regions map (PGDA product 90) and the LOLA gridded data records `LDEM_875S_20M` and
`LDEM_85S_40M` (NASA PDS Geosciences Node).

## NASA Space Apps Challenge resources

Public NASA material that the missions' design follows (the Data Sources screen explains how). Ideas
only; nothing is copied. NASA does not endorse this game.

- *Design and Develop Science Missions*, NASA Systems Engineering Webinar (2025),
  <https://www.nasa.gov/wp-content/uploads/2025/04/250323-design-and-develop-science-mission.pdf>
- *Concept Maturity Levels*, NASA JPL, <https://dataverse.jpl.nasa.gov/dataset.xhtml?persistentId=hdl:2014/44299>
- Mission Design Lab, NASA Goddard, <https://etd.gsfc.nasa.gov/capabilities/integrated-design-center/mission-design-lab/>
- *Build It Yourself: A Learning Game About Telescopes*, NASA Webb,
  <https://science.nasa.gov/mission/webb/game-build-it-yourself/>
