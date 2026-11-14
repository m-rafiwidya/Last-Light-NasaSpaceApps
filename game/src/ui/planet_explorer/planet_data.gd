class_name PlanetData

## The planet explorer's planets and sites, from the board's planets() (docs/ui/boards/Main.dc.html),
## and which planets are unlocked.
## Per planet: id, title, tab label, the theme colour of its tab underline (UIColor), its colour
## map, the atmosphere glow (none for the Moon), the view it opens on (lat, lon of the point facing
## the camera, radians), the hint shown while it is locked, and its sites. Per site: lat / lon in
## degrees (east positive), the tooltip's rows ([key, value]) and note, and an optional badge.

## Set by the `unlockall` console command (testing): every planet is unlocked
static var unlock_all: bool = false

const PLANETS: Array[Dictionary] = [
	{ "id": &"moon", "title": "THE MOON", "tab": "MOON", "color": &"moon",
		"map": "res://res/textures/moon/lroc_color_4k.jpg", "atmosphere": Color(0, 0, 0, 0),
		"view": Vector2(0.05, -0.2), "lock_hint": "", "sites": [
		{ "id": &"a11", "name": "APOLLO 11", "lat": 0.674, "lon": 23.473,
			"rows": [["LANDED", "20 Jul 1969"], ["CREW", "Neil Armstrong, Buzz Aldrin"], ["REGION", "Mare Tranquillitatis"]],
			"note": "The first crewed landing on the Moon." },
		{ "id": &"a12", "name": "APOLLO 12", "lat": -3.012, "lon": -23.422, "badge": "WHERE LAST LIGHT TAKES PLACE",
			"rows": [["LANDED", "19 Nov 1969"], ["CREW", "Pete Conrad, Alan Bean"], ["REGION", "Oceanus Procellarum"]],
			"note": "A pinpoint landing right next to Surveyor 3, a robotic lander from April 1967. The crew walked over to it and brought parts of it back to Earth." },
		{ "id": &"a14", "name": "APOLLO 14", "lat": -3.646, "lon": -17.471,
			"rows": [["LANDED", "5 Feb 1971"], ["CREW", "Alan Shepard, Edgar Mitchell"], ["REGION", "Fra Mauro"]],
			"note": "Explored the Fra Mauro highlands. Shepard famously hit two golf balls on the surface." },
		{ "id": &"a15", "name": "APOLLO 15", "lat": 26.132, "lon": 3.634,
			"rows": [["LANDED", "30 Jul 1971"], ["CREW", "David Scott, James Irwin"], ["REGION", "Hadley–Apennine"]],
			"note": "The first mission to drive the Lunar Roving Vehicle." },
		{ "id": &"a16", "name": "APOLLO 16", "lat": -8.973, "lon": 15.5,
			"rows": [["LANDED", "21 Apr 1972"], ["CREW", "John Young, Charles Duke"], ["REGION", "Descartes Highlands"]],
			"note": "The only Apollo landing in the central lunar highlands." },
		{ "id": &"a17", "name": "APOLLO 17", "lat": 20.191, "lon": 30.772,
			"rows": [["LANDED", "11 Dec 1972"], ["CREW", "Gene Cernan, Harrison Schmitt"], ["REGION", "Taurus–Littrow"]],
			"note": "The last crewed landing so far. Schmitt was the first geologist to walk on the Moon." },
	] },
	{ "id": &"mars", "title": "MARS", "tab": "MARS", "color": &"mars",
		"map": "res://res/textures/planets/mars_viking_color_4k.jpg", "atmosphere": Color(0.902, 0.588, 0.431, 0.25),
		"view": Vector2(0.2, 1.2), "lock_hint": "COMPLETE THE MOON MISSIONS", "sites": [
		{ "id": &"v1", "name": "VIKING 1", "lat": 22.27, "lon": -47.95,
			"rows": [["LANDED", "20 Jul 1976"], ["AGENCY", "NASA"], ["REGION", "Chryse Planitia"]],
			"note": "NASA’s first Mars landing. It sent back the first clear pictures from the surface." },
		{ "id": &"v2", "name": "VIKING 2", "lat": 47.64, "lon": -134.29,
			"rows": [["LANDED", "3 Sep 1976"], ["AGENCY", "NASA"], ["REGION", "Utopia Planitia"]],
			"note": "Photographed frost on the ground during the Martian winter." },
		{ "id": &"pf", "name": "PATHFINDER", "lat": 19.33, "lon": -33.55,
			"rows": [["LANDED", "4 Jul 1997"], ["AGENCY", "NASA"], ["REGION", "Ares Vallis"]],
			"note": "Carried Sojourner, the first rover to drive on Mars." },
		{ "id": &"sp", "name": "SPIRIT", "lat": -14.57, "lon": 175.47,
			"rows": [["LANDED", "4 Jan 2004"], ["AGENCY", "NASA"], ["REGION", "Gusev crater"]],
			"note": "Planned for 90 days, it kept working for six years." },
		{ "id": &"op", "name": "OPPORTUNITY", "lat": -1.95, "lon": -5.53,
			"rows": [["LANDED", "25 Jan 2004"], ["AGENCY", "NASA"], ["REGION", "Meridiani Planum"]],
			"note": "Drove over 45 km, a record for driving on another world." },
		{ "id": &"cu", "name": "CURIOSITY", "lat": -4.59, "lon": 137.44, "badge": "THE ROVER THAT INSPIRED OURS",
			"rows": [["LANDED", "6 Aug 2012"], ["AGENCY", "NASA"], ["REGION", "Gale crater"]],
			"note": "Still climbing Mount Sharp. Our rover’s design is based on it." },
		{ "id": &"pe", "name": "PERSEVERANCE", "lat": 18.44, "lon": 77.45,
			"rows": [["LANDED", "18 Feb 2021"], ["AGENCY", "NASA"], ["REGION", "Jezero crater"]],
			"note": "Collects rock samples for a future return to Earth, and brought the Ingenuity helicopter." },
		{ "id": &"zh", "name": "ZHURONG", "lat": 25.07, "lon": 109.93,
			"rows": [["LANDED", "15 May 2021"], ["AGENCY", "CNSA"], ["REGION", "Utopia Planitia"]],
			"note": "China’s first Mars rover." },
	] },
	{ "id": &"earth", "title": "EARTH", "tab": "EARTH", "color": &"earth",
		"map": "res://res/textures/planets/earth_blue_marble_4k.jpg", "atmosphere": Color(0.431, 0.667, 1.0, 0.35),
		"view": Vector2(-0.22, 2.0), "lock_hint": "FINISH THE GAME",
		"subtitle": "TANDBORSTE · NASA SPACE APPS CHALLENGE 2026", "sites": [
		{ "id": &"fahd", "name": "FAHD MUHAMMAD ZAHID", "lat": -6.891, "lon": 107.61,
			"rows": [["STUDIES", "Informatics"], ["AT", "Institut Teknologi Bandung"], ["CITY", "Bandung, Indonesia"], ["FROM", "Indonesia"]] },
		{ "id": &"rafi", "name": "MUHAMMAD RAFI WIDYATAMA", "lat": 3.121, "lon": 101.654,
			"rows": [["STUDIES", "Mechanical Engineering"], ["AT", "Universiti Malaya"], ["CITY", "Kuala Lumpur, Malaysia"], ["FROM", "Indonesia"]] },
		{ "id": &"satinize", "name": "RAYHAN SATRIO ADI NURDJAMAN", "lat": 1.297, "lon": 103.776,
			"rows": [["STUDIES", "Mechanical Engineering"], ["AT", "National University of Singapore"], ["CITY", "Singapore"], ["FROM", "Indonesia"]] },
		{ "id": &"faiq", "name": "FAIQ HAIDAR DZIKRULLAH SATRIAWAN", "lat": -37.911, "lon": 145.134,
			"rows": [["STUDIES", "Mechanical Engineering"], ["AT", "Monash University"], ["CITY", "Melbourne, Australia"], ["FROM", "Indonesia"]] },
	] },
]


