extends Node

## Gameplay sound effects (autoload; pauses with the game). The sounds are made in game/music
## (sfx_sounds.py) and copied into res/audio/sfx/ by export_to_game.py.
##
## - play(&"grab", position) plays a one-shot: at a position or node (3D, mono) or with no
##   position (2D). Names with variations (<name>_1 .. _N) pick one at random, never the same
##   twice in a row. Non-tonal sounds (UNTUNED: steps, impacts, bumps, rolling) get a small random
##   pitch; tonal ones are tuned to the music's key and keep their pitch.
## - Loops (make_loop / adopt_loop): their owner sets `gain` (and `main`) every frame; at most
##   MAX_LOOPS are heard at once, the most important and loudest first.
## - Ducking: while a rover is driven, its motor and wheels are the main layer; every other sound
##   (and the ambience) ducks under them, more as the motor gets louder. Alerts don't duck.
## - Ambience beds on the Ambience bus: the workshop's room tone inside any Workshop, the Moon's
##   near-silence outside on a level with MoonTerrain, chosen by where the camera is.
## - Observers: as nodes enter the tree, Players get PlayerSounds, Robots RoverSounds and
##   Workshops WorkshopSounds (src/audio/); HotswapSockets (not the cargo socket) and loose
##   RigidBody3D props are watched from here (mount / release / refusal, impacts).
## No gameplay sounds outside a level (main menu backdrop, loading), nor for QUIET_AFTER_LOAD
## seconds after one starts (parts mounting, props settling).

## A one-shot started (tests listen to it)
signal played(sound: StringName, player: Node)

const DIR: String = "res://res/audio/sfx/"
const SFX_BUS: StringName = &"SFX"
const AMBIENCE_BUS: StringName = &"Ambience"
const MAX_VARIATIONS: int = 8
## Base names whose sounds are not tuned to the music, so they may play at a random pitch
const UNTUNED: Array[String] = ["step_", "land_", "impact_", "bump", "throw", "rolling"]
const PITCH_JITTER: float = 0.05
## 3D sounds: full level within UNIT_SIZE m, silent beyond MAX_DISTANCE; farther sounds are also
## muffled (the distance lowpass)
const UNIT_SIZE: float = 3.0
const MAX_DISTANCE: float = 40.0
const DISTANCE_LOWPASS: float = 2500.0
const QUIET_AFTER_LOAD: float = 1.5
const MAX_ONE_SHOTS: int = 16
## Loops (not counting the ambience beds) heard at once
const MAX_LOOPS: int = 4
const LOOP_FADE_TIME: float = 0.3
## Ducking while driving: DUCK_DB, plus up to DUCK_MOTOR_DB more with the motor's loudness
const DUCK_DB: float = -4.0
const DUCK_MOTOR_DB: float = -6.0
## Ambience beds: levels (dB) and crossfade time (s)
const AMBIENCE_DB: Dictionary = {&"amb_workshop": 0.0, &"amb_moon": 0.0}
const AMBIENCE_FADE_TIME: float = 2.0
## Impacts of loose props: the least speed change (m/s) in one step that makes a sound, the change
## that plays at full level, and the least time between two of the same prop
const IMPACT_MIN_SPEED: float = 0.6
const IMPACT_FULL_SPEED: float = 5.0
const IMPACT_COOLDOWN: float = 0.12
## Prop weight classes (kg): light below the first, heavy from the second
const IMPACT_MASSES: Vector2 = Vector2(4.0, 15.0)
## A grab right after a socket gave the same part out is part of the release sound
const GRAB_AFTER_RELEASE: float = 0.15


## A looping sound whose owner sets `gain` (0..1, linear) every frame
class Loop:
	var player: Node
	## dB at gain 1
	var base_db: float = 0.0
	var gain: float = 0.0
	## How loud it really is (0..1), for choosing which loops are heard; < 0: gain
	var audible: float = -1.0
	## The driven rover's motor or wheels: never ducked, preferred
	var main: bool = false
	## Our own stream player: stopped while silent. Adopted players (the motor's generator)
	## keep playing.
	var owned: bool = true
	var limit: float = 1.0
	var silent_time: float = 0.0


