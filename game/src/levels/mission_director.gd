class_name MissionDirector

extends Node

signal recovery_started(rover: Robot)
signal recovery_finished(rover: Robot)
## Kite stopped for good out in the field (flat battery or cold shutdown): it stays where it is until
## someone carries it home (EvaRescue) or the emergency recovery runs
signal stranded_changed(stranded: bool)

const SCAN_OBJECTIVES: Dictionary = {"iris_panel": "m1.iris_scanned"}
const ARRIVAL_OBJECTIVE: String = "m1.workshop_entered"
const MOUNT_OBJECTIVES: Dictionary = {"radio_module": "m2.module_loaded", "field_logger": "m3.logger_recovered"}
const CARGO_SOCKET: String = "CargoSocket"
const IRIS_ONLINE_FLAG: String = "iris_online"
const DOCK_OBJECTIVES: Dictionary = {"m1": "m1.kite_docked", "m2": "m2.kite_docked", "m3": "m3.kite_docked"}
const RECOVERY_DELAY: float = 3.0
const STRANDED_MESSAGE: String = "Kite is out of power. Return to the workshop console, then go outside to recover it."
const STRANDED_COLD_MESSAGE: String = "Kite shut down in the cold. Return to the workshop console, then go outside to recover it."
const OXYGEN_MESSAGE: String = "Suit oxygen ran out. Emergency recovery: you and Kite are being returned to the habitat."
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
const PAIR_MISSING: String = "THERMAL PAIR MISSING: record a sun and a shade ground temperature within 40 m of the far logger (thermal turret on the arm, mast view, E), then dock again."
const PAIR_TOO_FAR: String = "Reading taken, but too far from Evan's logger. Take the pair within 40 m of it."
const PAIR_SUN_FIRST: String = "Sun reading saved. Now a shade reading near the logger: try the marker post's shadow or Kite's own."
const PAIR_SHADE_FIRST: String = "Shade reading saved. Now a sunlit one near the logger."
const PAIR_DONE: String = "Sun and shade pair recorded."
const PAIR_ALREADY: String = "Thermal pair already recorded."
const THERMAL_KIT: Array[String] = ["thermal_cover", "thermal_heater"]
const STUCK_MESSAGE: String = "Recovery requested: Kite is being returned to the pad."
## Kite away from the pad and still this long (s): the console offers the emergency recovery
const STILL_FOR: float = 8.0
const STILL_SPEED: float = 0.2
## Mission time an emergency recovery costs (simulated, compressed like the rest of the story time)
const RECOVERY_MINUTES: float = 45.0
const PAIR_OBJECTIVE: String = "m3.thermal_pair_recorded"
## Set when both thermal readings were taken at the far rim (the pair may come before the logger)
const PAIR_FLAG: String = "m3_thermal_pair_far_rim"
## One flag per kind read at the far rim, saved, so the pair survives a load between the two readings
const RIM_READING_FLAG: String = "m3_thermal_far_rim_%s"
## Both readings within this of the far-rim logger site (m, horizontal)
const FAR_RIM_RADIUS: float = 40.0
## FarLogger's field position in moon_level.tscn, used when the level has no field logger
const FAR_RIM_SITE := Vector2(1.819, -59.287)
const LOGGER_ID: String = "field_logger"
const LANDING_ZONE_GROUP: StringName = &"landing_zone"
const LANDER_SCENE: String = "res://src/field/lander.tscn"
## Where Kite was when the campaign saved with the crate aboard: a load leaves it there
const CRATE_AT_KEY: String = "crate_on_kite_at"

@export var workshop: Workshop

var rover: Robot = null
var pad: ChargingPad = null
var ending: CampaignEnding = null
var cutscenes: CutsceneDirector = null
var stats: MissionStats = null
var recovering: bool = false
## Set while Kite is stranded in the field (see stranded_changed); `stranded_cause` is "battery" or "cold"
var stranded: bool = false
var stranded_cause: String = ""
var _stranded_detail: Dictionary = {}
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
var left_parts: LeftParts = null
var _traction: float = 1.0
var _far_rim := FAR_RIM_SITE
var _pair_done_before: bool = false
var landing_zone: Node3D = null
## The loaded save had Kite out in the field: it was put back there, cargo and all
var _restored_in_field: bool = false


