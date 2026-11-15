class_name CutsceneScreen

extends UIScreen

## What a CutsceneDirector draws over its camera: letterbox bars (2.39:1, bg colour), a black
## cover for title cards and fades, the title card (Michroma mission title + Exo 2 caption), a
## caption line in the top bar, the subtitles in the bottom bar and the hold-to-skip key with its
## fill line. Built in code; UIManager adds it under the pause menu. The title and its caption
## shrink (size and letter spacing together) to fit between the safe margins; the subtitles show
## one line at a time, centred in the bottom bar, which grows if a line needs more room.

const THEME: Theme = preload("res://res/ui_theme_v2.tres")
const SUBTITLE_STACK: PackedScene = preload("res://src/ui/subtitle_stack/subtitle_stack.tscn")
const ASPECT: float = 2.39
const BAR_TIME: float = 0.6
const UNFADE_TIME: float = 0.4
const BG := Color("#050507")
const TEXT := Color("#ECE9E3")
const TEXT_2 := Color("#C9C4BB")
const LINE := Color("#2A2A2E")
const SIDE: float = 64.0
const SKIP_WIDTH: float = 168.0
const SKIP_IDLE_ALPHA: float = 0.45
## Safe margin each side: a share of the width, at least SIDE
const SAFE_SHARE: float = 0.05
const CAPTION_SIZE: int = 24
const SUBTITLE_MAX_WIDTH: float = 960.0
const SUBTITLE_MIN_WIDTH: float = 360.0
const SUBTITLE_PAD: float = 14.0
## The bottom bar never grows past this share of the height for a line
const MAX_BAR_SHARE: float = 0.3
const STEADY_FRAMES: int = 3

var root: Control
var top_bar: ColorRect
var bottom_bar: ColorRect
var black: ColorRect
var title_label: Label
var title_caption: Label
var caption: Label
var skip_box: VBoxContainer
var skip_fill: ColorRect
var subtitle_slot: Control
var subtitles: SubtitleStack
## 0 (no bars) to 1 (full letterbox)
var bars: float = 0.0
var letterbox: bool = true
var _bar_tween: Tween = null
var _black_tween: Tween = null
var _bar_need: float = 0.0
var _fitted: Dictionary = {}
var _bases: Dictionary = {}
var _last_height: float = 0.0
var _steady: int = 0


func _init() -> void:
	name = "CutsceneScreen"
	add_to_group(&"cutscene_screen")


func _ready() -> void:
	root = Control.new()
	root.name = "Root"
	root.theme = THEME
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	black = _rect("Black", BG)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	top_bar = _rect("TopBar", BG)
	bottom_bar = _rect("BottomBar", BG)

	var title_box := VBoxContainer.new()
	title_box.name = "Title"
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.add_theme_constant_override(&"separation", 28)
	title_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(title_box)
	title_label = _label("TitleText", &"LabelMissionTitle")
	title_box.add_child(title_label)
	title_caption = _label("TitleCaption", &"LabelCaption")
	title_caption.add_theme_color_override(&"font_color", TEXT_2)
	title_caption.add_theme_font_size_override(&"font_size", CAPTION_SIZE)
	title_box.add_child(title_caption)

	caption = _label("Caption", &"LabelCaption")
	caption.add_theme_color_override(&"font_color", TEXT_2)
	caption.add_theme_font_size_override(&"font_size", 20)
	root.add_child(caption)

	subtitle_slot = Control.new()
	subtitle_slot.name = "SubtitleSlot"
	subtitle_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(subtitle_slot)
	subtitles = SUBTITLE_STACK.instantiate()
	subtitles.slot = subtitle_slot
	subtitles.backing = false
	subtitles.skip_hint = false
	root.add_child(subtitles)

	skip_box = VBoxContainer.new()
	skip_box.name = "Skip"
	skip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skip_box.add_theme_constant_override(&"separation", 10)
	root.add_child(skip_box)
	var chip := KeyChip.new()
	chip.fallback_key = "Space"
	chip.action = &"cutscene_skip"
	chip.label_text = "Hold to skip"
	skip_box.add_child(chip)
	var track := _rect("Track", LINE, skip_box)
	track.custom_minimum_size = Vector2(SKIP_WIDTH, 2.0)
	skip_fill = _rect("Fill", TEXT, track)
	skip_fill.size = Vector2(0.0, 2.0)
	hide()


func _process(_delta: float) -> void:
	if visible:
		_layout()


