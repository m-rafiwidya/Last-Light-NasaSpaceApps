extends UIScreen

const ICONS: Array[Texture2D] = [preload("res://res/textures/dev/orange.png"),
	preload("res://res/textures/dev/grey.png"), preload("res://res/textures/dev/orange.png"),
	preload("res://res/textures/dev/grey.png")]

enum Section {MISSION, KITE, DOWNLINK, PLANNING}
const SECTIONS: Array[String] = ["Mission", "Kite", "Downlink", "Planning"]
const DOWNLINK_TIME: float = 2.5
const FLIGHT_TIME: float = 18.0
const PLANNING_MISSION: String = "m1"
const REFRESH_TIME: float = 0.25
const DONE_COLOR: String = "#3d8f4f"

var fade_tween: Tween = null
var section: Section = Section.MISSION
var _sending: float = -1.0
var _refresh: float = 0.0
var _flight: float = -1.0
var _service_id: String = ""
var _manifest: Dictionary = {}
var _order: Dictionary = {}
var _planning: VBoxContainer = null
var _service_buttons: Dictionary = {}
var _item_boxes: Dictionary = {}
var _mass_label: Label = null
var _skip: Button = null


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
	_build_planning()
	CampaignState.objective_completed.connect(func(_id: String) -> void: refresh())
	CampaignState.mission_started.connect(func(_id: String) -> void: refresh())
	CampaignState.mission_completed.connect(func(_id: String) -> void: refresh())
	CampaignState.campaign_reset.connect(reset)
	refresh()
	hide()


func _process(delta: float) -> void:
	if _sending >= 0.0:
		_sending += delta
		if _sending >= DOWNLINK_TIME:
			_finish_downlink()
	if _flight >= 0.0:
		_flight += delta
		if _flight >= FLIGHT_TIME:
			_finish_flight()
	if not visible:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		refresh()


## Drops a downlink or cargo order in progress and the planning choices (a new campaign or a loaded slot)
func reset() -> void:
	_sending = -1.0
	_flight = -1.0
	_order = {}
	_service_id = ""
	for entry in CargoPlan.items():
		_manifest[entry["id"]] = entry.get("required", false)
	select_section(Section.MISSION)


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
	_planning.visible = false
	match section:
		Section.MISSION:
			_show_mission()
		Section.KITE:
			_show_kite()
		Section.DOWNLINK:
			_show_downlink()
		Section.PLANNING:
			_show_planning()
	_update_action()
	%DownlinkProgress.visible = _sending >= 0.0 or _flight >= 0.0
	%DownlinkProgress.value = clampf(_sending / DOWNLINK_TIME if _sending >= 0.0 else _flight / FLIGHT_TIME, 0.0, 1.0)
	%ControlKite.disabled = _workshop() == null
	%ItemList.set_item_disabled(Section.PLANNING, not planning_open())


func _show_mission() -> void:
	var mission := CampaignState.current_mission()
	if CampaignState.is_campaign_complete():
		var ending := CampaignState.mission_ending(CampaignState.last_mission())
		_set_text("Campaign complete", "Every mission is complete. Free play: the workshop and Kite are yours.\n\n%s"
			% ending.get("next_assignment", ""))
		return
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
	elif mission == MissionDirector.COLD_MISSION:
		lines.append("")
		lines.append_array(route_forecast())
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
	var downlink := CampaignState.mission_downlink(mission)
	var objective: String = downlink.get("objective", "")
	if objective.is_empty():
		_set_text("Downlink", "Nothing to send for this mission.")
		return
	if _sending >= 0.0:
		_set_text("Downlink", "%s  %d%%" % [downlink.get("progress", "Sending..."), floori(_sending / DOWNLINK_TIME * 100.0)])
	elif CampaignState.is_objective_done(objective):
		_set_text("Downlink: report received", CampaignState.mission_report(mission))
		var attachment: String = downlink.get("attachment", "")
		if attachment and ResourceLoader.exists(attachment):
			var rect := TextureRect.new()
			rect.texture = load(attachment)
			rect.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
			%Attachments.add_child(rect)
	elif _downlink_ready(mission):
		_set_text("Downlink", downlink.get("ready", "Ready to send."))
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
	elif _flight >= 0.0:
		%Action.text = "Cargo in flight..."
		%Action.disabled = true
	elif not mission.is_empty() and CampaignState.is_mission_completed(mission) and next:
		%Action.text = "Start next mission: %s" % CampaignState.mission_title(next)
	elif section == Section.DOWNLINK and _downlink_objective(mission) and not CampaignState.is_objective_done(_downlink_objective(mission)):
		%Action.text = CampaignState.mission_downlink(mission).get("action", "Send")
		%Action.disabled = not _downlink_ready(mission)
	elif section == Section.PLANNING and _can_order():
		%Action.text = "Confirm order"
		%Action.disabled = not confirm_blocked().is_empty()
	else:
		%Action.visible = false


func _downlink_objective(mission: String) -> String:
	return CampaignState.mission_downlink(mission).get("objective", "")


