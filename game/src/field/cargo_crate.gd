class_name CargoCrate

extends Node3D

## The M2 delivery crate (workflow.md "Crate contract"): it holds the parts of every delivered crate
## item (CargoPlan.crate_parts(), today the radio-power module). Fahd places it near the pad;
## while a node is in group `cargo_crate` the workshop leaves the module's fallback rack slot empty.
##
## Before the delivery the crate isn't there (hidden, no collision). When CampaignState sets
## `cargo_delivered` it appears, lays out its parts inside and opens its lid. Loaded with the
## delivery already done, it starts open and filled. A part already out of the crate (mounted on
## Kite, or seated in IRIS's module bay) isn't laid out again, so a reload never shows two.
##
## Built from boxes: an open-topped body (floor and four walls, one static collider each) and a lid
## hinged on the back top edge, in the decor crate's (dc_crate) materials. Origin: the middle of the
## floor's underside; the front (label) faces +Z. Guidance finds it as `group:cargo_crate` and glows
## `highlight_node` (the body and lid, not the parts inside).

signal opened
signal filled(parts: Array)

const DECOR_CRATE: String = "res://res/models/decor_kit/dc_crate.glb"
## Outer size (m): wide enough for the 0.28 m module lying flat, with room for a hand
const SIZE := Vector3(0.70, 0.36, 0.46)
const WALL: float = 0.02
const LID_OPEN_DEG: float = -105.0
const LID_TIME: float = 1.4
## Parts are laid out this far above the floor and settle onto it
const DROP: float = 0.02
const LABEL_INK := Color(0.11, 0.115, 0.125)

## What Guidance lights up: the crate's body and lid (set in _ready)
@export var highlight_node: Node3D
var is_open: bool = false
## The parts laid out in the crate (they stay listed after they're taken out)
var contents: Array[HotswapPart] = []
var _body: StaticBody3D = null
var _lid_pivot: Node3D = null
var _label: Label3D = null
var _parts_root: Node3D = null
var _filled: bool = false


func _ready() -> void:
	add_to_group(CargoPlan.CRATE_GROUP)
	_build()
	_parts_root = Node3D.new()
	_parts_root.name = "Contents"
	add_child(_parts_root)
	CampaignState.flag_changed.connect(_on_flag_changed)
	if CargoPlan.is_delivered():
		_appear(true)
		# Wait for MissionDirector to put a saved loadout back on Kite (it waits a physics frame),
		# so parts already mounted are seen and skipped
		await get_tree().physics_frame
		await get_tree().physics_frame
		fill()
	else:
		_set_present(false)


func _on_flag_changed(flag: String, value: bool) -> void:
	if flag != CargoPlan.DELIVERED_FLAG or not value or _filled:
		return
	_appear(false)
	fill()


## Lays out the delivered parts that aren't already out of the crate; once only
func fill() -> void:
	if _filled:
		return
	_filled = true
	var out: Dictionary = _parts_already_out()
	var paths: PackedStringArray = CargoPlan.crate_parts()
	var parts: Array = []
	for path in paths:
		var part := (load(path) as PackedScene).instantiate() as HotswapPart
		var id: String = part.get_catalog_id()
		if int(out.get(id, 0)) > 0:
			out[id] = int(out[id]) - 1
			part.free()
			continue
		parts.append(part)
	for i in parts.size():
		var part: HotswapPart = parts[i]
		_parts_root.add_child(part)
		# In a row across the crate's width, lying as they do on the rack
		var across: float = (SIZE.x - 2.0 * WALL) * (float(i) + 0.5) / float(parts.size()) - (SIZE.x / 2.0 - WALL)
		part.transform = Transform3D(Basis.IDENTITY, Vector3(across, WALL + DROP, 0.0))
		contents.append(part)
	filled.emit(parts)


## How many of each catalog id are already out of the crate: mounted on a rover or seated in a
## module bay (IrisModuleCradle)
func _parts_already_out() -> Dictionary:
	var out: Dictionary = {}
	var level: Node = SceneLoader.current_scene if is_instance_valid(SceneLoader.current_scene) else get_parent()
	if level == null:
		return out
	for node in level.find_children("*", "HotswapPart", true, false):
		var part := node as HotswapPart
		if _parts_root.is_ancestor_of(part):
			continue
		var bay: Node = part.get_parent()
		if part.is_mounted() or (bay != null and bay.is_in_group(&"iris_module_cradle")):
			var id: String = part.get_catalog_id()
			out[id] = int(out.get(id, 0)) + 1
	return out


