class_name Workshop

extends Node3D

## The lunar workshop (tools/blender/WORKSHOP_KIT.md): a rover service bay with the charging
## pad and the parts rack, and an operator area with the mission console, behind a glazed
## partition. One scene for every level (the Moon and the test level); the level places it and
## the rover it serves.
##
## Everything is built at _ready from the kit: ws_layout.glb says where each part GLB goes
## (place_<part>_NN empties) and where the lights, triggers, spawn and anchors are. Kit axes:
## the bay door faces -Z (the kit's +Y), the floor top is at y 0.
##
## - Console (E): drive `rover`. The player is put at the console first, so leaving the rover
##   (Esc) brings the view back there.
## - Bay door: opens while a rover is being driven inside or near it, closes 3 s after the
##   doorway is clear; the panel beside it (E) opens and closes it by hand.
## - Pressure curtain (`airlock_barrier`): an invisible wall in the bay door on collision
##   layer 8, which only the player collides with. The Moon keeps the player inside; the test
##   level turns it off.
## - Personnel door: slides open for the player; locked (red) while the bay door is open and the
##   curtain is on.
## - Rack: the rover parts on their slots, labelled; "Restock rack" lays them out again.
## - Astronaut (tools/blender/ASTRONAUT_KIT.md): an empty suit on its stand in the operator area,
##   and the operator seated at the console on a stool, shown only while the console drives the
##   rover (the rover's camera can see them through the partition window). Both are static meshes.
## - Decor (tools/blender/DECOR_KIT.md, `decor_enabled`): set dressing inside and around the
##   workshop, built by WorkshopDecor as the child "Decor". Scenery only: it can't be picked up,
##   used or scanned.

const KIT_DIR: String = "res://res/models/workshop_kit/"
const ASTRONAUT_DIR: String = "res://res/models/astronaut_kit/"
const PLAYER_BARRIER_LAYER: int = 8
## Footprint half sizes (m) and interior clear height
const HALF_X: float = 5.0
const HALF_Z: float = 4.0
const CEILING: float = 3.0
const DOOR_OPEN_ANGLE: float = -90.0

## The rover this workshop serves: the console drives it, the pad charges it
@export var rover: Robot
## The pressure curtain in the bay door (the player can't walk out)
@export var airlock_barrier: bool = true
## Put the rover parts on the rack
@export var stock_rack: bool = true
## Dress the workshop (DECOR_KIT.md): clutter, safety gear, crew things, history cards, exterior
@export var decor_enabled: bool = true
@export var door_open_time: float = 2.5
@export var door_close_delay: float = 3.0
@export var personnel_door_time: float = 0.8

## The bay door, 0 closed .. 1 open
var door_open: float = 0.0
var personnel_open: float = 0.0
var pad: ChargingPad = null
var rack_stock: Node3D = null
var console_trigger: InteractTrigger = null
var door_panel_trigger: InteractTrigger = null
var restock_trigger: InteractTrigger = null
## The seated operator and the stool at the console, visible while the console drives the rover
var operator: Node3D = null
## The empty suit on its stand (its helmet on the stand's shelf)
var suit_on_stand: Node3D = null
## The set dressing (null when `decor_enabled` is off)
var decor: WorkshopDecor = null
var curtain: StaticBody3D = null
## Layout empties and part empties by name (positions in this node's frame)
var anchors: Dictionary = {}
var labels: Array[Label3D] = []

var _door_target: float = 0.0
var _door_manual: bool = false
var _door_clear_time: float = 0.0
var _door_leaf: Node3D = null
var _door_light: GeometryInstance3D = null
var _personnel_leaf: Node3D = null
var _personnel_rest: Vector3 = Vector3.ZERO
var _personnel_light: GeometryInstance3D = null
var _door_area: Area3D = null
# Casts the closed door's shadow over its 25 mm clearance gaps, which otherwise let thin lines of
# sunlight into the bay; hidden while the door moves or is open
var _door_shadow_seal: MeshInstance3D = null
# The doors' colliders (AnimatableBody3D) and where they sit on their leaves. An AnimatableBody3D
# only follows its own transform, not its parent's, so they are top-level and placed every frame
var _door_bodies: Array = []
var _personnel_area: Area3D = null
var _stock := PartsStock.new()
var _screen_lines: Array[Label] = []
var _screen_time: float = 0.0
var _time: float = 0.0
var _door_material := StandardMaterial3D.new()
var _personnel_material := StandardMaterial3D.new()

