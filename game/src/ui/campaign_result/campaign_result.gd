class_name CampaignResult

extends UIScreen

## The campaign's end (Complete.dc.html, centred like Pause): label, title, rule, one-line result,
## four stats, the missions and optional tasks, the closing radio line, CONTINUE / MAIN MENU.

var fade_tween: Tween = null


func _ready() -> void:
	add_to_group(&"campaign_result")
	%Window.modulate.a = 0.0
	%Rule.color = %Window.get_theme_color(&"text", &"UIColor")
	%Continue.pressed.connect(_on_continue_pressed)
	%MainMenu.pressed.connect(_on_main_menu_pressed)
	%DataSources.pressed.connect(open_data_sources)
	GameState.state_changed.connect(_on_state_changed)
	hide_caption()
	hide()


func summary() -> Dictionary:
	var missions: PackedStringArray = []
	var optional_done: PackedStringArray = []
	var optional_skipped: PackedStringArray = []
	for mission in CampaignState.mission_order():
		if not CampaignState.is_mission_completed(mission):
			continue
		missions.append(mission)
		var required := CampaignState.mission_objectives(mission)
		for objective in CampaignState.mission_objectives(mission, true):
			if objective in required:
				continue
			if CampaignState.is_objective_done(objective):
				optional_done.append(objective)
			else:
				optional_skipped.append(objective)
	return {
		"missions": missions,
		"optional_done": optional_done,
		"optional_skipped": optional_skipped,
		"play_time_sec": int(CampaignState.play_time_sec),
		"recoveries": CampaignState.recoveries,
	}


func open() -> void:
	var data := summary()
	var optional_total: int = data["optional_done"].size() + data["optional_skipped"].size()
	_set_stats([["%d / %d" % [data["missions"].size(), CampaignState.mission_order().size()], "Missions completed"],
		["%d / %d" % [data["optional_done"].size(), optional_total], "Optional tasks"],
		[SaveIndex.format_play_time(data["play_time_sec"]), "Play time"],
		[str(data["recoveries"]), "Emergency recoveries"]])
	var lines: PackedStringArray = []
	for mission in data["missions"]:
		lines.append("[color=%s]%s  ·  %s[/color]" % [_hex(&"text"), mission.to_upper(), CampaignState.mission_title(mission)])
	for objective in data["optional_done"]:
		lines.append(_optional_title(objective))
	for objective in data["optional_skipped"]:
		lines.append("[color=%s][s]%s[/s]  (skipped)[/color]" % [_hex(&"dim"), _optional_title(objective)])
	var ending := CampaignState.mission_ending(CampaignState.last_mission())
	lines.append("\n[color=%s]%s[/color]" % [_hex(&"muted"), ending.get("next_assignment", "")])
	%Summary.text = "\n".join(lines)
	var closing: Array = ending.get("lines", [])
	var last: Dictionary = closing[-1] if not closing.is_empty() else {}
	%Speaker.text = str(last.get("speaker", "Control")).to_upper()
	%RadioLine.text = last.get("text", "")
	%Speaker.get_parent().visible = %RadioLine.text != ""
	%Result.text = "Every mission is complete." if CampaignState.is_campaign_complete() else "The field assignment is over."
	hide_caption()
	show()
	_fade_to(1.0)
	%Continue.grab_focus()


func _hex(token: StringName) -> String:
	return "#" + %Window.get_theme_color(token, &"UIColor").to_html(false)


## Value over caption, split by thin dividers
func _set_stats(stats: Array) -> void:
	for child in %Stats.get_children():
		child.queue_free()
	for i in stats.size():
		var cell := VBoxContainer.new()
		cell.custom_minimum_size.x = 228.0
		cell.add_theme_constant_override(&"separation", 10)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for item in [[stats[i][0], &"LabelStatValue"], [stats[i][1], &"LabelStatCaption"]]:
			var label := Label.new()
			label.text = item[0]
			label.theme_type_variation = item[1]
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.add_child(label)
		if i > 0:
			var divider := ColorRect.new()
			divider.custom_minimum_size.x = 1.0
			divider.color = %Window.get_theme_color(&"rule_2", &"UIColor")
			divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
			%Stats.add_child(divider)
		%Stats.add_child(cell)


## The stat cells' texts, value then caption, for the tests
func stat_texts() -> Array:
	var texts: Array = []
	for cell in %Stats.get_children():
		if cell is VBoxContainer:
			texts.append([cell.get_child(0).text, cell.get_child(1).text])
	return texts


func is_open() -> bool:
	return visible and %Window.modulate.a > 0.0


func show_caption(text: String) -> void:
	%CaptionText.text = text
	%Caption.visible = true
	show()


func hide_caption() -> void:
	%Caption.visible = false


func fade_out() -> void:
	hide_caption()
	if not visible:
		return
	_fade_to(0.0).tween_callback(hide)


func _optional_title(objective: String) -> String:
	return CampaignState.objective_title(objective).trim_prefix("Optional: ")


func _on_state_changed(_old_state, new_state) -> void:
	if new_state != GameState.State.IN_GAME_MENU:
		fade_out()


func _on_continue_pressed() -> void:
	if GameState.state == GameState.State.IN_GAME_MENU:
		GameState.change_state_to(GameState.State.IN_GAME_PLAYER)


func open_data_sources() -> void:
	var screen := get_tree().get_first_node_in_group(&"data_sources") as DataSourcesScreen
	if screen:
		screen.open()


func _on_main_menu_pressed() -> void:
	SceneLoader.load_scene(SceneLoader.MAIN_MENU_ID)


func _fade_to(alpha: float) -> Tween:
	if fade_tween:
		fade_tween.kill()
	fade_tween = create_ui_tween()
	fade_tween.tween_property(%Window, "modulate:a", alpha, FADE_DURATION)
	return fade_tween
