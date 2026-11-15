class_name MissionDirector

extends Node

signal recovery_started(rover: Robot)
signal recovery_finished(rover: Robot)

const SCAN_OBJECTIVES: Dictionary = {"iris_panel": "m1.iris_scanned"}
const ARRIVAL_OBJECTIVE: String = "m1.workshop_entered"
const MOUNT_OBJECTIVES: Dictionary = {"radio_module": "m2.module_loaded", "field_logger": "m3.logger_recovered"}
const CARGO_SOCKET: String = "CargoSocket"
const IRIS_ONLINE_FLAG: String = "iris_online"
const DOCK_OBJECTIVES: Dictionary = {"m1": "m1.kite_docked", "m2": "m2.kite_docked", "m3": "m3.kite_docked"}
const RECOVERY_DELAY: float = 3.0
const RECOVERY_MESSAGE: String = "Kite's battery is flat. Emergency recovery: Kite is being returned to the pad."
# Before 20 m are learned: Kite on flat regolith at 3 m/s with its electronics on (test_rover_mass)
const DEFAULT_WH_PER_M: float = 0.035
const MIN_WH_PER_M: float = 0.003
const LEARN_MIN_SPEED: float = 0.5
const MIN_LEARN_DISTANCE: float = 20.0
const RETURN_MARGIN: float = 1.3
const MAX_STEP_DRAIN: float = 0.05
const WARN_EXTRA: float = 0.1
const COLD_MISSION: String = "m3"
const COLD_LIMIT: float = 20.0
const COLD_WARNING: String = "COLD: Kite is in shade without its thermal cover and heater. Cold shutdown in %d s: get back to sunlight."
const COLD_MESSAGE: String = "Kite's electronics got too cold. Emergency recovery: Kite is being returned to the pad."
const THERMAL_KIT: Array[String] = ["thermal_cover", "thermal_heater"]
const STUCK_MESSAGE: String = "Recovery requested: Kite is being returned to the pad."
## Kite away from the pad and still this long (s): the console offers the emergency recovery
const STILL_FOR: float = 8.0
const STILL_SPEED: float = 0.2

@export var workshop: Workshop

var rover: Robot = null
var pad: ChargingPad = null
var ending: CampaignEnding = null
var cutscenes: CutsceneDirector = null
var stats: MissionStats = null
var recovering: bool = false
var alert: String = ""
var _recovery_time: float = 0.0
var _returned_by_recovery: bool = false
var _last_position: Vector3 = Vector3.ZERO
var _last_charge: float = -1.0
var _distance: float = 0.0
var _energy: float = 0.0
var cold_time: float = 0.0
var still_time: float = 0.0
var _level_sun := Vector2.ZERO
var _low_warned: bool = false


func _ready() -> void:
	add_to_group(&"mission_director")
	rover = workshop.rover if workshop else null
	pad = workshop.pad if workshop else null
	var sky := _sky()
	if sky:
		_level_sun = Vector2(sky.sun_azimuth, sky.sun_elevation)
	CampaignState.mission_started.connect(func(_id: String) -> void: _prepare_mission())
	CampaignState.campaign_reset.connect(apply_mission_sun)
	CampaignState.flag_changed.connect(_on_flag_changed)
	CampaignState.objective_completed.connect(_on_progress)
	CampaignState.mission_completed.connect(_on_progress)
	CampaignState.mission_started.connect(_on_progress)
	SceneLoader.level_unloaded.connect(_on_progress)
	get_tree().node_added.connect(_on_node_added)
	for target in get_tree().get_nodes_in_group(&"scan_target"):
		_watch(target)
	if pad:
		pad.docked.connect(_on_docked)
	cutscenes = CutsceneDirector.new()
	cutscenes.name = "Cutscenes"
	cutscenes.level = get_parent()
	cutscenes.director = self
	add_child(cutscenes)
	ending = CampaignEnding.new()
	ending.name = "CampaignEnding"
	add_child(ending)
	stats = MissionStats.new()
	stats.name = "MissionStats"
	add_child(stats)
	_start()


