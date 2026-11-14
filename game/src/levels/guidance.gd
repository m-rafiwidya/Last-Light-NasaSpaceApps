class_name Guidance

extends Node

signal step_changed(objective: String, index: int)

const MISSIONS_PATH: String = "res://res/story/missions.json"
const STUCK_TIME: float = 45.0
const LABEL_LIFT: float = 0.35
const ACTIVE_STATES: Array[String] = ["IN_GAME_PLAYER", "IN_GAME_ROBOT", "MISSION_CONSOLE"]
const GLOW_SHADER: Shader = preload("res://src/ui/guidance/guidance_glow.gdshader")
const OUTLINE_SHADER: Shader = preload("res://src/ui/guidance/guidance_outline.gdshader")

var objective: String = ""
var index: int = -1
var stuck_time: float = 0.0
var target: Node3D = null
var overlay: GuidanceOverlay = null
var active: bool = false

var _steps: Dictionary = {}
var _complete_text: Dictionary = {}
var _highlighted: Array[GeometryInstance3D] = []
var _markers: Array[Node] = []
var _follows: Array = []
var _material: ShaderMaterial = null


func _ready() -> void:
	add_to_group(&"guidance")
	_load()
	_material = ShaderMaterial.new()
	_material.shader = GLOW_SHADER
	var outline := ShaderMaterial.new()
	outline.shader = OUTLINE_SHADER
	_material.next_pass = outline
	overlay = GuidanceOverlay.new()
	overlay.guidance = self
	add_child(overlay)
	GeneralSettings.section.changed.connect(func(_key: String) -> void:
		if active:
			_refresh_highlight())
	CampaignState.mission_started.connect(func(_id: String) -> void: _set_active(true))
	_set_active(not CampaignState.current_mission().is_empty())


func _set_active(value: bool) -> void:
	active = value
	set_physics_process(value)
	overlay.set_process(value)
	overlay.visible = value
	if not value:
		_clear_highlight()
		target = null
		objective = ""
		index = -1
		stuck_time = 0.0


func _load() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MISSIONS_PATH))
	if not (data is Dictionary and data.get("missions") is Array):
		return
	for mission in data["missions"]:
		if mission.get("guidance") is Dictionary:
			for objective_id in mission["guidance"]:
				_steps[objective_id] = mission["guidance"][objective_id]
		if mission.get("complete_guidance") is String:
			_complete_text[mission["id"]] = mission["complete_guidance"]


static func enabled() -> bool:
	return GeneralSettings.guidance()


func steps(objective_id: String) -> Array:
	return _steps.get(objective_id, [])


func current_step() -> Dictionary:
	var list := steps(objective)
	return list[index] if index >= 0 and index < list.size() else {}


func step_text() -> String:
	var step := current_step()
	if step.is_empty():
		var mission := CampaignState.current_mission()
		return _complete_text.get(mission, "") if CampaignState.is_mission_completed(mission) else ""
	var key: String = step.get("key", "")
	return ("[%s]  %s" % [InputBindings.action_text(StringName(key)), step["text"]]) if key else step["text"]


func stuck_text() -> String:
	return current_step().get("stuck", "") if stuck_time >= STUCK_TIME else ""


func is_waypoint() -> bool:
	return current_step().get("waypoint", false) and target != null


func _physics_process(delta: float) -> void:
	if CampaignState.current_mission().is_empty():
		_set_active(false)
		return
	_follow_markers()
	if not GameState.State.keys()[GameState.state] in ACTIVE_STATES:
		return
	var new_objective := CampaignState.current_objective()
	var new_index := compute_index(new_objective)
	if new_objective != objective or new_index != index:
		objective = new_objective
		index = new_index
		stuck_time = 0.0
		_refresh_highlight()
		step_changed.emit(objective, index)
	else:
		stuck_time += delta
		if enabled() and (not is_instance_valid(target) and target != null
				or resolve(current_step().get("target", "")) != target):
			_refresh_highlight()


func compute_index(objective_id: String) -> int:
	var list := steps(objective_id)
	if list.is_empty():
		return -1
	var last_met: int = -1
	for i in list.size():
		if is_met(list[i].get("done_when", {})):
			last_met = i
	return mini(last_met + 1, list.size() - 1)


func is_met(condition: Dictionary) -> bool:
	if condition.is_empty():
		return false
	var state: String = GameState.State.keys()[GameState.state]
	for key in condition:
		match key:
			"state":
				if not state in condition["state"]:
					return false
			"not_state":
				if state in condition["not_state"]:
					return false
			"holding_part":
				var held: Object = GameState.player.holder.held_object if is_instance_valid(GameState.player) else null
				if not (held is HotswapPart and HotswapPart.PartType.keys()[held.part_type].to_lower() == condition["holding_part"]):
					return false
			"mounted":
				var socket := resolve(condition["mounted"]) as HotswapSocket
				if socket == null or socket.part == null:
					return false
			"near":
				var rover := _rover()
				var node := resolve(condition["near"])
				if rover == null or node == null:
					return false
				var offset: Vector3 = node.global_position - rover.global_position
				offset.y = 0.0
				if offset.length() > float(condition.get("distance", 10.0)):
					return false
			"view":
				var rover := _rover()
				var rig := rover.get_node_or_null("CameraRig") as RoverCamera if rover else null
				if rig == null or rig.view != RoverCamera.View.get(str(condition["view"]).to_upper(), -1):
					return false
			"console_section":
				var console := get_tree().get_first_node_in_group(&"mission_console")
				if console == null or SECTION_NAMES.find(str(condition["console_section"])) != int(console.section):
					return false
	return true


