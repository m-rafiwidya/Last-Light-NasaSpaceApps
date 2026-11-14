class_name CampaignResult

extends UIScreen

const DONE_COLOR: String = "#3d8f4f"
const SKIPPED_COLOR: String = "#7a7a7a"

var fade_tween: Tween = null


func _ready() -> void:
	add_to_group(&"campaign_result")
	%Window.modulate.a = 0.0
	%Continue.pressed.connect(_on_continue_pressed)
	%MainMenu.pressed.connect(_on_main_menu_pressed)
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
	var lines: PackedStringArray = ["[b]Missions completed  %d / %d[/b]" % [data["missions"].size(), CampaignState.mission_order().size()]]
	for mission in data["missions"]:
		lines.append("[color=%s]✓  %s  %s[/color]" % [DONE_COLOR, mission.to_upper(), CampaignState.mission_title(mission)])
	lines.append("\n[b]Optional tasks[/b]")
	for objective in data["optional_done"]:
		lines.append("[color=%s]✓  %s[/color]" % [DONE_COLOR, _optional_title(objective)])
	for objective in data["optional_skipped"]:
		lines.append("[color=%s]○  %s  (skipped)[/color]" % [SKIPPED_COLOR, _optional_title(objective)])
	if data["optional_done"].is_empty() and data["optional_skipped"].is_empty():
		lines.append("None")
	lines.append("\n[b]Play time[/b]  %s" % SaveIndex.format_play_time(data["play_time_sec"]))
	lines.append("[b]Emergency recoveries[/b]  %d" % data["recoveries"])
	var ending := CampaignState.mission_ending(CampaignState.last_mission())
	lines.append("\n[i]%s[/i]" % ending.get("next_assignment", ""))
	%Title.text = "[b][i]Field assignment complete[/i][/b]"
	%Summary.text = "\n".join(lines)
	hide_caption()
	show()
	_fade_to(1.0)
	%Continue.grab_focus()


func is_open() -> bool:
	return visible and %Window.modulate.a > 0.0


func show_caption(text: String) -> void:
	%Caption.text = text
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


func _on_main_menu_pressed() -> void:
	SceneLoader.load_scene(SceneLoader.MAIN_MENU_ID)


func _fade_to(alpha: float) -> Tween:
	if fade_tween:
		fade_tween.kill()
	fade_tween = create_ui_tween()
	fade_tween.tween_property(%Window, "modulate:a", alpha, FADE_DURATION)
	return fade_tween