func _ready() -> void:
	add_to_group(&"mission_director")
	rover = workshop.rover if workshop else null
	pad = workshop.pad if workshop else null
	landing_zone = get_tree().get_first_node_in_group(LANDING_ZONE_GROUP) as Node3D
	var sky := _sky()
	if sky:
		_level_sun = Vector2(sky.sun_azimuth, sky.sun_elevation)
	CampaignState.mission_started.connect(func(_id: String) -> void: _prepare_mission())
	CampaignState.campaign_reset.connect(apply_mission_sun)
	CampaignState.flag_changed.connect(_on_flag_changed)
	CampaignState.objective_completed.connect(_on_progress)
	CampaignState.mission_completed.connect(_on_progress)
	CampaignState.mission_started.connect(_on_progress)
	get_tree().node_added.connect(_on_node_added)
	for target in get_tree().get_nodes_in_group(&"scan_target"):
		_watch(target)
	if pad:
		pad.docked.connect(_on_docked)
		pad.docked.connect(func(docked_rover: Robot) -> void:
			if docked_rover == rover:
				SaveIndex.request_save())
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
	left_parts = LeftParts.new()
	left_parts.name = "LeftParts"
	add_child(left_parts)
	CampaignState.objective_completed.connect(func(_id: String) -> void: _try_pair())
	for sensor in get_tree().get_nodes_in_group(ThermalSensor.GROUP):
		sensor.reading_taken.connect(_on_reading_taken)
		sensor.message_source = pair_message
	var logger := get_parent().get_node_or_null("FarLogger") as HotswapPart
	if logger and not logger.is_mounted():
		_far_rim = Vector2(logger.global_position.x, logger.global_position.z)
	_start()


func _start() -> void:
	await get_tree().physics_frame
	if rover == null:
		return
	var loading: bool = not SaveIndex.pending_kite.is_empty()
	_prepare_mission()
	workshop.set_rover_pool(_starting_parts(loading))
	if loading:
		var saved: Dictionary = SaveIndex.pending_kite
		SaveIndex.pending_kite = {}
		KiteSave.apply(rover, saved)
		var pose: Variant = KiteSave.field_pose(saved)
		_restored_in_field = pose != null
		if pose == null:
			dock_rover()
			_returned_by_recovery = true
		else:
			rover.global_transform = pose
			rover.linear_velocity = Vector3.ZERO
			rover.angular_velocity = Vector3.ZERO
			if saved.get("stranded") == true:
				_restore_stranding(str(saved.get("stranded_cause", "battery")),
					saved["stranded_detail"] if saved.get("stranded_detail") is Dictionary else {})
		workshop.set_carried_parts(KiteSave.apply_tray(rover, saved))
		left_parts.restore(get_parent())
	_settle_cargo()
	_apply_iris_online(true)
	_last_position = rover.global_position
	_prepare_mission()
	_try_pair()
	workshop.account_rack()
	for socket: HotswapSocket in rover.find_children("*", "HotswapSocket", true, false):
		socket.part_mounted.connect(_on_part_mounted.bind(socket))


func _on_flag_changed(flag: String, value: bool) -> void:
	if flag == IRIS_ONLINE_FLAG:
		_apply_iris_online(false)
	elif flag == CargoPlan.DELIVERED_FLAG and value:
		_land_cargo()


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
		SaveIndex.request_save()


## SaveIndex calls this just before it writes: the field state that lives in the campaign's stats
func before_save() -> void:
	if rover and is_instance_valid(rover):
		_note_crate_on_kite()
		if left_parts and not CampaignState.current_mission().is_empty():
			left_parts.record()


## What KiteSave keeps of Kite's situation: on the pad (or being brought back to it), stranded and why
func field_state() -> Dictionary:
	return {"on_pad": recovering or pad == null or pad.is_in_zone(rover), "stranded": stranded,
		"stranded_cause": stranded_cause, "stranded_detail": _stranded_detail.duplicate(true)}


