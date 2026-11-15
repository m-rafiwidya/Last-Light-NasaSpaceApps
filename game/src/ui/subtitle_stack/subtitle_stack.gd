class_name SubtitleStack

extends PanelContainer
## Every DialogServer line as a stacked DialogBox; each subtitle screen has one and follows every line.

var dialog_box_scene: PackedScene = preload("res://src/ui/dialog_box/dialog_box.tscn")
var dialog_boxes: Dictionary = {}

@onready var boxes: VBoxContainer = $Boxes


func _ready() -> void:
	DialogServer.dialog_played.connect(_on_dialog_played)
	DialogServer.dialog_ended.connect(_on_dialog_ended)
	GeneralSettings.section.changed.connect(func(_key: String) -> void: _apply_subtitles())
	_apply_subtitles()


func _apply_subtitles() -> void:
	visible = GeneralSettings.subtitles()


func _on_dialog_played(dialog: Dialog) -> void:
	var dialog_box: Control = dialog_box_scene.instantiate()
	dialog_box.set_line(dialog.speaker, dialog.subtitle)
	boxes.add_child(dialog_box)
	_ignore_mouse(dialog_box)
	dialog_box.fade_in()
	dialog_boxes[dialog.get_instance_id()] = dialog_box


func _on_dialog_ended(dialog: Dialog) -> void:
	var dialog_box: Variant = dialog_boxes.get(dialog.get_instance_id())
	dialog_boxes.erase(dialog.get_instance_id())
	if is_instance_valid(dialog_box):
		dialog_box.fade_out()


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)
