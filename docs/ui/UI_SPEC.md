# LAST LIGHT UI spec

Design reference for the game's menus, screens and HUD. The boards in `boards/` are the source of truth for layout, sizes, timing and behaviour. This file collects the shared rules and the per-screen intent so an implementation stays consistent.

## How to read the boards

- Each `boards/*.dc.html` is one screen, drawn at **1600 × 900**. Open it in a text editor: the markup is plain HTML with inline styles, the `<style>` block holds the classes, and the `<script>` block holds the behaviour (`renderVals()` shows what each state displays; handlers show transitions).
- `{{name}}` holes, `<sc-if>` and `<sc-for>` are the design tool's templating. `sc-if` means "shown when true", `sc-for` means "repeat for each item". `data-props` at the bottom lists the preview toggles (for example `saveFile`, `mode`, `alert`); they show the states a screen must support.
- `/_blob/bb123daca0826d320dc695b61684775a` in the boards is `assets/astronaut-logo.svg`.
- Canvas drawing code (starfield, the JS globe) is a stand-in. Implement those natively in Godot (see "Godot notes").
- **All text on the boards is placeholder.** Names, mission titles, objectives and radio lines come from `game/docs/STORY_SCRIPT.md` and `game/docs/examples/MISSIONS.json`. In particular the HUD, Console and Complete boards were drawn before the final story; their names are now updated (the player's rover is **Kite**, the destination **IRIS**), but "diagnostic cartridge" means the mission's cargo (for example the replacement radio-power module).

## Design tokens

### Colour

| Token | Hex | Use |
|---|---|---|
| bg | `#050507` | Every full-screen background, behind the starfield |
| text | `#ECE9E3` | Primary text, active states, light buttons, bars, underlines |
| text-2 | `#C9C4BB` | Secondary headings, subtitle-style lines |
| text-3 | `#B5B2AC` | Tertiary text, hint labels, icon buttons |
| muted | `#8A8783` | Captions, inactive menu items, labels |
| dim | `#6B6863` | Completed/struck-through items, SKIP, minor buttons |
| disabled | `#4A4844` | Locked items, empty checkboxes |
| ink | `#141417` | Text on light buttons, key chips and selects |
| panel | `#1B1B1F` (hover `#26262B`) | Inactive tabs, ghost buttons |
| line | `#1E1E22`, `#1C1C20`, `#2A2A2E` | Track of bars, row dividers, icon button borders |
| warn | `#E5484D` | Low battery, boundary warning, fault dots. The only "alert" colour |
| moon / mars / earth | `#C9C4BB` / `#C8643A` / `#4C8FD6` | Planet tab underline in the explorer only |

**No orange anywhere else.** Keep the palette white-on-near-black with greys; red only for warnings.

### Type

| Font | Use |
|---|---|
| **Michroma** 400 | Titles, menu items, buttons, small all-caps headings. Always uppercase with wide letter-spacing |
| **Exo 2** 400/500/600 | Body text, HUD text, captions, loading facts' captions, popups, "Did you know?" |
| **IBM Plex Mono** 400/500 | Small technical UI: settings rows, loading stage, SKIP, explorer tooltips |

Font files (OFL licence) are in `assets/fonts/`.

Common sizes at 1600 × 900 (scale proportionally):

| Element | Font / size / letter-spacing |
|---|---|
| Game title "LAST LIGHT" | Michroma 40, spacing 22 |
| Main menu items | Michroma 18, spacing 10 |
| Screen title (PAUSED, MISSION COMPLETE) | Michroma 26, spacing 16 |
| Mission title card | Michroma 44, spacing 20 |
| Loading fact | Michroma 30, line height 1.55, spacing 1 |
| Pause items / underline buttons | Michroma 15, spacing 6 to 8 |
| Solid button | Michroma 13, spacing 5 |
| HUD section heading (KITE, WORKSHOP) | Michroma 13, spacing 6 |
| Body / HUD values | Exo 2 14 to 20, weight 500 or 600 |
| Captions | Exo 2 12 to 15, weight 500, muted |
| Settings rows | IBM Plex Mono 12, spacing 1 |

## Shared components

1. **Underline text button** (main menu, pause, console tabs). Michroma, muted grey. On hover/focus: text turns `text`, a 1px `text` underline grows under it in 0.35 s. Main menu and console tabs grow from the left; pause and centred menus grow from the centre. Active tab keeps the full underline.
2. **Primary underline button** (Loading CONTINUE). White text, underline sits at 25 % width and grows to 100 % on hover.
3. **Solid slanted button** (START NEW CAMPAIGN, settings BACK/RESET). `text` fill, `ink` text, parallelogram (slant 10 to 12 px each side), height 36 to 48. Hover: pure white and 1 px lift.
4. **Slanted tabs, selects, toggles, key-bind slabs** (settings). Same parallelogram shape. Inactive tab `panel` with muted text; active tab `text` fill with `ink` text. Toggle 52 × 22, knob moves right and track turns light when on.
5. **Back button**. 48 × 48 square, 1 px `#2A2A2E` border, 20 px left chevron (stroke 1.8), colour `text-3`; hover border `muted`, chevron `text`. Always top-left at (56, 48). Same component for the planet explorer, Play popups and anything else that goes back.
6. **Key chip**. Small `text` parallelogram (22 px high, slant 5 px) with the key in Exo 2 12 600 `ink`, followed by the action label. Used in the HUD prompts and popup footers ("Esc Cancel", "Enter Load").
7. **Framed popup / selected card**. Black at 72 to 78 % opacity, 1 px border `rgba(236,233,227,.85)`, soft glow `0 0 18px rgba(236,233,227,.12)`, and four 9 px corner brackets (2 px, offset 4 px outside the frame). Unselected cards: 1 px `#2A2A2E` border, no brackets.
8. **Starfield**. Seeded random stars on `bg`: about 500 per 1600 × 900, radius 0.7 / 1.1 / 1.6 px (rare large), alpha 0.2 to 0.8. Static.
9. **Floating astronaut** (logo). `assets/astronaut-logo.svg`, 7 s ease-in-out loop: translate (0,0) → (7,-14) → (2,-22) → (-6,-10) → (0,0) px with rotation -2° → 1.5° → 4° → 0.5° → -2°, pivot at 55 % / 45 %.
10. **Segmented bar** (battery, story progress). Thin slanted segments, filled `text`, empty `#2A2A2E`; low battery fills `warn`.

## Motion

- Entrances: fade + 8 to 10 px rise, 0.45 to 0.6 s, staggered 0.04 to 0.05 s per item.
- Popups: open with the menu behind blurring (about 10 px) and dimming to ~45 %, 0.5 s.
- Pause: game view blurs 6 px and darkens to 50 %; settings blurs 10 px and darkens to 30 %.
- Notifications: info toast slides down, holds, fades out over 5 s. Warnings stay until resolved and use a 1.6 s blinking `warn` dot.
- Avoid big zooms, flares or "slideshow" transitions. Quiet and smooth.

## Screens

### Main menu (`Main.dc.html`)

- Left column at x 150: floating astronaut (150 × 170), "LAST LIGHT", then PLAY / SETTINGS / QUIT GAME (underline buttons, no dashes or bullets).
- Right side: a large **3D Moon** that slowly rotates and can be dragged. Hover brightens it slightly; click opens the planet explorer.
- **Opening sequence** (first launch, skippable with SKIP bottom-right): black, "TANDBORSTE PRESENTS" fades in and out, the Moon rises in, the astronaut drifts in from the left, "LAST LIGHT" resolves from blur, the menu items slide in. Total about 10 s. Timings are in the board's CSS (`.ll-intro ...`).
- **PLAY** opens a popup over the blurred menu:
  - **No save file**: framed popup, "There's no save file.", solid button START NEW CAMPAIGN → loading → mission title card → game.
  - **Save files exist**: "Select save data to load." and a list of save cards (newest first). Each card: mission image (16:9, one image per mission), date and time (DD/MM/YYYY HH:MM), mission name, a small story-progress bar with %, time played top-right, and a slanted "Autosave" tag on autosaves. Hover/focus selects a card (frame + corner brackets). Click/Enter loads → loading → title card ("Resuming · <current objective>"). Under the list: the same START NEW CAMPAIGN button. Footer: "Enter Load", "Esc Cancel". Back button top-left.
- **Planet explorer**: back button top-left, planet name centred at the top (Michroma 26), the planet globe centred (about 640 px), prev/next chevron buttons either side, tabs MOON / MARS / EARTH at the bottom with a planet-coloured underline on the active one. Locked planets show a lock and a hint ("COMPLETE THE MOON MISSIONS", "FINISH THE GAME"). Markers on the globe open a tooltip card (name, rows such as LANDED / CREW / REGION / COORDS, short note). Apollo 12 is marked "WHERE LAST LIGHT TAKES PLACE". Earth shows the team members' cities. Site data is in the board's `planets()`.

### Loading (`Loading.dc.html`)

"Did you know?" (Exo 2 22 600) above one fact (Michroma 30) and its source caption, with dots for which fact is showing. Facts rotate about every 7 s. Floating astronaut on the right. Bottom: stage text in IBM Plex Mono (LOADING TERRAIN, PREPARING THE WORKSHOP, WAKING UP KITE, ALMOST THERE), percentage on the right, 2 px progress bar. When done: CONTINUE (primary underline button). Fact list is in `facts()`.

### Pause (`Pause.dc.html`)

Centred: PAUSED, a 48 px rule, then RESUME / SWITCH TO TEST LEVEL / SETTINGS / QUIT TO MENU / QUIT TO DESKTOP as underline buttons growing from the centre. Game view blurred behind. No objective panel here.

### Settings (`Settings.dc.html`, also reachable from Pause)

Framed panel with SETTINGS, slanted tabs GENERAL / AUDIO / VIDEO / CONTROLS, and rows of label + control (select, toggle, slider with value, or key-bind slab that shows "PRESS A KEY" while listening). RESET TO DEFAULTS on General, RESET BINDINGS on Controls, BACK at the bottom. The full option list and default values are in `defaults()` and `layout()` and mirror the existing settings menu. Every control must actually apply.

### Credits (`Credits.dc.html`)

48 s roll on the starfield with the astronaut drifting across: logo and title, A GAME BY TANDBORSTE, TEAM (name + university), REAL DATA (NASA sources), BUILT WITH, TYPE, MUSIC AND SOUND, SPECIAL THANKS, closing note on what is real and what is fiction. Ends on THANK YOU FOR PLAYING with WATCH AGAIN / MAIN MENU. SKIP bottom-right. Update team roles and special thanks before release.

### In-game HUD (`HUD.dc.html`)

Small, quiet, no permanent key list.

- **Top-left**: location ("Apollo 12 site" / "Oceanus Procellarum") and mission time.
- **Top-centre**: compass strip (about 560 px, 4 px per degree, edges fade out) with N/NE/E... labels, tick marks, markers for the current target and home, and the numeric heading below.
- **Under the compass**: notification slot. Info toasts (white dot, fade out) or persistent warnings (blinking red dot): boundary warning, low battery / can't make it back.
- **Top-right**: objectives. Mission label, current goal, the checklist (done = tick + strike-through, current = filled marker, pending = empty square), then a pointer with target name and distance.
- **Bottom-left while driving**: rover name, active camera view, segmented battery bar with % and estimated range ("~220 m left"), speed, cargo, distance to the charging pad.
- **Bottom-left on foot (workshop)**: area name, what you're holding, rover status.
- **Bottom-centre**: radio subtitle line with the speaker name above it (Michroma 11, muted), one line at a time.
- **Above it / centre**: context prompt with a key chip ("E  Insert module", "E  Use console").
- **Bottom-right**: one "New control" or "Tip" card the first time a control matters, plus the leave/exit hint. Esc stays Pause.
- **Crosshair**: corner brackets + dot for the rover camera; small dot on foot.
- States to support: driving / on foot, each objective step, info toast / boundary warning / low battery / none, radio on/off.

### Mission console (`Console.dc.html`)

Full-screen console on the starfield: header (MISSION CONSOLE, location, mission time), left nav of underline tabs, content on the right, footer key hints ("Tab Next section", "Esc Close console"). The board shows Briefing (mission text + numbered objectives), Status (live telemetry rows and a report section that appears after a scan) and Site map (top-down SVG with base, rover, target, route, dashed boundary, north arrow, scale bar). **The final story asks for Mission / Kite / Downlink sections and one large "Control Kite" button**; build those with this visual language.

### Mission complete (`Complete.dc.html`)

Centred like Pause: mission label, MISSION COMPLETE, 48 px rule, one-line result, four stats separated by thin dividers (time, distance, battery used, rover returned), a final radio line with speaker, then CONTINUE / REPLAY MISSION / MAIN MENU. Has a variant for a partial result (rover not returned). Use the chapter-ending results the story script lists (station restored, archive complete, records received, rover recovered, energy used, assistance).

## Godot notes

- Build a shared **Theme** first (fonts, colours, StyleBoxes for each button type) and use it everywhere. Use `FontVariation` resources for letter-spacing (`spacing_glyph`) and weights.
- Parallelogram shapes: `StyleBoxFlat` with `skew` (Godot 4.2+), or a small polygon/shader if the version lacks it.
- Underline animation: a 1 px `ColorRect` under the label, width tweened with `Tween` on focus/hover. Make focus and hover identical so keyboard/gamepad navigation looks the same as the mouse.
- Blur behind popups and pause: a full-screen `ColorRect` with a shader sampling `SCREEN_TEXTURE`/`hint_screen_texture` with mip blur, plus a dark tint.
- Starfield: one static texture or a `_draw()` on a `Control` with a fixed seed.
- Main menu Moon: a real 3D sphere in a `SubViewport` (lunar colour texture, slow rotation, mouse drag). Do not replace it with a flat 2D image. The explorer's Moon/Mars/Earth globes are the same idea with clickable site markers.
- Design resolution 1600 × 900. Use stretch mode `canvas_items` with aspect `expand` and anchor the HUD to screen corners so it works at 16:9 and 16:10.
- Key chips should read the real bound key from the InputMap, not hard-coded letters.
