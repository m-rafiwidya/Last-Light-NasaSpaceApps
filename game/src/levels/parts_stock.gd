class_name PartsStock

extends RefCounted

## A recorded set of loose parts that can be laid out again: the levels' parts pile (RoverLevel)
## and the workshop's rack (Workshop). `record` notes every HotswapPart in a container as it is;
## `restock` clears the container's loose parts (parts mounted on a rover stay) and lays out a
## fresh copy of what was recorded.
##
## With a pool (`set_extras`) the stock conserves parts: the pool is the recorded parts plus the
## extras (a rover's own starting parts), and the container shows the pool minus the parts
## mounted on the rover. A part on the rover takes its extra first, else its slot's part; an
## extra left over (the rover's original wheel after a swap) takes a vacated slot.

## Part properties copied into a restocked part
const PROPERTIES: Array[String] = ["catalog_id", "tint", "radius", "grip"]

# One entry per part: scene, transform and properties
var _layout: Array = []
var _extras: Array = []


func record(container: Node) -> void:
	_layout.clear()
	for part in container.get_children():
		if not part is HotswapPart:
			continue
		var properties: Dictionary = {}
		for property in PROPERTIES:
			if property in part:
				properties[property] = part.get(property)
		_layout.append({"scene": load(part.scene_file_path), "transform": part.transform, "properties": properties,
			"name": part.name, "key": key_of(part)})


func size() -> int:
	return _layout.size()


static func key_of(part: HotswapPart) -> String:
	return part.scene_file_path + "|" + part.get_catalog_id()


## The pool's extra parts, from parts that are in the tree now
func set_extras(parts: Array) -> void:
	_extras.clear()
	for part: HotswapPart in parts:
		var properties: Dictionary = {}
		for property in PROPERTIES:
			if property in part:
				properties[property] = part.get(property)
		_extras.append({"scene": load(part.scene_file_path), "properties": properties, "key": key_of(part)})


## What the container shows with `mounted` on the rover: the recorded entries, minus those
## taken, plus extras in the vacated slots
func plan(mounted: Array) -> Array:
	var left: Array = _layout.duplicate()
	var extras: Array = _extras.duplicate()
	var vacated: Array = []
	for part: HotswapPart in mounted:
		var key: String = key_of(part)
		var i: int = _find(extras, key)
		if i >= 0:
			extras.remove_at(i)
			continue
		i = _find(left, key)
		if i >= 0:
			vacated.append(left[i])
			left.remove_at(i)
	for extra in extras:
		if vacated.is_empty():
			break
		var j: int = maxi(_find(vacated, extra["key"]), 0)
		var slot: Dictionary = vacated[j]
		vacated.remove_at(j)
		left.append({"scene": extra["scene"], "transform": slot["transform"], "properties": extra["properties"],
			"name": slot["name"], "key": extra["key"]})
	return left


## Whether laying out the pool with `mounted` differs from the recorded layout
func differs(mounted: Array) -> bool:
	return plan(mounted).size() != _layout.size() or plan(mounted).any(func(entry: Dictionary) -> bool:
		return not _layout.has(entry))


func _find(entries: Array, key: String) -> int:
	for i in entries.size():
		if entries[i]["key"] == key:
			return i
	return -1


## Clears the loose parts in `container` (a held one is released first; mounted parts stay)
## and lays out the recorded parts again. `holders_root` is searched for the rovers that may be
## holding a part.
func restock(container: Node, holders_root: Node, mounted: Variant = null) -> void:
	var holders: Array = [GameState.player] + holders_root.find_children("*", "Robot", true, false)
	for part in container.get_children():
		if not part is HotswapPart or part.is_mounted():
			continue
		for holder_owner in holders:
			if is_instance_valid(holder_owner) and holder_owner.holder and holder_owner.holder.held_object == part:
				holder_owner.holder.release()
		container.remove_child(part)
		part.queue_free()
	for entry in (_layout if mounted == null else plan(mounted)):
		var part: HotswapPart = entry["scene"].instantiate()
		part.name = entry["name"]
		part.transform = entry["transform"]
		for property in entry["properties"]:
			part.set(property, entry["properties"][property])
		container.add_child(part)
