class_name CutsceneDirector

extends Node

## Plays the level's cutscenes from res/story/cutscenes.json (format in its _readme). A cutscene
## enters GameState CUTSCENE (both controllers locked), drives its own camera, actions and lines,
## and returns to the exact state and camera it started from. Each plays once per campaign
## (CampaignState.mark_cutscene_played, marked when it starts). Hold cutscene_skip to skip.

signal started(id: String)
signal finished(id: String, skipped: bool)

const DATA_PATH: String = "res://res/story/cutscenes.json"
const SKIP_HOLD: float = 1.0
const SKIP_FADE: float = 0.3
const MAX_STEP: float = 1.0 / 20.0
const DIALOGUE_GRACE: float = 4.0
const CAMERA_CLEARANCE: float = 1.0
const CAMERA_FAR: float = 50000.0
const OPENING_EVENT: String = "campaign_start"
const MANUAL_EVENT: String = "manual"
const EVENT_KINDS: PackedStringArray = ["objective", "mission_started", "mission_completed"]

enum Phase {IDLE, PLAYING, SKIP_FADE, WAIT_RELEASE, WAIT_DIALOGUE}

## Triggered cutscenes play on their own (manual ones always can). Off under a script run, so the
## loop tests don't sit through them; tests that check cutscenes turn it on.
static var autoplay: bool = not _is_script_run()

var level: Node = null
var director: Node = null
var cutscenes: Dictionary = {}
var lines: Dictionary = {}
var playing_id: String = ""
var phase: Phase = Phase.IDLE
var time: float = 0.0
var skip_hold: float = 0.0
var skipped: bool = false
var opening_pending: bool = false
var camera: Camera3D = null

var _shots: Array = []
var _actions: Array = []
var _lines: Array = []
var _total: float = 0.0
var _rest: Dictionary = {}
var _own: Array[DialogSequence] = []
var _previous_state: int = -1
var _after_state: int = -1
var _previous_camera: Camera3D = null
var _phase_time: float = 0.0
var _skip_armed: bool = false
var _held_dialogue: bool = false
var _queue: Array[String] = []


func _ready() -> void:
	load_data()
	for problem in problems():
		push_warning("Cutscenes: " + problem)
	CampaignState.objective_completed.connect(func(id: String) -> void: _on_event("objective:" + id))
	CampaignState.mission_started.connect(func(id: String) -> void: _on_event("mission_started:" + id))
	CampaignState.mission_completed.connect(func(id: String) -> void: _on_event("mission_completed:" + id))
	SceneLoader.level_loaded.connect(_on_level_loaded)
	opening_pending = autoplay and _opening_id() != "" and _is_new_campaign()
	if opening_pending and cutscenes[_opening_id()].get("hold_dialogue", false):
		DialogueTriggers.hold = true


func _exit_tree() -> void:
	if phase != Phase.IDLE:
		GameState.cutscene_active = false
		if _held_dialogue:
			DialogueTriggers.hold = false
		var screen := _screen()
		if screen:
			screen.finish(true)
	elif opening_pending:
		DialogueTriggers.hold = false


func load_data() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else null
	cutscenes = data.get("cutscenes", {}) if data is Dictionary else {}
	lines = data.get("lines", {}) if data is Dictionary else {}


## Data errors: unknown events, lines missing or shared with the trigger files, shots without a duration
func problems() -> PackedStringArray:
	var result: PackedStringArray = []
	for id in cutscenes:
		var on: String = str(cutscenes[id].get("on", ""))
		if on != OPENING_EVENT and on != MANUAL_EVENT and not DialogueTriggers.is_real_event(on):
			result.append("\"%s\" has an unknown event \"%s\"" % [id, on])
		for shot in cutscenes[id].get("shots", []):
			if float(shot.get("duration", 0.0)) <= 0.0:
				result.append("\"%s\" has a shot without a duration" % id)
			for line in shot.get("lines", []):
				if not (lines.get(str(line.get("id", ""))) is Dictionary):
					result.append("\"%s\" names a missing line \"%s\"" % [id, line.get("id", "")])
	for line_id in lines:
		if DialogueTriggers.lines.has(line_id):
			result.append("line \"%s\" is also in lines.json" % line_id)
	return result


