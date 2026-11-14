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
		"description": "Powers the rover. Required to drive. 100 Wh at 5 kg.",
		"mounts": "Mounts on the rear of the rover",
	},
	"battery_light": {
		"name": "Light battery",
		"description": "Smaller, lighter pack: 60 Wh at 3 kg, so less range but less to haul.",
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
		"description": "IRIS's fault-log reader. Kite's arm delivers it to IRIS's service port.",
		"mounts": "Rides on the rover's cargo mount, on the deck",
	},
	"radio_module": {
		"name": "Radio-power module",
		"description": "Replacement for IRIS's lost radio-power unit. Heavy: 12 kg. Kite's arm seats it in IRIS's module socket.",
		"mounts": "Rides on the rover's cargo mount, in its cradle",
	},
	"sample_scoop": {
		"name": "Sampling scoop",
		"description": "Takes a spoonful of regolith from a marked site. 0.4 kg. Held by the arm tool.",
		"mounts": "Carried by the arm tool; stored on the sample bench",
	},
	"sample_container": {
		"name": "Sample container S-1",
		"description": "Sealed jar with a fill gauge, for the near site by IRIS. 0.5 kg empty.",
		"mounts": "Rides on the rover's cargo mount; stored on the sample bench",
	},
	"sample_container_far": {
		"name": "Sample container S-2",
		"description": "Sealed jar with a fill gauge, for the far site on the rim. 0.5 kg empty.",
		"mounts": "Rides on the rover's cargo mount; stored on the sample bench",
	},
	"arm_tool_thermal": {
		"name": "Thermal sensor turret",
		"description": "Arm tool turret with an infrared radiometer: reads the ground's surface temperature under it. 5.3 kg, 1 W while reading.",
		"mounts": "Mounts on the end of the robotic arm",
	},
	"field_logger": {
		"name": "Far logger",
		"description": "Evan's comparison logger from the far rim, with its stored measurement series. 1.6 kg. Labelled twice.",
		"mounts": "Rides on the rover's cargo mount, in its cradle",
	},
	"thermal_cover": {
		"name": "Thermal cover",
		"description": "Insulating blanket for the electronics bay: slows heat loss in shade. 0.9 kg, no power.",
		"mounts": "Mounts on the deck's right rear, beside the antenna; stored on the sample bench",
	},
	"thermal_heater": {
		"name": "Heater",
		"description": "Keeps the electronics bay warm under the thermal cover. 0.6 kg, 12 W while on.",
		"mounts": "Mounts on the deck in front of the thermal cover; stored on the sample bench",
	},
}

## Default catalog entry per HotswapPart.PartType (by value: WHEEL, MOTOR, BATTERY, MAST_HEAD,
## ARM_TOOL, ANTENNA, CARGO, THERMAL)
const TYPE_DEFAULTS: Array[String] = ["wheel", "motor", "battery", "mast_head", "arm_tool", "antenna", "cartridge", "thermal_cover"]

const UNKNOWN: Dictionary = {"name": "Part", "description": "", "mounts": ""}


static func entry(id: String) -> Dictionary:
	return ENTRIES.get(id, UNKNOWN)


static func default_id(part_type: int) -> String:
	return TYPE_DEFAULTS[part_type] if part_type >= 0 and part_type < TYPE_DEFAULTS.size() else ""


## Name of what a part type is, for empty sockets ("Mast camera goes here")
static func type_name(part_type: int) -> String:
	return entry(default_id(part_type))["name"]
