class_name PartTooltip

extends PanelContainer

## Small panel next to the crosshair describing what it's on: a part (loose or mounted: name,
## what it does, where it mounts, stats), an empty socket (what goes there) or any other
## InteractTrigger (just its prompt). Names and descriptions come from PartCatalog, stats from
## the part; the E prompt line comes from the trigger (or says what E does with a loose part),
## with the interact key the player bound (InputBindings.with_current_keys).
## Used by the player HUD and the robot HUD; hidden while Settings > General > Show Tooltips is off.

const OFFSET: Vector2 = Vector2(36.0, 28.0)
const GAP: float = 24.0

## Kept clear of this control (the subtitle stack): the panel moves up when they would meet
var avoid: Control = null

var _title: Label
var _description: Label
var _mounts: Label
var _stats: Label
var _prompt: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = preload("res://res/ui_theme_v2.tres")
	theme_type_variation = &"TipPanel"
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 4)
	add_child(lines)
	_title = _line(lines, &"LabelTipName")
	_description = _line(lines, &"LabelTooltipBody")
	_mounts = _line(lines, &"LabelTipKey")
	_stats = _line(lines, &"LabelTooltipStats")
	_prompt = _line(lines, &"LabelTooltipPrompt")
	hide()


func _line(parent: Node, variation: StringName) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	parent.add_child(label)
	return label


## Shows the panel for `target` (what the crosshair is on, or null). `on_foot` adds the
## take-out prompt for mounted parts; `holding` is true while `target` is the held object.
func show_for(target: Object, on_foot: bool, holding: bool) -> void:
	if not GeneralSettings.show_tooltips():
		hide()
		return
	var title := ""
	var description := ""
	var mounts := ""
	var stats := PackedStringArray()
	var prompt := ""
	var part: HotswapPart = null
	if target is HotswapPart:
		part = target
		prompt = 'Press "E" to drop, left click to throw' if holding else 'Press "E" to pick up'
	elif target is InteractTrigger:
		var socket := (target as Node).get_parent() as HotswapSocket
		if socket and socket.part:
			part = socket.part
			prompt = (target as InteractTrigger).tooltip if on_foot else ""
		elif socket:
			title = "Empty: %s goes here" % socket.get_accepted_name()
		else:
			prompt = (target as InteractTrigger).tooltip
	if part:
		title = part.get_display_name()
		description = part.get_description()
		mounts = part.get_mount_hint()
		stats = part.get_stat_lines()
	if title.is_empty() and prompt.is_empty():
		hide()
		return
	_set_line(_title, title)
	_set_line(_description, description)
	_set_line(_mounts, mounts)
	_set_line(_stats, "\n".join(stats))
	_set_line(_prompt, InputBindings.with_current_keys(prompt))
	show()
	reset_size()
	position = get_viewport_rect().size / 2.0 + OFFSET
	if avoid and avoid.is_visible_in_tree() and avoid.size.y > 0.0 and get_global_rect().intersects(avoid.get_global_rect()):
		position.y = avoid.get_global_rect().position.y - GAP - size.y


func _set_line(label: Label, text: String) -> void:
	label.text = text
	label.visible = not text.is_empty()
