class_name PartTooltip

extends PanelContainer

## Small panel next to the crosshair describing what it's on: a part (loose or mounted: name,
## what it does, where it mounts, stats), an empty socket (what goes there) or any other
## InteractTrigger (just its prompt). Names and descriptions come from PartCatalog, stats from
## the part; the E prompt line comes from the trigger (or says what E does with a loose part),
## with the interact key the player bound (InputBindings.with_current_keys).
## Used by the player HUD and the robot HUD; hidden while Settings > General > Show Tooltips is off.

const OFFSET: Vector2 = Vector2(36.0, 28.0)
const COLOR_DIM := Color(0.8, 0.84, 0.9, 0.75)
const COLOR_STATS := Color(0.55, 0.85, 1.0)
const COLOR_PROMPT := Color(1.0, 0.85, 0.4)

var _title: Label
var _description: Label
var _mounts: Label
var _stats: Label
var _prompt: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.08, 0.78)
	style.border_color = Color(0.55, 0.8, 1.0, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 2)
	add_child(lines)
	_title = _line(lines, 26, Color.WHITE)
	_description = _line(lines, 18, Color.WHITE)
	_mounts = _line(lines, 18, COLOR_DIM)
	_stats = _line(lines, 18, COLOR_STATS)
	_prompt = _line(lines, 18, COLOR_PROMPT)
	hide()


func _line(parent: Node, size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
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


func _set_line(label: Label, text: String) -> void:
	label.text = text
	label.visible = not text.is_empty()
