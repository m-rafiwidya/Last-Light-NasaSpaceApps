class_name SubtitleStack

extends PanelContainer
## Every DialogServer line as a stacked DialogBox; each subtitle screen has one and follows every line.
## It owns a reserved area at the bottom centre (HUD board: left / right 400 of 1600, bottom 44) and
## places itself there every frame: inside `slot` when the screen gives it one (the console), else
## centred above the bottom edge, narrowed or moved beside a `keep_out` control (the rover stats),
## lifted above it only when neither fits. It never reaches up into a `keep_below` control (the
## objective panel): the oldest lines go first. At most MAX_ENTRIES lines show at once; a line
## always shows in full, wrapped. With `one_at_a_time` (cutscenes) only one line ever shows: a line
## fades out as soon as it ends, and the next waits until it is gone, then fades in.
## The backing (theme variation SubtitleBacking) is drawn here, never by the panel style: as opaque as
## the most opaque line in it, so it fades and resizes with its text and is never seen empty.
## `backing` false (cutscenes: the text sits on the letterbox bar) draws none.

const MAX_ENTRIES: int = 2
const BOTTOM: float = 53.0
const SIDE: float = 53.0
const MIN_WIDTH: float = 560.0
const MAX_WIDTH: float = 960.0
const GAP: float = 24.0
const SINGLE_FADE: float = 0.25

var dialog_box_scene: PackedScene = preload("res://src/ui/dialog_box/dialog_box.tscn")
var dialog_boxes: Dictionary = {}
## A Control whose rect is the reserved area (its minimum height follows the stack's)
var slot: Control = null
## Controls the stack must stay clear of
var keep_out: Array[Control] = []
## Controls the stack must stay under
var keep_below: Array[Control] = []
var one_at_a_time: bool = false
var backing: bool = true
## The skip key chip on the radio line DialogServer would skip (off in cutscenes)
var skip_hint: bool = true
var _backing_color: Color = Color(0.0, 0.0, 0.0, 0.8)
## Lines waiting for the shown one to leave (one_at_a_time)
var _waiting: Array[Dialog] = []

@onready var boxes: VBoxContainer = $Boxes


func _ready() -> void:
	add_to_group(&"subtitle_stack")
	var style: StyleBox = get_theme_stylebox(&"panel")
	if style is StyleBoxFlat:
		_backing_color = (style as StyleBoxFlat).bg_color
	var empty := StyleBoxEmpty.new()
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		empty.set_content_margin(side, style.get_content_margin(side) if style else 0.0)
	add_theme_stylebox_override(&"panel", empty)
	DialogServer.dialog_played.connect(_on_dialog_played)
	DialogServer.dialog_ended.connect(_on_dialog_ended)
	GeneralSettings.section.changed.connect(func(_key: String) -> void: _apply_subtitles())
	_apply_subtitles()
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	place()


func _process(_delta: float) -> void:
	if not _waiting.is_empty() and boxes.get_child_count() == 0:
		_show(_waiting.pop_front())
	_update_skip_hint()
	place()
	queue_redraw()


func _update_skip_hint() -> void:
	var skippable: Dialog = DialogServer.skippable_dialog() if skip_hint and DialogServer.skip_allowed() else null
	var target: Variant = dialog_boxes.get(skippable.get_instance_id()) if skippable else null
	for id in dialog_boxes:
		var box: Variant = dialog_boxes[id]
		if is_instance_valid(box):
			box.show_skip(box == target)


func _draw() -> void:
	var alpha: float = backing_alpha()
	if alpha > 0.0 and size.y > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(_backing_color, _backing_color.a * alpha))


## How opaque the backing is now (0..1 of its colour): its most opaque line's opacity
func backing_alpha() -> float:
	return text_alpha() if backing else 0.0


## The most opaque line with text in it (0: none)
func text_alpha() -> float:
	var alpha: float = 0.0
	for box in boxes.get_children():
		if box.is_queued_for_deletion() or not box.visible or box.is_empty():
			continue
		alpha = maxf(alpha, box.modulate.a)
	return alpha


## How many lines are on screen (fading ones included)
func shown_count() -> int:
	return boxes.get_children().filter(func(box: Node) -> bool: return not box.is_queued_for_deletion()).size()


