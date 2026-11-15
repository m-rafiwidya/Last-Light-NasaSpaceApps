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
	# Settings key-bind slab while it waits for a key (Settings.dc.html .ll-key.is-listen)
	"key_listen": Color("3A3A40"),
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
	_planet_explorer(c)

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
	# Settings: title, a slider's value, the "(next level load)" note
	_label("LabelSettingsTitle", MICHROMA, 18, 10, c.text)
	_label("LabelMonoValue", PLEX_MONO, 12, 1, c.text)
	_label("LabelMonoNote", PLEX_MONO, 11, 1, c.dim)
	# Opening sequence's "TANDBORSTE PRESENTS" (its spacing is animated from 4 to 14)
	_label("LabelPresents", PLEX_MONO, 13, 6, c.text_3)
	# Loading screen: stage text and percentage
	_label("LabelLoadingStage", PLEX_MONO, 12, 5, c.text_3)
	_label("LabelLoadingPercent", PLEX_MONO, 12, 3, c.muted)
	# In-game guidance text (tracker, rover mission hint, waypoint and world labels): Exo 2, light
	# text and greys; only the alert is red
	_label("LabelHudObjective", EXO_600, 15, 0, c.text_2)
	_label("LabelHudStep", EXO_600, 18, 0, c.text)
	_label("LabelHudStuck", EXO_500, 14, 0, c.text_3)
	_label("LabelHudAlert", EXO_600, 17, 0, c.warn)
	_label("LabelHudWorld", EXO_600, 14, 0, c.text)
	# Radio subtitle body (RichTextLabel); the speaker above it is LabelEyebrow (Michroma 11, muted)
	theme.set_type_variation("RichSubtitle", "RichTextLabel")
	theme.set_font("normal_font", "RichSubtitle", _font(EXO_500, 0))
	theme.set_font("bold_font", "RichSubtitle", _font(EXO_600, 0))
	theme.set_font("italics_font", "RichSubtitle", _font(EXO_500, 0))
	theme.set_font("bold_italics_font", "RichSubtitle", _font(EXO_600, 0))
	theme.set_color("default_color", "RichSubtitle", c.text)


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

	# Pause menu items (Pause.dc.html .ll-pc): centred, so the label gets the board's 6 px of left
	# padding, which balances the trailing letter-spacing and centres the letters
	_button_base("UnderlineButtonPause", MICHROMA, 15, 6)
	_button_colors("UnderlineButtonPause", c.muted, c.text, c.disabled)
	var pause_item := StyleBoxEmpty.new()
	pause_item.content_margin_left = 6.0 * SCALE
	for state in ["normal", "hover", "pressed", "disabled"]:
		theme.set_stylebox(state, "UnderlineButtonPause", pause_item)

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

	_settings_controls(c)

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


