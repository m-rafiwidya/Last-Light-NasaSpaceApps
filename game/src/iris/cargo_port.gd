class_name CargoPort

extends Node3D

## A service port that a rover's arm can lower cargo into (tools/blender/IRIS_KIT.md 6.2, 8). Sits
## on the port's top centre (socket_cartridge), its axes the port's: X along the opening's long
## side, Y up. CargoDelivery on a rover finds ports in the "cargo_port" group.

## Emitted when a part has been lowered in and released
signal cargo_inserted(part: HotswapPart, rover: Robot)

## The catalog id of what fits (HotswapPart.get_catalog_id())
@export var accepts: String = "cartridge"
## Where a seated part's origin goes (anchor_cartridge_seated)
var seat: Node3D = null
## Something that must be scanned first (has `is_scanned`), or null
var scan_gate: Node = null
## The part in the port, null while it's empty
var occupant: HotswapPart = null


func _ready() -> void:
	add_to_group(&"cargo_port")


func fits(part: HotswapPart) -> bool:
	return occupant == null and part != null and part.get_catalog_id() == accepts


func needs_scan() -> bool:
	return scan_gate != null and not scan_gate.get("is_scanned")


## Takes the part: it goes onto the seat, squared to the port, and stays there frozen
func accept(part: HotswapPart, rover: Robot) -> void:
	occupant = part
	part.reparent(seat if seat else self, false)
	part.transform = Transform3D.IDENTITY
	part.collision_layer = 0
	part.collision_mask = 0
	part.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	part.freeze = true
	cargo_inserted.emit(part, rover)
