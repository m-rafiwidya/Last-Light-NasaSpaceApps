extends SceneTree
## Headless test: gameplay sounds (Sfx, src/audio/) on the Moon level.
##   1. Buses: SFX sends to Master, Ambience to SFX; the Effects Volume setting sets the SFX bus.
##      Every phase 1 sound loads; the loops loop.
##   2. Nothing plays on the main menu, nor right after the level starts.
##   3. On foot: steps on the workshop floor inside, on regolith outside; a landing; grab, drop
##      and throw; the thrown part's impact. Non-tonal sounds get a random pitch, tonal ones keep
##      theirs.
##   4. Ambience: the workshop's bed inside, the Moon's outside.
##   5. Sockets and power: taking the battery out plays the release and the power-down, putting it
##      back the seat and the power-up; a refusal plays the refusal.
##   6. Driving: the link opens; driving plays the motor and the wheels as the main layer, nothing
##      else is louder than allowed (ducking), at most Sfx.MAX_LOOPS loops are heard; a drop
##      bumps; a low battery alerts once; leaving closes the link.
##   7. The bay door: unlatch, the drive loop while it moves, the seal when it stops.
##   8. The charger: connect, fully charged, fault.
## Prints one line per check and PASS / FAIL.
##
##     Godot --headless --fixed-fps 240 --path game -s res://tests/test_sfx.gd

const TICKS: int = 240
const SETTINGS_PATH: String = "user://settings.cfg"
const PHASE_1: Array[String] = [
	"step_regolith", "step_floor", "land_regolith", "land_floor", "grab", "drop", "throw",
	"impact_regolith_light", "impact_regolith_medium", "impact_regolith_heavy",
	"impact_hard_light", "impact_hard_medium", "impact_hard_heavy", "part_seat", "part_release",
	"part_refused", "power_up", "power_down", "link_open", "link_close", "battery_low", "bump",
	"rolling_loop", "door_start", "door_loop", "door_stop", "charger_connect", "charger_full",
	"charger_fault", "amb_workshop", "amb_moon",
]

var GS: Node
var SL: Node
var SFX: Node
var failures: int = 0
var log: Array = []            # [sound, player, physics frame]
var workshop
var rover
var player
var _saved_settings: String = ""
var _had_settings: bool = false


func _initialize() -> void:
	_had_settings = FileAccess.file_exists(SETTINGS_PATH)
	if _had_settings:
		_saved_settings = FileAccess.get_file_as_string(SETTINGS_PATH)
	root.add_child.call_deferred(load("res://src/main.tscn").instantiate())
	_run.call_deferred()


func _check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		failures += 1
	print("RESULT %-66s %s %s" % [name, "PASS" if ok else "FAIL", detail])


func _ticks(seconds: float) -> void:
	for i in int(seconds * TICKS):
		await physics_frame


func _mark() -> int:
	return log.size()


func _played(since: int, sound: String) -> Array:
	return log.slice(since).filter(func(e: Array) -> bool: return String(e[0]) == sound)


func _names(since: int) -> String:
	return ",".join(log.slice(since).map(func(e: Array) -> String: return String(e[0])))


func _kit(x: float, y: float, z: float = 0.0) -> Vector3:
	return workshop.to_global(Vector3(x, z, -y))


func _dock() -> Vector2:
	var local: Vector3 = workshop.anchors["dock_point"]
	return Vector2(local.x, -local.z)


func _place_rover(kit_x: float, kit_y: float, height: float = 0.12) -> void:
	rover.global_transform = Transform3D(workshop.global_basis, _kit(kit_x, kit_y, height))
	rover.linear_velocity = Vector3.ZERO
	rover.angular_velocity = Vector3.ZERO


func _place_player(at: Vector3) -> void:
	player.global_position = at
	player.linear_velocity = Vector3.ZERO


func _restore_settings() -> void:
	if _had_settings:
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		f.store_string(_saved_settings)
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