var _streams: Dictionary = {}          # base name -> Array[AudioStream]
var _last_variation: Dictionary = {}
var _loops: Array = []                # of Loop
var _one_shots: int = 0
var _quiet_until: float = 0.0
var _time: float = 0.0
var _duck: float = 1.0                 # linear gain on everything but the main layer and alerts
var _ambience: Dictionary = {}         # name -> AudioStreamPlayer
var _ambience_gain: Dictionary = {}    # name -> current linear gain
var _workshops: Array = []
var _terrains: Array = []              # MoonTerrains: the level is on the Moon
var _props: Dictionary = {}            # RigidBody3D -> {velocity, cooldown}
var _released_part: Object = null
var _released_time: float = -INF


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	GameState.state_changed.connect(_on_state_changed)
	SceneLoader.level_loaded.connect(func(_name) -> void: _quiet_until = _time + QUIET_AFTER_LOAD)
	for bed in AMBIENCE_DB:
		var player := AudioStreamPlayer.new()
		player.name = String(bed)
		player.stream = _variants(bed)[0] if not _variants(bed).is_empty() else null
		player.bus = AMBIENCE_BUS
		add_child(player)
		_ambience[bed] = player
		_ambience_gain[bed] = 0.0


## True while gameplay sounds may play: in a level, not just after it started
func is_active() -> bool:
	var s = GameState.state
	if s == GameState.State.MAIN_MENU or s == GameState.State.LOADING:
		return false
	return _time >= _quiet_until


## Plays a one-shot. `at`: a Vector3 or Node3D for a 3D sound, null for a 2D one. `main`: part of
## the driven rover's main layer, `duck` false for alerts: neither ducks while driving.
func play(sound: StringName, at: Variant = null, volume_db: float = 0.0, main: bool = false,
		duck: bool = true) -> Node:
	if not is_active() or _one_shots >= MAX_ONE_SHOTS:
		return null
	var variants: Array = _variants(sound)
	if variants.is_empty():
		push_warning("Sfx: no sound %s" % sound)
		return null
	var stream: AudioStream = variants[_pick(sound, variants.size())]
	var gain_db: float = volume_db + (0.0 if main or not duck else linear_to_db(_duck))
	var pitch: float = 1.0 + randf_range(-PITCH_JITTER, PITCH_JITTER) if is_untuned(sound) else 1.0
	var player: Node
	if at == null:
		var flat := AudioStreamPlayer.new()
		flat.stream = stream
		flat.volume_db = gain_db
		flat.pitch_scale = pitch
		flat.bus = SFX_BUS
		player = flat
		add_child(flat)
		flat.play()
	else:
		var spatial := _make_3d(stream, gain_db)
		spatial.pitch_scale = pitch
		player = spatial
		add_child(spatial)
		spatial.global_position = at if at is Vector3 else (at as Node3D).global_position
		spatial.play()
	_one_shots += 1
	played.emit(sound, player)
	player.finished.connect(func() -> void:
		_one_shots -= 1
		player.queue_free())
	return player


func is_untuned(sound: StringName) -> bool:
	for prefix in UNTUNED:
		if String(sound).begins_with(prefix):
			return true
	return false


## A loop on `parent` (a Node3D: 3D at `offset` from it), managed here: set its `gain` every frame
func make_loop(sound: StringName, parent: Node3D, base_db: float = 0.0, offset: Vector3 = Vector3.ZERO) -> Loop:
	var variants: Array = _variants(sound)
	var loop := Loop.new()
	loop.base_db = base_db
	var player := _make_3d(variants[0] if not variants.is_empty() else null, -80.0)
	player.name = "Sfx_" + String(sound)
	player.position = offset
	parent.add_child(player)
	loop.player = player
	_loops.append(loop)
	return loop


## Manages an existing, always-playing loop player (the motor's generator): limit and ducking only
func adopt_loop(player: Node, base_db: float = 0.0) -> Loop:
	var loop := Loop.new()
	loop.player = player
	loop.base_db = base_db
	loop.gain = 1.0
	loop.owned = false
	_loops.append(loop)
	return loop


## Loops being heard now (limit not faded out, gain above silence)
func audible_loops() -> Array:
	return _loops.filter(func(l: Loop) -> bool:
		return is_instance_valid(l.player) and l.limit > 0.5 and _level(l) > 0.002)


## The camera the player hears through
func listener_position() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	return camera.global_position if camera else Vector3.ZERO


## True if `body` is part of the Moon's ground (terrain or rocks): it sounds like regolith
func is_regolith(body: Node) -> bool:
	var node: Node = body
	while node:
		if node is MoonTerrain or node is RockField:
			return true
		node = node.get_parent()
	return false