func _apply_subtitles() -> void:
	visible = GeneralSettings.subtitles()


## The rect the stack takes for its current lines
func place() -> void:
	var view: Vector2 = get_viewport_rect().size
	var width: float = clampf(view.x * 0.5, MIN_WIDTH, MAX_WIDTH)
	var bottom: float = view.y - BOTTOM
	if slot and slot.is_visible_in_tree():
		var area: Rect2 = slot.get_global_rect()
		width = minf(area.size.x, MAX_WIDTH)
		_set_rect(area.position.x + (area.size.x - width) / 2.0, area.end.y, width)
		slot.custom_minimum_size.y = size.y
		return
	width = minf(width, view.x - 2.0 * SIDE)
	var left: float = (view.x - width) / 2.0
	for other in keep_out:
		if not is_instance_valid(other) or not other.is_visible_in_tree():
			continue
		var rect: Rect2 = other.get_global_rect()
		if rect.end.x + GAP <= left or rect.position.x - GAP >= left + width:
			continue
		# Narrow the band symmetrically to clear it, else beside it, else above it
		var inset: float = rect.end.x + GAP if rect.get_center().x < view.x / 2.0 else view.x - rect.position.x + GAP
		var clear: float = minf(view.x - 2.0 * inset, width)
		var beside: float = view.x - inset - SIDE
		if clear >= MIN_WIDTH:
			width = clear
			left = (view.x - width) / 2.0
		elif beside >= MIN_WIDTH:
			width = minf(beside, MAX_WIDTH)
			left = inset if rect.get_center().x < view.x / 2.0 else view.x - inset - width
		else:
			bottom = minf(bottom, rect.position.y - GAP)
	_set_rect(left, bottom, width)
	_stay_below()


## Drops the oldest lines at once while the stack reaches into a keep_below control
func _stay_below() -> void:
	var shown: Array = boxes.get_children().filter(func(box: Node) -> bool: return box.visible)
	if shown.size() < 2:
		return
	for other in keep_below:
		if is_instance_valid(other) and other.is_visible_in_tree() and other.get_global_rect().grow(GAP).intersects(get_global_rect()):
			var oldest: Control = shown[0]
			oldest.hide()
			oldest.queue_free()
			for key in dialog_boxes.keys():
				if dialog_boxes[key] == oldest:
					dialog_boxes.erase(key)
			_set_rect(position.x, position.y + size.y, size.x)
			return


func _set_rect(left: float, bottom: float, width: float) -> void:
	size.x = width
	var height: float = get_combined_minimum_size().y
	size = Vector2(width, height)
	position = Vector2(left, bottom - height)


func _on_dialog_played(dialog: Dialog) -> void:
	if one_at_a_time and (boxes.get_child_count() > 0 or not _waiting.is_empty()):
		for box in boxes.get_children():
			box.fade_out(0.0, SINGLE_FADE, false)
		_waiting.append(dialog)
		return
	_show(dialog)


func _show(dialog: Dialog) -> void:
	var dialog_box: Control = dialog_box_scene.instantiate()
	dialog_box.set_line(dialog.speaker, dialog.subtitle)
	boxes.add_child(dialog_box)
	_ignore_mouse(dialog_box)
	if one_at_a_time:
		dialog_box.fade_in(SINGLE_FADE, false)
	else:
		dialog_box.fade_in()
	dialog_boxes[dialog.get_instance_id()] = dialog_box
	_limit_entries()


## The oldest lines beyond MAX_ENTRIES leave at once
func _limit_entries() -> void:
	var shown: Array = boxes.get_children().filter(func(box: Node) -> bool: return not box.leaving)
	for i in maxi(shown.size() - MAX_ENTRIES, 0):
		shown[i].fade_out(0.0)


func _on_dialog_ended(dialog: Dialog) -> void:
	_waiting.erase(dialog)
	var dialog_box: Variant = dialog_boxes.get(dialog.get_instance_id())
	dialog_boxes.erase(dialog.get_instance_id())
	if is_instance_valid(dialog_box):
		dialog_box.show_skip(false)
		if one_at_a_time:
			dialog_box.fade_out(0.0, SINGLE_FADE, false)
		else:
			dialog_box.fade_out()


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)