func _run() -> void:
	await process_frame
	GS = root.get_node("GameState")
	SL = root.get_node("SceneLoader")
	SFX = root.get_node("Sfx")
	SFX.played.connect(func(sound: StringName, p: Node) -> void: log.append([sound, p, Engine.get_physics_frames()]))

	_bus_checks()
	while GS.state != GS.State.MAIN_MENU:
		await physics_frame
	await _ticks(2.0)
	_check("main menu: no gameplay sounds", log.is_empty() and not SFX.is_active(), _names(0))

	SL.load_scene("moon_level")
	while not (GS.state == GS.State.IN_GAME_PLAYER and SL.current_level_id == "moon_level"):
		await physics_frame
	var start := _mark()
	await _ticks(SFX.QUIET_AFTER_LOAD * 0.5)
	_check("level start: quiet while things settle", _mark() == start and not SFX.is_active(), _names(start))
	await _ticks(SFX.QUIET_AFTER_LOAD)
	workshop = SL.current_scene.get_node("Workshop")
	rover = workshop.rover
	player = GS.player

	await _foot_checks()
	await _socket_checks()
	await _drive_checks()
	await _door_checks()
	await _charger_checks()
	_restore_settings()
	print("RESULT %s" % ("ALL PASS" if failures == 0 else "%d CHECKS FAILED" % failures))
	quit(1 if failures else 0)


# 1 ---------------------------------------------------------------------------------------------
func _bus_checks() -> void:
	var sfx: int = AudioServer.get_bus_index(&"SFX")
	var ambience: int = AudioServer.get_bus_index(&"Ambience")
	_check("bus SFX exists, sends to Master", sfx >= 0 and AudioServer.get_bus_send(sfx) == &"Master")
	_check("bus Ambience exists, sends to SFX", ambience >= 0 and AudioServer.get_bus_send(ambience) == &"SFX")
	root.get_node("AudioManager").set_volume("effects", 40.0)
	_check("Effects Volume sets the SFX bus", absf(AudioServer.get_bus_volume_db(sfx) - linear_to_db(0.4)) < 0.01,
		"%.2f dB" % AudioServer.get_bus_volume_db(sfx))
	root.get_node("AudioManager").set_volume("effects", 80.0)
	var missing: Array = PHASE_1.filter(func(n: String) -> bool: return SFX._variants(StringName(n)).is_empty())
	_check("every phase 1 sound loads", missing.is_empty(), str(missing))
	var not_looping: Array = PHASE_1.filter(func(n: String) -> bool:
		return (n.ends_with("_loop") or n.begins_with("amb_")) and not (SFX._variants(StringName(n))[0] as AudioStreamOggVorbis).loop)
	_check("the loops loop", not_looping.is_empty(), str(not_looping))


# 3, 4 ------------------------------------------------------------------------------------------
func _walk(seconds: float) -> void:
	Input.action_press("move_forward")
	await _ticks(seconds)
	Input.action_release("move_forward")
	await _ticks(0.3)


