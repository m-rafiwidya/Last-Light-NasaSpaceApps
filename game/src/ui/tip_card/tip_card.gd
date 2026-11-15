class_name TipCard

extends PanelContainer
## The HUD's "New control" card (UI_SPEC, bottom-right): a caption and one key chip per control,
## shown once per campaign (CampaignState tips), the moment a HUD offers it. It fades out after
## DURATION seconds, or LINGER seconds after every control was used, and never takes input.

const UI_THEME: Theme = preload("res://res/ui_theme_v2.tres")
const DURATION: float = 10.0
const LINGER: float = 1.2
const FADE_IN: float = 0.4
const FADE_OUT: float = 0.5
const LOOK_DISTANCE: float = 150.0
const MARGIN: Vector2 = Vector2(53.0, 48.0)
const GAP: float = 24.0
const USED_ALPHA: float = 0.4
const MOVE: Array = [&"move_forward", &"move_left", &"move_backward", &"move_right"]
## Per tip: rows of {label, actions (keys read from the bindings) or key (fixed text)}
const TIPS: Dictionary = {
	&"on_foot": [
		{"label": "Move", "actions": MOVE},
		{"label": "Look", "key": "Mouse"},
		{"label": "Interact", "actions": [&"interact_use"]},
	],
	&"drive": [
		{"label": "Drive", "actions": MOVE},
		{"label": "Camera view", "actions": [&"camera_next"]},
		{"label": "Reset upright", "actions": [&"robot_reset"]},
		{"label": "Headlights", "actions": [&"lights"]},
	],
}

var tip: StringName = &""
var age: float = 0.0
var used: Array[bool] = []
var _end: float = DURATION
var _look: float = 0.0
var _rows: VBoxContainer = VBoxContainer.new()
var _chips: Array[KeyChip] = []
var _row_nodes: Array[Control] = []
## Kept clear of: the card lifts above it when they would meet
var avoid: Control


func _init() -> void:
	name = "TipCard"
	theme = UI_THEME
	theme_type_variation = &"TipCardPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	minimum_size_changed.connect(_place)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_theme_constant_override(&"separation", 8)
	add_child(_rows)
	var caption := Label.new()
	caption.theme_type_variation = &"LabelEyebrow"
	caption.text = "NEW CONTROL"
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_child(caption)
	hide()


func _ready() -> void:
	InputBindings.events.changed.connect(_refresh_keys)
	CampaignState.campaign_reset.connect(dismiss)


## Shows `id` unless it was shown before in this campaign or another tip is up
func offer(id: StringName) -> void:
	if visible or not TIPS.has(id) or CampaignState.is_tip_shown(id):
		return
	CampaignState.mark_tip_shown(id)
	tip = id
	age = 0.0
	_end = DURATION
	_look = 0.0
	used.clear()
	for row: Control in _row_nodes:
		row.queue_free()
	_row_nodes.clear()
	_chips.clear()
	for row: Dictionary in TIPS[id]:
		var chip := KeyChip.new()
		chip.label_text = row["label"]
		chip.alignment = BoxContainer.ALIGNMENT_BEGIN
		_rows.add_child(chip)
		_chips.append(chip)
		_row_nodes.append(chip)
		used.append(false)
	_refresh_keys()
	modulate.a = 0.0
	show()
	_place()


func dismiss() -> void:
	if visible:
		hide()
		tip = &""


func _refresh_keys() -> void:
	if tip == &"":
		return
	var rows: Array = TIPS[tip]
	for i in rows.size():
		var row: Dictionary = rows[i]
		_chips[i].fallback_key = row["key"] if row.has("key") else InputBindings.keys_text(row["actions"])
		_chips[i].refresh()
	_place()


## Pins the card's bottom-right corner to the screen corner and sizes it to its content, so it grows
## up and left; above `avoid` when that is in the way
func _place() -> void:
	var need: Vector2 = get_combined_minimum_size()
	var area: Vector2 = get_parent_area_size()
	var bottom: float = -MARGIN.y
	if avoid and avoid.is_visible_in_tree() and avoid.size.y > 0.0:
		var stack: Rect2 = avoid.get_global_rect()
		if stack.end.x + GAP > area.x - MARGIN.x - need.x:
			bottom = minf(bottom, stack.position.y - GAP - area.y)
	bottom = maxf(bottom, need.y - area.y)
	offset_right = -MARGIN.x
	offset_left = offset_right - need.x
	offset_bottom = bottom
	offset_top = bottom - need.y


func _input(event: InputEvent) -> void:
	if visible and event is InputEventMouseMotion:
		_look += (event as InputEventMouseMotion).relative.length()


func _process(delta: float) -> void:
	if not visible:
		return
	age += delta
	_place()
	var rows: Array = TIPS[tip]
	for i in rows.size():
		var row: Dictionary = rows[i]
		if not used[i]:
			used[i] = (row["actions"] as Array).any(Input.is_action_just_pressed) if row.has("actions") else _look >= LOOK_DISTANCE
			if used[i]:
				_chips[i].modulate.a = USED_ALPHA
	if not used.has(false):
		_end = minf(_end, age + LINGER)
	modulate.a = clampf(minf(age / FADE_IN, (_end - age) / FADE_OUT), 0.0, 1.0)
	if age >= _end:
		dismiss()
