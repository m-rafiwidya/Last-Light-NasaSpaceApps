extends UIScreen

var dialog_box_scene: PackedScene = preload("res://src/ui/dialog_box/dialog_box.tscn")
var dialog_boxes: Dictionary
var fade_tween: Tween = null


func _ready() -> void:
	DialogServer.dialog_played.connect(_on_dialog_played)
	DialogServer.dialog_ended.connect(_on_dialog_ended)
	hide()


func _process(_delta: float) -> void:
	if is_instance_valid(GameState.player):
		var is_looking_at_interact_trigger: bool = GameState.player.looking_at_object is InteractTrigger or GameState.player.looking_at_object is RigidBody3D
		$MarginContainer/CenterContainer/TextureRect.visible = !GameState.player.hide_crosshair and not is_looking_at_interact_trigger
		$MarginContainer/CenterContainer/TextureRect2.visible = !GameState.player.hide_crosshair and is_looking_at_interact_trigger


func _on_dialog_played(dialog: Dialog):
	var dialog_box: Control = dialog_box_scene.instantiate()
	dialog_box.set_text(dialog.get_display_text())
	$DialogBoxContainer/Boxes.add_child(dialog_box)
	dialog_box.fade_in()
	dialog_boxes[dialog.get_instance_id()] = dialog_box


func _on_dialog_ended(dialog: Dialog):
	if not dialog_boxes.has(dialog.get_instance_id()):
		return
	var dialog_box = dialog_boxes[dialog.get_instance_id()]
	dialog_boxes.erase(dialog.get_instance_id())
	if is_instance_valid(dialog_box):
		dialog_box.fade_out()


func fade_in():
	show()
	_fade_to(1.0)


func fade_out():
	if visible:
		_fade_to(0.0).tween_callback(hide)


# Kills the previous fade so a quick fade_out -> fade_in can't hide the HUD afterwards
func _fade_to(alpha: float) -> Tween:
	if fade_tween:
		fade_tween.kill()
	fade_tween = create_ui_tween()
	fade_tween.tween_property($CanvasModulate, "color", Color(1.0, 1.0, 1.0, alpha), FADE_DURATION)
	return fade_tween
