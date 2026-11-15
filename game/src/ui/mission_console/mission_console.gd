extends UIScreen

## Full-screen console (Console.dc.html): header, underline tabs on the left with CONTROL KITE
## under them, the section on the right (scrolls), the subtitle slot and the key hints at the foot.

enum Section {MISSION, KITE, DOWNLINK, PLANNING}
const SECTIONS: Array[String] = ["Mission", "Kite", "Downlink", "Planning"]
const DOWNLINK_TIME: float = 2.5
const FLIGHT_TIME: float = 18.0
const PLANNING_MISSION: String = "m1"
const REFRESH_TIME: float = 0.25

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
var _tabs: Array[Button] = []


func _ready() -> void:
	add_to_group(&"mission_console")
	%Window.modulate.a = 0.0
	%Rule.color = _color(&"rule")
	%Close.pressed.connect(_on_close_pressed)
	%Action.pressed.connect(_on_action_pressed)
	%ControlKite.pressed.connect(_on_control_kite_pressed)
	var close_sound := ButtonSoundComponent.new()
	close_sound.press_sound = &""
	%Close.add_child(close_sound)
	for i in SECTIONS.size():
		var tab := UnderlineButton.new()
		tab.theme_type_variation = &"UnderlineButtonTab"
		tab.text = SECTIONS[i].to_upper()
		tab.focus_mode = Control.FOCUS_NONE
		tab.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		tab.pressed.connect(_on_tab_pressed.bind(i))
		%Tabs.add_child(tab)
		_tabs.append(tab)
	$SubtitleStack.slot = %SubtitleSlot
	%Window.resized.connect(_layout)
	_layout()
	_build_planning()
	CampaignState.objective_completed.connect(func(_id: String) -> void: refresh())
	CampaignState.mission_started.connect(func(_id: String) -> void: refresh())
	CampaignState.mission_completed.connect(func(_id: String) -> void: refresh())
	CampaignState.campaign_reset.connect(reset)
	refresh()
	hide()


## The board's margins (120 / 64 / 56 of 1600 x 900) and nav width, narrowed on small screens
func _layout() -> void:
	var width: float = %Window.size.x
	var side: float = clampf(width * 0.075, 32.0, 144.0)
	%Frame.add_theme_constant_override(&"margin_left", maxi(roundi(side), roundi(BackButton.DESIGN_POSITION.x + BackButton.SIZE + 24.0)))
	%Frame.add_theme_constant_override(&"margin_right", roundi(side))
	%Nav.custom_minimum_size.x = clampf(width * 0.25, 260.0, 480.0)
	var height: float = %Window.size.y
	%Frame.add_theme_constant_override(&"margin_top", roundi(clampf(height * 0.071, 32.0, 77.0)))
	%Frame.add_theme_constant_override(&"margin_bottom", roundi(clampf(height * 0.062, 28.0, 67.0)))
	$Window/Frame/Column/BodyGap.custom_minimum_size.y = clampf(height * 0.067, 16.0, 72.0)
	_fit_action()


func _input(event: InputEvent) -> void:
	if not visible or GameState.state != GameState.State.MISSION_CONSOLE:
		return
	var step: int = 1 if event.is_action_pressed(&"ui_focus_next") else -1 if event.is_action_pressed(&"ui_focus_prev") else 0
	if step == 0:
		return
	get_viewport().set_input_as_handled()
	var next: int = section
	for i in SECTIONS.size():
		next = posmod(next + step, SECTIONS.size())
		if not _tabs[next].disabled:
			break
	if next != section:
		AudioManager.play_ui(&"click")
		select_section(next as Section)


func _on_tab_pressed(index: int) -> void:
	AudioManager.play_ui(&"click")
	_show_section(index)


## The tab button of a section
func tab_button(value: Section) -> Button:
	return _tabs[value]


func _color(token: StringName) -> Color:
	return %Window.get_theme_color(token, &"UIColor")


