class_name MissionDirector

extends Node

signal recovery_started(rover: Robot)
signal recovery_finished(rover: Robot)

const SCAN_OBJECTIVES: Dictionary = {"iris_panel": "m1.iris_scanned"}
const DOCK_OBJECTIVES: Dictionary = {"m1": "m1.kite_docked", "m2": "m2.kite_docked", "m3": "m3.kite_docked"}
const RECOVERY_DELAY: float = 3.0
const RECOVERY_MESSAGE: String = "Kite's battery is flat. Emergency recovery: Kite is being returned to the pad."
const DEFAULT_WH_PER_M: float = 0.05
const MIN_LEARN_DISTANCE: float = 20.0
const RETURN_MARGIN: float = 1.3
const MAX_STEP_DRAIN: float = 0.05
const WARN_EXTRA: float = 0.1

@export var workshop: Workshop

var rover: Robot = null
var pad: ChargingPad = null
var recovering: bool = false
var alert: String = ""
var _recovery_time: float = 0.0
var _returned_by_recovery: bool = false
var _last_position: Vector3 = Vector3.ZERO
var _last_charge: float = -1.0
var _distance: float = 0.0
var _energy: float = 0.0


func _ready() -> void:
	add_to_group(&"mission_director")
	rover = workshop.rover if workshop else null
	pad = workshop.pad if workshop else null
	CampaignState.mission_started.connect(func(_id: String) -> void: _prepare_mission())
	get_tree().node_added.connect(_on_node_added)
	for target in get_tree().get_nodes_in_group(&"scan_target"):
		_watch(target)
	if pad:
		pad.docked.connect(_on_docked)
	_start()


func _start() -> void:
	await get_tree().physics_frame
	if rover == null:
		return
	_last_position = rover.global_position
	_prepare_mission()
	if rover.battery_socket:
		rover.battery_socket.part_mounted.connect(_on_part_mounted)


func _on_node_added(node: Node) -> void:
	if node.has_signal(&"scanned"):
		_watch.call_deferred(node)


func _watch(target: Node) -> void:
	if not is_instance_valid(target) or not target.is_in_group(&"scan_target") or not target.has_signal(&"scanned"):
		return
	var callback := _on_scanned.bind(target)
	if not target.is_connected(&"scanned", callback):
		target.connect(&"scanned", callback)


func _prepare_mission() -> void:
	if CampaignState.current_mission() != "m1" or CampaignState.is_objective_done("m1.kite_prepared"):
		return
	if rover and rover.battery_socket and rover.battery_socket.part:
		var battery := rover.battery_socket.unmount()
		battery.queue_free()


func try_complete(objective: String) -> bool:
	var objectives := CampaignState.mission_objectives(CampaignState.current_mission())
	var index: int = objectives.find(objective)
	if index < 0 or CampaignState.is_objective_done(objective):
		return false
	for k in index:
		if not CampaignState.is_objective_done(objectives[k]):
			return false
	CampaignState.complete_objective(objective)
	return true


func _on_part_mounted(part: HotswapPart) -> void:
	if part is BatteryPart:
		try_complete("m1.kite_prepared")


func _on_scanned(_by: Robot, target: Node) -> void:
	var id: String = str(target.get("target_id")) if target.get("target_id") != null else ""
	if not SCAN_OBJECTIVES.has(id):
		return
	if not try_complete(SCAN_OBJECTIVES[id]) and target is ScanTarget \
			and not CampaignState.is_objective_done(SCAN_OBJECTIVES[id]):
		target.is_scanned = false


func _on_docked(docked_rover: Robot) -> void:
	if docked_rover != rover or _returned_by_recovery:
		return
	var objective: String = DOCK_OBJECTIVES.get(CampaignState.current_mission(), "")
	if objective:
		try_complete(objective)


func _physics_process(delta: float) -> void:
	if rover == null or pad == null:
		return
	if _returned_by_recovery and not pad.is_in_zone(rover):
		_returned_by_recovery = false
	_learn_consumption()
	if recovering:
		_recovery_time -= delta
		if _recovery_time <= 0.0:
			_finish_recovery()
		return
	if CampaignState.current_mission().is_empty() or rover.battery == null:
		return
	if rover.battery.is_empty() and not pad.is_in_zone(rover):
		_start_recovery()


func _learn_consumption() -> void:
	var moved: Vector3 = rover.global_position - _last_position
	moved.y = 0.0
	_last_position = rover.global_position
	var charge: float = rover.battery.charge if rover.battery else -1.0
	if moved.length() < 5.0:
		_distance += moved.length()
	if _last_charge >= 0.0 and charge >= 0.0 and charge < _last_charge and _last_charge - charge < MAX_STEP_DRAIN:
		_energy += _last_charge - charge
	_last_charge = charge


func wh_per_metre() -> float:
	if _distance < MIN_LEARN_DISTANCE:
		return DEFAULT_WH_PER_M
	return maxf(_energy / _distance, DEFAULT_WH_PER_M * 0.5)


func distance_to_pad() -> float:
	if rover == null or pad == null:
		return 0.0
	return pad.offset_of(rover).length()


## Charge fraction needed to drive back to the pad from here, with a margin
func return_fraction_needed() -> float:
	if rover == null or rover.battery == null or rover.battery.capacity <= 0.0:
		return 0.0
	return distance_to_pad() * wh_per_metre() * RETURN_MARGIN / rover.battery.capacity


func return_warning() -> bool:
	if rover == null or rover.battery == null or pad.is_in_zone(rover):
		return false
	return rover.battery.get_charge_fraction() <= return_fraction_needed() + WARN_EXTRA


func _start_recovery() -> void:
	recovering = true
	_recovery_time = RECOVERY_DELAY
	alert = RECOVERY_MESSAGE
	Debug.add_log(RECOVERY_MESSAGE)
	recovery_started.emit(rover)


func _finish_recovery() -> void:
	recovering = false
	alert = ""
	_returned_by_recovery = true
	var dock: Transform3D = workshop.get_dock_transform()
	dock.origin += Vector3.UP * 0.3
	rover.global_transform = dock
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO
	if rover.battery:
		rover.battery.add_charge(rover.battery.capacity)
	_last_position = rover.global_position
	_last_charge = rover.battery.charge if rover.battery else -1.0
	recovery_finished.emit(rover)
