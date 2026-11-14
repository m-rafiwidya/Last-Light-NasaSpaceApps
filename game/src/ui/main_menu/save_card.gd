class_name SaveCard

extends FramedPanel

## One save in the PLAY popup's list (docs/ui/boards/Main.dc.html `.ll-save`, design x 1.2):
## the mission image, date and time, mission title, a 16-segment story progress bar with %,
## the time played top-right and the slanted Autosave tag. Hovering focuses it, and focus
## selects it (frame, glow, corner brackets), so mouse and keyboard share one highlight.
## Click or Enter emits `activated`.

signal activated

const SIZE: Vector2 = Vector2(720.0, 124.8)
## The image fills the card's inner height at 16:9
const IMAGE_SIZE: Vector2 = Vector2(204.8, 115.2)
const SEGMENTS: int = 16
const SEGMENT_GAP: float = 2.4
const SEGMENT_HEIGHT: float = 3.6
const PROGRESS_WIDTH: float = 288.0
const TAG_COLOR: Color = Color("#34343A")
const TAG_SLANT: float = 9.6

var info: SaveSlotInfo

var _mouse_down: bool = false


func _init() -> void:
	custom_minimum_size = SIZE
	focus_mode = Control.FOCUS_ALL
	selected = false
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## Fills the card; call before it enters the tree
func setup(slot: SaveSlotInfo) -> void:
	info = slot
	name = "Save_" + slot.slot_id


func _ready() -> void:
	super()
	mouse_entered.connect(_on_mouse_entered)
	focus_entered.connect(func() -> void: selected = true)
	focus_exited.connect(func() -> void: selected = false)
	_build()


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_accept") and not event.is_echo():
		accept_event()
		_activate()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if event.pressed:
			_mouse_down = true
			grab_focus()
		elif _mouse_down:
			_mouse_down = false
			if get_global_rect().has_point(get_global_mouse_position()):
				_activate()


func _activate() -> void:
	AudioManager.play_ui(&"game_start")
	activated.emit()


func _on_mouse_entered() -> void:
	if not has_focus():
		AudioManager.play_hover()
		grab_focus()


func _build() -> void:
	var frame := MarginContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		frame.add_theme_constant_override("margin_" + side, 4)   # 4.8 with the 1 px border
	add_child(frame)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 0)
	frame.add_child(row)

	var image := TextureRect.new()
	image.name = "Image"
	image.custom_minimum_size = IMAGE_SIZE
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.texture = SaveIndex.mission_image(info.mission_id)
	row.add_child(image)

	var text_margin := MarginContainer.new()
	text_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_margin.add_theme_constant_override("margin_left", 19)
	text_margin.add_theme_constant_override("margin_top", 7)
	row.add_child(text_margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 3)
	text_margin.add_child(column)
	column.add_child(_label("Date", SaveIndex.format_date(info.saved_at), &"LabelBody", 17, &"text_3"))
	column.add_child(_label("Title", SaveIndex.mission_title(info.mission_id), &"LabelBodyStrong", 24, &"text"))

	var progress_margin := MarginContainer.new()
	progress_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_margin.add_theme_constant_override("margin_top", 4)
	column.add_child(progress_margin)
	var progress := HBoxContainer.new()
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress.custom_minimum_size.x = PROGRESS_WIDTH
	progress.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	progress.add_theme_constant_override("separation", 12)
	progress_margin.add_child(progress)
	var bar := Control.new()
	bar.name = "ProgressBar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.custom_minimum_size.y = SEGMENT_HEIGHT
	bar.draw.connect(_draw_segments.bind(bar))
	progress.add_child(bar)
	progress.add_child(_label("Percent", "%d%%" % roundi(info.story_progress * 100.0), &"LabelBody", 14, &"muted"))

	# Corner items sit on an overlay the size of the card's inside
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	var played := _label("Played", SaveIndex.format_play_time(info.play_time_sec), &"LabelBody", 16, &"muted")
	played.anchor_left = 1.0
	played.anchor_right = 1.0
	played.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	played.offset_left = -18.0
	played.offset_right = -18.0
	played.offset_top = 10.0
	overlay.add_child(played)
	if info.is_autosave:
		overlay.add_child(_autosave_tag())


func _autosave_tag() -> Control:
	var tag := MarginContainer.new()
	tag.name = "AutosaveTag"
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_theme_constant_override("margin_left", 19)
	tag.add_theme_constant_override("margin_right", 17)
	tag.add_theme_constant_override("margin_top", 3)
	tag.add_theme_constant_override("margin_bottom", 3)
	tag.add_child(_label("Text", "Autosave", &"LabelBody", 16, &"text_2"))
	tag.draw.connect(func() -> void:
		var s: Vector2 = tag.size
		tag.draw_colored_polygon(PackedVector2Array([
			Vector2(TAG_SLANT, 0.0), Vector2(s.x, 0.0), s, Vector2(0.0, s.y)]), TAG_COLOR))
	tag.anchor_left = 1.0
	tag.anchor_top = 1.0
	tag.anchor_right = 1.0
	tag.anchor_bottom = 1.0
	tag.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tag.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tag.offset_left = -4.0
	tag.offset_right = -4.0
	tag.offset_top = -4.0
	tag.offset_bottom = -4.0
	return tag


func _draw_segments(bar: Control) -> void:
	var on: Color = get_theme_color(&"text", &"UIColor")
	var off: Color = get_theme_color(&"line_3", &"UIColor")
	var filled: int = roundi(info.story_progress * SEGMENTS)
	var width: float = (bar.size.x - SEGMENT_GAP * (SEGMENTS - 1)) / SEGMENTS
	for i in SEGMENTS:
		var rect := Rect2(i * (width + SEGMENT_GAP), 0.0, width, SEGMENT_HEIGHT)
		bar.draw_rect(rect, on if i < filled else off)


func _label(node_name: String, text: String, variation: StringName, font_size: int, color: StringName) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", get_theme_color(color, &"UIColor"))
	return label