## Closing the window keeps the progress when saving is allowed; no toast, the game is going
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and rover and is_instance_valid(rover):
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
	if CampaignState.current_mission() == COLD_MISSION and not has_part(LOGGER_ID):
		return
	if CampaignState.current_mission() == COLD_MISSION and not CampaignState.is_objective_done(PAIR_OBJECTIVE):
		alert = PAIR_MISSING
		Debug.add_log(PAIR_MISSING)
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
	if stranded:
		if pad.is_in_zone(rover):
			_end_stranding(true)
		elif rover.battery != null and not rover.battery.is_empty():
			_end_stranding(false)               # the pack has power again (recharged, swapped): not stranded
	_learn_consumption()
	_update_ground()
	_update_crate()
	if recovering:
		_recovery_time -= delta
		if _recovery_time <= 0.0:
			_finish_recovery()
		return
	_update_cold(delta)
	_update_pair_alert()
	_update_still(delta)
	if recovering or CampaignState.current_mission().is_empty() or rover.battery == null:
		_low_warned = false
		return
	var warn: bool = return_warning()
	if warn and not _low_warned:
		DialogueTriggers.alert("low_battery")
	_low_warned = warn
	if rover.battery.is_empty() and not pad.is_in_zone(rover) and not stranded:
		_strand("battery")


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
	if stranded:
		return
	var zone := cold_zone_at(rover.global_position)
	rover.heater_requested = zone != null and heater_fitted()
	if zone == null or thermal_kit_fitted():
		if cold_time > 0.0:
			cold_time = 0.0
			alert = ""
		return
	if cold_time == 0.0:
		DialogueTriggers.alert("cold")
	cold_time += delta
	alert = COLD_WARNING % ceili(maxf(zone.shutdown_s - cold_time, 0.0))
	if cold_time >= zone.shutdown_s:
		cold_time = 0.0
		_strand("cold", {"zone": zone.route_name})


func loose_zone_at(point: Vector3) -> LooseGroundZone:
	for zone in get_tree().get_nodes_in_group(&"loose_ground_zone"):
		if zone is LooseGroundZone and zone.contains(point):
			return zone
	return null


## Loose ground under Kite: Robot.ground_traction (G1) while inside, 1.0 outside. Does nothing
## until the rover has that property.
func _update_ground() -> void:
	if not "ground_traction" in rover:
		return
	var zone := loose_zone_at(rover.global_position)
	var traction: float = zone.traction if zone and not recovering else 1.0
	if traction != _traction or float(rover.get("ground_traction")) != traction:
		_traction = traction
		rover.set("ground_traction", traction)


func has_part(catalog_id: String) -> bool:
	for socket: HotswapSocket in rover.find_children("*", "HotswapSocket", true, false):
		if socket.part and socket.part.get_catalog_id() == catalog_id:
			return true
	return false


## Kite on its way back: the mission's work out there is done
func returning() -> bool:
	var mission := CampaignState.current_mission()
	if mission == COLD_MISSION:
		return CampaignState.is_objective_done("m3.logger_recovered")
	return CampaignState.current_objective() == DOCK_OBJECTIVES.get(mission, "")


# --- Thermal pair at the far rim (m3.thermal_pair_recorded) -------------------------------------

## Readings elsewhere never undo one taken at the far rim
func _on_reading_taken(kind: String, _celsius: float, point: Vector3) -> void:
	_pair_done_before = _pair_done()
	if _counts_for_pair(point):
		CampaignState.set_flag(RIM_READING_FLAG % kind)
		_try_pair()


func _counts_for_pair(point: Vector3) -> bool:
	return CampaignState.current_mission() == COLD_MISSION and Vector2(point.x, point.z).distance_to(_far_rim) <= FAR_RIM_RADIUS


## The sensor's subtitle after the temperature (called after reading_taken, so the flags are current)
func pair_message(kind: String, point: Vector3) -> String:
	if _pair_done_before and CampaignState.current_mission() == COLD_MISSION:
		return PAIR_ALREADY
	if not _counts_for_pair(point):
		return PAIR_TOO_FAR
	if _pair_done():
		return PAIR_DONE
	return PAIR_SUN_FIRST if kind == "sun" else PAIR_SHADE_FIRST


