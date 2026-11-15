extends HotswapPart

## The delivery crate as cargo (plan v2 R2, for Fahd's F2): the resupply flight's crate, small
## enough to ride home on Kite's cargo mount and be unpacked in the workshop. What's inside comes
## from the order (CargoPlan), not from this part; F2 sets `mass` to suit. The claw can pick it up
## (group claw_target). Scene: src/field/cargo_crate_part.tscn (the decor crate at 0.6 scale).

const CLAW_GROUP: StringName = &"claw_target"


func _ready() -> void:
	super()
	add_to_group(CLAW_GROUP)
	# The decor model brings its own static collider; a part's body is its own box shape
	for body in find_children("*", "StaticBody3D", true, false):
		body.queue_free()
