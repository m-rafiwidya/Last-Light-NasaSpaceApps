class_name KiteSave

extends RefCounted

## Kite in a save: the part in each socket (by socket node name) and the battery's charge.
## Read through the sockets' `part` and restored with HotswapSocket.unmount() / mount().


static func capture(rover: Robot) -> Dictionary:
	var sockets: Dictionary = {}
	for socket: HotswapSocket in rover.find_children("*", "HotswapSocket", true, false):
		var part: HotswapPart = socket.part
		if part == null or part.scene_file_path.is_empty():
			sockets[socket.name] = null
			continue
		var properties: Dictionary = {}
		for property in PartsStock.PROPERTIES:
			if property in part:
				var value: Variant = part.get(property)
				properties[property] = [value.r, value.g, value.b, value.a] if value is Color else value
		var entry: Dictionary = {"scene": part.scene_file_path, "properties": properties}
		if part is BatteryPart:
			entry["charge"] = (part as BatteryPart).charge
		sockets[socket.name] = entry
	return {"sockets": sockets}


## Puts the saved parts in `rover`'s sockets; sockets the save doesn't name keep their part
static func apply(rover: Robot, data: Dictionary) -> void:
	var sockets: Variant = data.get("sockets")
	if not sockets is Dictionary:
		return
	for socket: HotswapSocket in rover.find_children("*", "HotswapSocket", true, false):
		if not sockets.has(socket.name):
			continue
		var entry: Variant = sockets[socket.name]
		var part: HotswapPart = _make_part(entry) if entry is Dictionary else null
		if entry != null and part == null:
			continue
		if socket.part:
			_discard(rover, socket.unmount())
		if part == null:
			continue
		rover.get_parent().add_child(part)
		part.global_position = socket.global_position
		socket.mount(part)
		if not part.is_mounted():
			part.queue_free()
		elif part is BatteryPart and (entry.get("charge") is float or entry.get("charge") is int):
			(part as BatteryPart).charge = clampf(entry["charge"], 0.0, (part as BatteryPart).capacity)


## Out of the level now, freed a moment later: RoverVisuals still holds an unmounted wheel for a frame
static func _discard(rover: Robot, part: HotswapPart) -> void:
	part.get_parent().remove_child(part)
	rover.get_tree().create_timer(1.0).timeout.connect(part.free)


static func _make_part(entry: Dictionary) -> HotswapPart:
	var path: Variant = entry.get("scene")
	if not (path is String and path.begins_with("res://") and ResourceLoader.exists(path)):
		return null
	var scene := load(path) as PackedScene
	var part := scene.instantiate() as HotswapPart if scene else null
	if part == null:
		return null
	var properties: Variant = entry.get("properties")
	if properties is Dictionary:
		for property in PartsStock.PROPERTIES:
			if not (properties.has(property) and property in part):
				continue
			var value: Variant = properties[property]
			if part.get(property) is Color:
				if value is Array and value.size() == 4:
					part.set(property, Color(value[0], value[1], value[2], value[3]))
			elif part.get(property) is float and (value is float or value is int):
				part.set(property, float(value))
			elif part.get(property) is String and value is String:
				part.set(property, value)
	return part
