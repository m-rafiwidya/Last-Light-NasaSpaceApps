extends Node

## The Player's own sounds (added by Sfx): footsteps, landings, and grab / drop / throw for its
## holder. Steps and landings are 2D (the player's own body) and sound like the ground under the
## feet: regolith on the Moon's terrain and rocks, the hard floor anywhere else.

## Steps: one per stride while on the floor and moving faster than STEP_MIN_SPEED (m/s). The
## stride grows from crouching to sprinting (Player.STEP_SIZE_WALK .. STEP_SIZE_SPRINT).
const STEP_MIN_SPEED: float = 0.4
const STEP_CROUCH_SIZE: float = 0.5
## Step level (dB) crouching, walking, sprinting
const STEP_DB: Vector3 = Vector3(-6.0, 0.0, 2.0)
## A landing needs this long in the air (s) and this fall speed (m/s); it plays at full level
## from LAND_FULL_SPEED
const LAND_MIN_AIR_TIME: float = 0.3
const LAND_MIN_SPEED: float = 1.0
const LAND_FULL_SPEED: float = 5.0

var player: Player
var _distance: float = 0.0
var _air_time: float = 0.0
var _fall_speed: float = 0.0
var _was_on_floor: bool = true


func _ready() -> void:
	player = get_parent() as Player
	Sfx.watch_holder(player.holder)


func _physics_process(delta: float) -> void:
	var on_floor: bool = player.is_on_floor
	var velocity: Vector3 = player.linear_velocity
	if not on_floor:
		_air_time += delta
		_fall_speed = maxf(-velocity.y, 0.0)
		_was_on_floor = false
		return
	if not _was_on_floor and _air_time >= LAND_MIN_AIR_TIME and _fall_speed >= LAND_MIN_SPEED:
		var level: float = clampf(remap(_fall_speed, LAND_MIN_SPEED, LAND_FULL_SPEED, 0.0, 1.0), 0.0, 1.0)
		Sfx.play(StringName("land_" + _surface()), null, lerpf(-8.0, 0.0, level))
		_distance = 0.0
	_was_on_floor = true
	_air_time = 0.0

	var speed: float = Vector2(velocity.x, velocity.z).length()
	var stride: float = _stride(speed)
	if speed < STEP_MIN_SPEED:
		_distance = stride * 0.6           # the first step comes soon after setting off
		return
	_distance += speed * delta
	if _distance >= stride:
		_distance -= stride
		Sfx.play(StringName("step_" + _surface()), null, _step_db(speed))


func _stride(speed: float) -> float:
	if player.is_crouching:
		return STEP_CROUCH_SIZE
	var t: float = clampf(remap(speed, Player.SPEED_WALK, Player.SPEED_SPRINT, 0.0, 1.0), 0.0, 1.0)
	return lerpf(Player.STEP_SIZE_WALK, Player.STEP_SIZE_SPRINT, t)


func _step_db(speed: float) -> float:
	if player.is_crouching:
		return STEP_DB.x
	var t: float = clampf(remap(speed, Player.SPEED_WALK, Player.SPEED_SPRINT, 0.0, 1.0), 0.0, 1.0)
	return lerpf(STEP_DB.y, STEP_DB.z, t)


# "regolith" or "floor": what is under the feet (the player's origin is at its feet)
func _surface() -> String:
	var from: Vector3 = player.global_position + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 1.5, 1)
	query.exclude = [player.get_rid()]
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	return "regolith" if hit and Sfx.is_regolith(hit["collider"]) else "floor"