func _pair_done() -> bool:
	return CampaignState.has_flag(PAIR_FLAG) or CampaignState.is_objective_done(PAIR_OBJECTIVE)


func _try_pair() -> void:
	if CampaignState.has_flag(RIM_READING_FLAG % "sun") and CampaignState.has_flag(RIM_READING_FLAG % "shade"):
		CampaignState.set_flag(PAIR_FLAG)
	if CampaignState.has_flag(PAIR_FLAG) and not CampaignState.is_objective_done(PAIR_OBJECTIVE):
		try_complete(PAIR_OBJECTIVE)


func _update_pair_alert() -> void:
	if alert == PAIR_MISSING and (not pad.is_in_zone(rover) or CampaignState.is_objective_done(PAIR_OBJECTIVE)):
		alert = ""


func _update_still(delta: float) -> void:
	var away: bool = not pad.is_in_zone(rover)
	still_time = still_time + delta if away and rover.linear_velocity.length() < STILL_SPEED else 0.0


## Kite is out on a mission and stranded, or away from the pad and hasn't moved for STILL_FOR s (stuck
## in the crater, wedged in boulders): the console may call the emergency recovery
## A stranded Kite (flat battery, cold shutdown) can be recovered at once, in every mission, whether or
## not anyone tries a rescue on foot: it is out of action, standing still or not (a flat Kite may still be
## coasting for a few seconds, and it used to be recovered without being asked at all).
func can_request_recovery() -> bool:
	if recovering or CampaignState.current_mission().is_empty() or rover == null:
		return false
	return stranded or (rover.battery != null and still_time >= STILL_FOR)


func request_recovery() -> bool:
	if not can_request_recovery():
		return false
	if stranded:
		# The recovery keeps what stranded Kite: the battery's or the cold's own record and words
		var cause := stranded_cause
		var detail := _stranded_detail.duplicate()
		_start_recovery(COLD_MESSAGE if cause == "cold" else RECOVERY_MESSAGE, cause, detail)
		return true
	var loose := loose_zone_at(rover.global_position)
	if loose:
		_start_recovery(STUCK_MESSAGE, "slip", {"zone": loose.label})
	else:
		_start_recovery(STUCK_MESSAGE, "stuck")
	return true


## Kite stops where it is: its battery is flat (or the cold killed it: the pack is drained) and the
## alert says to go and get it. Nothing moves it; the emergency recovery stays available from the
## console once it has been still for STILL_FOR s, and suit oxygen running out runs it too.
## A loaded save had Kite stranded: the same state and alert, nothing drained, recorded or refilled
func _restore_stranding(cause: String, detail: Dictionary) -> void:
	stranded = true
	stranded_cause = cause
	_stranded_detail = detail.duplicate(true)
	alert = STRANDED_COLD_MESSAGE if cause == "cold" else STRANDED_MESSAGE
	stranded_changed.emit(true)


func _strand(cause: String, detail: Dictionary = {}) -> void:
	if stranded:
		return
	stranded = true
	stranded_cause = cause
	_stranded_detail = detail.duplicate()
	if cause == "cold" and rover.battery:
		rover.battery.drain(rover.battery.capacity)
	alert = STRANDED_COLD_MESSAGE if cause == "cold" else STRANDED_MESSAGE
	Debug.add_log(alert)
	stranded_changed.emit(true)


## Kite is no longer stranded: carried onto the pad (`rescued`, noted in the report as a
## no-cost recovery on foot), or the emergency recovery took over
func _end_stranding(rescued: bool) -> void:
	if not stranded:
		return
	if rescued:
		var detail := _stranded_detail.duplicate()
		detail["rescued_on_foot"] = true
		detail["leg"] = "back" if returning() else "out"
		CampaignState.record_recovery(stranded_cause, distance_to_pad(), detail, 0.0)
	if alert == STRANDED_MESSAGE or alert == STRANDED_COLD_MESSAGE:
		alert = ""
	stranded = false
	stranded_cause = ""
	_stranded_detail = {}
	stranded_changed.emit(false)


