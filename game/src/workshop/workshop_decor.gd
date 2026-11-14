class_name WorkshopDecor

extends Node3D

## The workshop's set dressing (tools/blender/DECOR_KIT.md): work clutter, life support and
## safety, signs of the crew, service notes, two NASA history cards, and a little exterior
## dressing with tyre tracks on the apron. Built by `Workshop` (`decor_enabled`) as its child
## "Decor", in the workshop's frame (kit axes: the bay door faces -Z, the floor top at y 0).
##
## Decor is scenery only: static meshes and, where a piece stands on the floor, one StaticBody3D
## box on layer 1 (mask 0). Nothing here can be picked up, used or scanned, so the crosshair and
## the part tooltip never react to it.
##
## - Interior: dc_interior.glb, every interior piece joined into one mesh (one surface per
##   material), with the history cards' photo quads apart (card_photo_<key>).
## - Exterior: each piece from its own GLB at its outside_* empty, rested on the ground (the
##   regolith under the apron isn't flat), and the cable built along path_cable_*.
## - Words: every text_<style>_<key> empty gets Label3Ds with the words from TEXTS_PATH, fitted
##   to the piece's paper or plate (never baked into a texture).
## - Tyre tracks: Decals along path_track*_*, projecting onto the Moon terrain's render layer
##   only, so they don't show in the test level and never paint a rover.

const KIT_DIR: String = "res://res/models/decor_kit/"
const TEXTS_PATH: String = "res://res/decor/decor_texts.json"
const PHOTOS: Dictionary = {
	"apollo12": "res://res/textures/decor/as12-49-7278.jpg",
	"surveyor3": "res://res/textures/decor/as12-48-7136.jpg",
}
const TRACK_ALBEDO: String = "res://res/textures/decor/track_albedo.png"
const TRACK_NORMAL: String = "res://res/textures/decor/track_normal.png"
## How dark each track reads (the way out is fresh, the others older)
const TRACK_STRENGTH: Dictionary = {"track1": 1.0, "track2": 0.7, "track3": 0.45}
const TRACK_WIDTH: float = 1.2
const TRACK_DEPTH: float = 0.6
## How far an exterior floor piece sits into the ground it rests on (m)
const GROUND_SINK: float = 0.01
const CABLE_RADIUS: float = 0.015
const INK := Color(0.11, 0.115, 0.125)
## Cap height of the default font as a fraction of its size (as Workshop's rack labels)
const CAP_RATIO: float = 0.714
const FONT_SIZE: int = 64

## Text boxes in the piece's frame (m): the room the words may take, their cap height, the least
## they may shrink to, and whether they wrap. Labels are looked up by their key's start.
const NOTE_PAPER := Vector2(0.21, 0.27)
const NOTE_MARGIN: float = 0.012
## The clip covers the paper's top 3 cm
const NOTE_CLIP: float = 0.035
const NOTE_TITLE_CAP: float = 0.016
const NOTE_BODY_CAP: float = 0.012
const NOTE_MIN_CAP: float = 0.008
const SIGN_BOX := Vector2(0.26, 0.17)
const SIGN_CAP: float = 0.018
const CARD_PLATE := Vector2(0.42, 0.22)
const CARD_MARGIN: float = 0.014
const CARD_TITLE_CAP: float = 0.015
const CARD_CAPTION_CAP: float = 0.0105
const CARD_CREDIT_CAP: float = 0.008
## Label plates: key start -> [width, height, cap, wraps]
const LABEL_PLATES: Dictionary = {
	"tool_chest": [0.17, 0.06, 0.030, false],
	"crate_": [0.27, 0.09, 0.035, true],
	"panels_tag": [0.11, 0.07, 0.014, true],
	"wheel_tag": [0.11, 0.07, 0.014, true],
	"plant": [0.22, 0.032, 0.018, false],
	"junction": [0.22, 0.05, 0.028, false],
	"fire_": [0.28, 0.09, 0.035, false],
}

## The texts file's data
var texts: Dictionary = {}
## Every Label3D made, with the box it must fit: [label, box size (m), wraps]
var labels: Array = []
## Text keys found in the layout (style_key)
var text_keys: Array[String] = []
var interior: Node3D = null
var exterior_pieces: Array[Node3D] = []
var cable: MeshInstance3D = null
var tracks: Array[Decal] = []
var _cable_points: Array[Vector3] = []


