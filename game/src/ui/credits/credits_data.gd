class_name CreditsData

extends RefCounted

## The credits roll's text, read from res://res/credits.md (the format is described there; the
## repository's CREDITS.md points to it).
## sections() returns one Dictionary per "###" heading:
##   title    the heading, "" for the headerless CLOSING NOTE
##   entries  Array of {"name", "sub"} (a "NAME | small line" row), {"text"} (a block, \n kept) or
##            {"fine"} (a block of fine print, wrapped and left-aligned: the engine licence)
## The last section is not in the file: engine_section() builds it from the running engine.

const SOURCE: String = "res://res/credits.md"
const ENGINE_TITLE: String = "GODOT ENGINE LICENCE"
const CLOSING_NOTE: String = "CLOSING NOTE"
const ROW_SEPARATOR: String = " | "


static func sections() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var file := FileAccess.open(SOURCE, FileAccess.READ)
	if file == null:
		push_warning("Credits: %s not found, the roll shows only its fixed parts" % SOURCE)
	else:
		result = parse(file.get_as_text())
	result.append(engine_section())
	return result


## Godot's own licence (Engine.get_license_text(), paragraphs unwrapped) and, one line per component,
## the copyright holders and licence of every third-party component built into the engine
## (Engine.get_copyright_info()). Godot's licence asks for these notices in every game made with it.
static func engine_section() -> Dictionary:
	var entries: Array = [{"fine": "Made with Godot Engine, godotengine.org"}]
	for paragraph in Engine.get_license_text().strip_edges().split("\n\n"):
		entries.append({"fine": paragraph.replace("\n", " ").strip_edges()})
	var components: PackedStringArray = third_party_lines()
	if not components.is_empty():
		entries.append({"fine": "Third-party components in Godot Engine"})
		entries.append({"fine": "\n".join(components)})
	return {"title": ENGINE_TITLE, "entries": entries}


## "Name: holder; holder (Licence)" for each component of Engine.get_copyright_info() except Godot
## itself (its licence is the text above). A component's parts are merged: holders and licences once.
static func third_party_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for component: Dictionary in Engine.get_copyright_info():
		if component["name"] == "Godot Engine":
			continue
		var holders: PackedStringArray = []
		var licences: PackedStringArray = []
		for part: Dictionary in component["parts"]:
			for holder: String in part["copyright"]:
				if not holders.has(holder):
					holders.append(holder)
			var licence: String = part["license"]
			if not licences.has(licence):
				licences.append(licence)
		lines.append("%s: %s (%s)" % [component["name"], "; ".join(holders), ", ".join(licences)])
	return lines


static func parse(markdown: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var current: Dictionary = {}
	var block: PackedStringArray = []
	for raw in markdown.split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("### "):
			_end_block(current, block)
			block = []
			var title: String = line.trim_prefix("### ")
			current = {"title": "" if title == CLOSING_NOTE else title, "entries": []}
			result.append(current)
		elif line.is_empty():
			_end_block(current, block)
			block = []
		elif not current.is_empty():
			block.append(line)
	_end_block(current, block)
	return result


static func _end_block(section: Dictionary, block: PackedStringArray) -> void:
	if block.is_empty() or section.is_empty():
		return
	var entries: Array = section["entries"]
	var all_rows: bool = Array(block).all(func(l: String) -> bool: return ROW_SEPARATOR in l)
	if all_rows:
		for line in block:
			var parts: PackedStringArray = line.split(ROW_SEPARATOR, true, 1)
			entries.append({"name": parts[0].strip_edges(), "sub": parts[1].strip_edges()})
	else:
		entries.append({"text": "\n".join(block)})