## The player may pick Kite up out here: it is a field mission with Kite away from the pad and
## either stranded or stopped for STILL_FOR s (stuck). Never inside the workshop's pad zone.
func can_player_lift() -> bool:
	return rover != null and pad != null and not recovering and not CampaignState.current_mission().is_empty() \
		and not pad.is_in_zone(rover) and (stranded or still_time >= STILL_FOR)


## Suit oxygen ran out. With Kite away from the pad (stranded, stuck or just out in the field) the
## emergency recovery runs for it; the caller brings the player home.
func start_oxygen_recovery() -> bool:
	if recovering or rover == null or pad == null or CampaignState.current_mission().is_empty() or pad.is_in_zone(rover):
		return false
	_end_stranding(false)
	_start_recovery(OXYGEN_MESSAGE, "oxygen")
	return true


func _start_recovery(message: String = RECOVERY_MESSAGE, cause: String = "battery", detail: Dictionary = {}) -> void:
	_end_stranding(false)
	recovering = true
	_recovery_time = RECOVERY_DELAY
	alert = message
	Debug.add_log(message)
	detail = detail.duplicate()
	detail["leg"] = "back" if returning() else "out"
	var mission_stats := CampaignState.mission_stats(CampaignState.current_mission())
	detail["route"] = mission_stats.get("route", "")
	detail["used_wh"] = MissionReport.battery_wh(mission_stats)
	if rover.battery:
		detail["battery"] = rover.battery.get_catalog_id()
		detail["battery_wh"] = rover.battery.capacity
	detail["grip_wheels"] = has_part("wheel_high_grip")
	detail["thermal_kit"] = thermal_kit_fitted()
	CampaignState.record_recovery(cause, distance_to_pad(), detail, RECOVERY_MINUTES)
	DialogueTriggers.alert("recovery")
	recovery_started.emit(rover)


## Where a recovery leaves Kite's cargo: where it stopped, or, inside a cold or loose-ground zone,
## at the nearest route flag outside every zone, so standard wheels without the thermal kit reach it
func drop_point(at: Vector3) -> Vector3:
	if not _in_hazard(at):
		return at
	var markers := get_tree().get_first_node_in_group(&"route_markers") as RouteMarkers
	if markers == null:
		return at
	var best := at
	var best_d: float = INF
	for id in RouteMarkers.TITLES:
		for p: Vector2 in markers.route(id):
			var point := Vector3(p.x, at.y, p.y)
			var d: float = Vector2(at.x, at.z).distance_to(p)
			if d < best_d and not _in_hazard(point):
				best = point
				best_d = d
	return best


func _in_hazard(point: Vector3) -> bool:
	if loose_zone_at(point):
		return true
	for zone in get_tree().get_nodes_in_group(&"cold_zone"):
		if zone is ColdZone and zone.is_active() and zone.contains(point):
			return true
	return false


## The cargo stays out there: every CARGO part on Kite is left at the drop point
func leave_cargo() -> void:
	var at: Vector3 = drop_point(rover.global_position)
	var i: int = 0
	for socket: HotswapSocket in rover.find_children("*", "HotswapSocket", true, false):
		if socket.part and socket.part.part_type == HotswapPart.PartType.CARGO:
			var part: HotswapPart = socket.unmount()
			left_parts.leave(part, socket.name, at + Vector3(0.8 * i, 0.0, 0.0))
			i += 1


func _finish_recovery() -> void:
	recovering = false
	alert = ""
	_returned_by_recovery = true
	leave_cargo()
	dock_rover()
	if rover.battery:
		rover.battery.add_charge(rover.battery.capacity)
	_last_position = rover.global_position
	_last_charge = rover.battery.charge if rover.battery else -1.0
	recovery_finished.emit(rover)


# --- The cargo at the landing zone (m2.cargo_retrieved) -----------------------------------------

## Where the delivered crate is set down: the zone's CratePoint
func crate_point() -> Vector3:
	if landing_zone == null:
		return Vector3.ZERO
	var marker := landing_zone.get_node_or_null("CratePoint") as Node3D
	return marker.global_position if marker else landing_zone.global_position


