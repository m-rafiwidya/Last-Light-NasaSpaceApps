class_name CargoPlan

extends RefCounted

## The M2 cargo order: services, manifest, checks and delivery (res/story/cargo.json). A delivery
## is recorded in CampaignState as items cargo.<item_id> and cargo.service.<service_id> plus the
## flag cargo_delivered, so it is saved with the campaign.

const PATH: String = "res://res/story/cargo.json"
const DELIVERED_FLAG: String = "cargo_delivered"
const ITEM_PREFIX: String = "cargo."
const SERVICE_PREFIX: String = "cargo.service."
const CRATE_GROUP: StringName = &"cargo_crate"

static var _data: Dictionary = {}
static var _masses: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if parsed is Dictionary else {"services": [], "items": [], "lunar_day": {}}
	return _data


static func objective() -> String:
	return str(data().get("objective", "m2.cargo_ordered"))


static func services() -> Array:
	return data()["services"]


static func items() -> Array:
	return data()["items"]


static func service(id: String) -> Dictionary:
	for entry in services():
		if entry["id"] == id:
			return entry
	return {}


static func item(id: String) -> Dictionary:
	for entry in items():
		if entry["id"] == id:
			return entry
	return {}


static func required_items() -> PackedStringArray:
	var ids: PackedStringArray = []
	for entry in items():
		if entry.get("required", false):
			ids.append(entry["id"])
	return ids


static func packaging_kg() -> float:
	return float(data().get("packaging_kg", 0.0))


static func descent_delta_v() -> float:
	return float(data().get("descent_delta_v_mps", 0.0))


static func item_mass(id: String) -> float:
	if _masses.has(id):
		return _masses[id]
	var total: float = 0.0
	for part in item(id).get("parts", []):
		var node: Node = load(part["scene"]).instantiate()
		total += float(node.get("mass")) * int(part.get("count", 1))
		node.free()
	_masses[id] = total
	return total


static func order_mass(ids: Array) -> float:
	var total: float = packaging_kg()
	for id in ids:
		total += item_mass(id)
	return total


## Local lunar day (days since sunrise) M3 falls on with this service
static func m3_day(service_id: String) -> float:
	var lunar: Dictionary = data()["lunar_day"]
	return float(lunar.get("order_day", 0.0)) + float(service(service_id).get("arrival_day", 0.0)) \
		+ float(lunar.get("m3_after_delivery_days", 0.0))


static func is_late(service_id: String) -> bool:
	var lunar: Dictionary = data()["lunar_day"]
	return m3_day(service_id) >= float(lunar.get("daylight_days", 14.77)) - float(lunar.get("nightfall_margin_days", 0.0))


## Sun elevation in degrees on a local day: a uniform arc over the daylight half (game assumption)
static func sun_elevation(day: float) -> float:
	var daylight: float = float(data()["lunar_day"].get("daylight_days", 14.77))
	var arc: float = clampf(day / daylight, 0.0, 1.0) * 180.0
	return minf(arc, 180.0 - arc)


static func days_to_sunset(day: float) -> float:
	return float(data()["lunar_day"].get("daylight_days", 14.77)) - day


## Why an order can't be confirmed, or "" when it can
static func validate(service_id: String, ids: Array) -> String:
	var entry := service(service_id)
	if entry.is_empty():
		return "Choose a delivery service."
	for id in required_items():
		if not ids.has(id):
			return "%s is required." % item(id)["name"]
	var mass := order_mass(ids)
	if mass > float(entry["limit_kg"]) + 0.0001:
		return "Over the %s's limit: %.1f / %.1f kg." % [entry["name"], mass, float(entry["limit_kg"])]
	if is_late(service_id):
		for id in data()["lunar_day"].get("night_required", []):
			if not ids.has(id):
				return "Arrives near nightfall: M3's routes are cold, so the %s is required." % item(id)["name"]
	return ""


static func is_delivered() -> bool:
	return CampaignState.has_flag(DELIVERED_FLAG)


static func is_ordered(id: String) -> bool:
	return CampaignState.has_item(ITEM_PREFIX + id)


static func delivered_service() -> String:
	for entry in services():
		if CampaignState.has_item(SERVICE_PREFIX + entry["id"]):
			return entry["id"]
	return ""


static func delivered_items() -> PackedStringArray:
	var ids: PackedStringArray = []
	for entry in items():
		if is_ordered(entry["id"]):
			ids.append(entry["id"])
	return ids


static func m3_near_nightfall() -> bool:
	var id := delivered_service()
	return not id.is_empty() and is_late(id)


## Records a valid order as delivered and completes the objective. Returns false, changing
## nothing, when the order is invalid, already delivered or not the current objective.
static func deliver(service_id: String, ids: Array) -> bool:
	if is_delivered() or not validate(service_id, ids).is_empty() or CampaignState.current_objective() != objective():
		return false
	for id in ids:
		CampaignState.add_item(ITEM_PREFIX + id)
	CampaignState.add_item(SERVICE_PREFIX + service_id)
	CampaignState.set_flag(DELIVERED_FLAG)
	CampaignState.complete_objective(objective())
	return true


## Part scenes for Rafi's cargo crate: one path per part of every delivered crate item
static func crate_parts() -> PackedStringArray:
	var paths: PackedStringArray = []
	for entry in items():
		if entry.get("crate", false) and is_ordered(entry["id"]):
			for part in entry["parts"]:
				for i in int(part.get("count", 1)):
					paths.append(part["scene"])
	return paths


## Workshop slots (in `stock`: "rack" or "bench") still waiting for their delivery; none without a campaign
static func hidden_slots(stock: String, has_crate: bool) -> Array:
	var hidden: Array = []
	if CampaignState.current_mission().is_empty():
		return hidden
	for entry in items():
		var fallback: Array = entry.get("fallback_stock", {}).get(stock, [])
		if not is_ordered(entry["id"]):
			hidden.append_array(entry.get("stock", {}).get(stock, []) + fallback)
		elif has_crate:
			hidden.append_array(fallback)
	return hidden
