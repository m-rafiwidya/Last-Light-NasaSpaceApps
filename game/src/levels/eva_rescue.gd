class_name EvaRescue

extends Node

## The spacewalk and Kite's rescue on foot (Moon level; MissionDirector, Workshop and Player are the
## systems it ties together). Optional: the player may leave through the bay door in a suit and carry
## a stranded Kite home with the existing pickup.
##
## - Suit oxygen: a simplified gameplay resource, not a physiological model. It drains 1 s per second
##   while the player is on foot outside the pressurised workshop (the building's footprint) and fills
##   again inside. It doesn't move while the game is paused, in a menu, the console or a cutscene
##   (only in-game states count, and the tree's pause stops _physics_process). Loading or changing the
##   control mode never refills it.
## - Warnings: "low" at LOW_FRACTION and "critical" at CRITICAL_FRACTION, as text on the HUD (EvaHud)
##   that names the way home, with a sound when each is crossed and again every CRITICAL_REPEAT s while
##   critical.
## - Running out: the emergency recovery runs for Kite when it is away from the pad (the usual time cost)
##   and the player is back inside, suit refilled, with no load screen.
## - Carrying: Player picks Kite up with the usual pickup when `allows_lift()` (stranded or stuck, out
##   in the field); here the tray is secured while Kite is held and let go on the drop.
## - Back inside from a spacewalk: an autosave is asked for (it waits while the player still carries Kite).
## - Hand pickups of mission cargo outdoors are refused (`hand_pickup_refused`): only Kite does that.

signal oxygen_changed(fraction: float)
signal warned(level: String)
signal exhausted

const GROUP: StringName = &"eva_rescue"
const LOW_FRACTION: float = 0.30
const CRITICAL_FRACTION: float = 0.15
## While critical, the warning sound repeats this often (s)
const CRITICAL_REPEAT: float = 15.0
## Seconds inside the workshop to fill an empty suit
const REFILL_SECONDS: float = 30.0

const MSG_NO_CARGO: String = "Only Kite can handle mission cargo outside. Leave it for Kite."
const MSG_RECOVERED: String = "Suit oxygen ran out. You were brought back to the habitat; Kite was recovered."
const MSG_RECOVERED_PLAYER: String = "Suit oxygen ran out. You were brought back to the habitat."

## How long the suit lasts outside (s). Tuned from measured walk and carry times to the farthest place
## Kite can strand, plus a 30% margin (tests/measure_eva_oxygen.gd, README "The spacewalk")
@export var capacity_s: float = 1200.0
@export var workshop: Workshop
@export var director: MissionDirector
## Where the player is put back after running out of oxygen
@export var home_point: Marker3D

var oxygen_s: float = 0.0
## "", "low" or "critical"
var warning: String = ""
## A short line for the HUD (`notice_text`) until `_notice_until` (real time, ms)
var notice_text: String = ""
var _notice_until: int = 0
var _critical_clock: float = 0.0
var _held_robot: Robot = null
var _ridden: Array[HotswapPart] = []
var _holder: ObjectHolder = null
var _was_outside: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	oxygen_s = capacity_s
	if workshop:
		workshop.set_eva_exit(true)
	_bind_player.call_deferred()


## The player is spawned after the level's own nodes: pick up its holder once it is there
func _bind_player() -> void:
	var player := GameState.player
	if not is_instance_valid(player) or _holder == player.holder:
		return
	_holder = player.holder
	_holder.picked_up.connect(_on_picked_up)
	_holder.dropped.connect(_on_dropped)
	_holder.thrown.connect(_on_dropped)


func fraction() -> float:
	return clampf(oxygen_s / capacity_s, 0.0, 1.0) if capacity_s > 0.0 else 0.0


func seconds_left() -> float:
	return oxygen_s


## "O2 78%  ·  about 15 min left"
func hud_text() -> String:
	var minutes: int = ceili(oxygen_s / 60.0)
	return "O2 %d%%  ·  about %d min left" % [roundi(fraction() * 100.0), minutes]


## True while the player is on foot outside the pressurised workshop
func on_eva() -> bool:
	var player := GameState.player
	return workshop != null and is_instance_valid(player) and not workshop.contains(player.global_position)


## Kite is liftable by hand here: the director says it is stranded or stopped in the field
func allows_lift(robot: Robot) -> bool:
	return director != null and robot == director.rover and director.can_player_lift()


## Hand pickups the suit refuses: mission cargo (crates, samples, the logger, cartridges) outside
## the workshop. Workshop pickups stay as they are. "" when allowed, else the HUD line.
func hand_pickup_refused(body: Node) -> String:
	var part := body as HotswapPart
	if part != null and part.part_type == HotswapPart.PartType.CARGO and on_eva():
		return MSG_NO_CARGO
	return ""


func say(text: String, seconds: float = 4.0) -> void:
	notice_text = text
	_notice_until = Time.get_ticks_msec() + int(seconds * 1000.0)


func notice() -> String:
	return notice_text if Time.get_ticks_msec() < _notice_until else ""