## Settings controls: the light select slab, the key-bind slab, the slider, the select's popup
func _settings_controls(c: Dictionary) -> void:
	# Select (.ll-sel): 30 px high slab, Plex Mono 12, 18 px left and 36 px right padding (the
	# chevron sits there). Hover and focus go pure white like the other light slabs.
	var sel := "SettingsSelect"
	_button_base(sel, PLEX_MONO, 12, 0)
	theme.set_type_variation(sel, "OptionButton")
	_button_colors(sel, c.ink, c.ink, c.dim)
	theme.set_constant("h_separation", sel, 0)
	theme.set_constant("arrow_margin", sel, 0)
	var sel_n := _flat(c.text, 10.0, 30.0)
	var sel_h := _flat(c.white, 10.0, 30.0)
	var sel_d := _flat(c.panel, 10.0, 30.0)
	for sb in [sel_n, sel_h, sel_d]:
		sb.content_margin_left = 18.0 * SCALE
		sb.content_margin_right = 36.0 * SCALE
		sb.content_margin_top = 0.0
		sb.content_margin_bottom = 0.0
	theme.set_stylebox("normal", sel, sel_n)
	theme.set_stylebox("hover", sel, sel_h)
	theme.set_stylebox("pressed", sel, sel_h)
	theme.set_stylebox("focus", sel, sel_h)
	theme.set_stylebox("disabled", sel, sel_d)

	# Key-bind slab (.ll-key): Michroma 11, spacing 3; while listening the slab goes #3A3A40 and
	# the label turns into Plex Mono 11, spacing 4
	var key := "SettingsKeySlab"
	_button_base(key, MICHROMA, 11, 3)
	_button_colors(key, c.ink, c.ink, c.dim)
	var key_n := _flat(c.text, 10.0, 30.0)
	var key_h := _flat(c.white, 10.0, 30.0)
	for sb in [key_n, key_h]:
		_margins(sb, 12)
	theme.set_stylebox("normal", key, key_n)
	theme.set_stylebox("hover", key, key_h)
	theme.set_stylebox("pressed", key, key_h)
	theme.set_stylebox("focus", key, key_h)
	theme.set_stylebox("disabled", key, key_n)
	var listen := "SettingsKeySlabListening"
	_button_base(listen, PLEX_MONO, 11, 4)
	theme.set_type_variation(listen, key)
	_button_colors(listen, c.text, c.text, c.text)
	var key_l := _flat(c.key_listen, 10.0, 30.0)
	_margins(key_l, 12)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		theme.set_stylebox(state, listen, key_l)

	# Slider: a thin track, filled up to a round knob; the knob goes white on hover and focus
	var slider := "SettingsSlider"
	theme.set_type_variation(slider, "HSlider")
	var track := StyleBoxFlat.new()
	track.bg_color = c.dim
	track.set_corner_radius_all(_px(3))
	track.content_margin_top = 2.5 * SCALE
	track.content_margin_bottom = 2.5 * SCALE
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = c.text_2
	var fill_lit := track.duplicate() as StyleBoxFlat
	fill_lit.bg_color = c.text
	theme.set_stylebox("slider", slider, track)
	theme.set_stylebox("grabber_area", slider, fill)
	theme.set_stylebox("grabber_area_highlight", slider, fill_lit)
	theme.set_icon("grabber", slider, _knob(c.text))
	theme.set_icon("grabber_highlight", slider, _knob(c.white, c.muted))
	theme.set_icon("grabber_disabled", slider, _knob(c.dim))

	# One settings row: a 1 px divider under it
	theme.set_type_variation("SettingsRow", "PanelContainer")
	var row := StyleBoxFlat.new()
	row.draw_center = false
	row.border_color = c.line_2
	row.border_width_bottom = 1
	theme.set_stylebox("panel", "SettingsRow", row)

	# The select's drop-down list
	var panel := StyleBoxFlat.new()
	panel.bg_color = c.panel
	panel.border_color = c.line_3
	panel.set_border_width_all(1)
	panel.set_content_margin_all(6.0 * SCALE)
	var hover := StyleBoxFlat.new()
	hover.bg_color = c.text
	theme.set_stylebox("panel", "PopupMenu", panel)
	theme.set_stylebox("hover", "PopupMenu", hover)
	theme.set_font("font", "PopupMenu", _font(PLEX_MONO, 0))
	theme.set_font_size("font_size", "PopupMenu", _px(12))
	theme.set_color("font_color", "PopupMenu", c.text_2)
	theme.set_color("font_hover_color", "PopupMenu", c.ink)
	theme.set_color("font_disabled_color", "PopupMenu", c.dim)
	theme.set_constant("v_separation", "PopupMenu", _px(8))
	theme.set_constant("item_start_padding", "PopupMenu", _px(12))
	theme.set_constant("item_end_padding", "PopupMenu", _px(12))