# Rack slots (WORKSHOP_KIT.md 6.3): slot -> [part scene, properties, rest rotation]
const WHEEL: String = "res://src/robot/socket/wheel_part.tscn"
const HIGH_GRIP: Dictionary = {"grip": 1.3, "catalog_id": "wheel_high_grip", "tint": Color(0.62, 0.34, 0.12, 1.0)}
const SLOTS: Dictionary = {
	1: [WHEEL, {}, "wheel"], 2: [WHEEL, {}, "wheel"], 3: [WHEEL, {}, "wheel"],
	4: [WHEEL, {}, "wheel"], 5: [WHEEL, {}, "wheel"], 6: [WHEEL, {}, "wheel"],
	7: [WHEEL, HIGH_GRIP, "wheel"], 8: [WHEEL, HIGH_GRIP, "wheel"], 9: [WHEEL, HIGH_GRIP, "wheel"],
	10: [WHEEL, HIGH_GRIP, "wheel"],
	11: ["res://src/robot/socket/motor_part.tscn", {}, ""],
	12: ["res://src/robot/socket/battery_part.tscn", {}, "side"],
	13: ["res://src/robot/socket/mast_head_part.tscn", {}, ""],
	14: ["res://src/robot/socket/arm_tool_part.tscn", {}, ""],
	15: ["res://src/robot/socket/antenna_part.tscn", {}, ""],
	16: ["res://src/robot/socket/battery_light_part.tscn", {}, "side"],
	# The diagnostic cartridge (IRIS_KIT.md 4), lying flat on the top shelf
	17: ["res://src/robot/socket/cartridge_part.tscn", {}, ""],
}
# Wheels rest on the cradle rails' inner edges (0.08 m off the wheel's centre, 0.04 m tall)
const WHEEL_SEAT: float = 0.04 + 0.1269 - 0.15 + 0.003
const PART_LIFT: float = 0.005
# Rack labels: label -> [text, plate width (m)]
const LABELS: Dictionary = {
	1: ["WHEELS", 2.23], 2: ["HIGH-GRIP WHEELS", 1.36], 3: ["MOTOR", 0.44], 4: ["BATTERY", 0.54],
	5: ["MAST CAMERA", 0.66], 6: ["TOOL TURRET", 0.55], 7: ["ANTENNA", 0.56], 8: ["SPARE", 0.55],
	9: ["CARTRIDGES", 2.38],
}
## Label text cap height (m) and the least it may shrink to while fitting its plate
const LABEL_CAP: float = 0.065
const LABEL_CAP_MIN: float = 0.050
const LABEL_FONT_SIZE: int = 96
## Cap height of the default font as a fraction of its size
const CAP_RATIO: float = 0.714


func _ready() -> void:
	add_to_group(&"workshop")
	_build_parts()
	_build_lights()
	_build_pad()
	_build_doors()
	_build_triggers()
	_build_labels()
	_build_console_screen()
	_build_astronauts()
	if decor_enabled:
		decor = WorkshopDecor.new()
		decor.name = "Decor"
		add_child(decor)
	if stock_rack:
		_build_rack_stock()


# --- Building ------------------------------------------------------------------------------

