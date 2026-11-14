extends UIScreen

const PANEL_IMAGE: Texture2D = preload("res://res/textures/dev/grey.png")
const ICONS: Array[Texture2D] = [preload("res://res/textures/dev/orange.png"),
	preload("res://res/textures/dev/grey.png"), preload("res://res/textures/dev/orange.png")]

enum Section {MISSION, KITE, DOWNLINK}
const SECTIONS: Array[String] = ["Mission", "Kite", "Downlink"]
const DOWNLINKS: Dictionary = {"m1": "m1.inspection_sent", "m3": "m3.archive_sent"}
const DOWNLINK_NAMES: Dictionary = {"m1": "inspection", "m3": "archive"}
const DOWNLINK_TIME: float = 2.5
const REFRESH_TIME: float = 0.25
const DONE_COLOR: String = "#3d8f4f"

var fade_tween: Tween = null
var section: Section = Section.MISSION
var _sending: float = -1.0
var _refresh: float = 0.0


func _ready() -> void:
	add_to_group(&"mission_console")
	%Window.modulate.a = 0.0
	%Close.pressed.connect(_on_close_pressed)
	%ItemList.item_selected.connect(_show_section)
	%ItemList.item_selected.connect(func(_index: int) -> void: AudioManager.play_ui(&"click"))
	%Action.pressed.connect(_on_action_pressed)
	%ControlKite.pressed.connect(_on_control_kite_pressed)
	var close_sound := ButtonSoundComponent.new()
	close_sound.press_sound = &""
	%Close.add_child(close_sound)
	%ItemList.clear()
	for i in SECTIONS.size():
		%ItemList.add_item(SECTIONS[i], ICONS[i])
	%ItemList.select(0)
	CampaignState.objective_completed.connect(func(_id: String) -> void: refresh())
	CampaignState.mission_started.connect(func(_id: String) -> void: refresh())
	CampaignState.mission_completed.connect(func(_id: String) -> void: refresh())
	refresh()
	hide()


func _process(delta: float) -> void:
	if _sending >= 0.0:
		_sending += delta
		if _sending >= DOWNLINK_TIME:
			_finish_downlink()
	if not visible:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		refresh()


func _show_section(index: int) -> void:
	section = index as Section
	refresh()


func select_section(value: Section) -> void:
	%ItemList.select(value)
	_show_section(value)


func refresh() -> void:
	_refresh = REFRESH_TIME
	for child in %Attachments.get_children():
		child.queue_free()
	match section:
		Section.MISSION:
			_show_mission()
		Section.KITE:
			_show_kite()
		Section.DOWNLINK:
			_show_downlink()
	_update_action()
	%DownlinkProgress.visible = _sending >= 0.0
	%DownlinkProgress.value = clampf(_sending / DOWNLINK_TIME, 0.0, 1.0)
	%ControlKite.disabled = _workshop() == null


func _show_mission() -> void:
	var mission := CampaignState.current_mission()
	if mission.is_empty():
		_set_text("No active mission", "Mission control has not assigned a mission yet.")
		return
	var lines: PackedStringArray = []
	var current := CampaignState.current_objective()
	var required := CampaignState.mission_objectives(mission)
	for objective in CampaignState.mission_objectives(mission, true):
		var title := CampaignState.objective_title(objective)
		if CampaignState.is_objective_done(objective):
			lines.append("[color=%s]✓  %s[/color]" % [DONE_COLOR, title])
		elif objective == current:
			lines.append("[b]›  %s[/b]" % title)
		else:
			lines.append("○  %s%s" % [title, "" if objective in required else "  (optional)"])
	if CampaignState.is_mission_completed(mission):
		lines.append("\n[b]Mission complete.[/b]")
	_set_text("%s  %s" % [mission.to_upper(), CampaignState.mission_title(mission)], "\n".join(lines))