func _ready() -> void:
	var data: JSON = load(TEXTS_PATH)
	texts = data.data if data else {}
	interior = load(KIT_DIR + "dc_interior.glb").instantiate()
	interior.name = "Interior"
	add_child(interior)
	for key in PHOTOS:
		var photo := interior.find_child("card_photo_" + key, true, false) as MeshInstance3D
		if photo:
			var material := StandardMaterial3D.new()
			material.albedo_texture = load(PHOTOS[key])
			material.roughness = 0.9
			photo.material_override = material
	var layout: Node = load(KIT_DIR + "dc_layout.glb").instantiate()
	var tracks_points: Dictionary = {}
	for node in layout.find_children("*", "Node3D", true, false):
		var n := String(node.name)
		if n.begins_with("place_"):
			for text in node.get_children():
				_add_texts(self, _in_layout(text), String(text.name))
		elif n.begins_with("outside_"):
			_add_exterior(n, _in_layout(node), node)
		elif n.begins_with("path_cable_"):
			_cable_points.append(_in_layout(node).origin)
		elif n.begins_with("path_track"):
			var track := n.trim_prefix("path_").get_slice("_", 0)
			if not tracks_points.has(track):
				tracks_points[track] = []
			tracks_points[track].append(_in_layout(node).origin)
	layout.free()
	for track in tracks_points:
		_add_track(track, tracks_points[track])
	for body in find_children("*", "CollisionObject3D", true, false):
		(body as CollisionObject3D).collision_layer = 1
		(body as CollisionObject3D).collision_mask = 0
	# The ground needs the physics space: rest the exterior on it once the first frame has run
	_rest_on_ground.call_deferred()


# A layout empty's transform relative to the layout's root (in this node's frame)
func _in_layout(node: Node3D) -> Transform3D:
	var result: Transform3D = node.transform
	var parent: Node = node.get_parent()
	while parent is Node3D and parent.get_parent() != null:
		result = (parent as Node3D).transform * result
		parent = parent.get_parent()
	return result


func _add_exterior(node_name: String, at: Transform3D, layout_node: Node) -> void:
	var regex := RegEx.create_from_string("^outside_(.+)_(\\d+)$")
	var piece_name := regex.search(node_name).get_string(1)
	var piece: Node3D = load(KIT_DIR + piece_name + ".glb").instantiate()
	piece.name = node_name.trim_prefix("outside_")
	piece.transform = at
	add_child(piece)
	exterior_pieces.append(piece)
	for text in layout_node.get_children():
		_add_texts(piece, (text as Node3D).transform, String(text.name))


# --- Words -------------------------------------------------------------------------------------