func _hex(token: StringName) -> String:
	return "#" + _color(token).to_html(false)


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
	_fit_action()
	%DownlinkProgress.visible = _sending >= 0.0 or _flight >= 0.0
	%DownlinkProgress.value = clampf(_sending / DOWNLINK_TIME if _sending >= 0.0 else _flight / FLIGHT_TIME, 0.0, 1.0)
	%ControlKite.disabled = _workshop() == null
	_tabs[Section.PLANNING].disabled = not planning_open()
	for i in _tabs.size():
		if _tabs[i].active != (i == section):
			_tabs[i].active = i == section
	%HeaderInfo.text = "Workshop  ·  %s" % SaveIndex.format_play_time(int(CampaignState.play_time_sec))


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
	var objectives := CampaignState.mission_objectives(mission, true)
	for i in objectives.size():
		var objective: String = objectives[i]
		var title := CampaignState.objective_title(objective)
		if objective not in required:
			title += "  (optional)"
		lines.append(_step(i + 1, title, CampaignState.is_objective_done(objective), objective == current))
	lines.append_array(crew_request_lines(mission))
	if CampaignState.is_mission_completed(mission):
		lines.append("\n[b]Mission complete.[/b]")
	else:
		var checklist := CampaignState.mission_checklist(mission)
		if not checklist.is_empty():
			lines.append("")
			for note in checklist:
				lines.append("[color=%s]NOTE    %s[/color]" % [_hex(&"muted"), note])
		if mission == MissionDirector.COLD_MISSION:
			lines.append("")
			lines.append_array(route_forecast())
	_set_text("%s  ·  %s" % [mission.to_upper(), CampaignState.mission_title(mission)], "\n".join(lines))


## "REQUEST  Hana: Collect the near-site sample" under the objectives, with met / missed once the downlink is sent
func crew_request_lines(mission: String) -> PackedStringArray:
	var lines: PackedStringArray = []
	var stats := CampaignState.mission_stats(mission)
	var sent: bool = stats.get("crew_requests") is Array
	for result in CrewRequests.results(mission, stats):
		var outcome: String = ("  (%s)" % ("met" if result["met"] else "missed")) if sent else ""
		lines.append("[color=%s]REQUEST  %s: %s%s[/color]" % [_hex(&"text_2"), result["speaker"], result["summary"], outcome])
	if not lines.is_empty():
		lines.insert(0, "")
	return lines


func _show_kite() -> void:
	var workshop := _workshop()
	if workshop == null:
		_set_text("Kite", "No link to Kite.")
		return
	var rover: Robot = workshop.rover
	var rows: Array = []
	if rover.battery:
		rows.append(["Battery", "%d%%" % floori(rover.battery.get_charge_fraction() * 100.0)])
	else:
		rows.append(["Battery", "[color=%s]None fitted[/color]: take the battery from the rack and drop it into the socket at Kite's rear" % _hex(&"warn")])
	if workshop.pad and workshop.pad.rover == rover:
		rows.append(["Dock", workshop.pad.get_status_text()])
	else:
		rows.append(["Dock", "Out, %d m from the pad" % roundi(workshop.pad.offset_of(rover).length() if workshop.pad else 0.0)])
	var director := _director()
	if director:
		if director.recovering:
			rows.append(["Alert", "[color=%s]%s[/color]" % [_hex(&"warn"), director.alert]])
		elif rover.battery and not workshop.pad.is_in_zone(rover):
			rows.append(["Return", "Needs about %d%%" % ceili(director.return_fraction_needed() * 100.0)])
		if director.can_request_recovery():
			rows.append(["Stuck?", "Kite hasn't moved for %d s. Emergency recovery returns it to the pad (logged in the report)." % floori(director.still_time)])
	var parts: PackedStringArray = []
	for socket in rover.find_children("*", "HotswapSocket", true, false):
		if socket.part:
			parts.append(socket.part.get_display_name())
	rows.append(["Fitted", ", ".join(parts) if parts else "Nothing"])
	_set_text("Kite", _table(rows))


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
		_set_text("Downlink: report received", report_text(MissionReport.sections(mission)))
		var attachment: String = downlink.get("attachment", "")
		if attachment and ResourceLoader.exists(attachment):
			var rect := TextureRect.new()
			rect.texture = load(attachment)
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
			rect.custom_minimum_size = Vector2(480.0, 480.0 * rect.texture.get_height() / maxf(rect.texture.get_width(), 1.0))
			%Attachments.add_child(rect)
	elif _downlink_ready(mission):
		_set_text("Downlink", _skip_note(downlink) + downlink.get("ready", "Ready to send."))
	else:
		var waiting := CampaignState.current_objective()
		_set_text("Downlink", _skip_note(downlink) + "Nothing to send yet. First: %s." % CampaignState.objective_title(waiting))


## The downlink's warning about an optional objective still open, with its blank line ("" for none)
func _skip_note(downlink: Dictionary) -> String:
	var note: Variant = downlink.get("skip_note")
	if not (note is Dictionary) or CampaignState.is_objective_done(str(note.get("objective", ""))):
		return ""
	return "[color=%s][b]%s[/b][/color]\n\n" % [_hex(&"warn"), note.get("text", "")]