func _downlink_ready(mission: String) -> bool:
	var objective := _downlink_objective(mission)
	return not objective.is_empty() and CampaignState.current_objective() == objective


func _on_action_pressed() -> void:
	var mission := CampaignState.current_mission()
	var next := CampaignState.next_mission(mission)
	if _sending >= 0.0 or _flight >= 0.0:
		return
	if not mission.is_empty() and CampaignState.is_mission_completed(mission) and next:
		CampaignState.start_mission(next)
		select_section(Section.MISSION)
	elif section == Section.PLANNING and _can_order():
		confirm_order()
	elif _downlink_ready(mission):
		_sending = 0.0
		refresh()


func _finish_downlink() -> void:
	_sending = -1.0
	var mission := CampaignState.current_mission()
	if _downlink_ready(mission):
		CampaignState.complete_objective(_downlink_objective(mission))
	refresh()


# --- Planning: the M2 cargo order (CargoPlan) ------------------------------------------------


func planning_open() -> bool:
	return CampaignState.is_mission_completed(PLANNING_MISSION)


func _can_order() -> bool:
	return CampaignState.current_objective() == CargoPlan.objective() and not CargoPlan.is_delivered()


func _build_planning() -> void:
	for entry in CargoPlan.items():
		_manifest[entry["id"]] = entry.get("required", false)
	_planning = VBoxContainer.new()
	_planning.name = "Planning"
	var description: Control = %Description
	description.get_parent().add_child(_planning)
	description.get_parent().move_child(_planning, description.get_index() + 1)
	var row := HBoxContainer.new()
	_planning.add_child(row)
	var group := ButtonGroup.new()
	for entry in CargoPlan.services():
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = "%s  (%.0f kg, day %d)" % [entry["name"], float(entry["limit_kg"]), int(entry["arrival_day"])]
		button.pressed.connect(select_service.bind(str(entry["id"])))
		row.add_child(button)
		_service_buttons[entry["id"]] = button
	var grid := GridContainer.new()
	grid.columns = 2
	_planning.add_child(grid)
	for entry in CargoPlan.items():
		var box := CheckBox.new()
		box.focus_mode = Control.FOCUS_NONE
		box.text = "%s  %.1f kg%s" % [entry["name"], CargoPlan.item_mass(entry["id"]), "  (required)" if entry.get("required", false) else ""]
		box.button_pressed = _manifest[entry["id"]]
		box.toggled.connect(func(on: bool) -> void: set_item(str(entry["id"]), on))
		grid.add_child(box)
		_item_boxes[entry["id"]] = box
	_mass_label = Label.new()
	_planning.add_child(_mass_label)
	_skip = Button.new()
	_skip.text = "Skip flight"
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.pressed.connect(skip_flight)
	_planning.add_child(_skip)
	_planning.hide()


func select_service(id: String) -> void:
	if _flight < 0.0 and not CargoPlan.service(id).is_empty():
		_service_id = id
		refresh()


func set_item(id: String, on: bool) -> void:
	if _flight >= 0.0 or not _manifest.has(id):
		return
	_manifest[id] = on or CargoPlan.item(id).get("required", false)
	refresh()


func manifest_ids() -> Array:
	return _manifest.keys().filter(func(id: String) -> bool: return _manifest[id])


## Why Confirm order is disabled, or "" when it is enabled
func confirm_blocked() -> String:
	if not _can_order():
		return "No cargo order is due."
	return CargoPlan.validate(_service_id, manifest_ids())


func flying() -> bool:
	return _flight >= 0.0


func confirm_order() -> bool:
	if _flight >= 0.0 or not confirm_blocked().is_empty():
		return false
	_order = {"service": _service_id, "items": manifest_ids()}
	_flight = 0.0
	refresh()
	return true


func skip_flight() -> void:
	if _flight >= 0.0:
		_finish_flight()


func _finish_flight() -> void:
	_flight = -1.0
	CargoPlan.deliver(_order["service"], _order["items"])
	refresh()


func _show_planning() -> void:
	var editable: bool = _can_order() and _flight < 0.0
	_planning.visible = section == Section.PLANNING and (_can_order() or _flight >= 0.0)
	for id in _service_buttons:
		_service_buttons[id].set_pressed_no_signal(id == (_order.get("service", "") if _flight >= 0.0 else _service_id))
		_service_buttons[id].disabled = not editable
	for id in _item_boxes:
		_item_boxes[id].set_pressed_no_signal(_manifest[id])
		_item_boxes[id].disabled = not editable or CargoPlan.item(id).get("required", false)
	_skip.visible = _flight >= 0.0
	_mass_label.visible = _flight < 0.0
	if not planning_open():
		_set_text("Planning", "Cargo planning opens once %s is complete." % CampaignState.mission_title(PLANNING_MISSION))
	elif _flight >= 0.0:
		_set_text("Cargo flight", "\n".join(_flight_lines()))
	elif CargoPlan.is_delivered():
		_set_text("Planning: cargo delivered", "\n".join(_ledger_lines()))
	elif not _can_order():
		_set_text("Planning", "Start %s to order its cargo." % CampaignState.mission_title(CampaignState.next_mission(PLANNING_MISSION)))
	else:
		_set_text("Planning: order the M2 cargo", "\n".join(_card_lines()))
		var limit: float = float(CargoPlan.service(_service_id).get("limit_kg", 0.0))
		_mass_label.text = "Total %.1f / %s kg  (packaging %.1f kg included)" % [CargoPlan.order_mass(manifest_ids()),
			("%.1f" % limit) if limit > 0.0 else "-", CargoPlan.packaging_kg()]


