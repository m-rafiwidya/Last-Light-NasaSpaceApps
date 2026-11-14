class_name SpacedLabel

extends Control

## One line of text with a float letter-spacing that can be animated smoothly.
## FontVariation.spacing_glyph is whole pixels, so animating it moves every letter in 1 px steps
## and the last one by as many pixels as there are letters before it: the text visibly jumps.
## Here the text is shaped once without spacing and each letter is drawn at its own float offset
## (through the canvas transform, so it isn't snapped to a pixel). Font, size and colour come from
## a Label theme type variation; that variation's own letter-spacing is ignored.

@export var text: String = "":
	set(value):
		text = value
		_reshape()
## Label theme type variation to take the font, size and colour from
@export var label_variation: StringName = &"Label":
	set(value):
		label_variation = value
		_reshape()
## Extra space after every letter in px, like CSS letter-spacing (the trailing one included)
@export var letter_spacing: float = 0.0:
	set(value):
		letter_spacing = value
		queue_redraw()
## Spacing the minimum size is computed with, so animating letter_spacing doesn't move the
## layout. Negative: use letter_spacing.
@export var layout_spacing: float = -1.0:
	set(value):
		layout_spacing = value
		update_minimum_size()
@export var horizontal_alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT:
	set(value):
		horizontal_alignment = value
		queue_redraw()

var _line: TextLine = null
var _glyphs: Array[Dictionary] = []
var _clusters: int = 0
var _width: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_reshape()


func _reshape() -> void:
	if not is_inside_tree():
		return
	var font: Font = get_theme_font(&"font", label_variation)
	if font is FontVariation and (font as FontVariation).spacing_glyph != 0:
		font = (font as FontVariation).duplicate()
		(font as FontVariation).spacing_glyph = 0
	_line = TextLine.new()
	_line.add_string(text, font, get_theme_font_size(&"font_size", label_variation))
	_glyphs.assign(TextServerManager.get_primary_interface().shaped_text_get_glyphs(_line.get_rid()))
	_clusters = 0
	_width = 0.0
	for glyph in _glyphs:
		if glyph["count"] > 0:
			_clusters += 1
		_width += glyph["advance"] * glyph["repeat"]
	update_minimum_size()
	queue_redraw()


func text_width(spacing: float) -> float:
	return _width + spacing * _clusters


func _get_minimum_size() -> Vector2:
	if _line == null:
		return Vector2.ZERO
	var spacing: float = layout_spacing if layout_spacing >= 0.0 else letter_spacing
	return Vector2(ceilf(text_width(spacing)), ceilf(_line.get_size().y))


func _draw() -> void:
	if _line == null:
		return
	var ts: TextServer = TextServerManager.get_primary_interface()
	var color: Color = get_theme_color(&"font_color", label_variation)
	var x: float = 0.0
	match horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			x = (size.x - text_width(letter_spacing)) / 2.0
		HORIZONTAL_ALIGNMENT_RIGHT:
			x = size.x - text_width(letter_spacing)
	var baseline: float = roundf((size.y - _line.get_size().y) / 2.0 + _line.get_line_ascent())
	var cluster: int = -1
	var canvas: RID = get_canvas_item()
	for glyph in _glyphs:
		if glyph["count"] > 0:
			cluster += 1
		var offset: Vector2 = glyph["offset"]
		# The float part of the position goes into the transform; the glyph is drawn at whole pixels
		draw_set_transform(Vector2(x + offset.x + letter_spacing * cluster, 0.0))
		for r in glyph["repeat"]:
			ts.font_draw_glyph(glyph["font_rid"], canvas, glyph["font_size"],
				Vector2(r * glyph["advance"], baseline + offset.y), glyph["index"], color)
		x += glyph["advance"] * glyph["repeat"]
	draw_set_transform(Vector2.ZERO)
