class_name MissionStats

extends Node

## Adds Kite's drive to the current mission's stats (CampaignState.mission_stats) until its
## downlink is sent: distance, battery use by consumer, cold shade, slope, payload, route flags
## passed and stuck hints shown. Recoveries are recorded by MissionDirector.

const MOVING_SPEED: float = 0.5
const FLAG_RADIUS: float = 10.0
## Share of a route's flags passed before the report names that route
const ROUTE_SHARE: float = 0.5
const SLOPE_SMOOTHING: float = 4.0

var director: MissionDirector = null
var _last_position: Vector3 = Vector3.ZERO
var _tilt: float = 0.0
var _stuck_shown: bool = false


func _ready() -> void:
	director = get_parent() as MissionDirector


func _physics_process(delta: float) -> void:
	var rover: Robot = director.rover if director else null
	var mission := CampaignState.current_mission()
	if rover == null or mission.is_empty():
		return
	var stats := CampaignState.mission_stats(mission)
	var moved: Vector3 = rover.global_position - _last_position
	_last_position = rover.global_position
	if stats.get("sent", false):
		return
	var moving: bool = rover.linear_velocity.length() > MOVING_SPEED and not director.recovering
	moved.y = 0.0
	if moving and moved.length() < 5.0:
		_add(stats, "distance_m", moved.length())
	if rover.battery:
		_add(stats, "drive_wh", maxf(rover.electrical_power, 0.0) * delta / 3600.0)
		_add(stats, "electronics_wh", rover.electronics_power * delta / 3600.0)
		_add(stats, "heater_wh", rover.heater_power * delta / 3600.0)
		stats["capacity_wh"] = rover.battery.capacity
		stats["min_battery"] = minf(float(stats.get("min_battery", 1.0)), rover.battery.get_charge_fraction())
	if director.cold_zone_at(rover.global_position):
		_add(stats, "cold_s", delta)
		if rover.heater_requested:
			_add(stats, "heater_s", delta)
	var tilt: float = rad_to_deg(rover.global_basis.y.angle_to(Vector3.UP))
	_tilt = lerpf(_tilt, tilt, minf(delta * SLOPE_SMOOTHING, 1.0)) if moving else tilt
	if moving:
		stats["max_slope_deg"] = maxf(float(stats.get("max_slope_deg", 0.0)), _tilt)
	stats["max_payload_kg"] = maxf(float(stats.get("max_payload_kg", 0.0)), rover.cargo_mass)
	_pass_flags(stats, Vector2(rover.global_position.x, rover.global_position.z))
	_count_stuck_hint(stats)


func _add(stats: Dictionary, key: String, value: float) -> void:
	stats[key] = float(stats.get(key, 0.0)) + value


## Route flags Kite passed (indices; the logger, the shared last point, isn't a flag)
func _pass_flags(stats: Dictionary, at: Vector2) -> void:
	var markers := get_tree().get_first_node_in_group(&"route_markers") as RouteMarkers
	if markers == null:
		return
	var passed: Dictionary = stats.get("route_flags", {})
	for id in RouteMarkers.TITLES:
		var points: PackedVector2Array = markers.route(id)
		for i in points.size() - 1:
			var key: String = str(i)
			if at.distance_to(points[i]) < FLAG_RADIUS and not passed.get(id, {}).has(key):
				if not passed.has(id):
					passed[id] = {}
				passed[id][key] = true
				stats["route_flags"] = passed
				stats["route"] = route_from(passed, markers)


static func route_from(passed: Dictionary, markers: RouteMarkers) -> String:
	var best: String = ""
	var best_share: float = ROUTE_SHARE
	for id in RouteMarkers.TITLES:
		var flags: int = markers.route(id).size() - 1
		var share: float = float(passed.get(id, {}).size()) / flags if flags > 0 else 0.0
		if share >= best_share:
			best = id
			best_share = share
	return best


func _count_stuck_hint(stats: Dictionary) -> void:
	var guidance := get_tree().get_first_node_in_group(&"guidance") as Guidance
	var shown: bool = guidance != null and guidance.active and guidance.stuck_text() != ""
	if shown and not _stuck_shown:
		stats["stuck_hints"] = int(stats.get("stuck_hints", 0)) + 1
	_stuck_shown = shown