func _foot_checks() -> void:
	# Inside, on the workshop floor
	_place_player(workshop.to_global(workshop.anchors["spawn_player"]) + Vector3(0.0, 0.05, 0.0))
	await _ticks(SFX.AMBIENCE_FADE_TIME + 0.5)
	var beds: Dictionary = SFX._ambience_gain
	_check("ambience inside: the workshop's bed", beds[&"amb_workshop"] > 0.99 and beds[&"amb_moon"] < 0.01
		and SFX._ambience[&"amb_workshop"].playing, str(beds))
	var mark := _mark()
	await _walk(1.2)
	var steps: Array = _played(mark, "step_floor")
	_check("walking inside: steps on the floor", steps.size() >= 2 and _played(mark, "step_regolith").is_empty(), _names(mark))
	_check("steps are 2D on the SFX bus", not steps.is_empty() and steps[0][1] is AudioStreamPlayer and steps[0][1].bus == &"SFX")
	var pitches: Array = steps.map(func(e: Array) -> float: return e[1].pitch_scale if is_instance_valid(e[1]) else 1.0)
	_check("steps get a small random pitch", pitches.any(func(p: float) -> bool: return not is_equal_approx(p, 1.0))
		and pitches.all(func(p: float) -> bool: return absf(p - 1.0) <= SFX.PITCH_JITTER + 1e-4), str(pitches))

	# Grab, drop, throw a rack part
	var part = null
	for node in workshop.rack_stock.find_children("*", "RigidBody3D", true, false):
		if node.has_method("is_mounted") and not node.is_mounted() and node.mass < 10.0:
			part = node
			break
	mark = _mark()
	player.holder.pickup(part)
	await _ticks(0.5)
	player.holder.release()
	await _ticks(0.8)
	player.holder.pickup(part)
	await _ticks(0.4)
	player.holder.throw()
	var thrown_mark := _mark()
	await _ticks(2.0)
	var grabs: Array = _played(mark, "grab")
	_check("grab, drop and throw play at the part", grabs.size() == 2 and _played(mark, "drop").size() == 1
		and _played(mark, "throw").size() == 1 and grabs[0][1] is AudioStreamPlayer3D, _names(mark))
	_check("tonal sounds keep their pitch (grab)", grabs.all(func(e: Array) -> bool: return not is_instance_valid(e[1]) or e[1].pitch_scale == 1.0))
	var impacts: Array = log.slice(thrown_mark).filter(func(e: Array) -> bool: return String(e[0]).begins_with("impact_hard_"))
	_check("the thrown part hits the floor: a hard impact", not impacts.is_empty(), _names(thrown_mark))

	# Outside, on regolith
	_place_player(_kit(-1.0, 14.0, 0.0) + Vector3(0.0, 2.0, 0.0))
	await _ticks(0.3)
	_place_player(_ground_below(_kit(-1.0, 14.0, 0.0)) + Vector3(0.0, 1.6, 0.0))
	mark = _mark()
	await _ticks(2.5)
	_check("falling 1.6 m onto the ground outside: a landing on regolith", _played(mark, "land_regolith").size() == 1, _names(mark))
	_check("ambience outside: the Moon's bed", SFX._ambience_gain[&"amb_moon"] > 0.99 and SFX._ambience_gain[&"amb_workshop"] < 0.01, str(SFX._ambience_gain))
	mark = _mark()
	await _walk(1.5)
	_check("walking outside: steps on regolith", _played(mark, "step_regolith").size() >= 2 and _played(mark, "step_floor").is_empty(), _names(mark))
	_place_player(workshop.to_global(workshop.anchors["spawn_player"]) + Vector3(0.0, 0.05, 0.0))
	await _ticks(0.5)


func _ground_below(at: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 20.0, at + Vector3.DOWN * 20.0, 1)
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"] if hit else at


# 5 ---------------------------------------------------------------------------------------------
func _socket_checks() -> void:
	rover.battery.charge = rover.battery.capacity
	var mark := _mark()
	var battery = rover.battery_socket.unmount()
	battery.global_position += Vector3.UP * 2.0          # out of the socket's capture box
	battery.freeze = true
	await _ticks(0.3)
	_check("battery out: release and power-down", _played(mark, "part_release").size() == 1 and _played(mark, "power_down").size() == 1, _names(mark))
	mark = _mark()
	battery.freeze = false
	rover.battery_socket.mount(battery)
	await _ticks(0.3)
	_check("battery in: seat and power-up", _played(mark, "part_seat").size() == 1 and _played(mark, "power_up").size() == 1, _names(mark))
	mark = _mark()
	rover.battery_socket._show_refusal(battery, "test")
	await _ticks(0.1)
	_check("a refused part: the refusal", _played(mark, "part_refused").size() == 1, _names(mark))
	await _ticks(1.0)


