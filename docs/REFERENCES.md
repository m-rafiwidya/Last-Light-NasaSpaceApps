# References: Last Light (Tandborste, NASA Space Apps Challenge 2026)

Every external resource in the repository, for the Space Apps **References** field. Compiled
Compiled from the repo only: `CREDITS.md`, `game/res/credits.md`, `game/res/story/data_sources.json`,
every `PROVENANCE.md` / `SOURCES.md`, the font and sample licence files, `terrain.json`'s source list,
the git history, and a search of all tracked text for URLs, AI tools and copied code. Updated later on
Updated with the team's answers on the logo, the rover reference image and the AI tools.

**What was and was not checked.** Licences marked *(repo)* are quoted from a licence file or provenance
note committed here. Licences marked *(general knowledge)* are from the publisher's well-known terms and
were **not** re-fetched from the web for this list; confirm them on the source page before the
submission. Nothing in the repo was changed to produce this file.

## 1. Flags: read this first

| # | Item | Why it is flagged | Suggested action |
|---|---|---|---|
| F1 | **Godot Engine licence notice** | **Resolved.** The credits roll now ends with a GODOT ENGINE LICENCE section built from `Engine.get_license_text()` and `Engine.get_copyright_info()` (`CreditsData.engine_section()`). What is still not shown: the full texts of the third-party licences (`Engine.get_license_info()`). | Decide whether to add those texts. |
| F2 | **GeneralUser GS soundfont (piano in the shipped music)** | Its own licence says it cannot be 100% sure where every sample came from, and that this uncertainty may concern anyone using it in a commercial product (*repo*: `game/music/soundfonts/LICENSE.txt`). The `.sf2` is git-ignored, but the felt piano in `deep_space_memory.ogg` is rendered from it. | Decide whether to accept the author's stated risk, or re-render the piano with the synth engine. Credit S. Christian Collins in the credits (not there today). |
| F3 | **Rover reference image** `tools/blender/reference/curiosity.jpg` | **Resolved.** NASA/JPL-Caltech artist's concept of Curiosity (public domain), modelling reference only, not shipped. Source: https://science.nasa.gov/mission/msl-curiosity/. (Checked by viewing the file: an artist's concept render of Curiosity, not Perseverance.) | None. |
| F4 | **Title logo** `docs/ui/assets/astronaut-logo.svg` = `game/res/ui/astronaut_logo.svg` | **Answered by the team.** An AI-generated silhouette **drawn as SVG by Claude**, based on NASA's photograph of Bruce McCandless II, STS-41-B, 1984 (NASA image **S84-27017**, public domain). No third-party generator or artist is involved. The source photo is not in the repo. McCandless is an identifiable person (his likeness, as in F8). | Keep the "no endorsement" wording. |
| F5 | **Game icon `game/icon.svg`** | **Resolved.** Was Godot's stock icon (CC BY 4.0). Now our own: the title logo `game/res/ui/astronaut_logo.svg` (F4) on a dark rounded square, composed as SVG. It is `config/icon` in `project.godot`. | None. |
| F6 | **Voice lines: no voice audio ships** | `cutscenes.json` and `lines.json` point at `res://res/audio/voice/*.ogg`, but **no voice files exist or are tracked, so no voice audio ships**: the game falls back to subtitles. The paths stay as they are. | If voice files are added later, record who voices each line and add any AI voice tool to the credits. |
| F7 | **Private suit concept image** | `astronaut_kit/PROVENANCE.md` says the astronaut's style was checked against "a private concept image by another artist". It is git-ignored (`tools/blender/reference/private/`) and is **not** in the repo or the game; no shapes, text or logos were taken. | Keep it out of the repo. If the artist's permission is unknown, do not name or show the image. |
| F8 | **Apollo photographs of identifiable astronauts** | Public-domain NASA images (*repo*), but NASA's media guidelines bar use that implies endorsement, and identifiable people carry personality rights. Used as historical record on two workshop cards. | Keep the credit line and the "no endorsement" wording already in `CREDITS.md`. |
| F9 | **Gaia / Hipparcos / Tycho-2 content in the star map** | The star map is NASA SVS (NASA media terms), but the star data inside is ESA's. ESA asks for the Gaia/DPAC acknowledgement, and ESA's Gaia images are CC BY-SA 3.0 IGO *(general knowledge)*. Whether that share-alike reaches the SVS rendering is unclear. | Keep the "ESA/Gaia/DPAC" credit (already in the credits). Check the SVS page's own usage line. |
| F10 | **No licence for our own code and assets** | There is no `LICENSE` file at the root. | Add one (or state "all rights reserved") before the submission. |
| F11 | **Credits files out of step** | **Resolved** for what this list found (Kenney, GeneralUser GS, Gazetteer, fonts, Space Apps resources, AI tools, Godot, Blender). `data_sources.json` still has the extra NASA pages the credits do not (see section 11). | None for the credits. |
| F12 | **AI images and AI sound effects** | **Resolved.** The team's answer: images came from Claude Code (the Blender and render scripts) and sound effects from Claude Code's synthesis scripts, the Kenney CC0 samples and the GeneralUser GS soundfont. That matches `game/music/samples/SOURCES.md` and the `PROVENANCE.md` files (no separate image or sound generator). | None. |

