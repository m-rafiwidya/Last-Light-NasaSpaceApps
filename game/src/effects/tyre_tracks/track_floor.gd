class_name TrackFloor

extends CSGBox3D

## The test level's floor: tyre tracks show on it (track_floor.gdshader, its material_override).
## TyreTracks finds it in the group `tyre_tracks_surface` and asks for the area its tracks cover and
## the materials that draw them.


func _ready() -> void:
	add_to_group(&"tyre_tracks_surface")


## The floor's top, x and z (world)
func tyre_tracks_area() -> Rect2:
	var top: Vector3 = global_position - Vector3(size.x, 0.0, size.z) * 0.5
	return Rect2(top.x, top.z, size.x, size.z)


func tyre_tracks_materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	if material_override is ShaderMaterial:
		out.append(material_override)
	return out
