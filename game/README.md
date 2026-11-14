# Game (Godot 4) - Architecture & Context Guide

This document explains how the current game works: boot sequence, global state, UI, level loading, the player, and the small dialog/interaction systems. It is written for both humans and AI agents. Everything here was verified against the code in `src/` (see [Known issues](#13-known-issues--gotchas--todos) for places where code and intent disagree).

## 0. Reading order (start here)

Follow the code in this order and the whole game will make sense:

1. `src/main.tscn` and `src/main.gd` - the entry point. They instantiate `UIManager`.
2. `src/ui/ui_manager/` - owns every UI screen and reacts to game-state changes.
3. `src/ui/main_menu/` - the first screen the player sees.
4. `src/autoloads/scene_loader.gd` - loads levels, spawns the player.
5. `src/player/` - the physics-based first-person player.
6. `src/robot/` - the drivable robot (currently what `SceneLoader` spawns instead of the player, see [section 15](#15-robot)).

Then the supporting pieces: `game_state.gd`, `dialog_server.gd`, `debug.gd`, HUD, pause menu, console.

---

## Table of contents

1. [Quick facts](#1-quick-facts)
2. [Directory map](#2-directory-map)
3. [Autoloads (global singletons)](#3-autoloads-global-singletons)
4. [Boot sequence](#4-boot-sequence)
5. [Game state machine](#5-game-state-machine)
6. [UI layer](#6-ui-layer)
7. [Scene loading](#7-scene-loading)
8. [Player](#8-player)
9. [Interaction & object pickup](#9-interaction--object-pickup)
10. [Dialog system](#10-dialog-system)
11. [Debug console](#11-debug-console)
12. [Input map & physics layers](#12-input-map--physics-layers)
13. [Known issues / gotchas / TODOs](#13-known-issues--gotchas--todos)
14. [Recipes: how to extend the game](#14-recipes-how-to-extend-the-game)
15. [Robot](#15-robot)

---

## 1. Quick facts

| Item | Value |
|---|---|
| Engine | Godot 4.7 (`config/features`), Forward Plus renderer |
| Physics | Jolt Physics (`3d/physics_engine`) |
| Main scene | `res://src/main.tscn` |
| Viewport | 1920x1080, stretch mode `viewport`, aspect `expand` |
| Language | GDScript |
| Game type | First-person 3D, rigidbody character, physics prop pickup, subtitle/dialog system, drivable robot (placed in the level, entered via an interact trigger) |
| Content | One level only: `src/levels/test_level.tscn` (also reused as the main-menu backdrop) |
| Theme | `res/theme.tres` (shared by all UI) |

The repository has three top-level folders (`backend/`, `database/`, `game/`). This document only covers `game/`.

---

## 2. Directory map

```
game/
├── project.godot            # autoloads, input map, display, physics engine
├── res/                     # raw assets
│   ├── theme.tres           # global UI theme
│   └── textures/{dev,ui}/   # dev grid textures, crosshair.svg, interaction.svg
└── src/
    ├── main.tscn / main.gd           # entry point (root "Main" node)
    ├── autoloads/
    │   ├── scene_loader.gd           # level loading + player spawning
    │   ├── game_state.gd             # state machine, pause, mouse mode
    │   ├── debug.gd                  # console log + command parser
    │   └── dialog_server.gd          # subtitle timing + signals
    ├── object_holder/
    │   └── object_holder.gd                  # shared pick up / hold / throw logic for the player and the robot (class ObjectHolder)
    ├── robot/
    │   ├── robot.tscn / robot.gd                 # RigidBody3D vehicle sim (class Robot)
    │   ├── robot_controller.gd                 # keyboard + mouse input -> desired_speed/steer/look vars + interact/primary signals (class RobotController)
    │   └── components/                       # engine.gd/.tscn (RobotEngine), running_gear.gd/.tscn (RunningGear), engine_sound.gd (motor whir)
    ├── dialog/
    │   ├── dialog.gd                 # Resource: one subtitle line (+ future audio)
    │   └── dialog_sequence.gd        # Resource: ordered array of Dialog
    ├── interact_trigger/
    │   └── interact_trigger.gd       # Area3D the player can "use" with E
    ├── levels/
    │   └── test_level.tscn           # the only level
    ├── player/
    │   ├── player.tscn / player.gd           # RigidBody3D character (class Player)
    │   └── player_controller.gd              # input -> intent (class PlayerController)
    └── ui/
        ├── ui_screen.gd              # base class (CanvasLayer) with fade_in/fade_out
        ├── ui_manager/               # orchestrates all screens
        ├── main_menu/
        ├── pause_menu/
        ├── hud/                      # player HUD (crosshair, subtitles)
        ├── robot_hud/                # robot HUD (speed readout, controls hint)
        ├── loading_screen/
        ├── console/
        ├── dialog_box/               # one subtitle line widget
        ├── sub_screens/settings_sub_menu.tscn/.gd   # shared by main + pause menu (tabbed, dummy widgets)
        └── button_style_components/  # ButtonResizeComponent, ButtonSoundComponent
```

---

## 3. Autoloads (global singletons)

Registered in `project.godot` in this order. All of them are globally reachable by name.

| Autoload | File | Responsibility |
|---|---|---|
| `SceneLoader` | `autoloads/scene_loader.gd` | Loads levels on a thread, instantiates them under `Main`, spawns the player / menu camera. Emits `request_transition`, `level_loaded`, `level_unloaded`. |
| `GameState` | `autoloads/game_state.gd` | Holds the current `State`, emits `state_changed`, controls pause + mouse mode. Holds the reference to the current `player`. |
| `Debug` | `autoloads/debug.gd` | Stores console log lines and parses console commands. |
| `DialogServer` | `autoloads/dialog_server.gd` | Times and broadcasts subtitles (`dialog_played`, `dialog_ended`). |

`SceneLoader`, `GameState` are set to `PROCESS_MODE_ALWAYS` so they keep running while the tree is paused. `UIManager` is also `process_mode = 3` (ALWAYS) in its scene.

### Communication style

The architecture is **signal driven and one-directional**:

```
SceneLoader --(calls)--> GameState.change_state_to()
GameState   --(signal state_changed)--> UIManager --(calls)--> each UI screen
SceneLoader --(signals request_transition / level_loaded)--> UIManager --> LoadingScreen
LoadingScreen --(signal finished_fade_in)--> SceneLoader   (wired by UIManager)
DialogServer --(signals)--> HUD --> DialogBox
```

UI screens never decide game state themselves, except by calling `GameState.change_state_to(...)` (pause menu Resume) or `SceneLoader.load_scene(...)` (menu buttons).

---

## 4. Boot sequence

What happens from launching the game to seeing the main menu.

```mermaid
sequenceDiagram
    participant E as Engine
    participant M as Main
    participant UI as UIManager
    participant SL as SceneLoader
    participant GS as GameState
    participant LS as LoadingScreen

    E->>E: Create autoloads (SceneLoader, GameState, Debug, DialogServer)
    E->>M: Instance main.tscn
    Note over M,UI: Children become ready before the parent
    UI->>UI: _ready(): connect GameState.state_changed, SceneLoader signals
    UI->>LS: connect finished_fade_in to SceneLoader._on_finished_fade_in
    M->>SL: main_node = self
    M->>SL: load_scene("main_menu", no_fade_in = true)
    SL->>GS: change_state_to(LOADING)
    GS-->>UI: state_changed -> LoadingScreen visible, other screens fade out
    SL-->>UI: request_transition(true)
    UI->>LS: reset() (fully black immediately)
    SL->>SL: _on_finished_fade_in() directly (no fade to wait for)
    SL->>SL: ResourceLoader.load_threaded_request(level)
    loop every frame
        SL->>SL: _process polls load_threaded_get_status
    end
    SL->>SL: _setup_scene() -> instantiate, add under Main
    SL->>SL: _setup_main_menu() -> spawn Camera3D at CameraMarker
    SL->>GS: change_state_to(MAIN_MENU)
    GS-->>UI: state_changed -> MainMenu.fade_in() (slides in)
    SL-->>UI: level_loaded
    UI->>LS: fade_out() then hide()
```

Key points:

- `main.tscn` is just `Main (Node)` + an instance of `UIManager`. `main.gd` gives `SceneLoader` a reference to itself (`main_node`) so loaded levels get added as children of `Main`, then requests the `"main_menu"` level.
- The first load passes `no_fade_in = true` because there is nothing to fade from; the screen is simply black until the menu is ready.
- The **main menu backdrop is a real 3D level** (`test_level.tscn`, see `LEVEL_PATHS`) viewed through a camera placed at the level's `CameraMarker`. No player is spawned for it.

---

## 5. Game state machine

Defined in `GameState` (`enum State {MAIN_MENU, LOADING, IN_GAME_PLAYER, IN_GAME_ROBOT, PAUSED, IN_GAME_MENU, MISSION_CONSOLE}`). Initial value: `LOADING`. `IN_GAME_MENU` is declared but not used anywhere yet.

- `IN_GAME_PLAYER` is the default in-game state (first-person player active). A gameplay level always loads into it.
- `IN_GAME_ROBOT` means the robot is being driven. It is entered from `IN_GAME_PLAYER` by the `RobotTrigger` in the test level and left with Esc (`ui_cancel`), which goes back to `IN_GAME_PLAYER` (not to pause).
- `GameState.last_in_game_state` remembers which of the two was active. `PAUSED` and `MISSION_CONSOLE` leave through `GameState.return_to_game()` (Esc, Resume, the console's X button), which returns to it. `GameState.is_in_game()` is true for both.
- `MISSION_CONSOLE` is entered from `IN_GAME_PLAYER` by the `MissionConsoleTrigger` in the test level.

```mermaid
stateDiagram-v2
    [*] --> LOADING
    LOADING --> MAIN_MENU: main menu level ready
    LOADING --> IN_GAME_PLAYER: gameplay level ready (player spawned)
    MAIN_MENU --> LOADING: Start pressed
    IN_GAME_PLAYER --> PAUSED: Esc
    IN_GAME_PLAYER --> IN_GAME_ROBOT: RobotTrigger interacted
    IN_GAME_ROBOT --> IN_GAME_PLAYER: Esc
    IN_GAME_PLAYER --> MISSION_CONSOLE: MissionConsoleTrigger interacted
    MISSION_CONSOLE --> IN_GAME_PLAYER: Esc or X
    PAUSED --> IN_GAME_PLAYER: Esc or Resume
    PAUSED --> LOADING: Quit To Menu
```

### Side effects per state

`change_state_to(new)` runs `_on_state_exit(old)`, sets state, runs `_on_state_enter(new)`, then emits `state_changed(old, new)`.

| State | On enter | On exit | UI shown (via `UIManager`) |
|---|---|---|---|
| `MAIN_MENU` | Mouse mode `VISIBLE` | - | `MainMenu` |
| `LOADING` | - | - | `LoadingScreen` visible |
| `IN_GAME_PLAYER` | Mouse `CAPTURED`; remembered as `last_in_game_state` | - | `HUD` |
| `IN_GAME_ROBOT` | Mouse `CAPTURED`; remembered as `last_in_game_state`; robot camera becomes current | - | `RobotHUD` |
| `PAUSED` | Mouse `VISIBLE`, `pause_game()` | `unpause_game()` | `PauseMenu` |
| `MISSION_CONSOLE` | Mouse `VISIBLE` | - | `MissionConsole` (computer-theme window with hardcoded dummy mission list, X button closes, opacity fade) |

### Input lock

`PlayerController` only accepts input while `GameState.state == IN_GAME_PLAYER` (`is_input_enabled()`); `RobotController` only while `IN_GAME_ROBOT`. Only one of them is ever active, so the player stands still while the robot is driven and vice versa. The description below is for `PlayerController`; `RobotController` works the same way.

`PlayerController` In any other state it zeroes `move_direction`, `is_sprinting` and `request_jump`, ignores mouse look and all presses, but still forwards key/button **releases** so crouch/interact/primary/secondary can't get stuck. The first physics tick after re-entering `IN_GAME_PLAYER` is also treated as locked, so a click used to close a UI screen isn't read as a throw. New states automatically lock both; to allow input in a new state, change `is_input_enabled()`.

### Pausing

Pausing is a smooth slow-down, not an instant freeze:

- `pause_game()`: tween `Engine.time_scale` to `0.0` over 0.5s (tween ignores time scale and runs while paused), then `get_tree().set_pause(true)`.
- `unpause_game()`: sets `get_tree().paused = false` immediately and tweens `time_scale` back to `1.0` over 0.5s.
- Any node that must animate/process while paused needs `process_mode = ALWAYS` (UI tweens use `TWEEN_PAUSE_PROCESS` + `set_ignore_time_scale(true)`).

---

## 6. UI layer

### 6.1 UIManager (`src/ui/ui_manager/`)

A `Node` (process mode ALWAYS) whose children are all UI screens:

```
UIManager
├── HUD            (CanvasLayer, player HUD)
├── RobotHUD       (CanvasLayer, robot HUD)
├── MainMenu       (CanvasLayer)
├── PauseMenu      (CanvasLayer)
├── MissionConsole (CanvasLayer, computer-theme window, hardcoded dummy items)
├── LoadingScreen  (CanvasLayer, layer = 256, always on top)
└── Console        (PopupPanel, hidden)
```

`ui_manager.gd` does three things:

1. **Reacts to `GameState.state_changed`** - the single place that maps state -> visible screens:
   - `new == MAIN_MENU` -> `MainMenu.fade_in()` else `fade_out()`
   - `new == PAUSED` -> `PauseMenu.fade_in()` else `fade_out()`
   - `new == IN_GAME_PLAYER` -> `HUD.fade_in()` else `fade_out()`
   - `new == IN_GAME_ROBOT` -> `RobotHUD.fade_in()` else `fade_out()`
   - `new == MISSION_CONSOLE` -> `MissionConsole.fade_in()` else `fade_out()`
   - `LoadingScreen.visible = (new == LOADING or old == LOADING)` (so it stays visible through the `LOADING -> X` transition until `level_loaded` fades it out).
2. **Relays SceneLoader signals to the LoadingScreen**: `request_transition(no_fade_in)` -> `reset()` (instant black) or `fade_in()`; `level_loaded` -> `fade_out()`.
3. **Handles global keys** in `_process`: `console` (backtick) and `ui_cancel` (Esc).
   - Backtick: shows/hides the `Console` popup. It does **not** change game state (the game keeps running while it is open). See [section 11](#11-debug-console).
   - Esc: `IN_GAME_PLAYER -> PAUSED`, `IN_GAME_ROBOT -> IN_GAME_PLAYER`, `PAUSED`/`MISSION_CONSOLE -> last in-game state`.

### 6.2 UIScreen base class (`ui/ui_screen.gd`)

`class_name UIScreen extends CanvasLayer` with empty `fade_in()` / `fade_out()`. `MainMenu`, `PauseMenu`, `HUD`, `LoadingScreen` all extend it so `UIManager` can treat them uniformly. **New full-screen UI should extend `UIScreen`.**

### 6.3 Main menu (`ui/main_menu/`)

- Two sub-screens inside one `CanvasLayer`: `MainMenuSubScreen` (Start / Settings / Quit) and `SettingsSubMenu` (instance of `sub_screens/settings_sub_menu.tscn`).
- Sub-screens "slide" horizontally by tweening `position`. Off-screen positions: main = `(-1920, 0)`, settings = `(1920, 0)`. On `_ready` both are placed off-screen; `fade_in()` slides the main sub-screen to `(0,0)`.
- Buttons:
  - **Start** -> `SceneLoader.load_scene("test_level")`
  - **Settings** -> slides settings in; **Back** slides it out
  - **Quit** -> `get_tree().quit()`
- `fade_in()` / `fade_out()` (the `UIScreen` API) just slide the main sub-screen in/out.
- Tweens are created with `create_de_facto_tween()` (ease in/out cubic, ignore time scale, runs while paused).

### 6.4 Pause menu (`ui/pause_menu/`)

Same structure as the main menu (sub-screen sliding), plus a `BGTint` `ColorRect` that fades to 50% black. Buttons: **Resume** (`GameState.return_to_game()`), **Settings**, **Quit To Menu** (`SceneLoader.load_scene("main_menu")`), **Quit To Desktop**. `fade_in()` always resets to the pause sub-screen.

### 6.5 Settings sub-menu (`ui/sub_screens/settings_sub_menu.tscn`)

Shared by main and pause menus. Layout: a tab row (General / Audio / Video / Controls), a `Pages` container (one `ScrollContainer` per tab, each holding a `Rows` VBox), and a Back button whose handler is connected by the parent menu. `settings_sub_menu.gd` builds the rows in code and switches pages via a `Tab` enum (`GENERAL`, `AUDIO`, `VIDEO`, `CONTROLS`): pressing a tab instantly shows its page under the tab row and hides the others. Exactly one page is always visible, and General is the default. All widgets (sliders, checkboxes, dropdowns, buttons) are **dummies** and are not wired to any real setting.

### 6.6 HUD (`ui/hud/`) and Robot HUD (`ui/robot_hud/`)

The `HUD` below is the **player** HUD, shown only in `IN_GAME_PLAYER`. `RobotHUD` (`robot_hud.tscn/.gd`, extends `UIScreen`) is shown only in `IN_GAME_ROBOT`: a speed readout (`Debug.current_robot.linear_velocity`) bottom-left and a controls hint bottom-right, faded with a `CanvasModulate` like the player HUD. A debug **friction circle** panel (`friction_circles.gd`, top-right) reads `Debug.current_robot` directly and draws one circle per wheel: the circle is the grip limit (`mu * load`), the dot is the ground force in the wheel's own (steered) frame (up = drive, down = brake, sideways = cornering), with a fading trail, a grip-used arc/percentage, a load bar and the chassis-frame velocity in the middle.

- `CanvasModulate` is tweened to fade the whole HUD (alpha 0/1); the HUD is `show()`n on first `fade_in()` and starts hidden.
- **Crosshair swap** (every frame): shows `crosshair.svg` normally, `interaction.svg` when `GameState.player.looking_at_object` is an `InteractTrigger` or a `RigidBody3D` (something you can use/pick up). Both hidden while `player.hide_crosshair` is true.
- **Subtitles**: listens to `DialogServer.dialog_played/ended`, instantiates a `DialogBox` into `DialogBoxContainer/Boxes` (bottom-centre) and fades it out on end. `DialogBoxContainer` is a single themed `PanelContainer` that draws one background behind the whole stack; `Boxes` is a `VBoxContainer` inside it. It is anchored to a zero-height line near the bottom, so it grows upward as boxes are added and collapses to nothing when empty.
- `Tooltip` label and a static `DialogBox` node exist in `hud.tscn` but are hidden and unused (see known issues).

### 6.7 Loading screen (`ui/loading_screen/`)

- Black full-screen `ColorRect` + `ProgressBar` (bottom-left) on `layer = 256`.
- `AnimationPlayer` with `RESET` (alpha 1, i.e. opaque), `fade_in` (0 -> 1 in 0.5s), `fade_out` (1 -> 0 in 0.5s).
  Note the naming: "fade_in" means *the black screen fades in* (hiding the game).
- Emits `finished_fade_in` (wired to `SceneLoader._on_finished_fade_in` by `UIManager`) and `finished_fade_out` (then hides itself).
- Progress bar is driven every frame from `SceneLoader.progress[0] * 100`.

### 6.8 Button components (`ui/button_style_components/`)

Drop-in child `Node`s that style their parent `Button`:

- `ButtonResizeComponent`: scales up on hover (elastic tween), back on exit. Sets the button and itself to process while paused.
- `ButtonSoundComponent`: creates hover/press `AudioStreamPlayer`s on bus `"UI"` at -20 dB. Sound files are not wired up yet (commented TODOs).

All buttons in the menus use `focus_mode = 0` (no keyboard focus).

---

## 7. Scene loading

`SceneLoader` is the only thing that creates or destroys levels. Levels are registered in a dictionary:

```gdscript
const LEVEL_PATHS: Dictionary = {
    "test_level": "res://src/levels/test_level.tscn",
    MAIN_MENU_ID: "res://src/levels/test_level.tscn",   # "main_menu"
}
```

### Flow of `load_scene(level_name, no_fade_in = false)`

```mermaid
flowchart TD
    A[load_scene level_name] --> B{Already loading<br/>or unknown name?}
    B -- yes --> Z[return / push_error]
    B -- no --> C[loading_scene_id = name<br/>progress = 0]
    C --> D[GameState -> LOADING]
    D --> E[emit request_transition no_fade_in]
    E --> F{no_fade_in?}
    F -- yes --> H
    F -- no --> G[LoadingScreen fades to black 0.5s<br/>emits finished_fade_in]
    G --> H[_on_finished_fade_in]
    H --> I[queue_free current_scene<br/>emit level_unloaded]
    I --> J[ResourceLoader.load_threaded_request]
    J --> K[_process polls status every frame]
    K -- LOADED --> L[_setup_scene: instantiate and add under Main]
    L --> M{loading_scene_id == main_menu?}
    M -- yes --> N[_setup_main_menu]
    M -- no --> O[_setup_level]
    N --> P[loading_scene_id = empty<br/>emit level_loaded]
    O --> P
    P --> Q[LoadingScreen fades out and hides]
```

### `_setup_level()` (gameplay level)

Requires a node named **`SpawnPoint`** (`Marker3D`) in the level. It spawns the player and then calls `GameState.change_state_to(IN_GAME_PLAYER)` -> HUD appears, mouse captured. The robot is **not** spawned by code any more; levels that want one place it manually (see the test level).

**`_setup_player(spawn_point)`**
1. Creates a `PlayerController` (plain `Node`) and adds it to the level.
2. Instantiates `player.tscn`, sets `GameState.player`, copies the spawn point's `transform`, assigns `player.controller`, adds it to the level.

The controller must be assigned **before** `add_child(player)` because `Player._ready()` connects to its signals. `_setup_player` also makes the player's camera current, since the robot's camera lives in the level too.

### `_setup_main_menu()`

Requires a **`CameraMarker`** (`Marker3D`). Sets state to `MAIN_MENU`, then creates a `Camera3D` (FOV 90) at that marker's transform and makes it current (the level contains a robot with its own camera). No player is spawned.

### Level requirements checklist

| Node name | Type | Needed for |
|---|---|---|
| `SpawnPoint` | `Marker3D` | any gameplay level |
| `CameraMarker` | `Marker3D` | any level used as the main-menu backdrop |

### The test level (`levels/test_level.tscn`)

A sandbox with: directional light + procedural sky, a 128x128 CSG floor and CSG walls/arches (`use_collision = true`, inside a `NavigationRegion3D` with a baked navmesh), three pickup props (`Box`, `Text`, `Sphere` - `RigidBody3D` on collision layer 3), a see-saw (`StaticBody3D` + `HingeJoint3D` + `RigidBody3D`), and a `CharacterBody3D` box that is moved by the level's `AnimationPlayer` (`new_animation`, 10s loop). It also contains a `DialogTrigger` (`InteractTrigger`) that plays a demo dialog sequence, a `MissionConsoleTrigger` (copy of that cube) that switches `GameState` to `MISSION_CONSOLE`, and a `RobotTrigger` (another copy, labelled "Drive Robot") that switches to `IN_GAME_ROBOT`. The robot is placed in the scene manually: a `RobotController` node plus a `Robot` instance (`robot.tscn`) whose `controller` export points at it (next to the `RobotTrigger`, around `(10.5, 0.5, -1.2)`). Esc leaves the robot.

---

## 8. Player

Files: `player/player.tscn`, `player/player.gd` (`class_name Player`), `player/player_controller.gd` (`class_name PlayerController`).

### 8.1 Design split

- **`PlayerController`** = *intent*. Reads input and exposes values/signals. It does not touch physics. It could in principle be swapped for an AI or replay controller.
- **`Player`** = *body*. A `RigidBody3D` that reads the controller each physics step and moves itself.

### 8.2 Scene structure (`player.tscn`, root `PlayerCharacter`)

```
PlayerCharacter (RigidBody3D, script player.gd)
├── CollisionShape3D      CapsuleShape3D r=0.25 (height 2.0 standing, 1.0 crouched), offset y=1
├── Pivot (Node3D)        rotates around Y = yaw (azimuth)
│   ├── Marker3D          hidden, offset "look at map" marker (legacy)
│   └── Camera3D          y=1.5, FOV 90, near 0.001, far 500, rotates around X = pitch
│       └── RayCast3D     3 m forward, collides with areas, mask 53
├── AudioStreamPlayer3D   (unused)
└── CrouchCheck (RayCast3D)  upward 1.95 m, detects low ceilings
```

Body settings: mass 50, all angular axes locked (never tips over), friction 0 physics material (friction is done manually), `can_sleep = false`, continuous CD, contact monitor on (16 contacts reported - needed for floor detection).

### 8.3 PlayerController (input -> intent)

Output state:

| Field | Meaning |
|---|---|
| `move_direction` | normalized `Vector3` from WASD (forward = -Z, right = +X) |
| `is_sprinting` | Shift held |
| `request_jump` | set on Space press, cleared on release or when the player consumes it |
| `camera_azimuth` / `camera_altitude` | accumulated yaw / pitch in radians (pitch clamped to +-90 degrees) |

Signals (emitted with `true` on press, `false` on release): `crouch`, `interact`, `primary`, `secondary`.

- Mouse look is in `_unhandled_input`, ignored while `GameState.state == PAUSED`. It converts pixels to radians with a Source-engine-style formula: `px_to_rad = pixels / (DPI/2.54) / SENS * 2*PI`, with `DPI = 1000`, `SENS = 10.4` (centimetres per 360 degrees).
- Buttons/axes are polled in `_physics_process`.

### 8.4 Player movement (`Player._integrate_forces`)

This is a **custom force-based character controller** on top of a rigidbody:

1. **Floor detection**: loops over contacts; a contact counts as floor if `normal . UP >= cos(45 degrees)`. Also records the floor's velocity (moving platforms).
2. **Pick speed and acceleration**:

   | Situation | Speed (m/s) | Accel |
   |---|---|---|
   | Ground, walking | `SPEED_WALK` = 2.0 | `ACCEL_GROUND` = 12 |
   | Ground, sprinting | `SPEED_SPRINT` = 3.0 | 12 |
   | Ground, crouching | `SPEED_CROUCH` = 1.0 | 12 |
   | Airborne | `SPEED_AIR` = 1.0 | `ACCEL_AIR` = 3 |

3. **Custom friction** (grounded only): acts on the velocity component *not* along the wished direction (relative to the floor's velocity). If the friction impulse can fully stop it within one step it is applied as an impulse (static friction), otherwise as a force (kinetic). `FRICTION = 0.5`.
4. **Slope handling**: the wish direction is rotated onto the slope plane, and a compensation force cancels the horizontal part of gravity so the player doesn't slide.
5. **Acceleration**: applies a force toward the wish direction; if the next step would exceed the target speed, it applies the exact impulse needed to hit the target speed instead (no overshoot).
6. **Jump**: if on floor and `request_jump`, applies an impulse of `sqrt(2 * JUMP_HEIGHT * gravity)` (`JUMP_HEIGHT` = 0.8 m), nudges `origin.y` up by 0.05 to leave the ground, and clears the request.

### 8.5 Look & camera (`_physics_process`)

- `camera.rotation.x = controller.camera_altitude` (pitch) and `pivot.rotation.y = controller.camera_azimuth` (yaw). The body itself never rotates (angular locked); movement direction is `pivot.basis * controller.move_direction`.
- `looking_at_object` = held object, or `raycast.get_collider()` (used by the HUD crosshair).

### 8.6 Crouching

- `crouch` signal -> `_on_controller_crouch` -> `set_crouch(bool)`, which tweens (0.5s, physics-processed): capsule height 2.0 <-> 1.0, camera Y 1.5 <-> 1.25, `CrouchCheck` Y offset.
- **Uncrouch is blocked** while `CrouchCheck` hits a ceiling. Also, if you are standing and the ceiling check starts colliding, the player is forced into a crouch; when it clears and the player isn't holding the key, they stand again.

### 8.7 Camera detach helpers (unused today)

`release_camera(new_transform, fov)` / `bind_camera()` detach the camera (`top_level = true`), lock look/move/crosshair, and tween it to a target transform and back. Nothing in the current game calls them (they were meant for things like a map view).

---

## 9. Interaction & object pickup

### Interact (E / `interact_use`)

Handled in `Player._on_controller_interact` on press:

1. If holding an object -> release it.
2. Else if the 3 m raycast hits something:
   - `RigidBody3D` -> pick it up.
   - `InteractTrigger` -> `collider.interact(self)`, which emits `interacted(player)`.

The raycast has `collide_with_areas = true`, mask `53` = layers 1, 3, 5, 6 (world, props, interact triggers, +layer 6).

### `InteractTrigger` (`interact_trigger/interact_trigger.gd`)

`class_name InteractTrigger extends Area3D`. Has `@export var tooltip: String` and signal `interacted(player: Player)`. It's a generic hook: gameplay code connects to `interacted`. The `tooltip` is not displayed anywhere yet.

### Holding / throwing a `RigidBody3D`

- **Pick up**: stores the object's original layer/mask and orientation (relative to the camera). The object is moved to **collision layer 4 (the "held" layer)** and its mask drops the player layer, so it can't push the player around or shove them upward.
- **Shared code**: all of this lives in `ObjectHolder` (`src/object_holder/object_holder.gd`, a `RefCounted` created with `ObjectHolder.new(body, pivot, camera)`), used by both `Player` (`player.holder`) and `Robot` (`robot.holder`). API: `pickup(body)`, `release()`, `throw()`, `update(delta)`, `held_object`.
- **While held** (`ObjectHolder.update`, every physics step): a PID-style controller applies force and torque to pull the object to a point `PICKUP_DISTANCE` = 2 m in front of the camera. Pitch is clamped so the holder can't pull itself up by looking down. Gains scale with mass (`log(mass/10 + 1)` for position, linear in mass for rotation). Integral terms (`KI`) are 0. `apply_reaction_force` (pushes the holder back) is `false`. A collision exception with the holder is added while held (needed for the robot, which is on the props layer).
- **Release**: press E again; restores original layer/mask.
- **Throw**: left click (`interact_primary`) while holding -> releases and applies an impulse along the camera forward vector, scaled with mass.
- `secondary` (right click) only sets `is_rotating_held_object`; re-rotation isn't implemented.

---

## 10. Dialog system

Data (`Resource`s, editable in the inspector):

- `Dialog`: `audio_stream: AudioStream` (voice line, played by `DialogServer`; its length extends the on-screen time), `speaker: String` (empty = narration), `subtitle: String` (multiline) and `min_duration` (seconds, default 1.0). `get_display_text()` returns `"Speaker: subtitle"` (or just the subtitle with no speaker); the HUD shows this until a dedicated speaker UI exists.
- `DialogSequence`: `dialogs: Array[Dialog]`.

`DialogServer` (autoload):

- `play_dialog(dialog) -> bool`: awaitable. Emits `dialog_played`, waits `get_dialog_duration()` (1000 chars/min reading speed, at least the audio length and `min_duration`) on a pausable `SceneTreeTimer`, then emits `dialog_ended`. Returns `true` if it finished, `false` if cancelled or if that same `Dialog` is already playing.
- `play_dialog_sequence(seq) -> bool`: awaitable. Plays each dialog in order with a 0.35s gap (`SEQUENCE_GAP`). The gap is shorter than the DialogBox hold + fade-out, so consecutive lines can be on screen together; the HUD stacks them smoothly. Ignored while another sequence is playing, so re-triggering a trigger can't start overlapping copies. Emits `sequence_finished(seq, completed)`.
- Audio: if a `Dialog` has an `audio_stream`, `DialogServer` plays it on an `AudioStreamPlayer` child (bus `AUDIO_BUS`, currently `Master`) for the life of the line; it is stopped and freed when the line ends or is cancelled.
- `stop_all()`: cancels everything. It bumps an internal generation counter, so any waiting coroutine exits when it wakes, and emits `dialog_ended` for active dialogs so the HUD clears. It is called automatically on `SceneLoader.level_unloaded`, so a sequence can no longer continue into the next level or menu.

**What happens when dialogs overlap** (there is no queue or priority system yet):

| Situation | Result |
|---|---|
| Two different `Dialog`s via `play_dialog` | Both start immediately. Two boxes stack in the HUD and both `audio_stream`s play at once. Each ends on its own timer. |
| Same `Dialog` instance while it is playing | Second call returns `false` immediately, no signals. |
| A sequence while another sequence plays | Returns `false` immediately; the running sequence is unaffected. `sequence_finished` is **not** emitted for the rejected one. |
| A single line during a sequence (or vice versa) | No coordination; they overlap as in the first row. |
| `stop_all()` / level unload | Everything is cut off, audio stopped, HUD cleared. A running sequence only notices when its current timer wakes, so `sequence_finished(seq, false)` (and the caller's `await`) can arrive late, up to that line's remaining duration. |

Display: `HUD` listens to the two signals and creates/fades a `DialogBox` (`ui/dialog_box/`) inside `DialogBoxContainer/Boxes` (fade in 0.5s; on end, 3.0s hold, fade out 0.5s, `queue_free`).

`DialogBox` is a plain `Control` "slot" that the `VBoxContainer` lays out, with a bottom-anchored `Content` (`MarginContainer` + `RichTextLabel`) inside it. It has no background of its own; the HUD's `DialogBoxContainer` panel provides it, so stacked boxes have no gaps. Fades animate a `reveal` property (0 to 1) that drives the slot's `custom_minimum_size.y` and the content's Y scale (pivot at its bottom edge), so sibling boxes slide instead of jumping. Don't put the scaled node directly under a `Container`: containers reset child scale on every re-sort, which is why the content is nested one level down.

Ways to trigger today: the `say <text>` console command (see below), and the `DialogTrigger` in `test_level.tscn`, whose `interacted` signal plays the `intro_dialog` export of `test_level.gd`, a `DialogSequence` authored in `res/dialogs/test_sequence.tres`. Author new sequences the same way: create a `DialogSequence` resource in the inspector, add `Dialog` entries, and export it on the level or NPC script.

---

## 11. Debug console

- Toggle: backtick (`` ` ``, action `console`). `Console` is a `PopupPanel` (title still says "Open Wheel Debug Console", a leftover name). It shows `Debug.debug_console_output` (refreshed every frame) and a `LineEdit` + Submit button.
- **Does not pause the game.** Toggling the console only shows/hides the popup; `GameState` is untouched. Likely consequences (inferred from the code, not tested): while in game the mouse stays captured, and `PlayerController` polls `Input` globally, so typing W/A/S/D/Space in the console may also move the player.
- Logging: `Debug.add_log(message)` appends a timestamped line.
- Commands (`Debug.parse_command`, case-insensitive first word):

| Command | Effect |
|---|---|
| `timescale <float>` | `Engine.set_time_scale(value)` |
| `quit` | quit the game |
| `say <text...>` | creates a temporary `Dialog` with that subtitle and plays it via `DialogServer` |
| `fullbright` | toggles `Viewport.DEBUG_DRAW_UNSHADED` |

| anything else | logs `Unknown command "..."` |

---

## 12. Input map & physics layers

### Input actions (`project.godot`)

| Action | Binding |
|---|---|
| `move_forward` / `move_backward` / `move_left` / `move_right` | W / S / A / D (physical keys) |
| `move_jump` | Space |
| `move_sprint` | Shift |
| `move_crouch` | Ctrl |
| `interact_use` | E (pick up / drop / use trigger) |
| `interact_primary` | Left mouse (throw held object) |
| `interact_secondary` | Right mouse (sets rotate flag, unused) |
| `console` | `` ` `` (backtick) |
| `ui_cancel` | Esc (Godot built-in; pause toggle) |

The robot shares the player's actions: `move_forward` = drive forward, `move_backward` = drive backward, `move_left` / `move_right` = steering, mouse = look, `interact_use` = pick up / drop, `interact_primary` = throw. It has no robot-only actions.

### Collision layers (bit value in parentheses)

| Layer | Used for | Who uses it |
|---|---|---|
| 1 (1) | World / static geometry | CSG level; player mask |
| 2 (2) | Player | `PlayerCharacter` layer |
| 3 (4) | Pickup props | `Box`, `Text`, `Sphere`, see-saw plank; player mask; `CrouchCheck` mask |
| 4 (8) | Held object | Applied in code during pickup (`held_layer = 4`) |
| 5 (16) | Interact triggers | `InteractTrigger` `Area3D`s |

Player `collision_mask = 5` (world + props). Interaction raycast mask `53` (world, props, triggers, layer 6). When creating new content, put pickups on layer 3 and triggers on layer 5, and give triggers `collision_mask = 0`.

---

## 13. Known issues / gotchas / TODOs

Grounded in the current code; useful to know before changing things.

**Gameplay / wiring**
- Only `test_level.tscn` uses an `InteractTrigger` (the `DialogTrigger` demo).
- `InteractTrigger.tooltip` and the HUD `Tooltip` label are not connected.
- `GameState.State.IN_GAME_MENU`, `Player.inventory`/`active_item_index`, `viewmodel_controller`, `AudioStreamPlayer3D`, `is_rotating_held_object` are placeholders with no behaviour.

**Scene loading**
- `LEVEL_PATHS["main_menu"]` points at `test_level.tscn` (same file as the playable level) - fine for now, but a dedicated menu level is the intended direction (`is_first_main_menu_load` is reserved for an intro).
- **Load failures are not recovered from.** Failure paths only `push_error` and return:
  - `load_threaded_request` error or `THREAD_LOAD_FAILED`: `loading_scene_id` is never cleared (every later `load_scene` call is silently ignored), state stays `LOADING`, and the loading screen stays black. The old level has already been `queue_free`d by then.
  - Missing `SpawnPoint`: the scene is added and `level_loaded` fires (loading screen fades out), but `_setup_level` returns before `IN_GAME_PLAYER`, so the state stays `LOADING` with no player and no HUD.
  - Missing `CameraMarker`: menu state is set but there is no camera.
  - Level paths in `LEVEL_PATHS` are not validated (see TODO in the file). A fix has been proposed but is **not implemented yet**.
- `GameState.player` is not cleared when a level unloads (line commented out); it can be a stale/freed reference after returning to the menu. The HUD guards with `if GameState.player` but anything else should check `is_instance_valid`.
- `_setup_main_menu` sets state before creating the camera; the trailing comment is misleading.

**UI**
- The settings menu widgets (sliders, toggles, dropdowns, key-binding buttons) are dummies: they hold local state only and are not saved or applied. The selected settings tab persists while the menu stays alive (it is not reset to General on re-open), and the active tab button has no highlight yet. `ButtonSoundComponent` plays on an audio bus named `"UI"` that does not exist yet (no custom bus layout); until it is created Godot falls back to `Master`. **Planned:** a dedicated `UI` bus.
- Sub-screen positions assume a 1920 px wide viewport (hard-coded `+-1920`).
- **Planned / consider for the final build (settings menu):**
  - Replace the manual `Tab` enum + show/hide loop with a `ButtonGroup` (`toggle_mode = true` on the four tab buttons) so the engine guarantees exactly one tab is selected and highlights the active one. Optionally swap the `Pages` container for a `TabContainer` (`tabs_visible = false`, set `current_tab` from the buttons). Check that `ButtonResizeComponent` and the pressed style in `res://res/theme.tres` look right on toggled buttons.
  - Replace the code-built dummy rows with a reusable row scene (label + widget bound to a setting key) once real settings exist, and persist them (e.g. `ConfigFile`).
- `HUD.fade_out()` makes the HUD transparent but doesn't hide it (the `hide` callback is commented out).
- `dialog_server.gd` still has a comment above `SEQUENCE_GAP` claiming the gap must exceed the DialogBox hold + fade-out. That is no longer true (hold is 3.0s, fade-out 0.5s); boxes are meant to stack now.
- `DialogServer` has no queue: a second sequence started while one is playing is ignored, and individual lines can overlap (`play_dialog` only rejects the same `Dialog` instance twice). See the overlap table in section 10.
- `play_dialog` returns `false` for both "cancelled" and "ignored because already playing", and `play_dialog_sequence` treats any `false` as a cancel. If a line of a sequence is already playing standalone (e.g. via `say`), the sequence aborts early with `completed = false`.

**Player**
- Known TODO in code: crouch transitions can capture a transient camera transform; "friction doesn't work when walking then crouching".
- `LEAP_SPEED`, `STEP_SIZE_*`, `JUMP_SPEED_PENALTY`, constants are declared but unused (the pickup gains are computed inline in `ObjectHolder`).

**Robot** (see [section 15](#15-robot) for details)
- Wheel radius is read from the mounted `WheelPart` every physics frame (15.3a). The motor sizing (`no_load_speed`, `stall_torque`) still assumes 0.15 m wheels, so other radii change top speed and acceleration, and `WheelPart.grip` is not used yet.
- The robot needs a mounted, charged `BatteryPart` to drive (`Robot.require_battery`, 15.3a). The robot in `test_level.tscn` starts with its sockets empty, so mount the battery lying in the level first. There is no way to recharge yet. `MotorPart.max_torque` was replaced by the `RobotEngine` values (`stall_torque`, `no_load_speed`, ...).
- The robot was ported from the separate `openwheel` project and was **not wired up when it landed**. Missing pieces found and fixed: `Debug.current_robot`, the robot input actions, and level placement. The original glTF car model was dropped; the robot is currently a placeholder box mesh.
- Physics settings were **not** ported: `openwheel` runs 360 physics ticks/s and gravity 20; this project runs 240 ticks/s (`project.godot`) with Godot's default gravity (9.8, not lunar). The tyre model has its own comments about "spazzing" at low speed, so expect some twitchiness. The robot's mass, springs, tyre stiffness and motor were tuned for 9.8 gravity; if you change gravity, they need retuning.

- The player is still alive (frozen, input locked) while the robot is driven, and the robot is also in the world while the player walks around (it just coasts to a stop).
- `InteractTrigger`s can't be used while driving (they rely on the `Player` raycast); Esc is the only way out.
- `robot.tscn` quirks inherited from `openwheel`: the visual is just a placeholder `MeshInstance3D` box (1 x 0.33 x 1 m); `WheelFront`/`WheelBack` markers are unused; `Robot.controller` is typed `RobotController` and is not set in `robot.tscn`, so every level that instances the robot must assign it (the test level does).
- The robot's `Debug.parse_command` hooks from `openwheel` (`setaccel`, `hitcar`) were not ported.

**Camera ownership** (for future consideration)
- Several places decide which `Camera3D` is `current`, with no single owner:
  - `SceneLoader._setup_player` makes the player's camera current, and `_setup_main_menu` does the same for the menu camera.
  - `Robot._on_game_state_changed` makes the robot's camera current on entering `IN_GAME_ROBOT`.
- The robot reaches into `GameState.player.camera` to hand the view back when going `IN_GAME_ROBOT -> IN_GAME_PLAYER`, so the robot has to know about the player. If `GameState.player` is gone or stale it silently does nothing and no camera is current. Any new camera user (cutscene, map view, spectator) would need the same ad-hoc handover.
- Correctness depends on ordering: Godot allows one current camera per viewport and `make_current()` just steals it. This is why the robot's camera is not `current` in `robot.tscn` (otherwise they won the view on load), and why `_setup_main_menu` calls `make_current()` explicitly (the level contains a robot with its own camera). Anything that adds a camera with `current = true` can break this.
- The player's `release_camera()` / `bind_camera()` helpers (see 8.7) are an unused, player-only version of the same idea. `GameState.camera` is declared but unused.
- **Possible fix, if it starts to hurt:** a small `CameraManager` autoload with a stack of cameras.
  - `push(camera)` makes it current and remembers the previous one; `pop(camera)` returns to the one below, skipping freed cameras; `set_active(camera)` replaces the top entry (for swapping the active view).
  - The player pushes its camera on entering `IN_GAME_PLAYER`, the robot pushes on `IN_GAME_ROBOT` and pops on exit, and `SceneLoader` pushes the menu camera. The robot and `SceneLoader` would no longer touch each other's cameras.
  - It would also be the one place to add blends between views (tween a transition `Camera3D`), replacing `release_camera` / `bind_camera` and `GameState.camera`.
  - **Do not reparent cameras** to switch views: the player's and robot's cameras are driven by their `Pivot` nodes (and the player's by the crouch tweens), so reparenting would break both for no gain over `make_current()` or a transition camera.
- Not worth doing while the game only switches between the player and the robot; worth doing once a third camera user or view blending appears.

**Repo hygiene**
- `project.godot` `config/name` is still `"Game"` and the main menu title label reads `"New Game Project"`.

---

## 14. Recipes: how to extend the game

### Add a new level
1. Create `src/levels/my_level.tscn` (root `Node3D`).
2. Add a `Marker3D` named **`SpawnPoint`** (player spawns with its transform).
3. (Optional, if used as menu backdrop) add a `Marker3D` named **`CameraMarker`**.
4. Register it in `SceneLoader.LEVEL_PATHS`: `"my_level": "res://src/levels/my_level.tscn"`.
5. Load it with `SceneLoader.load_scene("my_level")`.

### Add a pickup prop
`RigidBody3D` with `collision_layer = 4` (layer 3), a collision shape, and a mesh. No script needed; the player's raycast finds it and the HUD shows the interaction crosshair.

### Add an interactable (door, button, NPC...)
(No example exists in the current level; this is the intended pattern.)
1. Add an `Area3D` using the `InteractTrigger` script, `collision_layer = 16` (layer 5), `collision_mask = 0`, with a `CollisionShape3D`.
2. Connect its `interacted(player)` signal to your logic, e.g. `DialogServer.play_dialog_sequence(my_sequence)`.

### Add dialog
Create a `DialogSequence` `.tres` under `res/dialogs/` with `Dialog` entries (set `speaker`, `subtitle`, optionally `audio_stream`), `@export` it on the script that triggers it, then call `DialogServer.play_dialog_sequence(seq)` (or `play_dialog(dialog)` for one line).

### Add a console command
Add a new `match` case in `Debug.parse_command` (`autoloads/debug.gd`); use `add_log()` to print feedback.

### Add a new UI screen
1. Create a scene whose root is a `CanvasLayer` with a script that `extends UIScreen`; implement `fade_in()` / `fade_out()`.
2. Instance it under `UIManager` in `ui_manager.tscn`.
3. Add its show/hide rule to `UIManager._on_game_state_changed`, adding a new `GameState.State` if needed (and handle it in `_on_state_enter/_on_state_exit`).
4. Use `ButtonResizeComponent` / `ButtonSoundComponent` children and `res/theme.tres` for consistent styling. Remember `process_mode = ALWAYS` for anything that must work while paused.

### Add a new game state
If it is a new in-game mode, also set `last_in_game_state` in `_on_state_enter` and extend `is_in_game()`.
Add it to `GameState.State`, handle enter/exit side effects in `_on_state_enter` / `_on_state_exit`, then decide which UI screens it shows in `UIManager._on_game_state_changed`.

### Switch between player and robot
Place a `RobotController` node and a `robot.tscn` instance in the level (assign its `controller`), add an `InteractTrigger` and, in the level script, call `GameState.change_state_to(GameState.State.IN_GAME_ROBOT)` from its `interacted` signal when `GameState.state == IN_GAME_PLAYER`. `UIManager` sends Esc back to `IN_GAME_PLAYER`.

---

## 15. Robot

Files: `src/robot/robot.tscn`, `robot.gd` (`class_name Robot`), `robot_controller.gd` (`class_name RobotController`), `components/engine.gd` (`RobotEngine`, a brushed DC motor model), `components/running_gear.gd` (`RunningGear`), `components/engine_sound.gd` (procedural motor sound). The sim was ported from the `openwheel` project, then simplified: no gearbox, clutch or handbrake.

**Status:** the robot is placed manually in `test_level.tscn` and driven only while `GameState.state == IN_GAME_ROBOT` (entered through the level's `RobotTrigger`, left with Esc). While parked it ignores input and rolls to a stop (the controller eases to zero). `GameState.player` is untouched by the robot.

### 15.1 Design split
Same idea as the player: the **controller** is *intent*, the **robot** is *body*.

- **`RobotController`** (`robot_controller.gd`) = intent. Reads the keyboard and exposes plain variables, like `PlayerController`: `desired_speed` (-1 full reverse .. 1 full forward, 0 = no input; used by the robot as the motor voltage, so it maps to a fraction of top speed) and `steer` (-1 left .. 1 right), `camera_azimuth` / `camera_altitude` (mouse look, like `PlayerController`), plus the `interact` and `primary` signals (emitted with `true` on press, `false` on release). The `Robot` reads the variables directly and connects to the signals in `_ready()`.
- It polls `Input` in `_physics_process` using the player's actions (`move_forward` / `move_backward` -> desired speed via `get_axis`, `move_left/right` -> steer), moves each value toward its target with `move_toward` (steer 2.0/s, desired speed 2.0/s), and emits the signals on press/release. While locked, only releases are emitted. Input only counts while `GameState.state == IN_GAME_ROBOT`, and the first tick after unlocking is ignored. When locked the targets are zero, so the desired speed eases to 0 (the robot slows down) and steering re-centres.
- `Robot` only uses `desired_speed`, `steer`, the look angles and the signals, so an AI or replay controller exposing the same interface could be swapped in.

### 15.2 Scene structure (`robot.tscn`, root `Robot`)
```
Robot (RigidBody3D, robot.gd)  mass 80 (moon rover, ~1x1 m), layers 2+3, mask 7, COM (0,0.15,0), can_sleep=false, contact_monitor
├── MeshInstance3D   placeholder box mesh (1 x 0.33 x 1 m)
├── Engine           RobotEngine: brushed DC motor (stall torque 10.7 Nm, no-load speed 345 rad/s)
├── RunningGear      RunningGear: tyre + suspension params (wheelbase/track 1 m, default wheel radius 0.15, spring 4000, damping 400, ride height 0.15)
├── HotswapSocket x6 4 wheel sockets + 1 motor + 1 battery socket (`accepted_type`), wired to the `*_socket` / `motor_socket` / `battery_socket` exports, see 15.3a
├── BodyCollision / CockpitCollision   CollisionPolygon3D
├── Pivot            Node3D, yaw (at 0, 1, -0.2)
│   └── Camera3D     first-person camera, pitch (FOV 90)
│       └── RayCast3D  3 m pickup ray, mask 53, collides with areas
└── EngineSound      AudioStreamPlayer3D + components/engine_sound.gd (procedural motor whir)
```

### 15.3 Simulation (`Robot._integrate_forces`)
Every physics step:
1. `_sync_driven_wheels`: forces the driven wheels (rear-left, rear-right) to the differential speed.
2. `RunningGear.simulate_suspensions(state, steer)`: per wheel, ray-casts down (mask layer 1) from the wheel position. Computes spring + damper load, then slip ratio / slip angle and a Pacejka magic-formula tyre force (longitudinal + lateral), plus wheel torque that spins the wheel.
3. `_step_drivetrain`: the engine is rigidly coupled to the driven wheels through one fixed ratio (`gear_ratio * final_drive`), so motor speed is wheel speed times that ratio. The controller input (`desired_speed`, -1..1) is used as the **motor voltage**, and `RobotEngine.get_motor_torque` is a brushed DC motor: `torque = stall_torque * (voltage - speed / no_load_speed)`, limited to +-stall_torque. Top speed is therefore set by the motor (about `voltage * no_load_speed`, less rolling resistance: ~10 units/s at full input), half input gives about half speed, and no input brakes the robot with back-EMF (strong at speed, fading to nothing near standstill; `Robot.rolling_resistance_force` finishes the stop). Launch acceleration is about 3.5 m/s^2 and tapers as speed builds. Only the differential speed is integrated. To retune: `no_load_speed ~ top speed / wheel radius * total ratio`, `stall_torque ~ (effective mass * launch accel + rolling resistance) * wheel radius / total ratio`.
4. `_apply_wheel_forces`: applies suspension load at the wheel offset and tyre force at the contact point.

There is **one gear** (no shifting, no clutch, no handbrake): `W` drives forward and `S` drives backward.

**Low-speed stability (anti-jitter).** The Pacejka slip terms divide by ground speed, so they used to blow up near a standstill and the tyre force flipped sign every tick. Two fixes live in `RunningGear.simulate_suspensions`:
- `low_speed_threshold` (default 1.5 m/s): the slip ratio and slip angle denominators are `max(abs(speed), low_speed_threshold)`. Near zero speed the tyre acts like smooth viscous friction (force proportional to slip speed), and a stationary robot gets zero tyre force with no hard-coded `2.0` slip or `sign()` hack. The lateral force no longer needs the `sign(velocity_longitudinal)` band-aid, because the slip angle is lateral / |longitudinal|.
- Longitudinal force cap: the wheel is integrated explicitly, so a force that is too large for the wheel's inertia overshoots the ground speed and reverses. The force is clamped to `0.5 * inertia * |slip speed| / (radius^2 * step)`, so one step removes at most half the slip. For the driven wheels `Robot` passes the drivetrain inertia shared between them (`_get_wheel_inertias()`), not the wheel's own 0.03 kg m^2, since that is what the tyre torque actually has to move.

Side effects: grip is slightly weaker below about 1.5 m/s, and there is still no true static friction, so a stationary robot can creep slowly on a steep slope.

### 15.3a Wheel parts and sockets (`socket/`)
Each wheel can be a swappable `WheelPart` (`socket/wheel_part.gd`, a `HotswapPart`) mounted in a `HotswapSocket` (`socket/hotswap_socket.gd`). `Robot` has four exports (`front_left_socket`, `front_right_socket`, `rear_left_socket`, `rear_right_socket`) and builds `wheel_sockets` (wheel enum -> socket) in `_ready()`.

- **Radius.** `WheelPart.radius` (default 0.15 m) overrides the wheel's `EFFECTIVE_RADIUS` in `running_gear.wheel_properties`. An empty socket falls back to `RunningGear.wheel_radius`. The radius feeds wheel speed (`wheel speed = angular velocity * radius`), the tyre torque on the wheel, and the rolling-resistance torque on the driven wheels (average radius of the two rear wheels, `Robot._get_driven_wheel_radius`). Changing it also changes top speed and acceleration, because the motor sizing in 15.3 assumes the default 0.15 m wheel.
- **Placement.** The part is not a child that follows the body rigidly: it is moved to where the running gear puts the wheel (hanging from the suspension at ground height + radius) and turned by the wheel's steer angle.
- **Not used yet.** `WheelPart.grip` is exported but nothing reads it yet (the Pacejka tyre model uses fixed coefficients).

- **Motor.** A `MotorPart` (`socket/motor_part.gd`) carries the same values as `RobotEngine`: `stall_torque`, `no_load_speed`, `rotor_inertia` (not `inertia`, which `RigidBody3D` already has), `stall_power` and an optional `torque_curve`. When the motor socket's part changes, `Robot` calls `engine.use_motor_part(part)`, which copies the values into the `Engine` node. With the socket empty the engine goes back to its built-in values (the scene defaults). Because everything reads `engine.*` (`_step_drivetrain`, `engine_sound.gd`), torque, top speed (`~ voltage * no_load_speed / ratio * wheel radius`), rotor inertia and the motor sound follow the mounted motor automatically.
- **Battery.** A `BatteryPart` (`socket/battery_part.gd`) holds the charge itself, so a hot-swapped battery keeps its own charge. Exports: `capacity` (Wh), `initial_charge` (0..1 of capacity) and `sag_threshold`. In `_step_drivetrain` the controller input is multiplied by `battery.get_voltage_factor()` before it becomes the motor voltage: 1.0 down to `sag_threshold` (default 10% charge), then falling linearly to 0 when empty, so a dying battery loses speed and torque instead of cutting out abruptly. The motor then drains `electrical_power * step / 3600` Wh, where `RobotEngine.get_electrical_power = stall_power * voltage * torque / stall_torque` (never negative, so braking gives nothing back). Cruising therefore costs much less than launching, and a motor with a higher `stall_power` empties the battery faster. With 100 Wh and the default 1500 W stall power, flat-out driving from rest lasts several minutes.
- **No battery = no drive.** `Robot.require_battery` (default true) gives the motor zero voltage while the battery socket is empty or the battery is flat (back-EMF braking still applies, so the robot coasts to a stop). Set it to false to treat an empty battery socket as an unlimited supply, e.g. for testing. `Robot.battery`, `Robot.motor_part`, `Robot.supply_voltage_factor` and `Robot.electrical_power` are exposed for the HUD, and `RobotHUD` shows `BATTERY  <charge %>  <watts>` (red when low or missing).
- **Charging.** `BatteryPart.add_charge(energy_wh)` is the entry point for charging; nothing calls it yet (no charging station), so a drained battery stays drained.

**Update pattern: polled every physics frame, not signal-based.** `Robot._physics_process` calls `_update_wheel_parts()` on every tick, which re-reads each socket's `part.radius`, writes it into `EFFECTIVE_RADIUS`, and repositions and steers the part. `_integrate_forces` then uses the value on that same tick, so a radius change or a hot-swap takes effect immediately. `HotswapSocket.part_mounted` / `part_unmounted` exist but the robot does not connect to them. `_update_power_parts()` follows the same pattern for the motor and battery sockets: the battery is looked up every tick, and the motor values are copied into the engine only when the mounted part changes. *Consideration:* writing the radius from those signals instead would avoid re-assigning it every frame, but it should not really matter, since the polling is cheap (a few dictionary writes per wheel) and it is also what keeps the position and steering up to date. The per-frame placement has to stay in `_physics_process` either way.

### 15.3b Motor sound (`components/engine_sound.gd`)
A procedural electric-motor whir through an `AudioStreamGenerator` (22.05 kHz), generated per frame from `Robot.motor_angular_velocity` and `Robot.motor_torque`. Pitch follows motor speed (70 to 650 Hz across 0 to no-load speed), loudness follows speed plus load (silent when parked), and load adds upper harmonics and controller (PWM) whine. It also adds an inharmonic gear whine and a little noise. All of it is tunable through exports on the node (the scene sets `volume = 0.2`).

### 15.4 Cameras
The robot has a single **first-person camera** that looks and picks things up like the player's (the follow / bumper modes and the `camera` input action were removed). The layout mirrors the player: `Pivot` (yaw, at (0, 1, -0.2) in the robot's local space: 1 m up, ahead of the cockpit) -> `Camera3D` (pitch, FOV 90, near 0.001, far 500) -> `RayCast3D` (3 m, collides with areas, mask 53). `Robot._physics_process` sets `camera.rotation.x = controller.camera_altitude` and `pivot.rotation.y = controller.camera_azimuth`, so the view is relative to the robot body and turns with it. Mouse look is read by `RobotController._unhandled_input` (same sensitivity formula as the player) and only while `IN_GAME_ROBOT`; `GameState` captures the mouse in that state.

The camera is **not** `current` in the scene: `Robot` listens to `GameState.state_changed`, makes it current on entering `IN_GAME_ROBOT`, and on `IN_GAME_ROBOT -> IN_GAME_PLAYER` drops any held prop and gives the camera back to `GameState.player`.

**Pickup** is identical to the player's, since both use the shared `ObjectHolder` (`src/object_holder/object_holder.gd`, section 9): `E` (`interact_use`) picks up the `RigidBody3D` under the crosshair or drops the held one, left click (`interact_primary`) throws it. `RobotController` exposes these as `interact` / `primary` signals. The robot is on the props layer, so the ray ignores the robot itself (`raycast.add_exception`) and a held prop gets a collision exception with the robot. `InteractTrigger`s are not usable from the robot. `Robot.looking_at_object` feeds the crosshair in `RobotHUD`.

### 15.5 Collision layers
The robot is on layers 2 and 3 (collision_layer 6) with mask 7 (world, vehicles, props), so it collides with the level and pushes props. Being on the props layer (3) is what lets the player's interact raycast (mask 53) hit it, so the player can **pick up and throw the robot** like any other prop (mass 80), and the player collides with it (player mask 5 includes layer 3). While held it is moved to layer 4 and loses the player layer from its mask, as for every held object. The suspension rays only hit layer 1, so props and walls on other layers don't hold the wheels up.

### 15.6 Recipe: spawn the robot in a new place
Instance `robot.tscn` in the level and set its `transform`. The origin is the robot's centre and `RunningGear` ride height is 0.15 m, so leave a bit of height above the ground. Add a `RobotController` node and assign it to the robot's `controller` export in the scene (it must be set before `Robot._ready()`, which scene instancing does).

See [section 13](#13-known-issues--gotchas--todos) ("Robot") for the issues found while integrating it.