func _start() -> void:
	await get_tree().physics_frame
	if rover == null:
		return
	var loading: bool = not SaveIndex.pending_kite.is_empty()
	_prepare_mission()
	workshop.set_rover_pool(_starting_parts(loading))
	if loading:
		KiteSave.apply(rover, SaveIndex.pending_kite)
		SaveIndex.pending_kite = {}
		dock_rover()
		_returned_by_recovery = true
	_apply_iris_online(true)
	_last_position = rover.global_position
	_prepare_mission()
	workshop.account_rack()
	for socket: HotswapSocket in rover.find_children("*", "HotswapSocket", true, false):
		socket.part_mounted.connect(_on_part_mounted.bind(socket))


func _on_flag_changed(flag: String, _value: bool) -> void:
	if flag == IRIS_ONLINE_FLAG:
		_apply_iris_online(false)


func _apply_iris_online(instant: bool) -> void:
	var iris: Node = get_parent().get_node_or_null("Iris")
	var online: bool = CampaignState.has_flag(IRIS_ONLINE_FLAG)
	if iris and iris.has_method("set_online") and bool(iris.get("is_online")) != online:
		iris.set_online(online, instant)


func _starting_parts(skip_battery: bool) -> Array:
	var parts: Array = []
	for socket: HotswapSocket in rover.find_children("*", "HotswapSocket", true, false):
		if socket.part and not (skip_battery and socket.part is BatteryPart):
			parts.append(socket.part)
	return parts


func _on_progress(_id: String) -> void:
	if rover and is_instance_valid(rover):
		SaveIndex.save_current(rover)


func dock_rover() -> void:
	var dock: Transform3D = workshop.get_dock_transform()
	dock.origin += Vector3.UP * 0.3
	rover.global_transform = dock
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO


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
	apply_mission_sun()
	if CampaignState.current_mission() != "m1" or CampaignState.is_objective_done("m1.kite_prepared"):
		return
	if rover and rover.battery_socket and rover.battery_socket.part:
		var battery := rover.battery_socket.unmount()
		battery.queue_free()


func _sky() -> LunarSky:
	return get_parent().get_node_or_null("WorldEnvironment") as LunarSky


## M3 (and after it) shows the sun of its local day (CargoPlan), so the shade the player sees is
## the shade the cold zones use; before it, the level's own sun
func apply_mission_sun() -> void:
	var sky := _sky()
	if sky == null:
		return
	var sun: Vector2 = _level_sun
	var service: String = CargoPlan.delivered_service()
	if service and (CampaignState.current_mission() == COLD_MISSION or CampaignState.is_mission_completed(COLD_MISSION)):
		sun = CargoPlan.sun_on_day(CargoPlan.m3_day(service))
	if not is_equal_approx(sky.sun_azimuth, sun.x) or not is_equal_approx(sky.sun_elevation, sun.y):
		sky.sun_azimuth = sun.x
		sky.sun_elevation = sun.y


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


func _on_part_mounted(part: HotswapPart, socket: HotswapSocket) -> void:
	var id: String = part.get_catalog_id()
	if part is BatteryPart and socket == rover.battery_socket:
		try_complete("m1.kite_prepared")
	elif MOUNT_OBJECTIVES.has(id) and (id != "radio_module" or socket.name == CARGO_SOCKET):
		try_complete(MOUNT_OBJECTIVES[id])


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
	var charge: float = rover.battery.get_charge_fraction() if rover.battery else 0.0
	if objective and try_complete(objective):
		CampaignState.mission_stats(CampaignState.current_mission())["dock_battery"] = charge


func _physics_process(delta: float) -> void:
	_update_arrival()
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
	_update_cold(delta)
	_update_still(delta)
	if recovering or CampaignState.current_mission().is_empty() or rover.battery == null:
		_low_warned = false
		return
	var warn: bool = return_warning()
	if warn and not _low_warned:
		DialogueTriggers.alert("low_battery")
	_low_warned = warn
	if rover.battery.is_empty() and not pad.is_in_zone(rover):
		_start_recovery()


## m1 starts at the lander: the workshop lets the player in until they are inside
func _update_arrival() -> void:
	if workshop == null:
		return
	var arriving: bool = CampaignState.current_mission() == "m1" and not CampaignState.is_objective_done(ARRIVAL_OBJECTIVE)
	workshop.set_arrival(arriving)
	if arriving and GameState.state == GameState.State.IN_GAME_PLAYER and not cutscenes.is_busy() \
			and is_instance_valid(GameState.player) and workshop.is_arrived(GameState.player.global_position):
		try_complete(ARRIVAL_OBJECTIVE)