**Nothing found with a non-commercial licence.** Every third-party item below is public domain, CC0, OFL,
MIT or similar. **Nothing found marked no-redistribution.** Still needing a record: F6 (no voice audio ships) and F7. No NASA, ESA or USGS logo file is tracked.

## 2. Game engine and tools

| Name | Source | Licence | Used where |
|---|---|---|---|
| **Godot Engine 4.7** (Forward Plus) | https://godotengine.org | MIT *(general knowledge)*. Notice not shipped: **F1** | The whole game (`game/project.godot`, `config/features`). Listed under BUILT WITH in the credits. |
| **Blender 5.2** | https://www.blender.org | GPL for the program; the models it exports are ours *(general knowledge)* | Runs the generator scripts in `tools/blender/scripts/` that make every model in `game/res/models/`. Listed in the credits. |
| Blender glTF exporter | bundled with Blender | GPL (the exported `.glb` files are ours) *(general knowledge)* | `.glb` files in `game/res/models/` |
| **Python libraries** for the music and terrain tools: NumPy, SciPy, Pillow, pedalboard, pretty_midi, mido, pyloudnorm, soundfile | https://pypi.org (each project) | BSD / MIT / HPND for most; **pedalboard is GPL-3.0** *(general knowledge, not re-checked)* | Offline tools only (`game/music/*.py`, `tools/terrain/build_moon_terrain.py`). Not shipped; their output (audio, terrain data) is ours. |
| **FluidSynth** (command-line renderer) | https://www.fluidsynth.org | LGPL-2.1+ *(general knowledge)* | `game/music/render.py`: renders the felt piano from the soundfont. Offline only. |

## 3. Fonts

All four are SIL Open Font License 1.1 (*repo*: licence files next to each font). OFL allows use,
embedding and redistribution in a game, provided the licence travels with the font.

