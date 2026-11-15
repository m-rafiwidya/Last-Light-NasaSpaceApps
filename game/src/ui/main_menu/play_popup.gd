class_name PlayPopup

extends Control

## The main menu's PLAY popup (docs/ui/UI_SPEC.md "Main menu", board Main.dc.html, design
## x 1.2). Opening it blurs and dims everything drawn before it (the starfield, the Moon, the
## menu column) and its full-screen blur takes the mouse. The owner turns the menu's own input
## off while it is open.
## - No saves: "There's no save file." and START NEW CAMPAIGN.
## - Saves: "Select save data to load.", one card per slot (SaveIndex.list_slots(): empty and
##   unreadable slots included), then START NEW CAMPAIGN. Up/down move between cards, Enter or
##   click loads a save (or starts a new campaign in an empty slot), Del twice deletes one. A long
##   list scrolls to keep the selected card in view. With every slot used, START NEW CAMPAIGN asks
##   first, naming the slot it would replace; Cancel (or Esc) returns to the popup.
## Esc or the back button closes it; `closed` is emitted as it starts closing.
## `load_only` (the pause menu's Load): only the readable saves, no Delete or START NEW CAMPAIGN, and
## loading over unsaved progress asks first.

signal closed

const OPEN_TIME: float = 0.5
const CLOSE_TIME: float = 0.3
## Content entrance (.ll-pin: fade and 10 px rise in 0.45 s)
const RISE: float = 12.0
const RISE_TIME: float = 0.45
## 14 px x 1.2, rounded: container separations are whole pixels
const CARD_GAP: float = 17.0
## Room around the cards inside the scroll area, so the selected card's brackets and glow show
const LIST_MARGIN: float = 22.0
## Cards beyond this height scroll (five fit)
const MAX_LIST_HEIGHT: float = 5.0 * 124.8 + 4.0 * CARD_GAP + 2.0 * LIST_MARGIN
## Board gaps: heading to the first card 28 px, last card to START 32 px (x 1.2)
const HEADING_GAP: float = 33.6
const START_GAP: float = 38.4

var is_open: bool = false
var load_only: bool = false

var _tween: Tween
var _confirm: Control
var _confirm_message: Label
var _confirm_ok: Button
var _confirm_cancel: Button
var _confirm_return: Control
var _confirm_replace_slot: String = ""
var _confirm_load_slot: String = ""
var _blur_material: ShaderMaterial

@onready var _blur: ColorRect = $Blur
@onready var _content: Control = $Content
@onready var _back: BackButton = %Back
@onready var _no_save: Control = %NoSave
@onready var _saves: Control = %Saves
@onready var _scroll: ScrollContainer = %Scroll
@onready var _cards: VBoxContainer = %Cards
@onready var _start_empty: Button = %StartEmpty
@onready var _start_list: Button = %StartList
@onready var _load_chip: Control = %LoadChip


func _ready() -> void:
	_blur_material = _blur.material
	_back.position = BackButton.DESIGN_POSITION
	_back.pressed.connect(close)
	_start_empty.pressed.connect(_on_start_pressed)
	_start_list.pressed.connect(_on_start_pressed)
	for side in ["left", "top", "right", "bottom"]:
		(%ListMargin as MarginContainer).add_theme_constant_override("margin_" + side, int(LIST_MARGIN))
	# The list is 600 px (x 1.2) wide plus the margin, centred; the gaps around it lose the margin
	_saves.offset_left = -SaveCard.SIZE.x / 2.0 - LIST_MARGIN
	_saves.offset_right = SaveCard.SIZE.x / 2.0 + LIST_MARGIN
	(%GapTop as Control).custom_minimum_size.y = HEADING_GAP - LIST_MARGIN
	(%GapBottom as Control).custom_minimum_size.y = START_GAP - LIST_MARGIN
	_cards.add_theme_constant_override("separation", int(CARD_GAP))
	_build_confirm()
	_set_interactive(false)
	hide()


## Esc closes the popup and nothing else. In _input, before the GUI and before the UIManager
## sees it, so the Esc can't reach anything under the popup.
func _input(event: InputEvent) -> void:
	if not is_open or Debug.console_open:
		return
	if event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		AudioManager.play_ui(&"back")
		if is_confirming():
			_close_confirm()
		else:
			close()


## Reads the saves and shows the popup. Focus goes to the newest save, or START NEW CAMPAIGN.
func open() -> void:
	if is_open:
		return
	is_open = true
	_populate()
	show()
	_set_interactive(true)
	_animate(1.0, OPEN_TIME)
	_content.modulate.a = 0.0
	_content.position.y = RISE
	_tween.parallel().tween_property(_content, "modulate:a", 1.0, RISE_TIME)
	_tween.parallel().tween_property(_content, "position:y", 0.0, RISE_TIME)
	_focus_default()


