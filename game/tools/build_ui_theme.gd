## Builds res/ui_theme_v2.tres from the tokens in docs/ui/UI_SPEC.md. The designs are drawn at
## 1600 x 900 and the project runs at 1920 x 1080, so every size is multiplied by SCALE (1.2).
## Run from the repo root:
##   Godot --headless --path game -s res://tools/build_ui_theme.gd
## Edit the tokens here and re-run; do not hand-edit the .tres.
extends SceneTree

const SCALE: float = 1.2
const OUT_PATH: String = "res://res/ui_theme_v2.tres"

const MICHROMA = "res://res/fonts/michroma-latin-400-normal.woff2"
const EXO_400 = "res://res/fonts/exo-2-latin-400-normal.woff2"
const EXO_500 = "res://res/fonts/exo-2-latin-500-normal.woff2"
const EXO_600 = "res://res/fonts/exo-2-latin-600-normal.woff2"
const PLEX_MONO = "res://res/fonts/IBMPlexMono-Regular.ttf"
const PLEX_MONO_500 = "res://res/fonts/ibm-plex-mono-latin-500-normal.woff2"

# Colour tokens (UI_SPEC "Design tokens"). Stored on the "UIColor" theme type, read with
# get_theme_color("text", "UIColor")
const COLORS: Dictionary = {
	"bg": Color("050507"),
	"text": Color("ECE9E3"),
	"text_2": Color("C9C4BB"),
	"text_3": Color("B5B2AC"),
	"muted": Color("8A8783"),
	"dim": Color("6B6863"),
	"disabled": Color("4A4844"),
	"ink": Color("141417"),
	"panel": Color("1B1B1F"),
	"panel_hover": Color("26262B"),
	"line": Color("1E1E22"),
	"line_2": Color("1C1C20"),
	"line_3": Color("2A2A2E"),
	"warn": Color("E5484D"),
	"white": Color("FFFFFF"),
	"moon": Color("C9C4BB"),
	"mars": Color("C8643A"),
	"earth": Color("4C8FD6"),
}

var _fonts: Dictionary = {}
var theme: Theme = Theme.new()


func _init() -> void:
	var c: Dictionary = COLORS
	theme.default_font = _font(EXO_500, 0)
	theme.default_font_size = _px(17)

	for key in c:
		theme.set_color(key, "UIColor", c[key])

	_labels(c)
	_buttons(c)
	_panels(c)

	var err: int = ResourceSaver.save(theme, OUT_PATH)
	print("saved ", OUT_PATH, " err=", err)
	quit(err)


func _px(v: float) -> int:
	return roundi(v * SCALE)


## FontVariation over `path` with letter-spacing `spacing` (already in design px, scaled here)
func _font(path: String, spacing: float) -> FontVariation:
	var key: String = "%s|%d" % [path, _px(spacing)]
	if _fonts.has(key):
		return _fonts[key]
	var fv := FontVariation.new()
	fv.base_font = load(path)
	fv.spacing_glyph = _px(spacing)
	_fonts[key] = fv
	return fv


func _label(variation: String, path: String, size: float, spacing: float, color: Color) -> void:
	theme.set_type_variation(variation, "Label")
	theme.set_font("font", variation, _font(path, spacing))
	theme.set_font_size("font_size", variation, _px(size))
	theme.set_color("font_color", variation, color)


func _labels(c: Dictionary) -> void:
	theme.set_color("font_color", "Label", c.text)
	_label("LabelGameTitle", MICHROMA, 40, 22, c.text)
	_label("LabelScreenTitle", MICHROMA, 26, 16, c.text)
	_label("LabelMissionTitle", MICHROMA, 44, 20, c.text)
	_label("LabelLoadingFact", MICHROMA, 30, 1, c.text)
	theme.set_constant("line_spacing", "LabelLoadingFact", _px(30 * 0.55))
	_label("LabelHeading", MICHROMA, 13, 6, c.text_2)
	_label("LabelEyebrow", MICHROMA, 11, 5, c.muted)
	_label("LabelBody", EXO_500, 17, 0, c.text)
	_label("LabelBodyStrong", EXO_600, 17, 0, c.text)
	_label("LabelCaption", EXO_500, 13, 0, c.muted)
	_label("LabelDidYouKnow", EXO_600, 22, 0, c.text)
	_label("LabelMono", PLEX_MONO, 12, 1, c.text_2)
	_label("LabelMonoMedium", PLEX_MONO_500, 12, 1, c.text_2)
	# Opening sequence's "TANDBORSTE PRESENTS" (its spacing is animated from 4 to 14)
	_label("LabelPresents", PLEX_MONO, 13, 6, c.text_3)


