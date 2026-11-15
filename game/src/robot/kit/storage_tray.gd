class_name StorageTray

extends Node3D

## Kite's open storage tray on the deck (replacing G2's snap slots): loose parts ride in it with real
## physics, so braking, bumps, turns and slopes slide and tip them, and careless driving throws them
## out. The tray's floor and rim are collision shapes of Kite's own body (TrayFloor, TrayWall*), so
## they move exactly with it; this node holds the visual tray and `TrayArea`, which knows which
## parts are inside. (A separate moving-platform body trailed Kite by a physics step and let parts
## slip through its walls.)

@onready var area: Area3D = $TrayArea

## While true the tray's parts ride locked to Kite (frozen, children of the tray), e.g. while a
## human carries Kite home or a cargo net holds them; see set_secured()
var secured: bool = false
var _secured_parts: Array[HotswapPart] = []
var _parent_of: Dictionary = {}                 # part -> its parent before it was secured


## The loose parts in the tray now
func items() -> Array[HotswapPart]:
	var found: Array[HotswapPart] = []
	for node in area.get_overlapping_bodies():
		var part := node as HotswapPart
		if part and not part.is_mounted():
			found.append(part)
	return found


func holds(part: HotswapPart) -> bool:
	return part in items()


## Inside of the tray (m): parts must fit within it, lying as they are. Low enough (0.12 m) to stay
## under the cargo mount's capture box, which starts 7 cm above the mount and would grab a cargo
## part poking up into it from the tray's front edge
const INSIDE := Vector3(0.19, 0.12, 0.19)


## True when `part` would fit in the tray (its meshes' box, either way round)
func fits(part: HotswapPart) -> bool:
	var size := Vector3.ZERO
	var first := true
	var box := AABB()
	for mesh: MeshInstance3D in part.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		var b: AABB = (part.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	size = box.size
	return not first and maxf(size.x, size.z) <= INSIDE.x and minf(size.x, size.z) <= INSIDE.z and size.y <= INSIDE.y


## Locks the tray's parts to Kite (on) or lets them ride loose again where they are (off). For
## carrying Kite (a human rescue: tilted and swung, loose parts would spill) and a cargo net.
func set_secured(on: bool) -> void:
	if on == secured:
		return
	secured = on
	if on:
		_secured_parts = items()
		for part in _secured_parts:
			_parent_of[part] = part.get_parent()
			part.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			part.freeze = true
			part.reparent(self, true)
		return
	for part in _secured_parts:
		if not is_instance_valid(part) or part.get_parent() != self:
			continue                             # taken out meanwhile
		var back: Node = _parent_of.get(part)
		part.reparent(back if is_instance_valid(back) else get_parent().get_parent(), true)
		part.freeze = false
		part.sleeping = false
		part.linear_velocity = Vector3.ZERO
		part.angular_velocity = Vector3.ZERO
	_secured_parts.clear()
	_parent_of.clear()


## Where to let go of a part so it lands in the tray (world): above the floor's centre
func drop_point() -> Vector3:
	return area.global_position + global_basis.y * 0.04