func _build_parts() -> void:
	var holder := Node3D.new()
	holder.name = "Parts"
	add_child(holder)
	var layout: Node = load(KIT_DIR + "ws_layout.glb").instantiate()
	var regex := RegEx.create_from_string("^place_(.+)_(\\d+)$")
	var empties: Array = layout.find_children("*", "Node3D", true, false)
	for node in empties:
		var match := regex.search(String(node.name))
		if match:
			var part: Node3D = load(KIT_DIR + match.get_string(1) + ".glb").instantiate()
			part.name = String(node.name).trim_prefix("place_")
			part.transform = _in_layout(node)
			holder.add_child(part)
		elif String(node.name) != "ws_layout":
			anchors[String(node.name)] = _in_layout(node).origin
	layout.free()
	# Empties inside the parts (dock_point, slot_NN, trigger_console, ...)
	for node in holder.find_children("*", "Node3D", true, false):
		var n := String(node.name)
		if (n.begins_with("slot_") or n.begins_with("label_") or n.begins_with("trigger_") or n.begins_with("anchor_")
				or n.begins_with("pivot_") or n == "dock_point") and node.get_child_count() == 0 and not node is VisualInstance3D:
			if n == "label_sign":
				continue
			anchors[n] = to_local(node.global_position)


# A layout empty's transform relative to the layout's root
func _in_layout(node: Node3D) -> Transform3D:
	var result: Transform3D = node.transform
	var parent: Node = node.get_parent()
	while parent is Node3D and parent.get_parent() != null:
		result = (parent as Node3D).transform * result
		parent = parent.get_parent()
	return result


func _part(name: String) -> Node3D:
	return get_node("Parts/" + name) as Node3D


func _build_lights() -> void:
	var key := SpotLight3D.new()
	key.name = "BayKeyLight"
	key.position = anchors["light_bay_key"]
	key.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	key.spot_angle = 40.0
	key.spot_angle_attenuation = 0.6
	key.spot_range = 5.5
	key.light_energy = 6.0
	key.light_color = Color(1.0, 0.96, 0.9)
	key.shadow_enabled = true
	# The ground under the floor can't be seen from in here: leave the terrain's big chunks and the
	# rock field (one multimesh across the whole play area: 1.6 M triangles in this light's shadow
	# map) out of its shadow casters (MoonTerrain.RENDER_LAYER)
	key.shadow_caster_mask = 0xFFFFF & ~(1 << (MoonTerrain.RENDER_LAYER - 1))
	add_child(key)
	for item in [["RackLamp", "light_rack", Color(1.0, 0.72, 0.38), 2.2], ["DoorLamp", "light_door", Color(1.0, 0.72, 0.38), 1.6],
			["OperatorLamp", "light_operator", Color(1.0, 0.88, 0.72), 1.4]]:
		var omni := OmniLight3D.new()
		omni.name = item[0]
		omni.position = anchors[item[1]]
		omni.omni_range = 4.5
		omni.light_color = item[2]
		omni.light_energy = item[3]
		add_child(omni)
	var flood := SpotLight3D.new()
	flood.name = "ExteriorFlood"
	flood.position = anchors["light_exterior"]
	flood.rotation_degrees = Vector3(-30.0, 0.0, 0.0)
	flood.spot_angle = 45.0
	flood.spot_range = 12.0
	flood.light_energy = 2.0
	flood.light_color = Color(1.0, 0.85, 0.65)
	add_child(flood)
	var probe := ReflectionProbe.new()
	probe.name = "InteriorProbe"
	probe.position = Vector3(0.0, CEILING / 2.0, 0.0)
	probe.size = Vector3(2.0 * HALF_X - 0.4, CEILING, 2.0 * HALF_Z - 0.4)
	probe.interior = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.62, 0.6, 0.57)
	probe.ambient_color_energy = 0.75
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(probe)


func _build_pad() -> void:
	var pad_part := _part("ws_pad_01")
	pad = ChargingPad.new()
	pad.name = "ChargingPad"
	pad.transform = pad_part.transform
	pad.probe = pad_part.get_node("ws_pad/charge_probe")
	pad.status_meshes.assign([pad_part.get_node("ws_pad/pad_status_light"),
							  _part("ws_charger_01").get_node("ws_charger/charger_status_light")])
	pad.charger_trigger = _make_trigger("ChargerTrigger", anchors["trigger_charger"], Vector3(0.6, 1.2, 1.0), "Charger")
	add_child(pad)


