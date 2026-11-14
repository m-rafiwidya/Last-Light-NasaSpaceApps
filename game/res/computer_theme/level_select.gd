extends PopupPanel

@export var items: Array[LevelMenuItem]
@export var item_list: ItemList

@export var preview: TextureRect
@export var level_title: RichTextLabel
@export var description: RichTextLabel
var selected_index: int = 0


func _ready() -> void:
	item_list.clear()
	for i in range(len(items)):
		var item: LevelMenuItem = items[i]
		item_list.add_item(item.title, item.thumbnail)
		#item_list.set_item_disabled(i, true) for locked levels
	selected_index = 0
	item_list.select(selected_index)
	show_level_details(selected_index)


func _on_button_pressed() -> void:
	var item: LevelMenuItem = items[selected_index]
	hide()
	SceneLoader.load_scene(item.level_id)


func show_level_details(index: int) -> void:
	var item: LevelMenuItem = items[index]
	preview.texture = item.images[0]
	level_title.text = item.title
	description.text = item.description


func _on_item_list_item_clicked(
	index: int, _at_position: Vector2, _mouse_button_index: int
) -> void:
	selected_index = index
	show_level_details(index)


func _on_close_pressed() -> void:
	hide()


func _on_about_to_popup() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_popup_hide() -> void:
	if GameState.state == GameState.State.IN_GAME:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