func has_cutscene(id: String) -> bool:
	return cutscenes.has(id)


func is_playing() -> bool:
	return phase != Phase.IDLE


## Playing, about to play the opening, or with a cutscene waiting
func is_busy() -> bool:
	return is_playing() or opening_pending or not _queue.is_empty()


func duration(id: String) -> float:
	var total: float = 0.0
	for shot in cutscenes.get(id, {}).get("shots", []):
		total += float(shot.get("duration", 0.0))
	return total


## Plays `id` and returns when it is over (false if it can't start). `after_state` (a GameState
## State) is where it hands over instead of the state it started from.
func play(id: String, after_state: int = -1) -> bool:
	if not cutscenes.has(id) or is_playing() or level == null:
		return false
	var cutscene: Dictionary = cutscenes[id]
	CampaignState.mark_cutscene_played(id)
	playing_id = id
	_after_state = after_state
	_previous_state = GameState.state if GameState.state != GameState.State.PAUSED else GameState.last_in_game_state
	_previous_camera = get_viewport().get_camera_3d()
	_build(cutscene)
	_held_dialogue = bool(cutscene.get("hold_dialogue", false))
	if _held_dialogue:
		DialogueTriggers.hold = true
	camera = Camera3D.new()
	camera.name = "CutsceneCamera"
	camera.far = float(level.get("camera_far")) if level.get("camera_far") != null else CAMERA_FAR
	level.add_child(camera)
	time = 0.0
	skip_hold = 0.0
	skipped = false
	_skip_armed = not Input.is_action_pressed(&"cutscene_skip")
	GameState.cutscene_active = true
	GameState.change_state_to(GameState.State.CUTSCENE)
	var screen := _screen()
	if screen:
		screen.begin(bool(cutscene.get("letterbox", true)))
	phase = Phase.PLAYING
	_evaluate(0.0)
	camera.make_current()
	started.emit(id)
	var result: Array = await finished
	return result[0] == id


## Ends the playing cutscene as if the skip were held: every action's end state, its lines cut
func skip() -> void:
	if phase == Phase.PLAYING:
		_begin_skip()


func _process(delta: float) -> void:
	if phase == Phase.IDLE:
		return
	var step: float = minf(delta, MAX_STEP)
	var screen := _screen()
	match phase:
		Phase.PLAYING:
			_update_skip_input(step, screen)
			if phase != Phase.PLAYING:
				return
			time += step
			_evaluate(time)
			if time >= _total:
				_phase_time = 0.0
				phase = Phase.WAIT_DIALOGUE
		Phase.SKIP_FADE:
			_phase_time += step
			if _phase_time >= SKIP_FADE:
				_apply_end_states()
				phase = Phase.WAIT_RELEASE
		Phase.WAIT_RELEASE:
			if not Input.is_action_pressed(&"cutscene_skip"):
				_finish()
		Phase.WAIT_DIALOGUE:
			_phase_time += step
			if _phase_time >= DIALOGUE_GRACE or not _own.any(func(s: DialogSequence) -> bool: return DialogServer.is_sequence_pending(s)):
				_finish()


func _update_skip_input(step: float, screen: CutsceneScreen) -> void:
	var held: bool = Input.is_action_pressed(&"cutscene_skip")
	if not held:
		_skip_armed = true
	skip_hold = skip_hold + step if held and _skip_armed else 0.0
	if screen:
		screen.set_skip(clampf(skip_hold / SKIP_HOLD, 0.0, 1.0), skip_hold > 0.0)
	if skip_hold >= SKIP_HOLD:
		_begin_skip()


func _begin_skip() -> void:
	skipped = true
	phase = Phase.SKIP_FADE
	_phase_time = 0.0
	for sequence in _own:
		DialogServer.cancel_sequence(sequence)
	var screen := _screen()
	if screen:
		screen.fade_black(1.0, SKIP_FADE)


