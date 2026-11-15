class_name HotswapSocket

extends Node3D

## A slot on the robot that a HotswapPart can be plugged into. A loose part that overlaps
## `PartCapture` is mounted automatically; the player takes it out again by using
## the `InteractTrigger` (E), which puts the part in their hands. A part of the right type
## that doesn't fit (HotswapPart.get_mount_problem(), e.g. a wheel outside the kit envelope)
## is refused: the socket blinks red and a subtitle says why.
## The robot keeps references to its sockets and reads `part` to adjust its variables.

signal part_mounted(part: HotswapPart)
signal part_unmounted(part: HotswapPart)
## A part of the right type that doesn't fit was refused (the socket blinks red)
signal part_refused(part: HotswapPart)

@export var socket_name: String = "Socket"
## When false only parts of `accepted_type` are mounted
@export var accepts_any_type: bool = true
@export var accepted_type: HotswapPart.PartType = HotswapPart.PartType.WHEEL
## When set, only the part with this catalog entry is mounted (one part type, several spots: the
## thermal cover's socket takes the cover, not the heater)
@export var accepted_catalog_id: String = ""
## Where a mounted part's origin goes, relative to the socket. Kit parts have their origin
## at their connector, so their sockets use zero (ROVER_KIT.md 4).
@export var mount_offset: Vector3 = Vector3(0.0, 0.1, 0.0)
## Size and centre (socket space) of the PartCapture box where a dropped part is mounted.
## Kit sockets sit close together, so each one gets a box that fits its spot.
@export var capture_size: Vector3 = Vector3(0.5, 0.6, 0.5)
@export var capture_offset: Vector3 = Vector3(0.0, 0.35, 0.0)
## Size and centre (socket space) of the InteractTrigger box the player uses (E) to take
## the mounted part out
@export var trigger_size: Vector3 = Vector3(0.5, 0.8, 0.4)
@export var trigger_offset: Vector3 = Vector3(0.0, 0.4, 0.0)
## Name of a socket_* node on the rover (e.g. "socket_wheel_front_L" on the chassis model,
## "socket_mast_head" on the mast). The robot moves this socket onto it, with zero rotation,
## when it is ready. Empty = stays put.
@export var anchor: StringName = &""
## Parent the socket to its anchor so it follows a moving part (e.g. the arm tool socket on
## the wrist); otherwise it is only placed there once.
@export var follow_anchor: bool = false

## The mounted part, null while the socket is empty
var part: HotswapPart = null

var _world: Node = null
# Parts refused while they overlap PartCapture, so each entry is reported once
var _refused: Dictionary = {}
var _blink_tween: Tween = null
var _base_material: Material = null
# Shared by every socket: one subtitle at a time when a part overlaps several sockets.
# Physics frame of the last refusal subtitle (game time, so it follows pauses and time scale).
static var _last_refusal_message_frame: int = -100000

const REFUSAL_MESSAGE_INTERVAL: float = 1.0
const REFUSAL_BLINKS: int = 3
const REFUSAL_BLINK_TIME: float = 0.15

@onready var _capture: Area3D = $PartCapture
@onready var _trigger: InteractTrigger = $InteractTrigger
@onready var _trigger_shape: CollisionShape3D = $InteractTrigger/CollisionShape3D
@onready var _mount_point: Marker3D = $MountPoint
@onready var _base: MeshInstance3D = $Base


func _ready() -> void:
	_mount_point.position = mount_offset
	_set_box($PartCapture/CollisionShape3D, capture_size, capture_offset)
	_set_box(_trigger_shape, trigger_size, trigger_offset)
	_base_material = _base.material_override
	_capture.body_exited.connect(func(body: Node3D) -> void: _refused.erase(body))
	_trigger.interacted.connect(_on_interact_trigger_interacted)
	# The trigger stays on while the socket is empty too, so the crosshair can find the socket
	# (the tooltip says what goes there); using it then does nothing
	_set_trigger_enabled(true)


# The shapes are shared by every socket instance, so each socket gets its own copy
func _set_box(shape_node: CollisionShape3D, size: Vector3, offset: Vector3) -> void:
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	shape_node.position = offset


