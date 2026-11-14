class_name CreditsData

extends RefCounted

## The credits roll's text, read from res://res/credits.md (the format is described there; the
## repository's CREDITS.md points to it).
## sections() returns one Dictionary per "###" heading:
##   title    the heading, "" for the headerless CLOSING NOTE
##   entries  Array of {"name", "sub"} (a "NAME | small line" row) or {"text"} (a block, \n kept)

const SOURCE: String = "res://res/credits.md"
const CLOSING_NOTE: String = "CLOSING NOTE"
const ROW_SEPARATOR: String = " | "


static func sections() -> Array[Dictionary]:
	var file := FileAccess.open(SOURCE, FileAccess.READ)
	if file == null:
		push_warning("Credits: %s not found, the roll shows only its fixed parts" % SOURCE)
		return []
	return parse(file.get_as_text())


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