## Whether the explorer shows `id`'s globe and sites, or a lock and its hint: the Moon always,
## Mars after the Moon chapter (m3 completed), Earth after the end of the game.
## TODO(campaign state): Earth needs a "game finished" state; until then it stays locked (or
## all, with `unlockall`).
static func is_unlocked(id: StringName) -> bool:
	var campaign: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null(^"CampaignState")
	return unlock_all or id == &"moon" or (id == &"mars" and campaign != null and campaign.is_mission_completed("m3"))


static func index_of(id: StringName) -> int:
	for i in PLANETS.size():
		if PLANETS[i].id == id:
			return i
	return -1


## The tooltip's rows for a site: its own, plus COORDS off Earth (the team's cities don't need them)
static func tooltip_rows(planet: Dictionary, site: Dictionary) -> Array:
	var rows: Array = site.rows.duplicate()
	if planet.id != &"earth":
		rows.append(["COORDS", "%.2f°%s  %.2f°%s" % [absf(site.lat), "N" if site.lat >= 0.0 else "S",
			absf(site.lon), "E" if site.lon >= 0.0 else "W"]])
	return rows


## The planet the main menu's globe shows: the one last viewed in the explorer (UiSettings), or the
## Moon if that one is locked
static func menu_planet() -> StringName:
	var id := StringName(UiSettings.last_planet())
	return id if index_of(id) >= 0 and is_unlocked(id) else &"moon"
