class_name SlantedSelect

extends OptionButton

## Light slanted select slab with a chevron (settings rows). The drop-down list is the theme's
## PopupMenu. Long labels are trimmed with an ellipsis instead of widening the slab; the list
## shows them whole. Hover and focus look the same (pure white).

## Slab size: 300 x 30 design px x 1.2
const SIZE: Vector2 = Vector2(360.0, 36.0)
## Chevron from the design SVG (24 viewBox drawn at 12 px, path M5 9l7 7 7-7), x 1.2
const CHEVRON: PackedVector2Array = [Vector2(3.0, 5.4), Vector2(7.2, 9.6), Vector2(11.4, 5.4)]
const CHEVRON_STROKE: float = 1.44
## Right edge of the chevron's box from the slab's right edge (18 px x 1.2) and its size
const CHEVRON_INSET: float = 21.6
const CHEVRON_BOX: float = 14.4

static var _no_arrow: ImageTexture


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	theme_type_variation = &"SettingsSelect"
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	clip_text = true
	fit_to_longest_item = false
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	custom_minimum_size = SIZE
	# The chevron is drawn below; the theme's own arrow is replaced by an empty picture
	if _no_arrow == null:
		_no_arrow = ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8))
	add_theme_icon_override(&"arrow", _no_arrow)


func _draw() -> void:
	var origin := Vector2(size.x - CHEVRON_INSET - CHEVRON_BOX, (size.y - CHEVRON_BOX) / 2.0)
	var points := PackedVector2Array()
	for p in CHEVRON:
		points.append(origin + p)
	draw_polyline(points, get_theme_color(&"ink", &"UIColor"), CHEVRON_STROKE, true)
