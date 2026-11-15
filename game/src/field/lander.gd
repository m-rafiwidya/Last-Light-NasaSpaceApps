class_name Lander

extends Node3D

## The crew lander (res/models/lander_kit/lander.glb, tools/blender/LANDER_KIT.md), landed near the
## outpost: a set piece with collision. Origin at the base, the hatch side facing -Z. Markers: Hatch
## (on the porch, where the player stands on arrival, facing out), EngineGlow (the engine's light and
## glowing bell), PlumePoint (the bell's exit) and RampFoot. Moved away from where it stands (the
## opening's descent), its ramp folds up in front of the shut hatch; set_hatch_light(true) lowers the
## ramp, then opens the hatch. When a cutscene hands over, the motion finishes at once.
## Under power the engine's light and bell flicker and the exhaust shimmers under the bell; the plume
## (LanderPlume) blows the ground out below 10 m while both engine and plume are on. touchdown()
## settles the lander on its struts.

signal touched_down

const RAMP_DEPLOYED: float = -30.0
const RAMP_STOWED: float = 90.0
const RAMP_LOWER_STOWED: float = -180.0
const HATCH_OPEN: float = -176.0
const RAMP_TIME: float = 3.0
const HATCH_TIME: float = 1.5
const FLYING_DISTANCE: float = 0.5
const GLOW_ENERGY: float = 4.0
const SHIMMER: float = 1.0
## A cutscene camera stays outside this box (local, the legs and the antenna included) plus CAMERA_MARGIN
const HULL := AABB(Vector3(-3.3, -0.1, -3.7), Vector3(6.6, 7.0, 7.0))
const CAMERA_MARGIN: float = 0.6
## Touchdown: the upper stage sinks this share of its height on the struts and springs back
const JOLT_DEPTH: float = 0.02
const JOLT_TIME: float = 0.9

@onready var hatch: Marker3D = $Hatch
@onready var engine_glow: Node3D = $EngineGlow
@onready var plume_point: Marker3D = $PlumePoint
@onready var hatch_light: Light3D = $HatchLight
@onready var ramp_hinge: Node3D = $RampHinge
@onready var fold_hinge: Node3D = $RampHinge/FoldHinge
@onready var plume: LanderPlume = $PlumePoint/Plume
@onready var model: Node3D = $Model
@onready var _glow_light: OmniLight3D = $EngineGlow/Light
@onready var _bell: MeshInstance3D = $EngineGlow/Bell
@onready var _shimmer: MeshInstance3D = $EngineGlow/Shimmer

var engine_on: bool = false
var plume_on: bool = false
## 0: ramp folded up, hatch shut; 1: ramp down and hatch open (RAMP_TIME + HATCH_TIME apart)
var deployed: float = 1.0
var _deploy_target: float = 1.0
var _rest: Vector3
var _ramp_upper: Node3D
var _ramp_lower: Node3D
var _hatch_leaf: Node3D
var _time: float = 0.0
## Seconds since touchdown() (-1: settled)
var jolt_time: float = -1.0
var _bell_color: Color


func _ready() -> void:
	add_to_group(&"cutscene_solid")
	_ramp_upper = $Model.find_child("lander_ramp_upper", true, false)
	_ramp_lower = $Model.find_child("lander_ramp_lower", true, false)
	_hatch_leaf = $Model.find_child("lander_hatch_leaf", true, false)
	_rest = global_position
	_bell.set_surface_override_material(0, _bell.get_surface_override_material(0).duplicate())
	_bell_color = (_bell.get_surface_override_material(0) as StandardMaterial3D).albedo_color
	set_engine(false)
	set_hatch_light(false)
	_apply()
	GameState.state_changed.connect(_on_state_changed)


func _process(delta: float) -> void:
	_time += delta
	_update_engine()
	_update_jolt(delta)
	if global_position.distance_to(_rest) > FLYING_DISTANCE:
		_deploy_target = 0.0
		deployed = 0.0
	elif deployed != _deploy_target:
		deployed = move_toward(deployed, _deploy_target, delta / (RAMP_TIME + HATCH_TIME))
	_apply()


func set_engine(on: bool) -> void:
	engine_on = on
	engine_glow.visible = on
	_update_engine()


func set_plume(on: bool) -> void:
	plume_on = on
	_update_engine()


func touchdown() -> void:
	jolt_time = 0.0
	touched_down.emit()


## `point` moved out of the hull box (plus CAMERA_MARGIN) by the shortest way, sideways or up
func keep_camera_out(point: Vector3) -> Vector3:
	var local: Vector3 = to_local(point)
	var box: AABB = HULL.grow(CAMERA_MARGIN)
	if not box.has_point(local):
		return point
	var exits: Array = [
		[local.x - box.position.x, Vector3(box.position.x, local.y, local.z)],
		[box.end.x - local.x, Vector3(box.end.x, local.y, local.z)],
		[local.z - box.position.z, Vector3(local.x, local.y, box.position.z)],
		[box.end.z - local.z, Vector3(local.x, local.y, box.end.z)],
		[box.end.y - local.y, Vector3(local.x, box.end.y, local.z)],
	]
	exits.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return to_global(exits[0][1])


## The upper stage's sink (share of its height) t seconds after touchdown: down on the struts, a
## small rebound, settled by JOLT_TIME
static func jolt_at(t: float) -> float:
	if t < 0.0 or t >= JOLT_TIME:
		return 0.0
	return JOLT_DEPTH * exp(-t / 0.22) * sin(PI * t / 0.3)


func _update_engine() -> void:
	plume.active = engine_on and plume_on
	if not engine_on:
		return
	var flicker: float = 1.0 + 0.1 * sin(_time * 37.0) + 0.07 * sin(_time * 61.3 + 1.7) + 0.05 * sin(_time * 113.0)
	_glow_light.light_energy = GLOW_ENERGY * flicker
	(_bell.get_surface_override_material(0) as StandardMaterial3D).albedo_color = _bell_color * clampf(flicker, 0.8, 1.2)
	(_shimmer.get_surface_override_material(0) as ShaderMaterial).set_shader_parameter("intensity", SHIMMER * flicker)


func _update_jolt(delta: float) -> void:
	if jolt_time < 0.0:
		return
	jolt_time += delta
	model.scale.y = 1.0 - jolt_at(jolt_time)
	if jolt_time >= JOLT_TIME:
		jolt_time = -1.0
		model.scale.y = 1.0


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
		jolt_time = -1.0
		model.scale.y = 1.0


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
