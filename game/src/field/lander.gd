class_name Lander

extends Node3D

## The crew lander, landed near the outpost: a set piece with collision. Origin at the base, the
## hatch side facing -Z. Markers: Hatch (where the player stands on arrival, facing out),
## EngineGlow (the engine's light) and PlumePoint (where the landing plume starts). The opening
## cutscene drives it through the calls below.

@onready var hatch: Marker3D = $Hatch
@onready var engine_glow: Node3D = $EngineGlow
@onready var plume_point: Marker3D = $PlumePoint
@onready var hatch_light: Light3D = $HatchLight

var engine_on: bool = false
var plume_on: bool = false


func _ready() -> void:
	set_engine(false)
	set_hatch_light(false)


func set_engine(on: bool) -> void:
	engine_on = on
	engine_glow.visible = on


func set_plume(on: bool) -> void:
	plume_on = on


func set_hatch_light(on: bool) -> void:
	hatch_light.visible = on