func _finish() -> void:
	var id := playing_id
	phase = Phase.IDLE
	GameState.cutscene_active = false
	var screen := _screen()
	if screen:
		screen.finish(false)
	var state: int = _after_state if _after_state >= 0 else _previous_state
	GameState.change_state_to(state)
	if state == GameState.State.IN_GAME_PLAYER and is_instance_valid(GameState.player):
		GameState.player.camera.make_current()
	elif is_instance_valid(_previous_camera) and state != GameState.State.IN_GAME_ROBOT:
		_previous_camera.make_current()
	if is_instance_valid(camera):
		camera.queue_free()
	camera = null
	if _held_dialogue:
		_held_dialogue = false
		DialogueTriggers.release()
	if id == _opening_id():
		opening_pending = false
	playing_id = ""
	_own.clear()
	finished.emit(id, skipped)
	_play_queued.call_deferred()


# ---------------------------------------------------------------- triggers

func _opening_id() -> String:
	for id in cutscenes:
		if cutscenes[id].get("on", "") == OPENING_EVENT:
			return id
	return ""


func _is_new_campaign() -> bool:
	var order := CampaignState.mission_order()
	if order.is_empty() or CampaignState.current_mission() != order[0]:
		return false
	for objective in CampaignState.mission_objectives(CampaignState.current_mission(), true):
		if CampaignState.is_objective_done(objective):
			return false
	return not CampaignState.is_cutscene_played(_opening_id())


func _on_level_loaded(_level_name: String) -> void:
	if opening_pending and level and level.is_inside_tree() and is_instance_valid(GameState.player):
		play(_opening_id())


func _on_event(event: String) -> void:
	if not autoplay or level == null or not is_inside_tree():
		return
	for id in cutscenes:
		if cutscenes[id].get("on", "") == event and not CampaignState.is_cutscene_played(id) and not id in _queue:
			_queue.append(id)
	_play_queued.call_deferred()


func _play_queued() -> void:
	if is_playing() or _queue.is_empty() or not is_instance_valid(GameState.player):
		return
	var id: String = _queue.pop_front()
	if not CampaignState.is_cutscene_played(id):
		play(id)


# ---------------------------------------------------------------- timeline

func _build(cutscene: Dictionary) -> void:
	_shots.clear()
	_actions.clear()
	_lines.clear()
	_rest.clear()
	_own.clear()
	var start: float = 0.0
	for shot in cutscene.get("shots", []):
		var length: float = float(shot.get("duration", 0.0))
		_shots.append({"start": start, "end": start + length, "data": shot})
		for action in shot.get("actions", []):
			_actions.append({"at": start + float(action.get("at", 0.0)), "data": action, "done": false})
			if action.get("node") is String:
				_remember_rest(action["node"])
		for line in shot.get("lines", []):
			_lines.append({"at": start + float(line.get("at", 0.0)), "id": str(line.get("id", "")), "done": false})
		var camera_data: Dictionary = shot.get("camera", {})
		for key in ["anchor", "frame", "side"]:
			if camera_data.get(key) is String:
				_remember_rest(camera_data[key])
		start += length
	_total = start
	_actions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["at"] < b["at"])


func _remember_rest(path: String) -> void:
	var node := resolve(path)
	if node and not _rest.has(path):
		_rest[path] = node.global_transform


func _evaluate(t: float) -> void:
	var shot: Dictionary = _shot_at(t)
	if not shot.is_empty():
		var local: float = t - shot["start"]
		_update_camera(shot["data"], local, shot["end"] - shot["start"])
		_update_screen(shot["data"], local, shot["end"] - shot["start"])
	for action in _actions:
		if action["at"] > t:
			continue
		if action["data"].get("do") == "path":
			_apply_path(action["data"], t - action["at"])
		elif not action["done"]:
			action["done"] = true
			_apply_action(action["data"])
	for line in _lines:
		if not line["done"] and line["at"] <= t:
			line["done"] = true
			_queue_line(line["id"])


func _shot_at(t: float) -> Dictionary:
	for shot in _shots:
		if t < shot["end"]:
			return shot
	return _shots.back() if not _shots.is_empty() else {}