## Grab, drop and throw sounds for a holder (the player's or a rover's)
func watch_holder(holder: ObjectHolder) -> void:
	holder.picked_up.connect(func(object: RigidBody3D) -> void:
		if object == _released_part and _time - _released_time < GRAB_AFTER_RELEASE:
			return
		play(&"grab", object))
	holder.dropped.connect(func(object: RigidBody3D) -> void: play(&"drop", object))
	holder.thrown.connect(func(object: RigidBody3D) -> void: play(&"throw", object))


func _physics_process(delta: float) -> void:
	_time += delta
	_update_props(delta)


func _process(delta: float) -> void:
	_update_duck()
	_update_loops(delta)
	_update_ambience(delta)


# ---------------------------------------------------------------- observers

func _on_node_added(node: Node) -> void:
	# Reparented nodes (a mounted part, a socket following its anchor) come by again
	if node.has_meta(&"sfx_watched"):
		return
	if node is Player or node is Robot or node is Workshop or node is MoonTerrain \
			or node is HotswapSocket or node is RigidBody3D:
		node.set_meta(&"sfx_watched", true)
	if node is Player:
		_attach(node, preload("res://src/audio/player_sounds.gd").new())
	elif node is Robot:
		_attach(node, preload("res://src/audio/rover_sounds.gd").new())
	elif node is Workshop:
		_workshops.append(node)
		_attach(node, preload("res://src/audio/workshop_sounds.gd").new())
	elif node is MoonTerrain:
		_terrains.append(node)
	elif node is HotswapSocket:
		_watch_socket(node)
	if node is RigidBody3D and not (node is Player or node is Robot):
		_watch_prop(node)


# Observers are added once the node is ready (they read what its _ready sets up)
func _attach(target: Node, observer: Node) -> void:
	var add := func() -> void:
		if is_instance_valid(target) and target.is_inside_tree():
			target.add_child(observer)
		else:
			observer.free()
	add.call_deferred()


func _watch_socket(socket: HotswapSocket) -> void:
	if socket.accepted_type == HotswapPart.PartType.CARGO:
		return                          # the IRIS delivery gets its own sounds later
	socket.part_mounted.connect(func(_part: HotswapPart) -> void: play(&"part_seat", socket))
	socket.part_unmounted.connect(func(part: HotswapPart) -> void:
		_released_part = part
		_released_time = _time
		play(&"part_release", socket))
	socket.part_refused.connect(func(_part: HotswapPart) -> void: play(&"part_refused", socket))


func _watch_prop(body: RigidBody3D) -> void:
	# Impacts need the contacts
	body.contact_monitor = true
	body.max_contacts_reported = maxi(body.max_contacts_reported, 4)
	_props[body] = {"velocity": Vector3.ZERO, "cooldown": 0.0}


# A loose prop whose velocity changed sharply in one step while touching something hit it
func _update_props(delta: float) -> void:
	for gone in _props.keys().filter(func(b) -> bool: return not is_instance_valid(b)):
		_props.erase(gone)
	for body: RigidBody3D in _props:
		if not body.is_inside_tree():
			continue
		var entry: Dictionary = _props[body]
		var velocity: Vector3 = body.linear_velocity
		var change: float = (velocity - entry["velocity"]).length()
		entry["velocity"] = velocity
		entry["cooldown"] = maxf(entry["cooldown"] - delta, 0.0)
		if body.freeze or body.sleeping or change < IMPACT_MIN_SPEED or entry["cooldown"] > 0.0:
			continue
		if body.collision_layer == 1 << (ObjectHolder.HELD_LAYER - 1):
			continue                     # held: the holder pulls it about
		var touching: Array[Node3D] = body.get_colliding_bodies()
		if touching.is_empty():
			continue
		entry["cooldown"] = IMPACT_COOLDOWN
		var surface: String = "regolith" if touching.any(is_regolith) else "hard"
		var weight: String = "light" if body.mass < IMPACT_MASSES.x else ("medium" if body.mass < IMPACT_MASSES.y else "heavy")
		var level: float = clampf(remap(change, IMPACT_MIN_SPEED, IMPACT_FULL_SPEED, 0.0, 1.0), 0.0, 1.0)
		play(StringName("impact_%s_%s" % [surface, weight]), body.global_position, lerpf(-18.0, 0.0, sqrt(level)))