## Closes the popup (the menu behind sharpens again). `animate = false` hides it at once.
func close(animate: bool = true) -> void:
	if not is_open:
		return
	is_open = false
	_confirm.hide()
	_set_interactive(false)
	if animate:
		_animate(0.0, CLOSE_TIME)
		_tween.parallel().tween_property(_content, "modulate:a", 0.0, CLOSE_TIME)
		_tween.tween_callback(hide)
	else:
		if _tween:
			_tween.kill()
		_blur_material.set_shader_parameter(&"amount", 0.0)
		hide()
	closed.emit()


func has_saves() -> bool:
	return _saves.visible


func get_cards() -> Array[SaveCard]:
	var cards: Array[SaveCard] = []
	for child in _cards.get_children():
		if child is SaveCard and not child.is_queued_for_deletion():
			cards.append(child)
	return cards


func get_start_button() -> Button:
	return _start_list if has_saves() else _start_empty


## Focus on the newest save, else the first used slot, else START NEW CAMPAIGN
func _focus_default() -> void:
	var cards: Array[SaveCard] = get_cards()
	var best: SaveCard = null
	for card in cards:
		if card.info.is_readable() and (best == null or card.info.saved_at > best.info.saved_at):
			best = card
	for card in cards:
		if best == null and not card.info.is_empty():
			best = card
	if best:
		best.grab_focus()
	else:
		get_start_button().grab_focus()


func _populate() -> void:
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	var slots: Array[SaveSlotInfo] = SaveIndex.list_saves() if load_only else SaveIndex.list_slots()
	var any: bool = slots.any(func(info: SaveSlotInfo) -> bool: return not info.is_empty())
	_no_save.visible = not any
	_saves.visible = any
	_load_chip.visible = any
	_start_empty.visible = not load_only
	_start_list.visible = not load_only
	if not any:
		_lock_focus(_start_empty, null, null)
		return
	var cards: Array[SaveCard] = []
	for info in slots:
		var card := SaveCard.new()
		card.load_only = load_only
		card.setup(info)
		card.activated.connect(_on_card_activated.bind(info))
		card.delete_confirmed.connect(_on_delete_confirmed.bind(info.slot_id))
		card.focus_entered.connect(_keep_in_view.bind(card))
		_cards.add_child(card)
		cards.append(card)
	# Up/down walk the cards, then START NEW CAMPAIGN; focus never leaves the popup
	var last: Control = null if load_only else _start_list
	for i in cards.size():
		_lock_focus(cards[i], cards[i - 1] if i > 0 else null,
			cards[i + 1] if i + 1 < cards.size() else last)
	if last:
		_lock_focus(_start_list, cards[-1], null)
	var n: int = cards.size()
	var list_height: float = n * SaveCard.SIZE.y + (n - 1) * CARD_GAP + 2.0 * LIST_MARGIN
	_scroll.custom_minimum_size.y = minf(list_height, MAX_LIST_HEIGHT)
	_scroll.scroll_vertical = 0


## Sets a control's focus neighbours; null keeps it where it is
func _lock_focus(control: Control, up: Control, down: Control) -> void:
	var here: NodePath = NodePath(".")
	control.focus_neighbor_left = here
	control.focus_neighbor_right = here
	control.focus_neighbor_top = control.get_path_to(up) if up else here
	control.focus_neighbor_bottom = control.get_path_to(down) if down else here
	control.focus_previous = control.focus_neighbor_top
	control.focus_next = control.focus_neighbor_bottom


## Scrolls just enough to show the card with its brackets and glow (ScrollContainer.follow_focus
## stops at the card's edge and would cut them off)
func _keep_in_view(card: SaveCard) -> void:
	var top: float = card.position.y
	var bottom: float = card.position.y + card.size.y + 2.0 * LIST_MARGIN
	if top < _scroll.scroll_vertical:
		_scroll.scroll_vertical = int(top)
	elif bottom > _scroll.scroll_vertical + _scroll.size.y:
		_scroll.scroll_vertical = ceili(bottom - _scroll.size.y)


func _on_card_activated(info: SaveSlotInfo) -> void:
	if not is_open:
		return
	if load_only and SaveIndex.has_unsaved_progress():
		_confirm_message.text = "Load Slot %d (%s, %s)?\nProgress since your last save will be lost." % [
			SaveIndex.slot_number(info.slot_id), info.mission_title, SaveIndex.format_date(info.saved_at)]
		_confirm_ok.text = "LOAD"
		_confirm_load_slot = info.slot_id
		_confirm_replace_slot = ""
		_show_confirm()
		return
	if info.is_empty():
		SaveIndex.start_new_campaign(info.slot_id)
	elif not SaveIndex.load_slot(info.slot_id):
		_populate()
		_focus_default()