func _show_kite() -> void:
	var workshop := _workshop()
	if workshop == null:
		_set_text("Kite", "No link to Kite.")
		return
	var rover: Robot = workshop.rover
	var lines: PackedStringArray = []
	if rover.battery:
		lines.append("Battery  %d%%" % floori(rover.battery.get_charge_fraction() * 100.0))
	else:
		lines.append("Battery  [color=red]none fitted[/color]: take the battery from the rack and drop it into the socket at Kite's rear")
	if workshop.pad and workshop.pad.rover == rover:
		lines.append("Dock  " + workshop.pad.get_status_text())
	else:
		lines.append("Dock  out, %d m from the pad" % roundi(workshop.pad.offset_of(rover).length() if workshop.pad else 0.0))
	var director := _director()
	if director:
		if director.recovering:
			lines.append("[color=red]%s[/color]" % director.alert)
		elif rover.battery and not workshop.pad.is_in_zone(rover):
			lines.append("Return needs about %d%%" % ceili(director.return_fraction_needed() * 100.0))
	var parts: PackedStringArray = []
	for socket in rover.find_children("*", "HotswapSocket", true, false):
		if socket.part:
			parts.append(socket.part.get_display_name())
	lines.append("\nFitted  " + (", ".join(parts) if parts else "nothing"))
	_set_text("Kite", "\n".join(lines))


func _show_downlink() -> void:
	var mission := CampaignState.current_mission()
	var objective: String = DOWNLINKS.get(mission, "")
	if objective.is_empty():
		_set_text("Downlink", "Nothing to send for this mission.")
		return
	var what: String = DOWNLINK_NAMES[mission]
	if _sending >= 0.0:
		_set_text("Downlink", "Sending the %s to Earth...  %d%%" % [what, floori(_sending / DOWNLINK_TIME * 100.0)])
	elif CampaignState.is_objective_done(objective):
		_set_text("Downlink: report received", CampaignState.mission_report(mission))
		var rect := TextureRect.new()
		rect.texture = PANEL_IMAGE
		rect.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
		%Attachments.add_child(rect)
	elif _downlink_ready(mission):
		_set_text("Downlink", "The %s is stored on the console and ready to send to Earth." % what)
	else:
		var waiting := CampaignState.current_objective()
		_set_text("Downlink", "Nothing to send yet. First: %s." % CampaignState.objective_title(waiting))


func _update_action() -> void:
	var mission := CampaignState.current_mission()
	var next := CampaignState.next_mission(mission)
	%Action.visible = true
	%Action.disabled = false
	if _sending >= 0.0:
		%Action.text = "Sending..."
		%Action.disabled = true
	elif not mission.is_empty() and CampaignState.is_mission_completed(mission) and next:
		%Action.text = "Start next mission: %s" % CampaignState.mission_title(next)
	elif section == Section.DOWNLINK and DOWNLINKS.has(mission) and not CampaignState.is_objective_done(DOWNLINKS[mission]):
		%Action.text = "Send %s" % DOWNLINK_NAMES[mission]
		%Action.disabled = not _downlink_ready(mission)
	else:
		%Action.visible = false


func _downlink_ready(mission: String) -> bool:
	var objective: String = DOWNLINKS.get(mission, "")
	return not objective.is_empty() and CampaignState.current_objective() == objective


func _on_action_pressed() -> void:
	var mission := CampaignState.current_mission()
	var next := CampaignState.next_mission(mission)
	if _sending >= 0.0:
		return
	if not mission.is_empty() and CampaignState.is_mission_completed(mission) and next:
		CampaignState.start_mission(next)
		select_section(Section.MISSION)
	elif _downlink_ready(mission):
		_sending = 0.0
		refresh()


func _finish_downlink() -> void:
	_sending = -1.0
	var mission := CampaignState.current_mission()
	if _downlink_ready(mission):
		CampaignState.complete_objective(DOWNLINKS[mission])
	refresh()


func _on_control_kite_pressed() -> void:
	var workshop := _workshop()
	if workshop and is_instance_valid(GameState.player):
		workshop.drive_from_console(GameState.player)


func _workshop() -> Workshop:
	if not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group(&"workshop"):
		if is_instance_valid(node.rover):
			return node
	return null


func _director() -> MissionDirector:
	return get_tree().get_first_node_in_group(&"mission_director") as MissionDirector if is_inside_tree() else null


func _set_text(title: String, body: String) -> void:
	%Title.text = "[b][i]%s[/i][/b]" % title
	%Description.text = body


func _on_close_pressed():
	if GameState.state == GameState.State.MISSION_CONSOLE:
		GameState.return_to_game()


func fade_in():
	refresh()
	show()
	_fade_to(1.0)


func fade_out():
	if not visible:
		return
	_fade_to(0.0).tween_callback(hide)


func _fade_to(alpha: float) -> Tween:
	if fade_tween:
		fade_tween.kill()
	fade_tween = create_ui_tween()
	fade_tween.tween_property(%Window, "modulate:a", alpha, FADE_DURATION)
	return fade_tween