# 6 ---------------------------------------------------------------------------------------------
func _drive_checks() -> void:
	_place_rover(_dock().x, 8.0)
	await _ticks(1.0)
	var mark := _mark()
	GS.drive(rover)
	await _ticks(0.3)
	_check("taking the rover: the link opens", _played(mark, "link_open").size() == 1, _names(mark))
	Input.action_press("move_forward")
	await _ticks(1.5)
	var rolling = rover.get_node("Sfx_rolling_loop")
	var engine = rover.get_node("EngineSound")
	var audible: Array = SFX.audible_loops()
	_check("driving: the wheels roll, the main layer", rolling.playing and rolling.volume_db > -20.0
		and audible.any(func(l) -> bool: return l.player == rolling and l.main), "%.1f dB" % rolling.volume_db)
	_check("driving: the motor whirs on SFX, the main layer", engine.bus == &"SFX"
		and audible.any(func(l) -> bool: return l.player == engine and l.main))
	_check("driving: everything else ducks", SFX._duck < db_to_linear(SFX.DUCK_DB) + 0.01, "%.1f dB" % linear_to_db(SFX._duck))
	# More loops than allowed: the most important ones win
	var extra: Array = []
	for i in 6:
		var loop = SFX.make_loop(&"door_loop", rover, -6.0, Vector3(0, 0, 2.0 + i))
		loop.gain = 1.0
		extra.append(loop)
	await _ticks(1.0)
	audible = SFX.audible_loops()
	_check("at most %d loops heard, the driven rover's among them" % SFX.MAX_LOOPS, audible.size() <= SFX.MAX_LOOPS
		and audible.any(func(l) -> bool: return l.player == rolling), "%d heard" % audible.size())
	for loop in extra:
		loop.player.queue_free()
	Input.action_release("move_forward")
	await _ticks(2.0)
	# A bump
	_place_rover(_dock().x, 8.0, 0.7)
	mark = _mark()
	await _ticks(2.0)
	_check("a drop onto the ground: a bump", _played(mark, "bump").size() >= 1, _names(mark))
	# Battery low, once
	var battery = rover.battery
	battery.charge = battery.capacity * (battery.sag_threshold + 0.05)
	await _ticks(0.2)
	mark = _mark()
	battery.charge = battery.capacity * (battery.sag_threshold - 0.01)
	await _ticks(0.5)
	battery.charge = battery.capacity * (battery.sag_threshold - 0.02)
	await _ticks(0.5)
	_check("battery low while driving: one alert, not ducked", _played(mark, "battery_low").size() == 1, _names(mark))
	mark = _mark()
	battery.charge = 0.0
	await _ticks(0.3)
	_check("battery empty: power-down", _played(mark, "power_down").size() == 1, _names(mark))
	battery.charge = battery.capacity
	await _ticks(0.3)
	mark = _mark()
	GS.change_state_to(GS.State.IN_GAME_PLAYER)
	await _ticks(0.3)
	_check("leaving the rover: the link closes", _played(mark, "link_close").size() == 1, _names(mark))


# 7 ---------------------------------------------------------------------------------------------
func _door_checks() -> void:
	_place_rover(_dock().x, _dock().y)
	await _ticks(1.0)
	var mark := _mark()
	workshop._on_door_panel_interacted(player)
	await _ticks(workshop.door_open_time * 0.5)
	var loop = workshop.get_node("DoorShadowSeal/Sfx_door_loop")
	var moving_db: float = loop.volume_db
	await _ticks(workshop.door_open_time * 0.5 + 0.6)
	_check("bay door: unlatch, the drive while it moves, the seal", _played(mark, "door_start").size() == 1
		and moving_db > -20.0 and _played(mark, "door_stop").size() == 1, "%s, loop %.1f dB" % [_names(mark), moving_db])
	workshop._on_door_panel_interacted(player)
	await _ticks(workshop.door_open_time + 1.0)


# 8 ---------------------------------------------------------------------------------------------
func _charger_checks() -> void:
	var battery = rover.battery
	battery.charge = battery.capacity * 0.997
	_place_rover(_dock().x, _dock().y + 2.0)
	await _ticks(2.0)
	_place_rover(_dock().x, _dock().y)
	var mark := _mark()
	await _ticks(4.0)
	_check("docking: the charger connects, then fully charged", _played(mark, "charger_connect").size() == 1
		and _played(mark, "charger_full").size() == 1, "%s, %s" % [_names(mark), workshop.pad.get_status_text()])
	mark = _mark()
	var taken = rover.battery_socket.unmount()
	taken.global_position += Vector3.UP * 2.0
	taken.freeze = true
	await _ticks(1.0)
	taken.freeze = false
	_check("battery taken off the pad: a fault", _played(mark, "charger_fault").size() == 1, _names(mark))
	rover.battery_socket.mount(taken)
	await _ticks(1.0)
