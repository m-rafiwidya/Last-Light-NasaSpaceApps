# Credits

Third-party assets in this repository and where they come from. NASA imagery is used under
NASA's media usage guidelines; no endorsement by NASA or ESA is implied.

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

## Moon terrain

`game/res/terrain/moon_site01/`: the Moon level's ground, made by `tools/terrain/build_moon_terrain.py`
(see `tools/terrain/MOON_TERRAIN.md`) from NASA Lunar Reconnaissance Orbiter LOLA data. The game
data are converted (to metres in a local frame, with the Moon's curvature), resampled and, in the
play area, given procedural small craters, roughness and rocks; the large-scale shape is NASA's.

- **LOLA 5 m/pixel south pole landing site DEMs**, Site01 "Connecting ridge", NASA Goddard Space
  Flight Center Planetary Geodesy Data Archive (PGDA), <https://pgda.gsfc.nasa.gov/products/78>;
  Barker, M. K., et al. (2021), Improved LOLA elevation maps for south pole landing sites,
  Planetary and Space Science 203, 105119, doi:10.1016/j.pss.2020.105119
- **LOLA permanently shadowed regions, 20 m/pixel** (`LPSR_80S_20MPP_ADJ`), NASA GSFC PGDA,
  <https://pgda.gsfc.nasa.gov/products/90>
- **LOLA gridded data records** `LDEM_875S_20M` and `LDEM_85S_40M`, NASA Planetary Data System
  Geosciences Node, <https://pds-geosciences.wustl.edu/lro/lro-l-lola-3-rdr-v1/lrolol_1xxx/data/lola_gdr/polar/img/>

Every source file's URL, byte count and SHA-256 are recorded in `terrain.json` (`sources`).