## The area the player aims at to take the part out (and the crosshair finds the socket by)
func get_trigger() -> InteractTrigger:
	return _trigger


## What goes in this socket, for the tooltip of an empty socket
func get_accepted_name() -> String:
	if accepts_any_type:
		return "Any part"
	return PartCatalog.entry(accepted_catalog_id)["name"] if accepted_catalog_id else PartCatalog.type_name(accepted_type)


func is_occupied() -> bool:
	return part != null


func can_accept(candidate: HotswapPart) -> bool:
	if part or candidate.is_mounted() or not accepts_type(candidate):
		return false
	return candidate.get_mount_problem().is_empty()


func accepts_type(candidate: HotswapPart) -> bool:
	return accepts_any_type or (candidate.part_type == accepted_type
		and (accepted_catalog_id.is_empty() or candidate.get_catalog_id() == accepted_catalog_id))


func mount(new_part: HotswapPart) -> void:
	if not can_accept(new_part):
		return
	part = new_part
	_world = new_part.get_parent()
	new_part.attach_to(self)
	new_part.reparent(_mount_point, false)
	new_part.transform = Transform3D(Basis.IDENTITY, new_part.mount_offset)
	_trigger.tooltip = 'Press "E" to take out ' + new_part.get_display_name()
	part_mounted.emit(new_part)


## Moves the mounted part back into the world and returns it (null if the socket was empty).
func unmount() -> HotswapPart:
	if not part:
		return null
	var old_part := part
	part = null
	# current_scene is Main, not the level, so fall back to the loaded level instead
	var new_parent: Node = _world if is_instance_valid(_world) else SceneLoader.current_scene
	old_part.reparent(new_parent, true)
	old_part.detach()
	_trigger.tooltip = ""
	part_unmounted.emit(old_part)
	return old_part


func _physics_process(_delta: float) -> void:
	if part:
		return
	for body in _capture.get_overlapping_bodies():
		var candidate := body as HotswapPart
		if candidate == null or candidate.is_mounted() or not accepts_type(candidate):
			continue
		var problem: String = candidate.get_mount_problem()
		if problem.is_empty():
			mount(candidate)
			return
		if not _refused.has(candidate):
			_refused[candidate] = true
			_show_refusal(candidate, problem)


# Blinks the socket's base plate red and shows the reason as a subtitle (at most one
# subtitle per REFUSAL_MESSAGE_INTERVAL seconds across all sockets).
func _show_refusal(candidate: HotswapPart, problem: String) -> void:
	part_refused.emit(candidate)
	Debug.add_log("%s refused %s: %s" % [socket_name, candidate.get_display_name(), problem])
	var now: int = Engine.get_physics_frames()
	var interval_frames: int = roundi(REFUSAL_MESSAGE_INTERVAL * Engine.physics_ticks_per_second)
	if now - _last_refusal_message_frame >= interval_frames:
		_last_refusal_message_frame = now
		var dialog := Dialog.new()
		dialog.speaker = "Kite"
		dialog.subtitle = "Can't mount this %s: %s" % [candidate.get_display_name().to_lower(), problem]
		dialog.min_duration = 3.0
		dialog.repeat_id = "kite_refused:" + dialog.subtitle
		DialogServer.play_dialog(dialog)

	if _blink_tween:
		_blink_tween.kill()
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(1.0, 0.2, 0.15)
	red.emission_enabled = true
	red.emission = Color(1.0, 0.1, 0.05)
	_base.material_override = red
	_blink_tween = create_tween()
	for i in REFUSAL_BLINKS:
		_blink_tween.tween_callback(_base.show)
		_blink_tween.tween_interval(REFUSAL_BLINK_TIME)
		_blink_tween.tween_callback(_base.hide)
		_blink_tween.tween_interval(REFUSAL_BLINK_TIME)
	_blink_tween.tween_callback(func() -> void: _base.material_override = _base_material)


func _set_trigger_enabled(enabled: bool) -> void:
	_trigger_shape.set_deferred("disabled", not enabled)


func _on_interact_trigger_interacted(player: Player) -> void:
	var taken := unmount()
	if taken:
		player.holder.pickup(taken)