func _build_doors() -> void:
	var door_part := _part("ws_wall_bay_door_01")
	_door_leaf = door_part.get_node("ws_wall_bay_door/bay_door")
	_door_light = door_part.get_node("ws_wall_bay_door/bay_door_light")
	var personnel_part := _part("ws_partition_door_01")
	_personnel_leaf = personnel_part.get_node("ws_partition_door/personnel_door")
	_personnel_rest = _personnel_leaf.position
	_personnel_light = personnel_part.get_node("ws_partition_door/personnel_door_light")
	for item in [[_door_material, _door_light], [_personnel_material, _personnel_light]]:
		item[0].shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		item[0].emission_enabled = true
		item[1].material_override = item[0]
	for leaf in [_door_leaf, _personnel_leaf]:
		for body in leaf.get_children():
			if body is AnimatableBody3D:
				var offset: Transform3D = body.transform
				body.top_level = true
				body.global_transform = leaf.global_transform * offset
				_door_bodies.append([body, leaf, offset])
	_door_shadow_seal = MeshInstance3D.new()
	_door_shadow_seal.name = "DoorShadowSeal"
	var seal := BoxMesh.new()
	seal.size = Vector3(4.2, 2.6, 0.02)
	_door_shadow_seal.mesh = seal
	_door_shadow_seal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_door_shadow_seal.position = Vector3(-1.0, 1.3, -3.89)
	add_child(_door_shadow_seal)
	_door_area = _make_area("DoorArea", anchors["trigger_door_auto"], Vector3(6.0, 2.0, 8.0), 2 | 4)
	_personnel_area = _make_area("PersonnelArea", anchors["trigger_personnel"], Vector3(2.0, 2.0, 1.2), 2)
	if airlock_barrier:
		curtain = StaticBody3D.new()
		curtain.name = "PressureCurtain"
		curtain.collision_layer = 1 << (PLAYER_BARRIER_LAYER - 1)
		curtain.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(4.0, 2.5, 0.1)
		shape.shape = box
		curtain.add_child(shape)
		curtain.position = Vector3(-1.0, 1.25, -3.85)
		add_child(curtain)


func _build_triggers() -> void:
	console_trigger = _make_trigger("ConsoleTrigger", anchors["trigger_console"], Vector3(0.6, 0.6, 1.2),
			'Press "E" to drive the rover')
	console_trigger.interacted.connect(_on_console_interacted)
	door_panel_trigger = _make_trigger("BayDoorTrigger", anchors["trigger_bay_door"], Vector3(0.4, 0.5, 0.2),
			'Press "E" to open the bay door')
	door_panel_trigger.interacted.connect(_on_door_panel_interacted)
	restock_trigger = _make_trigger("RestockTrigger", anchors["trigger_restock"], Vector3(0.2, 0.3, 0.2),
			'Press "E" to restock the rack')
	restock_trigger.interacted.connect(_on_restock_interacted)


func _make_trigger(node_name: String, at: Vector3, size: Vector3, tooltip: String) -> InteractTrigger:
	var trigger := InteractTrigger.new()
	trigger.name = node_name
	trigger.tooltip = tooltip
	trigger.collision_layer = 16
	trigger.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	trigger.add_child(shape)
	trigger.position = at
	add_child(trigger)
	return trigger


func _make_area(node_name: String, at: Vector3, size: Vector3, mask: int) -> Area3D:
	var area := Area3D.new()
	area.name = node_name
	area.collision_layer = 0
	area.collision_mask = mask
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	area.add_child(shape)
	area.position = at
	add_child(area)
	return area


