extends SceneTree

## Checks the v2 UI components: focus_mode ALL on interactive ones, the underline grows on focus
## exactly as on hover (left and centre variants), the key chip reads the InputMap, and the
## theme variations exist. Run:
##   Godot --headless --fixed-fps 240 --path game -s res://tests/test_ui_components.gd

var _failures: Array[String] = []


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var gallery: Node = load("res://src/ui/components/ui_gallery.tscn").instantiate()
	root.add_child(gallery)
	await process_frame
	await process_frame

	var buttons: Array[Node] = gallery.find_children("*", "Button", true, false)
	for b in buttons:
		_check((b as Control).focus_mode == Control.FOCUS_ALL, "focus_mode ALL on %s" % b.name)

	var theme: Theme = load("res://res/ui_theme_v2.tres")
	for v in ["UnderlineButton", "UnderlineButtonMenu", "UnderlineButtonPrimary", "SolidButton",
			"SolidButtonSmall", "SlantedTab", "BackButton"]:
		_check(theme.get_type_variation_base(v) == &"Button", "variation " + v)
	for v in ["SettingsKeySlab", "SettingsKeySlabListening", "UnderlineButtonPause"]:
		_check(theme.get_type_variation_base(v) in [&"Button", &"SettingsKeySlab"], "variation " + v)
	_check(theme.get_type_variation_base("SettingsSelect") == &"OptionButton", "variation SettingsSelect")
	_check(theme.get_type_variation_base("SettingsSlider") == &"HSlider", "variation SettingsSlider")
	for v in ["KeyChipPanel", "FramedPanel", "CardPanel", "SettingsRow"]:
		_check(theme.get_type_variation_base(v) == &"PanelContainer", "variation " + v)

	for centre in [false, true]:
		var scene := "res://src/ui/components/underline_button%s.tscn" % ("_centre" if centre else "")
		var by_hover := _make_underline(scene)
		var by_focus := _make_underline(scene)
		await process_frame
		_check(by_hover._fraction == 0.0 and by_focus._fraction == 0.0, "underline starts empty")
		by_hover.mouse_entered.emit()
		by_focus.grab_focus()
		await create_timer(0.6, true, false, true).timeout
		_check(is_equal_approx(by_hover._fraction, 1.0), "hover grows underline (centre=%s)" % centre)
		_check(is_equal_approx(by_focus._fraction, 1.0), "focus grows underline (centre=%s)" % centre)
		_check(by_hover._underline.position.is_equal_approx(by_focus._underline.position)
				and by_hover._underline.size.is_equal_approx(by_focus._underline.size),
				"hover and focus underline identical (centre=%s)" % centre)
		by_focus.release_focus()
		by_hover.mouse_exited.emit()
		await create_timer(0.6, true, false, true).timeout
		_check(is_equal_approx(by_focus._fraction, 0.0), "underline shrinks on blur")

	var chip := load("res://src/ui/components/key_chip.tscn").instantiate() as KeyChip
	root.add_child(chip)
	chip.action = &"ui_cancel"
	_check(chip.key_text() == "Esc", "ui_cancel shows Esc, got '%s'" % chip.key_text())
	chip.action = &"interact_use"
	_check(chip.key_text() == "E", "interact_use shows E, got '%s'" % chip.key_text())
	InputMap.action_erase_events(&"interact_use")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F
	InputMap.action_add_event(&"interact_use", ev)
	chip.refresh()
	_check(chip.key_text() == "F", "rebound key shows F, got '%s'" % chip.key_text())

	if _failures.is_empty():
		print("RESULT test_ui_components PASS")
	else:
		print("RESULT test_ui_components FAIL: ", _failures)
	quit(0 if _failures.is_empty() else 1)


func _make_underline(scene: String) -> UnderlineButton:
	var b := load(scene).instantiate() as UnderlineButton
	b.text = "SETTINGS"
	root.add_child(b)
	b.position = Vector2(100, 100 + 100 * root.get_child_count())
	return b