func _update_action() -> void:
	var mission := CampaignState.current_mission()
	var next := CampaignState.next_mission(mission)
	%Action.visible = true
	%Action.disabled = false
	if _sending >= 0.0:
		%Action.show_text("Sending...")
		%Action.disabled = true
	elif _flight >= 0.0:
		%Action.show_text("Cargo in flight...")
		%Action.disabled = true
	elif not mission.is_empty() and CampaignState.is_mission_completed(mission) and next:
		%Action.show_text("Start next mission: %s" % CampaignState.mission_title(next))
	elif section == Section.DOWNLINK and _downlink_objective(mission) and not CampaignState.is_objective_done(_downlink_objective(mission)):
		%Action.show_text(CampaignState.mission_downlink(mission).get("action", "Send"))
		%Action.disabled = not _downlink_ready(mission)
	elif section == Section.PLANNING and _can_order():
		%Action.show_text("Confirm order")
		%Action.disabled = not confirm_blocked().is_empty()
	elif section == Section.KITE and _director() and _director().can_request_recovery():
		%Action.show_text("Request emergency recovery")
	else:
		%Action.visible = false


## The action button at its text's width, wrapping only when the content column is narrower
func _fit_action() -> void:
	var action: Button = %Action
	var font: Font = action.get_theme_font(&"font")
	var normal: StyleBox = action.get_theme_stylebox(&"normal")
	var natural: float = font.get_string_size(action.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		action.get_theme_font_size(&"font_size")).x + normal.get_margin(SIDE_LEFT) + normal.get_margin(SIDE_RIGHT) + 2.0
	var room: float = %Window.size.x - %Frame.get_theme_constant(&"margin_left") - %Frame.get_theme_constant(&"margin_right") \
		- %Nav.custom_minimum_size.x
	action.custom_minimum_size.x = minf(natural, maxf(room, 160.0))


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
	elif section == Section.KITE and _director() and _director().request_recovery():
		refresh()
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
	_planning.add_theme_constant_override(&"separation", 22)
	var row := HFlowContainer.new()
	row.add_theme_constant_override(&"h_separation", 10)
	row.add_theme_constant_override(&"v_separation", 10)
	_planning.add_child(row)
	var group := ButtonGroup.new()
	for entry in CargoPlan.services():
		var button := Button.new()
		button.theme_type_variation = &"SlantedToggleTab"
		button.custom_minimum_size.y = 43.2
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.text = ("%s  %.0f kg  day %d" % [entry["name"], float(entry["limit_kg"]), int(entry["arrival_day"])]).to_upper()
		button.pressed.connect(select_service.bind(str(entry["id"])))
		row.add_child(button)
		_service_buttons[entry["id"]] = button
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 40)
	grid.add_theme_constant_override(&"v_separation", 6)
	_planning.add_child(grid)
	for entry in CargoPlan.items():
		var box := CheckBox.new()
		box.theme_type_variation = &"ConsoleCheck"
		box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.focus_mode = Control.FOCUS_NONE
		box.text = "%s  %.1f kg%s" % [entry["name"], CargoPlan.item_mass(entry["id"]), "  (required)" if entry.get("required", false) else ""]
		var note := CrewRequests.planning_note(str(entry["id"]))
		if note:
			box.text += "  ·  " + note
		box.button_pressed = _manifest[entry["id"]]
		box.toggled.connect(func(on: bool) -> void: set_item(str(entry["id"]), on))
		grid.add_child(box)
		_item_boxes[entry["id"]] = box
	_mass_label = Label.new()
	_mass_label.theme_type_variation = &"LabelMonoValue"
	_planning.add_child(_mass_label)
	_skip = Button.new()
	_skip.theme_type_variation = &"SkipButton"
	_skip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_skip.text = "SKIP FLIGHT"
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
		var picked: bool = id == _service_id
		lines.append("[color=%s][b]%s[/b]  limit %.1f kg, arrives day %d[/color]" % [_hex(&"text" if picked else &"text_2"),
			entry["name"], float(entry["limit_kg"]), int(entry["arrival_day"])])
		lines.append("    %s" % entry["description"])
		if CargoPlan.is_late(id):
			lines.append("    [b]Day %d: M3 near nightfall[/b] (sun ~%d° up in the west, %.1f days to sunset): Head crater's west wall is in shade on the short route, so the thermal kit is needed."
				% [int(entry["arrival_day"]), roundi(CargoPlan.sun_elevation(day)), CargoPlan.days_to_sunset(day)])
		else:
			lines.append("    Day %d: M3 in high sun (~%d° up): no shade on either route, no thermal kit needed."
				% [int(entry["arrival_day"]), roundi(CargoPlan.sun_elevation(day))])
	var problem := confirm_blocked()
	lines.append("")
	lines.append("[color=%s]%s[/color]" % [_hex(&"warn"), problem] if problem else "[color=%s][b]Manifest valid.[/b][/color]" % _hex(&"text"))
	lines.append("[color=%s]Story days are compressed. Mass limits, arrival days and sun angles are game assumptions.[/color]" % _hex(&"dim"))
	return lines


