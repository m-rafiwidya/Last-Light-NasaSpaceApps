class_name DataSourcesScreen

extends UIScreen

## Data Sources (plan item L): a framed panel like Settings over a blurred backdrop, listing
## res/story/data_sources.json group by group (name, what the game uses it for, a link that opens
## in the browser) in a scroll list, with BACK. Opened from the main menu and the campaign result
## screen: get_tree().get_first_node_in_group(&"data_sources").open(). Esc or BACK closes it.

signal closed

const PATH: String = "res://res/story/data_sources.json"
const THEME: Theme = preload("res://res/ui_theme_v2.tres")
const BLUR: Shader = preload("res://src/ui/components/backdrop_blur.gdshader")
const FRAMED_PANEL: PackedScene = preload("res://src/ui/components/framed_panel.tscn")
const SOLID_BUTTON: PackedScene = preload("res://src/ui/components/solid_button.tscn")
const MARGIN: float = 28.8
const LINK_FONT_SIZE: int = 15

var data: Dictionary = {}
## Every entry shown: {"group", "name", "use", "link", "node"}
var entries: Array[Dictionary] = []
var scroll: ScrollContainer
var panel: Control
var back: Button

var _root: Control
var _list: VBoxContainer
var _previous_focus: Control
var _tween: Tween


func _ready() -> void:
	layer = 110
	add_to_group(&"data_sources")
	_root = Control.new()
	_root.name = "Root"
	_root.theme = THEME
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var blur := ColorRect.new()
	var material := ShaderMaterial.new()
	material.shader = BLUR
	material.set_shader_parameter(&"radius_px", 12.0)
	material.set_shader_parameter(&"amount", 1.0)
	material.set_shader_parameter(&"brightness", 0.3)
	material.set_shader_parameter(&"bg_color", Color(0.0196, 0.0196, 0.0275, 1.0))
	blur.material = material
	blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(blur)
	panel = FRAMED_PANEL.instantiate()
	panel.selected = false
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = MARGIN
	panel.offset_top = MARGIN
	panel.offset_right = -MARGIN
	panel.offset_bottom = -MARGIN
	_root.add_child(panel)
	var margin := MarginContainer.new()
	for side in [["left", 77], ["top", 48], ["right", 77], ["bottom", 43]]:
		margin.add_theme_constant_override("margin_" + side[0], side[1])
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 26)
	margin.add_child(column)
	data = load_data()
	column.add_child(_label(str(data.get("title", "DATA SOURCES")), &"LabelSettingsTitle"))
	if data.get("intro", "") != "":
		column.add_child(_label(str(data["intro"]), &"LabelHeading", true))
	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 22)
	scroll.add_child(_list)
	_build_list()
	var footer := HBoxContainer.new()
	column.add_child(footer)
	back = SOLID_BUTTON.instantiate()
	back.name = "Back"
	back.text = "BACK"
	back.set(&"compact", true)
	var sound := ButtonSoundComponent.new()
	sound.press_sound = &"back"
	back.add_child(sound)
	back.pressed.connect(close)
	footer.add_child(back)
	hide()


static func load_data() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
	return parsed if parsed is Dictionary else {"groups": []}


func is_open() -> bool:
	return visible


func open() -> void:
	if not visible:
		_previous_focus = get_viewport().gui_get_focus_owner()
	show()
	scroll.scroll_vertical = 0
	_root.modulate.a = 0.0
	if _tween:
		_tween.kill()
	_tween = create_ui_tween()
	_tween.tween_property(_root, "modulate:a", 1.0, FADE_DURATION)
	back.grab_focus()


func close() -> void:
	if not visible:
		return
	if _tween:
		_tween.kill()
	hide()
	if is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()
	_previous_focus = null
	closed.emit()


func fade_in() -> void:
	open()


func fade_out() -> void:
	close()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		close()


func _build_list() -> void:
	entries.clear()
	for group: Dictionary in data.get("groups", []):
		var box := VBoxContainer.new()
		box.add_theme_constant_override(&"separation", 14)
		box.add_child(_label(str(group.get("title", "")).to_upper(), &"LabelEyebrow", true))
		var group_entries: Array = group.get("entries", [])
		if group.get("note", "") != "" and (not group.get("placeholder", false) or group_entries.is_empty()):
			box.add_child(_label(str(group["note"]), &"LabelMonoNote", true))
		for entry: Dictionary in group_entries:
			var node := _entry(entry)
			box.add_child(node)
			entries.append({"group": str(group.get("id", "")), "name": str(entry.get("name", "")),
				"use": str(entry.get("use", "")), "link": str(entry.get("link", "")), "node": node})
		_list.add_child(box)


func _entry(entry: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override(&"separation", 4)
	row.add_child(_label(str(entry.get("name", "")), &"LabelBodyStrong", true))
	if entry.get("use", "") != "":
		var use := _label(str(entry["use"]), &"LabelHeading", true)
		row.add_child(use)
	var link: String = str(entry.get("link", ""))
	if link != "":
		var button := LinkButton.new()
		button.name = "Link"
		button.uri = link
		button.text = link.trim_prefix("https://").trim_prefix("http://").get_slice("/", 0) + "  ↗"
		button.tooltip_text = link
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.add_theme_font_size_override(&"font_size", LINK_FONT_SIZE)
		var muted: Color = _root.get_theme_color(&"muted", &"UIColor")
		var bright: Color = _root.get_theme_color(&"text", &"UIColor")
		button.add_theme_color_override(&"font_color", muted)
		button.add_theme_color_override(&"font_hover_color", bright)
		button.add_theme_color_override(&"font_focus_color", bright)
		button.add_theme_color_override(&"font_pressed_color", bright)
		row.add_child(button)
	return row


func _label(text: String, variation: StringName, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.custom_minimum_size.x = 1.0
	return label
