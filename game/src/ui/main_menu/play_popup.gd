class_name PlayPopup

extends Control

## The main menu's PLAY popup (docs/ui/UI_SPEC.md "Main menu", board Main.dc.html, design
## x 1.2). Opening it blurs and dims everything drawn before it (the starfield, the Moon, the
## menu column) and its full-screen blur takes the mouse. The owner turns the menu's own input
## off while it is open.
## - No saves: "There's no save file." and START NEW CAMPAIGN.
## - Saves: "Select save data to load.", the save cards newest first (SaveIndex.list_saves()),
##   then START NEW CAMPAIGN. Up/down move between cards, Enter or click loads. A long list
##   scrolls to keep the selected card in view.
## Esc or the back button closes it; `closed` is emitted as it starts closing.

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

var _tween: Tween
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
	var cards: Array[SaveCard] = get_cards()
	if cards.is_empty():
		_start_empty.grab_focus()
	else:
		cards[0].grab_focus()


## Closes the popup (the menu behind sharpens again). `animate = false` hides it at once.
func close(animate: bool = true) -> void:
	if not is_open:
		return
	is_open = false
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


func _populate() -> void:
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	var saves: Array[SaveSlotInfo] = SaveIndex.list_saves()
	_no_save.visible = saves.is_empty()
	_saves.visible = not saves.is_empty()
	_load_chip.visible = not saves.is_empty()
	if saves.is_empty():
		_lock_focus(_start_empty, null, null)
		return
	var cards: Array[SaveCard] = []
	for info in saves:
		var card := SaveCard.new()
		card.setup(info)
		card.activated.connect(_on_card_activated.bind(info.slot_id))
		card.focus_entered.connect(_keep_in_view.bind(card))
		_cards.add_child(card)
		cards.append(card)
	# Up/down walk the cards, then START NEW CAMPAIGN; focus never leaves the popup
	for i in cards.size():
		_lock_focus(cards[i], cards[i - 1] if i > 0 else null,
			cards[i + 1] if i + 1 < cards.size() else _start_list)
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


func _on_card_activated(slot_id: String) -> void:
	if is_open:
		SaveIndex.load_slot(slot_id)


func _on_start_pressed() -> void:
	if is_open:
		SaveIndex.start_new_campaign()


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
