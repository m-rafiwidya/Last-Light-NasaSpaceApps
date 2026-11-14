class_name PartCatalog

extends RefCounted

## Every rover part's player-facing name, one-line description and where it mounts, in one
## place. A HotswapPart picks its entry with `catalog_id` (empty = the default for its part
## type). To add a part: add an entry here (and a default for a new part type), then set the
## part scene's `catalog_id`.

const ENTRIES: Dictionary = {
	"wheel": {
		"name": "Wheel",
		"description": "Standard wheel. All six are driven by the motor.",
		"mounts": "Mounts on any of the six wheel positions",
	},
	"wheel_high_grip": {
		"name": "High-grip wheel",
		"description": "Grippier tread: more traction on slopes and loose ground.",
		"mounts": "Mounts on any of the six wheel positions",
	},
	"motor": {
		"name": "Motor",
		"description": "Drives the wheels. Sets the rover's pull and top speed.",
		"mounts": "Mounts in the hatch on the front of the rover",
	},
	"battery": {
		"name": "Battery",
		"description": "Powers the rover. Required to drive.",
		"mounts": "Mounts on the rear of the rover",
	},
	"mast_head": {
		"name": "Mast camera",
		"description": "The rover's eyes: drive by it, look around and scan things.",
		"mounts": "Mounts on top of the mast",
	},
	"arm_tool": {
		"name": "Arm tool turret",
		"description": "Drill, scoop, brush, camera and sensor for the robotic arm.",
		"mounts": "Mounts on the end of the robotic arm",
	},
	"antenna": {
		"name": "High-gain antenna",
		"description": "Tracks Earth to keep the rover in contact.",
		"mounts": "Mounts on the rear-left of the deck",
	},
	"cartridge": {
		"name": "Diagnostic cartridge",
		"description": "Kite's fault-log reader. The rover's arm delivers it to Kite's service port.",
		"mounts": "Rides on the rover's cargo mount, on the deck",
	},
}

## Default catalog entry per HotswapPart.PartType (by value: WHEEL, MOTOR, BATTERY, MAST_HEAD,
## ARM_TOOL, ANTENNA, CARGO)
const TYPE_DEFAULTS: Array[String] = ["wheel", "motor", "battery", "mast_head", "arm_tool", "antenna", "cartridge"]

const UNKNOWN: Dictionary = {"name": "Part", "description": "", "mounts": ""}


static func entry(id: String) -> Dictionary:
	return ENTRIES.get(id, UNKNOWN)


static func default_id(part_type: int) -> String:
	return TYPE_DEFAULTS[part_type] if part_type >= 0 and part_type < TYPE_DEFAULTS.size() else ""


## Name of what a part type is, for empty sockets ("Mast camera goes here")
static func type_name(part_type: int) -> String:
	return entry(default_id(part_type))["name"]
