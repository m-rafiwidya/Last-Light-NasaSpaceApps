class_name HotswapSocket

extends Node3D

## A slot on the robot that a HotswapPart can be plugged into. A loose part that overlaps
## `PartCapture` is mounted automatically; the player takes it out again by using
## the `InteractTrigger` (E), which puts the part in their hands.
## The robot keeps references to its sockets and reads `part` to adjust its variables.

signal part_mounted(part: HotswapPart)
signal part_unmounted(part: HotswapPart)

@export var socket_name: String = "Socket"
## When false only parts of `accepted_type` are mounted
@export var accepts_any_type: bool = true
@export var accepted_type: HotswapPart.PartType = HotswapPart.PartType.WHEEL

## The mounted part, null while the socket is empty
var part: HotswapPart = null

var _world: Node = null

@onready var _capture: Area3D = $PartCapture
@onready var _trigger: InteractTrigger = $InteractTrigger
@onready var _trigger_shape: CollisionShape3D = $InteractTrigger/CollisionShape3D
@onready var _mount_point: Marker3D = $MountPoint


func _ready() -> void:
	_trigger.interacted.connect(_on_interact_trigger_interacted)
	_set_trigger_enabled(false)


func is_occupied() -> bool:
	return part != null


func can_accept(candidate: HotswapPart) -> bool:
	if part or candidate.is_mounted():
		return false
	return accepts_any_type or candidate.part_type == accepted_type


func mount(new_part: HotswapPart) -> void:
	if not can_accept(new_part):
		return
	part = new_part
	_world = new_part.get_parent()
	new_part.attach_to(self)
	new_part.reparent(_mount_point, false)
	new_part.transform = Transform3D(Basis.IDENTITY, new_part.mount_offset)
	_trigger.tooltip = 'Press "E" to take out ' + new_part.get_display_name()
	_set_trigger_enabled(true)
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
	_set_trigger_enabled(false)
	part_unmounted.emit(old_part)
	return old_part


func _physics_process(_delta: float) -> void:
	if part:
		return
	for body in _capture.get_overlapping_bodies():
		if body is HotswapPart and can_accept(body):
			mount(body)
			return


func _set_trigger_enabled(enabled: bool) -> void:
	_trigger_shape.set_deferred("disabled", not enabled)


func _on_interact_trigger_interacted(player: Player) -> void:
	var taken := unmount()
	if taken:
		player.holder.pickup(taken)