func _on_state_changed(old_state, new_state) -> void:
	var player := GameState.State.IN_GAME_PLAYER
	var robot := GameState.State.IN_GAME_ROBOT
	if old_state == player and new_state == robot:
		play(&"link_open", null, 0.0, false, false)
	elif old_state == robot and new_state == player:
		play(&"link_close", null, 0.0, false, false)


# ---------------------------------------------------------------- loops, ducking, ambience

func _update_duck() -> void:
	var target: float = 1.0
	if GameState.state == GameState.State.IN_GAME_ROBOT and is_instance_valid(GameState.robot):
		var engine := GameState.robot.get_node_or_null("EngineSound")
		var loudness: float = engine.loudness if engine and "loudness" in engine else 0.0
		target = db_to_linear(DUCK_DB + DUCK_MOTOR_DB * loudness)
	_duck = lerpf(_duck, target, 0.15)


func _level(loop: Loop) -> float:
	return loop.audible if loop.audible >= 0.0 else loop.gain


func _update_loops(delta: float) -> void:
	_loops = _loops.filter(func(l: Loop) -> bool: return is_instance_valid(l.player))
	var listener: Vector3 = listener_position()
	var ranked: Array = _loops.filter(func(l: Loop) -> bool: return _level(l) > 0.002)
	var score := func(l: Loop) -> float:
		var distance: float = (l.player as Node3D).global_position.distance_to(listener) if l.player is Node3D else 0.0
		return _level(l) * (4.0 if l.main else 1.0) / (1.0 + distance / 10.0)
	ranked.sort_custom(func(a: Loop, b: Loop) -> bool: return score.call(a) > score.call(b))
	var allowed: Array = ranked.slice(0, MAX_LOOPS)
	var active: bool = is_active()
	for loop in _loops:
		var target: float = 1.0 if allowed.has(loop) and active else 0.0
		loop.limit = move_toward(loop.limit, target, delta / LOOP_FADE_TIME)
		var gain: float = loop.gain * loop.limit * (1.0 if loop.main else _duck)
		loop.player.volume_db = loop.base_db + linear_to_db(maxf(gain, 1e-4))
		if not loop.owned:
			continue
		loop.silent_time = loop.silent_time + delta if gain <= 1e-4 else 0.0
		if gain > 1e-4 and not loop.player.playing:
			loop.player.play()
		elif loop.silent_time > 0.5 and loop.player.playing:
			loop.player.stop()


func _update_ambience(delta: float) -> void:
	var bed: StringName = &""
	if is_active():
		var listener: Vector3 = listener_position()
		_workshops = _workshops.filter(func(w) -> bool: return is_instance_valid(w))
		_terrains = _terrains.filter(func(t) -> bool: return is_instance_valid(t))
		if _workshops.any(func(w: Workshop) -> bool: return w._is_inside(listener)):
			bed = &"amb_workshop"
		elif not _terrains.is_empty():
			bed = &"amb_moon"
	for name in _ambience:
		var player: AudioStreamPlayer = _ambience[name]
		var gain: float = move_toward(_ambience_gain[name], 1.0 if name == bed else 0.0, delta / AMBIENCE_FADE_TIME)
		_ambience_gain[name] = gain
		player.volume_db = AMBIENCE_DB[name] + linear_to_db(maxf(gain * _duck, 1e-4))
		if gain > 0.0 and not player.playing and player.stream:
			player.play()
		elif gain <= 0.0 and player.playing:
			player.stop()


# ---------------------------------------------------------------- streams

func _make_3d(stream: AudioStream, volume_db: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = SFX_BUS
	player.volume_db = volume_db
	player.unit_size = UNIT_SIZE
	player.max_distance = MAX_DISTANCE
	player.attenuation_filter_cutoff_hz = DISTANCE_LOWPASS
	return player


func _variants(sound: StringName) -> Array:
	if _streams.has(sound):
		return _streams[sound]
	var variants: Array = []
	for extension in [".wav", ".ogg"]:
		if ResourceLoader.exists(DIR + sound + extension):
			variants.append(load(DIR + sound + extension))
	if variants.is_empty():
		for i in range(1, MAX_VARIATIONS + 1):
			var path: String = "%s%s_%d.wav" % [DIR, sound, i]
			if not ResourceLoader.exists(path):
				break
			variants.append(load(path))
	_streams[sound] = variants
	return variants


func _pick(sound: StringName, count: int) -> int:
	if count == 1:
		return 0
	var index: int = randi() % count
	if index == _last_variation.get(sound, -1):
		index = (index + 1 + randi() % (count - 1)) % count
	_last_variation[sound] = index
	return index
