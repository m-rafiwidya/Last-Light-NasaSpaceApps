extends UIScreen

const GREY: Texture2D = preload("res://res/textures/dev/grey.png")
const ORANGE: Texture2D = preload("res://res/textures/dev/orange.png")

# Hardcoded placeholder entries.
const ITEMS: Array[Dictionary] = [
	{
		"title": "Orbital Checkout",
		"thumbnail": GREY,
		"images": [GREY, ORANGE],
		"description":
		"Wow! [color=green]Dummy[/color] [wave amp=10 freq=10]mission![/wave]\n\nLorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
	},
	{
		"title": "Lunar Survey",
		"thumbnail": ORANGE,
		"images": [ORANGE, GREY, ORANGE],
		"description":
		"Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore.",
	},
	{
		"title": "Debris Cleanup",
		"thumbnail": GREY,
		"images": [GREY],
		"description":
		"Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
	},
	{
		"title": "Solar Array Repair",
		"thumbnail": ORANGE,
		"images": [ORANGE, ORANGE],
		"description":
		"Lorem ipsum dolor sit amet, consectetur adipiscing elit. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.",
	},
]

var fade_tween: Tween = null


func _ready() -> void:
	%Window.modulate.a = 0.0
	%Close.pressed.connect(_on_close_pressed)
	%ItemList.item_selected.connect(_show_item)

	%ItemList.clear()
	for item in ITEMS:
		%ItemList.add_item(item.title, item.thumbnail)
	%ItemList.select(0)
	_show_item(0)
	hide()


func _show_item(index: int) -> void:
	var item: Dictionary = ITEMS[index]
	%Title.text = "[b][i]%s[/i][/b]" % item.title
	%Description.text = item.description

	for child in %Attachments.get_children():
		child.queue_free()
	for image in item.images:
		var rect := TextureRect.new()
		rect.texture = image
		rect.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
		%Attachments.add_child(rect)


func _on_close_pressed():
	# The screen stays clickable while fading out, so only react in this state.
	if GameState.state == GameState.State.MISSION_CONSOLE:
		GameState.return_to_game()


func fade_in():
	show()
	_fade_to(1.0)


func fade_out():
	if not visible:
		return
	_fade_to(0.0).tween_callback(hide)


func _fade_to(alpha: float) -> Tween:
	if fade_tween:
		fade_tween.kill()
	fade_tween = create_ui_tween()
	fade_tween.tween_property(%Window, "modulate:a", alpha, FADE_DURATION)
	return fade_tween
