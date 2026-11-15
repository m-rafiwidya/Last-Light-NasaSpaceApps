extends SceneTree
## Renders the trailer's on-screen text as 1920x1080 transparent PNGs (needs a window):
##     Godot --path game --resolution 640x360 -s res://tools/trailer/render_text.gd -- out=<dir>
## caption_<i>.png, voice_<i>.png, title.png (transparent) and title_card.png (on black).

const TIMELINE: String = "res://tools/trailer/timeline.json"
const SIZE := Vector2i(1920, 1080)
const EXO_400: String = "res://res/fonts/exo-2-latin-400-normal.woff2"
const EXO_500: String = "res://res/fonts/exo-2-latin-500-normal.woff2"
const EXO_600: String = "res://res/fonts/exo-2-latin-600-normal.woff2"
const MICHROMA: String = "res://res/fonts/michroma-latin-400-normal.woff2"
const WHITE := Color(1.0, 1.0, 1.0)
const SOFT := Color(0.86, 0.89, 0.93)
const DIM := Color(0.70, 0.75, 0.82)

var out: String = ""
var viewport: SubViewport


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out = arg.trim_prefix("out=")
	DirAccess.make_dir_recursive_absolute(out)
	var timeline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TIMELINE))
	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var captions: Array = timeline["captions"]
	for i in captions.size():
		var box := _column(float(captions[i].get("y", 0.78)), 0.0)
		box.add_child(_label(captions[i]["text"], EXO_600, int(timeline.get("caption_size", 62)), WHITE, 1.0, 1800))
		await _save(box, "caption_%d.png" % i)

	var voices: Array = timeline["voice"]
	for i in voices.size():
		var box := _column(0.78, 0.0)
		var text := RichTextLabel.new()
		text.bbcode_enabled = true
		text.fit_content = true
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(1700, 0)
		text.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		text.add_theme_font_override("normal_font", load(EXO_600))
		text.add_theme_font_size_override("normal_font_size", 58)
		text.add_theme_color_override("default_color", WHITE)
		_shadow(text, "font_shadow_color", "shadow_offset_x", "shadow_offset_y", "shadow_outline_size")
		text.text = "[center][font=%s][color=#%s]%s[/color][/font]   %s[/center]" % [EXO_400, SOFT.to_html(false), voices[i]["speaker"], voices[i]["text"]]
		box.add_child(text)
		await _save(box, "voice_%d.png" % i)

	var lines: Array = timeline["title"]["lines"]
	var styles: Array = [[MICHROMA, 150, WHITE, 10], [EXO_500, 54, WHITE, 2], [EXO_400, 38, SOFT, 1]]
	for opaque in [false, true]:
		var box := _column(0.5, 0.0)
		box.add_theme_constant_override("separation", 26)
		for k in lines.size():
			var style: Array = styles[mini(k, styles.size() - 1)]
			box.add_child(_label(lines[k], style[0], style[1], style[2], 1.0, 1800, style[3]))
		var back: ColorRect = null
		if opaque:
			back = ColorRect.new()
			back.color = Color(0.0196, 0.0196, 0.0275)
			back.size = SIZE
			viewport.add_child(back)
			viewport.move_child(back, 0)
		await _save(box, "title_card.png" if opaque else "title.png", false)
		if back:
			back.queue_free()
	print("TRAILER text done: ", out)
	quit()


## A centred column whose middle sits at `y` (fraction of the height); `anchor` 0 grows downward
func _column(y: float, _anchor: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size = Vector2(SIZE.x, 0)
	box.position = Vector2(0, SIZE.y * y)
	box.set_meta("y", y)
	return box


func _label(text: String, font: String, size: int, color: Color, alpha: float, width: int, spacing: int = 0) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(width, 0)
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var variation := FontVariation.new()
	variation.base_font = load(font)
	variation.spacing_glyph = spacing
	label.add_theme_font_override("font", variation)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(color, alpha))
	_shadow(label, "font_shadow_color", "shadow_offset_x", "shadow_offset_y", "shadow_outline_size")
	return label


func _shadow(control: Control, color: String, x: String, y: String, outline: String) -> void:
	control.add_theme_color_override(color, Color(0.0, 0.0, 0.0, 0.55))
	control.add_theme_constant_override(x, 0)
	control.add_theme_constant_override(y, 3)
	control.add_theme_constant_override(outline, 14)


func _save(box: VBoxContainer, file: String, band: bool = true) -> void:
	viewport.add_child(box)
	await process_frame
	box.size = Vector2(SIZE.x, 0)
	await process_frame
	box.position.y = SIZE.y * float(box.get_meta("y")) - box.size.y * 0.5
	var shade: TextureRect = null
	if band:
		shade = _band(box.position.y + box.size.y * 0.5, box.size.y + 150.0)
		viewport.add_child(shade)
		viewport.move_child(shade, box.get_index())
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(out.path_join(file))
	box.queue_free()
	if shade:
		shade.queue_free()
	await process_frame


## A full-width soft dark band centred at `y`, `height` tall, so text reads on bright regolith
func _band(y: float, height: float) -> TextureRect:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.42, 0.58, 1.0])
	gradient.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	texture.width = 4
	texture.height = 256
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.position = Vector2(0, y - height * 0.5)
	rect.size = Vector2(SIZE.x, height)
	return rect
