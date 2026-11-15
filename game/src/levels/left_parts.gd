class_name LeftParts

extends Node3D

## Parts an emergency recovery left out in the field (MissionDirector.leave_cargo): they lie where
## Kite stopped, frozen, until Kite fetches them. Kite stopped with the part's own socket empty and
## within FETCH_RANGE of it: E (interact_use) while driving mounts it back. Any part works, not only
## the logger. Recorded in the current mission's stats ("left_behind"), so a save keeps them.

const GROUP: StringName = &"left_parts"
const STATS_KEY: String = "left_behind"
const FETCH_RANGE: float = 1.5
const HINT_RANGE: float = 8.0
const STOPPED_SPEED: float = 0.1

## [{part, socket}] in the level now
var entries: Array = []


func _ready() -> void:
	add_to_group(GROUP)


## `part` (already off Kite) lies at `at` until fetched back into the socket named `socket_name`
func leave(part: HotswapPart, socket_name: String, at: Vector3) -> void:
	part.freeze = true
	part.linear_velocity = Vector3.ZERO
	part.angular_velocity = Vector3.ZERO
	part.global_transform = Transform3D(Basis.IDENTITY, _ground(part, at) + Vector3.UP * 0.2)
	entries.append({"part": part, "socket": socket_name})
	_record()


func has_parts() -> bool:
	_prune()
	return not entries.is_empty()


## Recreates the parts of the current mission's stats (a loaded save)
func restore(level: Node) -> void:
	for entry in CampaignState.mission_stats(CampaignState.current_mission()).get(STATS_KEY, []):
		var part := KiteSave._make_part(entry) if entry is Dictionary else null
		var at: Variant = entry.get("at") if entry is Dictionary else null
		if part == null or not (at is Array and at.size() == 3):
			continue
		level.add_child(part)
		part.freeze = true
		part.global_position = Vector3(at[0], at[1], at[2])
		entries.append({"part": part, "socket": str(entry.get("socket", ""))})


func _ground(part: Node3D, at: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 30.0, at + Vector3.DOWN * 30.0, 1)
	var hit: Dictionary = part.get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if hit else at


func _prune() -> void:
	entries = entries.filter(func(e: Dictionary) -> bool:
		return is_instance_valid(e["part"]) and not (e["part"] as HotswapPart).is_mounted())


## Rewrites the saved list from the parts still lying out (a part mounted by any route drops off it)
func record() -> void:
	_record()


func _record() -> void:
	_prune()
	var stats := CampaignState.mission_stats(CampaignState.current_mission())
	if stats.is_empty() and CampaignState.current_mission().is_empty():
		return
	var saved: Array = []
	for e in entries:
		var part: HotswapPart = e["part"]
		var p: Vector3 = part.global_position
		saved.append({"scene": part.scene_file_path, "socket": e["socket"], "at": [p.x, p.y, p.z],
			"catalog": part.get_catalog_id()})
	stats[STATS_KEY] = saved


## The nearest left part Kite could fetch: {part, socket, distance} or {}
func nearest(rover: Robot) -> Dictionary:
	_prune()
	var best: Dictionary = {}
	for e in entries:
		var socket := rover.find_child(e["socket"], true, false) as HotswapSocket if rover else null
		if socket == null:
			continue
		var offset: Vector3 = (e["part"] as Node3D).global_position - socket.global_position
		offset.y = 0.0
		if best.is_empty() or offset.length() < best["distance"]:
			best = {"part": e["part"], "socket": socket, "distance": offset.length()}
	return best


func can_fetch(rover: Robot) -> bool:
	var near := nearest(rover)
	return not near.is_empty() and near["distance"] <= FETCH_RANGE and (near["socket"] as HotswapSocket).part == null \
		and rover.linear_velocity.length() <= STOPPED_SPEED


func get_hint(rover: Robot) -> String:
	var near := nearest(rover)
	if near.is_empty() or near["distance"] > HINT_RANGE:
		return ""
	var part: HotswapPart = near["part"]
	if (near["socket"] as HotswapSocket).part != null:
		return "%s: its mount on Kite is full" % part.get_display_name()
	if near["distance"] > FETCH_RANGE:
		return "%s: bring Kite %.1f m closer" % [part.get_display_name(), near["distance"] - FETCH_RANGE]
	if rover.linear_velocity.length() > STOPPED_SPEED:
		return "Stop here"
	return "In position: press %s to load the %s" % [InputBindings.action_text(&"interact_use", "E"), part.get_display_name()]


func try_fetch(rover: Robot) -> bool:
	if not can_fetch(rover):
		return false
	var near := nearest(rover)
	var part: HotswapPart = near["part"]
	part.freeze = false
	(near["socket"] as HotswapSocket).mount(part)
	_record()
	return part.is_mounted()


func _physics_process(_delta: float) -> void:
	if entries.is_empty() or not Input.is_action_just_pressed(&"interact_use"):
		return
	if GameState.state == GameState.State.IN_GAME_ROBOT and is_instance_valid(GameState.robot):
		try_fetch(GameState.robot)