func _appear(instant: bool) -> void:
	_set_present(true)
	_update_label()
	open(instant)


func open(instant: bool = false) -> void:
	if is_open:
		return
	is_open = true
	if instant:
		_lid_pivot.rotation_degrees.x = LID_OPEN_DEG
	else:
		var tween := create_tween()
		tween.tween_property(_lid_pivot, "rotation_degrees:x", LID_OPEN_DEG, LID_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	opened.emit()


func is_present() -> bool:
	return visible


func _set_present(present: bool) -> void:
	visible = present
	for body in find_children("*", "StaticBody3D", true, false):
		(body as StaticBody3D).collision_layer = 1 if present else 0


func _update_label() -> void:
	var service := CargoPlan.service(CargoPlan.delivered_service())
	var lines: PackedStringArray = ["DELIVERY - IRIS SPARES"]
	if not service.is_empty():
		lines.append(str(service.get("name", "")).to_upper())
	_label.text = "\n".join(lines)


func _build() -> void:
	var materials: Array[Material] = _decor_materials()
	var body_material: Material = materials[0] if materials.size() > 0 else null
	var lid_material: Material = materials[-1] if materials.size() > 0 else null
	var look := Node3D.new()
	look.name = "Look"
	add_child(look)
	highlight_node = look
	_body = StaticBody3D.new()
	_body.name = "Body"
	_body.collision_mask = 0
	look.add_child(_body)
	var half := SIZE / 2.0
	var inner_h: float = SIZE.y - WALL
	# Floor, front and back walls (full width), left and right walls (between them)
	_box(_body, "Floor", Vector3(SIZE.x, WALL, SIZE.z), Vector3(0.0, WALL / 2.0, 0.0), body_material)
	_box(_body, "Front", Vector3(SIZE.x, inner_h, WALL), Vector3(0.0, WALL + inner_h / 2.0, half.z - WALL / 2.0), body_material)
	_box(_body, "Back", Vector3(SIZE.x, inner_h, WALL), Vector3(0.0, WALL + inner_h / 2.0, -half.z + WALL / 2.0), body_material)
	var side := Vector3(WALL, inner_h, SIZE.z - 2.0 * WALL)
	_box(_body, "Left", side, Vector3(-half.x + WALL / 2.0, WALL + inner_h / 2.0, 0.0), body_material)
	_box(_body, "Right", side, Vector3(half.x - WALL / 2.0, WALL + inner_h / 2.0, 0.0), body_material)
	# The lid, hinged on the back top edge; closed it lies on the walls
	_lid_pivot = Node3D.new()
	_lid_pivot.name = "LidHinge"
	_lid_pivot.position = Vector3(0.0, SIZE.y, -half.z)
	look.add_child(_lid_pivot)
	var lid := StaticBody3D.new()
	lid.name = "Lid"
	lid.collision_mask = 0
	_lid_pivot.add_child(lid)
	_box(lid, "Lid", Vector3(SIZE.x + 0.01, WALL, SIZE.z + 0.01), Vector3(0.0, WALL / 2.0, half.z), lid_material)
	# The delivery label on the front
	_label = Label3D.new()
	_label.name = "Label"
	_label.font_size = 48
	_label.pixel_size = 0.0009
	_label.outline_size = 0
	_label.modulate = LABEL_INK
	_label.double_sided = false
	_label.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_label.position = Vector3(0.0, SIZE.y * 0.6, half.z + 0.002)
	add_child(_label)


func _box(parent: Node3D, box_name: String, size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = box_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
	var shape := CollisionShape3D.new()
	shape.name = box_name + "Shape"
	var collider := BoxShape3D.new()
	collider.size = size
	shape.shape = collider
	shape.position = at
	parent.add_child(shape)


## The decor crate's surface materials, so this crate matches the workshop's
func _decor_materials() -> Array[Material]:
	var found: Array[Material] = []
	var scene := load(DECOR_CRATE) as PackedScene
	if scene == null:
		return found
	var model: Node = scene.instantiate()
	var meshes: Array[Node] = model.find_children("*", "MeshInstance3D", true, false)
	var mesh: MeshInstance3D = meshes[0] as MeshInstance3D if not meshes.is_empty() else null
	if mesh and mesh.mesh:
		for i in mesh.mesh.get_surface_count():
			var material: Material = mesh.get_active_material(i)
			if material:
				found.append(material)
	model.free()
	return found