## "Base 142 m, 30 degrees left": where the habitat is, from the way the player faces
func home_hint() -> String:
	var player := GameState.player
	if workshop == null or not is_instance_valid(player):
		return ""
	var to_home: Vector3 = workshop.global_position - player.global_position
	to_home.y = 0.0
	var forward: Vector3 = -player.pivot.global_basis.z
	forward.y = 0.0
	if to_home.length() < 0.1 or forward.length() < 0.1:
		return "Habitat here"
	var angle: float = rad_to_deg(forward.signed_angle_to(to_home, Vector3.UP))
	var side: String = "ahead" if absf(angle) < 15.0 else "behind you" if absf(angle) > 165.0 \
		else "%d degrees %s" % [roundi(absf(angle)), "left" if angle > 0.0 else "right"]
	return "Habitat %d m, %s" % [roundi(to_home.length()), side]


## The warning line the HUD shows (text, not colour alone), "" when oxygen is fine
func warning_text() -> String:
	match warning:
		"critical":
			return "OXYGEN CRITICAL: GO HOME NOW  ·  %s" % home_hint()
		"low":
			return "OXYGEN LOW: HEAD HOME  ·  %s" % home_hint()
	return ""


func _physics_process(delta: float) -> void:
	if workshop == null or not GameState.is_in_game() or get_tree().paused:
		return
	if _holder == null:
		_bind_player()
	var player := GameState.player
	if not is_instance_valid(player):
		return
	var inside: bool = workshop.contains(player.global_position)
	if inside and _was_outside and director:
		SaveIndex.request_save()
	_was_outside = not inside
	if inside:
		oxygen_s = minf(oxygen_s + capacity_s / REFILL_SECONDS * delta, capacity_s)
		_critical_clock = 0.0
	else:
		oxygen_s = maxf(oxygen_s - delta, 0.0)
	oxygen_changed.emit(fraction())
	_update_warning(delta)
	if oxygen_s <= 0.0:
		_run_out()


func _update_warning(delta: float) -> void:
	var now: String = "critical" if fraction() <= CRITICAL_FRACTION else "low" if fraction() <= LOW_FRACTION else ""
	if now != warning:
		var worse: bool = now == "critical" or (now == "low" and warning == "")
		warning = now
		_critical_clock = 0.0
		if worse:
			_warn(now)
		return
	if warning == "critical" and on_eva():
		_critical_clock += delta
		if _critical_clock >= CRITICAL_REPEAT:
			_critical_clock = 0.0
			_warn(warning)


func _warn(level: String) -> void:
	AudioManager.play_ui(&"notification")
	warned.emit(level)


## Out of oxygen: let go of Kite, run the emergency recovery for it (when it is away from the pad) and
## put the player back in the workshop with a full suit
func _run_out() -> void:
	exhausted.emit()
	var player := GameState.player
	if is_instance_valid(player) and player.holder.held_object:
		player.holder.release()
	var kite_recovered: bool = director != null and director.start_oxygen_recovery()
	_bring_player_home()
	oxygen_s = capacity_s
	warning = ""
	say(MSG_RECOVERED if kite_recovered else MSG_RECOVERED_PLAYER, 8.0)


func _bring_player_home() -> void:
	var player := GameState.player
	if not is_instance_valid(player):
		return
	var spot: Marker3D = home_point
	if spot == null and workshop:
		spot = get_parent().get_node_or_null("SpawnPoint") as Marker3D
	if spot:
		player.global_position = spot.global_position + Vector3.UP * 0.1
		player.pivot.global_rotation.y = spot.global_rotation.y
		player.controller.camera_azimuth = spot.global_rotation.y
	player.linear_velocity = Vector3.ZERO
	player.angular_velocity = Vector3.ZERO


# --- Carrying Kite -----------------------------------------------------------------------------

func _on_picked_up(object: RigidBody3D) -> void:
	var robot := object as Robot
	if robot == null:
		return
	_held_robot = robot
	_tray_of(robot, true)


func _on_dropped(_object: RigidBody3D) -> void:
	if is_instance_valid(_held_robot):
		_tray_of(_held_robot, false)
	_held_robot = null


## Locks Kite's tray parts to it while a human carries it home, lets them ride loose again on the drop.
## The locked parts are frozen bodies that move with Kite: like Kite itself (ObjectHolder's exception)
## they mustn't shove the carrier, so each gets an exception with the player while they ride.
func _tray_of(robot: Robot, secured: bool) -> void:
	var tray := robot.get_node_or_null("StorageBox") as StorageTray
	if tray == null:
		return
	var player := GameState.player
	if secured:
		tray.set_secured(true)
		for child in tray.get_children():
			if child is HotswapPart and is_instance_valid(player):
				(child as HotswapPart).add_collision_exception_with(player)
				_ridden.append(child)
		return
	for part: HotswapPart in _ridden:
		if is_instance_valid(part) and is_instance_valid(player):
			part.remove_collision_exception_with(player)
	_ridden.clear()
	tray.set_secured(false)
