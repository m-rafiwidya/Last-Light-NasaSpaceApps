# Claude Code prompts, in order

Paste one prompt per session (or per `/clear`). Review and commit after each before starting the next. Work on a branch, not main.

Every prompt follows the handoff rules in `README_AI.md`: inspect what exists first, reuse the current architecture, one bounded task, report what changed and what wasn't checked.

## 0. Import the story handoff (docs only)

> I'm adding our team's final story handoff to the repo. The zip is at <path>. Read its START_HERE.md and follow its "Put this into the repository" section: copy the planning files into the matching paths, keep our existing technical README and link the new docs from it, and reconcile with AGENTS.md / CLAUDE.md if present. Docs only: do not change any code, scenes or assets. Show me the file list before committing.

## 1. Add the UI design package (docs only)

> Copy the folder I've provided into docs/ui/ (UI_SPEC.md, PROMPTS.md, boards/, assets/, screenshots/). Docs only, no code. Then read docs/ui/UI_SPEC.md and tell me, in a short list, which existing scenes and scripts under src/ui/ correspond to each screen in the spec, and which screens don't exist yet. Don't change anything.

## 2. Shared theme and fonts

> Read docs/ui/UI_SPEC.md (Design tokens, Shared components, Godot notes). Import the fonts from docs/ui/assets/fonts/ into the project's assets, and create one shared Godot Theme with: the colour tokens, FontVariations for Michroma / Exo 2 / IBM Plex Mono at the listed sizes and letter-spacing, and StyleBoxes for the underline text button, the solid slanted button, the slanted tab (inactive/active), the back button and the key chip. Add small reusable scenes for the underline button (with the tweened underline, same on hover and focus), the back button and the key chip. Don't restyle existing screens yet. Show me a quick test scene with each component.

## 3. Main menu and opening sequence

> Read docs/ui/UI_SPEC.md (Main menu) and docs/ui/boards/Main.dc.html plus docs/ui/screenshots/ for it. Inspect our current main menu first. Rebuild it to match: left column with the floating astronaut logo (docs/ui/assets/astronaut-logo.svg), LAST LIGHT and PLAY / SETTINGS / QUIT GAME using the shared theme, and on the right the existing 3D Moon (keep it 3D, slow rotation, drag to rotate, hover highlight). Add the skippable opening sequence with the timings from the board's CSS. Keep the existing settings/quit wiring. Do not build the Play popup or planet explorer yet. Report files changed and what you couldn't check.

## 4. Play popup and save slots

> Read the Play section of docs/ui/UI_SPEC.md and the play popup parts of docs/ui/boards/Main.dc.html. First find how the game currently saves/loads (campaign state, checkpoints). Implement the PLAY popup: blurred menu behind, back button, and two states. No save: "There's no save file." with START NEW CAMPAIGN. Saves exist: the save card list (mission image, date/time, mission name, story progress bar and %, time played, Autosave tag), hover/focus selection with the corner-bracket frame, Enter/click to load, Esc to cancel, and START NEW CAMPAIGN under the list. Read save metadata from the real save system; if it doesn't store last-played time, play time, mission id or progress yet, add those fields to the save data without changing how gameplay state is stored. Use a placeholder image per mission id until we provide real ones (16:9). Starting/loading goes through the loading screen. Report what you changed in the save format.

## 5. Planet explorer

> Read the Planet explorer part of docs/ui/UI_SPEC.md and docs/ui/boards/Main.dc.html (the planets() data has the sites). Clicking the main-menu Moon opens the explorer: back button, planet title, centred 3D globe with clickable site markers and the tooltip card, prev/next buttons, MOON / EARTH tabs with planet-coloured underlines, and the locked states. Lock state comes from campaign progress (Earth after finishing). Keep it self-contained in the menu scene.

## 6. Loading screen

> Read the Loading section of docs/ui/UI_SPEC.md and docs/ui/boards/Loading.dc.html. Restyle our existing loading screen to match: facts with dots, floating astronaut, stage text, percentage and progress bar driven by the real load progress, CONTINUE when done. Use the fact list from the board. Rename any "ROOK" stage text to "KITE".

## 7. Pause and settings

> Read the Pause and Settings sections of docs/ui/UI_SPEC.md and docs/ui/boards/Pause.dc.html and Settings.dc.html. Restyle the existing pause menu (centred, underline buttons, blurred game behind) and settings (slanted tabs, rows, BACK / RESET). Then make every settings control actually apply and persist (video, audio, controls key rebinding with the InputMap, mouse sensitivity, subtitles). List any setting you couldn't wire and why.

## 8. In-game HUD

> Coordinate with the former teammate first: the HUD reads mission state. Read the HUD section of docs/ui/UI_SPEC.md and docs/ui/boards/HUD.dc.html, and game/README_GAMEPLAY.md for the real objectives. Inspect hud.gd and robot_hud.gd and the signals the mission/rover systems already emit. Restyle and extend the HUD: objectives panel top-right driven by the real active objective, compass strip with target/home markers, battery bar with range estimate and return warning, radio subtitle line with speaker, context prompts with key chips from the InputMap, first-time control hints instead of the permanent control lists, and hide the friction-circle debug panel behind a debug toggle. Keep each camera view's existing overlay. Don't change mission logic.

## 9. Mission console

> Read the Mission console section of docs/ui/UI_SPEC.md and docs/ui/boards/Console.dc.html, plus the console requirements in Tandborste-Game-and-Story-Plan.md ("One console: Mission / Kite / Downlink. One large Control Kite button."). Replace the placeholder email-client console with that design and make it reachable on the Moon level from the workshop terminal. Content comes from the mission state and STORY_SCRIPT.md, not the board's placeholder text.

## 10. Mission complete and credits

> Read the Mission complete and Credits sections of docs/ui/UI_SPEC.md and the matching boards. Build the mission result screen using the real results listed in STORY_SCRIPT.md ("Ending presentation"), with CONTINUE / REPLAY MISSION / MAIN MENU and the partial-result variant. Then build the credits roll from the board, with WATCH AGAIN / MAIN MENU and SKIP.