func _learn_consumption() -> void:
	var moved: Vector3 = rover.global_position - _last_position
	moved.y = 0.0
	_last_position = rover.global_position
	var charge: float = rover.battery.charge if rover.battery else -1.0
	# Learned only while moving, so time stopped doesn't inflate it; the electronics' draw at the
	# pace driven is included, which is what the drive back costs at the same pace
	var moving: bool = rover.linear_velocity.length() > LEARN_MIN_SPEED
	if moving and moved.length() < 5.0:
		_distance += moved.length()
	if moving and _last_charge >= 0.0 and charge >= 0.0 and charge < _last_charge and _last_charge - charge < MAX_STEP_DRAIN:
		_energy += _last_charge - charge
	_last_charge = charge


func wh_per_metre() -> float:
	if _distance < MIN_LEARN_DISTANCE:
		return DEFAULT_WH_PER_M
	return maxf(_energy / _distance, MIN_WH_PER_M)


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


func heater_fitted() -> bool:
	var socket := rover.find_child("HeaterSocket", true, false) as HotswapSocket
	return socket != null and socket.part != null and socket.part.get_catalog_id() == "thermal_heater"


func thermal_kit_fitted() -> bool:
	var fitted: Array = []
	for socket: HotswapSocket in rover.find_children("*", "HotswapSocket", true, false):
		if socket.part:
			fitted.append(socket.part.get_catalog_id())
	return THERMAL_KIT.all(func(id: String) -> bool: return fitted.has(id))


## The active cold zone Kite is in, or null
func cold_zone_at(point: Vector3) -> ColdZone:
	if CampaignState.current_mission() != COLD_MISSION or CampaignState.is_mission_completed(COLD_MISSION):
		return null
	for zone in get_tree().get_nodes_in_group(&"cold_zone"):
		if zone is ColdZone and zone.is_active() and zone.contains(point):
			return zone
	return null


func _update_cold(delta: float) -> void:
	var in_cold: bool = cold_zone_at(rover.global_position) != null
	rover.heater_requested = in_cold and heater_fitted()
	if not in_cold or thermal_kit_fitted():
		if cold_time > 0.0:
			cold_time = 0.0
			alert = ""
		return
	if cold_time == 0.0:
		DialogueTriggers.alert("cold")
	cold_time += delta
	alert = COLD_WARNING % ceili(maxf(COLD_LIMIT - cold_time, 0.0))
	if cold_time >= COLD_LIMIT:
		cold_time = 0.0
		_start_recovery(COLD_MESSAGE, "cold")


func _update_still(delta: float) -> void:
	var away: bool = not pad.is_in_zone(rover)
	still_time = still_time + delta if away and rover.linear_velocity.length() < STILL_SPEED else 0.0


## Kite is out on a mission, away from the pad and hasn't moved for STILL_FOR s (stuck in the
## crater, wedged in boulders): the console may call the emergency recovery
func can_request_recovery() -> bool:
	return not recovering and not CampaignState.current_mission().is_empty() and rover.battery != null \
		and still_time >= STILL_FOR


func request_recovery() -> bool:
	if not can_request_recovery():
		return false
	_start_recovery(STUCK_MESSAGE, "stuck")
	return true


func _start_recovery(message: String = RECOVERY_MESSAGE, cause: String = "battery") -> void:
	recovering = true
	_recovery_time = RECOVERY_DELAY
	alert = message
	Debug.add_log(message)
	CampaignState.record_recovery(cause, distance_to_pad())
	DialogueTriggers.alert("recovery")
	recovery_started.emit(rover)


func _finish_recovery() -> void:
	recovering = false
	alert = ""
	_returned_by_recovery = true
	dock_rover()
	if rover.battery:
		rover.battery.add_charge(rover.battery.capacity)
	_last_position = rover.global_position
	_last_charge = rover.battery.charge if rover.battery else -1.0
	recovery_finished.emit(rover)
