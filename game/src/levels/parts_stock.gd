class_name PartsStock

extends RefCounted

## A recorded set of loose parts that can be laid out again: the levels' parts pile (RoverLevel)
## and the workshop's rack (Workshop). `record` notes every HotswapPart in a container as it is;
## `restock` clears the container's loose parts (parts mounted on a rover stay) and lays out a
## fresh copy of what was recorded.

## Part properties copied into a restocked part
const PROPERTIES: Array[String] = ["catalog_id", "tint", "radius", "grip"]

# One entry per part: scene, transform and properties
var _layout: Array = []


func record(container: Node) -> void:
	_layout.clear()
	for part in container.get_children():
		if not part is HotswapPart:
			continue
		var properties: Dictionary = {}
		for property in PROPERTIES:
			if property in part:
				properties[property] = part.get(property)
		_layout.append({"scene": load(part.scene_file_path), "transform": part.transform, "properties": properties})


func size() -> int:
	return _layout.size()


## Clears the loose parts in `container` (a held one is released first; mounted parts stay)
## and lays out the recorded parts again. `holders_root` is searched for the rovers that may be
## holding a part.
func restock(container: Node, holders_root: Node) -> void:
	var holders: Array = [GameState.player] + holders_root.find_children("*", "Robot", true, false)
	for part in container.get_children():
		if not part is HotswapPart or part.is_mounted():
			continue
		for holder_owner in holders:
			if is_instance_valid(holder_owner) and holder_owner.holder and holder_owner.holder.held_object == part:
				holder_owner.holder.release()
		container.remove_child(part)
		part.queue_free()
	for entry in _layout:
		var part: HotswapPart = entry["scene"].instantiate()
		part.transform = entry["transform"]
		for property in entry["properties"]:
			part.set(property, entry["properties"][property])
		container.add_child(part)
