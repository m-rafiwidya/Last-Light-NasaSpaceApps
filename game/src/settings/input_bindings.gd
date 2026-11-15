class_name InputBindings

extends RefCounted

## The key bindings players can change (Settings > Controls), in ACTIONS (menu order). Rebinding
## replaces the action's key, its first keyboard event in the InputMap; its other events stay (the
## mouse wheel for zoom, Alt+Enter for fullscreen). Keys that differ from the project's
## (project.godot [input]) are saved in user://settings.cfg (section "bindings", action ->
## physical keycode) and put back in the InputMap at launch (load_saved, from Main).
## Conflicts: a key another listed action uses is swapped, that action gets the old key (rebind()
## says which). Esc can't be bound (it pauses and closes menus, ui_cancel), and neither can a key
## an action that isn't listed uses (the debug console's backtick): rebind() refuses and says why.
## The menus' own ui_* actions don't count as conflicts (Space is both jump and ui_accept).
## LOCKED rows are shown but not rebindable (mouse-only throw, Esc).
## KeyChip, the HUD hints and the part tooltip follow `events.changed`.

const SECTION: String = "bindings"

## [action, label] in menu order
const ACTIONS: Array = [
	[&"move_forward", "Move Forward"],
	[&"move_backward", "Move Backward"],
	[&"move_left", "Move Left"],
	[&"move_right", "Move Right"],
	[&"move_sprint", "Sprint"],
	[&"move_jump", "Jump"],
	[&"move_crouch", "Crouch"],
	[&"interact_use", "Interact"],
	[&"lights", "Helmet Light / Headlights"],
	[&"camera_next", "Rover Camera View"],
	[&"camera_zoom_in", "Zoom In"],
	[&"camera_zoom_out", "Zoom Out"],
	[&"arm_toggle", "Deploy / Stow Arm"],
	[&"arm_joint_1", "Arm Joint 1"],
	[&"arm_joint_2", "Arm Joint 2"],
	[&"arm_joint_3", "Arm Joint 3"],
	[&"arm_joint_4", "Arm Joint 4"],
	[&"arm_joint_5", "Arm Joint 5"],
	[&"arm_rotate_up", "Raise Arm Joint"],
	[&"arm_rotate_down", "Lower Arm Joint"],
	[&"robot_reset", "Reset Rover Upright"],
	[&"dialogue_skip", "Skip Radio Line"],
	[&"toggle_fullscreen", "Toggle Fullscreen"],
]
## [action, label]: shown in the menu with their binding, not rebindable
const LOCKED: Array = [
	[&"interact_primary", "Throw"],
	[&"ui_cancel", "Pause / Back"],
]

## Short names for keys and buttons (OS.get_keycode_string / InputEvent.as_text -> shown)
const NAMES: Dictionary = {
	"Escape": "Esc", "Kp Enter": "Enter", "Equal": "=", "Minus": "-", "QuoteLeft": "`",
	"Comma": ",", "Period": ".", "Slash": "/", "BackSlash": "\\", "Semicolon": ";",
	"Apostrophe": "'", "BracketLeft": "[", "BracketRight": "]",
	"Left Mouse Button": "LMB", "Right Mouse Button": "RMB", "Middle Mouse Button": "MMB",
	"Mouse Wheel Up": "Wheel Up", "Mouse Wheel Down": "Wheel Down",
}
## What uses keys of actions that aren't listed, for rebind()'s refusal
const OTHER_USES: Dictionary = {&"console": "the debug console"}

## changed(): after any binding changed (rebind, reset, load_saved)
static var events: Events = Events.new()
static var _loaded: bool = false


class Events:
	extends RefCounted
	signal changed


static func is_rebindable(action: StringName) -> bool:
	return ACTIONS.any(func(entry: Array) -> bool: return entry[0] == action)


## The action's key: its first keyboard event, null if it has none
static func key_event(action: StringName) -> InputEventKey:
	if not InputMap.has_action(action):
		return null
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return event
	return null


## A key's identity: its physical keycode, or its keycode for events bound by keycode (F11)
static func key_code(event: InputEventKey) -> Key:
	return event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode


## The action's key as shown (KeyChip, slabs, HUD hints): its key, else its first event (LMB),
## else `fallback`
static func action_text(action: StringName, fallback: String = "") -> String:
	if not InputMap.has_action(action):
		return fallback
	var key := key_event(action)
	if key:
		return event_text(key)
	var all: Array[InputEvent] = InputMap.action_get_events(action)
	return event_text(all[0]) if not all.is_empty() else fallback


## Several actions' keys as one hint: "WASD" while each is one character, "Up/Left/Down/Right"
## otherwise; "1-5" for the arm joints as shipped
static func keys_text(actions: Array) -> String:
	var texts: PackedStringArray = []
	for action: StringName in actions:
		texts.append(action_text(action, "?"))
	var joined: String = "".join(texts)
	if joined == "12345":
		return "1-5"
	return joined if joined.length() == texts.size() else "/".join(texts)


## Text written with the shipped interact key (prompts such as 'Press "E" to talk', "press E")
## with the key it has now
static func with_current_keys(text: String) -> String:
	var key: String = action_text(&"interact_use", "E")
	if key == "E":
		return text
	return text.replace('"E"', '"%s"' % key).replace("press E", "press " + key).replace("Press E", "Press " + key)