| Name | Source | Licence | Used where |
|---|---|---|---|
| **Michroma** (Vernon Adams) | https://github.com/googlefonts/Michroma-font; files from Fontsource | SIL OFL 1.1 (*repo*: `game/res/fonts/LICENSE-michroma.txt`) | `game/res/fonts/michroma-latin-400-normal.woff2`: titles and headings across the UI. Also `docs/ui/assets/fonts/`. |
| **Exo 2** (Natanael Gama) | https://github.com/googlefonts/Exo-2.0 | SIL OFL 1.1 (*repo*: `LICENSE-exo-2.txt`) | `exo-2-latin-400/500/600-normal.woff2`: UI body text. Also in `docs/ui/assets/fonts/`. |
| **IBM Plex Mono** (IBM) | https://github.com/IBM/plex | SIL OFL 1.1 (*repo*: `LICENSE-ibm-plex-mono.txt`) | `IBMPlexMono-Regular/Bold/Italic/BoldItalic.ttf` and `ibm-plex-mono-latin-500-normal.woff2`: data, readouts, console. Also in `docs/ui/assets/fonts/`. |
| **Caveat** (The Caveat Project Authors) | https://github.com/googlefonts/caveat | SIL OFL 1.1 (*repo*: `LICENSE-caveat.txt`) | `caveat-latin-500-normal.woff2`: Evan's handwriting on IRIS, the field logger and notes. **Not in the in-game credits' TYPE list.** |

The UI boards in `docs/ui/boards/` load the same three families from Google Fonts at view time
(`fonts.googleapis.com`). The boards are design documents, not part of the game.

## 4. NASA, USGS and other space-agency data

