class_name RoverLevel

extends Node3D

## Shared by levels with drivable rovers and a parts pile (the test level extends it, the Moon
## level uses it as is). Found by name:
##   <Rover>Trigger       an InteractTrigger next to each Robot child <Rover>: E drives that rover
##   PartsPile            loose HotswapParts, recorded as the level starts
##   RespawnPartsTrigger  E clears the loose pile parts and lays out the recorded pile again
## Every rover gets its wheel dust (WheelDust) and the level its tyre tracks (TyreTracks) unless
## GraphicsSettings.surface_effects is Off; the level's dusty ground (group `dusty_ground`, render
## layer WheelDust.GROUND_RENDER_LAYER) is what the dust sprays from and lands on and what takes
## prints, its `tyre_tracks_surface`s (MoonTerrain, TrackFloor) what draws them.


## Gravity in this level (m/s^2), applied by SceneLoader as the level loads: Earth's 9.8 (the
## project default) unless the level sets its own, e.g. 1.62 on the Moon
@export var gravity: float = 9.8
## How high the player jumps here (m), whatever the gravity (handed to the Player by
## SceneLoader); the Moon caps it at 1.2 m, still floaty: 2.4 s in the air
@export var jump_height: float = Player.JUMP_HEIGHT
## The player's ground friction coefficient here (deceleration = gravity * this). Lunar
## gravity alone would leave a sixth of Earth's grip (2.1 m to stop from a walk); the Moon
## sets 1.6 (0.8 m)
@export var ground_friction: float = Player.FRICTION
## Where Earth is in this level's sky (world direction): the rovers' high-gain antennas track it
## (RoverVisuals reads it from the level). The Moon puts its Earth here (LunarSky draws it)
@export var earth_direction: Vector3 = RoverVisuals.DEFAULT_EARTH_DIRECTION
## Far plane (m) of the player's and the rovers' cameras here: 500 m by default; the Moon's
## terrain reaches the horizon, so it sets about 200 km
@export var camera_far: float = 500.0
## The rovers' suspension here: RunningGear properties (RunningGear.SUSPENSION_PROPERTIES) that
## replace the rover scene's own, applied by the Robot as it enters the level. Empty: the scene's
## values, tuned for Earth gravity. The Moon's keeps Earth's ride height and sag with springs a
## sixth as stiff (the dampers stay Earth's, so the ride is heavily damped), and adds a progressive
## bump stop, so landings off crater rims at 4-6 m/s don't bottom out (tests/test_rover_landing.gd)
@export var rover_suspension: Dictionary = {}
## Whether a driven rover's mast camera picks things up, holds and throws them here. The Moon
## turns it off: there the rover only carries what's on its cargo mount (IRIS_KIT.md 10)
@export var rover_pickup: bool = true
## Whether the player on foot can pick up and throw a rover here (the test level's sandbox: yes;
## the Moon: no)
@export var player_lifts_rovers: bool = true

## Nearest a camera's near plane may be for a far plane: Godot's light culler fails (an error
## every frame) when far / near is much over 10^7, measured with a 200 km far plane: 1 mm fails,
## 1 cm is fine
const NEAR_PER_FAR: float = 1e-7


## The near plane to use for `far`: `near`, or larger if far / near would be too big
static func near_for_far(near: float, far: float) -> float:
	return maxf(near, far * NEAR_PER_FAR)

# PartsPile as the level starts
var _pile := PartsStock.new()


func _ready() -> void:
	for rover in get_children():
		if rover is Robot:
			var trigger := get_node_or_null(NodePath(rover.name + "Trigger")) as InteractTrigger
			if trigger:
				trigger.interacted.connect(_on_robot_trigger_interacted.bind(rover))
	if has_node("PartsPile"):
		_pile.record($PartsPile)
	if has_node("RespawnPartsTrigger"):
		$RespawnPartsTrigger.interacted.connect(_on_respawn_parts_trigger_interacted)
	_add_surface_effects()


# Wheel dust on every rover, the field its grains land on, and the level's tyre tracks
func _add_surface_effects() -> void:
	var setting: GraphicsSettings.SurfaceEffects = GraphicsSettings.get_surface_effects()
	if setting == GraphicsSettings.SurfaceEffects.OFF:
		return
	var low: bool = setting == GraphicsSettings.SurfaceEffects.LOW
	for rover in find_children("*", "Robot", true, false):
		rover.add_child(WheelDust.new(low))
	WheelDust.add_ground_collider(self, low)
	add_child(TyreTracks.new(setting))


## Take control of the trigger's rover. Esc (ui_cancel, handled by UIManager) hands control
## back to the player.
func _on_robot_trigger_interacted(_player: Player, rover: Robot):
	if GameState.state == GameState.State.IN_GAME_PLAYER:
		GameState.drive(rover)


# --- Parts pile -----------------------------------------------------------------------------

## Clears the loose pile parts (parts mounted on a rover stay) and lays out a fresh full pile.
func _on_respawn_parts_trigger_interacted(_player: Player) -> void:
	_pile.restock($PartsPile, self)