func _flight_lines() -> PackedStringArray:
	var entry := CargoPlan.service(_order["service"])
	var phases: Array = entry.get("phases", [])
	var fraction: float = clampf(_flight / FLIGHT_TIME, 0.0, 1.0)
	var current: int = mini(floori(fraction * phases.size()), phases.size() - 1)
	var lines: PackedStringArray = ["%s, %.1f kg delivered payload" % [entry["name"], CargoPlan.order_mass(_order["items"])], ""]
	for i in phases.size():
		lines.append(_step(i + 1, "Day %d  %s" % [int(phases[i][1]), phases[i][0]], i < current, i == current))
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
		return PackedStringArray(["ROUTE FORECAST  no cargo delivered yet: M3's sun, and so its shade, depends on when the cargo lands."])
	var day: float = CargoPlan.m3_day(id)
	var late: bool = CargoPlan.is_late(id)
	var director := _director()
	var kit: String = "not delivered"
	if CargoPlan.is_ordered("thermal_kit"):
		kit = "fitted" if director and director.rover and director.thermal_kit_fitted() else "delivered, not fitted"
	var grip: String = "delivered" if CargoPlan.is_ordered("grip_wheels") else "not delivered"
	var lines: PackedStringArray = ["[b]ROUTE FORECAST[/b]  M3 on lunar day %.1f, sun ~%d° up%s" % [day,
		roundi(CargoPlan.sun_elevation(day)), ", near nightfall" if late else ""]]
	lines.append("%s (orange flags, about %d m there and back): a boulder field, then down Head's west wall and round its north side, up to the far rim. High-grip wheels help in the boulders (%s)."
		% [RouteMarkers.TITLES["short"], _route_metres("short"), grip])
	if late:
		lines.append("    Near nightfall Head's west wall is in shade on the way down: thermal kit needed (%s)." % kit)
	else:
		lines.append("    High sun: no shade in the crater, no thermal kit needed.")
	lines.append("%s (blue flags, about %d m there and back): gentler and longer, sunlit all the way. No thermal kit needed."
		% [RouteMarkers.TITLES["long"], _route_metres("long")])
	lines.append("Without cover and heater fitted, Kite shuts down after %d s in cold shade and is recovered."
		% roundi(MissionDirector.COLD_LIMIT))
	return lines


func _route_metres(id: String) -> int:
	var markers := get_tree().get_first_node_in_group(&"route_markers") as RouteMarkers
	return roundi(markers.round_trip(id) / 10.0) * 10 if markers else 0


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
	%Title.text = title
	%Description.text = body


## A numbered step (Console.dc.html Briefing list): done struck through and dim, the current one
## bright, pending muted
func _step(number: int, text: String, done: bool, current: bool) -> String:
	var line := "[color=%s]%02d[/color]    %s" % [_hex(&"dim"), number, text]
	if done:
		return "[color=%s][s]%s[/s][/color]" % [_hex(&"dim"), line]
	if current:
		return "[color=%s][b]%s[/b][/color]" % [_hex(&"text"), line]
	return "[color=%s]%s[/color]" % [_hex(&"muted"), line]


## Caption / value rows (the board's telemetry rows)
func _table(rows: Array) -> String:
	var cells: PackedStringArray = []
	for row in rows:
		cells.append("[cell expand=1 padding=0,8,24,8][color=%s]%s[/color][/cell][cell expand=4 padding=0,8,0,8][color=%s]%s[/color][/cell]"
			% [_hex(&"muted"), row[0], _hex(&"text"), row[1]])
	return "[table=2]%s[/table]" % "".join(cells)


## A downlink report: plain text, or headed sections ([{"title", "why", "body"}]), each heading
## followed by its short "why" line. The report area scrolls, so a long one needs no layout change.
func report_text(report: Variant) -> String:
	if report is String:
		return report
	var parts: PackedStringArray = []
	for entry in report:
		var lines: PackedStringArray = []
		if entry.get("title", "") != "":
			lines.append("[color=%s][b]%s[/b][/color]" % [_hex(&"text"), str(entry["title"]).to_upper()])
		if entry.get("why", "") != "":
			lines.append("[color=%s]%s[/color]" % [_hex(&"muted"), entry["why"]])
		if entry.get("body", "") != "":
			lines.append(str(entry["body"]))
		parts.append("\n".join(lines))
	return "\n\n".join(parts)


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
