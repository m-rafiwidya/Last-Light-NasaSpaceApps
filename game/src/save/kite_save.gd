class_name KiteSave

extends RefCounted

## Kite in a save: the part in each socket (by socket node name) and the battery's charge, the loose
## parts in its tray (StorageBox) with their transform in the tray, where Kite stands and, from the
## MissionDirector, whether it is on the pad and stranded.
## Read through the sockets' `part` and restored with HotswapSocket.unmount() / mount().

const TRAY: String = "StorageBox"


static func capture(rover: Robot) -> Dictionary:
	var sockets: Dictionary = {}
	for socket: HotswapSocket in rover.find_children("*", "HotswapSocket", true, false):
		var part: HotswapPart = socket.part
		sockets[socket.name] = null if part == null or part.scene_file_path.is_empty() else _entry(part)
	var data: Dictionary = {"sockets": sockets, "pose": _floats(rover.global_transform)}
	var tray: Node3D = rover.get_node_or_null(TRAY)
	if tray:
		var items: Array = []
		for part: HotswapPart in tray.call(&"items"):
			if not part.scene_file_path.is_empty():
				var entry: Dictionary = _entry(part)
				entry["local"] = _floats(tray.global_transform.affine_inverse() * part.global_transform)
				items.append(entry)
		data["tray"] = items
	var director: Node = rover.get_tree().get_first_node_in_group(&"mission_director")
	if director and director.has_method(&"field_state"):
		data.merge(director.call(&"field_state"))
	return data


static func _entry(part: HotswapPart) -> Dictionary:
	var properties: Dictionary = {}
	for property in PartsStock.PROPERTIES:
		if property in part:
			var value: Variant = part.get(property)
			properties[property] = [value.r, value.g, value.b, value.a] if value is Color else value
	var entry: Dictionary = {"scene": part.scene_file_path, "properties": properties}
	if part is BatteryPart:
		entry["charge"] = (part as BatteryPart).charge
	return entry


## Where Kite stood when saved, or null (an older save, or Kite was on the pad: it goes on the dock)
static func field_pose(data: Dictionary) -> Variant:
	if data.get("on_pad", true) == true:
		return null
	return _transform(data.get("pose"))


## Recreates the saved tray parts on `rover`'s tray (Kite already where it belongs); returns them
static func apply_tray(rover: Robot, data: Dictionary) -> Array[HotswapPart]:
	var made: Array[HotswapPart] = []
	var tray: Node3D = rover.get_node_or_null(TRAY)
	var items: Variant = data.get("tray")
	if tray == null or not items is Array:
		return made
	for entry in items:
		var local: Variant = _transform(entry.get("local")) if entry is Dictionary else null
		var part: HotswapPart = _make_part(entry) if local != null else null
		if part == null:
			continue
		rover.get_parent().add_child(part)
		part.global_transform = tray.global_transform * (local as Transform3D)
		part.linear_velocity = Vector3.ZERO
		part.angular_velocity = Vector3.ZERO
		_set_charge(part, entry)
		made.append(part)
	return made


static func _set_charge(part: HotswapPart, entry: Dictionary) -> void:
	if part is BatteryPart and (entry.get("charge") is float or entry.get("charge") is int):
		(part as BatteryPart).charge = clampf(entry["charge"], 0.0, (part as BatteryPart).capacity)


static func _floats(t: Transform3D) -> Array:
	return [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
		t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]


static func _transform(value: Variant) -> Variant:
	if not (value is Array and value.size() == 12 and value.all(func(v) -> bool: return v is float or v is int)):
		return null
	var f: Array = value
	return Transform3D(Basis(Vector3(f[0], f[1], f[2]), Vector3(f[3], f[4], f[5]), Vector3(f[6], f[7], f[8])),
		Vector3(f[9], f[10], f[11]))


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
		else:
			_set_charge(part, entry)


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
