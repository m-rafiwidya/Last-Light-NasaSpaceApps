extends Control

## Test scene for the v2 UI components (res/ui_theme_v2.tres). Open it with
##   Godot --path game res://src/ui/components/ui_gallery.tscn
## Tab / arrow keys / gamepad move focus; hover and focus should look the same everywhere.
## `-- --shot=<file.png>` saves a screenshot after a few frames and quits (for checking the look).

const UNDERLINE := preload("res://src/ui/components/underline_button.tscn")
const UNDERLINE_CENTRE := preload("res://src/ui/components/underline_button_centre.tscn")
const SOLID := preload("res://src/ui/components/solid_button.tscn")
const TAB := preload("res://src/ui/components/slanted_tab.tscn")
const BACK := preload("res://src/ui/components/back_button.tscn")
const KEY_CHIP := preload("res://src/ui/components/key_chip.tscn")
const FRAMED := preload("res://src/ui/components/framed_panel.tscn")

var _tabs: Array[SlantedTab] = []


func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 67)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	scroll.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 22)
	margin.add_child(root)

	var title := Label.new()
	title.theme_type_variation = &"LabelScreenTitle"
	title.text = "UI GALLERY"
	root.add_child(title)

	_underline_section(root)
	_solid_section(root)
	_tab_section(root)
	_back_and_keys_section(root)
	_panel_section(root)

	# Keyboard / gamepad users start with something focused
	var first := find_child("*Menu*", true, false)
	if first is Control:
		(first as Control).grab_focus()

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot_and_quit(arg.trim_prefix("--shot="))


func _heading(parent: Control, text: String) -> void:
	var l := Label.new()
	l.theme_type_variation = &"LabelEyebrow"
	l.text = text
	parent.add_child(l)


func _row(parent: Control, gap: int = 40) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", gap)
	parent.add_child(row)
	return row


func _underline_section(root: Control) -> void:
	_heading(root, "UNDERLINE BUTTONS  (left | centre | primary | active | disabled)")
	var row := _row(root, 60)
	var menu := UNDERLINE.instantiate() as UnderlineButton
	menu.name = "MenuLeft"
	menu.theme_type_variation = &"UnderlineButtonMenu"
	menu.text = "SETTINGS"
	row.add_child(menu)
	var left := UNDERLINE.instantiate() as UnderlineButton
	left.text = "BRIEFING"
	row.add_child(left)
	var centre := UNDERLINE_CENTRE.instantiate() as UnderlineButton
	centre.text = "SETTINGS"
	row.add_child(centre)
	var primary := UNDERLINE.instantiate() as UnderlineButton
	primary.theme_type_variation = &"UnderlineButtonPrimary"
	primary.rest_fraction = 0.25
	primary.text = "CONTINUE"
	row.add_child(primary)
	var active := UNDERLINE.instantiate() as UnderlineButton
	active.text = "STATUS"
	active.active = true
	row.add_child(active)
	var off := UNDERLINE.instantiate() as UnderlineButton
	off.text = "LOCKED"
	off.disabled = true
	row.add_child(off)


func _solid_section(root: Control) -> void:
	_heading(root, "SOLID SLANTED BUTTONS  (48 px | 36 px | disabled)")
	var row := _row(root)
	var big := SOLID.instantiate() as SolidButton
	big.text = "START NEW CAMPAIGN"
	row.add_child(big)
	var small := SOLID.instantiate() as SolidButton
	small.compact = true
	small.text = "RESET TO DEFAULTS"
	row.add_child(small)
	var off := SOLID.instantiate() as SolidButton
	off.compact = true
	off.text = "BACK"
	off.disabled = true
	row.add_child(off)


func _tab_section(root: Control) -> void:
	_heading(root, "SLANTED TABS  (click to switch the active one)")
	var row := _row(root, 8)
	for i in ["GENERAL", "AUDIO", "VIDEO", "CONTROLS"].size():
		var tab := TAB.instantiate() as SlantedTab
		tab.text = ["GENERAL", "AUDIO", "VIDEO", "CONTROLS"][i]
		tab.active = i == 0
		tab.pressed.connect(_on_tab_pressed.bind(tab))
		row.add_child(tab)
		_tabs.append(tab)


func _on_tab_pressed(pressed: SlantedTab) -> void:
	for tab in _tabs:
		tab.active = tab == pressed


func _back_and_keys_section(root: Control) -> void:
	_heading(root, "BACK BUTTON  |  KEY CHIPS  (keys come from the InputMap)")
	var row := _row(root, 48)
	row.add_child(BACK.instantiate())
	for entry in [
		[&"ui_accept", "Load"],
		[&"ui_cancel", "Cancel"],
		[&"interact_use", "Insert module"],
		[&"move_forward", "Move"],
		[&"camera_next", "Next camera"],
		[&"interact_primary", "Grab"],
		[&"no_such_action", "Fallback"],
	]:
		var chip := KEY_CHIP.instantiate() as KeyChip
		chip.action = entry[0]
		chip.label_text = entry[1]
		chip.fallback_key = "?"
		row.add_child(chip)


func _panel_section(root: Control) -> void:
	_heading(root, "FRAMED POPUP  |  SELECTED CARD  |  UNSELECTED CARD  |  FOCUSABLE CARDS (hover or Tab)")
	var row := _row(root, 48)
	row.custom_minimum_size.y = 150
	var popup := FRAMED.instantiate() as FramedPanel
	popup.custom_minimum_size = Vector2(420, 130)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	var msg := Label.new()
	msg.theme_type_variation = &"LabelBody"
	msg.text = "There's no save file."
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(msg)
	var btn := SOLID.instantiate() as SolidButton
	btn.compact = true
	btn.text = "START NEW CAMPAIGN"
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(btn)
	popup.add_child(box)
	row.add_child(popup)

	for i in 4:
		var card := FRAMED.instantiate() as FramedPanel
		card.custom_minimum_size = Vector2(300, 125)
		card.selected = i == 0
		card.select_on_focus = i >= 2
		var l := Label.new()
		l.theme_type_variation = &"LabelBodyStrong"
		l.text = ["Selected card", "Unselected card", "Focusable card", "Focusable card"][i]
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(l)
		row.add_child(card)


func _shot_and_quit(path: String) -> void:
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