func _layout() -> void:
	var view: Vector2 = root.get_viewport_rect().size
	var margin: float = safe_margin(view.x)
	_fit(title_label, &"LabelMissionTitle", -1, view.x - 2.0 * margin)
	_fit(title_caption, &"LabelCaption", CAPTION_SIZE, view.x - 2.0 * margin)
	skip_box.reset_size()
	var width: float = subtitle_width(view.x)
	var text_height: float = subtitles.size.y if subtitles.visible and subtitles.shown_count() > 0 else 0.0
	# Only once the line is wrapped at the band's width and its height has settled (the first
	# frames can report it wrapped narrower)
	_steady = _steady + 1 if text_height == _last_height and absf(subtitles.size.x - minf(width, subtitles.MAX_WIDTH)) < 1.0 else 0
	_last_height = text_height
	if text_height > 0.0 and _steady >= STEADY_FRAMES:
		_bar_need = clampf(text_height + 2.0 * SUBTITLE_PAD, _bar_need, view.y * MAX_BAR_SHARE)
	var full: float = maxf(maxf((view.y - view.x / ASPECT) * 0.5, view.y * 0.1), _bar_need)
	var bar: float = full * bars
	top_bar.position = Vector2.ZERO
	top_bar.size = Vector2(view.x, bar)
	bottom_bar.position = Vector2(0.0, view.y - bar)
	bottom_bar.size = Vector2(view.x, bar)
	caption.position = Vector2(0.0, maxf(bar * 0.5 - caption.size.y * 0.5, 24.0))
	caption.size = Vector2(view.x, caption.size.y)
	var bar_top: float = view.y - maxf(bar, full)
	subtitle_slot.position = Vector2((view.x - width) * 0.5, bar_top + (full - text_height) * 0.5)
	subtitle_slot.size = Vector2(width, 0.0)
	skip_box.position = Vector2(view.x - SIDE - skip_box.size.x,
		view.y - maxf(full, skip_box.size.y + 32.0) * 0.5 - skip_box.size.y * 0.5)


## Shows the screen: the bars slide in (or stay out without `with_letterbox`), nothing else shown
func begin(with_letterbox: bool) -> void:
	letterbox = with_letterbox
	_bar_need = 0.0
	show()
	set_title("", "", 0.0, 0.0)
	set_caption("")
	set_skip(0.0, false)
	_kill(_black_tween)
	black.color.a = 0.0
	_tween_bars(1.0 if with_letterbox else 0.0)
	_layout()


## Bars out, black (from a skip) faded away, then hidden; `instant` hides at once
func finish(instant: bool) -> void:
	set_title("", "", 0.0, 0.0)
	set_caption("")
	set_skip(0.0, false)
	if instant:
		_kill(_bar_tween)
		_kill(_black_tween)
		bars = 0.0
		hide()
		return
	if black.color.a > 0.0:
		fade_black(0.0, UNFADE_TIME)
	_tween_bars(0.0).tween_callback(hide)


func set_black(alpha: float) -> void:
	if _black_tween and _black_tween.is_running():
		return
	black.color.a = alpha


func fade_black(alpha: float, seconds: float) -> Tween:
	_kill(_black_tween)
	_black_tween = create_ui_tween()
	_black_tween.tween_property(black, "color:a", alpha, seconds)
	return _black_tween


func set_title(text: String, caption_text: String, text_alpha: float, caption_alpha: float) -> void:
	title_label.text = text
	title_caption.text = caption_text
	title_label.modulate.a = text_alpha
	title_caption.modulate.a = caption_alpha


func set_caption(text: String) -> void:
	caption.text = text
	caption.visible = not text.is_empty()


## The skip line's fill (0 to 1); brighter while the key is held
func set_skip(progress: float, holding: bool) -> void:
	skip_fill.size = Vector2(SKIP_WIDTH * progress, 2.0)
	skip_box.modulate.a = 1.0 if holding else SKIP_IDLE_ALPHA


func safe_margin(width: float) -> float:
	return maxf(SIDE, width * SAFE_SHARE)


## The subtitle band's width: centred, clear of the skip key on the right
func subtitle_width(width: float) -> float:
	return clampf(width - 2.0 * (SIDE + skip_box.size.x + 32.0), SUBTITLE_MIN_WIDTH, SUBTITLE_MAX_WIDTH)


## The bottom bar's rect when fully in
func bottom_bar_rect() -> Rect2:
	var view: Vector2 = root.get_viewport_rect().size
	var full: float = maxf(maxf((view.y - view.x / ASPECT) * 0.5, view.y * 0.1), _bar_need)
	return Rect2(0.0, view.y - full, view.x, full)


## Sizes `label` (its theme type's font and size, or `base_size`) down, size and letter spacing
## together, until its text fits `room` pixels
func _fit(label: Label, type: StringName, base_size: int, room: float) -> void:
	var key := "%s|%d" % [label.text, roundi(room)]
	if _fitted.get(label) == key:
		return
	_fitted[label] = key
	if not _bases.has(label):
		_bases[label] = [THEME.get_font(&"font", type), base_size if base_size > 0 else THEME.get_font_size(&"font_size", type)]
	var base: Font = _bases[label][0]
	var size: int = _bases[label][1]
	var spacing: int = base.spacing_glyph if base is FontVariation else 0
	var font: Font = base
	var fitted: int = size
	if not label.text.is_empty():
		var width: float = base.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var scale: float = minf(room / maxf(width, 1.0), 1.0)
		fitted = floori(size * scale)
		if scale < 1.0 and base is FontVariation:
			font = base.duplicate()
			font.spacing_glyph = floori(spacing * scale)
		while fitted > 8 and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x > room:
			fitted -= 1
	label.add_theme_font_override(&"font", font)
	label.add_theme_font_size_override(&"font_size", fitted)


func _tween_bars(target: float) -> Tween:
	_kill(_bar_tween)
	_bar_tween = create_ui_tween()
	_bar_tween.tween_property(self, "bars", target, maxf(BAR_TIME * absf(target - bars), 0.01))
	return _bar_tween


func _kill(tween: Tween) -> void:
	if tween:
		tween.kill()


func _rect(node_name: String, color: Color, parent: Node = null) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent else root).add_child(rect)
	return rect


func _label(node_name: String, variation: StringName) -> Label:
	var label := Label.new()
	label.name = node_name
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