func _apply_end_states() -> void:
	_evaluate(_total)
	for action in _actions:
		if action["data"].get("do") == "path":
			_apply_path(action["data"], INF)


func _queue_line(id: String) -> void:
	var entry: Variant = lines.get(id)
	if not entry is Dictionary:
		return
	var sequence := DialogSequence.new()
	sequence.dialogs = [DialogueTriggers.make_dialog(entry)]
	_own.append(sequence)
	DialogServer.queue_sequence(sequence)


# ---------------------------------------------------------------- camera

func _update_camera(shot: Dictionary, local: float, length: float) -> void:
	var data: Dictionary = shot.get("camera", {})
	if data.is_empty() or camera == null:
		return
	var e: float = ease_value(str(data.get("ease", "in_out")), clampf(local / length, 0.0, 1.0))
	var position: Vector3
	var target: Vector3
	var fov: float
	if data.get("frame") is String:
		var framed := resolve(data["frame"])
		if framed == null:
			return
		var centre: Vector3 = framed.global_position
		var side_node := resolve(str(data.get("side", "")))
		var away: Vector3 = (side_node.global_position - centre) if side_node else Vector3.BACK
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3.BACK
		away = away.rotated(Vector3.UP, deg_to_rad(float(data.get("turn", 0.0))))
		var distance: float = _range(data.get("distance", 9.0), e)
		position = centre + away * distance + Vector3.UP * _range(data.get("height", 3.0), e)
		target = centre + Vector3.UP * float(data.get("look_height", 1.5))
		fov = _range(data.get("fov", 70.0), e)
	else:
		var from: Dictionary = data.get("from", {})
		var to: Dictionary = data.get("to", from)
		var origin: Vector3 = _anchor_origin(data)
		position = origin + _vec(from.get("pos")).lerp(_vec(to.get("pos", from.get("pos"))), e)
		var look_node := resolve(str(data.get("look_node", "")))
		if look_node:
			target = look_node.global_position + _vec(data.get("look_offset"))
		else:
			target = origin + _vec(from.get("look")).lerp(_vec(to.get("look", from.get("look"))), e)
		fov = lerpf(float(from.get("fov", 60.0)), float(to.get("fov", from.get("fov", 60.0))), e)
	position.y = maxf(position.y, _ground(position) + CAMERA_CLEARANCE)
	camera.global_position = position
	camera.fov = fov
	if not position.is_equal_approx(target):
		camera.look_at(target, Vector3.UP if absf((target - position).normalized().y) < 0.999 else Vector3.FORWARD)


func _anchor_origin(data: Dictionary) -> Vector3:
	var path: String = str(data.get("anchor", ""))
	if path.is_empty():
		return Vector3.ZERO
	if data.get("live", false):
		var node := resolve(path)
		return node.global_position if node else Vector3.ZERO
	return (_rest[path] as Transform3D).origin if _rest.has(path) else Vector3.ZERO


func _ground(point: Vector3) -> float:
	var terrain: Node = level.get_node_or_null("Terrain") if level else null
	if terrain and terrain.has_method("height_at"):
		return terrain.height_at(point.x, point.z)
	return -INF


static func ease_value(kind: String, x: float) -> float:
	match kind:
		"linear":
			return x
		"in":
			return x * x * x
		"out":
			return 1.0 - pow(1.0 - x, 3.0)
	return x * x * (3.0 - 2.0 * x)


static func _range(value: Variant, e: float) -> float:
	if value is Array and value.size() >= 2:
		return lerpf(float(value[0]), float(value[1]), e)
	return float(value)


static func _vec(value: Variant) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2])) if value is Array and value.size() >= 3 else Vector3.ZERO


# ---------------------------------------------------------------- actions

## A path: "keys" [[t, x, y, z], ...], offsets in world axes from the node's place when the cutscene
## started, through every key with smooth (Hermite) speeds, stopping at the last
func _apply_path(action: Dictionary, local: float) -> void:
	var path: String = str(action.get("node", ""))
	var node := resolve(path) as Node3D
	var keys: Array = action.get("keys", [])
	if node == null or keys.is_empty() or not _rest.has(path):
		return
	var rest: Transform3D = _rest[path]
	node.global_position = rest.origin + path_offset(keys, local)