## Metres from the pad to the crate's spot at the landing zone and back (0 without a zone)
func landing_zone_round_trip() -> float:
	if landing_zone == null or pad == null:
		return 0.0
	var offset: Vector3 = crate_point() - pad.global_position
	offset.y = 0.0
	return 2.0 * offset.length()


## Kite's range on its charge now: the rover's own estimate (G1) when it has one, else the charge
## over the consumption learned this session
func kite_range() -> float:
	if rover == null:
		return 0.0
	if rover.has_method("range_estimate"):
		return float(rover.call("range_estimate"))
	return rover.battery.charge / wh_per_metre() if rover.battery else 0.0


func crate_on_kite() -> bool:
	var socket := rover.get_node_or_null(CARGO_SOCKET) as HotswapSocket if rover else null
	return socket != null and socket.part != null and socket.part.get_catalog_id() == CargoPlan.CRATE_ID


func _crates() -> Array:
	return get_parent().find_children("*", "HotswapPart", true, false).filter(func(p: HotswapPart) -> bool:
		return p.get_catalog_id() == CargoPlan.CRATE_ID and not p.is_queued_for_deletion())


func _land_cargo() -> void:
	if landing_zone == null or not CargoPlan.awaiting_retrieval():
		return
	_show_cargo_lander()
	var crate := (load(CargoPlan.CRATE_PART_SCENE) as PackedScene).instantiate() as HotswapPart
	crate.name = "Crate"
	crate.mass = maxf(CargoPlan.crate_mass(), 1.0)
	landing_zone.add_child(crate)
	left_parts.leave(crate, CARGO_SOCKET, crate_point())


func _show_cargo_lander() -> void:
	if landing_zone == null or not CargoPlan.is_delivered() or landing_zone.has_node("CargoLander"):
		return
	var lander: Node3D = (load(LANDER_SCENE) as PackedScene).instantiate()
	lander.name = "CargoLander"
	landing_zone.add_child(lander)


## After a load: the cargo lander, the crate's mass, and a crate saved aboard Kite left where Kite was
## (Kite itself is put back on the pad, so the crate stays out there, as after a recovery)
func _settle_cargo() -> void:
	_show_cargo_lander()
	var mission := CampaignState.current_mission()
	var stats := CampaignState.mission_stats(mission)
	if CargoPlan.awaiting_retrieval():
		for crate: HotswapPart in _crates():
			crate.mass = maxf(CargoPlan.crate_mass(), 1.0)
		if crate_on_kite() and not _restored_in_field:
			var at: Variant = stats.get(CRATE_AT_KEY)
			var where: Vector3 = Vector3(at[0], at[1], at[2]) if at is Array and at.size() == 3 else crate_point()
			left_parts.leave((rover.get_node(CARGO_SOCKET) as HotswapSocket).unmount(), CARGO_SOCKET, drop_point(where))
		elif _crates().is_empty():
			_land_cargo()
	elif CargoPlan.is_delivered() and CampaignState.mission_objectives(mission).has(CargoPlan.RETRIEVED_OBJECTIVE):
		try_complete(CargoPlan.RETRIEVED_OBJECTIVE)       # a save from before the landing zone
	stats.erase(CRATE_AT_KEY)


func _note_crate_on_kite() -> void:
	var mission := CampaignState.current_mission()
	if mission.is_empty():
		return
	var stats := CampaignState.mission_stats(mission)
	if crate_on_kite():
		var p: Vector3 = rover.global_position
		stats[CRATE_AT_KEY] = [p.x, p.y, p.z]
	else:
		stats.erase(CRATE_AT_KEY)


## Kite in the bay with the crate aboard: unpacked, its parts to the rack, bench and the bay's crate
func _update_crate() -> void:
	if recovering or not CargoPlan.awaiting_retrieval() or not crate_on_kite() or not workshop.contains(rover.global_position):
		return
	(rover.get_node(CARGO_SOCKET) as HotswapSocket).unmount().queue_free()
	CampaignState.mission_stats(CampaignState.current_mission()).erase(CRATE_AT_KEY)
	CampaignState.set_flag(CargoPlan.AT_ZONE_FLAG, false)
	try_complete(CargoPlan.RETRIEVED_OBJECTIVE)