Rights notes: NASA material is generally not copyrighted and may be used under NASA's media usage
guidelines (https://www.nasa.gov/nasa-brand-center/images-and-media/), with no implication of NASA
endorsement. LROC, PDS and USGS products are public data. *(general knowledge)* unless marked *(repo)*.

| Name | Source URL | Licence | Used where |
|---|---|---|---|
| **LROC NAC DTM, Apollo 12 site**: `NAC_DTM_APOLLO12_E030S3365` (2 m/post), `..._CONF` (confidence), orthophoto `..._M120005333_2M`. NASA/GSFC/Arizona State University | https://data.lroc.im-ldi.com/lroc/view_rdr/NAC_DTM_APOLLO12 (files from `pds.lroc.im-ldi.com`, `LRO-L-LROC-5-RDR-V1.0`) | NASA PDS public data | The ground you drive on: `game/res/terrain/moon_apollo12/` built by `tools/terrain/build_moon_terrain.py`. Orthophoto only as a brightness pattern. Authored changes (rocks, graded base) listed in `terrain.json`. |
| Henriksen et al. (2017), *Icarus* 283, 122-137 | https://doi.org/10.1016/j.icarus.2016.05.012 | Journal article: **cited, nothing copied** | Method and accuracy of the DTM (credits, Data Sources screen) |
| **SLDEM2015** (LOLA + SELENE Terrain Camera), tile `sldem2015_512_30s_00s_315_360_float` | https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data/sldem2015/ | NASA PDS public data | Terrain beyond the DTM, out to 33 km (`moon_apollo12/` far tiers) |
| Barker et al. (2016), *Icarus* 273, 346-355 | https://doi.org/10.1016/j.icarus.2015.07.039 | Journal article: cited only | Method of SLDEM2015 |
| **LROC coordinates of lunar anthropogenic features** (2016), ASU | https://www.lroc.asu.edu/data/support/downloads/2016_LROC_Coordinates_of_Human_Features.pdf | Public data (ASU/NASA LROC); a PDF table, used for three coordinates | Positions of the LM, ALSEP and Surveyor 3, so the base and routes keep clear |
| **JPL Horizons** (NASA/JPL SSD) | https://ssd.jpl.nasa.gov/horizons/ (API: https://ssd.jpl.nasa.gov/api/horizons.api) | NASA/JPL public ephemeris | Sun, Earth and star-map orientation for 1969-11-20 05:49 UTC (`LunarSky`, level lighting) |
| **Gazetteer of Planetary Nomenclature: Head crater** (USGS / IAU) | https://planetarynames.wr.usgs.gov/Feature/2396 | USGS public data | Head crater's name, position, size (Data Sources screen; M3 route). **Missing from `CREDITS.md` and `credits.md`.** |
| **Deep Star Maps 2020**, `starmap_2020_4k.exr` (NASA/GSFC SVS; star data ESA/Gaia/DPAC, Hipparcos-2, Tycho-2) | https://svs.gsfc.nasa.gov/4851/ (file fetched from the Internet Archive capture of `svs.gsfc.nasa.gov/vis/a000000/a004800/a004851/starmap_2020_4k.exr`; SHA-1 in `CREDITS.md`) | NASA SVS media terms; ESA star data: see **F9** | `game/res/textures/sky/starmap_2020_4k.exr`, unmodified: the Moon's sky (`lunar_sky.gdshader`) |
| **CGI Moon Kit** colour map `lroc_color_16bit_srgb_4k.tif` (NASA SVS; LROC WAC, NASA/GSFC/ASU) | https://svs.gsfc.nasa.gov/4720 | Public domain NASA (*repo*: `CREDITS.md`) | `game/res/textures/moon/lroc_color_4k.jpg`, converted to 8-bit JPEG: the main menu Moon (`menu_moon.gdshader`) and the planet explorer |
| **Blue Marble: Next Generation**, Dec 2004 (NASA Earth Observatory, Reto Stöckli) | https://visibleearth.nasa.gov/images/73909 | Public domain NASA (*repo*) | `game/res/textures/sky/earth_blue_marble_1024.jpg` (Earth in the Moon's sky), `game/res/textures/planets/earth_blue_marble_4k.jpg` (planet explorer). Resampled. |
| **Apollo 12 photograph AS12-49-7278** (NASA; Charles Conrad Jr.) | https://images.nasa.gov/details/as12-49-7278 (also https://www.nasa.gov/image-detail/amf-as12-49-7278/) | Public domain NASA (*repo*); see **F8** | `game/res/textures/decor/as12-49-7278.jpg`, cropped/resized: history card in the workshop (`dc_history_card`) |
| **Apollo 12 photograph AS12-48-7136** (NASA; Alan L. Bean) | https://images.nasa.gov/details/as12-48-7136 | Public domain NASA (*repo*); see **F8** | `game/res/textures/decor/as12-48-7136.jpg`, cropped/resized: second history card |
| **Photograph of Bruce McCandless II, STS-41-B (February 1984)** (NASA) | NASA image library, https://images.nasa.gov (image **S84-27017**; see **F4**) | Public domain NASA, per the team; see **F8** | **Not in the repo.** Only the basis of the title logo `game/res/ui/astronaut_logo.svg`, drawn as SVG by Claude (credits roll, main menu, loading) |
| **Curiosity rover, artist's concept** (NASA/JPL-Caltech) | https://science.nasa.gov/mission/msl-curiosity/ | Public domain NASA | `tools/blender/reference/curiosity.jpg`: modelling reference for the rover kit only; **not shipped** |
| NASA, *Moon by the Numbers* | https://science.nasa.gov/moon/by-the-numbers/ | NASA web content, facts only | Gravity 1.62 m/s², lunar day, light time (Data Sources; physics constants) |
| NASA, *The lunar atmosphere* | https://science.nasa.gov/moon/lunar-atmosphere/ | NASA web content, facts only | Why dust flies in clean arcs |
| NASA LRO spacecraft and instruments (Diviner) | https://science.nasa.gov/mission/lro/spacecraft-and-instruments/ | NASA web content, facts only | Why shade temperature matters. Readings in game are simulated. |
| Removed `moon_site01` pipeline: LOLA 5 m south-pole DEMs (PGDA product 78), LOLA PSR map (PGDA 90), `LDEM_875S_20M`, `LDEM_85S_40M`; Barker et al. 2021, doi:10.1016/j.pss.2020.105119 | https://pgda.gsfc.nasa.gov/products/78, /products/90; https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/ | NASA public data | **Not in the game any more**: only its settings remain in `tools/terrain/moon_site01.json` and preview images in `tools/terrain/previews/moon_site01/`. |

## 5. Science references (facts and numbers only; no text or figures copied)

| Name | Source URL | Licence | Used where |
|---|---|---|---|
| *A Study on Wheel Sinkage and Rolling Resistance ... Plain and Lugged wheels on TRI-1 Soil Simulant* | https://www.researchgate.net/publication/345142748_A_Study_on_Wheel_Sinkage_and_Rolling_Resistance_with_variations_in_wheel_geometry_for_Plain_and_Lugged_wheels_on_TRI_-1_Soil_Simulant | Copyrighted paper (publisher/authors). **Cited for one number only** (rolling resistance about 0.12). Do not copy figures or text. | Rover physics constants (`game/docs/SCIENCE_AND_DATA.md`, Data Sources) |

## 6. NASA Space Apps challenge resources (design inspiration; cited, not copied)

From the "NASA Space Apps Challenge resources" group in `data_sources.json`. NASA does not endorse the game.

| Name | Source URL | Used where |
|---|---|---|
| *Design and Develop Science Missions*, NASA Systems Engineering Webinar (2025) | https://www.nasa.gov/wp-content/uploads/2025/04/250323-design-and-develop-science-mission.pdf | Mission structure: launch / space / ground / user segments |
| *Concept Maturity Levels* (JPL) | https://dataverse.jpl.nasa.gov/dataset.xhtml?persistentId=hdl:2014/44299 | Goal to loadout to forecast design flow |
| Mission Design Lab (NASA Goddard) | https://etd.gsfc.nasa.gov/capabilities/integrated-design-center/mission-design-lab/ | M3 route trade study |
| *Build It Yourself: A Learning Game About Telescopes* (NASA Webb) | https://science.nasa.gov/mission/webb/game-build-it-yourself/ | Design idea: the goal drives the engineering, results explained afterwards |

Licence for all four: NASA/JPL/GSFC public material *(general knowledge)*; ideas only.

## 7. Audio and music

| Name | Source | Licence | Used where |
|---|---|---|---|
| **Kenney, *Impact Sounds* 1.0** (2019-12-19; zip sha256 `029d734a...5de77f8` in `SOURCES.md`) | https://kenney.nl/assets/impact-sounds | **CC0 1.0** (*repo*: `game/music/samples/kenney_impact/License.txt`); credit appreciated, not required | 30 kept files (`footstep_snow`, `footstep_concrete`, `impactSoft_medium/heavy`, `impactGeneric_light`, `impactWood_heavy`, each 000-004) in `game/music/samples/kenney_impact/`. `game/music/sfx_sounds.py` slows, filters and mixes them into the shipped sounds in `game/res/audio/sfx/` (steps, landings, regolith and hard impacts, bump, door, latch and charger clunks). **Not credited anywhere in the game.** |
| **GeneralUser GS 2.0.3** soundfont (S. Christian Collins) | https://www.schristiancollins.com (downloaded from https://github.com/mrbumpy409/GeneralUser-GS) | Custom GeneralUser GS licence v2.0 (*repo*: `game/music/soundfonts/LICENSE.txt`): free for private and commercial use, **but the author cannot guarantee every contained sample's origin**. See **F2**. | Only the `felt_piano` voice of `game/music/tracks/deep_space_memory.py`, rendered through FluidSynth and heavily processed into `game/res/audio/music/deep_space_memory.ogg` (the game's music, `audio_manager.gd`). The `.sf2` itself is git-ignored and not shipped. |
| Brian Eno, *Apollo: Atmospheres and Soundtracks*; (style notes also name two other games) | n/a | **Inspiration for feel only**; `game/music/CLAUDE.md` forbids quoting or imitating any melody | The Deep Space music mood; no audio or notes taken |
| Synthesised audio: `deep_space_memory.ogg` pads/drone/bells, UI sounds (`game/res/audio/ui/*.wav`), ambience beds (`amb_moon.ogg`, `amb_workshop.ogg`), engine rumble, door loop, charger/battery tones | Written by this project: `game/music/synth.py`, `ui_sounds.py`, `sfx_sounds.py`, `tracks/` | Ours; the scripts use no samples (the Kenney files are the only recorded samples) | `game/res/audio/music`, `ui`, `sfx` |

The in-game credits say "MUSIC AND SOUND: Tandborste", which leaves out the two rows above.

## 8. AI tools

As answered by the team.

| Tool | What for | Evidence | Notes |
|---|---|---|---|
| **Claude Code (Anthropic)**: Claude Opus 5.5, Claude Sonnet 5.5 | **Code, the Blender model scripts and the music composition.** The GDScript game code, the build tools, the Blender generator scripts that produce every 3D model, the terrain pipeline, and the scripts that compose and synthesise the music (`game/music/`), plus UI work, the mission-card render script and the docs. | 156 of 294 commits carry a `Co-Authored-By: Claude` trailer (138 Opus 5.5, 18 Sonnet 5.5) | Credited in the credits roll and `CREDITS.md`. The 3D models are produced by scripts, not by an image or mesh generator. |
| **Claude Code: images** | **Images**: every 3D model and render comes from the Blender generator scripts and the render scripts (`game/tools/render_mission_images.gd`). **Title logo:** an AI-generated silhouette **drawn as SVG by Claude**, based on NASA's photograph of Bruce McCandless II, STS-41-B, 1984. | `game/res/ui/astronaut_logo.svg` (**F4**); the `PROVENANCE.md` files | No separate image generator. |
| **Claude Code: sound effects** | **Sound effects**: the synthesis scripts in `game/music/` (`sfx_sounds.py`, `ui_sounds.py`, `synth.py`), plus the **Kenney CC0** samples and the **GeneralUser GS** soundfont (sections 2 and 7) | `game/music/samples/SOURCES.md` | No separate sound generator. GeneralUser GS: see **F2**. |
| **Mixamo** (Adobe) | Planned source of astronaut animations | `tools/blender/ASTRONAUT_KIT.md`: "Uploading it to Mixamo hasn't been tried"; `astronaut.glb` has no animations | **Not used.** Add Mixamo's terms and a credit if that changes. |

ChatGPT and ElevenLabs appear only in the planning documents. The team did not list them, so they are
not counted as used here. If a voice tool is used for the missing voice files (**F6**), add it.

## 9. Original work (no third-party content)

All made by this project's scripts; the `PROVENANCE.md` files record "nothing third-party":

- Workshop kit (`game/res/models/workshop_kit/`), IRIS kit (`iris_kit/`), astronaut kit (`astronaut_kit/`),
  decor kit (`decor_kit/`), rover kit (`rover_kit/`), lander kit (`lander_kit/`).
- Tyre-track textures `track_albedo.png`, `track_normal.png` (`make_track_texture.py`).
- All 14 shaders in `game/src/**/*.gdshader*`. **No shader or code was found that is copied from elsewhere**
  (no `Shadertoy`, `godotshaders.com`, StackOverflow or GitHub source attribution in any file; a search of
  comments for "adapted from", "ported from", "copied from" found nothing). The regolith shader's header
  says it is procedural. This is a text search, not a similarity check.
- Rover design is "inspired by" NASA's Curiosity (reference render: **F3**); no NASA mesh was used
  (`docs/ASSET_PLAN.md`: "No NASA mesh fits any of these").
- `game/res/textures/dev/*.png`, `game/res/textures/ui/*.svg` (crosshair, interaction): simple UI/dev
  graphics; no source recorded, no sign of third-party origin.
- Mission cards `game/res/ui/missions/*.png`: renders of the game's own scenes (include NASA terrain, section 4).
- `docs/ui/screenshots/*.png`: renders of our design boards. Not shipped.

## 10. Doc-only references (cited in design docs; not shipped, not in `data_sources.json`)

These appear in `game/docs/SCIENCE_AND_DATA.md`, `game/docs/ASSET_BRIEF.md`, `game/README_GAMEPLAY.md` or the
plan documents. Add them to the Space Apps field only if you want the full reading list.

| URL | Where cited |
|---|---|
| https://science.nasa.gov/3d-resources/ and /curiosity-rover-msl/ (NASA 3D Resources: reference only, "check each licence") | `ASSET_BRIEF.md`, `docs/ASSET_PLAN.md` |
| https://science.nasa.gov/mission/surveyor-3/ | `ASSET_BRIEF.md`, `SCIENCE_AND_DATA.md` |
| https://www.nasa.gov/wp-content/uploads/static/history/alsj/HamishALSEP.html (Apollo Lunar Surface Journal) | `ASSET_BRIEF.md` |
| https://www.nasa.gov/centers-and-facilities/johnson/designing-space-exploration-with-the-human-in-mind/ | `ASSET_BRIEF.md` |
| https://science.nasa.gov/moon/weather-on-the-moon/ | `SCIENCE_AND_DATA.md`, the story plan |
| https://astrobiology.nasa.gov/news/restoring-data-from-the-apollo-missions/ | `SCIENCE_AND_DATA.md` |
| https://data.nasa.gov/dataset/lunar-prospector-grs-elemental-abundance-v1-0 and the PDS `lp_grs_derived` collection | `SCIENCE_AND_DATA.md` |
| https://www1.grc.nasa.gov/beginners-guide-to-aeronautics/ideal-rocket-equation/ | `SCIENCE_AND_DATA.md`, `README_GAMEPLAY.md` |
| https://docs.godotengine.org/en/stable/ (VehicleBody3D, signals, resources) | `game/README_GAMEPLAY.md` |
| https://www.spaceappschallenge.org/2026/find-a-team/missionforge/ | the story plan (our team page) |

## 11. Check against the credits files

Compared `CREDITS.md`, `game/res/credits.md` (the in-game roll) and `game/res/story/data_sources.json`,
after the credits update and this one:

| Resource | `CREDITS.md` | `credits.md` (in game) | `data_sources.json` |
|---|---|---|---|
| LROC NAC DTM, orthophoto, SLDEM2015, human-features PDF, Horizons | yes | yes (grouped) | yes (the DTM's confidence map is only in `CREDITS.md`) |
| Star map, CGI Moon Kit, Blue Marble | yes | yes (Moon Kit not named separately) | yes |
| Apollo photographs | yes | no (the cards print their own credit) | yes (links one of the two) |
| USGS Gazetteer (Head crater) | yes | yes | yes |
| Moon by the Numbers, lunar atmosphere, LRO/Diviner | no | no | yes |
| TRI-1 wheel paper | no | no | yes |
| Henriksen 2017, Barker 2016 | yes | no | yes |
| Space Apps challenge resources (section 6) | yes | yes | yes |
| Godot Engine (name, MIT text, third-party notices) | yes (name, how the roll gets the rest) | yes (name; the licence section is generated) | no |
| Blender | yes | yes | no |
| Fonts: all four, copyright lines, OFL notice | yes | yes | no |
| Kenney *Impact Sounds* (CC0) | yes | yes | no |
| GeneralUser GS soundfont | yes | yes | no |
| AI: Claude Opus 5.5 / Sonnet 5.5 (code, Blender scripts, music) | yes | yes | no |
| AI: title logo (Claude, as SVG) and its NASA source photo | yes | yes | no |
| AI: images and sound effects (Claude Code scripts; Kenney, GeneralUser GS) | yes | yes | no |
| Curiosity reference image (not shipped) | yes (msl-curiosity link) | no (not shipped) | no |
| ~~Default Godot icon~~ | replaced by our own icon (**F5**) | | |

`data_sources.json` says its facts come from `game/docs/SCIENCE_AND_DATA.md` and `CREDITS.md` and "keep
them in step"; the NASA pages in the rows marked **no** under it are the remaining gap.