static func path_offset(keys: Array, t: float) -> Vector3:
	if t <= float(keys[0][0]):
		return _vec(keys[0].slice(1))
	var last: int = keys.size() - 1
	if t >= float(keys[last][0]):
		return _vec(keys[last].slice(1))
	var i: int = 0
	while float(keys[i + 1][0]) < t:
		i += 1
	var t0: float = keys[i][0]
	var t1: float = keys[i + 1][0]
	var h: float = t1 - t0
	var p0 := _vec(keys[i].slice(1))
	var p1 := _vec(keys[i + 1].slice(1))
	var m0 := _tangent(keys, i)
	var m1 := _tangent(keys, i + 1)
	var s: float = (t - t0) / h
	var s2: float = s * s
	var s3: float = s2 * s
	return (2.0 * s3 - 3.0 * s2 + 1.0) * p0 + (s3 - 2.0 * s2 + s) * h * m0 \
		+ (-2.0 * s3 + 3.0 * s2) * p1 + (s3 - s2) * h * m1


static func _tangent(keys: Array, i: int) -> Vector3:
	var last: int = keys.size() - 1
	if i == last:
		return Vector3.ZERO
	var a: int = maxi(i - 1, 0)
	var b: int = mini(i + 1, last)
	return (_vec(keys[b].slice(1)) - _vec(keys[a].slice(1))) / (float(keys[b][0]) - float(keys[a][0]))


func _apply_action(action: Dictionary) -> void:
	var node := resolve(str(action.get("node", "")))
	match str(action.get("do", "")):
		"call":
			if node and node.has_method(str(action.get("method", ""))):
				node.callv(str(action["method"]), action.get("args", []))
		"visible":
			if node is Node3D:
				node.visible = bool(action.get("on", true))
		"place_player":
			_place_player(node as Node3D)


## Stands the player on `marker`, facing its -Z
func _place_player(marker: Node3D) -> void:
	var player: Player = GameState.player
	if marker == null or not is_instance_valid(player):
		return
	player.global_position = marker.global_position
	player.linear_velocity = Vector3.ZERO
	var look: Vector3 = -marker.global_basis.z
	if player.controller:
		player.controller.camera_azimuth = atan2(-look.x, -look.z)


## A node by path from the level root, or @kite (the workshop's rover) / @player
func resolve(path: String) -> Node:
	if path.is_empty() or level == null:
		return null
	if path == "@kite":
		return director.get("rover") if director else null
	if path == "@player":
		return GameState.player if is_instance_valid(GameState.player) else null
	return level.get_node_or_null(path)


func _update_screen(shot: Dictionary, local: float, length: float) -> void:
	var screen := _screen()
	if screen == null:
		return
	var title: Dictionary = shot.get("title", {})
	if not title.is_empty():
		var out_at: float = length - float(title.get("out", 1.4))
		var fade_out: float = 1.0 - clampf((local - out_at) / 0.8, 0.0, 1.0)
		screen.set_title(str(title.get("text", "")), str(title.get("caption", "")),
			clampf((local - float(title.get("text_in", 0.8))) / 1.0, 0.0, 1.0) * fade_out,
			clampf((local - float(title.get("caption_in", 3.8))) / 1.0, 0.0, 1.0) * fade_out)
	else:
		screen.set_title("", "", 0.0, 0.0)
	if phase == Phase.PLAYING:
		var black: float = 1.0 if shot.get("black", false) else 0.0
		var fade_in: float = float(shot.get("fade_in", 0.0))
		if fade_in > 0.0:
			black = maxf(black, 1.0 - clampf(local / fade_in, 0.0, 1.0))
		screen.set_black(black)
	screen.set_caption(str(shot.get("caption", "")))


func _screen() -> CutsceneScreen:
	return get_tree().get_first_node_in_group(&"cutscene_screen") as CutsceneScreen if is_inside_tree() else null


static func _is_script_run() -> bool:
	var args: PackedStringArray = OS.get_cmdline_args()
	return args.has("-s") or args.has("--script")