func _on_delete_confirmed(slot_id: String) -> void:
	if not is_open:
		return
	var index: int = SaveIndex.SLOT_IDS.find(slot_id)
	SaveIndex.delete_slot(slot_id)
	AudioManager.play_ui(&"back")
	_populate()
	var cards: Array[SaveCard] = get_cards()
	if index >= 0 and index < cards.size():
		cards[index].grab_focus()
	else:
		_focus_default()


func _on_start_pressed() -> void:
	if not is_open or is_confirming():
		return
	var slot: SaveSlotInfo = SaveIndex.read_slot(SaveIndex.new_campaign_slot())
	if slot.is_empty():
		SaveIndex.start_new_campaign()
		return
	var what: String = "an unreadable save" if not slot.is_readable() \
		else "%s, %s" % [slot.mission_title, SaveIndex.format_date(slot.saved_at)]
	_confirm_message.text = "All save slots are in use.\nStarting a new campaign replaces Slot %d (%s)." % [
		SaveIndex.slot_number(slot.slot_id), what]
	_confirm_ok.text = "REPLACE SLOT %d" % SaveIndex.slot_number(slot.slot_id)
	_confirm_replace_slot = slot.slot_id
	_confirm_load_slot = ""
	_show_confirm()


func _show_confirm() -> void:
	_confirm_return = get_viewport().gui_get_focus_owner() as Control
	_content.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	_content.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	_confirm.show()
	_confirm_cancel.grab_focus()


func is_confirming() -> bool:
	return _confirm.visible


func get_confirm_buttons() -> Array[Button]:
	return [_confirm_ok, _confirm_cancel]


func _close_confirm() -> void:
	_confirm.hide()
	_set_interactive(is_open)
	if is_open and is_instance_valid(_confirm_return):
		_confirm_return.grab_focus()


func _on_confirm_ok() -> void:
	if is_open and is_confirming():
		_confirm.hide()
		if _confirm_load_slot:
			if not SaveIndex.load_slot(_confirm_load_slot):
				_set_interactive(true)
				_populate()
				_focus_default()
			return
		SaveIndex.start_new_campaign(_confirm_replace_slot)


func _build_confirm() -> void:
	_confirm = Control.new()
	_confirm.name = "Confirm"
	_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.visible = false
	add_child(_confirm)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm.add_child(center)
	var panel := FramedPanel.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 30)
	margin.add_child(box)
	_confirm_message = Label.new()
	_confirm_message.name = "Message"
	_confirm_message.theme_type_variation = &"LabelBody"
	_confirm_message.add_theme_font_size_override(&"font_size", 22)
	_confirm_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_confirm_message)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	_confirm_ok = SolidButton.new()
	_confirm_ok.name = "ConfirmOk"
	_confirm_ok.pressed.connect(_on_confirm_ok)
	row.add_child(_confirm_ok)
	_confirm_cancel = SolidButton.new()
	_confirm_cancel.name = "ConfirmCancel"
	_confirm_cancel.text = "CANCEL"
	_confirm_cancel.pressed.connect(func() -> void:
		AudioManager.play_ui(&"back")
		_close_confirm())
	row.add_child(_confirm_cancel)
	_confirm_ok.focus_neighbor_right = _confirm_ok.get_path_to(_confirm_cancel)
	_confirm_cancel.focus_neighbor_left = _confirm_cancel.get_path_to(_confirm_ok)
	for button in [_confirm_ok, _confirm_cancel]:
		button.focus_neighbor_top = NodePath(".")
		button.focus_neighbor_bottom = NodePath(".")
	_confirm_ok.focus_neighbor_left = NodePath(".")
	_confirm_cancel.focus_neighbor_right = NodePath(".")


## While closed (or closing) nothing in the popup takes the mouse or focus
func _set_interactive(on: bool) -> void:
	_blur.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	_content.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED if on else Control.MOUSE_BEHAVIOR_DISABLED
	_content.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED if on else Control.FOCUS_BEHAVIOR_DISABLED


func _animate(blur_to: float, duration: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(false)
	_tween.set_ignore_time_scale(true)
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_method(func(v: float) -> void: _blur_material.set_shader_parameter(&"amount", v),
		float(_blur_material.get_shader_parameter(&"amount")), blur_to, duration)