func _build_labels() -> void:
	var font: Font = ThemeDB.fallback_font
	for n in LABELS:
		var key := "label_%02d" % n
		if not anchors.has(key):
			continue
		var text: String = LABELS[n][0]
		var plate: float = LABELS[n][1]
		var label := Label3D.new()
		label.name = "Label%02d" % n
		label.text = text
		label.font_size = LABEL_FONT_SIZE
		label.outline_size = 0
		label.modulate = Color(0.11, 0.115, 0.125)
		label.double_sided = false
		var pixel: float = LABEL_CAP / (CAP_RATIO * LABEL_FONT_SIZE)
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE).x
		var room: float = plate - 0.04
		if width * pixel > room:
			pixel = maxf(room / width, LABEL_CAP_MIN / (CAP_RATIO * LABEL_FONT_SIZE))
		label.pixel_size = pixel
		# The rack faces -Z: turn the label to face it, 2 mm off the plate
		label.rotation = Vector3(0.0, PI, 0.0)
		label.position = anchors[key] + Vector3(0.0, 0.0, -0.002)
		add_child(label)
		labels.append(label)
	# The sign over the bay door
	var sign: Node3D = _part("ws_door_sign_01").find_child("label_sign", true, false)
	if sign:
		var door_label := Label3D.new()
		door_label.name = "DoorSignLabel"
		door_label.text = "SERVICE BAY"
		door_label.font_size = LABEL_FONT_SIZE
		door_label.pixel_size = 0.13 / (CAP_RATIO * LABEL_FONT_SIZE)
		door_label.outline_size = 0
		door_label.modulate = Color(0.11, 0.115, 0.125)
		door_label.double_sided = false
		door_label.position = to_local(sign.global_position) + Vector3(0.0, 0.0, -0.002)
		door_label.rotation = Vector3(0.0, PI, 0.0)
		add_child(door_label)


## The width (m) a rack label's text takes, for the label-fit check
func label_width(label: Label3D) -> float:
	return ThemeDB.fallback_font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x * label.pixel_size


## The cap height (m) a label's text is drawn at
func label_cap_height(label: Label3D) -> float:
	return label.pixel_size * label.font_size * CAP_RATIO


func _build_console_screen() -> void:
	var screen: GeometryInstance3D = _part("ws_console_01").get_node("ws_console/console_screen")
	var viewport := SubViewport.new()
	viewport.name = "ConsoleScreen"
	viewport.size = Vector2i(640, 360)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.disable_3d = true
	var background := ColorRect.new()
	background.color = Color(0.04, 0.07, 0.08)
	background.size = Vector2(640, 360)
	viewport.add_child(background)
	var box := VBoxContainer.new()
	box.position = Vector2(32, 26)
	box.size = Vector2(576, 308)
	box.add_theme_constant_override("separation", 14)
	viewport.add_child(box)
	for item in [["SERVICE BAY CONSOLE", 30, Color(0.95, 0.68, 0.25)], ["", 34, Color(0.75, 0.95, 0.85)],
			["", 34, Color(0.75, 0.95, 0.85)], ["", 34, Color(0.75, 0.95, 0.85)], ["E  DRIVE THE ROVER", 30, Color(0.95, 0.68, 0.25)]]:
		var line := Label.new()
		line.text = item[0]
		line.add_theme_font_size_override("font_size", item[1])
		line.add_theme_color_override("font_color", item[2])
		box.add_child(line)
		_screen_lines.append(line)
	add_child(viewport)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = viewport.get_texture()
	screen.material_override = material
	_update_screen()


func _update_screen() -> void:
	if _screen_lines.is_empty():
		return
	var state := "NO ROVER"
	var battery := "BATTERY  --"
	if is_instance_valid(rover):
		if pad and pad.rover == rover:
			state = "ROVER  ON THE PAD: " + pad.get_status_text().to_upper()
		elif _is_inside(rover.global_position):
			state = "ROVER  IN THE BAY"
		else:
			state = "ROVER  OUT, %d M AWAY" % roundi(rover.global_position.distance_to(global_position))
		if rover.battery:
			battery = "BATTERY  %d %%" % floori(rover.battery.get_charge_fraction() * 100.0)
		else:
			battery = "BATTERY  NONE MOUNTED"
	_screen_lines[1].text = state
	_screen_lines[2].text = battery
	_screen_lines[3].text = "BAY DOOR  " + ("OPEN" if door_open >= 1.0 else "CLOSED" if door_open <= 0.0 else "MOVING")