## Label3Ds for one text_<style>_<key> anchor under `parent` (at `at`, facing the piece's front)
func _add_texts(parent: Node3D, at: Transform3D, anchor_name: String) -> void:
	if not anchor_name.begins_with("text_"):
		return
	var full := anchor_name.trim_prefix("text_")
	var style := full.get_slice("_", 0)
	var key := full.substr(style.length() + 1)
	text_keys.append(full)
	# The words lie 2 mm in front of their paper or plate
	var front := at.translated_local(Vector3(0.0, 0.0, 0.002))
	match style:
		"note":
			var note: Dictionary = texts.get("notes", {}).get(key, {})
			var top := NOTE_PAPER.y / 2.0 - NOTE_CLIP
			var room_w := NOTE_PAPER.x - 2.0 * NOTE_MARGIN
			var title := _label(parent, front.translated_local(Vector3(0.0, top, 0.0)), note.get("title", ""), INK)
			title.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			_fit(title, Vector2(room_w, 0.04), NOTE_TITLE_CAP, NOTE_MIN_CAP, true)
			var title_h := _height(title) + 0.008
			var lines: Array = note.get("lines", [])
			var body_text := "\n".join(PackedStringArray(lines.map(func(line): return "- " + str(line))))
			# A left-aligned Label3D starts at its origin: put that on the paper's left margin
			var body := _label(parent, front.translated_local(Vector3(-room_w / 2.0, top - title_h, 0.0)), body_text, INK)
			body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			_fit(body, Vector2(room_w, NOTE_PAPER.y - NOTE_CLIP - NOTE_MARGIN - title_h), NOTE_BODY_CAP, NOTE_MIN_CAP, true)
		"sign":
			var words: String = texts.get("signs", {}).get(key, "")
			_fit(_label(parent, front, words, INK), SIGN_BOX, SIGN_CAP, SIGN_CAP * 0.6, true)
		"label", "redlabel":
			var words: String = texts.get("labels", {}).get(key, "")
			var plate: Array = [0.2, 0.05, 0.025, false]
			for start in LABEL_PLATES:
				if key.begins_with(start):
					plate = LABEL_PLATES[start]
			var color := Color(0.96, 0.95, 0.92) if style == "redlabel" else INK
			_fit(_label(parent, front, words, color), Vector2(plate[0], plate[1]), plate[2], plate[2] * 0.5, plate[3])
		"card":
			var card: Dictionary = texts.get("cards", {}).get(key, {})
			var room_w := CARD_PLATE.x - 2.0 * CARD_MARGIN
			var top := CARD_PLATE.y / 2.0 - CARD_MARGIN
			var bottom := -CARD_PLATE.y / 2.0 + CARD_MARGIN
			var title := _label(parent, front.translated_local(Vector3(0.0, top, 0.0)), card.get("title", ""), INK)
			title.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			_fit(title, Vector2(room_w, 0.03), CARD_TITLE_CAP, CARD_TITLE_CAP * 0.6, false)
			var credit := _label(parent, front.translated_local(Vector3(0.0, bottom, 0.0)), card.get("credit", ""), INK)
			credit.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			_fit(credit, Vector2(room_w, 0.02), CARD_CREDIT_CAP, CARD_CREDIT_CAP * 0.75, false)
			var caption_top := top - _height(title) - 0.01
			var caption_room := caption_top - (bottom + _height(credit) + 0.008)
			var caption := _label(parent, front.translated_local(Vector3(-room_w / 2.0, caption_top, 0.0)), card.get("caption", ""), INK)
			caption.vertical_alignment = VERTICAL_ALIGNMENT_TOP
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			_fit(caption, Vector2(room_w, caption_room), CARD_CAPTION_CAP, CARD_CAPTION_CAP * 0.75, true)
		_:
			push_error("WorkshopDecor: unknown text style in %s" % anchor_name)


func _label(parent: Node3D, at: Transform3D, words: String, color: Color) -> Label3D:
	var label := Label3D.new()
	label.name = "Text%02d" % labels.size()
	label.text = words
	label.font_size = FONT_SIZE
	label.outline_size = 0
	label.modulate = color
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.transform = at
	parent.add_child(label)
	return label


## Sizes the label's text to its box: `cap` (m), shrinking down to `min_cap` until it fits; with
## `wraps`, lines wrap at the box's width. Records the label for fits().
func _fit(label: Label3D, box: Vector2, cap: float, min_cap: float, wraps: bool) -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wraps else TextServer.AUTOWRAP_OFF
	var size := cap
	while true:
		label.pixel_size = size / (CAP_RATIO * FONT_SIZE)
		if wraps:
			label.width = box.x / label.pixel_size
		var measured := text_size(label)
		if (measured.x <= box.x + 0.0005 and measured.y <= box.y + 0.0005) or size <= min_cap:
			break
		size = maxf(size * 0.94, min_cap)
	labels.append([label, box, wraps])