static func event_text(event: InputEvent) -> String:
	var text: String
	if event is InputEventKey:
		var key := event as InputEventKey
		var code: Key = key_code(key)
		if key.physical_keycode != KEY_NONE and DisplayServer.get_name() != "headless":
			# The label on the player's keyboard layout (WASD stays where it is on AZERTY)
			code = DisplayServer.keyboard_get_label_from_physical(key.physical_keycode)
		text = OS.get_keycode_string(code | key.get_modifiers_mask())
	elif event is InputEventMouseButton:
		text = event.as_text().get_slice(" (", 0)
	else:
		text = event.as_text()
	return NAMES.get(text, text)


## Binds `event`'s key to `action`. Returns what the menu should tell the player: "" when it was
## simply bound (or already was), a note when another action's key was swapped, or why it was
## refused (nothing changed then: check is_bound_to).
static func rebind(action: StringName, event: InputEventKey) -> String:
	load_saved()
	var code: Key = key_code(event)
	if code == KEY_ESCAPE:
		return "Esc can't be bound: it pauses the game and closes menus"
	var current := key_event(action)
	if current and key_code(current) == code and current.get_modifiers_mask() == 0:
		return ""
	var swapped: StringName = &""
	for other: StringName in InputMap.get_actions():
		if other == action or String(other).begins_with("ui_"):
			continue
		for other_event in InputMap.action_get_events(other):
			if not (other_event is InputEventKey and key_code(other_event) == code
					and (other_event as InputEventKey).get_modifiers_mask() == 0):
				continue
			if not is_rebindable(other):
				return "%s is used by %s" % [event_text(other_event), OTHER_USES.get(other, other)]
			if other_event != key_event(other):
				return "%s is also used by %s" % [event_text(other_event), label(other)]
			swapped = other
	var message: String = ""
	if swapped != &"":
		if current:
			_set_key(swapped, key_code(current))
		else:
			_erase_key(swapped)
		message = "%s was on %s: swapped, %s is now %s" % [event_text(event), label(swapped), label(swapped),
			action_text(swapped, "unbound")]
	_set_key(action, code)
	_save()
	events.changed.emit()
	return message


## True when `action`'s key is the one in `event`
static func is_bound_to(action: StringName, event: InputEventKey) -> bool:
	var key := key_event(action)
	return key != null and key_code(key) == key_code(event)


static func label(action: StringName) -> String:
	for entry in ACTIONS + LOCKED:
		if entry[0] == action:
			return entry[1]
	return String(action)


## Every listed action back to the project's events (and nothing saved)
static func reset() -> void:
	load_saved()
	for entry in ACTIONS:
		var action: StringName = entry[0]
		InputMap.action_erase_events(action)
		for event in _project_events(action):
			InputMap.action_add_event(action, event.duplicate())
	_save()
	events.changed.emit()


## Puts the saved bindings in the InputMap (once; at launch). Not in a script run unless
## SettingsSection.read_saved (see there).
static func load_saved() -> void:
	if _loaded:
		return
	_loaded = true
	if not SettingsSection.read_saved:
		return
	var config := ConfigFile.new()
	if config.load(SettingsSection.PATH) != OK or not config.has_section(SECTION):
		return
	for action: String in config.get_section_keys(SECTION):
		var code: Variant = config.get_value(SECTION, action)
		if is_rebindable(action) and code is int and code > 0 and code != KEY_ESCAPE:
			_set_key(action, code)
	events.changed.emit()


## Reads the file again (tests: a launch with what was saved)
static func reload_saved() -> void:
	_loaded = false
	load_saved()


## The project's key for `action` (project.godot), KEY_NONE if it has none
static func default_key_code(action: StringName) -> Key:
	for event in _project_events(action):
		if event is InputEventKey:
			return key_code(event)
	return KEY_NONE


static func _project_events(action: StringName) -> Array:
	var setting: Variant = ProjectSettings.get_setting("input/" + action)
	return setting.get("events", []) if setting is Dictionary else []


# Replaces the action's key (keeping its place among the events) or adds one
static func _set_key(action: StringName, code: Key) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = code
	var old_events: Array[InputEvent] = InputMap.action_get_events(action)
	var replaced: bool = false
	InputMap.action_erase_events(action)
	for event in old_events:
		if event is InputEventKey and not replaced:
			InputMap.action_add_event(action, key)
			replaced = true
		else:
			InputMap.action_add_event(action, event)
	if not replaced:
		InputMap.action_add_event(action, key)


static func _erase_key(action: StringName) -> void:
	var key := key_event(action)
	if key:
		InputMap.action_erase_event(action, key)


# The keys that differ from the project's
static func _save() -> void:
	var config := ConfigFile.new()
	config.load(SettingsSection.PATH)
	if config.has_section(SECTION):
		config.erase_section(SECTION)
	for entry in ACTIONS:
		var action: StringName = entry[0]
		var key := key_event(action)
		var code: Key = key_code(key) if key else KEY_NONE
		if code != default_key_code(action):
			config.set_value(SECTION, action, int(code))
	config.save(SettingsSection.PATH)