func _build_rack_stock() -> void:
	rack_stock = Node3D.new()
	rack_stock.name = "RackStock"
	add_child(rack_stock)
	for n in SLOTS:
		var key := "slot_%02d" % n
		if not anchors.has(key):
			continue
		var entry: Array = SLOTS[n]
		var part: HotswapPart = load(entry[0]).instantiate()
		for property in entry[1]:
			part.set(property, entry[1][property])
		var basis := Basis.IDENTITY
		if entry[2] == "wheel":
			basis = Basis(Vector3.UP, PI / 2.0)          # axle along the rack's depth
		elif entry[2] == "side":
			# On its side, then turned so its 0.355 m side runs across the shelf
			basis = Basis(Vector3.UP, PI / 2.0) * Basis(Vector3(0.0, 0.0, 1.0), -PI / 2.0)
		var box := _part_aabb(part, basis)
		var lift: float = WHEEL_SEAT if entry[2] == "wheel" else PART_LIFT
		var slot: Vector3 = anchors[key]
		var origin := Vector3(slot.x - box.get_center().x, slot.y + lift - box.position.y, slot.z - box.get_center().z)
		part.transform = Transform3D(basis, origin)
		part.name = "Slot%02d" % n
		rack_stock.add_child(part)
	_stock.record(rack_stock)


func _build_astronauts() -> void:
	# The GLBs are modelled in the kit's frame, so they go at their anchors unrotated
	suit_on_stand = load(ASTRONAUT_DIR + "astronaut_rack.glb").instantiate()
	suit_on_stand.name = "SuitOnStand"
	suit_on_stand.position = anchors["anchor_suit"]
	add_child(suit_on_stand)
	operator = Node3D.new()
	operator.name = "Operator"
	operator.position = anchors["anchor_seat"]
	add_child(operator)
	operator.add_child(load(KIT_DIR + "ws_stool.glb").instantiate())
	operator.add_child(load(ASTRONAUT_DIR + "astronaut_seated.glb").instantiate())
	# The player's camera (and helmet light) stays at the console while driving, inside the seated
	# helmet: the operator mustn't shadow it
	for mesh in operator.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	operator.visible = false
	GameState.state_changed.connect(_on_game_state_changed)


func _on_game_state_changed(_old_state, new_state) -> void:
	# The operator stays seated through a pause; leaving the rover (or the level) stands them up
	if new_state != GameState.State.IN_GAME_ROBOT and new_state != GameState.State.PAUSED \
			and new_state != GameState.State.CREDITS:
		operator.visible = false


# A part's mesh bounds with `basis` applied, relative to its origin (before it is in the tree)
func _part_aabb(part: Node3D, basis: Basis) -> AABB:
	var result := AABB()
	var first := true
	for mesh in part.find_children("*", "MeshInstance3D", true, false):
		if not mesh.visible:
			continue
		var t := Transform3D(basis, Vector3.ZERO) * _transform_in(part, mesh)
		var box: AABB = t * (mesh as MeshInstance3D).get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


func _transform_in(root: Node3D, node: Node3D) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent()
	while parent != root and parent is Node3D:
		result = (parent as Node3D).transform * result
		parent = parent.get_parent()
	return result


# --- Gameplay ------------------------------------------------------------------------------

## Shows or hides the set dressing (its colliders stay), for comparing its frame-rate cost
func set_decor_visible(shown: bool) -> void:
	if decor:
		decor.visible = shown


## Where the docked rover's origin goes, facing out of the bay door
func get_dock_transform() -> Transform3D:
	return Transform3D(global_basis, to_global(anchors["dock_point"]))


func _is_inside(world_point: Vector3) -> bool:
	var p := to_local(world_point)
	return absf(p.x) < HALF_X and absf(p.z) < HALF_Z