## The size (m) the label's words take: wrapped to its width when it wraps
func text_size(label: Label3D) -> Vector2:
	var font: Font = ThemeDB.fallback_font
	var px: Vector2
	if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
		px = font.get_multiline_string_size(label.text, label.horizontal_alignment, label.width, label.font_size, -1,
				TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
	else:
		px = font.get_multiline_string_size(label.text, label.horizontal_alignment, -1, label.font_size)
	return px * label.pixel_size


func _height(label: Label3D) -> float:
	return text_size(label).y


## The cap height (m) a label is drawn at
func cap_height(label: Label3D) -> float:
	return label.pixel_size * label.font_size * CAP_RATIO


## Labels whose words don't fit their box (empty when all fit)
func misfits() -> Array[String]:
	var out: Array[String] = []
	for item in labels:
		var label: Label3D = item[0]
		var measured := text_size(label)
		if measured.x > item[1].x + 0.001 or measured.y > item[1].y + 0.001:
			out.append("%s (%.3f x %.3f m in %.3f x %.3f)" % [label.text.get_slice("\n", 0), measured.x, measured.y, item[1].x, item[1].y])
	return out


# --- Ground, cable, tracks ---------------------------------------------------------------------

## Rests every exterior floor piece and the cable's ground points on whatever is below them
func _rest_on_ground() -> void:
	await get_tree().physics_frame
	var exclude: Array[RID] = []
	for body in get_parent().find_children("*", "CollisionObject3D", true, false):
		exclude.append((body as CollisionObject3D).get_rid())
	for piece in exterior_pieces:
		if absf(piece.position.y) > 0.001:
			continue                                    # on the wall, not the ground
		var ground: float = ground_height(piece.position, exclude)
		piece.position.y = ground - GROUND_SINK
	var points: Array[Vector3] = []
	for p in _cable_points:
		if absf(p.y) < 0.001:
			p.y = ground_height(p, exclude) + CABLE_RADIUS
		points.append(p)
	_build_cable(points)


## The ground's height (in this node's frame) under `local`, ignoring `exclude`; 0 if none
func ground_height(local: Vector3, exclude: Array[RID] = []) -> float:
	var from := to_global(Vector3(local.x, 1.0, local.z))
	var to := to_global(Vector3(local.x, -2.0, local.z))
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return to_local(hit["position"]).y if not hit.is_empty() else 0.0


func _build_cable(points: Array[Vector3]) -> void:
	if points.size() < 2:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in points.size() - 1:
		var a: Vector3 = points[k]
		var b: Vector3 = points[k + 1]
		var along := (b - a).normalized()
		var side := along.cross(Vector3.UP)
		if side.length() < 0.1:
			side = Vector3.RIGHT
		side = side.normalized() * CABLE_RADIUS
		var up := side.cross(along).normalized() * CABLE_RADIUS
		var ring := [side, up, -side, -up]
		for j in 4:
			var c0: Vector3 = ring[j]
			var c1: Vector3 = ring[(j + 1) % 4]
			for v in [a + c0, b + c0, b + c1, a + c0, b + c1, a + c1]:
				st.add_vertex(v)
	st.generate_normals()
	cable = MeshInstance3D.new()
	cable.name = "Cable"
	cable.mesh = st.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.878, 0.627, 0.188)      # ws_accent
	material.roughness = 0.6
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	cable.material_override = material
	add_child(cable)


## One Decal per segment of a track's path, the tread's pair of prints along it
func _add_track(track: String, points: Array) -> void:
	var albedo: Texture2D = load(TRACK_ALBEDO)
	var normal: Texture2D = load(TRACK_NORMAL)
	for k in points.size() - 1:
		var a: Vector3 = points[k]
		var b: Vector3 = points[k + 1]
		var decal := Decal.new()
		decal.name = "%s_%02d" % [track.capitalize().replace(" ", ""), k + 1]
		decal.size = Vector3(TRACK_WIDTH, TRACK_DEPTH, a.distance_to(b))
		decal.texture_albedo = albedo
		decal.texture_normal = normal
		decal.modulate = Color(1.0, 1.0, 1.0, TRACK_STRENGTH.get(track, 0.5))
		decal.upper_fade = 0.2
		decal.lower_fade = 0.2
		decal.distance_fade_enabled = true
		decal.distance_fade_begin = 60.0
		decal.distance_fade_length = 20.0
		decal.cull_mask = 1 << (MoonTerrain.RENDER_LAYER - 1)
		# Local +Z along the segment (from b to a: the texture's v runs with the rover's travel)
		decal.transform = Transform3D(Basis.looking_at(b - a, Vector3.UP), (a + b) / 2.0)
		add_child(decal)
		tracks.append(decal)
