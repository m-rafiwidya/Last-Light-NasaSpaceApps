# Sample sources

Every recorded sample the game's sounds are built from. Only CC0 (public domain) samples go here.
`sfx_sounds.py` reads them; nothing here is copied into the game as is.

| Folder | Source | License | Downloaded | Used for |
|---|---|---|---|---|
| `kenney_impact/` | Kenney, *Impact Sounds* 1.0 (2019-12-19): https://kenney.nl/assets/impact-sounds (zip `kenney_impact-sounds.zip`, sha256 `029d734af1582474edf3a694d1b0cebc97c1c152f2f39fa34d4c2bafc5de77f8`) | CC0 1.0 (`kenney_impact/License.txt`) | — | see below |

Files kept from the Kenney pack (the rest of the pack is not used):

| Files | Used in (`sfx_sounds.py`) |
|---|---|
| `footstep_snow_000`–`004` | regolith crunch: `step_regolith`, `land_regolith`, `impact_regolith_*`, `bump`, and the grains of `rolling_loop` |
| `footstep_concrete_000`–`004` | workshop floor: `step_floor`, `land_floor` |
| `impactSoft_medium_000`–`004` | soft bodies under steps, regolith impacts, latch clunks (`part_seat`, `part_release`, `charger_connect`) |
| `impactSoft_heavy_000`–`004` | landings, heavy impacts, `bump`, `door_start`, `door_stop` |
| `impactGeneric_light_000`–`004` | hard-surface impacts, the faint click in latches |
| `impactWood_heavy_000`–`004` | hard-surface medium/heavy impacts, `bump`, the bay door's knocks, `charger_connect` |

Every sample is slowed or kept as is, steeply lowpassed (about 0.5–1.6 kHz) and given a short
room or none, so it fits the Deep Space style. The Kenney metal, bell, glass, tin and plate hits
ring and are not used.

The synthesised sounds (grab, drop, throw, the tones in latches, power, link, battery, charger,
the bay door's drive, both ambience beds) use no samples.