func _on_console_interacted(player: Player) -> void:
	if not is_instance_valid(rover) or GameState.state != GameState.State.IN_GAME_PLAYER:
		return
	# Stand the player at the console, facing the screen, before handing over: leaving the rover
	# brings the view back here
	var stand := to_global(anchors["anchor_operator"])
	player.global_position = Vector3(stand.x, player.global_position.y, stand.z)
	player.linear_velocity = Vector3.ZERO
	var look: Vector3 = to_global(anchors["anchor_prompt_console"]) - stand
	var world_yaw: float = atan2(-look.x, -look.z)
	# Player moves along its pivot's own basis, so the azimuth is the world yaw (levels spawn it
	# unrotated)
	if player.controller:
		player.controller.camera_azimuth = world_yaw
	GameState.drive(rover)
	operator.visible = true


func _on_door_panel_interacted(_player: Player) -> void:
	if _door_target > 0.5:
		if _doorway_occupied():
			return
		_door_manual = false
		_door_target = 0.0
	else:
		_door_manual = true
		_door_target = 1.0


func _on_restock_interacted(_player: Player) -> void:
	if rack_stock:
		_stock.restock(rack_stock, get_parent())


func _doorway_occupied() -> bool:
	for body in _door_area.get_overlapping_bodies():
		if body is Robot:
			return true
	return false


func _physics_process(delta: float) -> void:
	_time += delta
	_update_bay_door(delta)
	_update_personnel_door(delta)
	for item in _door_bodies:
		item[0].global_transform = item[1].global_transform * item[2]
	_screen_time += delta
	if _screen_time >= 0.25:
		_screen_time = 0.0
		_update_screen()


func _update_bay_door(delta: float) -> void:
	var driving: bool = GameState.state == GameState.State.IN_GAME_ROBOT
	var wanted := false
	for body in _door_area.get_overlapping_bodies():
		if body is Robot and driving:
			wanted = true
		elif body is Player and not airlock_barrier:
			wanted = true                           # on foot in the test level: walk in and out
	if driving and is_instance_valid(GameState.robot) and _is_inside(GameState.robot.global_position):
		wanted = true
	if wanted:
		_door_target = 1.0
		_door_clear_time = 0.0
	elif _door_target > 0.5 and not _door_manual:
		if _doorway_occupied():
			_door_clear_time = 0.0
		else:
			_door_clear_time += delta
			if _door_clear_time >= door_close_delay:
				_door_target = 0.0
	door_open = move_toward(door_open, _door_target, delta / door_open_time)
	_door_leaf.rotation_degrees = Vector3(DOOR_OPEN_ANGLE * smoothstep(0.0, 1.0, door_open), 0.0, 0.0)
	_door_shadow_seal.visible = door_open <= 0.0
	var moving: bool = door_open > 0.0 and door_open < 1.0
	var color := Color(0.3, 1.0, 0.4) if door_open <= 0.0 else Color(1.0, 0.65, 0.15)
	var level: float = (1.0 if fmod(_time, 0.5) < 0.25 else 0.2) if moving else 1.0
	_door_material.albedo_color = color * level
	_door_material.emission = color
	_door_material.emission_energy_multiplier = 2.0 * level
	door_panel_trigger.tooltip = 'Press "E" to %s the bay door' % ("close" if _door_target > 0.5 else "open")


## The personnel door is locked while the bay is open to the outside (the curtain is on)
func is_personnel_door_locked() -> bool:
	return airlock_barrier and door_open > 0.0


func _update_personnel_door(delta: float) -> void:
	var player_near := false
	for body in _personnel_area.get_overlapping_bodies():
		if body is Player:
			player_near = true
	var locked := is_personnel_door_locked()
	var target: float = 1.0 if player_near and not locked else 0.0
	personnel_open = move_toward(personnel_open, target, delta / personnel_door_time)
	_personnel_leaf.position = _personnel_rest + Vector3(0.0, 0.0, smoothstep(0.0, 1.0, personnel_open))
	var color := Color(1.0, 0.15, 0.1) if locked else Color(0.3, 1.0, 0.4)
	_personnel_material.albedo_color = color
	_personnel_material.emission = color
	_personnel_material.emission_energy_multiplier = 2.0