func _card_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for entry in CargoPlan.services():
		var id: String = entry["id"]
		var day: float = CargoPlan.m3_day(id)
		var mark: String = "›" if id == _service_id else "○"
		lines.append("%s [b]%s[/b]  limit %.1f kg, arrives day %d" % [mark, entry["name"], float(entry["limit_kg"]),
			int(entry["arrival_day"])])
		lines.append("    %s" % entry["description"])
		if CargoPlan.is_late(id):
			lines.append("    [color=#b5651d]Day %d: M3 near nightfall (sun ~%d° up, %.1f days to sunset), colder routes.[/color]"
				% [int(entry["arrival_day"]), roundi(CargoPlan.sun_elevation(day)), CargoPlan.days_to_sunset(day)])
		else:
			lines.append("    Day %d: M3 in daylight (sun ~%d° up). Only the short route's shade is cold."
				% [int(entry["arrival_day"]), roundi(CargoPlan.sun_elevation(day))])
	var problem := confirm_blocked()
	lines.append("")
	lines.append("[color=red]%s[/color]" % problem if problem else "[color=%s]Manifest valid.[/color]" % DONE_COLOR)
	lines.append("Story days are compressed. Mass limits, arrival days and sun angles are game assumptions.")
	return lines


func _flight_lines() -> PackedStringArray:
	var entry := CargoPlan.service(_order["service"])
	var phases: Array = entry.get("phases", [])
	var fraction: float = clampf(_flight / FLIGHT_TIME, 0.0, 1.0)
	var current: int = mini(floori(fraction * phases.size()), phases.size() - 1)
	var lines: PackedStringArray = ["%s, %.1f kg delivered payload" % [entry["name"], CargoPlan.order_mass(_order["items"])], ""]
	for i in phases.size():
		var label := "Day %2d  %s" % [int(phases[i][1]), phases[i][0]]
		if i < current:
			lines.append("[color=%s]✓  %s[/color]" % [DONE_COLOR, label])
		elif i == current:
			lines.append("[b]›  %s[/b]" % label)
		else:
			lines.append("○  %s" % label)
	lines.append("")
	lines.append("Story day %d of %d (compressed)" % [floori(fraction * float(entry["arrival_day"])), int(entry["arrival_day"])])
	lines.append("Descent from lunar orbit: delta-v %d m/s (declared game assumption)" % roundi(CargoPlan.descent_delta_v()))
	return lines


func _ledger_lines() -> PackedStringArray:
	var id := CargoPlan.delivered_service()
	var entry := CargoPlan.service(id)
	var names: PackedStringArray = []
	for item_id in CargoPlan.delivered_items():
		names.append(CargoPlan.item(item_id)["name"])
	var lines: PackedStringArray = ["Delivered by the %s on story day %d." % [entry.get("name", "lander"), int(entry.get("arrival_day", 0))],
		"Manifest: %s (%.1f kg)." % [", ".join(names), CargoPlan.order_mass(Array(CargoPlan.delivered_items()))],
		"Parts are on the rack and the sample bench; the radio-power module is in the cargo crate by the pad.", ""]
	lines.append_array(route_forecast())
	return lines


## The M3 route forecast from the delivered cargo and Kite's fitted parts
func route_forecast() -> PackedStringArray:
	var id := CargoPlan.delivered_service()
	if id.is_empty():
		return PackedStringArray(["ROUTE FORECAST  no cargo delivered: the shaded short route needs the thermal kit."])
	var day: float = CargoPlan.m3_day(id)
	var late: bool = CargoPlan.is_late(id)
	var director := _director()
	var kit: String = "not delivered"
	if CargoPlan.is_ordered("thermal_kit"):
		kit = "fitted" if director and director.rover and director.thermal_kit_fitted() else "delivered, not fitted"
	var grip: String = "delivered" if CargoPlan.is_ordered("grip_wheels") else "not delivered"
	var lines: PackedStringArray = ["[b]ROUTE FORECAST[/b]  M3 on lunar day %.1f, sun ~%d° up%s" % [day,
		roundi(CargoPlan.sun_elevation(day)), ", near nightfall" if late else ""]]
	lines.append("Short route: rough ground through shade. Thermal kit needed (%s); high-grip wheels help (%s)." % [kit, grip])
	if late:
		lines.append("Long route: the far rim is in shade near nightfall. Thermal kit needed here too (%s)." % kit)
	else:
		lines.append("Long route: sunlit, gentler and longer. No thermal kit needed.")
	lines.append("Without cover and heater fitted, Kite shuts down after %d s in cold shade and is recovered."
		% roundi(MissionDirector.COLD_LIMIT))
	return lines


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