func _flat(color: Color, slant: float = 0.0, height: float = 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.anti_aliasing = true
	sb.anti_aliasing_size = 0.5
	if slant > 0.0:
		# Horizontal shift between the top and bottom edge = skew.x * height. The slant is a
		# fixed pixel value, so it only holds at the height the component is built with.
		sb.skew = Vector2(slant * SCALE / (height * SCALE), 0.0)
		# StyleBoxFlat skews around the vertical middle, so the shape overhangs the control by
		# half the slant on each side; pull the box in so it stays inside its rect like the
		# design's clip-path
		sb.expand_margin_left = -slant * SCALE / 2.0
		sb.expand_margin_right = -slant * SCALE / 2.0
	return sb


func _margins(sb: StyleBox, h: float, v: float = 0.0) -> void:
	sb.content_margin_left = h * SCALE
	sb.content_margin_right = h * SCALE
	sb.content_margin_top = v * SCALE
	sb.content_margin_bottom = v * SCALE


func _button_base(variation: String, path: String, size: float, spacing: float) -> void:
	theme.set_type_variation(variation, "Button")
	theme.set_font("font", variation, _font(path, spacing))
	theme.set_font_size("font_size", variation, _px(size))
	theme.set_constant("outline_size", variation, 0)
	# Components draw their own focus look; the focus box is overridden where needed
	theme.set_stylebox("focus", variation, StyleBoxEmpty.new())


func _button_colors(variation: String, normal: Color, hover: Color, disabled: Color) -> void:
	theme.set_color("font_color", variation, normal)
	theme.set_color("font_hover_color", variation, hover)
	theme.set_color("font_hover_pressed_color", variation, hover)
	theme.set_color("font_focus_color", variation, hover)
	theme.set_color("font_pressed_color", variation, hover)
	theme.set_color("font_disabled_color", variation, disabled)


func _buttons(c: Dictionary) -> void:
	# Underline buttons: no box at all, the component draws the underline
	var underline: Array = [
		["UnderlineButtonMenu", 18, 10, c.muted],
		["UnderlineButton", 15, 7, c.muted],
		["UnderlineButtonPrimary", 12, 5, c.text],
	]
	for u in underline:
		_button_base(u[0], MICHROMA, u[1], u[2])
		_button_colors(u[0], u[3], c.text, c.disabled)
		for state in ["normal", "hover", "pressed", "disabled"]:
			theme.set_stylebox(state, u[0], StyleBoxEmpty.new())

	# SKIP (opening sequence, credits): small mono text, dim, lights up on hover/focus
	_button_base("SkipButton", PLEX_MONO, 12, 4)
	_button_colors("SkipButton", c.dim, c.text, c.disabled)
	var skip := StyleBoxEmpty.new()
	_margins(skip, 12, 10)
	for state in ["normal", "hover", "pressed", "disabled"]:
		theme.set_stylebox(state, "SkipButton", skip)

	# Solid slanted buttons: [variation, font size, spacing, height, slant, h padding]
	var solid: Array = [
		["SolidButton", 13, 5, 48.0, 12.0, 38.0],
		["SolidButtonSmall", 11, 4, 36.0, 10.0, 22.0],
	]
	for s in solid:
		var v: String = s[0]
		_button_base(v, MICHROMA, s[1], s[2])
		_button_colors(v, c.ink, c.ink, c.dim)
		var normal := _flat(c.text, s[4], s[3])
		var hover := _flat(c.white, s[4], s[3])
		# Hover lifts 1 px: the box grows up and the label is nudged up by the same amount
		hover.expand_margin_top = 1.0 * SCALE
		var disabled := _flat(c.panel, s[4], s[3])
		_margins(normal, s[5])
		_margins(hover, s[5])
		hover.content_margin_bottom = 2.0 * SCALE
		_margins(disabled, s[5])
		theme.set_stylebox("normal", v, normal)
		theme.set_stylebox("hover", v, hover)
		theme.set_stylebox("pressed", v, hover)
		theme.set_stylebox("focus", v, hover)
		theme.set_stylebox("disabled", v, disabled)

	# Slanted tabs (same font as the small solid button)
	_button_base("SlantedTab", MICHROMA, 11, 4)
	_button_colors("SlantedTab", c.muted, c.text, c.disabled)
	var tab_n := _flat(c.panel, 10.0, 36.0)
	var tab_h := _flat(c.panel_hover, 10.0, 36.0)
	_margins(tab_n, 22)
	_margins(tab_h, 22)
	theme.set_stylebox("normal", "SlantedTab", tab_n)
	theme.set_stylebox("hover", "SlantedTab", tab_h)
	theme.set_stylebox("pressed", "SlantedTab", tab_h)
	theme.set_stylebox("focus", "SlantedTab", tab_h)
	theme.set_stylebox("disabled", "SlantedTab", tab_n)

	theme.set_type_variation("SlantedTabActive", "SlantedTab")
	_button_colors("SlantedTabActive", c.ink, c.ink, c.ink)
	var tab_on := _flat(c.text, 10.0, 36.0)
	_margins(tab_on, 22)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		theme.set_stylebox(state, "SlantedTabActive", tab_on)

	# Back button: 48 x 48, 1 px #2A2A2E border; hover/focus border muted. The component draws
	# the chevron.
	_button_base("BackButton", MICHROMA, 12, 0)
	var back_n := _outline(c.line_3)
	var back_h := _outline(c.muted)
	theme.set_stylebox("normal", "BackButton", back_n)
	theme.set_stylebox("hover", "BackButton", back_h)
	theme.set_stylebox("pressed", "BackButton", back_h)
	theme.set_stylebox("focus", "BackButton", back_h)
	theme.set_stylebox("disabled", "BackButton", back_n)


func _outline(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = color
	sb.set_border_width_all(1)
	return sb


func _panels(c: Dictionary) -> void:
	# Key chip: 22 px high parallelogram, slant 5
	theme.set_type_variation("KeyChipPanel", "PanelContainer")
	var chip := _flat(c.text, 5.0, 22.0)
	chip.content_margin_left = (7.0 + 5.0) * SCALE
	chip.content_margin_right = (7.0 + 5.0) * SCALE
	chip.content_margin_top = 0
	chip.content_margin_bottom = 0
	theme.set_stylebox("panel", "KeyChipPanel", chip)
	_label("LabelKeyChip", EXO_600, 12, 0, c.ink)
	_label("LabelKeyAction", EXO_500, 13, 0, c.text_3)

	# Framed popup / selected card: black 78 %, 1 px border text @ 85 %, soft glow
	theme.set_type_variation("FramedPanel", "PanelContainer")
	var framed := StyleBoxFlat.new()
	framed.bg_color = Color(0, 0, 0, 0.78)
	framed.border_color = Color(c.text.r, c.text.g, c.text.b, 0.85)
	framed.set_border_width_all(1)
	framed.shadow_color = Color(c.text.r, c.text.g, c.text.b, 0.12)
	framed.shadow_size = _px(18)
	theme.set_stylebox("panel", "FramedPanel", framed)

	# Unselected card: 1 px #2A2A2E, no glow, no brackets
	theme.set_type_variation("CardPanel", "PanelContainer")
	var card := StyleBoxFlat.new()
	card.bg_color = Color(0, 0, 0, 0.72)
	card.border_color = c.line_3
	card.set_border_width_all(1)
	theme.set_stylebox("panel", "CardPanel", card)