const SECTION_NAMES: Array[String] = ["mission", "kite", "downlink"]


func resolve(spec: String) -> Node3D:
	var kind: String = spec.get_slice(":", 0)
	var rest: String = spec.substr(kind.length() + 1)
	match kind:
		"path":
			return get_parent().get_node_or_null(rest) as Node3D
		"group":
			return get_tree().get_first_node_in_group(StringName(rest)) as Node3D
		"scan":
			for node in get_tree().get_nodes_in_group(&"scan_target"):
				if str(node.get("target_id")) == rest:
					return node as Node3D
		"kite":
			var rover := _rover()
			if rover == null:
				return null
			var parts := rest.split("/", true, 1)
			var node: Variant = rover.get(parts[0])
			if node is Node and parts.size() > 1:
				node = (node as Node).get_node_or_null(parts[1])
			return node as Node3D
	return null


func _rover() -> Robot:
	for workshop in get_tree().get_nodes_in_group(&"workshop"):
		if is_instance_valid(workshop.rover):
			return workshop.rover
	return null


func _refresh_highlight() -> void:
	_clear_highlight()
	if not enabled():
		target = null
		return
	var step := current_step()
	target = resolve(step.get("target", ""))
	if target == null:
		return
	var meshes: Array[GeometryInstance3D] = []
	for node in target.find_children("*", "GeometryInstance3D", true, false):
		var mesh := node as GeometryInstance3D
		if mesh.is_visible_in_tree() and not mesh is Label3D and mesh.material_overlay == null:
			meshes.append(mesh)
	var bounds := AABB()
	if meshes.is_empty():
		bounds = _box_marker()
	else:
		for mesh in meshes:
			mesh.material_overlay = _material
			_highlighted.append(mesh)
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			bounds = box if bounds.size == Vector3.ZERO else bounds.merge(box)
	var name_text: String = step.get("label", "")
	if name_text and bounds.size != Vector3.ZERO:
		var label := Label3D.new()
		label.name = "GuidanceLabel"
		label.text = name_text
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.fixed_size = true
		label.no_depth_test = true
		label.pixel_size = 0.0008
		label.font_size = 40
		label.outline_size = 10
		label.modulate = Color(1.0, 0.8, 0.35)
		label.render_priority = 10
		label.outline_render_priority = 9
		add_child(label)
		var at: Vector3 = bounds.get_center() + Vector3.UP * (bounds.size.y * 0.5 + LABEL_LIFT)
		label.global_position = at
		_markers.append(label)
		_follows.append([label, target, target.global_transform.affine_inverse() * at])


func _box_marker() -> AABB:
	var shape_node: CollisionShape3D = target as CollisionShape3D
	if shape_node == null:
		for node in target.find_children("*", "CollisionShape3D", true, false):
			shape_node = node
			break
	if shape_node == null or not shape_node.shape is BoxShape3D:
		return AABB(target.global_position - Vector3.ONE * 0.1, Vector3.ONE * 0.2)
	var size: Vector3 = (shape_node.shape as BoxShape3D).size
	var box := MeshInstance3D.new()
	box.name = "GuidanceBox"
	var mesh := BoxMesh.new()
	mesh.size = size + Vector3.ONE * 0.02
	box.mesh = mesh
	box.material_override = _material
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(box)
	box.global_transform = shape_node.global_transform
	_markers.append(box)
	_follows.append([box, shape_node, null])
	return shape_node.global_transform * AABB(-size * 0.5, size)


func _clear_highlight() -> void:
	for mesh in _highlighted:
		if is_instance_valid(mesh) and mesh.material_overlay == _material:
			mesh.material_overlay = null
	_highlighted.clear()
	for marker in _markers:
		if is_instance_valid(marker):
			marker.free()
	_markers.clear()
	_follows.clear()


func _follow_markers() -> void:
	for item in _follows:
		var marker: Node3D = item[0]
		var node: Node3D = item[1]
		if is_instance_valid(marker) and is_instance_valid(node):
			if item[2] == null:
				marker.global_transform = node.global_transform
			else:
				marker.global_position = node.global_transform * (item[2] as Vector3)


func highlighted_meshes() -> Array[GeometryInstance3D]:
	return _highlighted


func _exit_tree() -> void:
	_clear_highlight()
