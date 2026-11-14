class_name RoverScanner

extends Node

## Scanning with the mast camera (tools/blender/IRIS_KIT.md 6.3): while this rover is driven in
## the mast view, a ray from the camera's centre (RANGE m, the world and vehicle layers) that stays
## on a node in the "scan_target" group (IRIS) for HOLD seconds scans it: the target's
## mark_scanned(rover), and its scan_report as a "Kite:" subtitle. Off the target for more than
## GRACE seconds starts over. get_hint() feeds the robot HUD's ScanHint.

const RANGE: float = 30.0
const HOLD: float = 1.5
const GRACE: float = 0.3
const SHOW_DONE: float = 3.0
const MASK: int = 1 | 2

@onready var robot: Robot = get_parent() as Robot

## The target being scanned and how far along (0..1)
var target: Node = null
var progress: float = 0.0
var _off: float = 0.0
var _done_name: String = ""
var _done_time: float = 0.0


func _scan_target_of(node: Node) -> Node:
	while node:
		if node.is_in_group(&"scan_target"):
			return node
		node = node.get_parent()
	return null


func _physics_process(delta: float) -> void:
	_done_time = maxf(_done_time - delta, 0.0)
	if not robot.is_driven() or not robot.is_aiming() or robot.camera == null:
		target = null
		progress = 0.0
		return
	var from: Vector3 = robot.camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - robot.camera.global_basis.z * RANGE, MASK)
	query.exclude = [robot.get_rid()]
	var hit: Dictionary = robot.get_world_3d().direct_space_state.intersect_ray(query)
	var found: Node = _scan_target_of(hit["collider"]) if hit else null
	if found and not found.get("is_scanned"):
		if found != target:
			target = found
			progress = 0.0
		_off = 0.0
		progress = minf(progress + delta / HOLD, 1.0)
		if progress >= 1.0:
			found.mark_scanned(robot)
			_done_name = found.get("scan_name")
			_done_time = SHOW_DONE
			var line := Dialog.new()
			line.speaker = "Kite"
			line.subtitle = found.get("scan_report")
			line.min_duration = 6.0
			DialogServer.play_dialog(line)
			target = null
			progress = 0.0
	else:
		_off += delta
		if _off > GRACE:
			target = null
			progress = 0.0


func get_hint() -> String:
	if target:
		return "SCANNING  %s  %d%%" % [target.get("scan_name"), floori(progress * 100.0)]
	if _done_time > 0.0:
		return "SCANNED  %s" % _done_name
	return ""
