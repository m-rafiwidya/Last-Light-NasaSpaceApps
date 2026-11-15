class_name Lander

extends Node3D

## The crew lander (res/models/lander_kit/lander.glb, tools/blender/LANDER_KIT.md), landed near the
## outpost: a set piece with collision. Origin at the base, the hatch side facing -Z. Markers: Hatch
## (on the porch, where the player stands on arrival, facing out), EngineGlow (the engine's light and
## glowing bell), PlumePoint (the bell's exit) and RampFoot. Moved away from where it stands (the
## opening's descent), its ramp folds up in front of the shut hatch; set_hatch_light(true) lowers the
## ramp, then opens the hatch. When a cutscene hands over, the motion finishes at once.

const RAMP_DEPLOYED: float = -30.0
const RAMP_STOWED: float = 90.0
const RAMP_LOWER_STOWED: float = -180.0
const HATCH_OPEN: float = -176.0
const RAMP_TIME: float = 3.0
const HATCH_TIME: float = 1.5
const FLYING_DISTANCE: float = 0.5

@onready var hatch: Marker3D = $Hatch
@onready var engine_glow: Node3D = $EngineGlow
@onready var plume_point: Marker3D = $PlumePoint
@onready var hatch_light: Light3D = $HatchLight
@onready var ramp_hinge: Node3D = $RampHinge
@onready var fold_hinge: Node3D = $RampHinge/FoldHinge

var engine_on: bool = false
var plume_on: bool = false
## 0: ramp folded up, hatch shut; 1: ramp down and hatch open (RAMP_TIME + HATCH_TIME apart)
var deployed: float = 1.0
var _deploy_target: float = 1.0
var _rest: Vector3
var _ramp_upper: Node3D
var _ramp_lower: Node3D
var _hatch_leaf: Node3D


func _ready() -> void:
	_ramp_upper = $Model.find_child("lander_ramp_upper", true, false)
	_ramp_lower = $Model.find_child("lander_ramp_lower", true, false)
	_hatch_leaf = $Model.find_child("lander_hatch_leaf", true, false)
	_rest = global_position
	set_engine(false)
	set_hatch_light(false)
	_apply()
	GameState.state_changed.connect(_on_state_changed)


func _process(delta: float) -> void:
	if global_position.distance_to(_rest) > FLYING_DISTANCE:
		_deploy_target = 0.0
		deployed = 0.0
	elif deployed != _deploy_target:
		deployed = move_toward(deployed, _deploy_target, delta / (RAMP_TIME + HATCH_TIME))
	_apply()


func set_engine(on: bool) -> void:
	engine_on = on
	engine_glow.visible = on


func set_plume(on: bool) -> void:
	plume_on = on


func set_hatch_light(on: bool) -> void:
	hatch_light.visible = on
	if on:
		_deploy_target = 1.0


func is_deployed() -> bool:
	return deployed >= 1.0


func _on_state_changed(old_state: int, _new_state: int) -> void:
	if old_state == GameState.State.CUTSCENE and global_position.distance_to(_rest) <= FLYING_DISTANCE:
		deployed = _deploy_target
		_apply()


func _apply() -> void:
	var ramp: float = clampf(deployed * (RAMP_TIME + HATCH_TIME) / RAMP_TIME, 0.0, 1.0)
	var door: float = clampf((deployed * (RAMP_TIME + HATCH_TIME) - RAMP_TIME) / HATCH_TIME, 0.0, 1.0)
	ramp = ramp * ramp * (3.0 - 2.0 * ramp)
	door = door * door * (3.0 - 2.0 * door)
	ramp_hinge.rotation.x = deg_to_rad(lerpf(RAMP_STOWED, RAMP_DEPLOYED, ramp))
	fold_hinge.rotation.x = deg_to_rad(lerpf(RAMP_LOWER_STOWED, 0.0, ramp))
	if _ramp_upper:
		_ramp_upper.rotation.x = ramp_hinge.rotation.x
		_ramp_lower.rotation.x = fold_hinge.rotation.x
	if _hatch_leaf:
		_hatch_leaf.rotation.y = deg_to_rad(lerpf(0.0, HATCH_OPEN, door))