## The slider's knob: a filled circle (16 design px) with a one-pixel soft edge, in a 22 px square.
## With `ring` set (keyboard / gamepad focus) a thin ring is drawn round it.
func _knob(color: Color, ring: Color = Color(0, 0, 0, 0)) -> GradientTexture2D:
	var clear := Color(color.r, color.g, color.b, 0.0)
	var offsets := PackedFloat32Array([0.0, 0.70, 0.74, 1.0])
	var colors := PackedColorArray([color, color, clear, clear])
	if ring.a > 0.0:
		var ring_clear := Color(ring.r, ring.g, ring.b, 0.0)
		offsets = PackedFloat32Array([0.0, 0.70, 0.74, 0.84, 0.88, 0.96, 1.0])
		colors = PackedColorArray([color, color, clear, ring_clear, ring, ring, ring_clear])
	var gradient := Gradient.new()
	gradient.offsets = offsets
	gradient.colors = colors
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = _px(22)
	tex.height = _px(22)
	return tex


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

	# HUD text backing: plain black at 55 %, so light text stays readable over bright terrain. The
	# flush one has no padding (the subtitle stack's boxes bring their own)
	for variation in ["HudBacking", "HudBackingFlush"]:
		theme.set_type_variation(variation, "PanelContainer")
		var backing := StyleBoxFlat.new()
		backing.bg_color = Color(0, 0, 0, 0.55)
		if variation == "HudBacking":
			backing.content_margin_left = 14.0 * SCALE
			backing.content_margin_right = 14.0 * SCALE
			backing.content_margin_top = 9.0 * SCALE
			backing.content_margin_bottom = 9.0 * SCALE
		theme.set_stylebox("panel", variation, backing)

	# "New control" / "Tip" card (HUD board): ink at 70 %, 2 px left rule in text
	theme.set_type_variation("TipCardPanel", "PanelContainer")
	var tip := StyleBoxFlat.new()
	tip.bg_color = Color(c.ink.r, c.ink.g, c.ink.b, 0.7)
	tip.border_color = c.text
	tip.border_width_left = 2
	tip.content_margin_left = 18.0 * SCALE
	tip.content_margin_right = 18.0 * SCALE
	tip.content_margin_top = 12.0 * SCALE
	tip.content_margin_bottom = 12.0 * SCALE
	theme.set_stylebox("panel", "TipCardPanel", tip)

	# Unselected card: 1 px #2A2A2E, no glow, no brackets
	theme.set_type_variation("CardPanel", "PanelContainer")
	var card := StyleBoxFlat.new()
	card.bg_color = Color(0, 0, 0, 0.72)
	card.border_color = c.line_3
	card.set_border_width_all(1)
	theme.set_stylebox("panel", "CardPanel", card)


## Planet explorer (menu globe): title, tabs, the locked-planet text and the site tooltip card.
## planet_explorer.tscn uses these variations; without them the labels fall back to the default
## font and the card loses its panel.
func _planet_explorer(c: Dictionary) -> void:
	_label("LabelPlanetTitle", MICHROMA, 26, 12, c.text)
	_label("LabelPlanetSubtitle", EXO_500, 12, 4, c.muted)
	# Shown over a locked planet, and the line under it
	_label("LabelLocked", MICHROMA, 16, 8, c.text_3)
	_label("LabelLockHint", EXO_500, 12, 2, c.muted)

	# Tooltip card: the green badge, the site name (wraps), the key / value rows, the note
	_label("LabelTipBadge", EXO_500, 11, 3, Color("3FB950"))
	_label("LabelTipName", MICHROMA, 17, 3, c.text)
	_label("LabelTipKey", EXO_500, 12, 0, c.muted)
	_label("LabelTipValue", EXO_500, 12, 0, c.text)
	_label("LabelTipNote", EXO_500, 12, 0, c.text_3)
	theme.set_constant("line_spacing", "LabelTipNote", _px(7))

	# 1 px frame, near-black at 94 %, 20 x 18 px of padding
	theme.set_type_variation("TipPanel", "PanelContainer")
	var tip := StyleBoxFlat.new()
	tip.bg_color = Color("0A0A0D", 0.94)
	tip.border_color = Color("34343A")
	tip.set_border_width_all(1)
	tip.content_margin_left = 20.0 * SCALE
	tip.content_margin_right = 20.0 * SCALE
	tip.content_margin_top = 18.0 * SCALE
	tip.content_margin_bottom = 18.0 * SCALE
	theme.set_stylebox("panel", "TipPanel", tip)

	# Planet tabs: text only, the component draws the rest; lit while hovered, focused or active
	_button_base("PlanetTab", PLEX_MONO, 12, 4)
	theme.set_color("font_color", "PlanetTab", c.muted)
	for state in ["focus", "hover", "hover_pressed", "pressed"]:
		theme.set_color("font_%s_color" % state, "PlanetTab", c.text)
	var tab := StyleBoxEmpty.new()
	_margins(tab, 4, 10)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		theme.set_stylebox(state, "PlanetTab", tab)
